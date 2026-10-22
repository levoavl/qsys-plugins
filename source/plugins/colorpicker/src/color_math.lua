-- (c) levo AVL | Elias Jenny - MIT License
-- Pure colour functions, used by the layout (swatch colours) and the runtime.
-- Colours are r, g, b in 0..1 unless noted otherwise.

ColorMath = {}

local function Clamp01(x)
  if x ~= x or x < 0 then return 0 end  -- x ~= x catches NaN
  if x > 1 then return 1 end
  return x
end
ColorMath.Clamp01 = Clamp01

function ColorMath.To255(x)
  return math.floor(Clamp01(x) * 255 + 0.5)
end

-- {r, g, b} in 0..255, as used by layout Color fields
function ColorMath.LayoutColor(r, g, b)
  return { ColorMath.To255(r), ColorMath.To255(g), ColorMath.To255(b) }
end

-- h 0..360, s and v 0..1
function ColorMath.HsvToRgb(h, s, v)
  s, v = Clamp01(s), Clamp01(v)
  local hh = (h % 360) / 60
  local i = math.floor(hh)
  local f = hh - i
  local p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
  if i == 0 then return v, t, p
  elseif i == 1 then return q, v, p
  elseif i == 2 then return p, v, t
  elseif i == 3 then return p, q, v
  elseif i == 4 then return t, p, v
  end
  return v, p, q
end

-- returns h 0..360, s 0..1, v 0..1 (h = 0 for greys)
function ColorMath.RgbToHsv(r, g, b)
  local max, min = math.max(r, g, b), math.min(r, g, b)
  local d = max - min
  local h = 0
  if d > 0 then
    if max == r then h = 60 * (((g - b) / d) % 6)
    elseif max == g then h = 60 * ((b - r) / d + 2)
    else h = 60 * ((r - g) / d + 4) end
  end
  return h, (max > 0) and (d / max) or 0, max
end

function ColorMath.ToHex(r, g, b)
  return string.format("#%02X%02X%02X", ColorMath.To255(r), ColorMath.To255(g), ColorMath.To255(b))
end

-- Accepts "#RRGGBB", "RRGGBB", "#RGB", "0xRRGGBB" (spaces ignored).
-- Returns r, g, b in 0..1 or nil for invalid input.
function ColorMath.ParseHex(s)
  if type(s) ~= "string" then return nil end
  s = s:gsub("%s", ""):gsub("^#", ""):gsub("^0[xX]", "")
  if #s == 3 then s = s:gsub(".", "%0%0") end
  if not s:match("^%x%x%x%x%x%x$") then return nil end
  return tonumber(s:sub(1, 2), 16) / 255, tonumber(s:sub(3, 4), 16) / 255, tonumber(s:sub(5, 6), 16) / 255
end

-- Black body approximation (Tanner Helland), good enough for LED white points.
-- k in Kelvin, valid 1000..40000.
function ColorMath.Kelvin(k)
  local t = math.max(1000, math.min(40000, k)) / 100
  local r, g, b
  if t <= 66 then
    r = 255
    g = 99.4708025861 * math.log(t) - 161.1195681661
    b = (t <= 19) and 0 or (138.5177312231 * math.log(t - 10) - 305.0447927307)
  else
    r = 329.698727446 * (t - 60) ^ -0.1332047592
    g = 288.1221695283 * (t - 60) ^ -0.0755148492
    b = 255
  end
  return Clamp01(r / 255), Clamp01(g / 255), Clamp01(b / 255)
end

-- Largest amount k (0..1) of emitter colour e that fits into c; c is reduced
-- by k * e in place. A fixture's white or amber LED is described by its colour e.
local function Extract(c, e)
  local k, any = 1, false
  for i = 1, 3 do
    if e[i] > 0.001 then
      any = true
      k = math.min(k, c[i] / e[i])
    end
  end
  if not any then return 0 end
  k = Clamp01(k)
  for i = 1, 3 do c[i] = Clamp01(c[i] - k * e[i]) end
  return k
end

-- Channel values for an LED layout ("RGB", "RGBW", "RGBA", "RGBWA").
-- opts.subtract: true = take the white/amber part out of RGB (accurate colour),
--                false = keep RGB and add white/amber on top (brighter).
-- opts.white / opts.amber: emitter colours { r, g, b }.
-- White is extracted before amber: it takes the common part, amber the warm rest.
-- Returns { R =, G =, B =, W =, A = } (W/A only when the layout has them).
function ColorMath.Mix(r, g, b, layout, opts)
  local c = { Clamp01(r), Clamp01(g), Clamp01(b) }
  local work = opts.subtract and c or { c[1], c[2], c[3] }
  local out = {}
  if layout:find("W", 1, true) then out.W = Extract(work, opts.white) end
  if layout:find("A", 1, true) then out.A = Extract(work, opts.amber) end
  out.R, out.G, out.B = c[1], c[2], c[3]
  return out
end

-- Inverse of Mix: the colour a set of channel values produces.
-- ch = { R =, G =, B =, W =, A = } in 0..1 (missing channels count as 0).
function ColorMath.Unmix(ch, opts)
  local r, g, b = ch.R or 0, ch.G or 0, ch.B or 0
  if opts.subtract then
    local w, a = ch.W or 0, ch.A or 0
    r = r + w * opts.white[1] + a * opts.amber[1]
    g = g + w * opts.white[2] + a * opts.amber[2]
    b = b + w * opts.white[3] + a * opts.amber[3]
  end
  return Clamp01(r), Clamp01(g), Clamp01(b)
end
