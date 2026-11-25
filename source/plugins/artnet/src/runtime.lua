-- (c) levo AVL | Elias Jenny - MIT License
-- Runtime: Art-Net send and receive. Runs on the Core or in Emulation mode.

local STATUS = { OK = 0, Compromised = 1, Fault = 2, NotPresent = 3, Missing = 4, Initializing = 5 }
-- worst first, used to combine send and receive states into one Status
local SEVERITY = { [STATUS.Fault] = 5, [STATUS.Missing] = 4, [STATUS.Compromised] = 3,
                   [STATUS.Initializing] = 2, [STATUS.OK] = 1 }
local KEEPALIVE_S = 1.0       -- resend unchanged data so nodes do not time out
local SOCKET_RETRY_S = 5.0
local POLL_INTERVAL_S = 30    -- ArtPoll to learn sender names (receive universes only)
local SOURCE_WINDOW_S = 3     -- a source counts as active this long after its last packet

local DebugLevel = ({ None = 0, Basic = 1, Verbose = 2 })[Properties["Debug Print"].Value] or 0
local function Log(level, msg)
  if level <= DebugLevel then print("[Art-Net] " .. msg) end
end

local function SetStatus(value, text)
  if Controls.Status.Value ~= value then Controls.Status.Value = value end
  if Controls.Status.String ~= (text or "") then Controls.Status.String = text or "" end
end

local function SetString(ctl, s)
  if ctl.String ~= s then ctl.String = s end
end

-- Emulation detection. System.IsEmulating is guarded with pcall in case the API
-- is missing on some firmware; then we assume a real Core.
local Emulating = false
do
  local ok, v = pcall(function() return System.IsEmulating end)
  Emulating = ok and v == true
end

local UniverseCount = ArtNetConfig.Count(Properties)
local HasSend = ArtNetConfig.HasMode(Properties, "Send")
local HasReceive = ArtNetConfig.HasMode(Properties, "Receive")
local RefreshHz = math.max(1, math.min(44, Properties["Refresh Rate (Hz)"].Value))
local Continuous = Properties["Send Mode"].Value == "Continuous"
local DEFAULT_NODE_NAME = "Q-SYS Art-Net"

-- Clock. Timer.Now() is preferred; if it is not available on this firmware the
-- timer's own tick count is used (same approach as the Beat Analyzer).
local TickInterval = 1 / RefreshHz
local TickTime = 0
local ClockSource = "tick counter"
local function Clock() return TickTime end
do
  local ok, v = pcall(function() return Timer.Now() end)
  if ok and type(v) == "number" then
    ClockSource = "Timer.Now"
    Clock = function() return Timer.Now() end
  end
end

-- Keep long-lived objects reachable from a global. A timer or socket that is only
-- held by a local variable gets garbage collected on the Core and silently stops.
ArtNetRuntime = {}

local Socket = nil        -- ephemeral send socket (fallback when 6454 is not ours)
local SocketError = nil
local Discovery = nil     -- socket on UDP 6454: receive, ArtPoll replies, sending
local Universes = {}
local SendUniverses, ReceiveUniverses = {}, {}
local NameByIp = {}       -- sender names learned from ArtPollReply
local OwnIps = {}         -- our own interface addresses (ignore our own packets)

-- --------------------------------------------------------------- helpers
local function Ctl(u, name) return Controls["U" .. u .. " " .. name] end

local function OutputAllowed()
  return not Emulating or Controls["Send in Emulation"].Boolean
end

local function Trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

local function TargetIp(u)
  if Controls.Broadcast.Boolean then return Trim(Controls["Broadcast Address"].String) end
  return Trim(Ctl(u.index, "Target IP").String)
end

local function PortAddressOf(u)
  return ArtNet.PortAddress(Ctl(u.index, "Net").Value, Ctl(u.index, "SubNet").Value, Ctl(u.index, "Universe").Value)
end

local function AddrText(pa)
  return string.format("Port-Address %d (%d:%d:%d)", pa, pa >> 8, (pa >> 4) & 0xF, pa & 0xF)
