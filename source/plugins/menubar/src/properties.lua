-- (c) levo AVL | Elias Jenny - MIT License
-- Only settings that change the number or size of controls live here.
-- Everything else is on the Setup page and can be changed live.
table.insert(props, { Name = "Menu Count",   Type = "integer", Min = 2, Max = 12, Value = 4 })
table.insert(props, { Name = "Orientation",  Type = "enum", Choices = { "Horizontal", "Vertical" }, Value = "Horizontal" })
table.insert(props, { Name = "Item Width",   Type = "integer", Min = 30, Max = 1000, Value = 200 })
table.insert(props, { Name = "Item Height",  Type = "integer", Min = 30, Max = 600, Value = 80 })
table.insert(props, { Name = "Item Spacing", Type = "integer", Min = 0, Max = 200, Value = 0 })  -- px gap between items
table.insert(props, { Name = "Navigation",   Type = "enum", Choices = { "Page", "Layer", "Output Only" }, Value = "Page" })
table.insert(props, {
  Name = "Debug Print",
  Type = "enum",
  Choices = { "None", "Basic", "Verbose" },
  Value = "None",
})
