-- (c) levo AVL | Elias Jenny - MIT License
-- Runtime code: only runs on the Core or in Emulation mode.

local DebugLevel = ({ None = 0, Basic = 1, Verbose = 2 })[Properties["Debug Print"].Value] or 0
local Topo = AtemTopology.Resolve(Properties)
local ButtonMode = AtemTopology.ButtonMode(Properties)
local DeviceLegends = Properties["Button Legends"].Value == "Device Names"
local Cmd = AtemState.Cmd

local TICK = 0.02             -- main timer resolution (s)
local TBAR_HOLD = 0.5         -- ignore T-bar feedback this long after a user move
local BACKOFF = { 1, 2, 4, 8, 15, 30 }

local Now = 0                 -- monotonic time in seconds, advanced by the main timer

local function Log(level, msg)
  if level <= DebugLevel then print(("[ATEM] %s"):format(msg)) end
end

---------------------------------------------------------------------------
-- Control helpers (only write when the value changes)
---------------------------------------------------------------------------
local function SetString(name, s)
  local c = Controls[name]
  s = s or ""
  if c and c.String ~= s then c.String = s end
end

local function SetBool(name, b)
  local c = Controls[name]
  if c and c.Boolean ~= b then c.Boolean = b end
end

local function SetPosition(name, p)
  local c = Controls[name]
  if not c then return end
  p = math.max(0, math.min(1, p or 0))
  if math.abs(c.Position - p) > 0.0005 then c.Position = p end
end

local function SetLegend(name, text)
  local c = Controls[name]
  if c then pcall(function() if c.Legend ~= text then c.Legend = text end end) end
end

local function SetChoices(name, list)
  local c = Controls[name]
  if c then pcall(function() c.Choices = list end) end
end

local STATUS = { OK = 0, Compromised = 1, Fault = 2, NotPresent = 3, Missing = 4, Initializing = 5 }
local function SetStatus(value, text)
  local c = Controls.Status
  if c.Value ~= value then c.Value = value end
  SetString("Status", text)
end

local function SetError(text)
  SetString("Last Error", text)
  if text ~= "" then Log(1, "Error: " .. text) end
end

---------------------------------------------------------------------------
-- State and source names
---------------------------------------------------------------------------
local St = AtemState.New()
local Ready = false            -- state dump complete

-- button sources per M/E (fixed by the design) and the keys of all sources
local MEButtons = {}
for me = 1, Topo.MEs do MEButtons[me] = AtemTopology.MEButtonSources(Topo, me, ButtonMode) end
local NameSources = AtemTopology.ButtonSourceUnion(Topo, ButtonMode)

local function LongName(id)
  local inp = St.inputs[id]
  if inp and inp.long ~= "" then return inp.long end
  return (AtemTopology.SourceKey(id))
end

local function ShortName(id)
  local inp = St.inputs[id]
  if inp and inp.short ~= "" then return inp.short end
  local _, short = AtemTopology.SourceKey(id)
  return short
end

-- Combo box lists: name <-> source id per M/E
local ComboNames = {}   -- [me] = { [id] = name }
local ComboIds = {}     -- [me] = { [name] = id }

