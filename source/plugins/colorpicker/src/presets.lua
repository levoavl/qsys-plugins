-- (c) levo AVL | Elias Jenny - MIT License
-- Fixed preset colours and the colour wheel, shared by layout and runtime.

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

-- Colour wheel on a d x d grid of cells (d odd, centre cell = white):
-- hue = angle (red on top, clockwise), saturation = distance from the centre,
-- always at full brightness. Returns hue, saturation of a cell, or nil when the
-- cell lies outside the circle.
function WheelCell(row, col, d)
  local c = (d + 1) / 2
  local radius = (d - 1) / 2
  local dx, dy = col - c, row - c
  local dist = math.sqrt(dx * dx + dy * dy)
  if dist > radius + 0.5 then return nil end
  local hue = math.deg(math.atan(dx, -dy)) % 360  -- Lua 5.3: two-argument atan
  return hue, math.min(1, dist / radius)
end
