-- (c) levo AVL | Elias Jenny - MIT License
local n   = props["Menu Count"].Value
local nav = props["Navigation"].Value
local C   = LevoBrand.Colors
local M   = 16
local W   = 560
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
  local cols  = math.min(n, 4)
  local rows  = math.ceil(n / cols)
  local H = LevoBrand.HeaderHeight + 2 + 16 + rows * 52 + 140
  LevoBrand.Background(graphics, W, H)
  local y = LevoBrand.Header(graphics, W, LevoBrand.PluginName(PluginInfo), CurrentPage) + 16
  y = Section("Menu", y)
  for i = 1, n do
    local col, row = (i - 1) % cols, (i - 1) // cols
    layout["Menu " .. i] = { PrettyName = "Menu~" .. i .. "~Button", Style = "Button",
      Position = { M + col * itemW, y + row * 52 }, Size = { itemW, 48 } }
    layout["Menu Active " .. i] = { PrettyName = "Menu~" .. i .. "~Active", Style = "Led",
      Position = { M + col * itemW + itemW - 18, y + row * 52 + 4 }, Size = { 12, 12 } }
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
  local H = LevoBrand.HeaderHeight + 2 + 16 + 24 * 4 + (n + 1) * ROW + 6 * ROW + 80
  LevoBrand.Background(graphics, W, H)
  local y = LevoBrand.Header(graphics, W, LevoBrand.PluginName(PluginInfo), CurrentPage) + 16

  y = Section("Navigation: " .. nav, y)
  if nav == "Page" then
    Label("Panels", M, y, 100)
    layout["Panels"] = { PrettyName = "Setup~Panels", Style = "Text", Position = { M + 108, y }, Size = { 300, 20 } }
    y = y + ROW
    Label("Add Panel", M, y, 100)
    layout["Add Panel"] = { PrettyName = "Setup~Add Panel", Style = "ComboBox", Position = { M + 108, y }, Size = { 300, 20 } }
    y = y + ROW
    Label("Comma-separated names of touch panels / UCI viewers from the Inventory.", M + 108, y, 400, "Left", C.Mid)
    y = y + ROW + 6
  elseif nav == "Layer" then
    Label("UCI Name", M, y, 100)
    layout["UCI Name"] = { PrettyName = "Setup~UCI Name", Style = "Text", Position = { M + 108, y }, Size = { 300, 20 } }
    y = y + ROW + 6
  end

  y = Section("Menu items", y)
  local xLabel, xPage, xLayer = M + 40, M + 190, M + 340
  Label("Label", xLabel, y, 140, "Left", C.Mid)
  if nav ~= "Output Only" then Label("Page", xPage, y, 140, "Left", C.Mid) end
  if nav == "Layer" then Label("Layer", xLayer, y, 140, "Left", C.Mid) end
  y = y + 20
  for i = 1, n do
    Label(tostring(i), M, y, 32)
    layout["Label " .. i] = { PrettyName = "Menu~" .. i .. "~Label", Style = "Text", Position = { xLabel, y }, Size = { 140, 20 } }
    if nav ~= "Output Only" then
      layout["Page " .. i] = { PrettyName = "Menu~" .. i .. "~Page", Style = "Text", Position = { xPage, y }, Size = { 140, 20 } }
    end
    if nav == "Layer" then
      layout["Layer " .. i] = { PrettyName = "Menu~" .. i .. "~Layer", Style = "Text", Position = { xLayer, y }, Size = { 140, 20 } }
    end
    y = y + ROW
  end
  y = y + 6

  y = Section("Colours (hex)", y)
  for _, c in ipairs({ "Background", "Text", "Active Text", "Indicator" }) do
    Label(c, M, y, 100)
    layout["Color " .. c] = { PrettyName = "Colours~" .. c, Style = "Text", Position = { M + 108, y }, Size = { 100, 20 } }
    y = y + ROW
  end

elseif CurrentPage == "About" then
  LevoBrand.Background(graphics, W, 420)
  local y = LevoBrand.Header(graphics, W, LevoBrand.PluginName(PluginInfo), CurrentPage) + 16
  LevoBrand.About(graphics, M, y, W - 2 * M, PluginInfo)
end
