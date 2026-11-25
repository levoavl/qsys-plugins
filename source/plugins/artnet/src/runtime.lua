-- (c) levo AVL | Elias Jenny - MIT License
-- Runtime: Art-Net sender. Runs on the Core or in Emulation mode.

local STATUS = { OK = 0, Compromised = 1, Fault = 2, NotPresent = 3, Missing = 4, Initializing = 5 }
local KEEPALIVE_S = 1.0       -- resend unchanged data so nodes do not time out
local SOCKET_RETRY_S = 5.0

local DebugLevel = ({ None = 0, Basic = 1, Verbose = 2 })[Properties["Debug Print"].Value] or 0
local function Log(level, msg)
  if level <= DebugLevel then print("[Art-Net] " .. msg) end
end

local function SetStatus(value, text)
  Controls.Status.Value = value
  Controls.Status.String = text or ""
end

-- Emulation detection. System.IsEmulating is guarded with pcall in case the API
-- is missing on some firmware; then we assume a real Core.
local Emulating = false
do
  local ok, v = pcall(function() return System.IsEmulating end)
  Emulating = ok and v == true
end

local UniverseCount = Properties["Universe Count"].Value
local RefreshHz = math.max(1, math.min(44, Properties["Refresh Rate (Hz)"].Value))
local Continuous = Properties["Send Mode"].Value == "Continuous"
local DEFAULT_NODE_NAME = "Q-SYS Art-Net"

-- Clock. Timer.Now() is preferred; if it is not available on this firmware the
-- send timer's own tick count is used (same approach as the Beat Analyzer).
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

local Socket = nil        -- UdpSocket once opened
local SocketError = nil   -- last open error, nil when fine
local Universes = {}

-- --------------------------------------------------------------- helpers
local function Ctl(u, name) return Controls["U" .. u .. " " .. name] end

local function OutputAllowed()
  return not Emulating or Controls["Send in Emulation"].Boolean
end

local function TargetIp(u)
  if Controls.Broadcast.Boolean then return (Controls["Broadcast Address"].String:gsub("%s", "")) end
  return (Ctl(u.index, "Target IP").String:gsub("%s", ""))
end

local function PortAddressOf(u)
  return ArtNet.PortAddress(Ctl(u.index, "Net").Value, Ctl(u.index, "SubNet").Value, Ctl(u.index, "Universe").Value)
end

local function UpdateInfo(u)
  local pa = PortAddressOf(u)
  local addr = string.format("Port-Address %d (%d:%d:%d)", pa, pa >> 8, (pa >> 4) & 0xF, pa & 0xF)
  local text
  if not Ctl(u.index, "Enable").Boolean then
    text = "Output off  ·  " .. addr
  elseif not ArtNet.ValidIp(TargetIp(u)) then
    text = "No valid target IP  ·  " .. addr
  elseif not OutputAllowed() then
    text = "Emulation, not sending  ·  " .. addr
  else
    text = string.format("%s %s  ·  %s  ·  %d ch",
      Controls.Broadcast.Boolean and "Broadcast" or "Unicast", TargetIp(u), addr, u.channels)
  end
  Ctl(u.index, "Info").String = text
end

local function UpdateStatus()
  for _, u in ipairs(Universes) do UpdateInfo(u) end

  if SocketError then
    return SetStatus(STATUS.Fault, "UDP socket: " .. SocketError)
  end
  local enabled, bad = 0, {}
  for _, u in ipairs(Universes) do
    if Ctl(u.index, "Enable").Boolean then
      enabled = enabled + 1
      if not ArtNet.ValidIp(TargetIp(u)) then table.insert(bad, "U" .. u.index) end
    end
  end
  if enabled == 0 then
    SetStatus(STATUS.Missing, "No universe enabled")
  elseif #bad > 0 then
    SetStatus(STATUS.Fault, "Invalid target IP: " .. table.concat(bad, ", "))
  elseif not OutputAllowed() then
    SetStatus(STATUS.Compromised, "Emulation - output disabled (Setup: Emulation TX)")
  elseif Controls.Blackout.Boolean then
    SetStatus(STATUS.Compromised, "Blackout active")
  else
    SetStatus(STATUS.OK, string.format("Sending %d universe(s)", enabled))
  end
end

