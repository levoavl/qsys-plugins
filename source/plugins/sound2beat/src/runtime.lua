-- (c) levo AVL | Elias Jenny - MIT License
-- Runtime code: only runs on the Core or in Emulation mode.

local Opt = Options(Properties)
local DebugLevel = ({ None = 0, Basic = 1, Verbose = 2 })[Properties["Debug Print"].Value] or 0

local TICK = 0.01             -- main timer: level polling and beat clock (s)
local UI_INTERVAL = 0.1       -- display refresh for BPM, state, meters (s)
local NO_LEVEL_WARN = 5       -- no level change for this long -> warning (s)

local function Log(level, msg)
  if level <= DebugLevel then print(("[Sound2Beat] %s"):format(msg)) end
end

---------------------------------------------------------------------------
-- Clock. Timer.Now() is preferred (wall time, not affected by a late timer tick);
-- if it is not available the tick count is used.
---------------------------------------------------------------------------
local ClockSource, TickTime = "tick counter", 0
local function Clock() return TickTime end
do
  local ok, v = pcall(function() return Timer.Now() end)
  if ok and type(v) == "number" then
    ClockSource = "Timer.Now"
    Clock = function() return Timer.Now() end
  end
end

---------------------------------------------------------------------------
-- Control helpers (only write when the value changes)
---------------------------------------------------------------------------
local function Ctl(name) return Controls[name] end

local function SetString(name, s)
  local c = Ctl(name)
  s = s or ""
  if c and c.String ~= s then c.String = s end
end

local function SetBool(name, b)
  local c = Ctl(name)
  if c and c.Boolean ~= b then c.Boolean = b end
end

local function SetValue(name, v, eps)
  local c = Ctl(name)
  if c and math.abs(c.Value - v) > (eps or 0) then c.Value = v end
end

local function Num(name, default)
  local c = Ctl(name)
  return c and c.Value or default
end

local function Text(name)
  local c = Ctl(name)
  return c and c.String:gsub("^%s+", ""):gsub("%s+$", "") or ""
end

local STATUS = MAOutput.Status
local function SetStatus(code, text)
  local c = Controls.Status
  if c.Value ~= code then c.Value = code end
  SetString("Status", text)
end

local LastErrorText = ""
local function SetError(text)
  LastErrorText = text or ""
  SetString("Last Error", LastErrorText)
end

---------------------------------------------------------------------------
-- Defaults for text fields (knobs and toggles get theirs from DefaultValue)
---------------------------------------------------------------------------
local DEFAULT_TEMPLATE = {
  grandMA2 = "SpecialMaster 3.{master} At {bpm}",
  grandMA3 = "Master 3.{master} At BPM {bpm}",
}
local function DefaultText(name, value)
  local c = Ctl(name)
  if c and c.String:match("^%s*$") then c.String = value end
end
DefaultText("Meter Control", "meter.1")
if Opt.Console ~= "None" then DefaultText("Command Template", DEFAULT_TEMPLATE[Opt.Console]) end
if Opt.Console == "grandMA2" then DefaultText("Username", "administrator") end

---------------------------------------------------------------------------
-- Beat engine
---------------------------------------------------------------------------
local Engine = BeatEngine.New({})

local function ConfigureEngine()
  local lo, hi = math.floor(Num("BPM Min", 80)), math.floor(Num("BPM Max", 160))
  Engine:Configure({
    bpmMin = lo, bpmMax = hi,
    sensitivity = Num("Sensitivity", 50) / 100,
    minConfidence = Num("Min Confidence", 50) / 100,
  })
  if Engine.bpmMax ~= hi then
    SetError(("BPM range %d-%d is less than an octave, using %d-%d"):format(lo, hi, Engine.bpmMin, Engine.bpmMax))
  end
  Log(1, ("Detection: %d-%d BPM, sensitivity %d%%, min confidence %d%%"):format(
    Engine.bpmMin, Engine.bpmMax, math.floor(Num("Sensitivity", 50)), math.floor(Num("Min Confidence", 50))))
end
ConfigureEngine()
for _, name in ipairs({ "BPM Min", "BPM Max", "Sensitivity", "Min Confidence" }) do
  Ctl(name).EventHandler = ConfigureEngine
