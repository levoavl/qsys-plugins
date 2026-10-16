-- (c) levo AVL | Elias Jenny - MIT License
table.insert(props, {
  -- where the low-band level comes from
  Name = "Level Source",
  Type = "enum",
  Choices = { "Wired Pin", "Named Component", "Test Generator" },
  Value = "Wired Pin",
})
table.insert(props, {
  -- where the tempo goes; "None" = detection only (pins)
  Name = "Console Type",
  Type = "enum",
  Choices = { "None", "grandMA2", "grandMA3" },
  Value = "grandMA2",
})
table.insert(props, {
  Name = "Debug Print",
  Type = "enum",
  Choices = { "None", "Basic", "Verbose" },
  Value = "None",
})