-- --------------------------------------------------------------- socket
local function OpenSocket()
  local s = UdpSocket.New()
  local ok, err = pcall(function() s:Open() end)
  if ok then
    Socket, SocketError = s, nil
    if ArtNetRuntime then ArtNetRuntime.Socket = s end
    Log(1, "UDP socket open" .. (Emulating and " (Emulation)" or ""))
  else
    Socket, SocketError = nil, tostring(err)
    Log(1, "UDP socket open failed: " .. SocketError)
  end
  UpdateStatus()
end

local SentCount, SendErrors, LastSendError = 0, 0, nil

local function Send(u, now)
  local ip = TargetIp(u)
  if not ArtNet.ValidIp(ip) then return end
  u.sequence = (u.sequence % 255) + 1  -- 1..255, 0 would disable sequencing
  local packet = ArtNet.Dmx(u.sequence, PortAddressOf(u), (not Controls.Blackout.Boolean) and u.slots or nil)
  local ok, err = pcall(function() Socket:Send(ip, ArtNet.PORT, packet) end)
  if not ok then
    SendErrors = SendErrors + 1
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

-- --------------------------------------------------------------- universes
local function MarkAllDirty()
  for _, u in ipairs(Universes) do u.dirty = true end
end

for n = 1, UniverseCount do
  local u = { index = n, channels = Properties["Channels U" .. n].Value,
              slots = {}, dirty = true, lastSent = -math.huge, sequence = 0 }
  -- full 512-slot buffer, everything beyond the channel count stays 0
  for i = 1, ArtNet.SLOTS do u.slots[i] = 0 end
  for ch = 1, u.channels do
    local c = Ctl(n, "Ch " .. ch)
    u.slots[ch] = ArtNet.Clamp(c.Value, 0, 255)
    c.EventHandler = function(ctl)
      u.slots[ch] = ArtNet.Clamp(ctl.Value, 0, 255)
      u.dirty = true
    end
  end
  for _, name in ipairs({ "Target IP", "Net", "SubNet", "Universe", "Enable" }) do
    Ctl(n, name).EventHandler = function()
      u.dirty = true
      if name == "Enable" then
        Log(1, string.format("U%d output %s", n, Ctl(n, "Enable").Boolean and "on" or "off"))
      end
      UpdateStatus()
    end
  end
  Universes[n] = u
end

for _, name in ipairs({ "Broadcast", "Broadcast Address", "Blackout", "Send in Emulation" }) do
  Controls[name].EventHandler = function()
    MarkAllDirty()
    UpdateStatus()
  end
end

-- --------------------------------------------------------------- discovery
-- Answers ArtPoll on UDP 6454 with one ArtPollReply per universe, so tools like
-- ArtNetominator or Resolume show the node name. Needs port 6454 on the Core; if
-- it cannot be bound, sending works as before and Discovery says so.
local Discovery = nil

local function NodeName()
  local n = Controls["Node Name"].String:gsub("^%s+", ""):gsub("%s+$", "")
  return n ~= "" and n or DEFAULT_NODE_NAME
end

local function DesignName()
  local ok, st = pcall(function() return Design.GetStatus() end)
  return ok and type(st) == "table" and st.DesignName or nil
end

-- Local interface in the poller's subnet (first interface otherwise):
-- address, directed broadcast address, MAC
local function IpNum(ip)
  local a, b, c, d = tostring(ip or ""):match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
  return a and ((tonumber(a) << 24) | (tonumber(b) << 16) | (tonumber(c) << 8) | tonumber(d)) or nil
end
local function IpStr(n)
  return string.format("%d.%d.%d.%d", (n >> 24) & 0xFF, (n >> 16) & 0xFF, (n >> 8) & 0xFF, n & 0xFF)
end

local function LocalInterfaceFor(remote)
  local ok, ifs = pcall(function() return Network.Interfaces() end)
  if not ok or type(ifs) ~= "table" then return { ip = "0.0.0.0" } end
  local first = nil
  for _, i in pairs(ifs) do
    local addr, mask = i.Address or i.IP, i.Netmask or i.NetMask
    local a, m = IpNum(addr), IpNum(mask)
    if a then
      local info = { ip = addr, mac = i.MACAddress or i.MacAddress or i.MAC,
                     broadcast = m and IpStr((a & m) | (~m & 0xFFFFFFFF)) or nil }
      first = first or info
      if m and IpNum(remote) and (a & m) == (IpNum(remote) & m) then return info end
    end
  end
  return first or { ip = "0.0.0.0" }