end

Engine:SetAuto(Controls.Auto.Boolean)
Engine:SetHold(Controls.Hold.Boolean)
Controls.Auto.EventHandler = function(c) Engine:SetAuto(c.Boolean) end
Controls.Hold.EventHandler = function(c) Engine:SetHold(c.Boolean) end

local function ScaleText(f)
  if f >= 1 then return ("x%d"):format(math.floor(f + 0.5)) end
  return ("x1/%d"):format(math.floor(1 / f + 0.5))
end
local function SetScale(f)
  Engine:SetScale(f)
  SetString("Tempo Scale", ScaleText(Engine.scale))
  Log(1, "Tempo scale " .. ScaleText(Engine.scale))
end
SetString("Tempo Scale", ScaleText(1))

Controls.Tap.EventHandler = function() Engine:Tap(Clock()) end
Controls.Half.EventHandler = function() SetScale(Engine.scale / 2) end
Controls.Double.EventHandler = function() SetScale(Engine.scale * 2) end
Controls.Resync.EventHandler = function() Engine:Resync(Clock()); Log(1, "Resync") end
Controls["Shift Half Beat"].EventHandler = function() Engine:ShiftHalf(); Log(1, "Shift half beat") end

---------------------------------------------------------------------------
-- Level sources
---------------------------------------------------------------------------
local Level = { db = -100, changes = 0, lastChange = -100, rate = 0, rateT = 0, problem = nil }

-- Named component: resolved lazily, re-resolved when the names change
local Named = { comp = nil, ctl = nil, key = nil, nextTry = 0 }
local function ResolveNamed(now)
  local compName, ctlName = Text("Meter Component"), Text("Meter Control")
  local key = compName .. "|" .. ctlName
  if key == Named.key and (Named.ctl or now < Named.nextTry) then return Named.ctl end
  Named.key, Named.ctl, Named.nextTry = key, nil, now + 2
  if compName == "" then
    Level.problem = "No meter component name set (Setup)"
    return nil
  end
  local ok, comp = pcall(function() return Component.New(compName) end)
  if not ok or not comp then
    Level.problem = ("Component '%s' not found - check its Code Name and Script Access"):format(compName)
    return nil
  end
  local ok2, ctl = pcall(function() return comp[ctlName] end)
  if not ok2 or not ctl then
    Level.problem = ("Control '%s' not found in '%s'"):format(ctlName, compName)
    return nil
  end
  Named.comp, Named.ctl = comp, ctl
  Level.problem = nil
  Log(1, ("Reading level from %s / %s"):format(compName, ctlName))
  return ctl
end

-- Test generator: kicks at "Test BPM" with jitter, dropouts and a breakdown switch,
-- sampled like a meter that updates every "Test Update" ms.
local Gen = { nextKick = nil, lastKick = -10, nextUpdate = 0, db = -45 }
local function GeneratorLevel(now)
  local bpm = math.max(40, Num("Test BPM", 128))
  local P = 60 / bpm
  if not Gen.nextKick or Gen.nextKick < now - 1 then Gen.nextKick = now + 0.2 end
  while now >= Gen.nextKick do
    local breakdown = Controls["Test Breakdown"].Boolean
    if not breakdown and math.random() * 100 >= Num("Test Dropout", 10) then
      Gen.lastKick = Gen.nextKick + (math.random() * 2 - 1) * Num("Test Jitter", 5) / 1000
    end
    Gen.nextKick = Gen.nextKick + P
  end
  if now >= Gen.nextUpdate then
    local age = now - Gen.lastKick
    local floor = Controls["Test Breakdown"].Boolean and -30 or -45
    local kick = (age >= 0 and age < 0.18) and (-8 - age / 0.18 * 37) or -100
    Gen.db = math.max(kick, floor) + (math.random() * 3 - 1.5)
    Gen.nextUpdate = now + math.max(0.01, Num("Test Update", 20) / 1000)
  end
  return Gen.db
end

