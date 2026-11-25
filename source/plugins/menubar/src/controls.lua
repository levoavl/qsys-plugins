-- (c) levo AVL | Elias Jenny - MIT License
local n = props["Menu Count"].Value

-- Menu items: these go onto the UCI. Their look is drawn by the plugin.
table.insert(ctrls, { Name = "Menu", ControlType = "Button", ButtonType = "Toggle",
  Count = n, UserPin = true, PinStyle = "Both" })
table.insert(ctrls, { Name = "Menu Active", ControlType = "Indicator", IndicatorType = "Led",
  Count = n, UserPin = true, PinStyle = "Output" })
table.insert(ctrls, { Name = "Active Menu", ControlType = "Knob", ControlUnit = "Integer",
  Min = 1, Max = n, Count = 1, UserPin = true, PinStyle = "Both" })
table.insert(ctrls, { Name = "Lock", ControlType = "Button", ButtonType = "Toggle",
  Count = 1, UserPin = true, PinStyle = "Both" })
table.insert(ctrls, { Name = "Status", ControlType = "Indicator", IndicatorType = "Status",
  Count = 1, UserPin = true, PinStyle = "Output" })
