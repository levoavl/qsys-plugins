-- (c) levo AVL | Elias Jenny - MIT License
--
-- Minimal WebSocket client (RFC 6455) on top of the Q-SYS TcpSocket.
-- Text frames only, client-to-server frames are masked, fragmented messages and
-- frames split across TCP packets are reassembled. Ping is answered with pong.
--
-- Usage:
--   local ws = LevoWebSocket.New({
--     OnOpen    = function() end,
--     OnMessage = function(text) end,
--     OnClose   = function(reason) end,   -- socket closed, error or timeout
--     Log       = function(level, msg) end, -- optional, level 1 basic / 2 verbose
--   })
--   ws:Connect("192.168.1.10", 80, "/?ma=1")
--   ws:Send('{"session":0}')
--   ws:Close()
--
-- Reconnecting is left to the caller (OnClose), so it can apply its own backoff.

LevoWebSocket = {}

local OP_CONT, OP_TEXT, OP_BIN, OP_CLOSE, OP_PING, OP_PONG = 0x0, 0x1, 0x2, 0x8, 0x9, 0xA
LevoWebSocket.Opcodes = { Cont = OP_CONT, Text = OP_TEXT, Binary = OP_BIN, Close = OP_CLOSE, Ping = OP_PING, Pong = OP_PONG }

local function RandomBytes(n)
  local t = {}
  for i = 1, n do t[i] = string.char(math.random(0, 255)) end
  return table.concat(t)
end

-- Big-endian unsigned integer of `n` bytes as string
local function UInt(value, n)
  local t = {}
  for i = n, 1, -1 do
    t[i] = string.char(value % 256)
    value = value // 256
  end
  return table.concat(t)
end