local function ReadLevel(now)
  if Opt.LevelSource == "Test Generator" then
    Level.problem = nil
    return GeneratorLevel(now)
  elseif Opt.LevelSource == "Named Component" then
    local ctl = ResolveNamed(now)
    if not ctl then return -100 end
    local ok, v = pcall(function() return ctl.Value end)
    return ok and tonumber(v) or -100
  else
    return Num("Level In", -100)
  end
end

---------------------------------------------------------------------------
-- Console output
---------------------------------------------------------------------------
local NextUi = 0
local Out = nil
local OutState = { code = STATUS.OK, text = "Detection only", connected = false, loggedIn = false }
local LastSentBpm = nil

if Opt.Console ~= "None" then
  Out = MAOutput.New(Opt.Console, {
    Log = Log,
    OnState = function(s)
      local wasReady = OutState.code == STATUS.OK and OutState.loggedIn
      OutState = s
      NextUi = 0          -- show the new status on the next tick
      SetBool("Connected", s.connected)
      SetBool("Logged In", s.loggedIn)
      if s.code == STATUS.OK and s.loggedIn and not wasReady then
        LastSentBpm = nil   -- (re)connected: send the current tempo again
      end
    end,
    OnReply = function(line) SetString("Last Reply", line) end,
    OnError = function(text) SetError(text) end,
    OnSent = function(cmd) SetString("Last Command", cmd) end,
  })
  local function ConfigureOut()
    Out:Configure({
      ip = Text("IP Address"), port = Num("Port", 0),
      user = Text("Username"), pass = Ctl("Password") and Controls.Password.String or "",
      prefix = Text("OSC Prefix"),
    })
  end
  for _, name in ipairs({ "IP Address", "Port", "Username", "Password", "OSC Prefix" }) do
    if Ctl(name) then Ctl(name).EventHandler = ConfigureOut end
  end
  if Ctl("Reconnect") then Controls.Reconnect.EventHandler = function() Out:Reconnect() end end
  ConfigureOut()
end

local function FormatBpm(bpm) return ("%.1f"):format(bpm) end

local function TempoCommand(bpm)
  local template = Text("Command Template")
  if not template:find("{bpm}", 1, true) then
    SetError("Command Template needs a {bpm} placeholder")
    return nil
  end
  return (template:gsub("{master}", tostring(math.floor(Num("Speed Master", 1))))
                  :gsub("{bpm}", FormatBpm(bpm)))
end

local function SendTempo(bpm, reason)
  local cmd = TempoCommand(bpm)
  if not cmd then return end
  Out:Send(cmd, "tempo")
  LastSentBpm = math.floor(bpm * 10 + 0.5) / 10
  SetString("Last Sent", FormatBpm(LastSentBpm) .. " BPM")
  Log(1, ("Tempo %s BPM (%s)"):format(FormatBpm(LastSentBpm), reason))
end

local function CheckSend(now)
  if not Out or not Controls["Send Enable"].Boolean or not Out:IsReady() then return end
  if Engine.hold then return end
  local bpm = Engine:Bpm()
  if not bpm or not Engine:IsPrecise(now) then return end
  local rounded = math.floor(bpm * 10 + 0.5) / 10
  if LastSentBpm == nil or math.abs(rounded - LastSentBpm) >= Num("Send Hysteresis", 0.5) then
    SendTempo(rounded, LastSentBpm == nil and "locked" or "changed")
  end
end

if Ctl("Send Now") then
  Controls["Send Now"].EventHandler = function()
    local bpm = Engine:Bpm()
    if not bpm then SetError("No tempo to send yet"); return end
    if not Out:IsReady() then SetError("Console not ready") end
    SendTempo(bpm, "manual")
  end
end

---------------------------------------------------------------------------
-- Display
---------------------------------------------------------------------------
local Pulse = { beatOff = 0, downOff = 0, onsetOff = 0 }

