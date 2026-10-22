-- (c) levo AVL | Elias Jenny - MIT License
-- Fixed preset colours, picker field and hue strip, shared by layout and runtime.

ColorPresets = {
  { Name = "Red",     Hex = "#FF0000" },
  { Name = "Orange",  Hex = "#FF7F00" },
  { Name = "Amber",   Hex = "#FFBF00" },
  { Name = "Yellow",  Hex = "#FFFF00" },
  { Name = "Lime",    Hex = "#7FFF00" },
  { Name = "Green",   Hex = "#00FF00" },
  { Name = "Spring",  Hex = "#00FF7F" },
  { Name = "Cyan",    Hex = "#00FFFF" },
  { Name = "Azure",   Hex = "#007FFF" },
  { Name = "Blue",    Hex = "#0000FF" },
  { Name = "Violet",  Hex = "#7F00FF" },
  { Name = "Magenta", Hex = "#FF00FF" },
  { Name = "Rose",    Hex = "#FF007F" },
  { Name = "Warm White",    Hex = "#FFB46B" },  -- ~3000 K
  { Name = "Neutral White", Hex = "#FFDBBA" },  -- ~4500 K
  { Name = "White",   Hex = "#FFFFFF" },
}

-- Picker field: n x n cells, saturation left -> right (0..1), brightness
-- top -> bottom (1..0), for the current hue.
function FieldColor(row, col, n, hue)
  local s = (col - 1) / (n - 1)
  local v = 1 - (row - 1) / (n - 1)
  return ColorMath.HsvToRgb(hue, s, v)
end

-- Hue strip: k cells from top (360) to bottom (0), like the vertical hue fader.
-- Returns the hue in the middle of cell i.
function StripHue(i, k)
  return 360 * (k - i + 0.5) / k
end
