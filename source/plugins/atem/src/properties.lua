-- (c) levo AVL | Elias Jenny - MIT License
table.insert(props, {
  Name = "Model",
  Type = "enum",
  Choices = AtemTopology.ModelNames(),
  Value = AtemTopology.DEFAULT_MODEL,
})
-- Only used with Model = Custom
table.insert(props, { Name = "Custom M/Es", Type = "integer", Min = 1, Max = 4, Value = 1 })
table.insert(props, { Name = "Custom Inputs", Type = "integer", Min = 1, Max = 80, Value = 8 })
table.insert(props, { Name = "Custom Keyers per M/E", Type = "integer", Min = 0, Max = 4, Value = 4 })
table.insert(props, { Name = "Custom Downstream Keyers", Type = "integer", Min = 0, Max = 4, Value = 2 })
table.insert(props, { Name = "Custom Aux Outputs", Type = "integer", Min = 0, Max = 48, Value = 2 })
table.insert(props, { Name = "Custom Media Players", Type = "integer", Min = 0, Max = 4, Value = 2 })
table.insert(props, { Name = "Custom SuperSources", Type = "integer", Min = 0, Max = 2, Value = 0 })
table.insert(props, {
  Name = "Custom Audio", Type = "enum", Choices = { "Fairlight", "Classic", "None" }, Value = "Fairlight",
})
table.insert(props, { Name = "Custom Streaming / Recording", Type = "boolean", Value = false })

table.insert(props, {
  -- Buttons per source on the M/E buses. The combo boxes always list every source.
  Name = "Source Buttons",
  Type = "enum",
  Choices = { "All Sources", "Inputs Only", "None" },
  Value = "All Sources",
})
table.insert(props, {
  -- Buttons per source on every aux output (combo boxes always list every source).
  -- Large switchers: up to 48 aux x 100 sources - use "Inputs Only" or "None" there.
  Name = "Aux Buttons",
  Type = "enum",
  Choices = { "All Sources", "Inputs Only", "None" },
  Value = "All Sources",
})
table.insert(props, {
  -- "Device Names" writes the switcher's short source names as button legends.
  -- That overrides any legend set on UCI copies of the buttons, hence off by default.
  Name = "Button Legends",
  Type = "enum",
  Choices = { "Default Names", "Device Names" },
  Value = "Default Names",
})
table.insert(props, {
  Name = "Debug Print",
  Type = "enum",
  Choices = { "None", "Basic", "Verbose" },
  Value = "None",
})
