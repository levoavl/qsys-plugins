-- (c) levo AVL | Elias Jenny - MIT License
local n       = props["Menu Count"].Value
local nav     = props["Navigation"].Value
local content = props["Content"].Value

-- Menu items: these go onto the UCI. Their look is drawn by the plugin.
table.insert(ctrls, { Name = "Menu", ControlType = "Button", ButtonType = "Toggle",
  Count = n, UserPin = true, PinStyle = "Both" })
table.insert(ctrls, { Name = "Menu Active", ControlType = "Indicator", IndicatorType = "Led",
  Count = n, UserPin = true, PinStyle = "Output" })
if content ~= "Icon" then
  table.insert(ctrls, { Name = "Label", ControlType = "Text", Count = n, UserPin = true, PinStyle = "Both" })
end
if content ~= "Text" then
  table.insert(ctrls, { Name = "Icon", ControlType = "Text", Count = n, UserPin = false })
end
table.insert(ctrls, { Name = "Active Menu", ControlType = "Knob", ControlUnit = "Integer",
  Min = 1, Max = n, Count = 1, UserPin = true, PinStyle = "Both" })
table.insert(ctrls, { Name = "Lock", ControlType = "Button", ButtonType = "Toggle",
  Count = 1, UserPin = true, PinStyle = "Both" })

-- Navigation targets
if nav == "Page" then
  table.insert(ctrls, { Name = "Panels", ControlType = "Text", Count = 1, UserPin = false })
  table.insert(ctrls, { Name = "Add Panel", ControlType = "Text", Count = 1, UserPin = false })
end
if nav == "Layer" then
  table.insert(ctrls, { Name = "UCI Name", ControlType = "Text", Count = 1, UserPin = false })
  table.insert(ctrls, { Name = "Layer", ControlType = "Text", Count = n, UserPin = false })
end
if nav ~= "Output Only" then
  table.insert(ctrls, { Name = "Page", ControlType = "Text", Count = n, UserPin = false })
end

-- Colours as hex text, defaults are the levo colours
for _, c in ipairs({ "Background", "Text", "Active Text", "Indicator", "Divider" }) do
  table.insert(ctrls, { Name = "Color " .. c, ControlType = "Text", Count = 1, UserPin = false })
end

table.insert(ctrls, { Name = "Status", ControlType = "Indicator", IndicatorType = "Status",
  Count = 1, UserPin = true, PinStyle = "Output" })