local function UpdateDisplay(now)
  local bpm = Engine:Bpm()
  SetValue("BPM", bpm and math.floor(bpm * 10 + 0.5) / 10 or 0, 0.01)
  SetString("BPM Text", bpm and FormatBpm(bpm) or "---")
  local locked = Engine:IsLocked(now)
  SetBool("Locked", locked)
  SetString("Detection State", Engine:State(now))
  SetValue("Confidence", math.floor(Engine.confidence * 100 + 0.5))
  SetValue("Input Level", math.max(-60, math.min(0, Level.db)), 0.1)
  SetValue("Onset Strength", math.min(40, Engine.strength), 0.1)
  SetString("Onset Threshold", ("%.1f dB"):format(Engine.threshold))
  SetString("Onset Count", tostring(Engine.onsetCount))
  SetString("Level Updates", ("%d/s (clock: %s)"):format(Level.rate, ClockSource))
  local parts = {}
  for _, c in ipairs(Engine:Candidates(3)) do
    parts[#parts + 1] = ("%.1f (%d%%)"):format(c.bpm, math.floor(c.share * 100 + 0.5))
  end
  SetString("Tempo Candidates", table.concat(parts, "  "))
end

local function UpdateStatus(now)
  local audio = Level.problem
  if not audio and Opt.LevelSource ~= "Test Generator" and now - Level.lastChange > NO_LEVEL_WARN then
    audio = Opt.LevelSource == "Wired Pin" and "No level updates on the Level In pin" or "No level updates from the meter"
  end
  local code, text = OutState.code, OutState.text
  if audio then
    if code == STATUS.OK then code = STATUS.Compromised end
    text = (Out and (text .. " | ") or "") .. audio
  elseif not Out then
    text = "Detection only"
  end
  SetStatus(code, text)
end

---------------------------------------------------------------------------
-- Main timer
---------------------------------------------------------------------------
local MainTimer = Timer.New()
-- Keep long-lived objects reachable from a global. A timer that is only held by
-- a local variable gets garbage collected on the Core and silently stops.
Sound2BeatRuntime = { Timer = MainTimer, Engine = Engine, Out = Out }

local function OnTick()
  TickTime = TickTime + TICK
  local now = Clock()

  -- level in, onsets
  local db = ReadLevel(now)
  if db ~= Level.db then
    Level.changes = Level.changes + 1
    Level.lastChange = now
    Level.db = db
  end
  if now - Level.rateT >= 1 then
    Level.rate = math.floor(Level.changes / (now - Level.rateT) + 0.5)
    Level.changes, Level.rateT = 0, now
  end
  if Engine:Feed(now, db) then
    SetBool("Onset", true)
    Pulse.onsetOff = now + 0.06
    if DebugLevel >= 2 then Log(2, ("Onset %.1f dB (threshold %.1f)"):format(Engine.strength, Engine.threshold)) end
  end

  -- beat clock; a positive Beat Offset fires the beat earlier
  local lead = Num("Beat Offset", 0) / 1000
  for _, ev in ipairs(Engine:Update(now, lead)) do
    local P = Engine:ClockPeriod() or 0.5
    local len = math.max(0.05, math.min(0.15, P * 0.35))
    SetBool("Beat", true)
    Pulse.beatOff = now + len
    for i = 1, 4 do SetBool("Bar " .. i, i == ev.bar) end
    SetValue("Bar Position", ev.bar)
    if ev.bar == 1 then
      SetBool("Downbeat", true)
      Pulse.downOff = now + len
    end
  end
  if now >= Pulse.beatOff then SetBool("Beat", false) end
  if now >= Pulse.downOff then SetBool("Downbeat", false) end
  if now >= Pulse.onsetOff then SetBool("Onset", false) end
  if not Engine:Bpm() then
    for i = 1, 4 do SetBool("Bar " .. i, false) end
  end

  -- output
  CheckSend(now)
  if Out then Out:Tick(now) end

  if now >= NextUi then
    NextUi = now + UI_INTERVAL
    UpdateDisplay(now)
    UpdateStatus(now)
  end
end

MainTimer.EventHandler = function()
  local ok, err = pcall(OnTick)
  if not ok then
    SetError("Runtime error: " .. tostring(err))
    Log(1, "Runtime error: " .. tostring(err))
  end
end

---------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------
SetStatus(STATUS.Initializing, "Starting")
Level.rateT, Level.lastChange = Clock(), Clock()
Log(1, ("Sound2Beat %s started: source %s, console %s, clock %s"):format(
  PluginInfo.BuildVersion, Opt.LevelSource, Opt.Console, ClockSource))
MainTimer:Start(TICK)
