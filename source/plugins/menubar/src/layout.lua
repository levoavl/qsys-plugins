-- (c) levo AVL | Elias Jenny - MIT License
-- The Control page shows the menu bar at its real size and spacing, so the items can be
-- selected together and copied onto a UCI in one go.
local n        = props["Menu Count"].Value
local vertical = props["Orientation"].Value == "Vertical"
local IW, IH   = props["Item Width"].Value, props["Item Height"].Value
local SP       = props["Item Spacing"].Value
local C  = LevoBrand.Colors
local M  = 16

local barW = vertical and IW or (n * IW + (n - 1) * SP)
local barH = vertical and (n * IH + (n - 1) * SP) or IH

local function Label(text, x, ly, w, align, color, style)
  table.insert(graphics, {
    Type = "Text", Text = text, Position = { x, ly }, Size = { w, 20 },
    FontSize = 12, FontStyle = style or "Regular", HTextAlign = align or "Right", Color = color or C.Onyx,
  })
end

if CurrentPage == "Control" then
  local W = math.max(520, barW + 2 * M + (vertical and 40 or 0))
  local H = LevoBrand.HeaderHeight + 2 + 16 + 24 + barH + (vertical and 0 or 24) + 100
  LevoBrand.Background(graphics, W, H)
  local y = LevoBrand.Header(graphics, W, LevoBrand.PluginName(PluginInfo), CurrentPage) + 16
  Label("Menu bar - select all items and copy them onto the UCI", M, y, W - 2 * M, "Left", C.Atlantic, "Bold")
  y = y + 24

  for i = 1, n do
    local x = vertical and M or (M + (i - 1) * (IW + SP))
    local iy = vertical and (y + (i - 1) * (IH + SP)) or y
    layout["Menu " .. i] = { PrettyName = "Menu~" .. i, Style = "Button",
      Position = { x, iy }, Size = { IW, IH }, Margin = 0 }
    -- active LEDs next to (vertical) or below (horizontal) each item
    local lx = vertical and (M + IW + 16) or (x + IW / 2 - 6)
    local ly = vertical and (iy + IH / 2 - 6) or (y + IH + 8)
    layout["Menu Active " .. i] = { PrettyName = "Menu Active~" .. i, Style = "Led",
      Position = { lx, ly }, Size = { 12, 12 } }
  end
  y = y + barH + (vertical and 16 or 32)

  Label("Active Menu", M, y, 100)
  layout["Active Menu"] = { PrettyName = "Active Menu", Style = "Text", Position = { M + 108, y }, Size = { 60, 20 } }
  Label("Lock", M + 180, y, 60)
  layout["Lock"] = { PrettyName = "Lock", Style = "Button", Legend = "Lock",
    Position = { M + 248, y }, Size = { 60, 20 } }
  y = y + 32
  Label("Status", M, y, 100)
  layout["Status"] = { PrettyName = "Status", Position = { M + 108, y }, Size = { W - 2 * M - 108, 20 } }

elseif CurrentPage == "About" then
  local W = 560
  LevoBrand.Background(graphics, W, 440)
  local y = LevoBrand.Header(graphics, W, LevoBrand.PluginName(PluginInfo), CurrentPage) + 16
  y = LevoBrand.About(graphics, M, y, W - 2 * M, PluginInfo)
  Label("Icons: Material Symbols by Google, Apache License 2.0.", M, y + 4, W - 2 * M, "Left", C.Mid)
end
