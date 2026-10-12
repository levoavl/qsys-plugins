-- levo AVL branding for Q-SYS plugin layouts
-- Shared by all plugins in this repository; included once at the top of each
-- plugin's plugin.lua (after info.lua).
--
-- (c) levo AVL | Elias Jenny - MIT License

--[[ #include "levo_assets.lua" ]]

LevoBrand = {
  Company = "levo AVL",
  Author  = "levo AVL | Elias Jenny",
  Address = { "Printzstraße 4", "76139 Karlsruhe", "Germany" },
  Web     = "www.levo.de",
  Mail    = "hello@levo.de",
  Repo    = "github.com/levoavl/qsys-plugins",
  License = "MIT License",

  -- levo AVL colour system (RGB for digital use)
  Colors = {
    Atlantic  = { 0, 70, 140 },     -- primary
    Amber     = { 255, 184, 48 },   -- accent, highlights, call-to-action
    Porcelain = { 245, 245, 243 },  -- light background
    Onyx      = { 25, 25, 25 },     -- text, contrast
    Mid       = { 120, 120, 120 },  -- secondary text (derived)
  },

  HeaderHeight = 48,
}

local C = LevoBrand.Colors

local function Image(asset, x, y, w)
  local h = math.floor(w * asset.Height / asset.Width + 0.5)
  return { Type = "Image", Image = asset.Data, Position = { x, y }, Size = { w, h } }, h
end

local function Text(text, x, y, w, h, size, color, style, align)
  return {
    Type = "Text", Text = text,
    Position = { x, y }, Size = { w, h },
    FontSize = size, FontStyle = style or "Regular",
    HTextAlign = align or "Left",
    Color = color or C.Onyx,
  }
end

-- Page background in Porcelain. Call first so everything else draws on top.
function LevoBrand.Background(graphics, width, height)
  table.insert(graphics, {
    Type = "GroupBox", Fill = C.Porcelain, StrokeWidth = 0, CornerRadius = 0,
    Position = { 0, 0 }, Size = { width, height },
  })
end

-- Atlantic header bar with the porcelain wordmark on the left and the plugin
-- title on the right. Returns the y coordinate where page content can start.
function LevoBrand.Header(graphics, width, title)
  local h = LevoBrand.HeaderHeight
  table.insert(graphics, {
    Type = "GroupBox", Fill = C.Atlantic, StrokeWidth = 0, CornerRadius = 0,
    Position = { 0, 0 }, Size = { width, h },
  })
  local logo, logoH = Image(LevoAssets.wordmark_porcelain, 12, 0, 96)
  logo.Position[2] = math.floor((h - logoH) / 2)
  table.insert(graphics, logo)
  if title then
    table.insert(graphics, Text(title, 120, 0, width - 132, h, 14, C.Porcelain, "Bold", "Right"))
  end
  -- thin amber accent line under the header
  table.insert(graphics, {
    Type = "GroupBox", Fill = C.Amber, StrokeWidth = 0, CornerRadius = 0,
    Position = { 0, h }, Size = { width, 3 },
  })
  return h + 3
end

-- Content of the "About" page. `info` is the plugin's PluginInfo table.
function LevoBrand.About(graphics, x, y, width, info)
  local line = 18
  local logo, logoH = Image(LevoAssets.wordmark_atlantic, x, y, 160)
  table.insert(graphics, logo)
  y = y + logoH + 16

  local name = info.Name:gsub("^.-~", "")  -- strip the "levo AVL~" library folder
  table.insert(graphics, Text(name, x, y, width, 22, 16, C.Atlantic, "Bold"))
  y = y + 24
  table.insert(graphics, Text("Version " .. (info.BuildVersion or info.Version), x, y, width, line, 11, C.Mid))
  y = y + line + 12

  local rows = {
    LevoBrand.Company,
    LevoBrand.Address[1],
    LevoBrand.Address[2] .. ", " .. LevoBrand.Address[3],
    LevoBrand.Web .. "  ·  " .. LevoBrand.Mail,
  }
  for _, r in ipairs(rows) do
    table.insert(graphics, Text(r, x, y, width, line, 12, C.Onyx))
    y = y + line
  end
  y = y + 12

  table.insert(graphics, Text("Author: " .. LevoBrand.Author, x, y, width, line, 11, C.Onyx))
  y = y + line
  table.insert(graphics, Text("Source & updates: " .. LevoBrand.Repo, x, y, width, line, 11, C.Onyx))
  y = y + line
  table.insert(graphics, Text("Licensed under the " .. LevoBrand.License .. ". Provided as is, without warranty.",
    x, y, width, line, 11, C.Mid))
  y = y + line + 12

  table.insert(graphics, Text(
    "Not affiliated with or endorsed by QSC, LLC or the manufacturer of the controlled device. "
      .. "All trademarks belong to their respective owners.",
    x, y, width, line * 2, 10, C.Mid))
  return y + line * 2
end
