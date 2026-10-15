-- (c) levo AVL | Elias Jenny - MIT License
local counts = SlotCounts(props)

local function Add(def)
  def.Count = def.Count or 1
  if def.UserPin == nil then def.UserPin = true end
  table.insert(ctrls, def)
end
local function TextOut(name) Add({ Name = name, ControlType = "Indicator", IndicatorType = "Text", PinStyle = "Output" }) end
local function Led(name)     Add({ Name = name, ControlType = "Indicator", IndicatorType = "Led", PinStyle = "Output" }) end
local function Percent(name, pinStyle)
  Add({ Name = name, ControlType = "Knob", ControlUnit = "Percent", Min = 0, Max = 100, PinStyle = pinStyle })
end
local function Int(name, max)
  -- 0 = not set yet, the runtime fills in a default on start
  Add({ Name = name, ControlType = "Knob", ControlUnit = "Integer", Min = 0, Max = max, PinStyle = "Both" })
end
local function Momentary(name) Add({ Name = name, ControlType = "Button", ButtonType = "Momentary", PinStyle = "Both" }) end
local function Trigger(name)   Add({ Name = name, ControlType = "Button", ButtonType = "Trigger", PinStyle = "Input" }) end
local function TextIn(name, pinStyle) Add({ Name = name, ControlType = "Text", PinStyle = pinStyle or "Both" }) end

-- Connection / global
TextIn("IP Address")
Int("Port", 65535)
TextIn("Username")
TextIn("Password", "Input")
Trigger("Reconnect")
Add({ Name = "Status", ControlType = "Indicator", IndicatorType = "Status", PinStyle = "Output" })
Led("Connected")
Led("Logged In")
TextIn("Command TX", "Input")
TextOut("Session")
TextOut("Last Error")
TextOut("Reconnects")

-- Fader executors
for i = 1, counts.Faders do
  local p = "Fader " .. i .. " "
  Percent(p .. "Level", "Both")
  for b = 1, 3 do
    Momentary(p .. "Button " .. b)
    TextOut(p .. "Button " .. b .. " Label")
  end
  TextOut(p .. "Name")
  TextOut(p .. "Cue")
  TextOut(p .. "Function")
  Led(p .. "Active")
  Led(p .. "Fading")
  TextOut(p .. "State")
  Percent(p .. "Progress", "Output")
  Int(p .. "Page", 9999)
  Int(p .. "Exec", 999)
end

-- Button executors
for i = 1, counts.Buttons do
  local p = "Button " .. i .. " "
  Momentary(p .. "Press")
  TextOut(p .. "Name")
  TextOut(p .. "Cue")
  TextOut(p .. "Function")
  Led(p .. "Active")
  Led(p .. "Fading")
  TextOut(p .. "State")
  Percent(p .. "Progress", "Output")
  Int(p .. "Page", 9999)
  Int(p .. "Exec", 999)
end

-- Macros
for i = 1, counts.Macros do
  Trigger("Macro " .. i .. " Trigger")
  Int("Macro " .. i .. " Number", 9999)
end

-- Free commands
for i = 1, counts.Commands do
  TextIn("Command " .. i .. " Text")
  Trigger("Command " .. i .. " Send")
end