end

local function SourceName(ip)
  local n = NameByIp[ip]
  return (n and n ~= "") and (ip .. " (" .. n .. ")") or ip
end

local function ActiveSources(u, now)
  local list = {}
  for ip, t in pairs(u.sources) do
    if now - t <= SOURCE_WINDOW_S then table.insert(list, ip) end
  end
  table.sort(list)
  return list
end

-- --------------------------------------------------------------- status
local function SendInfo(u)
  local addr = AddrText(PortAddressOf(u))
  if not Ctl(u.index, "Enable").Boolean then
    return "Output off  ·  " .. addr
  elseif not ArtNet.ValidIp(TargetIp(u)) then
    return "No valid target IP  ·  " .. addr
  elseif not OutputAllowed() then
    return "Emulation, not sending  ·  " .. addr
  end
  return string.format("%s %s  ·  %s  ·  ch %d-%d",
    Controls.Broadcast.Boolean and "Broadcast" or "Unicast", TargetIp(u), addr, u.first, u.last)
end

local function ReceiveInfo(u, now)
  local addr = AddrText(PortAddressOf(u))
  if not Discovery then return "UDP 6454 not available - cannot receive  ·  " .. addr end
  local srcs = ActiveSources(u, now)
  if #srcs == 0 then
    local hold = u.lastRx and (" (" .. (u.lossZero and "zeroed" or "holding") .. ")") or ""
    return "Waiting for data" .. hold .. "  ·  " .. addr .. "  ·  ch " .. u.first .. "-" .. u.last
  end
  local names = {}
  for _, ip in ipairs(srcs) do table.insert(names, SourceName(ip)) end
  return string.format("From %s  ·  %d pkt/s  ·  %s", table.concat(names, " + "), u.rate, addr)
end

local function UpdateStatus()
  local now = Clock()
  local worst, text = STATUS.OK, nil
  local function Raise(st, t)
    if SEVERITY[st] > SEVERITY[worst] or text == nil then worst, text = st, t end
  end

  for _, u in ipairs(Universes) do
    SetString(Ctl(u.index, "Info"), u.receive and ReceiveInfo(u, now) or SendInfo(u))
  end

  -- send side
  if HasSend then
    if SocketError and not Discovery then
      Raise(STATUS.Fault, "UDP socket: " .. SocketError)
    else
      local enabled, bad = 0, {}
      for _, u in ipairs(SendUniverses) do
        if Ctl(u.index, "Enable").Boolean then
          enabled = enabled + 1
          if not ArtNet.ValidIp(TargetIp(u)) then table.insert(bad, "U" .. u.index) end
        end
      end
      if #bad > 0 then
        Raise(STATUS.Fault, "Invalid target IP: " .. table.concat(bad, ", "))
      elseif enabled == 0 then
        Raise(HasReceive and STATUS.OK or STATUS.Missing, "No send universe enabled")
      elseif not OutputAllowed() then
        Raise(STATUS.Compromised, "Emulation - output disabled (Setup: Emulation TX)")
      elseif Controls.Blackout.Boolean then
        Raise(STATUS.Compromised, "Blackout active")
      else
        Raise(STATUS.OK, string.format("Sending %d universe(s)", enabled))
      end
    end
  end

  -- receive side
  if HasReceive then
    if not Discovery then
      Raise(STATUS.Fault, "UDP 6454 not available - cannot receive")
    else
      local waiting, multi, ok = {}, {}, 0
      for _, u in ipairs(ReceiveUniverses) do
        local n = #ActiveSources(u, now)
        if n == 0 then table.insert(waiting, "U" .. u.index)
        elseif n > 1 then table.insert(multi, "U" .. u.index)
        else ok = ok + 1 end
      end
      if #waiting > 0 then
        Raise(STATUS.Missing, "No data on " .. table.concat(waiting, ", "))
      elseif #multi > 0 then
        Raise(STATUS.Compromised, "Several sources on " .. table.concat(multi, ", ") .. " - latest wins")
      else
        Raise(STATUS.OK, string.format("Receiving %d universe(s)", ok))
      end
    end
  end

  -- with send and receive both fine, say both
  if worst == STATUS.OK and HasSend and HasReceive then
    local s, r = 0, 0
    for _, u in ipairs(SendUniverses) do if Ctl(u.index, "Enable").Boolean then s = s + 1 end end
    for _, u in ipairs(ReceiveUniverses) do if #ActiveSources(u, now) > 0 then r = r + 1 end end
    text = string.format("Sending %d, receiving %d universe(s)", s, r)
  end
  SetStatus(worst, text or "OK")
