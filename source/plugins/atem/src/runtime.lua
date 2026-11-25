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

local CoreLog = Log           -- Q-SYS event log API, shadowed by the debug helper below
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
-- The Core reads a Status control back with the state in front ("Missing - text"),
-- so comparing with the read-back never matches. Compare with what we last wrote.
local LastStatus = {}
local function SetStatus(value, text)
  local c = Controls.Status
  text = text or ""
  if LastStatus.value ~= value then
    c.Value = value
    LastStatus.value = value
  end
  if LastStatus.text ~= text then
    c.String = text
    LastStatus.text = text
  end
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

-- Button sources per bus (fixed by the design)
local AuxMode = AtemTopology.AuxMode(Properties, Topo)
local KeyerSetup = AtemTopology.KeyerSetup(Properties)
local SSCount = AtemTopology.SuperSourceCount(Topo, Properties)
local MEButtons, AuxButtons = {}, {}
for me = 1, Topo.MEs do MEButtons[me] = AtemTopology.MEButtonSources(Topo, me, ButtonMode) end
for aux = 1, Topo.Aux do AuxButtons[aux] = AtemTopology.AuxButtonSources(Topo, aux, AuxMode) end
local BoxButtons = AtemTopology.BoxButtonSources(Topo, ButtonMode)
local _, NameSources = AtemTopology.NamePlacement(Topo, Properties)

local function Key(id) return (AtemTopology.SourceKey(id)) end

local function LongName(id)
  local inp = St.inputs[id]
  if inp and inp.long ~= "" then return inp.long end
  return Key(id)
end

local function ShortName(id)
  local inp = St.inputs[id]
  if inp and inp.short ~= "" then return inp.short end
  local _, short = AtemTopology.SourceKey(id)
  return short
end

-- Combo box groups: which sources a combo offers, name <-> id per group
local Combos = {}   -- name -> { controls = {...}, accept = fn(port, sa, me), byId, byName }
local function AddCombo(name, controls, accept)
  Combos[name] = { controls = controls, accept = accept, byId = {}, byName = {} }
end
for me = 1, Topo.MEs do
  local bit = 1 << (me - 1)
  AddCombo("me" .. me, { "ME" .. me .. " Program", "ME" .. me .. " Preview" },
    function(port, sa, meAvail) return meAvail & bit ~= 0 end)