local function MESourceList(me)
  local bit = 1 << (me - 1)
  if Ready and next(St.inputs) then
    local ids = {}
    for _, id in ipairs(St.inputOrder) do
      if St.inputs[id].me & bit ~= 0 then ids[#ids + 1] = id end
    end
    return AtemTopology.SortSources(ids, function(id) return St.inputs[id].port end)
  end
  return AtemTopology.MESources(Topo, me)
end

local function BuildCombos()
  for me = 1, Topo.MEs do
    local ids = MESourceList(me)
    local count = {}
    for _, id in ipairs(ids) do
      local n = LongName(id)
      count[n] = (count[n] or 0) + 1
    end
    local names, byId, byName = {}, {}, {}
    for _, id in ipairs(ids) do
      local n = LongName(id)
      if count[n] > 1 then n = n .. " (" .. AtemTopology.SourceKey(id) .. ")" end
      names[#names + 1] = n
      byId[id], byName[n] = n, id
    end
    ComboNames[me], ComboIds[me] = byId, byName
    SetChoices("ME" .. me .. " Program", names)
    SetChoices("ME" .. me .. " Preview", names)
  end
end

local function RenderNames()
  for _, id in ipairs(NameSources) do
    SetString("Name " .. AtemTopology.SourceKey(id), Ready and LongName(id) or "")
  end
  if DeviceLegends and Ready then
    for me = 1, Topo.MEs do
      for _, id in ipairs(MEButtons[me]) do
        local key, short = AtemTopology.SourceKey(id), ShortName(id)
        SetLegend("ME" .. me .. " Program " .. key, short)
        SetLegend("ME" .. me .. " Preview " .. key, short)
      end
    end
  end
end

---------------------------------------------------------------------------
-- M/E rendering
---------------------------------------------------------------------------
local TBarTouched = {}   -- [me] = time of the last user move

-- frame rate for "s:ff" rates; 25 until the switcher reports its video mode
local function Fps()
  return St.videoMode and AtemTopology.ModeFps[St.videoMode] or 25
end

local function RenderME(me)
  local m = St.me[me]
  local p = "ME" .. me .. " "
  if not (Ready and m) then
    for _, id in ipairs(MEButtons[me]) do
      local key = AtemTopology.SourceKey(id)
      SetBool(p .. "Program " .. key, false)
      SetBool(p .. "Preview " .. key, false)
    end
    SetString(p .. "Program", "")
    SetString(p .. "Preview", "")
    for _, n in ipairs({ "Auto", "In Transition", "Fade to Black", "Preview Transition", "Next Background" }) do
      SetBool(p .. n, false)
    end
    for _, style in ipairs(AtemTopology.TransitionStyles) do SetBool(p .. "Style " .. style, false) end
    for k = 1, Topo.USKs do
      SetBool(p .. "Next Key " .. k, false)
      SetBool(p .. "Key " .. k .. " On Air", false)
    end
    return
  end

  for _, id in ipairs(MEButtons[me]) do
    local key = AtemTopology.SourceKey(id)
    SetBool(p .. "Program " .. key, m.program == id)
    SetBool(p .. "Preview " .. key, m.preview == id)
  end
  local names = ComboNames[me] or {}
  SetString(p .. "Program", m.program and (names[m.program] or LongName(m.program)) or "")
  SetString(p .. "Preview", m.preview and (names[m.preview] or LongName(m.preview)) or "")

  SetBool(p .. "Auto", m.inTransition)
  SetBool(p .. "In Transition", m.inTransition)
  if Now - (TBarTouched[me] or -100) > TBAR_HOLD then
    SetPosition(p .. "T-Bar", m.inTransition and m.handle / 10000 or 0)
  end
  SetBool(p .. "Fade to Black", m.ftbBlack or m.ftbInTransition)
  if m.ftbRate > 0 then SetString(p .. "Fade to Black Rate", AtemTopology.FormatRate(m.ftbRate, Fps())) end

  for i, style in ipairs(AtemTopology.TransitionStyles) do
    SetBool(p .. "Style " .. style, m.nextStyle == i - 1)
  end
  SetString(p .. "Transition Style", AtemTopology.TransitionStyles[m.nextStyle + 1] or "")
  local rate = m.rates[m.nextStyle]
  SetString(p .. "Transition Rate", (rate and rate > 0) and AtemTopology.FormatRate(rate, Fps()) or "")
  SetBool(p .. "Preview Transition", m.previewTransition)
  SetBool(p .. "Next Background", m.nextSelection & 1 ~= 0)
  for k = 1, Topo.USKs do
    SetBool(p .. "Next Key " .. k, m.nextSelection & (1 << k) ~= 0)
    SetBool(p .. "Key " .. k .. " On Air", m.keyOnAir[k] == true)
  end
end

local Dirty = { me = {}, names = false }

local function RenderAll()
  BuildCombos()
  RenderNames()
  for me = 1, Topo.MEs do RenderME(me) end
  Dirty.me, Dirty.names = {}, false
end

---------------------------------------------------------------------------
-- Device info and model check
---------------------------------------------------------------------------
local function RenderDevice()
  local text = St.product
  local model = St.modelId and AtemTopology.ModelById(St.modelId)
  if model and text == "" then text = model.Name end
  SetString("Device", text)
  SetString("Protocol Version", AtemState.VersionString(St.version))
end

-- Compare the switcher with the plugin's model setting
local function CheckModel()
  local top = St.top or {}
  if Topo.Id then
    if St.modelId and St.modelId ~= Topo.Id then
      local actual = AtemTopology.ModelById(St.modelId)
      return ("Switcher is %s - plugin is set to %s"):format(
        actual and actual.Name or (St.product ~= "" and St.product or ("model " .. St.modelId)), Topo.Name)
    end
    return nil
  end
  local problems = {}
  if top.MEs and top.MEs < Topo.MEs then problems[#problems + 1] = top.MEs .. " M/E" end
  local keys = St.keyCount[1]
  if keys and keys < Topo.USKs then problems[#problems + 1] = keys .. " keyers per M/E" end
  if top.DSKs and top.DSKs < Topo.DSKs then problems[#problems + 1] = top.DSKs .. " DSK" end
  if top.Aux and top.Aux < Topo.Aux then problems[#problems + 1] = top.Aux .. " aux" end
  if #problems > 0 then
    return "Switcher only has " .. table.concat(problems, ", ") .. " - check the Custom properties"
  end
  return nil
end

---------------------------------------------------------------------------
-- Connection
---------------------------------------------------------------------------
local Conn = {
  ip = "",
  phase = "idle",       -- idle | connecting | syncing | ready | waiting (backoff)
  retryAt = nil,
  attempt = 0,
  reconnects = 0,
  syncStart = 0,
  unknown = {},
}

local Udp = UdpSocket.New()
local UdpOpen = false

local function OpenUdp()
  if UdpOpen then return true end
  local ok, err = pcall(function() Udp:Open() end)
  if not ok then
    SetError("Could not open UDP socket: " .. tostring(err))
    return false
  end
  UdpOpen = true
  return true
end

local function SetPhase(phase)
  Conn.phase = phase
  SetBool("Connected", phase == "syncing" or phase == "ready")
end

local Session -- forward
local Connect

local function ScheduleRetry(reason)
  Conn.attempt = Conn.attempt + 1
  local delay = BACKOFF[math.min(Conn.attempt, #BACKOFF)]
  Conn.retryAt = Now + delay
  Conn.retryReason = reason or "Not connected"
  Ready = false
  SetPhase("waiting")
  RenderAll()
  SetStatus(STATUS.Missing, ("%s - retry in %ds"):format(Conn.retryReason, delay))
  Log(1, ("%s, retry in %ds"):format(reason or "Disconnected", delay))
end

local function OnInitDone()
  Ready = true
  SetPhase("ready")
  Conn.attempt = 0
  RenderDevice()
  RenderAll()
  local problem = CheckModel()
  if problem then
    SetError(problem)
    SetStatus(STATUS.Compromised, problem)
  else
    SetStatus(STATUS.OK, "OK")
  end
  local inputs = 0
  for _ in pairs(St.inputs) do inputs = inputs + 1 end
  Log(1, ("State received in %.1fs: %s, protocol %s, %d M/E, %d sources"):format(
    Now - Conn.syncStart, St.product, AtemState.VersionString(St.version),
    St.top and St.top.MEs or 0, inputs))
end

local function OnCommand(name, data)
  local key, me = AtemState.Apply(St, name, data)
  if key == nil then
    if DebugLevel >= 2 and not Conn.unknown[name] then
      Conn.unknown[name] = true
      Log(2, ("Not handled: %s (%d bytes)"):format(name, #data))
    end
    return
  end
  if key == "error" then
    Log(1, ("Could not parse %s (%d bytes): %s"):format(name, #data, tostring(me)))
    return
  end
  if DebugLevel >= 2 and Ready then Log(2, ("< %s %s"):format(name, AtemProtocol.Hex(data, 24))) end
  if key == "me" then
    if me then Dirty.me[me] = true end
  elseif key == "input" then
    Dirty.names = true
  elseif key == "device" then
    if Ready then RenderDevice() end
  elseif key == "video" then
    for i = 1, Topo.MEs do Dirty.me[i] = true end
  elseif key == "init" then
    OnInitDone()
  end
end

Session = AtemProtocol.NewSession({
  Transmit = function(data)
    if DebugLevel >= 2 and #data > 12 then Log(2, "> " .. AtemProtocol.Hex(data:sub(13), 48)) end
    local ok, err = pcall(function() Udp:Send(Conn.ip, AtemProtocol.PORT, data) end)
    if not ok then Log(1, "Send failed: " .. tostring(err)) end
  end,
  OnConnected = function()
    SetPhase("syncing")
    Conn.syncStart = Now
    SetStatus(STATUS.Initializing, "Connected, receiving switcher state")
    Log(1, "Connected to " .. Conn.ip)
  end,
  OnCommand = OnCommand,
  OnLost = function(reason)
    SetError(reason)
    ScheduleRetry(Conn.phase == "connecting" and "No answer from switcher" or "Connection lost")
  end,
  Log = Log,
})

Udp.EventHandler = function(_, packet)
  if packet.Address ~= Conn.ip then return end
  Session:Receive(packet.Data, Now)
end

local function ValidIp(ip)
  local a, b, c, d = ip:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
  if not a then return false end
  for _, v in ipairs({ a, b, c, d }) do
    if tonumber(v) > 255 then return false end
  end
  return true
end

Connect = function()
  Session:Close()
  Ready = false
  St = AtemState.New()
  Conn.retryAt = nil
  Conn.ip = Controls["IP Address"].String:gsub("^%s+", ""):gsub("%s+$", "")
  RenderDevice()
  if Conn.ip == "" then
    SetPhase("idle")
    RenderAll()
    SetStatus(STATUS.Missing, "No IP address set")
    return
  end
  if not ValidIp(Conn.ip) then
    SetPhase("idle")
    RenderAll()
    SetStatus(STATUS.Fault, "Invalid IP address: " .. Conn.ip)
    return
  end
  if not OpenUdp() then
    SetPhase("idle")
    SetStatus(STATUS.Fault, "Could not open UDP socket")
    return
  end
  SetPhase("connecting")
  RenderAll()
  SetStatus(STATUS.Initializing, "Connecting to " .. Conn.ip)
  Log(1, ("Connecting to %s:%d"):format(Conn.ip, AtemProtocol.PORT))
  Session:Connect(Now)
end

-- Send a command; dropped (with a log line) when not connected
local function Send(cmd, what, coalesceKey)
  if not Ready then
    Log(1, "Not connected - dropped: " .. what)
    return false
  end
  if coalesceKey == nil then Log(1, what) end
  Session:Queue(cmd, coalesceKey)
  Session:Flush(Now)
  return true
end

---------------------------------------------------------------------------
-- Main timer
---------------------------------------------------------------------------
local MainTimer = Timer.New()
-- Keep long-lived objects reachable from a global. Objects only held by locals
-- can be garbage collected on the Core and silently stop working.
AtemRuntime = { Timer = MainTimer, Udp = Udp, Session = Session, Conn = Conn }

MainTimer.EventHandler = function()
  Now = Now + TICK
  if Conn.phase == "waiting" and Conn.retryAt then
    if Now >= Conn.retryAt then
      Conn.reconnects = Conn.reconnects + 1
      SetString("Reconnects", tostring(Conn.reconnects))
      Connect()
      return
    end
    -- count down in the status text
    SetString("Status", ("%s - retry in %ds"):format(Conn.retryReason, math.ceil(Conn.retryAt - Now - 1e-6)))
  end
  Session:Tick(Now)
  if Ready then
    if Dirty.names then
      BuildCombos()
      RenderNames()
      for me = 1, Topo.MEs do Dirty.me[me] = true end
      Dirty.names = false
    end
    for me in pairs(Dirty.me) do RenderME(me) end
    Dirty.me = {}
  end
end

---------------------------------------------------------------------------
-- User input
---------------------------------------------------------------------------
local function AfterInput(me)
  -- toggles flip on press: show the switcher's state again until feedback arrives
  RenderME(me)
end

for me = 1, Topo.MEs do
  local p = "ME" .. me .. " "

  for _, bus in ipairs({ "Program", "Preview" }) do
    local make = bus == "Program" and Cmd.Program or Cmd.Preview
    for _, id in ipairs(MEButtons[me]) do
      local key = AtemTopology.SourceKey(id)
      Controls[p .. bus .. " " .. key].EventHandler = function()
        Send(make(me, id), ("M/E %d %s: %s"):format(me, bus, key))
        AfterInput(me)
      end
    end
    Controls[p .. bus].EventHandler = function(c)
      local id = ComboIds[me] and ComboIds[me][c.String]
      if id then
        Send(make(me, id), ("M/E %d %s: %s"):format(me, bus, c.String))
      else
        Log(1, ("M/E %d %s: unknown source '%s'"):format(me, bus, c.String))
      end
      AfterInput(me)
    end
  end

  Controls[p .. "Cut"].EventHandler = function()
    Send(Cmd.Cut(me), ("M/E %d Cut"):format(me))
  end
  Controls[p .. "Auto"].EventHandler = function()
    Send(Cmd.Auto(me), ("M/E %d Auto"):format(me))
    AfterInput(me)
  end
  Controls[p .. "T-Bar"].EventHandler = function(c)
    TBarTouched[me] = Now
    local pos = math.floor(c.Position * 10000 + 0.5)
    Send(Cmd.TransitionPosition(me, pos), ("M/E %d T-bar %d"):format(me, pos), "tbar" .. me)
  end
  Controls[p .. "Fade to Black"].EventHandler = function()
    Send(Cmd.FadeToBlack(me), ("M/E %d Fade to Black"):format(me))
    AfterInput(me)
  end
  Controls[p .. "Fade to Black Rate"].EventHandler = function(c)
    local frames = AtemTopology.ParseRate(c.String, Fps())
    if frames then
      Send(Cmd.FadeToBlackRate(me, frames), ("M/E %d FTB rate %s (%d frames)"):format(me, c.String, frames), "ftbrate" .. me)
    else
      Log(1, ("M/E %d: invalid FTB rate '%s' (use s:ff, e.g. 1:00)"):format(me, c.String))
    end
    AfterInput(me)
  end

  local function SetStyle(index)
    Send(Cmd.NextStyle(me, index - 1), ("M/E %d style %s"):format(me, AtemTopology.TransitionStyles[index]))
    AfterInput(me)
  end
  for i, style in ipairs(AtemTopology.TransitionStyles) do
    Controls[p .. "Style " .. style].EventHandler = function() SetStyle(i) end
  end
  Controls[p .. "Transition Style"].EventHandler = function(c)
    for i, style in ipairs(AtemTopology.TransitionStyles) do
      if style == c.String then SetStyle(i) return end
    end
    AfterInput(me)
  end
  Controls[p .. "Transition Rate"].EventHandler = function(c)
    local m = St.me[me]
    local style = m and m.nextStyle or 0
    local frames = AtemTopology.ParseRate(c.String, Fps())
    local cmd = frames and Cmd.TransitionRate(me, style, frames)
    if cmd then
      Send(cmd, ("M/E %d %s rate %s (%d frames)"):format(me, AtemTopology.TransitionStyles[style + 1], c.String, frames),
        "rate" .. me)
    elseif not frames then
      Log(1, ("M/E %d: invalid rate '%s' (use s:ff, e.g. 1:00)"):format(me, c.String))
    else
      Log(1, ("M/E %d: %s has no rate"):format(me, AtemTopology.TransitionStyles[style + 1] or "?"))
    end
    AfterInput(me)
  end
  Controls[p .. "Preview Transition"].EventHandler = function()
    local m = St.me[me]
    Send(Cmd.PreviewTransition(me, not (m and m.previewTransition)), ("M/E %d Preview Transition"):format(me))
    AfterInput(me)
  end

  -- Next transition: background and keys form a bit mask that must not be empty
  local function ToggleNext(bit, what)
    local m = St.me[me]
    if m then
      local mask = m.nextSelection ~ bit
      if mask == 0 then
        Log(1, ("M/E %d: at least one element must stay selected for the next transition"):format(me))
      else
        Send(Cmd.NextSelection(me, mask), ("M/E %d Next %s"):format(me, what))
      end
    end
    AfterInput(me)
  end
  Controls[p .. "Next Background"].EventHandler = function() ToggleNext(1, "Background") end
  for k = 1, Topo.USKs do
    Controls[p .. "Next Key " .. k].EventHandler = function() ToggleNext(1 << k, "Key " .. k) end
    Controls[p .. "Key " .. k .. " On Air"].EventHandler = function()
      local m = St.me[me]
      local on = not (m and m.keyOnAir[k])
      Send(Cmd.KeyOnAir(me, k, on), ("M/E %d Key %d %s"):format(me, k, on and "on air" or "off air"))
      AfterInput(me)
    end
  end
end

Controls["IP Address"].EventHandler = function()
  Conn.attempt = 0
  Connect()
end
Controls.Reconnect.EventHandler = function()
  Conn.attempt = 0
  Conn.reconnects = Conn.reconnects + 1
  SetString("Reconnects", tostring(Conn.reconnects))
  Connect()
end

---------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------
SetString("Reconnects", "0")
SetError("")
for me = 1, Topo.MEs do
  SetChoices("ME" .. me .. " Transition Style", AtemTopology.TransitionStyles)
end
RenderAll()
Log(1, ("Started, build %s - model %s, %d M/E"):format(PluginInfo.BuildVersion, Topo.Name, Topo.MEs))
MainTimer:Start(TICK)
Connect()
