-- (c) levo AVL | Elias Jenny - MIT License
local n        = props["Menu Count"].Value
local vertical = props["Orientation"].Value == "Vertical"
local IW, IH   = props["Item Width"].Value, props["Item Height"].Value
-- Buttons overlap by 2 px: Q-SYS leaves a thin inset around a button icon, the overlap hides it.
-- Visible gaps come from Item Gap, drawn inside the SVG.
local SP       = -2
local C   = LevoBrand.Colors
local M   = 16
local ROW = 24

local barW = vertical and IW or (n * IW + (n - 1) * SP)
local barH = vertical and (n * IH + (n - 1) * SP) or IH

local function Label(text, x, ly, w, align, color, style)
  table.insert(graphics, {
    Type = "Text", Text = text, Position = { x, ly }, Size = { w, 20 },
    FontSize = 12, FontStyle = style or "Regular", HTextAlign = align or "Right", Color = color or C.Onyx,
  })
end

local function Section(text, x, ly, w)
  Label(text, x, ly, w, "Left", C.Atlantic, "Bold")
  return ly + 24
end

-- The menu bar at real size, so the items can be copied onto a UCI together
local function Bar(x0, y0)
  for i = 1, n do
    local x  = vertical and x0 or (x0 + (i - 1) * (IW + SP))
    local iy = vertical and (y0 + (i - 1) * (IH + SP)) or y0
    layout["Menu " .. i] = { PrettyName = "Menu~" .. i, Style = "Button",
      Position = { x, iy }, Size = { IW, IH }, Margin = 0, Padding = 0, StrokeWidth = 0 }
  end
end

if CurrentPage == "Control" then
  local W = math.max(520, barW + 2 * M + (vertical and 40 or 0))
  local H = LevoBrand.HeaderHeight + 2 + 16 + 24 + barH + (vertical and 0 or 24) + 100
  LevoBrand.Background(graphics, W, H)
  local y = LevoBrand.Header(graphics, W, LevoBrand.PluginName(PluginInfo), CurrentPage) + 16
  Label("Menu bar - select all items and copy them onto the UCI", M, y, W - 2 * M, "Left", C.Atlantic, "Bold")
  y = y + 24
  Bar(M, y)
  for i = 1, n do
    local x  = vertical and M or (M + (i - 1) * (IW + SP))
    local iy = vertical and (y + (i - 1) * (IH + SP)) or y
    local lx = vertical and (M + IW + 16) or (x + IW / 2 - 6)
    local ly = vertical and (iy + IH / 2 - 6) or (y + IH + 8)
    layout["Menu Active " .. i] = { PrettyName = "Menu Active~" .. i, Style = "Led",
      Position = { lx, ly }, Size = { 12, 12 } }
  end
  y = y + barH + (vertical and 16 or 32)
  Label("Active Menu", M, y, 100)
  layout["Active Menu"] = { PrettyName = "Active Menu", Style = "Text", Position = { M + 108, y }, Size = { 60, 20 } }
  Label("Lock", M + 180, y, 60)
  layout["Lock"] = { PrettyName = "Lock", Style = "Button", Legend = "Lock", Position = { M + 248, y }, Size = { 60, 20 } }
  y = y + 32
  Label("Status", M, y, 100)
  layout["Status"] = { PrettyName = "Status", Position = { M + 108, y }, Size = { W - 2 * M - 108, 20 } }

