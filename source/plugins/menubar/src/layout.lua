-- (c) levo AVL | Elias Jenny - MIT License
local n       = props["Menu Count"].Value
local nav     = props["Navigation"].Value
local content = props["Content"].Value
local C   = LevoBrand.Colors
local M   = 16
local W   = 700
local ROW = 24

local function Label(text, x, ly, w, align, color, style)
  table.insert(graphics, {
    Type = "Text", Text = text, Position = { x, ly }, Size = { w, 20 },
    FontSize = 12, FontStyle = style or "Regular", HTextAlign = align or "Right", Color = color or C.Onyx,
  })
end

local function Section(text, ly)
  Label(text, M, ly, W - 2 * M, "Left", C.Atlantic, "Bold")
  return ly + 24
end

if CurrentPage == "Control" then
  local itemW = 120
  local cols  = math.min(n, 5)
  local rows  = math.ceil(n / cols)
  local H = LevoBrand.HeaderHeight + 2 + 16 + 24 + rows * 52 + 100
  LevoBrand.Background(graphics, W, H)
  local y = LevoBrand.Header(graphics, W, LevoBrand.PluginName(PluginInfo), CurrentPage) + 16
  y = Section("Menu", y)
  for i = 1, n do
    local col, row = (i - 1) % cols, (i - 1) // cols
    layout["Menu " .. i] = { PrettyName = "Menu~" .. i .. "~Button", Style = "Button",
      Position = { M + col * itemW, y + row * 52 }, Size = { itemW, 48 } }
    layout["Menu Active " .. i] = { PrettyName = "Menu~" .. i .. "~Active", Style = "Led",
      Position = { M + col * itemW + itemW - 16, y + row * 52 + 4 }, Size = { 10, 10 } }
  end
  y = y + rows * 52 + 12
  Label("Active Menu", M, y, 100)
  layout["Active Menu"] = { PrettyName = "Active Menu", Style = "Text", Position = { M + 108, y }, Size = { 60, 20 } }
  Label("Lock", M + 180, y, 60)
  layout["Lock"] = { PrettyName = "Lock", Style = "Button", Legend = "Lock",
    Position = { M + 248, y }, Size = { 60, 20 } }
  y = y + 32
  Label("Status", M, y, 100)
  layout["Status"] = { PrettyName = "Status", Position = { M + 108, y }, Size = { W - 2 * M - 108, 20 } }

elseif CurrentPage == "Setup" then
  local H = LevoBrand.HeaderHeight + 2 + 16 + 24 * 3 + 4 * ROW + (n + 1) * ROW + 6 * ROW + 60
  LevoBrand.Background(graphics, W, H)
  local y = LevoBrand.Header(graphics, W, LevoBrand.PluginName(PluginInfo), CurrentPage) + 16

  y = Section("Navigation: " .. nav, y)
  if nav == "Page" then
    Label("Panels", M, y, 100)
    layout["Panels"] = { PrettyName = "Setup~Panels", Style = "Text", Position = { M + 108, y }, Size = { 360, 20 } }
    y = y + ROW
    Label("Add Panel", M, y, 100)
    layout["Add Panel"] = { PrettyName = "Setup~Add Panel", Style = "ComboBox", Position = { M + 108, y }, Size = { 360, 20 } }
    y = y + ROW
    Label("Names of touch panels / UCI viewers from the Inventory, comma-separated.", M + 108, y, 500, "Left", C.Mid)
    y = y + ROW + 6
  elseif nav == "Layer" then
    Label("UCI Name", M, y, 100)
    layout["UCI Name"] = { PrettyName = "Setup~UCI Name", Style = "Text", Position = { M + 108, y }, Size = { 360, 20 } }
    y = y + ROW
    Label("Layers: one or more per menu item, comma-separated.", M + 108, y, 500, "Left", C.Mid)
    y = y + ROW + 6
  end

  y = Section("Menu items", y)
  local x = M + 40
  local cols = {}
  if content ~= "Icon" then table.insert(cols, { "Label", 130 }) end
  if content ~= "Text" then table.insert(cols, { "Icon", 150 }) end
  if nav ~= "Output Only" then table.insert(cols, { "Page", 130 }) end
  if nav == "Layer" then table.insert(cols, { "Layer", 180 }) end
  local cx = x
  for _, c in ipairs(cols) do
    Label(c[1], cx, y, c[2], "Left", C.Mid); cx = cx + c[2] + 8
  end
  y = y + 20
  for i = 1, n do
    Label(tostring(i), M, y, 32)
    cx = x
    for _, c in ipairs(cols) do
      layout[c[1] .. " " .. i] = { PrettyName = "Menu~" .. i .. "~" .. c[1],
        Style = c[1] == "Icon" and "ComboBox" or "Text", Position = { cx, y }, Size = { c[2], 20 } }
      cx = cx + c[2] + 8
    end
    y = y + ROW
  end
  y = y + 6

  y = Section("Colours (hex)", y)
  for _, c in ipairs({ "Background", "Text", "Active Text", "Indicator", "Divider" }) do
    Label(c, M, y, 100)
    layout["Color " .. c] = { PrettyName = "Colours~" .. c, Style = "Text", Position = { M + 108, y }, Size = { 100, 20 } }
    y = y + ROW
  end

elseif CurrentPage == "About" then
  LevoBrand.Background(graphics, W, 440)
  local y = LevoBrand.Header(graphics, W, LevoBrand.PluginName(PluginInfo), CurrentPage) + 16
  y = LevoBrand.About(graphics, M, y, W - 2 * M, PluginInfo)
  Label("Icons: Material Symbols by Google, Apache License 2.0.", M, y + 4, W - 2 * M, "Left", C.Mid)
end
