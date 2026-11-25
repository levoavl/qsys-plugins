-- (c) levo AVL | Elias Jenny - MIT License
table.insert(props, { Name = "Menu Count",       Type = "integer", Min = 2, Max = 12, Value = 4 })
table.insert(props, { Name = "Orientation",      Type = "enum", Choices = { "Horizontal", "Vertical" }, Value = "Horizontal" })
table.insert(props, { Name = "Item Width",       Type = "integer", Min = 40, Max = 1000, Value = 200 })
table.insert(props, { Name = "Item Height",      Type = "integer", Min = 30, Max = 600, Value = 80 })
table.insert(props, { Name = "Indicator Style",  Type = "enum", Choices = { "Line", "Pill", "Block" }, Value = "Line" })
table.insert(props, { Name = "Indicator Size",   Type = "integer", Min = 2, Max = 40, Value = 6 })
table.insert(props, { Name = "Font Size",        Type = "integer", Min = 8, Max = 72, Value = 22 })
table.insert(props, { Name = "Animation Time",   Type = "integer", Min = 0, Max = 2000, Value = 300 })  -- ms, 0 = jump
table.insert(props, { Name = "Navigation",       Type = "enum", Choices = { "Page", "Layer", "Output Only" }, Value = "Page" })
table.insert(props, { Name = "Layer Transition", Type = "enum",
  Choices = { "none", "fade", "left", "right", "top", "bottom" }, Value = "fade" })
table.insert(props, {
  Name = "Debug Print",
  Type = "enum",
  Choices = { "None", "Basic", "Verbose" },
  Value = "None",
})