end

-- --------------------------------------------------------------- interfaces
local function IpNum(ip)
  local a, b, c, d = tostring(ip or ""):match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
  return a and ((tonumber(a) << 24) | (tonumber(b) << 16) | (tonumber(c) << 8) | tonumber(d)) or nil
end
local function IpStr(n)
  return string.format("%d.%d.%d.%d", (n >> 24) & 0xFF, (n >> 16) & 0xFF, (n >> 8) & 0xFF, n & 0xFF)
end

local function Interfaces()
  local ok, ifs = pcall(function() return Network.Interfaces() end)
  if not ok or type(ifs) ~= "table" then return {} end
  local list = {}
  for _, i in pairs(ifs) do
    local addr, mask = i.Address or i.IP, i.Netmask or i.NetMask
    local a, m = IpNum(addr), IpNum(mask)
    if a then
      table.insert(list, { ip = addr, num = a, mask = m, mac = i.MACAddress or i.MacAddress or i.MAC,
        broadcast = m and IpStr((a & m) | (~m & 0xFFFFFFFF)) or nil })
    end
  end
  return list
end

-- interface in the remote's subnet (first interface otherwise)
local function LocalInterfaceFor(remote)
  local list, r = Interfaces(), IpNum(remote)
  for _, i in ipairs(list) do
    if i.mask and r and (i.num & i.mask) == (r & i.mask) then return i end
  end
  return list[1] or { ip = "0.0.0.0" }
end

for _, i in ipairs(Interfaces()) do OwnIps[i.ip] = true end

-- --------------------------------------------------------------- sending
local function OpenSocket()
  local s = UdpSocket.New()
  local ok, err = pcall(function() s:Open() end)
  if ok then
    Socket, SocketError = s, nil
    ArtNetRuntime.Socket = s
    Log(1, "UDP send socket open" .. (Emulating and " (Emulation)" or ""))
  else
    Socket, SocketError = nil, tostring(err)
    Log(1, "UDP socket open failed: " .. SocketError)
  end
end

local SentCount, LastSendError = 0, nil

local function Send(u, now)
  local ip = TargetIp(u)
  if not ArtNet.ValidIp(ip) then return end
  -- Send from UDP 6454 when we own it (Art-Net source port; receivers then list
  -- DMX source and ArtPollReply node as one device), else from the send socket.
  local sock = Discovery or Socket
  if not sock then return end
  u.sequence = (u.sequence % 255) + 1  -- 1..255, 0 would disable sequencing
  local packet = ArtNet.Dmx(u.sequence, PortAddressOf(u), (not Controls.Blackout.Boolean) and u.slots or nil)
  local ok, err = pcall(function() sock:Send(ip, ArtNet.PORT, packet) end)
  if not ok then
    if LastSendError ~= tostring(err) then
      LastSendError = tostring(err)
      Log(1, string.format("U%d send to %s failed: %s", u.index, ip, LastSendError))
      SetStatus(STATUS.Fault, "Send failed: " .. LastSendError)
    end
  else
    SentCount = SentCount + 1
    if SentCount == 1 then Log(1, string.format("First packet sent: U%d -> %s:%d", u.index, ip, ArtNet.PORT)) end
    Log(2, string.format("U%d -> %s seq %d", u.index, ip, u.sequence))
    if LastSendError then LastSendError = nil; UpdateStatus() end
  end
  u.dirty, u.lastSent = false, now
end

