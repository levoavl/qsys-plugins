-- (c) levo AVL | Elias Jenny - MIT License
--
-- Blackmagic ATEM switcher protocol: UDP port 9910, reliable sessions on top of UDP.
-- The protocol is not officially documented. Packet handling follows the
-- reverse-engineered implementation in Sofie ATEM Connection
-- (https://github.com/Sofie-Automation/sofie-atem-connection, MIT License,
-- Copyright (c) 2023 Norsk rikskringkasting AS).
--
-- Packet: 12 byte header + commands
--   0-1   flags (5 bit) << 11 | packet length (11 bit)
--   2-3   session id
--   4-5   acknowledged packet id (AckReply)
--   6-7   retransmit from packet id (RetransmitRequest)
--   10-11 packet id (AckRequest)
-- Command: 2 byte length (incl. 8 byte header), 2 bytes 0, 4 char name, data.
-- Commands never span packets; packets can arrive out of order or twice.

AtemProtocol = {}
local P = AtemProtocol

local byte, char = string.byte, string.char

P.PORT = 9910
P.MAX_PACKET = 1416          -- same as ATEM Software Control
P.MAX_ID = 1 << 15           -- packet ids are 15 bit

P.Flag = { AckRequest = 0x01, Hello = 0x02, Retransmit = 0x04, RetransmitRequest = 0x08, AckReply = 0x10 }

---------------------------------------------------------------------------
-- Binary helpers. Offsets are 0-based like in the protocol notes.
---------------------------------------------------------------------------
function P.U8(s, o) return byte(s, o + 1) or 0 end
function P.U16(s, o)
  local a, b = byte(s, o + 1, o + 2)
  return ((a or 0) << 8) | (b or 0)
end
function P.S16(s, o)
  local v = P.U16(s, o)
  return v >= 0x8000 and v - 0x10000 or v
end
function P.U32(s, o) return (P.U16(s, o) << 16) | P.U16(s, o + 2) end
function P.S32(s, o)
  local v = P.U32(s, o)
  return v >= 0x80000000 and v - 0x100000000 or v
end
function P.Bool(s, o) return P.U8(s, o) ~= 0 end
-- Null-terminated string in a fixed-size field
function P.Str(s, o, len)
  local raw = s:sub(o + 1, o + len)
  local z = raw:find("\0", 1, true)
  return z and raw:sub(1, z - 1) or raw
end

function P.W8(v) return char(math.floor(v) & 0xFF) end
function P.W16(v)
  v = math.floor(v) & 0xFFFF
  return char(v >> 8, v & 0xFF)
end
function P.W32(v)
  v = math.floor(v) & 0xFFFFFFFF
  return char(v >> 24, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF)