-- Encode one (final) frame. `maskKey` is a 4-byte string, nil = unmasked.
function LevoWebSocket.EncodeFrame(opcode, payload, maskKey)
  payload = payload or ""
  local len = #payload
  local maskBit = maskKey and 0x80 or 0
  local head = string.char(0x80 | opcode)
  if len <= 125 then
    head = head .. string.char(maskBit | len)
  elseif len <= 0xFFFF then
    head = head .. string.char(maskBit | 126) .. UInt(len, 2)
  else
    head = head .. string.char(maskBit | 127) .. UInt(len, 8)
  end
  if not maskKey then return head .. payload end
  local k = { maskKey:byte(1, 4) }
  local out, chunk = {}, {}
  for i = 1, len do
    chunk[#chunk + 1] = string.char(payload:byte(i) ~ k[(i - 1) % 4 + 1])
    if #chunk == 4096 then out[#out + 1] = table.concat(chunk); chunk = {} end
  end
  out[#out + 1] = table.concat(chunk)
  return head .. maskKey .. table.concat(out)
end

-- Parse as many complete frames as possible from `buf`.
-- Returns a list of { fin, opcode, payload } and the unconsumed remainder.
function LevoWebSocket.ParseFrames(buf)
  local frames, pos, size = {}, 1, #buf
  while true do
    if size - pos + 1 < 2 then break end
    local b1, b2 = buf:byte(pos, pos + 1)
    local fin = (b1 & 0x80) ~= 0
    local opcode = b1 & 0x0F
    local masked = (b2 & 0x80) ~= 0
    local len = b2 & 0x7F
    local hdr = 2
    if len == 126 then
      if size - pos + 1 < 4 then break end
      local x1, x2 = buf:byte(pos + 2, pos + 3)
      len = x1 * 256 + x2
      hdr = 4
    elseif len == 127 then
      if size - pos + 1 < 10 then break end
      len = 0
      for i = 2, 9 do len = len * 256 + buf:byte(pos + i) end
      hdr = 10
    end
    local maskKey
    if masked then
      if size - pos + 1 < hdr + 4 then break end
      maskKey = { buf:byte(pos + hdr, pos + hdr + 3) }
      hdr = hdr + 4
    end
    if size - pos + 1 < hdr + len then break end
    local payload = buf:sub(pos + hdr, pos + hdr + len - 1)
    if maskKey then
      local t = {}
      for i = 1, #payload do t[i] = string.char(payload:byte(i) ~ maskKey[(i - 1) % 4 + 1]) end
      payload = table.concat(t)
    end
    frames[#frames + 1] = { fin = fin, opcode = opcode, payload = payload }
    pos = pos + hdr + len
  end
  return frames, buf:sub(pos)
end

function LevoWebSocket.New(handlers)
  local self = {
    handlers = handlers or {},
    sock = nil,
    state = "closed",   -- closed | connecting | handshake | open
    buffer = "",
    fragments = nil,
    host = nil,
  }

  local function Log(level, msg)
    if self.handlers.Log then self.handlers.Log(level, msg) end
  end

  local function Fire(name, ...)
    local fn = self.handlers[name]
    if fn then
      local ok, err = pcall(fn, ...)
      if not ok then Log(1, "WebSocket " .. name .. " handler error: " .. tostring(err)) end
    end
  end

  local function Shutdown(reason)
    if self.state == "closed" then return end
    self.state = "closed"
    self.buffer, self.fragments = "", nil
    if self.sock then
      local s = self.sock
      self.sock = nil  -- the event handler ignores events from sockets other than self.sock
      pcall(function() s:Disconnect() end)
    end
    Fire("OnClose", reason)
  end

  local function WriteFrame(opcode, payload)
    if not self.sock or self.state ~= "open" then return false end
    self.sock:Write(LevoWebSocket.EncodeFrame(opcode, payload, RandomBytes(4)))
    return true
  end

  local function HandleFrames()
    local frames
    frames, self.buffer = LevoWebSocket.ParseFrames(self.buffer)
    for _, f in ipairs(frames) do
      if f.opcode == OP_PING then
        WriteFrame(OP_PONG, f.payload)
      elseif f.opcode == OP_PONG then
        -- ignore
      elseif f.opcode == OP_CLOSE then
        Log(1, "WebSocket closed by server")
        Shutdown("closed by server")
        return
      elseif f.opcode == OP_TEXT or f.opcode == OP_BIN then
        if f.fin then
          Fire("OnMessage", f.payload)
        else
          self.fragments = { f.payload }
        end
      elseif f.opcode == OP_CONT and self.fragments then
        self.fragments[#self.fragments + 1] = f.payload
        if f.fin then
          local msg = table.concat(self.fragments)
          self.fragments = nil
          Fire("OnMessage", msg)
        end
      end
      if self.state ~= "open" then return end
    end
  end

  local function OnData(sock)
    local n = sock.BufferLength
    if n and n > 0 then
      self.buffer = self.buffer .. (sock:Read(n) or "")
    end
    if self.state == "handshake" then
      local hEnd = self.buffer:find("\r\n\r\n", 1, true)
      if not hEnd then
        if #self.buffer > 16384 then Shutdown("invalid handshake response") end
        return
      end
      local header = self.buffer:sub(1, hEnd - 1)
      self.buffer = self.buffer:sub(hEnd + 4)
      local code = header:match("^HTTP/%d%.%d (%d+)")
      if code ~= "101" then
        Log(1, "WebSocket handshake failed: " .. (header:match("^[^\r\n]*") or "?"))
        Shutdown("handshake failed (HTTP " .. tostring(code) .. ")")
        return
      end
      self.state = "open"
      Log(2, "WebSocket open")
      Fire("OnOpen")
      if self.state ~= "open" then return end
    end
    if self.state == "open" then HandleFrames() end
  end

  function self:Connect(host, port, path)
    Shutdown(nil)  -- silently drop a previous connection (no OnClose when already closed)
    self.host, self.state, self.buffer = host, "connecting", ""
    local sock = TcpSocket.New()
    sock.ReadTimeout = 0
    sock.WriteTimeout = 0
    sock.ReconnectTimeout = 0  -- reconnect is handled by the caller
    self.sock = sock
    sock.EventHandler = function(s, evt, err)
      if self.sock ~= s then return end  -- stale socket
      if evt == TcpSocket.Events.Connected then
        self.state = "handshake"
        Log(2, "TCP connected, sending WebSocket upgrade")
        s:Write(table.concat({
          "GET " .. (path or "/") .. " HTTP/1.1",
          "Host: " .. host .. ":" .. tostring(port),
          "Connection: Upgrade",
          "Upgrade: websocket",
          "Sec-WebSocket-Version: 13",
          "Sec-WebSocket-Key: " .. Crypto.Base64Encode(RandomBytes(16)),
          "", "",
        }, "\r\n"))
      elseif evt == TcpSocket.Events.Data then
        OnData(s)
      elseif evt == TcpSocket.Events.Closed then
        Shutdown("connection closed")
      elseif evt == TcpSocket.Events.Error then
        Shutdown("socket error: " .. tostring(err))
      elseif evt == TcpSocket.Events.Timeout then
        Shutdown("socket timeout")
      end
    end
    Log(2, ("TCP connecting to %s:%d"):format(host, port))
    sock:Connect(host, port)
  end

  function self:Send(text)
    return WriteFrame(OP_TEXT, text)
  end

  function self:IsOpen()
    return self.state == "open"
  end

  -- Close without firing OnClose (deliberate disconnect by the caller)
  function self:Close()
    if self.state == "open" then pcall(WriteFrame, OP_CLOSE, "") end
    local h = self.handlers.OnClose
    self.handlers.OnClose = nil
    Shutdown("closed by client")
    self.handlers.OnClose = h
  end

  return self
end
