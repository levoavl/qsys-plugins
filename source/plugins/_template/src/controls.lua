-- (c) levo AVL | Elias Jenny - MIT License
table.insert(ctrls, {
  Name = "IPAddress",
  ControlType = "Text",
  Count = 1,
  UserPin = true,
  PinStyle = "Both",
})
table.insert(ctrls, {
  Name = "Status",
  ControlType = "Indicator",
  IndicatorType = "Status",
  Count = 1,
  UserPin = true,
  PinStyle = "Output",
})
-- Lua Memory, Plugin Uptime, Internal Errors (levo_health.lua)
LevoHealth.AddControls(function(def) table.insert(ctrls, def) end)
