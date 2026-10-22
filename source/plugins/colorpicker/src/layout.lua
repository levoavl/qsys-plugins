-- (c) levo AVL | Elias Jenny - MIT License
local C = LevoBrand.Colors
local cfg = PickerConfig(props)
local M = 16  -- page margin

local W = 480
local content = {}  -- page graphics, drawn after background and header

local function Label(text, x, y, w, h, opts)
  opts = opts or {}
  table.insert(content, {
    Type = "Text", Text = text, Position = { x, y }, Size = { w, h or 18 },
    FontSize = opts.size or 11, FontStyle = opts.style or "Regular",
    HTextAlign = opts.align or "Left", Color = opts.color or C.Onyx,
  })
end

local function Section(text, y)
  Label(text, M, y, W - 2 * M, 20, { size = 13, style = "Bold", color = C.Atlantic })
  table.insert(content, {
    Type = "GroupBox", Fill = C.Amber, StrokeWidth = 0, CornerRadius = 0,
    Position = { M, y + 20 }, Size = { W - 2 * M, 2 },
  })
  return y + 28
end

local function Place(name, pretty, x, y, w, h, extra)
  local def = { PrettyName = pretty, Position = { x, y }, Size = { w, h } }
  for k, v in pairs(extra or {}) do def[k] = v end
  layout[name] = def
end

-- Colour button with a static layout colour (presets, hue strip, initial field colours).
local function ColorButton(name, pretty, x, y, w, h, r, g, b, flat)
  local col = ColorMath.LayoutColor(r, g, b)
  local def = { Style = "Button", Legend = "", Color = col, OffColor = col, CornerRadius = 2 }
  if flat then def.CornerRadius, def.StrokeWidth, def.Margin = 0, 0, 0 end
  Place(name, pretty, x, y, w, h, def)
end

-- Current colour bar, shown on every colour page
local function ColorBar(y)
  Place("Preview", "Color~Preview", M, y, 76, 76, { Style = "Text", Color = C.Line, CornerRadius = 2 })
  local x = M + 84
  Label("Hex", x - 8, y + 2, 52, 18, { align = "Right" })
  Place("Hex", "Color~Hex", x + 50, y, 84, 22, { Style = "Text", FontSize = 12 })
  Label("Fade", x + 146, y + 2, 40, 18, { align = "Right" })
  Place("Fade Time", "Color~Fade Time", x + 192, y, 56, 22, { Style = "Text" })
  local cx = x
  for _, ch in ipairs({ { "R", "Red" }, { "G", "Green" }, { "B", "Blue" } }) do
    Label(ch[1], cx - 8, y + 29, 52, 18, { align = "Right" })
    Place(ch[2], "Color~" .. ch[2], cx + 50, y + 27, 44, 22, { Style = "Text" })
    cx = cx + 92
  end
  Label("Dimmer", x - 8, y + 56, 52, 18, { align = "Right" })
  Place("Dimmer", "Color~Dimmer", x + 50, y + 56, 228, 18, { Style = "Fader", Color = C.Atlantic })
  return y + 92
end

local y = LevoBrand.HeaderHeight + 2 + 12
local H = 300

