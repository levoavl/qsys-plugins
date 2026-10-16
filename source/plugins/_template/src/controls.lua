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
