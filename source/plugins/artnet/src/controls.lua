-- (c) levo AVL | Elias Jenny - MIT License
local function Add(def)
  def.Count = def.Count or 1
  if def.UserPin == nil then def.UserPin = true end
  def.PinStyle = def.PinStyle or "Both"
  table.insert(ctrls, def)
end

for u = 1, ArtNetConfig.Count(props) do
  local cfg = ArtNetConfig.Universe(props, u)
  local p = "U" .. u .. " "
  local receive = cfg.mode == "Receive"
  -- channel controls are named by their DMX channel (U1 Ch 100 ...)
  for ch = cfg.first, cfg.last do
    Add({ Name = p .. "Ch " .. ch, ControlType = "Knob", ControlUnit = "Integer", Min = 0, Max = 255,
          PinStyle = receive and "Output" or "Both" })
  end
  Add({ Name = p .. "Net", ControlType = "Knob", ControlUnit = "Integer", Min = 0, Max = 127 })
  Add({ Name = p .. "SubNet", ControlType = "Knob", ControlUnit = "Integer", Min = 0, Max = 15 })
  Add({ Name = p .. "Universe", ControlType = "Knob", ControlUnit = "Integer", Min = 0, Max = 15 })
  Add({ Name = p .. "Info", ControlType = "Indicator", IndicatorType = "Text", PinStyle = "Output" })
  if receive then
    Add({ Name = p .. "Source Filter", ControlType = "Text" })
    Add({ Name = p .. "Timeout", ControlType = "Knob", ControlUnit = "Integer", Min = 1, Max = 60 })
    Add({ Name = p .. "On Loss", ControlType = "Text" })   -- combo: Hold / Zero
    Add({ Name = p .. "Data", ControlType = "Indicator", IndicatorType = "Led", PinStyle = "Output" })
  else
    Add({ Name = p .. "Target IP", ControlType = "Text" })
    Add({ Name = p .. "Enable", ControlType = "Button", ButtonType = "Toggle" })
  end
end

Add({ Name = "Broadcast", ControlType = "Button", ButtonType = "Toggle" })
Add({ Name = "Broadcast Address", ControlType = "Text" })
Add({ Name = "Node Name", ControlType = "Text" })
Add({ Name = "Discovery", ControlType = "Indicator", IndicatorType = "Text", PinStyle = "Output" })
Add({ Name = "Blackout", ControlType = "Button", ButtonType = "Toggle" })
Add({ Name = "Send in Emulation", ControlType = "Button", ButtonType = "Toggle", UserPin = false })
Add({ Name = "Status", ControlType = "Indicator", IndicatorType = "Status", PinStyle = "Output" })
