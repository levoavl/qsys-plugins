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

-- Colours are drawn as images: UCI styles (CSS) override button colours, not images.
-- An invisible button on top takes the touch.
local CLEAR = { 255, 255, 255, 0 }
local function Image(data, x, y, w, h)
  table.insert(content, { Type = "Image", Image = data, Position = { x, y }, Size = { w, h } })
end
-- No CSS classes here or at runtime: Designer does not take layout classes over to
-- UCI copies, and runtime classes would replace the ones given on the UCI.
-- On a UCI the touch buttons must lie in front of the swatches (Bring to Front).
local function TouchButton(name, pretty, x, y, w, h)
  Place(name, pretty, x, y, w, h, {
    Style = "Button", Legend = "", Color = CLEAR, OffColor = CLEAR, UnlinkOffColor = true,
    StrokeWidth = 0, CornerRadius = 0, Margin = 0,
  })
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
    Image(PickerImages.Swatch[p.Hex], x, cy, cw - 6, 30)
    TouchButton("Preset " .. i, "Presets~" .. p.Name, x, cy, cw - 6, 30)
    Label(p.Name, x, cy + 31, cw - 6, 14, { size = 9, color = C.Mid, align = "Center" })
  end
  y = y + math.ceil(#ColorPresets / cols) * 52 + 4

  if cfg.UserPresets > 0 then
    y = Section("User Presets", y)
    Place("Store", "User Presets~Store", W - M - 72, y - 30, 72, 20,
      { Style = "Button", Legend = "Store", FontSize = 10, Color = C.Amber })
    for i = 1, cfg.UserPresets do
      local col, row = (i - 1) % cols, (i - 1) // cols
      local x, cy = M + col * cw, y + row * 52
      -- same as the fixed presets: tap the colour itself (swatch + invisible button on top)
      Place("User " .. i .. " Swatch", "User Presets~User " .. i .. "~Swatch", x, cy, cw - 6, 30,
        { Style = "Text", Color = C.Line, CornerRadius = 0, StrokeWidth = 0 })
      TouchButton("User " .. i, "User Presets~User " .. i .. "~Recall", x, cy, cw - 6, 30)
      Label(tostring(i), x, cy + 31, cw - 6, 14, { size = 9, color = C.Mid, align = "Center" })
    end
    y = y + math.ceil(cfg.UserPresets / cols) * 52
  end
  H = y + M

elseif CurrentPage == "Picker" then
  y = ColorBar(y)
  y = Section("Picker", y)
  -- colour wheel image with invisible touch cells on top, brightness fader to its right
  local d = cfg.WheelSize
  local side = 320
  local cell = side / d
  local x0 = M + (W - 2 * M - side - 40) // 2
  Image(PickerImages.Wheel, x0, y, side, side)
  local function edge(i) return math.floor((i - 1) * cell + 0.5) end  -- cells tile without gaps
  for row = 1, d do
    for col = 1, d do
      if WheelCell(row, col, d) then
        local cx, cy = edge(col), edge(row)
        TouchButton(("Wheel %d.%d"):format(row, col), ("Picker~Wheel~Row %d~Column %d"):format(row, col),
          x0 + cx, y + cy, edge(col + 1) - cx, edge(row + 1) - cy)
      end
    end
  end
  Place("Brightness", "Adjust~Brightness", x0 + side + 18, y, 22, side, { Style = "Fader", Color = C.Atlantic })
  y = y + side + 12
  y = Section("Adjust", y)
  for _, f in ipairs({ "Hue", "Saturation" }) do
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
