-- (c) levo AVL | Elias Jenny - MIT License
table.insert(props, { Name = "Fader Count",   Type = "integer", Min = 0, Max = 64,  Value = 8 })
table.insert(props, { Name = "Button Count",  Type = "integer", Min = 0, Max = 128, Value = 16 })
table.insert(props, { Name = "Macro Count",   Type = "integer", Min = 0, Max = 64,  Value = 8 })
table.insert(props, { Name = "Command Count", Type = "integer", Min = 0, Max = 32,  Value = 4 })
table.insert(props, { Name = "Poll Interval (ms)", Type = "integer", Min = 100, Max = 2000, Value = 250 })
table.insert(props, {
  -- Legends written by the plugin override any UCI text, so the main buttons
  -- (state buttons) are left alone unless "All" is chosen.
  Name = "Button Legends",
  Type = "enum",
  Choices = { "Fader Buttons 2+3", "All", "Off" },
  Value = "Fader Buttons 2+3",
})
-- Adds an "Enable" control/pin: off = plugin idle with status "Disabled" (e.g. wired to
-- the console's power). Off by default, so existing designs keep running unchanged.
table.insert(props, { Name = "Enable Pin", Type = "boolean", Value = false })
table.insert(props, {
  Name = "Debug Print",
  Type = "enum",
  Choices = { "None", "Basic", "Verbose" },
  Value = "None",
})
