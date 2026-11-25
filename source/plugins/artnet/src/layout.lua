-- (c) levo AVL | Elias Jenny - MIT License
local C = LevoBrand.Colors
local M = 16  -- page margin

local function Label(text, x, y, w, h, opts)
  opts = opts or {}
  table.insert(graphics, {
    Type = "Text", Text = text, Position = { x, y }, Size = { w, h or 18 },
    FontSize = opts.size or 11, FontStyle = opts.style or "Regular",
    HTextAlign = opts.align or "Left", Color = opts.color or C.Onyx,
  })
end

local function Section(text, x, y, w)
  Label(text, x, y, w, 20, { size = 13, style = "Bold", color = C.Atlantic })
  table.insert(graphics, {
    Type = "GroupBox", Fill = C.Amber, StrokeWidth = 0, CornerRadius = 0,
    Position = { x, y + 20 }, Size = { w, 2 },
  })
  return y + 30
end

local function Place(name, pretty, x, y, w, h, extra)
  local def = { PrettyName = pretty, Position = { x, y }, Size = { w, h } }
  for k, v in pairs(extra or {}) do def[k] = v end
  layout[name] = def
end

local TEXT = { Style = "Text", FontSize = 11 }
local INFO = { Style = "Text", FontSize = 10, Color = C.Porcelain, StrokeWidth = 0, TextColor = C.Mid, HTextAlign = "Left" }

-- ------------------------------------------------------------ universe pages
local universe = tonumber(CurrentPage:match("^Universe (%d+)$"))

if universe then
  local cols = tonumber(props["Knobs per Row"].Value) or 10
  local channels = props["Channels U" .. universe].Value
  local CELL, KNOB, LABEL_H = 48, 40, 14
  local ROW_H = LABEL_H + KNOB + 10
  local rows = math.ceil(channels / cols)
  local W = math.max(2 * M + cols * CELL, 520)
  local H = LevoBrand.HeaderHeight + 2 + 120 + rows * ROW_H + M

  LevoBrand.Background(graphics, W, H)
  local y = LevoBrand.Header(graphics, W, LevoBrand.PluginName(PluginInfo), CurrentPage) + 12

  Place("Blackout", "Blackout", M, y, 90, 24,
    { Style = "Button", Legend = "Blackout", FontSize = 11, FontStyle = "Bold", Color = C.Amber })
  Place("Status", "Status", M + 100, y, W - 2 * M - 100, 24)
  y = y + 30
  Place("U" .. universe .. " Info", "Universe " .. universe .. "~Info", M, y, W - 2 * M, 18, INFO)
  y = y + 26

  y = Section("Channels", M, y, W - 2 * M)
  local p = "U" .. universe .. " "
  for ch = 1, channels do
    local col, row = (ch - 1) % cols, (ch - 1) // cols
    local x = M + col * CELL
    local cy = y + row * ROW_H
    Label(tostring(ch), x, cy, CELL - 8, LABEL_H, { size = 10, align = "Center", color = C.Mid })
    Place(p .. "Ch " .. ch, "Universe " .. universe .. "~Ch " .. ch,
      x + (CELL - 8 - KNOB) // 2, cy + LABEL_H, KNOB, KNOB, { Style = "Knob", Color = C.Amber })
  end

-- ------------------------------------------------------------ setup
elseif CurrentPage == "Setup" then
  local count = props["Universe Count"].Value
  local W = 560
  local H = LevoBrand.HeaderHeight + 2 + 120 + count * 54 + 190
  LevoBrand.Background(graphics, W, H)
  local y = LevoBrand.Header(graphics, W, LevoBrand.PluginName(PluginInfo), CurrentPage) + 12

  y = Section("Universes", M, y, W - 2 * M)
  -- column x positions
  local X_IP, X_NET, X_SUB, X_UNI, X_EN = M + 84, M + 220, M + 274, M + 328, M + 392
  Label("Target IP", X_IP, y, 130, 16, { size = 10, color = C.Mid })
  Label("Net", X_NET, y, 48, 16, { size = 10, color = C.Mid, align = "Center" })
  Label("Sub-Net", X_SUB, y, 48, 16, { size = 10, color = C.Mid, align = "Center" })
  Label("Universe", X_UNI, y, 48, 16, { size = 10, color = C.Mid, align = "Center" })
  Label("Output", X_EN, y, 64, 16, { size = 10, color = C.Mid, align = "Center" })
  y = y + 18

  for u = 1, count do
    local p = "U" .. u .. " "
    local grp = "Setup~Universe " .. u .. "~"
    Label("Universe " .. u, M, y, 80, 22, { style = "Bold" })
    Place(p .. "Target IP", grp .. "Target IP", X_IP, y, 130, 22, TEXT)
    Place(p .. "Net", grp .. "Net", X_NET, y, 48, 22, TEXT)
    Place(p .. "SubNet", grp .. "Sub-Net", X_SUB, y, 48, 22, TEXT)
    Place(p .. "Universe", grp .. "Universe", X_UNI, y, 48, 22, TEXT)
    Place(p .. "Enable", grp .. "Enable", X_EN, y, 64, 22,
      { Style = "Button", Legend = "Enable", FontSize = 10, Color = C.Amber })
    Place(p .. "Info", grp .. "Info", X_IP, y + 24, W - M - X_IP, 18, INFO)
    y = y + 54
  end

  y = Section("Network", M, y + 4, W - 2 * M)
  Place("Broadcast", "Setup~Broadcast", M, y, 90, 22,
    { Style = "Button", Legend = "Broadcast", FontSize = 10, Color = C.Amber })
  Label("Address", M + 100, y + 2, 56, 18, { align = "Right", color = C.Mid, size = 10 })
  Place("Broadcast Address", "Setup~Broadcast Address", M + 162, y, 130, 22, TEXT)
  Label("Off = unicast to each universe's Target IP", M + 302, y + 2, W - M - 302 - M, 18, { size = 10, color = C.Mid })
  y = y + 32
  Label("Node Name", M, y + 2, 80, 18, { color = C.Mid, size = 10 })
  Place("Node Name", "Setup~Node Name", M + 84, y, 160, 22, TEXT)
  Place("Discovery", "Setup~Discovery", M + 254, y + 2, W - M - 254 - M, 18, INFO)
  y = y + 32
  Place("Send in Emulation", "Setup~Send in Emulation", M, y, 90, 22,
    { Style = "Button", Legend = "Emulation TX", FontSize = 10, Color = C.Amber })
  Label("Send Art-Net while the design runs in Emulation mode", M + 100, y + 2, W - 2 * M - 100, 18, { size = 10, color = C.Mid })
  y = y + 32
  Label("Status", M, y + 2, 80, 18, { color = C.Mid, size = 10 })
  Place("Status", "Status", M + 84, y, W - 2 * M - 84, 24)

-- ------------------------------------------------------------ about
elseif CurrentPage == "About" then
  local W, H = 520, 400
  LevoBrand.Background(graphics, W, H)
  local y = LevoBrand.Header(graphics, W, LevoBrand.PluginName(PluginInfo), CurrentPage) + 16
  LevoBrand.About(graphics, M, y, W - 2 * M, PluginInfo)
end
