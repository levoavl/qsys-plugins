-- (c) levo AVL | Elias Jenny - MIT License
-- Fixed preset colours and the picker grid, shared by layout and runtime.

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

-- Grid cell colour. Columns 1..cols run through the hue circle, column cols + 1
-- is a grey ramp. The middle row is fully saturated; rows above get paler,
-- rows below darker.
function GridColor(row, col, rows, cols)
  if col > cols then
    local v = (rows > 1) and (1 - (row - 1) / (rows - 1)) or 1
    return v, v, v
  end
  local hue = (col - 1) * 360 / cols
  local mid = math.ceil(rows / 2)
  local s, v = 1, 1
  if row < mid then
    s = 0.25 + 0.75 * (row - 1) / math.max(1, mid - 1)
  elseif row > mid then
    v = 1 - 0.75 * (row - mid) / math.max(1, rows - mid)
  end
  return ColorMath.HsvToRgb(hue, s, v)
end
