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
    if Ctl(u.index, "Enable").Boolean and (u.dirty or now - u.lastSent >= KEEPALIVE_S) then
      Send(u, now)
    end
  end
end

-- --------------------------------------------------------------- start
SetStatus(STATUS.Initializing, "Starting")
if Controls["Broadcast Address"].String == "" then
  Controls["Broadcast Address"].String = "255.255.255.255"
end
Log(1, string.format("Started: %d universe(s), %d Hz, emulation %s, clock %s, build %s",
  UniverseCount, RefreshHz, tostring(Emulating), ClockSource, PluginInfo.BuildVersion))
-- Keep long-lived objects reachable from a global. A timer or socket that is only
-- held by a local variable gets garbage collected on the Core and silently stops.
ArtNetRuntime = { Tick = Tick, Universes = Universes }
-- start the send timer first, so a problem further down can never stop output
Tick:Start(TickInterval)
OpenSocket()
RetryAt = Clock() + SOCKET_RETRY_S
