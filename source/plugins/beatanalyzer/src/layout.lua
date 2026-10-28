-- (c) levo AVL | Elias Jenny - MIT License
local C = LevoBrand.Colors
local opt = Options(props)
local hasConsole = opt.Console ~= "None"
local W = 520
local M = 16  -- page margin

-- Content is collected first; background and header go underneath once the page
-- height is known.
local items = {}

local function Label(text, x, y, w, h, o)
  o = o or {}
  table.insert(items, {
    Type = "Text", Text = text, Position = { x, y }, Size = { w, h or 18 },
    FontSize = o.size or 11, FontStyle = o.style or "Regular",
    HTextAlign = o.align or "Left", Color = o.color or C.Onyx,
  })
end

local function Section(text, y)
  Label(text, M, y, W - 2 * M, 20, { size = 13, style = "Bold", color = C.Atlantic })
  table.insert(items, {
    Type = "GroupBox", Fill = C.Amber, StrokeWidth = 0, CornerRadius = 0,
    Position = { M, y + 20 }, Size = { W - 2 * M, 2 },
  })
  return y + 30
end

local function Place(name, pretty, x, y, w, h, extra)
  local def = { PrettyName = pretty, Position = { x, y }, Size = { w, h } }
  for k, v in pairs(extra or {}) do def[k] = v end
  layout[name] = def
end

-- read-only text that should look like a label, not like a field
local function Flat(extra)
  local t = { Style = "Text", Color = C.Porcelain, StrokeWidth = 0, CornerRadius = 0, TextColor = C.Onyx }
  for k, v in pairs(extra or {}) do t[k] = v end
  return t
end