end
function P.Pad(n) return string.rep("\0", n) end
-- Fixed-size string field, null padded
function P.WStr(s, len)
  s = (s or ""):sub(1, len)
  return s .. P.Pad(len - #s)
end

function P.Hex(s, max)
  s = max and s:sub(1, max) or s
  return (s:gsub(".", function(c) return ("%02x"):format(byte(c)) end))
end

-- One command, ready to be put into a packet
function P.Command(name, data)
  return P.W16(#data + 8) .. "\0\0" .. name .. data
end

-- Split a packet payload into commands: calls fn(name, data) for each
function P.SplitCommands(payload, fn)
  local pos, n = 0, #payload
  while pos + 8 <= n do
    local len = P.U16(payload, pos)
    if len < 8 or pos + len > n then return false end
    fn(payload:sub(pos + 5, pos + 8), payload:sub(pos + 9, pos + len))
    pos = pos + len
  end
  return true
end

local function Header(flags, length, session, ackId, packetId)
  return P.W16((flags << 11) | length) .. P.W16(session) .. P.W16(ackId or 0)
    .. "\0\0\0\0" .. P.W16(packetId or 0)
end

P.HELLO = Header(P.Flag.Hello, 20, 0x53AB, 0, 0) .. char(0x01) .. P.Pad(7)
-- byte 9 of the hello is 0x3a in the original client; keep it for compatibility
P.HELLO = P.HELLO:sub(1, 9) .. char(0x3a) .. P.HELLO:sub(11)

-- Is packet id `id` covered by an acknowledgement up to `ackId` (with 15 bit wrap)?
function P.Covered(ackId, id)
  local half = P.MAX_ID // 2
  local diff = (ackId - id) % P.MAX_ID
  return diff < half
end

---------------------------------------------------------------------------
-- Session: handshake, acknowledgements, retransmits, ordered delivery.
-- Transport-independent: the owner feeds received datagrams into Receive()
-- and calls Tick(now) regularly; outgoing datagrams go to opts.Transmit.
---------------------------------------------------------------------------
local Session = {}
Session.__index = Session

local HELLO_RETRY = 1.0       -- resend hello while waiting for an answer
local RX_TIMEOUT = 5.0        -- nothing received for this long -> connection lost
local RESEND_AFTER = 0.08     -- unacknowledged packet is resent after this time
local MAX_RESENDS = 10
local MAX_IN_FLIGHT = 16      -- packets waiting for an ack before we hold back
local MAX_OUT_OF_ORDER = 256
local STALL_TIMEOUT = 5.0     -- inbound stuck behind a lost packet for this long

-- opts: Transmit(data), OnConnected(), OnCommand(name, data), OnLost(reason), Log(level, msg)
function P.NewSession(opts)
  local s = setmetatable({ opts = opts }, Session)
  s:Reset()
  s.phase = "closed"
  return s
end

function Session:Reset()
  self.sessionId = 0
  self.nextId = 1
  self.lastRxId = 0
  self.inFlight = {}
  self.outOfOrder, self.outOfOrderCount = {}, 0
  self.stalledSince = nil
  self.queue, self.queueData = {}, {}
  self.lastRx = 0
  self.helloAt = 0
  self.txPackets, self.rxPackets, self.resends = 0, 0, 0
end

function Session:Log(level, msg)
  if self.opts.Log then self.opts.Log(level, msg) end
end

function Session:Raw(data)
  self.txPackets = self.txPackets + 1
  self.opts.Transmit(data)
end

function Session:Connect(now)
  self:Reset()
  self.phase = "hello"
  self.helloAt = now
  self.lastRx = now
  self:Raw(P.HELLO)
end

function Session:Close()
  self.phase = "closed"
  self.queue, self.queueData = {}, {}
  self.inFlight = {}
end

function Session:IsOpen() return self.phase == "open" end

function Session:Lost(reason)
  if self.phase == "closed" then return end
  self:Close()
  self.opts.OnLost(reason)
end

function Session:SendAck(id)
  self:Raw(Header(P.Flag.AckReply, 12, self.sessionId, id, 0))
end

function Session:Deliver(payload)
  if #payload == 0 then return end
  local ok = P.SplitCommands(payload, self.opts.OnCommand)
  if not ok then self:Log(1, "Malformed packet payload: " .. P.Hex(payload, 32)) end
end

function Session:Receive(pkt, now)
  if self.phase == "closed" or #pkt < 12 then return end
  local b0 = P.U8(pkt, 0)
  local flags = b0 >> 3
  local length = P.U16(pkt, 0) & 0x07FF
  if length ~= #pkt then
    self:Log(2, ("Dropped packet: length %d, header says %d"):format(#pkt, length))
    return
  end
  self.rxPackets = self.rxPackets + 1
  self.lastRx = now
  self.sessionId = P.U16(pkt, 2)
  local remoteId = P.U16(pkt, 10)

  if flags & P.Flag.Hello ~= 0 then
    -- hello answer: the switcher accepted us, the state dump follows
    if self.phase == "hello" then
      self.phase = "open"
      self.lastRxId = remoteId
      self.outOfOrder, self.outOfOrderCount = {}, 0
      self:SendAck(remoteId)
      self.opts.OnConnected()
    else
      self:SendAck(remoteId)
    end
    return
  end
  if self.phase ~= "open" then return end

  if flags & P.Flag.RetransmitRequest ~= 0 then
    local from = P.U16(pkt, 6) % P.MAX_ID
    self:Log(2, "Switcher asked for resend from packet " .. from)
    if not self:ResendFrom(from, now) then return end
  end

  if flags & P.Flag.AckRequest ~= 0 and remoteId < P.MAX_ID then
    local distance = (remoteId - self.lastRxId) % P.MAX_ID
    if distance == 1 then
      self.lastRxId = remoteId
      self:Deliver(pkt:sub(13))
      -- buffered packets that are now in sequence
      local nextId = (self.lastRxId + 1) % P.MAX_ID
      local buffered = self.outOfOrder[nextId]
      while buffered and self.phase == "open" do
        self.outOfOrder[nextId] = nil
        self.outOfOrderCount = self.outOfOrderCount - 1
        self.lastRxId = nextId
        self:Deliver(buffered)
        nextId = (nextId + 1) % P.MAX_ID
        buffered = self.outOfOrder[nextId]
      end
      self.stalledSince = self.outOfOrderCount > 0 and now or nil
      if self.phase == "open" then self:SendAck(self.lastRxId) end
    elseif distance > 1 and distance <= MAX_OUT_OF_ORDER then
      if not self.outOfOrder[remoteId] then
        if self.outOfOrderCount == 0 then self.stalledSince = now end
        self.outOfOrder[remoteId] = pkt:sub(13)
        self.outOfOrderCount = self.outOfOrderCount + 1
      end
    elseif P.Covered(self.lastRxId, remoteId) then
      -- a resend of something we already have: our ack got lost
      self:SendAck(self.lastRxId)
    end
  end

  if flags & P.Flag.AckReply ~= 0 then
    local ackId = P.U16(pkt, 4)
    local keep = {}
    for _, p in ipairs(self.inFlight) do
      if not P.Covered(ackId, p.id) then keep[#keep + 1] = p end
    end
    self.inFlight = keep
  end
end

function Session:ResendFrom(from, now)
  local index
  for i, p in ipairs(self.inFlight) do
    if p.id == from then index = i break end
  end
  if not index then
    self:Lost("Switcher asked for a packet that is no longer available")
    return false
  end
  for i = index, #self.inFlight do
    local p = self.inFlight[i]
    p.sentAt, p.resends = now, p.resends + 1
    self.resends = self.resends + 1
    self:Raw(p.data)
  end
  return true
end

-- Queue a command. Commands with the same coalesce key replace each other while
-- they wait (e.g. T-bar moves): only the latest value is sent.
function Session:Queue(cmd, coalesceKey)
  if self.phase ~= "open" then return false end
  if coalesceKey then
    if self.queueData[coalesceKey] == nil then self.queue[#self.queue + 1] = coalesceKey end
    self.queueData[coalesceKey] = cmd
  else
    self.queue[#self.queue + 1] = cmd
  end
  return true
end

function Session:Flush(now)
  while #self.queue > 0 and #self.inFlight < MAX_IN_FLIGHT do
    local payload = {}
    local size = 12
    while #self.queue > 0 do
      local item = self.queue[1]
      local cmd = self.queueData[item] or item
      if size + #cmd > P.MAX_PACKET and size > 12 then break end
      table.remove(self.queue, 1)
      self.queueData[item] = nil
      payload[#payload + 1] = cmd
      size = size + #cmd
    end
    local id = self.nextId
    self.nextId = (self.nextId + 1) % P.MAX_ID
    local data = Header(P.Flag.AckRequest, size, self.sessionId, 0, id) .. table.concat(payload)
    self.inFlight[#self.inFlight + 1] = { id = id, data = data, sentAt = now, resends = 0 }
    self:Raw(data)
  end
end

function Session:Tick(now)
  if self.phase == "hello" then
    if now - self.lastRx > RX_TIMEOUT then
      self:Lost("No answer from switcher")
    elseif now - self.helloAt >= HELLO_RETRY then
      self.helloAt = now
      self:Raw(P.HELLO)
    end
    return
  end
  if self.phase ~= "open" then return end

  if now - self.lastRx > RX_TIMEOUT then
    self:Lost("Switcher stopped responding")
    return
  end
  if self.stalledSince and now - self.stalledSince > STALL_TIMEOUT then
    self:Lost("Inbound stalled waiting for packet " .. ((self.lastRxId + 1) % P.MAX_ID))
    return
  end

  local first = self.inFlight[1]
  if first and now - first.sentAt > RESEND_AFTER then
    if first.resends >= MAX_RESENDS then
      self:Lost("Packet " .. first.id .. " was never acknowledged")
      return
    end
    self:Log(2, "Resending from packet " .. first.id)
    if not self:ResendFrom(first.id, now) then return end
  end

  self:Flush(now)
end
