-- (c) levo AVL | Elias Jenny - MIT License
local topo = AtemTopology.Resolve(props)
local mode = AtemTopology.ButtonMode(props)

local function Add(def)
  def.Count = def.Count or 1
  if def.UserPin == nil then def.UserPin = true end
  table.insert(ctrls, def)
end
local function TextOut(name) Add({ Name = name, ControlType = "Indicator", IndicatorType = "Text", PinStyle = "Output" }) end
local function Led(name)     Add({ Name = name, ControlType = "Indicator", IndicatorType = "Led", PinStyle = "Output" }) end
local function Toggle(name)  Add({ Name = name, ControlType = "Button", ButtonType = "Toggle", PinStyle = "Both" }) end
local function Trigger(name) Add({ Name = name, ControlType = "Button", ButtonType = "Trigger", PinStyle = "Input" }) end
local function TextIn(name)  Add({ Name = name, ControlType = "Text", PinStyle = "Both" }) end
local function Int(name, min, max)
  Add({ Name = name, ControlType = "Knob", ControlUnit = "Integer", Min = min, Max = max, PinStyle = "Both" })
end
local function Float(name)
  Add({ Name = name, ControlType = "Knob", ControlUnit = "Float", Min = 0, Max = 1, PinStyle = "Both" })
end

-- Connection
TextIn("IP Address")
Trigger("Reconnect")
Add({ Name = "Status", ControlType = "Indicator", IndicatorType = "Status", PinStyle = "Output" })
Led("Connected")
TextOut("Device")
TextOut("Protocol Version")
TextOut("Last Error")
TextOut("Reconnects")

-- Source names as reported by the switcher (for UCI labels)
for _, id in ipairs(AtemTopology.ButtonSourceUnion(topo, mode)) do
  TextOut("Name " .. AtemTopology.SourceKey(id))
end

-- M/E blocks
for me = 1, topo.MEs do
  local p = "ME" .. me .. " "
  TextIn(p .. "Program")   -- combo box: source name
  TextIn(p .. "Preview")
  for _, id in ipairs(AtemTopology.MEButtonSources(topo, me, mode)) do
    local key = AtemTopology.SourceKey(id)
    Toggle(p .. "Program " .. key)
    Toggle(p .. "Preview " .. key)
  end
  Trigger(p .. "Cut")
  Toggle(p .. "Auto")              -- lit while a transition runs
  Float(p .. "T-Bar")
  Led(p .. "In Transition")
  Toggle(p .. "Fade to Black")     -- lit while black / fading
  TextIn(p .. "Fade to Black Rate")   -- "s:ff" like ATEM Software Control
  TextIn(p .. "Transition Style")  -- combo box
  for _, style in ipairs(AtemTopology.TransitionStyles) do Toggle(p .. "Style " .. style) end
  TextIn(p .. "Transition Rate")      -- "s:ff"
  Toggle(p .. "Preview Transition")
  Toggle(p .. "Next Background")
  for k = 1, topo.USKs do
    Toggle(p .. "Next Key " .. k)
    Toggle(p .. "Key " .. k .. " On Air")
  end
end
