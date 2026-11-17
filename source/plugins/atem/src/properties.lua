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
  -- Auto: All Sources up to 8 aux, Inputs Only up to 24 aux, None above.
  Name = "Aux Buttons",
  Type = "enum",
  Choices = { "Auto", "All Sources", "Inputs Only", "None" },
  Value = "Auto",
})
-- Buttons per still (per media player) and per macro; the combo boxes list all
table.insert(props, { Name = "Still Buttons", Type = "integer", Min = 0, Max = 96, Value = 20 })
table.insert(props, { Name = "Macro Buttons", Type = "integer", Min = 0, Max = 100, Value = 20 })
-- Audio mixer page (Fairlight or classic, depending on the model). MADI channels
-- (Constellation) only with "On incl. MADI" - that can be 64 extra strips.
table.insert(props, {
  Name = "Audio", Type = "enum", Choices = { "On", "On incl. MADI", "Off" }, Value = "On",
})
-- Setup pages: fill / key sources and key type of the keyers, SuperSource boxes.
-- Off by default: the plugin is a remote control, details stay in ATEM Software Control.
table.insert(props, { Name = "Keyer Setup Page", Type = "boolean", Value = false })
table.insert(props, { Name = "SuperSource Page", Type = "boolean", Value = false })
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
