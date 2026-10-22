-- (c) levo AVL | Elias Jenny - MIT License
-- Runtime code: only runs on the Core or in Emulation mode. No network, pure logic.

local DebugLevel = ({ None = 0, Basic = 1, Verbose = 2 })[Properties["Debug Print"].Value] or 0
local Cfg = PickerConfig(Properties)

local TICK = 0.05          -- timer resolution (s), also the fade step
local FEEDBACK_HOLD = 1.0  -- after writing the console link, link input is only checked after this time
local FEEDBACK_TOL = 0.6   -- link input within this many % of what was sent counts as our own echo
local DEFAULT_WHITE, DEFAULT_AMBER = "#FFFFFF", "#FFBF00"
local EMPTY_SWATCH = string.format("#%02X%02X%02X", table.unpack(LevoBrand.Colors.Line))

local Now = 0              -- monotonic time in seconds, advanced by the main timer

local function Log(level, msg)
  if level <= DebugLevel then print(("[Color Picker] %s"):format(msg)) end
end

---------------------------------------------------------------------------
-- Control helpers (only write when the value changes)
---------------------------------------------------------------------------
local function SetValue(name, v)
  local c = Controls[name]
  if c and math.abs(c.Value - v) > 1e-6 then c.Value = v end
end

local function SetString(name, s)
  local c = Controls[name]
  if c and c.String ~= s then c.String = s end
end

local SwatchColors = {}  -- control name -> colour written last (avoid redundant writes)
local function SetSwatch(name, hex)
  if SwatchColors[name] ~= hex then
    SwatchColors[name] = hex
    Controls[name].Color = hex
  end
end

local STATUS = { OK = 0, Compromised = 1, Fault = 2, NotPresent = 3, Missing = 4, Initializing = 5 }
local function SetStatus(value, text)
  local c = Controls.Status
  if c.Value ~= value then c.Value = value end
  if c.String ~= text then c.String = text end
end

local function Warn(text)
  SetStatus(STATUS.Compromised, text)
  Log(1, "Warning: " .. text)
end

local function NormalizeHex(s)
  local r, g, b = ColorMath.ParseHex(s)
  if r then return ColorMath.ToHex(r, g, b) end
  return nil
end

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
-- Colour at full brightness of the dimmer: r, g, b 0..1; dim 0..1.
-- hue / sat are kept separately so they survive greys and black.
local State = { r = 1, g = 1, b = 1, dim = 1, hue = 0, sat = 0 }
local Fade = nil                 -- { from = {r,g,b}, to = {r,g,b}, t0, dur }
local LinkSent = {}              -- link channel -> last value written (%)
local LinkWrittenAt = -math.huge
local LinkPending = false        -- link input arrived during the hold time
local MixOpts = { subtract = Cfg.Subtract, white = { 1, 1, 1 }, amber = { 1, 0.749, 0 } }

local function Round2(x) return math.floor(x * 100 + 0.5) / 100 end

---------------------------------------------------------------------------
-- Outputs and display
---------------------------------------------------------------------------
local function WriteOutputs(writeLink)
  local r, g, b = State.r, State.g, State.b
  local scale = Cfg.SeparateDimmer and 1 or State.dim
  for _, lay in ipairs(OutputLayouts) do
    local mix = ColorMath.Mix(r, g, b, lay, MixOpts)
    for ch in lay:gmatch(".") do SetValue(lay .. " " .. ch, ColorMath.To255(mix[ch] * scale)) end
  end
  if Cfg.SeparateDimmer then SetValue("Dimmer Level", ColorMath.To255(State.dim)) end

  if writeLink and #Cfg.LinkChannels > 0 then
    local mix = ColorMath.Mix(r, g, b, Cfg.LinkLayout, MixOpts)
    for _, ch in ipairs(Cfg.LinkChannels) do
      local v = (ch == "D") and State.dim or mix[ch] * scale
      v = Round2(ColorMath.Clamp01(v) * 100)
      LinkSent[ch] = v
      SetValue("Link " .. ChannelNames[ch], v)
    end
    LinkWrittenAt = Now
  end
end

-- skip: "rgb" / "hsv" = the user is moving these controls, don't write them back
local function ShowColor(skip)
  local r, g, b = State.r, State.g, State.b
  local hex = ColorMath.ToHex(r, g, b)
  SetString("Hex", hex)
  if skip ~= "rgb" then
    SetValue("Red", ColorMath.To255(r))
    SetValue("Green", ColorMath.To255(g))
    SetValue("Blue", ColorMath.To255(b))
  end
  local h, s, v = ColorMath.RgbToHsv(r, g, b)
  if skip ~= "hsv" then
    if v > 0.002 then
      if s > 0.002 then State.hue = h end
      State.sat = s
    end
    SetValue("Hue", math.floor(State.hue + 0.5))
    SetValue("Saturation", Round2(State.sat * 100))
    SetValue("Brightness", Round2(v * 100))
  end
  SetValue("Dimmer", Round2(State.dim * 100))
  SetSwatch("Preview", hex)
