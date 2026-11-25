-- (c) levo AVL | Elias Jenny - MIT License
local function Add(def)
  def.Count = def.Count or 1
  if def.UserPin == nil then def.UserPin = true end
  def.PinStyle = def.PinStyle or "Both"
  table.insert(ctrls, def)
end

local universeCount = props["Universe Count"].Value

for u = 1, universeCount do
  local p = "U" .. u .. " "
  for ch = 1, props["Channels U" .. u].Value do
    Add({ Name = p .. "Ch " .. ch, ControlType = "Knob", ControlUnit = "Integer", Min = 0, Max = 255 })
  end
  Add({ Name = p .. "Target IP", ControlType = "Text" })
  Add({ Name = p .. "Net", ControlType = "Knob", ControlUnit = "Integer", Min = 0, Max = 127 })
  Add({ Name = p .. "SubNet", ControlType = "Knob", ControlUnit = "Integer", Min = 0, Max = 15 })
  Add({ Name = p .. "Universe", ControlType = "Knob", ControlUnit = "Integer", Min = 0, Max = 15 })
  Add({ Name = p .. "Enable", ControlType = "Button", ButtonType = "Toggle" })
  Add({ Name = p .. "Info", ControlType = "Indicator", IndicatorType = "Text", PinStyle = "Output" })
end

Add({ Name = "Broadcast", ControlType = "Button", ButtonType = "Toggle" })
Add({ Name = "Broadcast Address", ControlType = "Text" })
Add({ Name = "Blackout", ControlType = "Button", ButtonType = "Toggle" })
Add({ Name = "Send in Emulation", ControlType = "Button", ButtonType = "Toggle", UserPin = false })
Add({ Name = "Status", ControlType = "Indicator", IndicatorType = "Status", PinStyle = "Output" })