end
if KeyerSetup then
  local keyControls = {}
  for me = 1, Topo.MEs do
    for k = 1, Topo.USKs do
      keyControls[#keyControls + 1] = "ME" .. me .. " Key " .. k .. " Fill"
      keyControls[#keyControls + 1] = "ME" .. me .. " Key " .. k .. " Key"
    end
  end
  for n = 1, Topo.DSKs do
    keyControls[#keyControls + 1] = "DSK " .. n .. " Fill"
    keyControls[#keyControls + 1] = "DSK " .. n .. " Key"
  end
  AddCombo("key", keyControls, function(port, sa) return sa & AtemTopology.Avail.KeySource ~= 0 end)
end
for aux = 1, Topo.Aux do
  AddCombo("aux" .. aux, { "Aux " .. aux }, function(port, sa) return AtemTopology.AuxAvailable(aux, sa) end)
end
do
  local boxControls = {}
  for ss = 1, SSCount do
    for box = 1, AtemTopology.BOXES do boxControls[#boxControls + 1] = "SS" .. ss .. " Box " .. box .. " Source" end
  end
  AddCombo("box", boxControls, function(port, sa) return sa & AtemTopology.Avail.SuperSourceBox ~= 0 end)
end

-- Sources of the switcher (after the state dump), else of the model table
local function AllSources()
  local list = {}
  if Ready and next(St.inputs) then
    for _, id in ipairs(St.inputOrder) do
      local inp = St.inputs[id]
      list[#list + 1] = { id, inp.port, inp.sa, inp.me }
    end
  else
    list = Topo.Sources
  end
  return list
end

local function BuildCombos()
  local sources = AllSources()
  local portOf = {}
  for _, s in ipairs(sources) do portOf[s[1]] = s[2] end
  for _, combo in pairs(Combos) do
    local ids = {}
    for _, s in ipairs(sources) do
      if combo.accept(s[2], s[3], s[4]) then ids[#ids + 1] = s[1] end
    end
    ids = AtemTopology.SortSources(ids, function(id) return portOf[id] end)
    local count = {}
    for _, id in ipairs(ids) do
      local n = LongName(id)
      count[n] = (count[n] or 0) + 1
    end
    local names, byId, byName = {}, {}, {}
    for _, id in ipairs(ids) do
      local n = LongName(id)
      if count[n] > 1 then n = n .. " (" .. Key(id) .. ")" end
      names[#names + 1] = n
      byId[id], byName[n] = n, id
    end
    combo.byId, combo.byName = byId, byName
    for _, c in ipairs(combo.controls) do SetChoices(c, names) end
  end
end

local function ComboName(group, id)
  if id == nil or not Combos[group] then return "" end
  return Combos[group].byId[id] or LongName(id)
end

local function ComboId(group, name)
  return Combos[group].byName[name]
end

local function RenderNames()
  for _, id in ipairs(NameSources) do
    SetString("Name " .. Key(id), Ready and LongName(id) or "")
  end
  if DeviceLegends and Ready then
    local function legends(prefixes, ids)
      for _, id in ipairs(ids) do
        for _, p in ipairs(prefixes) do SetLegend(p .. Key(id), ShortName(id)) end
      end
    end
    for me = 1, Topo.MEs do legends({ "ME" .. me .. " Program ", "ME" .. me .. " Preview " }, MEButtons[me]) end
    for aux = 1, Topo.Aux do legends({ "Aux " .. aux .. " " }, AuxButtons[aux]) end
    for ss = 1, SSCount do
      for box = 1, AtemTopology.BOXES do legends({ "SS" .. ss .. " Box " .. box .. " " }, BoxButtons) end
    end
  end
end

---------------------------------------------------------------------------
-- Rendering
---------------------------------------------------------------------------
local TBarTouched = {}   -- [me] = time of the last user move

-- frame rate for "s:ff" rates; 25 until the switcher reports its video mode
local function Fps()
  return St.videoMode and AtemTopology.ModeFps[St.videoMode] or 25
end

-- The switcher reports the transition progress (0 -> 10000) and resets it to 0
-- afterwards. Like a hardware T-bar the fader stays at the end it reached: after
-- each completed transition the direction flips (state.tbarFlipped).
local function TBarDisplay(m)
  local progress = m.inTransition and m.handle / 10000 or 0
  if m.tbarFlipped then return 1 - progress end
  return progress
end

local function RenderME(me)
  local m = Ready and St.me[me] or nil
  local p = "ME" .. me .. " "
  m = m or { inTransition = false, handle = 0, ftbBlack = false, ftbInTransition = false, ftbRate = 0,
    nextStyle = -1, nextSelection = 0, previewTransition = false, rates = {}, keyOnAir = {}, keys = {} }

  for _, id in ipairs(MEButtons[me]) do
    local key = Key(id)
    SetBool(p .. "Program " .. key, m.program == id)
    SetBool(p .. "Preview " .. key, m.preview == id)
  end
  SetString(p .. "Program", ComboName("me" .. me, m.program))
  SetString(p .. "Preview", ComboName("me" .. me, m.preview))

  SetBool(p .. "Auto", m.inTransition)
  SetBool(p .. "In Transition", m.inTransition)
  if not TBarTouched[me] then
    SetPosition(p .. "T-Bar", TBarDisplay(m))
  end
  SetBool(p .. "Fade to Black", m.ftbBlack or m.ftbInTransition)
  SetString(p .. "Fade to Black Rate", m.ftbRate > 0 and AtemTopology.FormatRate(m.ftbRate, Fps()) or "")

  for i, style in ipairs(AtemTopology.TransitionStyles) do
    SetBool(p .. "Style " .. style, m.nextStyle == i - 1)
  end
  SetString(p .. "Transition Style", AtemTopology.TransitionStyles[m.nextStyle + 1] or "")
  local rate = m.rates[m.nextStyle]
  SetString(p .. "Transition Rate", (rate and rate > 0) and AtemTopology.FormatRate(rate, Fps()) or "")
  SetBool(p .. "Preview Transition", m.previewTransition)
  SetBool(p .. "Next Background", m.nextSelection & 1 ~= 0)
  for k = 1, Topo.USKs do
    local q = p .. "Key " .. k .. " "
    SetBool(p .. "Next Key " .. k, m.nextSelection & (1 << k) ~= 0)
    SetBool(q .. "On Air", m.keyOnAir[k] == true)
    local key = m.keys[k]
    SetString(q .. "Fill", key and ComboName("key", key.fill) or "")
    SetString(q .. "Key", key and ComboName("key", key.key) or "")
    SetString(q .. "Type", key and (AtemTopology.KeyTypes[key.type + 1] or ("Type " .. key.type)) or "")
  end
end

local function RenderDSK(n)
  local d = Ready and St.dsk[n] or {}
  local p = "DSK " .. n .. " "
  SetBool(p .. "On Air", d.onAir == true)
  SetBool(p .. "Tie", d.tie == true)
  SetBool(p .. "Auto", d.isAuto == true and d.inTransition == true)
  SetBool(p .. "In Transition", d.inTransition == true)
  SetString(p .. "Rate", (d.rate or 0) > 0 and AtemTopology.FormatRate(d.rate, Fps()) or "")
  SetString(p .. "Fill", ComboName("key", d.fill))
  SetString(p .. "Key", ComboName("key", d.key))
end

local function RenderAux(aux)
  local src = Ready and St.aux[aux] or nil
  for _, id in ipairs(AuxButtons[aux]) do SetBool("Aux " .. aux .. " " .. Key(id), src == id) end
  SetString("Aux " .. aux, ComboName("aux" .. aux, src))
end

local function RenderSS(ss)
  local boxes = Ready and St.ss[ss] and St.ss[ss].boxes or {}
  for box = 1, AtemTopology.BOXES do
    local b = boxes[box] or {}
    local p = "SS" .. ss .. " Box " .. box .. " "
    SetBool(p .. "Enable", b.enabled == true)
    for _, id in ipairs(BoxButtons) do SetBool(p .. Key(id), b.source == id) end
    SetString(p .. "Source", ComboName("box", b.source))
  end
end

-- Media pool, colour generators, macros
local Stills = AtemTopology.StillButtons(Topo, Properties)
local MacroCount = AtemTopology.MacroButtons(Topo, Properties)
local MediaIds = {}      -- [mp] = { [combo name] = { kind, index } }
local MacroIds = {}      -- [combo name] = index
local ColorTouched = {}  -- [n] = time of the last user move
local COLOR_HOLD = 0.5

local function StillName(i)
  local s = St.stills[i]
  return (s and s.used) and s.name or ""
end

local function ClipName(i)
  local c = St.clips[i]
  return (c and c.used) and c.name or ""
end

local function MediaChoice(kind, i)
  local name = kind == 1 and StillName(i) or ClipName(i)
  return ("%s %d%s"):format(kind == 1 and "Still" or "Clip", i, name ~= "" and (": " .. name) or "")
end

local function RenderPool()
  for i = 1, Stills do SetString("Still " .. i .. " Name", Ready and StillName(i) or "") end
  for i = 1, Topo.Clips do SetString("Clip " .. i .. " Name", Ready and ClipName(i) or "") end
  -- combo: every still / clip slot (unused ones too, so the list does not shift)
  local names, ids = {}, {}
  for i = 1, Topo.Stills do
    local n = MediaChoice(1, i)
    names[#names + 1], ids[n] = n, { 1, i }
  end
  for i = 1, Topo.Clips do
    local n = MediaChoice(2, i)
    names[#names + 1], ids[n] = n, { 2, i }
  end
  for mp = 1, Topo.MediaPlayers do
    MediaIds[mp] = ids
    SetChoices("MP" .. mp .. " Source", names)
  end
end

local function RenderMP(mp)
  local m = Ready and St.mp[mp] or {}
  local p = "MP" .. mp .. " "
  for i = 1, Stills do SetBool(p .. "Still " .. i, m.sourceType == 1 and m.still == i) end
  for i = 1, Topo.Clips do SetBool(p .. "Clip " .. i, m.sourceType == 2 and m.clip == i) end
  SetBool(p .. "Play", m.playing == true)
  SetBool(p .. "Loop", m.loop == true)
  local text = ""
  if m.sourceType == 1 and m.still then text = MediaChoice(1, m.still)
  elseif m.sourceType == 2 and m.clip then text = MediaChoice(2, m.clip) end
  SetString(p .. "Source", text)
end

local function RenderColor(n)
  if ColorTouched[n] then return end
  local c = Ready and St.colors[n]
  if not c then return end
  local p = "Color " .. n .. " "
  local function set(name, v)
    local ctl = Controls[name]
    if ctl and math.abs(ctl.Value - v) > 0.05 then ctl.Value = v end
  end
  set(p .. "Hue", math.floor(c.hue / 10 + 0.5))
  set(p .. "Saturation", c.sat / 10)
  set(p .. "Luma", c.luma / 10)
end

local function RenderMacros()
  local names, ids = {}, {}
  for i = 1, Topo.Macros do
    local m = St.macros[i]
    if Ready and m and m.used then
      local n = ("%d: %s"):format(i, m.name ~= "" and m.name or "(no name)")
      names[#names + 1], ids[n] = n, i
    end
  end
  MacroIds = ids
  SetChoices("Macro", names)
  local r = St.macroRun
  for i = 1, MacroCount do
    local m = St.macros[i]
    SetString("Macro " .. i .. " Name", (Ready and m and m.used) and m.name or "")
    SetBool("Macro " .. i, Ready and r.running and r.index == i or false)
  end
  SetBool("Macro Running", Ready and r.running or false)
  SetBool("Macro Loop", Ready and r.loop or false)
  local running = ""
  if Ready and r.running and r.index then
    local m = St.macros[r.index]
    running = ("%d: %s"):format(r.index, m and m.name or "")
  end
  SetString("Macro Running Name", running)
end

-- Audio
local AudioIds = AtemTopology.AudioInputs(Topo, Properties)
local AudioMin, AudioMax = AtemTopology.AudioRange(Topo)
local Fairlight = Topo.Audio == "Fairlight"
local AudioTouched = {}   -- [id or "master"] = time of the last user move
local AUDIO_HOLD = 0.5

local function AudioPrefix(id) return "Audio " .. AtemTopology.AudioKey(id) .. " " end

local function AudioName(id)
  if id < 1000 then return LongName(id) end
  return AtemTopology.AudioKey(id)
end

local function SetLevel(name, db, touchKey)
  if AudioTouched[touchKey] then return end
  local c = Controls[name]
  if not c or db == nil then return end
  db = math.max(AudioMin, math.min(AudioMax, db))
  if math.abs(c.Value - db) > 0.05 then c.Value = db end
end

local function RenderAudio()
  for _, id in ipairs(AudioIds) do
    local a = Ready and St.audio[id] or {}
    local p = AudioPrefix(id)
    SetLevel(p .. "Level", a.level, id)
    SetBool(p .. "On", a.mix == 1)
    SetBool(p .. "AFV", a.mix == 2)
    SetString(p .. "Name", Ready and AudioName(id) or AtemTopology.AudioKey(id))
  end
  if #AudioIds > 0 then
    local m = Ready and St.audioMaster or {}
    SetLevel("Audio Master Level", m.level, "master")
    SetBool("Audio Master AFV", m.ftb == true)
  end
end

-- Streaming / recording
local function StreamState(status)
  if status & 32 ~= 0 then return "Stopping" end
  if status & 4 ~= 0 then return "Streaming" end
  if status & 2 ~= 0 then return "Connecting" end
  if status & 16 ~= 0 then return "Error: invalid state" end
  if status & 0x8000 ~= 0 then return "Error" end
  return "Idle"
end

local function RecordState(status)
  local text
  if status & 128 ~= 0 then text = "Stopping"
  elseif status & 1 ~= 0 then text = "Recording"
  else text = "Idle" end
  if status & 2 == 0 then
    if status & 4 ~= 0 then text = text .. " - media full"
    elseif status & 8 ~= 0 then text = text .. " - media error"
    elseif status & 16 ~= 0 then text = text .. " - media unformatted"
    elseif status & 32 ~= 0 then text = text .. " - dropping frames"
    elseif status & 0x8000 ~= 0 then text = text .. " - error"
    else text = text .. " - no media" end
  end
  return text
end

local function Streaming() return St.stream.status & 4 ~= 0 end
local function Recording() return St.record.status & 1 ~= 0 end

local function RenderStream()
  if Topo.Streaming then
    SetBool("Stream", Ready and (Streaming() or St.stream.status & 2 ~= 0) or false)
    SetString("Stream Status", Ready and StreamState(St.stream.status) or "")
    SetString("Stream Duration", Ready and St.stream.duration or "")
  end
  if Topo.Recording then
    SetBool("Record", Ready and Recording() or false)
    SetString("Record Status", Ready and RecordState(St.record.status) or "")
    SetString("Record Duration", Ready and St.record.duration or "")
    local rem = St.record.remaining
    SetString("Record Time Remaining", (Ready and rem and rem >= 0)
      and ("%d:%02d:%02d"):format(rem // 3600, rem % 3600 // 60, rem % 60) or "")
    if Topo.RecordISO then SetBool("Record ISO", Ready and St.record.iso or false) end
  end
end

local Dirty
local function NewDirty()
  return { me = {}, dsk = {}, aux = {}, ss = {}, mp = {}, color = {}, names = false, pool = false, macro = false,
    audio = false, stream = false }
end
Dirty = NewDirty()

local function RenderAll()
  BuildCombos()
  RenderNames()
  for me = 1, Topo.MEs do RenderME(me) end
  for n = 1, Topo.DSKs do RenderDSK(n) end
  for aux = 1, Topo.Aux do RenderAux(aux) end
  for ss = 1, SSCount do RenderSS(ss) end
  RenderPool()
  for mp = 1, Topo.MediaPlayers do RenderMP(mp) end
  for n = 1, 2 do RenderColor(n) end
  RenderMacros()
  RenderAudio()
  RenderStream()
  Dirty = NewDirty()
end

local function IsClean(d)
  return not (d.names or d.pool or d.macro or d.audio or d.stream or next(d.me) or next(d.dsk)
    or next(d.aux) or next(d.ss) or next(d.mp) or next(d.color))
end

local function RenderDirty()
  if IsClean(Dirty) then return end   -- nothing changed: no new tables every tick
  if Dirty.names then
    RenderAll()
    return
  end
  for me in pairs(Dirty.me) do if me <= Topo.MEs then RenderME(me) end end
  for n in pairs(Dirty.dsk) do if n <= Topo.DSKs then RenderDSK(n) end end
  for aux in pairs(Dirty.aux) do if aux <= Topo.Aux then RenderAux(aux) end end
  for ss in pairs(Dirty.ss) do if ss <= SSCount then RenderSS(ss) end end
  if Dirty.pool then
    RenderPool()
    for mp = 1, Topo.MediaPlayers do Dirty.mp[mp] = true end
  end
  for mp in pairs(Dirty.mp) do if mp <= Topo.MediaPlayers then RenderMP(mp) end end
  for n in pairs(Dirty.color) do RenderColor(n) end
  if Dirty.macro then RenderMacros() end
  if Dirty.audio then RenderAudio() end
  if Dirty.stream then RenderStream() end
  Dirty = NewDirty()
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
  if key == "me" or key == "dsk" or key == "aux" or key == "ss" or key == "mp" then
    if me then Dirty[key][me] = true end
  elseif key == "color" then
    Dirty.color[AtemProtocol.U8(data, 0) + 1] = true
  elseif key == "pool" or key == "macro" or key == "audio" or key == "stream" then
    Dirty[key] = true
  elseif key == "input" then
    Dirty.names = true
  elseif key == "device" then
    if Ready then RenderDevice() end
  elseif key == "video" then
    Dirty.names = true   -- rates are shown in s:ff: render everything
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

local OnInternalError -- forward (health section)

Udp.EventHandler = function(_, packet)
  if packet.Address ~= Conn.ip or type(packet.Data) ~= "string" then return end
  local ok, err = pcall(Session.Receive, Session, packet.Data, Now)
  if not ok then OnInternalError("receive", err) end
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
local LastDurationPoll = 0
-- Keep long-lived objects reachable from a global. Objects only held by locals
-- can be garbage collected on the Core and silently stop working.
AtemRuntime = { Timer = MainTimer, Udp = Udp, Session = Session, Conn = Conn }

local function MainTick()
  Now = Now + TICK
  if Conn.phase == "waiting" and Conn.retryAt then
    if Now >= Conn.retryAt then
      Conn.reconnects = Conn.reconnects + 1
      SetString("Reconnects", tostring(Conn.reconnects))
      Connect()
      return
    end
    -- count down in the status text (written only when the second changes)
    SetStatus(STATUS.Missing, ("%s - retry in %ds"):format(Conn.retryReason, math.ceil(Conn.retryAt - Now - 1e-6)))
  end
  Session:Tick(Now)
  -- once the T-bar hold time is over, show the switcher's position again
  for me, t in pairs(TBarTouched) do
    if Now - t > TBAR_HOLD then
      TBarTouched[me] = nil
      Dirty.me[me] = true
    end
  end
  for k, t in pairs(AudioTouched) do
    if Now - t > AUDIO_HOLD then
      AudioTouched[k] = nil
      Dirty.audio = true
    end
  end
  -- the switcher reports stream / record durations on request
  if Ready and Now - LastDurationPoll >= 1 then
    LastDurationPoll = Now
    if Topo.Streaming and Streaming() then Session:Queue(Cmd.StreamDuration(), "srdr") end
    if Topo.Recording and Recording() then Session:Queue(Cmd.RecordDuration(), "rmdr") end
  end
  for n, t in pairs(ColorTouched) do
    if Now - t > COLOR_HOLD then
      ColorTouched[n] = nil
      Dirty.color[n] = true
    end
  end
  if Ready then RenderDirty() end
end

---------------------------------------------------------------------------
-- Health: error recovery, main timer watchdog, memory guard
-- A runtime error inside the main timer must not leave the connection state
-- machine half-way (e.g. stuck between two reconnect attempts), and the plugin
-- must never grow without bound on the Core.
---------------------------------------------------------------------------
local MEM_WARN_KB = 10 * 1024    -- normal use is around 1 MB: above this, log a warning
local MEM_LIMIT_KB = 32 * 1024   -- above this, reset the connection
local GC_EVERY = 60              -- s, full garbage collection
local STALL_AFTER = 3            -- s without a main timer tick -> restart it

local Health = { ticks = 0, seenTicks = 0, stalled = 0, seconds = 0, errors = 0, lastError = nil, lastErrorAt = -1e9 }
local HasGc = type(collectgarbage) == "function"
local function MemoryKB() return HasGc and collectgarbage("count") or 0 end

-- Core event log (Core Manager > Event Log), with a plain print as fallback
local EVENT_LOG_EVERY = 600      -- s, at most one event log entry per kind in this time
local EventLogged = {}           -- [kind] = Health.seconds of the last entry
local function EventLog(kind, msg)
  local last = EventLogged[kind]
  if last and Health.seconds - last < EVENT_LOG_EVERY then return end
  EventLogged[kind] = Health.seconds
  local text = "ATEM Switcher: " .. msg
  local logger = type(CoreLog) == "table" and (CoreLog.Error or CoreLog.Message)
  local ok = logger and pcall(logger, text)
  if not ok then print("[ATEM] (event log) " .. text) end
end

-- Errors are always printed (independent of Debug Print), at most once a minute per
-- message, and written to the Core event log (at most every 10 minutes per kind)
local function Report(msg, kind)
  if msg ~= Health.lastError or Health.seconds - Health.lastErrorAt >= 60 then
    print("[ATEM] " .. msg)
    Health.lastError, Health.lastErrorAt = msg, Health.seconds
  end
  EventLog(kind or msg, msg)
end

-- Drop everything the plugin knows about the switcher and connect again
local function ResetConnection(reason)
  pcall(function() Session:Close() end)
  Ready = false
  St = AtemState.New()
  Dirty = NewDirty()
  Conn.unknown = {}
  for k in pairs(TBarTouched) do TBarTouched[k] = nil end
  for k in pairs(AudioTouched) do AudioTouched[k] = nil end
  for k in pairs(ColorTouched) do ColorTouched[k] = nil end
  local ok, err = pcall(ScheduleRetry, reason)
  if not ok then
    -- last resort: plain state, the next tick retries
    Conn.phase, Conn.retryAt, Conn.retryReason = "waiting", Now + BACKOFF[1], reason
    Report("Recovery failed: " .. tostring(err))
  end
end

OnInternalError = function(where, err)
  Health.errors = Health.errors + 1
  local msg = ("Internal error (%s): %s"):format(where, tostring(err))
  Report(msg, "error " .. where)
  pcall(SetError, msg)
  ResetConnection("Internal error")
end

MainTimer.EventHandler = function()
  Health.ticks = Health.ticks + 1
  local ok, err = pcall(MainTick)
  if not ok then OnInternalError("timer", err) end
end

local function FormatUptime(s)
  s = math.floor(s)
  return ("%d:%02d:%02d"):format(s // 3600, s % 3600 // 60, s % 60)
end

local function HealthTick()
  Health.seconds = Health.seconds + 1
  -- main timer watchdog
  if Health.ticks == Health.seenTicks then
    Health.stalled = Health.stalled + 1
    if Health.stalled >= STALL_AFTER then
      Report("Main timer stalled - restarting it", "stall")
      MainTimer:Stop()
      MainTimer:Start(TICK)
      Health.stalled = 0
    end
  else
    Health.stalled = 0
  end
  Health.seenTicks = Health.ticks
  -- memory guard
  local kb = MemoryKB()
  if HasGc and (Health.seconds % GC_EVERY == 0 or kb > MEM_LIMIT_KB) then
    collectgarbage("collect")
    kb = MemoryKB()
    if kb > MEM_LIMIT_KB then
      Report(("Memory limit reached (%.1f MB) - resetting connection"):format(kb / 1024), "memory limit")
      ResetConnection("Memory limit reached")
      collectgarbage("collect")
      kb = MemoryKB()
    end
  end
  -- measured right after a full collection: live data only, garbage excluded
  if HasGc and Health.seconds % GC_EVERY == 0 and kb > MEM_WARN_KB then
    Report(("High memory use: %.1f MB (normal is about 1 MB)"):format(kb / 1024), "memory warn")
  end
  -- readouts: Plugin Uptime follows the main timer, so it stops when the plugin hangs
  SetString("Lua Memory", HasGc and ("%.1f MB"):format(kb / 1024) or "n/a")
  SetString("Plugin Uptime", FormatUptime(Now))
  SetString("Internal Errors", tostring(Health.errors))
end

local HealthTimer = Timer.New()
HealthTimer.EventHandler = function()
  local ok, err = pcall(HealthTick)
  if not ok then Report("Health check failed: " .. tostring(err)) end
end
AtemRuntime.HealthTimer = HealthTimer

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
      local id = ComboId("me" .. me, c.String)
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
    local m = St.me[me]
    local position = (m and m.tbarFlipped) and 1 - c.Position or c.Position
    local pos = math.floor(position * 10000 + 0.5)
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

-- Upstream keyer sources and type (Keyer Setup page)
for me = 1, KeyerSetup and Topo.MEs or 0 do
  for k = 1, Topo.USKs do
    Controls["ME" .. me .. " Key " .. k .. " Type"].EventHandler = function(c)
      for i, t in ipairs(AtemTopology.KeyTypes) do
        if t == c.String then
          Send(Cmd.KeyType(me, k, i - 1), ("M/E %d Key %d type %s"):format(me, k, t))
        end
      end
      RenderME(me)
    end
    local q = "ME" .. me .. " Key " .. k .. " "
    for _, part in ipairs({ "Fill", "Key" }) do
      Controls[q .. part].EventHandler = function(c)
        local id = ComboId("key", c.String)
        if id then
          local make = part == "Fill" and Cmd.KeyFill or Cmd.KeyKey
          Send(make(me, k, id), ("M/E %d Key %d %s: %s"):format(me, k, part, c.String))
        end
        RenderME(me)
      end
    end
  end
end

-- Downstream keyers
for n = 1, Topo.DSKs do
  local p = "DSK " .. n .. " "
  local function D() return St.dsk[n] or {} end
  Controls[p .. "On Air"].EventHandler = function()
    local on = not D().onAir
    Send(Cmd.DskOnAir(n, on), ("DSK %d %s"):format(n, on and "on air" or "off air"))
    RenderDSK(n)
  end
  Controls[p .. "Tie"].EventHandler = function()
    local on = not D().tie
    Send(Cmd.DskTie(n, on), ("DSK %d tie %s"):format(n, on and "on" or "off"))
    RenderDSK(n)
  end
  Controls[p .. "Auto"].EventHandler = function()
    Send(Cmd.DskAuto(St, n), ("DSK %d auto"):format(n))
    RenderDSK(n)
  end
  Controls[p .. "Rate"].EventHandler = function(c)
    local frames = AtemTopology.ParseRate(c.String, Fps())
    if frames then
      Send(Cmd.DskRate(n, frames), ("DSK %d rate %s (%d frames)"):format(n, c.String, frames), "dskrate" .. n)
    else
      Log(1, ("DSK %d: invalid rate '%s' (use s:ff, e.g. 1:00)"):format(n, c.String))
    end
    RenderDSK(n)
  end
  for _, part in ipairs(KeyerSetup and { "Fill", "Key" } or {}) do
    Controls[p .. part].EventHandler = function(c)
      local id = ComboId("key", c.String)
      if id then
        local make = part == "Fill" and Cmd.DskFill or Cmd.DskKey
        Send(make(n, id), ("DSK %d %s: %s"):format(n, part, c.String))
      end
      RenderDSK(n)
    end
  end
end

-- Aux outputs
for aux = 1, Topo.Aux do
  for _, id in ipairs(AuxButtons[aux]) do
    Controls["Aux " .. aux .. " " .. Key(id)].EventHandler = function()
      Send(Cmd.Aux(aux, id), ("Aux %d: %s"):format(aux, Key(id)))
      RenderAux(aux)
    end
  end
  Controls["Aux " .. aux].EventHandler = function(c)
    local id = ComboId("aux" .. aux, c.String)
    if id then
      Send(Cmd.Aux(aux, id), ("Aux %d: %s"):format(aux, c.String))
    else
      Log(1, ("Aux %d: unknown source '%s'"):format(aux, c.String))
    end
    RenderAux(aux)
  end
end

-- Media players
for mp = 1, Topo.MediaPlayers do
  local p = "MP" .. mp .. " "
  for i = 1, Stills do
    Controls[p .. "Still " .. i].EventHandler = function()
      Send(Cmd.MediaStill(mp, i), ("MP %d still %d"):format(mp, i))
      RenderMP(mp)
    end
  end
  for i = 1, Topo.Clips do
    Controls[p .. "Clip " .. i].EventHandler = function()
      Send(Cmd.MediaClip(mp, i), ("MP %d clip %d"):format(mp, i))
      RenderMP(mp)
    end
  end
  if Topo.Clips > 0 then
    Controls[p .. "Play"].EventHandler = function()
      local m = St.mp[mp] or {}
      Send(Cmd.MediaPlay(mp, not m.playing), ("MP %d %s"):format(mp, m.playing and "stop" or "play"))
      RenderMP(mp)
    end
    Controls[p .. "Loop"].EventHandler = function()
      local m = St.mp[mp] or {}
      Send(Cmd.MediaLoop(mp, not m.loop), ("MP %d loop %s"):format(mp, m.loop and "off" or "on"))
      RenderMP(mp)
    end
    Controls[p .. "Rewind"].EventHandler = function()
      Send(Cmd.MediaRewind(mp), ("MP %d rewind"):format(mp))
    end
  end
  Controls[p .. "Source"].EventHandler = function(c)
    local item = MediaIds[mp] and MediaIds[mp][c.String]
    if item then
      local make = item[1] == 1 and Cmd.MediaStill or Cmd.MediaClip
      Send(make(mp, item[2]), ("MP %d: %s"):format(mp, c.String))
    end
    RenderMP(mp)
  end
end

-- Colour generators: moves are merged while dragging
for n = 1, 2 do
  local p = "Color " .. n .. " "
  local function Changed(what)
    ColorTouched[n] = Now
    local hue = math.floor(Controls[p .. "Hue"].Value * 10 + 0.5)
    local sat = math.floor(Controls[p .. "Saturation"].Value * 10 + 0.5)
    local luma = math.floor(Controls[p .. "Luma"].Value * 10 + 0.5)
    local cmd = Cmd.Color(n, what == "Hue" and hue or nil, what == "Saturation" and sat or nil, what == "Luma" and luma or nil)
    Send(cmd, ("Color %d %s"):format(n, what), "color" .. n .. what)
  end
  for _, part in ipairs({ "Hue", "Saturation", "Luma" }) do
    Controls[p .. part].EventHandler = function() Changed(part) end
  end
end

-- Macros
local function RunMacro(i, what)
  local r = St.macroRun
  if r.running and r.index == i then
    Send(Cmd.MacroStop(), "Macro stop")
  else
    Send(Cmd.MacroRun(i), "Macro run " .. what)
  end
  RenderMacros()
end
for i = 1, MacroCount do
  Controls["Macro " .. i].EventHandler = function() RunMacro(i, tostring(i)) end
end
Controls["Macro Run"].EventHandler = function()
  local i = MacroIds[Controls["Macro"].String]
  if i then RunMacro(i, Controls["Macro"].String) else Log(1, "Macro run: no macro selected") end
end
Controls["Macro"].EventHandler = function() end
Controls["Macro Stop"].EventHandler = function() Send(Cmd.MacroStop(), "Macro stop") end
Controls["Macro Loop"].EventHandler = function()
  Send(Cmd.MacroLoop(not St.macroRun.loop), "Macro loop " .. (St.macroRun.loop and "off" or "on"))
  RenderMacros()
end

-- Audio
local function SendAudio(id, level, mix, what)
  local a = St.audio[id] or {}
  local cmd
  if Fairlight then
    if not a.source then
      Log(1, ("Audio %s: no Fairlight source known yet"):format(AtemTopology.AudioKey(id)))
      return
    end
    cmd = Cmd.FairlightInput(id, a.source, level, mix)
  else
    cmd = Cmd.ClassicInput(id, level, mix)
  end
  Send(cmd, ("Audio %s %s"):format(AtemTopology.AudioKey(id), what), level and ("audio" .. id) or nil)
end

for _, id in ipairs(AudioIds) do
  local p = AudioPrefix(id)
  Controls[p .. "Level"].EventHandler = function(c)
    AudioTouched[id] = Now
    SendAudio(id, c.Value, nil, ("level %.1f dB"):format(c.Value))
  end
  local function Mix(option, what)
    SendAudio(id, nil, option, what)
    RenderAudio()
  end
  Controls[p .. "On"].EventHandler = function()
    local a = St.audio[id] or {}
    if a.mix == 1 then Mix(0, "off") else Mix(1, "on") end
  end
  if AtemTopology.AudioHasAFV(id) then
    Controls[p .. "AFV"].EventHandler = function()
      local a = St.audio[id] or {}
      if a.mix == 2 then Mix(0, "off") else Mix(2, "AFV") end
    end
  end
end
if #AudioIds > 0 then
  Controls["Audio Master Level"].EventHandler = function(c)
    AudioTouched.master = Now
    local cmd = Fairlight and Cmd.FairlightMaster(c.Value, nil) or Cmd.ClassicMaster(c.Value, nil)
    Send(cmd, ("Audio master level %.1f dB"):format(c.Value), "audiomaster")
  end
  Controls["Audio Master AFV"].EventHandler = function()
    local on = not St.audioMaster.ftb
    local cmd = Fairlight and Cmd.FairlightMaster(nil, on) or Cmd.ClassicMaster(nil, on)
    Send(cmd, "Audio master AFV (follow FTB) " .. (on and "on" or "off"))
    RenderAudio()
  end
end

-- Streaming / recording
if Topo.Streaming then
  Controls["Stream"].EventHandler = function()
    local on = not (Streaming() or St.stream.status & 2 ~= 0)
    Send(Cmd.Stream(on), on and "Start streaming" or "Stop streaming")
    RenderStream()
  end
end
if Topo.Recording then
  Controls["Record"].EventHandler = function()
    local on = not Recording()
    Send(Cmd.Record(on), on and "Start recording" or "Stop recording")
    RenderStream()
  end
  if Topo.RecordISO then
    Controls["Record ISO"].EventHandler = function()
      Send(Cmd.RecordISO(not St.record.iso), "Record ISO " .. (St.record.iso and "off" or "on"))
      RenderStream()
    end
  end
end

-- SuperSource boxes
for ss = 1, SSCount do
  for box = 1, AtemTopology.BOXES do
    local p = "SS" .. ss .. " Box " .. box .. " "
    local function B()
      local s = St.ss[ss]
      return s and s.boxes[box] or {}
    end
    Controls[p .. "Enable"].EventHandler = function()
      local on = not B().enabled
      Send(Cmd.SuperSourceBox(St, ss, box, on, nil), ("SuperSource %d box %d %s"):format(ss, box, on and "on" or "off"))
      RenderSS(ss)
    end
    local function SetSource(id, what)
      Send(Cmd.SuperSourceBox(St, ss, box, nil, id), ("SuperSource %d box %d: %s"):format(ss, box, what))
      RenderSS(ss)
    end
    for _, id in ipairs(BoxButtons) do
      Controls[p .. Key(id)].EventHandler = function() SetSource(id, Key(id)) end
    end
    Controls[p .. "Source"].EventHandler = function(c)
      local id = ComboId("box", c.String)
      if id then SetSource(id, c.String) else RenderSS(ss) end
    end
  end
end

Controls["IP Address"].EventHandler = function()
  Conn.attempt = 0
  local ok, err = pcall(Connect)
  if not ok then OnInternalError("connect", err) end
end
Controls.Reconnect.EventHandler = function()
  Conn.attempt = 0
  Conn.reconnects = Conn.reconnects + 1
  SetString("Reconnects", tostring(Conn.reconnects))
  local ok, err = pcall(Connect)
  if not ok then OnInternalError("connect", err) end
end

---------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------
SetString("Reconnects", "0")
SetError("")
for me = 1, Topo.MEs do
  SetChoices("ME" .. me .. " Transition Style", AtemTopology.TransitionStyles)
  for k = 1, KeyerSetup and Topo.USKs or 0 do
    SetChoices("ME" .. me .. " Key " .. k .. " Type", AtemTopology.KeyTypes)
  end
end
RenderAll()
Log(1, ("Started, build %s - model %s, %d M/E"):format(PluginInfo.BuildVersion, Topo.Name, Topo.MEs))
MainTimer:Start(TICK)
HealthTimer:Start(1)
local ok, err = pcall(Connect)
if not ok then OnInternalError("start", err) end
