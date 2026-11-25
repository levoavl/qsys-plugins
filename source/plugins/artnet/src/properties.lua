-- (c) levo AVL | Elias Jenny - MIT License
table.insert(props, {
  Name = "Universe Count",
  Type = "integer", Min = 1, Max = 4, Value = 1,
})
for u = 1, 4 do
  table.insert(props, {
    Name = "Channels U" .. u,
    Type = "integer", Min = 1, Max = 512, Value = 32,
  })
end
table.insert(props, {
  Name = "Knobs per Row",
  Type = "enum", Choices = { "8", "10", "16" }, Value = "10",
})
table.insert(props, {
  Name = "Refresh Rate (Hz)",
  Type = "integer", Min = 1, Max = 44, Value = 30,
})
table.insert(props, {
  Name = "Send Mode",
  Type = "enum", Choices = { "On Change", "Continuous" }, Value = "On Change",
})
table.insert(props, {
  Name = "Debug Print",
  Type = "enum", Choices = { "None", "Basic", "Verbose" }, Value = "None",
})
