-- (c) levo AVL | Elias Jenny - MIT License
local n   = props["Menu Count"].Value

local function Add(def)
  def.Count = def.Count or 1
  if def.UserPin == nil then def.UserPin = false end
  table.insert(ctrls, def)
end
local function Combo(name, count) Add({ Name = name, ControlType = "Text", Count = count }) end
local function Text(name, count)  Add({ Name = name, ControlType = "Text", Count = count }) end
local function Toggle(name)       Add({ Name = name, ControlType = "Button", ButtonType = "Toggle" }) end
local function Int(name, min, max)
  Add({ Name = name, ControlType = "Knob", ControlUnit = "Integer", Min = min, Max = max })
end

-- Menu items: these go onto the UCI. Their look is drawn by the plugin.
Add({ Name = "Menu", ControlType = "Button", ButtonType = "Toggle", Count = n, UserPin = true, PinStyle = "Both" })
Add({ Name = "Menu Active", ControlType = "Indicator", IndicatorType = "Led", Count = n, UserPin = true, PinStyle = "Output" })
Add({ Name = "Active Menu", ControlType = "Knob", ControlUnit = "Integer", Min = 1, Max = n, UserPin = true, PinStyle = "Both" })
Add({ Name = "Lock", ControlType = "Button", ButtonType = "Toggle", UserPin = true, PinStyle = "Both" })
Add({ Name = "Status", ControlType = "Indicator", IndicatorType = "Status", UserPin = true, PinStyle = "Output" })

-- Setup: look (live)
Combo("Content")
Combo("Font")
Int("Font Size", 8, 72)
Toggle("Bold Active")
Int("Icon Size", 12, 300)
Toggle("Fill Active Icon")
Int("Item Gap", 0, 200)
Int("Corner Radius", 0, 300)
Combo("Rounded Corners")
Combo("Indicator Style")
Combo("Line Position")
Int("Indicator Size", 1, 40)
Int("Indicator Margin X", 0, 200)
Int("Indicator Margin Y", 0, 200)
Toggle("Dividers")
Int("Divider Length", 5, 100)
Int("Divider Width", 1, 10)
Int("Animation Time", 0, 2000)
for _, c in ipairs({ "Background", "Text", "Active Text", "Indicator", "Divider" }) do Text("Color " .. c) end

-- Setup: items and navigation
Add({ Name = "Label", ControlType = "Text", Count = n, UserPin = true, PinStyle = "Both" })
Combo("Icon", n)
Text("Page", n)
Text("Layers", n)
Text("Panels")
Combo("Add Panel")
Text("UCI Name")
Combo("Layer Transition")

-- Marks that the defaults have been written once
Text("Defaults Set")
