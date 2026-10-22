-- (c) levo AVL | Elias Jenny - MIT License
table.insert(props, { Name = "User Presets",   Type = "integer", Min = 0, Max = 32, Value = 8 })
-- picker field cells per side (saturation x brightness), the hue strip gets twice as many
table.insert(props, { Name = "Picker Resolution", Type = "integer", Min = 8, Max = 24, Value = 16 })
table.insert(props, {
  -- Scale Outputs: the dimmer is multiplied into every colour channel.
  -- Separate Output: colour channels stay at full level, the dimmer gets its own output.
  Name = "Dimmer",
  Type = "enum",
  Choices = { "Scale Outputs", "Separate Output" },
  Value = "Scale Outputs",
})
table.insert(props, {
  Name = "White/Amber Mixing",
  Type = "enum",
  Choices = { "Subtract (accurate)", "Add (brighter)" },
  Value = "Subtract (accurate)",
})
table.insert(props, {
  -- Percent controls (0-100 %) with input and output pin, for two-way wiring to
  -- console faders, e.g. the levo AVL grandMA2 plugin.
  Name = "Console Link",
  Type = "enum",
  Choices = { "Off", "RGB", "RGBW", "RGBA", "RGBWA" },
  Value = "RGB",
})
table.insert(props, {
  Name = "Debug Print",
  Type = "enum",
  Choices = { "None", "Basic", "Verbose" },
  Value = "None",
})
