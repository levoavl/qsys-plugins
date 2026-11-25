-- (c) levo AVL | Elias Jenny - MIT License
-- All settings live in the property panel. Per-item properties exist for the maximum
-- number of items and are hidden in rectify.lua when not needed.

local MAX_ITEMS = 12
local function Hex(rgb) return string.format("#%02X%02X%02X", rgb[1], rgb[2], rgb[3]) end
local C = LevoBrand.Colors

-- Bar geometry
table.insert(props, { Name = "Menu Count",   Type = "integer", Min = 2, Max = MAX_ITEMS, Value = 4 })
table.insert(props, { Name = "Orientation",  Type = "enum", Choices = { "Horizontal", "Vertical" }, Value = "Horizontal" })
table.insert(props, { Name = "Item Width",   Type = "integer", Min = 30, Max = 1000, Value = 200 })
table.insert(props, { Name = "Item Height",  Type = "integer", Min = 30, Max = 600, Value = 80 })
table.insert(props, { Name = "Item Spacing", Type = "integer", Min = 0, Max = 200, Value = 0 })  -- px gap between items
table.insert(props, { Name = "Corner Radius", Type = "integer", Min = 0, Max = 300, Value = 0 })
table.insert(props, { Name = "Rounded Corners", Type = "enum", Choices = { "Bar Ends", "Each Item" }, Value = "Bar Ends" })

-- Item content
table.insert(props, { Name = "Content",     Type = "enum", Choices = { "Text", "Icon", "Icon + Text" }, Value = "Text" })
table.insert(props, { Name = "Font",        Type = "enum",
  Choices = { "Arial", "Helvetica", "Verdana", "Tahoma", "Trebuchet MS", "Georgia" }, Value = "Arial" })
table.insert(props, { Name = "Font Size",   Type = "integer", Min = 8, Max = 72, Value = 22 })
table.insert(props, { Name = "Bold Active", Type = "boolean", Value = true })
table.insert(props, { Name = "Icon Size",   Type = "integer", Min = 12, Max = 300, Value = 36 })
table.insert(props, { Name = "Fill Active Icon", Type = "boolean", Value = true })

-- Indicator
table.insert(props, { Name = "Indicator Style",  Type = "enum", Choices = { "None", "Line", "Pill", "Block" }, Value = "Line" })
table.insert(props, { Name = "Line Position",    Type = "enum", Choices = { "Bottom / Right", "Top / Left" }, Value = "Bottom / Right" })
table.insert(props, { Name = "Indicator Size",   Type = "integer", Min = 1, Max = 40, Value = 6 })   -- line thickness
table.insert(props, { Name = "Indicator Margin", Type = "integer", Min = 0, Max = 100, Value = 0 })  -- gap to the item edges

-- Dividers between items
table.insert(props, { Name = "Dividers",       Type = "boolean", Value = false })
table.insert(props, { Name = "Divider Length", Type = "integer", Min = 5, Max = 100, Value = 60 })  -- % of item height/width
table.insert(props, { Name = "Divider Width",  Type = "integer", Min = 1, Max = 10, Value = 2 })

-- Colours (hex, or "none" for transparent)
table.insert(props, { Name = "Color Background",  Type = "string", Value = Hex(C.Porcelain) })
table.insert(props, { Name = "Color Text",        Type = "string", Value = Hex(C.Onyx) })
table.insert(props, { Name = "Color Active Text", Type = "string", Value = Hex(C.Atlantic) })
table.insert(props, { Name = "Color Indicator",   Type = "string", Value = Hex(C.Amber) })
table.insert(props, { Name = "Color Divider",     Type = "string", Value = Hex(C.Line) })

-- Behaviour
table.insert(props, { Name = "Animation Time",   Type = "integer", Min = 0, Max = 2000, Value = 300 })  -- ms, 0 = jump
table.insert(props, { Name = "Navigation",       Type = "enum", Choices = { "Page", "Layer", "Output Only" }, Value = "Page" })
table.insert(props, { Name = "Panels",           Type = "string", Value = "" })  -- Page mode: Inventory names, comma-separated
table.insert(props, { Name = "UCI Name",         Type = "string", Value = "" })  -- Layer mode
table.insert(props, { Name = "Layer Transition", Type = "enum",
  Choices = { "none", "fade", "left", "right", "top", "bottom" }, Value = "fade" })

-- Menu items
local icons = { "(none)" }
for _, name in ipairs(MenuIconNames) do table.insert(icons, name) end
for i = 1, MAX_ITEMS do
  table.insert(props, { Name = ("Menu %d Label"):format(i),  Type = "string", Value = "Menu " .. i })
  table.insert(props, { Name = ("Menu %d Icon"):format(i),   Type = "enum", Choices = icons, Value = "(none)" })
  table.insert(props, { Name = ("Menu %d Page"):format(i),   Type = "string", Value = "" })
  table.insert(props, { Name = ("Menu %d Layers"):format(i), Type = "string", Value = "" })  -- comma-separated
end

table.insert(props, {
  Name = "Debug Print",
  Type = "enum",
  Choices = { "None", "Basic", "Verbose" },
  Value = "None",
})
