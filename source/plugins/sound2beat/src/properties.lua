-- (c) levo AVL | Elias Jenny - MIT License
table.insert(props, {
  -- where the low-band level comes from
  Name = "Level Source",
  Type = "enum",
  Choices = { "Wired Pin", "Named Component", "Test Generator" },
  Value = "Wired Pin",
})
table.insert(props, {
  -- 2 = a second band (e.g. snare) is analysed together with the kick
  Name = "Input Bands",
  Type = "enum",
  Choices = { "1 (Kick)", "2 (Kick + Snare)" },
  Value = "1 (Kick)",
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