-- --------------------------------------------------------------- receiving
local function LossBehaviourZero(u)
  return Ctl(u.index, "On Loss").String == "Zero"
end

local function ApplyIncoming(u, dmx)
  for ch = u.first, u.last do
    local v = dmx:byte(ch) or 0       -- shorter packets: missing slots are 0
    if u.values[ch] ~= v then
      u.values[ch] = v
      Ctl(u.index, "Ch " .. ch).Value = v
    end
  end
end

local function OnDmx(sender, data, now)
  if OwnIps[sender] then return end
  local seq, pa, dmx = ArtNet.ParseDmx(data)
  if not seq then return end
  for _, u in ipairs(ReceiveUniverses) do
    if PortAddressOf(u) == pa then
      local filter = Trim(Ctl(u.index, "Source Filter").String)
      if filter == "" or filter == sender then
        if not u.lastRx or now - u.lastRx > Ctl(u.index, "Timeout").Value then
          Log(1, string.format("U%d receiving from %s", u.index, SourceName(sender)))
          u.dirtyStatus = true
        end
        if not u.sources[sender] or now - u.sources[sender] > SOURCE_WINDOW_S then u.dirtyStatus = true end
        u.sources[sender] = now
        u.lastRx, u.lossZero = now, false
        u.packets = u.packets + 1
        ApplyIncoming(u, dmx)
        if not Ctl(u.index, "Data").Boolean then Ctl(u.index, "Data").Boolean = true end
        Log(2, string.format("U%d <- %s seq %d len %d", u.index, sender, seq, #dmx))
      end
    end
  end
end

local function CheckReceiveTimeouts(now)
  local changed = false
  for _, u in ipairs(ReceiveUniverses) do
    local timeout = math.max(1, Ctl(u.index, "Timeout").Value)
    if u.lastRx and Ctl(u.index, "Data").Boolean and now - u.lastRx > timeout then
      Ctl(u.index, "Data").Boolean = false
      Log(1, string.format("U%d: no data for %ds (%s)", u.index, timeout, LossBehaviourZero(u) and "zero" or "hold"))
      if LossBehaviourZero(u) then
        ApplyIncoming(u, "")
        u.lossZero = true
      end
      changed = true
    end
    if u.dirtyStatus then u.dirtyStatus = false; changed = true end
  end
  return changed
end

-- --------------------------------------------------------------- discovery
-- Socket on UDP 6454: receives ArtDmx for receive universes, answers ArtPoll with
-- one ArtPollReply per universe (node name) and learns sender names from replies.
local function NodeName()
  local n = Trim(Controls["Node Name"].String)
  return n ~= "" and n or DEFAULT_NODE_NAME
end

local function DesignName()
  local ok, st = pcall(function() return Design.GetStatus() end)
  return ok and type(st) == "table" and st.DesignName or nil
end

local PollReplies = 0

local function SendPollReplies(iface, targets)
  local design = DesignName()
  local long = NodeName() .. " - levo AVL Art-Net " .. PluginInfo.BuildVersion .. (design and (" - " .. design) or "")
  local major, minor = PluginInfo.Version:match("^(%d+)%.(%d+)")
  local now = Clock()
  for _, u in ipairs(Universes) do
    local active
    if u.receive then active = #ActiveSources(u, now) > 0
    else active = Ctl(u.index, "Enable").Boolean and OutputAllowed() end
    local pkt = ArtNet.PollReply({
      ip = iface.ip, mac = iface.mac, output = u.receive, shortName = NodeName(), longName = long,
      report = string.format("#0001 [%04d] %s", PollReplies % 10000, active and "Active" or "Idle"),
      portAddress = PortAddressOf(u), bindIndex = u.index, active = active,
      versionMajor = tonumber(major) or 0, versionMinor = tonumber(minor) or 0,
    })
    for _, t in ipairs(targets) do
      pcall(function() Discovery:Send(t, ArtNet.PORT, pkt) end)
    end
  end
  PollReplies = PollReplies + 1
end

-- reply unicast to the poller (Art-Net 4) and to the subnet broadcast (Art-Net 3)
local function ReplyToPoll(sender)
  local iface = LocalInterfaceFor(sender)
  local targets = { sender }
  if iface.broadcast then table.insert(targets, iface.broadcast) end
  SendPollReplies(iface, targets)
  Log(2, string.format("ArtPoll from %s, replied as %s (%s, mac %s) to %s", sender, NodeName(), iface.ip,
    tostring(iface.mac), table.concat(targets, " + ")))
end

-- unsolicited reply at start-up and on name change
local function AnnounceNode(reason)
  if not Discovery or not OutputAllowed() then return end
  local iface = LocalInterfaceFor(nil)
  if not iface.broadcast then return end
  SendPollReplies(iface, { iface.broadcast })
  Log(1, string.format("Announced as %s to %s (%s)", NodeName(), iface.broadcast, reason))
end

-- ArtPoll so senders tell us their names (receive universes only)
local LastPoll = -math.huge
local function PollForNames(now)
  if not Discovery or not HasReceive or not OutputAllowed() then return end
  if now - LastPoll < POLL_INTERVAL_S then return end
  LastPoll = now
  for _, i in ipairs(Interfaces()) do
    if i.broadcast then pcall(function() Discovery:Send(i.broadcast, ArtNet.PORT, ArtNet.Poll()) end) end
  end
end

local function OnPacket(sock, packet)
  local data, sender = packet.Data, packet.Address
  local op = ArtNet.OpCode(data)
  if op == ArtNet.OP_DMX then
    if HasReceive then OnDmx(sender, data, Clock()) end
  elseif op == ArtNet.OP_POLL then
    if not OwnIps[sender] and OutputAllowed() then ReplyToPoll(sender) end
  elseif op == ArtNet.OP_POLL_REPLY then
    local ip, short = ArtNet.ParsePollReply(data)
    if ip and not OwnIps[ip] and short and short ~= "" and NameByIp[ip] ~= short then
      NameByIp[ip] = short
      Log(1, string.format("Node %s is \"%s\"", ip, short))
    end
  end
end

local function OpenDiscovery()
  local s = UdpSocket.New()
  s.EventHandler = OnPacket
  -- The exact UdpSocket:Open signature for binding a port is not fully documented;
  -- try the variants in order and keep the first that works.
  local variants = {
    function() s:Open(nil, ArtNet.PORT) end,
    function() s:Open("", ArtNet.PORT) end,
    function() s:Open("0.0.0.0", ArtNet.PORT) end,
  }
  local lastErr
  for i, open in ipairs(variants) do
    local ok, err = pcall(open)
    if ok then
      Discovery = s
      ArtNetRuntime.Discovery = s
      SetString(Controls.Discovery, "UDP " .. ArtNet.PORT .. " active (receive, ArtPoll)")
      Log(1, string.format("Listening on UDP %d (variant %d)", ArtNet.PORT, i))
      return
    end
    lastErr = tostring(err)
  end
  SetString(Controls.Discovery, "UDP " .. ArtNet.PORT .. " not available (in use?)")
  Log(1, "UDP " .. ArtNet.PORT .. " not available: " .. (lastErr or "?"))
end

-- --------------------------------------------------------------- universes
local function MarkAllDirty()
  for _, u in ipairs(SendUniverses) do u.dirty = true end
end

for n = 1, UniverseCount do
  local cfg = ArtNetConfig.Universe(Properties, n)
  local u = { index = n, receive = cfg.mode == "Receive", first = cfg.first, last = cfg.last,
              slots = {}, values = {}, dirty = true, lastSent = -math.huge, sequence = 0,
              sources = {}, packets = 0, rate = 0 }
  for _, name in ipairs({ "Net", "SubNet", "Universe" }) do
    Ctl(n, name).EventHandler = function() u.dirty = true; UpdateStatus() end
  end

  if u.receive then
    local loss = Ctl(n, "On Loss")
    loss.Choices = { "Hold", "Zero" }
    if loss.String ~= "Zero" then loss.String = "Hold" end
    if Ctl(n, "Timeout").Value < 1 then Ctl(n, "Timeout").Value = 3 end
    Ctl(n, "Data").Boolean = false
    for ch = u.first, u.last do u.values[ch] = math.floor(Ctl(n, "Ch " .. ch).Value + 0.5) end
    Ctl(n, "Source Filter").EventHandler = function() u.sources = {}; UpdateStatus() end
    loss.EventHandler = function() UpdateStatus() end
    Ctl(n, "Timeout").EventHandler = function() UpdateStatus() end
    table.insert(ReceiveUniverses, u)
  else
    -- full 512-slot buffer, everything outside the channel range stays 0
    for i = 1, ArtNet.SLOTS do u.slots[i] = 0 end
    for ch = u.first, u.last do
      local c = Ctl(n, "Ch " .. ch)
      u.slots[ch] = ArtNet.Clamp(c.Value, 0, 255)
      c.EventHandler = function(ctl)
        u.slots[ch] = ArtNet.Clamp(ctl.Value, 0, 255)
        u.dirty = true
      end
    end
    for _, name in ipairs({ "Target IP", "Enable" }) do
      Ctl(n, name).EventHandler = function()
        u.dirty = true
        if name == "Enable" then
          Log(1, string.format("U%d output %s", n, Ctl(n, "Enable").Boolean and "on" or "off"))
        end
        UpdateStatus()
      end
    end
    table.insert(SendUniverses, u)
  end
  Universes[n] = u
end
ArtNetRuntime.Universes = Universes

for _, name in ipairs({ "Broadcast", "Broadcast Address", "Blackout", "Send in Emulation" }) do
  Controls[name].EventHandler = function()
    MarkAllDirty()
    UpdateStatus()
  end
end

Controls["Node Name"].EventHandler = function()
  Log(1, "Node name: " .. NodeName())
  AnnounceNode("name changed")
end

-- --------------------------------------------------------------- main loop
local RetryAt = 0
local NextSecond = 0
local Tick = Timer.New()
ArtNetRuntime.Tick = Tick
Tick.EventHandler = function()
  TickTime = TickTime + TickInterval
  local now = Clock()

  -- once per second: receive rates, status refresh, socket retry, name polling
  if now >= NextSecond then
    NextSecond = now + 1
    for _, u in ipairs(ReceiveUniverses) do u.rate, u.packets = u.packets, 0 end
    if HasSend and not Socket and not Discovery and now >= RetryAt then
      RetryAt = now + SOCKET_RETRY_S
      OpenSocket()
    end
    PollForNames(now)
    CheckReceiveTimeouts(now)
    UpdateStatus()
  elseif HasReceive and CheckReceiveTimeouts(now) then
    UpdateStatus()
  end

  if not HasSend or not OutputAllowed() then return end
  if not (Discovery or Socket) then return end
  for _, u in ipairs(SendUniverses) do
    if Ctl(u.index, "Enable").Boolean and (Continuous or u.dirty or now - u.lastSent >= KEEPALIVE_S) then
      Send(u, now)
    end
  end
end

-- --------------------------------------------------------------- start
SetStatus(STATUS.Initializing, "Starting")
if Controls["Broadcast Address"].String == "" then
  Controls["Broadcast Address"].String = "255.255.255.255"
end
if Controls["Node Name"].String == "" then
  Controls["Node Name"].String = DEFAULT_NODE_NAME
end
Log(1, string.format("Started: %d universe(s) (%d send, %d receive), %d Hz, %s, emulation %s, clock %s, build %s",
  UniverseCount, #SendUniverses, #ReceiveUniverses, RefreshHz, Continuous and "continuous" or "on change",
  tostring(Emulating), ClockSource, PluginInfo.BuildVersion))
-- start the timer first, so a problem further down can never stop output
Tick:Start(TickInterval)
OpenDiscovery()
if HasSend and not Discovery then OpenSocket() end
RetryAt = Clock() + SOCKET_RETRY_S
AnnounceNode("start-up")
UpdateStatus()
