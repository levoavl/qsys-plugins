-- (c) levo AVL | Elias Jenny - MIT License
table.insert(props, { Name = "Fader Count",   Type = "integer", Min = 0, Max = 64,  Value = 8 })
table.insert(props, { Name = "Button Count",  Type = "integer", Min = 0, Max = 128, Value = 16 })
table.insert(props, { Name = "Macro Count",   Type = "integer", Min = 0, Max = 64,  Value = 8 })
table.insert(props, { Name = "Command Count", Type = "integer", Min = 0, Max = 32,  Value = 4 })
table.insert(props, { Name = "Poll Interval (ms)", Type = "integer", Min = 100, Max = 2000, Value = 250 })
table.insert(props, {
  Name = "Debug Print",
  Type = "enum",
  Choices = { "None", "Basic", "Verbose" },
  Value = "None",
})