elseif CurrentPage == "Setup" then
  -- live preview on top, settings below in two columns
  local colW = 330
  local W = math.max(2 * colW + 3 * M, barW + 2 * M)
  local x1, x2 = M, 2 * M + colW
  local lw = 120                       -- label width
  local cx1, cx2 = x1 + lw + 8, x2 + lw + 8

  local rowsLook = 26
  local rowsItems = n + 11
  local H = LevoBrand.HeaderHeight + 2 + 16 + 24 + barH + 24 + math.max(rowsLook, rowsItems) * ROW + 3 * 24 + 40
  LevoBrand.Background(graphics, W, H)
  local y = LevoBrand.Header(graphics, W, LevoBrand.PluginName(PluginInfo), CurrentPage) + 16
  Label("Preview", M, y, W - 2 * M, "Left", C.Atlantic, "Bold")
  y = y + 24
  Bar(M, y)
  y = y + barH + 24
  local yTop = y

  -- Left column: look
  local function Field(name, label, style, col, ly, w)
    local x = col == 1 and x1 or x2
    Label(label, x, ly, lw)
    local def = { PrettyName = "Setup~" .. name, Style = style, Position = { (col == 1 and cx1 or cx2), ly }, Size = { w or 120, 20 } }
    if style == "Button" then def.Legend = "On" end
    layout[name] = def
    return ly + ROW
  end

  y = Section("Content", x1, y, colW)
  y = Field("Content", "Content", "ComboBox", 1, y)
  y = Field("Font", "Font", "ComboBox", 1, y)
  y = Field("Font Size", "Font Size", "Text", 1, y, 60)
  y = Field("Bold Active", "Bold Active", "Button", 1, y, 60)
  y = Field("Icon Size", "Icon Size", "Text", 1, y, 60)
  y = Field("Fill Active Icon", "Fill Active Icon", "Button", 1, y, 60)
  y = y + 6
  y = Section("Shape", x1, y, colW)
  y = Field("Item Gap", "Item Gap", "Text", 1, y, 60)
  y = Field("Width Correction", "Width Correction", "Text", 1, y, 60)
  y = Field("Height Correction", "Height Correction", "Text", 1, y, 60)
  y = Field("Corner Radius", "Corner Radius", "Text", 1, y, 60)
  y = Field("Rounded Corners", "Rounded Corners", "ComboBox", 1, y)
  y = Field("Dividers", "Dividers", "Button", 1, y, 60)
  y = Field("Divider Length", "Divider Length %", "Text", 1, y, 60)
  y = Field("Divider Width", "Divider Width", "Text", 1, y, 60)
  y = y + 6
  y = Section("Indicator", x1, y, colW)
  y = Field("Indicator Style", "Style", "ComboBox", 1, y)
  y = Field("Line Position", "Line Position", "ComboBox", 1, y)
  y = Field("Indicator Size", "Line Size", "Text", 1, y, 60)
  y = Field("Indicator Margin X", "Margin Left/Right", "Text", 1, y, 60)
  y = Field("Indicator Margin Y", "Margin Top/Bottom", "Text", 1, y, 60)
  y = Field("Animation Time", "Animation ms", "Text", 1, y, 60)
  y = y + 6
  y = Section("Colours (hex or none)", x1, y, colW)
  for _, c in ipairs({ "Background", "Text", "Active Text", "Indicator", "Divider" }) do
    y = Field("Color " .. c, c, "Text", 1, y, 90)
  end

  -- Right column: navigation and items
  y = yTop
  y = Section("Pages (Uci.SetPage)", x2, y, colW)
  y = Field("Panels", "Panels", "Text", 2, y, 190)
  y = Field("Add Panel", "Add Panel", "ComboBox", 2, y, 190)
  Label("Empty = do not switch pages.", x2, y, colW, "Left", C.Mid); y = y + ROW
  y = Section("Layers (Uci.SetLayerVisibility)", x2, y, colW)
  y = Field("UCI Name", "UCI Name", "Text", 2, y, 190)
  y = Field("Layer Transition", "Transition", "ComboBox", 2, y, 120)
  y = y + 6
  y = Section("Menu items", x2, y, colW)
  local cols = { { "Label", 70 }, { "Icon", 90 }, { "Page", 60 }, { "Layers", 70 } }
  local x = x2 + 24
  for _, c in ipairs(cols) do Label(c[1], x, y, c[2], "Left", C.Mid); x = x + c[2] + 4 end
  y = y + 20
  for i = 1, n do
    Label(tostring(i), x2, y, 20)
    x = x2 + 24
    for _, c in ipairs(cols) do
      layout[c[1] .. " " .. i] = { PrettyName = "Menu~" .. i .. "~" .. c[1],
        Style = c[1] == "Icon" and "ComboBox" or "Text", Position = { x, y }, Size = { c[2], 20 } }
      x = x + c[2] + 4
    end
    y = y + ROW
  end
  Label("Layers: comma-separated, on the item's Page.", x2, y + 4, colW, "Left", C.Mid)

elseif CurrentPage == "About" then
  local W = 560
  LevoBrand.Background(graphics, W, 440)
  local y = LevoBrand.Header(graphics, W, LevoBrand.PluginName(PluginInfo), CurrentPage) + 16
  y = LevoBrand.About(graphics, M, y, W - 2 * M, PluginInfo)
  Label("Icons: Material Symbols by Google, Apache License 2.0.", M, y + 4, W - 2 * M, "Left", C.Mid)
end