end

local function ClearWarning()
  if Controls.Status.Value ~= STATUS.OK then SetStatus(STATUS.OK, "OK") end
end

-- Set a new colour. opts.fade: use the fade time (discrete selections),
-- opts.skip: see ShowColor.
local function ApplyColor(r, g, b, opts)
  opts = opts or {}
  r, g, b = ColorMath.Clamp01(r), ColorMath.Clamp01(g), ColorMath.Clamp01(b)
  ClearWarning()
  local dur = opts.fade and Controls["Fade Time"].Value or 0
  if dur >= TICK then
    Fade = { from = { State.r, State.g, State.b }, to = { r, g, b }, t0 = Now, dur = dur }
    Log(2, ("Fade to %s in %.1f s"):format(ColorMath.ToHex(r, g, b), dur))
    return
  end
  Fade = nil
  State.r, State.g, State.b = r, g, b
  ShowColor(opts.skip)
  WriteOutputs(true)
  Log(2, "Color " .. ColorMath.ToHex(r, g, b))
end

local function FadeStep()
  local t = math.min(1, (Now - Fade.t0) / Fade.dur)
  local f, to = Fade.from, Fade.to
  State.r = f[1] + (to[1] - f[1]) * t
  State.g = f[2] + (to[2] - f[2]) * t
  State.b = f[3] + (to[3] - f[3]) * t
  if t >= 1 then Fade = nil end
  ShowColor()
  WriteOutputs(true)
end

---------------------------------------------------------------------------
-- Console link feedback
---------------------------------------------------------------------------
local function LinkName(ch) return "Link " .. ChannelNames[ch] end

-- true when every link input still matches what we wrote (= our own echo)
local function LinkInSync()
  for _, ch in ipairs(Cfg.LinkChannels) do
    local sent = LinkSent[ch]
    if sent == nil or math.abs(Controls[LinkName(ch)].Value - sent) > FEEDBACK_TOL then return false end
  end
  return true
end

-- The console changed: take its levels as the new colour without writing back.
local function AdoptLink()
  local ch = {}
  for _, k in ipairs(Cfg.LinkChannels) do
    local v = Controls[LinkName(k)].Value
    ch[k] = ColorMath.Clamp01(v / 100)
    LinkSent[k] = v
  end
  local r, g, b = ColorMath.Unmix(ch, MixOpts)
  local dim = State.dim
  if Cfg.SeparateDimmer then
    if ch.D then dim = ch.D end
  else
    -- Console levels include the dimmer: divide it out, raise the dimmer if the
    -- console is brighter than the dimmer allows. All channels at 0 = dimmer 0,
    -- the colour is kept.
    local m = math.max(r, g, b)
    if m <= 0.002 then
      dim, r, g, b = 0, State.r, State.g, State.b
    else
      if m > dim then dim = m end
      r, g, b = r / dim, g / dim, b / dim
    end
  end
  Fade = nil
  State.r, State.g, State.b = ColorMath.Clamp01(r), ColorMath.Clamp01(g), ColorMath.Clamp01(b)
  State.dim = ColorMath.Clamp01(dim)
  ShowColor()
  WriteOutputs(false)
  Log(1, ("Console link changed -> %s, dimmer %d %%"):format(ColorMath.ToHex(State.r, State.g, State.b),
    math.floor(State.dim * 100 + 0.5)))
end

local function OnLinkInput(ctl)
  if LinkInSync() then return end  -- echo of our own write
  if Fade or (Now - LinkWrittenAt) < FEEDBACK_HOLD then
    LinkPending = true             -- console may still report old values, check later
    Log(2, "Link input held during fade/hold time")
    return
  end
  AdoptLink()
end

---------------------------------------------------------------------------
-- LED calibration
---------------------------------------------------------------------------
local function LoadEmitter(name, key, default, warn)
  local c = Controls[name]
  local hex = NormalizeHex(c.String)
  if not hex then
    if warn and c.String ~= "" then Warn(("%s: invalid hex '%s'"):format(name, c.String)) end
    hex = MixOpts[key .. "Hex"] or default
  end
  SetString(name, hex)
  MixOpts[key .. "Hex"] = hex
  MixOpts[key] = { ColorMath.ParseHex(hex) }
end

---------------------------------------------------------------------------
-- User presets
---------------------------------------------------------------------------
local function ShowUser(i)
  local hex = NormalizeHex(Controls["User " .. i .. " Hex"].String)
  SetSwatch("User " .. i .. " Swatch", hex or EMPTY_SWATCH)
  SetString("User " .. i .. " Swatch", hex and "" or "empty")
end

---------------------------------------------------------------------------
-- Event handlers
---------------------------------------------------------------------------
Controls.Hex.EventHandler = function(c)
  local r, g, b = ColorMath.ParseHex(c.String)
  if not r then
    Warn(("Invalid hex '%s'"):format(c.String))
    SetString("Hex", ColorMath.ToHex(State.r, State.g, State.b))
    return
  end
  ApplyColor(r, g, b, { fade = true })
