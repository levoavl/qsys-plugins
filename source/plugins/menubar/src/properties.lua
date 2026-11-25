-- (c) levo AVL | Elias Jenny - MIT License

-- Bar geometry
table.insert(props, { Name = "Menu Count",   Type = "integer", Min = 2, Max = 12, Value = 4 })
table.insert(props, { Name = "Orientation",  Type = "enum", Choices = { "Horizontal", "Vertical" }, Value = "Horizontal" })
table.insert(props, { Name = "Item Width",   Type = "integer", Min = 30, Max = 1000, Value = 200 })
table.insert(props, { Name = "Item Height",  Type = "integer", Min = 30, Max = 600, Value = 80 })
table.insert(props, { Name = "Item Spacing", Type = "integer", Min = 0, Max = 200, Value = 0 })  -- px gap between items
table.insert(props, { Name = "Corner Radius", Type = "integer", Min = 0, Max = 300, Value = 0 })
table.insert(props, { Name = "Rounded Corners", Type = "enum", Choices = { "Bar Ends", "Each Item" }, Value = "Bar Ends" })

-- Item content
table.insert(props, { Name = "Content",     Type = "enum", Choices = { "Text", "Icon", "Icon + Text" }, Value = "Text" })
table.insert(props, { Name = "Font",        Type = "enum",
  Choices = { "Arial", "Helvetica", "Verdana", "Tahoma", "Trebuchet MS", "Georgia" }, Value = "Arial" })
table.insert(props, { Name = "Font Size",   Type = "integer", Min = 8, Max = 72, Value = 22 })
table.insert(props, { Name = "Bold Active", Type = "boolean", Value = true })
table.insert(props, { Name = "Icon Size",   Type = "integer", Min = 12, Max = 300, Value = 36 })
table.insert(props, { Name = "Fill Active Icon", Type = "boolean", Value = true })

-- Indicator
table.insert(props, { Name = "Indicator Style",    Type = "enum", Choices = { "None", "Line", "Pill", "Block" }, Value = "Line" })
table.insert(props, { Name = "Line Position",      Type = "enum", Choices = { "Bottom / Right", "Top / Left" }, Value = "Bottom / Right" })
table.insert(props, { Name = "Indicator Size",     Type = "integer", Min = 1, Max = 40, Value = 6 })   -- line thickness
table.insert(props, { Name = "Indicator Margin",   Type = "integer", Min = 0, Max = 100, Value = 0 })  -- inset from the item edge

-- Dividers between items
table.insert(props, { Name = "Dividers",        Type = "boolean", Value = false })
table.insert(props, { Name = "Divider Length",  Type = "integer", Min = 5, Max = 100, Value = 60 })  -- % of item height/width
table.insert(props, { Name = "Divider Width",   Type = "integer", Min = 1, Max = 10, Value = 2 })

-- Behaviour
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