end

local PollReplies = 0

-- Sends one ArtPollReply per universe to `targets` (list of IPs)
local function SendPollReplies(iface, targets)
  local design = DesignName()
  local long = NodeName() .. " - levo AVL Art-Net " .. PluginInfo.BuildVersion .. (design and (" - " .. design) or "")
  local major, minor = PluginInfo.Version:match("^(%d+)%.(%d+)")
  for _, u in ipairs(Universes) do
    local active = Ctl(u.index, "Enable").Boolean and OutputAllowed()
    local pkt = ArtNet.PollReply({
      ip = iface.ip, mac = iface.mac, shortName = NodeName(), longName = long,
      report = string.format("#0001 [%04d] %s", PollReplies % 10000, active and "Sending" or "Idle"),
      portAddress = PortAddressOf(u), bindIndex = u.index, active = active,
      versionMajor = tonumber(major) or 0, versionMinor = tonumber(minor) or 0,
    })
    for _, t in ipairs(targets) do
      pcall(function() Discovery:Send(t, ArtNet.PORT, pkt) end)
    end
  end
  PollReplies = PollReplies + 1
end

-- Reply unicast to the poller (Art-Net 4) and to the subnet broadcast (Art-Net 3
-- tools expect that)
local function ReplyToPoll(sender)
  local iface = LocalInterfaceFor(sender)
  local targets = { sender }
  if iface.broadcast then table.insert(targets, iface.broadcast) end
  SendPollReplies(iface, targets)
  Log(2, string.format("ArtPoll from %s, replied as %s (%s, mac %s) to %s", sender, NodeName(), iface.ip,
    tostring(iface.mac), table.concat(targets, " + ")))
end

-- Unsolicited reply at start-up and when the name changes, so receivers learn the
-- name without waiting for their next poll
local function AnnounceNode(reason)
  if not Discovery or not OutputAllowed() then return end
  local iface = LocalInterfaceFor(nil)
  if not iface.broadcast then return end
  SendPollReplies(iface, { iface.broadcast })
  Log(1, string.format("Announced as %s to %s (%s)", NodeName(), iface.broadcast, reason))
end

local function OpenDiscovery()
  local s = UdpSocket.New()
  s.EventHandler = function(sock, packet)
    local op = ArtNet.OpCode(packet.Data)
    if op == ArtNet.OP_POLL and OutputAllowed() then ReplyToPoll(packet.Address) end
  end
  -- Signature of UdpSocket:Open for binding a port is not 100 % documented, try the
  -- variants in order and keep the first that works.
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
      Controls.Discovery.String = "Answering ArtPoll on UDP " .. ArtNet.PORT
      Log(1, string.format("Discovery: listening on UDP %d (variant %d)", ArtNet.PORT, i))
      return
    end
    lastErr = tostring(err)
  end
  Controls.Discovery.String = "Discovery not available (UDP " .. ArtNet.PORT .. " in use?)"
  Log(1, "Discovery not available: " .. (lastErr or "?"))
end

Controls["Node Name"].EventHandler = function(ctl)
  Log(1, "Node name: " .. NodeName())
  AnnounceNode("name changed")
end

-- --------------------------------------------------------------- send loop
local RetryAt = 0
local Tick = Timer.New()
Tick.EventHandler = function()
  TickTime = TickTime + TickInterval
  local now = Clock()
  if not Socket then
    if now >= RetryAt then
      RetryAt = now + SOCKET_RETRY_S
      OpenSocket()
    end
    return
  end
  if not OutputAllowed() then return end
  for _, u in ipairs(Universes) do
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
Log(1, string.format("Started: %d universe(s), %d Hz, %s, emulation %s, clock %s, build %s",
  UniverseCount, RefreshHz, Continuous and "continuous" or "on change", tostring(Emulating),
  ClockSource, PluginInfo.BuildVersion))
-- Keep long-lived objects reachable from a global. A timer or socket that is only
-- held by a local variable gets garbage collected on the Core and silently stops.
ArtNetRuntime = { Tick = Tick, Universes = Universes }
-- start the send timer first, so a problem further down can never stop output
Tick:Start(TickInterval)
OpenSocket()
RetryAt = Clock() + SOCKET_RETRY_S
OpenDiscovery()
AnnounceNode("start-up")