if CurrentPage == "Presets" then
  y = ColorBar(y)
  y = Section("Presets", y)
  local cols, cw = 8, (W - 2 * M) // 8
  for i, p in ipairs(ColorPresets) do
    local col, row = (i - 1) % cols, (i - 1) // cols
    local x, cy = M + col * cw, y + row * 52
    ColorButton("Preset " .. i, "Presets~" .. p.Name, x, cy, cw - 6, 30, ColorMath.ParseHex(p.Hex))
    Label(p.Name, x, cy + 31, cw - 6, 14, { size = 9, color = C.Mid, align = "Center" })
  end
  y = y + math.ceil(#ColorPresets / cols) * 52 + 4

  if cfg.UserPresets > 0 then
    y = Section("User Presets", y)
    Place("Store", "User Presets~Store", W - M - 72, y - 30, 72, 20,
      { Style = "Button", Legend = "Store", FontSize = 10, Color = C.Amber })
    for i = 1, cfg.UserPresets do
      local col, row = (i - 1) % cols, (i - 1) // cols
      local x, cy = M + col * cw, y + row * 54
      Place("User " .. i .. " Swatch", "User Presets~User " .. i .. "~Swatch", x, cy, cw - 6, 26,
        { Style = "Text", Color = C.Line, CornerRadius = 2 })
      Place("User " .. i, "User Presets~User " .. i .. "~Recall", x, cy + 28, cw - 6, 18,
        { Style = "Button", Legend = tostring(i), FontSize = 10, Color = C.Amber })
    end
    y = y + math.ceil(cfg.UserPresets / cols) * 54
  end
  H = y + M

elseif CurrentPage == "Picker" then
  y = ColorBar(y)
  y = Section("Picker", y)
  -- saturation x brightness field (recoloured with the hue at runtime), hue strip
  -- and vertical hue fader to its right
  local n, k = cfg.FieldSize, cfg.StripSize
  local cell = (320 // n) // 2 * 2  -- even, so the strip cells (cell / 2) stay whole pixels
  local side = cell * n
  for row = 1, n do
    for col = 1, n do
      local r, g, b = FieldColor(row, col, n, 0)  -- multiple returns only expand as the last argument
      ColorButton(("Field %d.%d"):format(row, col), ("Picker~Field~Row %d~Column %d"):format(row, col),
        M + (col - 1) * cell, y + (row - 1) * cell, cell, cell, r, g, b, true)
    end
  end
  local sx = M + side + 12
  for i = 1, k do
    local r, g, b = ColorMath.HsvToRgb(StripHue(i, k), 1, 1)
    ColorButton("Hue Strip " .. i, ("Picker~Hue Strip~%d"):format(i), sx, y + (i - 1) * (cell // 2), 28, cell // 2,
      r, g, b, true)
  end
  Place("Hue", "Adjust~Hue", sx + 34, y, 22, side, { Style = "Fader", Color = C.Atlantic })
  Label("Saturation >", M, y + side + 2, side, 14, { size = 9, color = C.Mid, align = "Right" })
  y = y + side + 22
  y = Section("Adjust", y)
  for _, f in ipairs({ "Saturation", "Brightness" }) do
    Label(f, M, y, 76, 18, { align = "Right" })
    Place(f, "Adjust~" .. f, M + 84, y, W - 2 * M - 84, 18, { Style = "Fader", Color = C.Atlantic })
    y = y + 26
  end
  Label("Kelvin", M, y + 2, 76, 18, { align = "Right" })
  Place("Kelvin", "Adjust~Kelvin", M + 84, y, 64, 22, { Style = "Text" })
  Label("1000 - 10000 K, sets a white point", M + 156, y + 2, 220, 18, { size = 10, color = C.Mid })
  H = y + 22 + M

elseif CurrentPage == "Outputs" then
  y = Section("Levels (0-255)", y)
  local colX = { R = 0, G = 1, B = 2, W = 3, A = 4 }
  local x0, cw = M + 76, 58
  for _, ch in ipairs({ "R", "G", "B", "W", "A" }) do
    Label(ChannelNames[ch], x0 + colX[ch] * cw, y, cw - 6, 16, { size = 10, color = C.Mid, align = "Center" })
  end
  y = y + 18
  for _, lay in ipairs(OutputLayouts) do
    Label(lay, M, y + 2, 68, 18, { style = "Bold", align = "Right" })
    for ch in lay:gmatch(".") do
      Place(lay .. " " .. ch, "Outputs~" .. lay .. "~" .. ChannelNames[ch], x0 + colX[ch] * cw, y, cw - 6, 22,
        { Style = "Text", IsReadOnly = true })
    end
    y = y + 28
  end
  if cfg.SeparateDimmer then
    Label("Dimmer", M, y + 2, 68, 18, { style = "Bold", align = "Right" })
    Place("Dimmer Level", "Outputs~Dimmer Level", x0, y, cw - 6, 22, { Style = "Text", IsReadOnly = true })
    y = y + 28
  end
  y = y + 8
  if #cfg.LinkChannels > 0 then
    y = Section("Console Link (" .. cfg.LinkLayout .. ", %)", y)
    local lx, lw = M, 80
    for _, ch in ipairs(cfg.LinkChannels) do
      local n = ChannelNames[ch]
      Label(n, lx, y, lw - 6, 16, { size = 10, color = C.Mid, align = "Center" })
      Place("Link " .. n, "Console Link~" .. n, lx, y + 18, lw - 6, 22, { Style = "Text", IsReadOnly = true })
      lx = lx + lw
    end
    y = y + 48
    Label("Wire each Link pin both ways to a console fader (out -> fader, fader -> in).",
      M, y, W - 2 * M, 16, { size = 10, color = C.Mid })
    y = y + 18
  end
  H = y + M

elseif CurrentPage == "Setup" then
  y = Section("LED Calibration", y)
  Label("White LED", M, y + 2, 76, 18, { align = "Right" })
  Place("White LED Color", "Setup~White LED Color", M + 84, y, 84, 22, { Style = "Text" })
  Label("Amber LED", M + 184, y + 2, 76, 18, { align = "Right" })
  Place("Amber LED Color", "Setup~Amber LED Color", M + 268, y, 84, 22, { Style = "Text" })
  y = y + 28
  Label("Hex color of the fixture's white and amber LEDs. Defaults: #FFFFFF, #FFBF00.",
    M, y, W - 2 * M, 16, { size = 10, color = C.Mid })
  y = y + 28

  if cfg.UserPresets > 0 then
    y = Section("User Presets", y)
    local cols, cw = 4, (W - 2 * M) // 4
    for i = 1, cfg.UserPresets do
      local col, row = (i - 1) % cols, (i - 1) // cols
      local x, cy = M + col * cw, y + row * 28
      Label(tostring(i), x, cy + 2, 22, 18, { align = "Right", color = C.Mid })
      Place("User " .. i .. " Hex", "User Presets~User " .. i .. "~Hex", x + 28, cy, cw - 40, 22, { Style = "Text" })
    end
    y = y + math.ceil(cfg.UserPresets / cols) * 28 + 8
  end

  y = Section("Status", y)
  Place("Status", "Status", M, y, W - 2 * M, 22)
  H = y + 22 + M

elseif CurrentPage == "About" then
  H = LevoBrand.About(content, M, y, W - 2 * M, PluginInfo) + M
end

LevoBrand.Background(graphics, W, H)
LevoBrand.Header(graphics, W, LevoBrand.PluginName(PluginInfo), CurrentPage)
for _, g in ipairs(content) do table.insert(graphics, g) end