end

local function OnRgb()
  ApplyColor(Controls.Red.Value / 255, Controls.Green.Value / 255, Controls.Blue.Value / 255, { skip = "rgb" })
end
Controls.Red.EventHandler = OnRgb
Controls.Green.EventHandler = OnRgb
Controls.Blue.EventHandler = OnRgb

local function OnHsv()
  State.hue = Controls.Hue.Value
  State.sat = Controls.Saturation.Value / 100
  local r, g, b = ColorMath.HsvToRgb(State.hue, State.sat, Controls.Brightness.Value / 100)
  ApplyColor(r, g, b, { skip = "hsv" })
end
Controls.Hue.EventHandler = OnHsv
Controls.Saturation.EventHandler = OnHsv
Controls.Brightness.EventHandler = OnHsv

Controls.Kelvin.EventHandler = function(c)
  ApplyColor(ColorMath.Kelvin(c.Value))
end

Controls.Dimmer.EventHandler = function(c)
  State.dim = ColorMath.Clamp01(c.Value / 100)
  WriteOutputs(true)
end

for i, p in ipairs(ColorPresets) do
  local r, g, b = ColorMath.ParseHex(p.Hex)
  Controls["Preset " .. i].EventHandler = function()
    Log(1, "Preset " .. p.Name)
    ApplyColor(r, g, b, { fade = true })
  end
end

for row = 1, Cfg.GridRows do
  for col = 1, Cfg.GridColumns + 1 do
    local r, g, b = GridColor(row, col, Cfg.GridRows, Cfg.GridColumns)
    Controls[("Grid %d.%d"):format(row, col)].EventHandler = function()
      ApplyColor(r, g, b, { fade = true })
    end
  end
end

for i = 1, Cfg.UserPresets do
  local hexName = "User " .. i .. " Hex"
  Controls["User " .. i].EventHandler = function()
    if Controls.Store.Boolean then
      local hex = ColorMath.ToHex(State.r, State.g, State.b)
      SetString(hexName, hex)
      Controls.Store.Boolean = false
      ShowUser(i)
      Log(1, ("User %d stored: %s"):format(i, hex))
      return
    end
    local r, g, b = ColorMath.ParseHex(Controls[hexName].String)
    if not r then
      Log(1, ("User %d is empty"):format(i))
      return
    end
    Log(1, ("User %d recalled"):format(i))
    ApplyColor(r, g, b, { fade = true })
  end
  Controls[hexName].EventHandler = function(c)
    if c.String ~= "" then
      local hex = NormalizeHex(c.String)
      if hex then SetString(hexName, hex) else Warn(("User %d: invalid hex '%s'"):format(i, c.String)) end
    end
    ShowUser(i)
  end
end

Controls["White LED Color"].EventHandler = function()
  LoadEmitter("White LED Color", "white", DEFAULT_WHITE, true)
  WriteOutputs(true)
end
Controls["Amber LED Color"].EventHandler = function()
  LoadEmitter("Amber LED Color", "amber", DEFAULT_AMBER, true)
  WriteOutputs(true)
end

for _, ch in ipairs(Cfg.LinkChannels) do
  Controls[LinkName(ch)].EventHandler = OnLinkInput
end

---------------------------------------------------------------------------
-- Timer: fades and delayed link checks
---------------------------------------------------------------------------
local MainTimer = Timer.New()
MainTimer.EventHandler = function()
  Now = Now + TICK
  if Fade then FadeStep() end
  if LinkPending and not Fade and (Now - LinkWrittenAt) >= FEEDBACK_HOLD then
    LinkPending = false
    if not LinkInSync() then AdoptLink() end
  end
end

---------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------
SetStatus(STATUS.Initializing, "Starting")
LoadEmitter("White LED Color", "white", DEFAULT_WHITE, false)
LoadEmitter("Amber LED Color", "amber", DEFAULT_AMBER, false)

-- Control values persist with the design / on the Core. An empty Hex field means
-- a fresh instance: start with white at full level.
local r, g, b = ColorMath.ParseHex(Controls.Hex.String)
if r then
  State.r, State.g, State.b = r, g, b
  State.dim = ColorMath.Clamp01(Controls.Dimmer.Value / 100)
  State.hue = Controls.Hue.Value
  State.sat = Controls.Saturation.Value / 100
  Log(1, "Restored " .. ColorMath.ToHex(r, g, b))
else
  State.dim = 1
  SetValue("Kelvin", 5600)
  Log(1, "Fresh instance, starting with white")
end
for i = 1, Cfg.UserPresets do ShowUser(i) end
ShowColor()
WriteOutputs(false)  -- the console keeps its state on start; its feedback is adopted when it arrives

MainTimer:Start(TICK)
SetStatus(STATUS.OK, "OK")
Log(1, ("Started, build %s - link %s, %d user preset(s)"):format(
  PluginInfo.BuildVersion, Cfg.LinkLayout, Cfg.UserPresets))
