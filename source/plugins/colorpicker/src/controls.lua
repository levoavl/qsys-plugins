-- (c) levo AVL | Elias Jenny - MIT License
local cfg = PickerConfig(props)

local function Add(def)
  def.Count = def.Count or 1
  if def.UserPin == nil then def.UserPin = true end
  table.insert(ctrls, def)
end
local function Level(name, pinStyle)  -- 0..255
  Add({ Name = name, ControlType = "Knob", ControlUnit = "Integer", Min = 0, Max = 255, PinStyle = pinStyle })
end
local function Percent(name, pinStyle)
  Add({ Name = name, ControlType = "Knob", ControlUnit = "Percent", Min = 0, Max = 100, PinStyle = pinStyle })
end
local function Trigger(name) Add({ Name = name, ControlType = "Button", ButtonType = "Trigger", PinStyle = "Input" }) end
local function TextIn(name) Add({ Name = name, ControlType = "Text", PinStyle = "Both" }) end
local function Swatch(name) Add({ Name = name, ControlType = "Indicator", IndicatorType = "Text", PinStyle = "Output" }) end

-- Current colour (each one is an input and shows the current state)
TextIn("Hex")
Level("Red", "Both")
Level("Green", "Both")
Level("Blue", "Both")
Add({ Name = "Hue", ControlType = "Knob", ControlUnit = "Integer", Min = 0, Max = 360, PinStyle = "Both" })
Percent("Saturation", "Both")
Percent("Brightness", "Both")
Add({ Name = "Kelvin", ControlType = "Knob", ControlUnit = "Integer", Min = 1000, Max = 10000, PinStyle = "Both" })
Percent("Dimmer", "Both")
Add({ Name = "Fade Time", ControlType = "Knob", ControlUnit = "Seconds", Min = 0, Max = 10, PinStyle = "Both" })
Swatch("Preview")
Add({ Name = "Status", ControlType = "Indicator", IndicatorType = "Status", PinStyle = "Output" })

-- Fixed presets
for i = 1, #ColorPresets do Trigger("Preset " .. i) end

-- Picker field and hue strip: plugin UI only, no pins (hundreds of cells).
-- Field cells are toggles that the runtime keeps switched on and recolours with
-- the hue - an "on" button always shows its runtime colour.
for row = 1, cfg.FieldSize do
  for col = 1, cfg.FieldSize do
    Add({ Name = ("Field %d.%d"):format(row, col), ControlType = "Button", ButtonType = "Toggle", UserPin = false })
  end
end
for i = 1, cfg.StripSize do
  Add({ Name = "Hue Strip " .. i, ControlType = "Button", ButtonType = "Trigger", UserPin = false })
end

-- User presets: press = recall, press while Store is on = save current colour
Add({ Name = "Store", ControlType = "Button", ButtonType = "Toggle", PinStyle = "Both" })
for i = 1, cfg.UserPresets do
  Trigger("User " .. i)
  Swatch("User " .. i .. " Swatch")
  TextIn("User " .. i .. " Hex")  -- holds the preset, persists with the design
end

-- LED calibration: colour of the white and amber emitters
TextIn("White LED Color")
TextIn("Amber LED Color")

-- Level outputs 0..255
for _, lay in ipairs(OutputLayouts) do
  for ch in lay:gmatch(".") do Level(lay .. " " .. ch, "Output") end
end
if cfg.SeparateDimmer then Level("Dimmer Level", "Output") end

-- Console link: percent, input + output pin for two-way wiring
for _, ch in ipairs(cfg.LinkChannels) do Percent("Link " .. ChannelNames[ch], "Both") end
