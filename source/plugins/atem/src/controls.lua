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
local _, named = AtemTopology.NamePlacement(topo, props)
for _, id in ipairs(named) do
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
    TextIn(p .. "Key " .. k .. " Fill")   -- combo box
    TextIn(p .. "Key " .. k .. " Key")    -- combo box (key / cut source)
    TextOut(p .. "Key " .. k .. " Type")
  end
end

-- Downstream keyers
for n = 1, topo.DSKs do
  local p = "DSK " .. n .. " "
  Toggle(p .. "On Air")
  Toggle(p .. "Tie")
  Toggle(p .. "Auto")              -- lit while the DSK mixes
  Led(p .. "In Transition")
  TextIn(p .. "Rate")              -- "s:ff"
  TextIn(p .. "Fill")              -- combo box
  TextIn(p .. "Key")               -- combo box
end

-- Aux outputs
local auxMode = AtemTopology.AuxMode(props)
for aux = 1, topo.Aux do
  TextIn("Aux " .. aux)            -- combo box
  for _, id in ipairs(AtemTopology.AuxButtonSources(topo, aux, auxMode)) do
    Toggle("Aux " .. aux .. " " .. AtemTopology.SourceKey(id))
  end
end

-- SuperSource boxes
local boxIds = AtemTopology.BoxButtonSources(topo, mode)
for ss = 1, topo.SuperSources do
  for box = 1, AtemTopology.BOXES do
    local p = "SS" .. ss .. " Box " .. box .. " "
    Toggle(p .. "Enable")
    TextIn(p .. "Source")          -- combo box
    for _, id in ipairs(boxIds) do Toggle(p .. AtemTopology.SourceKey(id)) end
  end
end
