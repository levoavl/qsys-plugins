-- (c) levo AVL | Elias Jenny - MIT License
local opt = Options(props)

local function Add(def)
  def.Count = def.Count or 1
  if def.UserPin == nil then def.UserPin = true end
  table.insert(ctrls, def)
end
local function TextOut(name) Add({ Name = name, ControlType = "Indicator", IndicatorType = "Text", PinStyle = "Output" }) end
local function Led(name)     Add({ Name = name, ControlType = "Indicator", IndicatorType = "Led", PinStyle = "Output" }) end
local function Meter(name, min, max)
  Add({ Name = name, ControlType = "Indicator", IndicatorType = "Meter", Min = min, Max = max, PinStyle = "Output" })
end
local function Trigger(name) Add({ Name = name, ControlType = "Button", ButtonType = "Trigger", PinStyle = "Input" }) end
local function Toggle(name, default)
  Add({ Name = name, ControlType = "Button", ButtonType = "Toggle", DefaultValue = default and 1 or 0, PinStyle = "Both" })
end
local function TextIn(name, pinStyle) Add({ Name = name, ControlType = "Text", PinStyle = pinStyle or "Both" }) end
local function Num(name, unit, min, max, default, pinStyle)
  Add({ Name = name, ControlType = "Knob", ControlUnit = unit, Min = min, Max = max, DefaultValue = default, PinStyle = pinStyle or "Both" })
end

-- Tempo (outputs)
Num("BPM", "Float", 0, 300, 0, "Output")
TextOut("BPM Text")
Led("Beat")
Led("Downbeat")
for i = 1, 4 do Led("Bar " .. i) end
Num("Bar Position", "Integer", 0, 4, 0, "Output")
Led("Locked")
TextOut("Detection State")
Meter("Confidence", 0, 100)
Meter("Input Level", -60, 0)
TextOut("Tempo Scale")

-- Tempo (user)
Trigger("Tap")
Toggle("Auto", true)
Toggle("Hold", false)
Trigger("Half")
Trigger("Double")
Trigger("Resync")
Trigger("Shift Half Beat")

-- Detection setup
if opt.LevelSource == "Wired Pin" then
  Num("Level In", "dB", -100, 20, -100, "Input")
elseif opt.LevelSource == "Named Component" then
  TextIn("Meter Component", "Input")
  TextIn("Meter Control", "Input")
end
Num("BPM Min", "Integer", 40, 200, 80)
Num("BPM Max", "Integer", 60, 300, 160)
Num("Sensitivity", "Percent", 0, 100, 50)
Num("Min Confidence", "Percent", 0, 100, 50)
Num("Beat Offset", "Integer", -200, 200, 0)   -- ms, positive = beat LED earlier

-- Console output
Add({ Name = "Status", ControlType = "Indicator", IndicatorType = "Status", PinStyle = "Output" })
if opt.Console ~= "None" then
  Toggle("Send Enable", true)
  Trigger("Send Now")
  TextOut("Last Sent")
  TextIn("IP Address")
  Num("Port", "Integer", 0, 65535, opt.Console == "grandMA2" and 30000 or 8000)
  if opt.Console == "grandMA2" then
    TextIn("Username")
    TextIn("Password", "Input")
    Led("Connected")
    Led("Logged In")
    Trigger("Reconnect")
  else
    TextIn("OSC Prefix")
  end
  Num("Speed Master", "Integer", 1, 16, 1)
  TextIn("Command Template")
  Num("Send Hysteresis", "Float", 0.1, 5, 0.5)
  TextOut("Last Command")
  TextOut("Last Reply")
end
TextOut("Last Error")

-- Debug
TextOut("Level Updates")
Led("Onset")
Meter("Onset Strength", 0, 40)
TextOut("Onset Threshold")
TextOut("Onset Count")
TextOut("Tempo Candidates")
if opt.LevelSource == "Test Generator" then
  Num("Test BPM", "Float", 40, 220, 128)
  Num("Test Jitter", "Integer", 0, 60, 5)          -- ms
  Num("Test Dropout", "Percent", 0, 80, 10)
  Num("Test Update", "Integer", 10, 100, 20)       -- simulated meter update interval, ms
  Toggle("Test Breakdown", false)
end