-- label left, control right; returns next y
local LW = 150
local function Row(label, name, pretty, y, w, extra, h)
  h = h or 20
  Label(label, M, y + (h - 18) // 2, LW - 8, 18, { align = "Right" })
  Place(name, pretty, M + LW, y, w, h, extra)
  return y + h + 6
end

local function Field(extra)
  local t = { Style = "Text", FontSize = 11 }
  for k, v in pairs(extra or {}) do t[k] = v end
  return t
end

local function Button(legend, extra)
  local t = { Style = "Button", Legend = legend, FontSize = 11, Color = C.Atlantic }
  for k, v in pairs(extra or {}) do t[k] = v end
  return t
end

local y = LevoBrand.HeaderHeight + 2 + 12

if CurrentPage == "Control" then
  -- Tempo overview
  y = Section("Tempo", y)
  Place("BPM Text", "Tempo~BPM", M, y, 250, 72, Flat({ FontSize = 56, FontStyle = "Bold", HTextAlign = "Left" }))
  Label("BPM", M + 4, y + 70, 60, 16, { size = 10, color = C.Mid })
  Place("Beat", "Tempo~Beat", W - M - 84, y + 2, 72, 72, { Color = C.Amber })
  Label("Beat", W - M - 84, y + 76, 72, 16, { size = 10, color = C.Mid, align = "Center" })
  y = y + 98
  -- bar position 1..4
  Label("Bar", M, y, 40, 22, { color = C.Mid })
  for i = 1, 4 do
    local x = M + 44 + (i - 1) * 44
    Place("Bar " .. i, "Tempo~Bar " .. i, x, y, 22, 22, { Color = i == 1 and C.Amber or C.Atlantic })
    Label(tostring(i), x - 4, y + 22, 30, 14, { size = 10, color = C.Mid, align = "Center" })
  end
  Place("Locked", "Tempo~Locked", W - M - 150, y + 2, 18, 18, { Color = C.Atlantic })
  Place("Detection State", "Tempo~Detection State", W - M - 126, y, 126, 22, Flat({ FontSize = 12, FontStyle = "Bold", HTextAlign = "Left" }))
  y = y + 44
  Label("Confidence", M, y, 80, 18, { color = C.Mid })
  Place("Confidence", "Tempo~Confidence", M + 84, y + 3, 180, 12, { Color = C.Atlantic, ShowTextbox = false, CornerRadius = 0 })
  Label("Kick", W - M - 200, y, 44, 18, { color = C.Mid, align = "Right" })
  Place("Kick Meter", "Tempo~Kick Meter", W - M - 150, y + 3, 150, 12, { Color = C.Amber, ShowTextbox = false, CornerRadius = 0 })
  y = y + 30

  -- Manual control
  y = Section("Tempo Control", y)
  Place("Tap", "Tempo Control~Tap", M, y, 110, 52, Button("TAP", { FontSize = 16, FontStyle = "Bold", Color = C.Amber }))
  local bx, bw = M + 122, 84
  Place("Resync", "Tempo Control~Resync", bx, y, bw, 24, Button("Resync"))
  Place("Shift Half Beat", "Tempo Control~Shift Half Beat", bx + bw + 8, y, bw, 24, Button("Shift ½"))
  Place("Auto", "Tempo Control~Auto", bx + 2 * (bw + 8), y, bw, 24, Button("Auto", { Color = C.Amber }))
  Place("Half", "Tempo Control~Half", bx, y + 28, bw, 24, Button("½ Tempo"))
  Place("Double", "Tempo Control~Double", bx + bw + 8, y + 28, bw, 24, Button("2× Tempo"))
  Place("Hold", "Tempo Control~Hold", bx + 2 * (bw + 8), y + 28, bw, 24, Button("Hold", { Color = C.Amber }))
  Place("Tempo Scale", "Tempo Control~Tempo Scale", W - M - 40, y + 28, 40, 24, Flat({ FontSize = 11, HTextAlign = "Center", TextColor = C.Mid }))
  y = y + 66

  -- Console
  y = Section(hasConsole and opt.Console or "Output", y)
  if hasConsole then
    Place("Send Enable", "Console~Send Enable", M, y, 110, 24, Button("Send Tempo", { Color = C.Amber }))
    Place("Send Now", "Console~Send Now", M + 118, y, 84, 24, Button("Send Now"))
    Label("Last sent", M + 214, y + 3, 64, 18, { color = C.Mid })
    Place("Last Sent", "Console~Last Sent", M + 280, y, W - 2 * M - 280, 24, Flat({ FontSize = 13, FontStyle = "Bold", HTextAlign = "Left" }))
    y = y + 32
  end
  Place("Status", "Status", M, y, W - 2 * M, 22)
  y = y + 34

elseif CurrentPage == "Setup" then
  y = Section("Level Input", y)
  if opt.LevelSource == "Wired Pin" then
    y = Row("Kick Level (dB)", "Kick Level", "Level Input~Kick Level", y, 80, { Style = "Text", FontSize = 11 })
    Label("Wire a meter's output pin here (kick band, e.g. 45-120 Hz).", M + LW, y - 4, W - M - LW - M, 16, { size = 10, color = C.Mid })
    y = y + 16
    if opt.Bands == 2 then
      y = Row("Snare Level (dB)", "Snare Level", "Level Input~Snare Level", y, 80, { Style = "Text", FontSize = 11 })
      Label("Snare band, e.g. 150-400 Hz (a hi-hat band works too).", M + LW, y - 4, W - M - LW - M, 16, { size = 10, color = C.Mid })
      y = y + 16
    end
  elseif opt.LevelSource == "Named Component" then
    y = Row("Kick Component", "Kick Component", "Level Input~Kick Component", y, 200, Field())
    y = Row("Kick Control", "Kick Control", "Level Input~Kick Control", y, 200, Field())
    Label("Code Name of the meter, Script Access enabled. Control: e.g. meter.1", M + LW, y - 4, W - M - LW - M, 16, { size = 10, color = C.Mid })
    y = y + 16
    if opt.Bands == 2 then
      y = Row("Snare Component", "Snare Component", "Level Input~Snare Component", y, 200, Field())
      y = Row("Snare Control", "Snare Control", "Level Input~Snare Control", y, 200, Field())
    end
  else
    Label("Test Generator active - settings on the Debug page.", M + LW, y, W - M - LW - M, 18, { color = C.Mid })
    y = y + 26
  end
  if opt.Bands == 2 then
    y = Row("Snare Weight", "Snare Weight", "Level Input~Snare Weight", y, 180, { Style = "Fader", Color = C.Atlantic })
    Label("Snare", M + LW + 190, y - 26, 50, 18, { color = C.Mid })
    Place("Snare Meter", "Level Input~Snare Meter", M + LW + 240, y - 23, W - 2 * M - LW - 240, 12, { Color = C.Amber, ShowTextbox = false, CornerRadius = 0 })
  end
  y = y + 6

  y = Section("Detection", y)
  y = Row("BPM Min", "BPM Min", "Detection~BPM Min", y, 80, Field())
  y = Row("BPM Max", "BPM Max", "Detection~BPM Max", y, 80, Field())
  y = Row("Sensitivity", "Sensitivity", "Detection~Sensitivity", y, 180, { Style = "Fader", Color = C.Atlantic })
  y = Row("Min Confidence", "Min Confidence", "Detection~Min Confidence", y, 180, { Style = "Fader", Color = C.Atlantic })
  y = Row("Beat Offset (ms)", "Beat Offset", "Detection~Beat Offset", y, 80, Field())
  Label("Positive = beat earlier (compensates meter latency).", M + LW, y - 4, W - M - LW - M, 16, { size = 10, color = C.Mid })
  y = y + 22

  if hasConsole then
    y = Section(opt.Console .. (opt.Console == "grandMA2" and " (Telnet)" or " (OSC)"), y)
    y = Row("IP Address", "IP Address", "Console~IP Address", y, 160, Field())
    y = Row("Port", "Port", "Console~Port", y, 80, Field())
    if opt.Console == "grandMA2" then
      y = Row("Username", "Username", "Console~Username", y, 160, Field())
      y = Row("Password", "Password", "Console~Password", y, 160, Field())
    else
      y = Row("OSC Prefix", "OSC Prefix", "Console~OSC Prefix", y, 160, Field())
    end
    y = Row("Speed Master", "Speed Master", "Console~Speed Master", y, 80, Field())
    y = Row("Command", "Command Template", "Console~Command Template", y, W - M - LW - M, Field())
    Label("{master} and {bpm} are replaced.", M + LW, y - 4, W - M - LW - M, 16, { size = 10, color = C.Mid })
    y = y + 16
    y = Row("Send Hysteresis", "Send Hysteresis", "Console~Send Hysteresis", y, 80, Field())
    y = Row("Whole BPM", "Whole BPM", "Console~Whole BPM", y, 80, Button("Whole BPM", { Color = C.Amber }))
    if opt.Console == "grandMA2" then
      Label("Connected", M + LW, y, 70, 18)
      Place("Connected", "Console~Connected", M + LW + 72, y + 1, 16, 16, { Color = C.Atlantic })
      Label("Logged in", M + LW + 100, y, 70, 18)
      Place("Logged In", "Console~Logged In", M + LW + 172, y + 1, 16, 16, { Color = C.Atlantic })
      Place("Reconnect", "Console~Reconnect", W - M - 90, y - 2, 90, 22, Button("Reconnect"))
      y = y + 28
    end
  end
  Place("Status", "Status", M, y, W - 2 * M, 22)
  y = y + 34

elseif CurrentPage == "Debug" then
  y = Section("Analysis", y)
  y = Row("Level Updates", "Level Updates", "Debug~Level Updates", y, 240, Flat({ HTextAlign = "Left" }))
  Label("Onset", M, y, LW - 8, 18, { align = "Right" })
  Place("Onset", "Debug~Onset", M + LW, y + 1, 16, 16, { Color = C.Amber })
  y = y + 26
  y = Row("Onset Strength", "Onset Strength", "Debug~Onset Strength", y, 240, { Color = C.Atlantic, ShowTextbox = false, CornerRadius = 0 }, 14)
  y = Row("Threshold", "Onset Threshold", "Debug~Onset Threshold", y, 120, Flat({ HTextAlign = "Left" }))
  y = Row("Onsets", "Onset Count", "Debug~Onset Count", y, 120, Flat({ HTextAlign = "Left" }))
  y = Row("Tempo Candidates", "Tempo Candidates", "Debug~Tempo Candidates", y, W - M - LW - M, Flat({ HTextAlign = "Left" }))
  y = Row("Bar Position", "Bar Position", "Debug~Bar Position", y, 60, Field())
  y = Row("BPM (value)", "BPM", "Debug~BPM", y, 80, Field())
  y = Row("Downbeat", "Downbeat", "Debug~Downbeat", y, 16, { Color = C.Amber }, 16)
  y = y + 6

  y = Section("Messages", y)
  if hasConsole then
    y = Row("Last Command", "Last Command", "Debug~Last Command", y, W - M - LW - M, Flat({ HTextAlign = "Left" }))
    y = Row("Last Reply", "Last Reply", "Debug~Last Reply", y, W - M - LW - M, Flat({ HTextAlign = "Left" }))
  end
  y = Row("Last Error", "Last Error", "Debug~Last Error", y, W - M - LW - M, Flat({ HTextAlign = "Left" }))
  y = y + 6

  if opt.LevelSource == "Test Generator" then
    y = Section("Test Generator", y)
    y = Row("Test BPM", "Test BPM", "Test Generator~Test BPM", y, 80, Field())
    y = Row("Jitter (ms)", "Test Jitter", "Test Generator~Test Jitter", y, 80, Field())
    y = Row("Dropout", "Test Dropout", "Test Generator~Test Dropout", y, 80, Field())
    y = Row("Meter Update (ms)", "Test Update", "Test Generator~Test Update", y, 80, Field())
    y = Row("Breakdown", "Test Breakdown", "Test Generator~Test Breakdown", y, 90, Button("Breakdown", { Color = C.Amber }))
  end
  y = y + 10

elseif CurrentPage == "About" then
  y = LevoBrand.About(items, M, y, W - 2 * M, PluginInfo) + 16
end

-- background and header underneath the content
local H = math.max(y, 300)
LevoBrand.Background(graphics, W, H)
LevoBrand.Header(graphics, W, LevoBrand.PluginName(PluginInfo), CurrentPage)
for _, g in ipairs(items) do table.insert(graphics, g) end
