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
  local cfg = ArtNetConfig.Universe(props, universe)
  local receive = cfg.mode == "Receive"
  local cols = tonumber(props["Knobs per Row"].Value) or 10
  local CELL, KNOB, LABEL_H = 48, 40, 14
  local ROW_H = LABEL_H + KNOB + 10
  local rows = math.ceil(cfg.count / cols)
  local W = math.max(2 * M + cols * CELL, 520)
  local H = LevoBrand.HeaderHeight + 2 + 120 + rows * ROW_H + M
  local grp = "Universe " .. universe .. "~"
  local p = "U" .. universe .. " "

  LevoBrand.Background(graphics, W, H)
  local y = LevoBrand.Header(graphics, W, LevoBrand.PluginName(PluginInfo),
    CurrentPage .. (receive and " - Receive" or " - Send")) + 12

  if receive then
    Place(p .. "Data", grp .. "Data", M, y + 2, 20, 20, { Style = "Led", Color = C.Amber, UnlinkOffColor = false })
    Label("Data", M + 26, y + 3, 60, 18, { color = C.Mid, size = 10 })
    Place("Status", "Status", M + 100, y, W - 2 * M - 100, 24)
  else
    Place("Blackout", "Blackout", M, y, 90, 24,
      { Style = "Button", Legend = "Blackout", FontSize = 11, FontStyle = "Bold", Color = C.Amber })
    Place("Status", "Status", M + 100, y, W - 2 * M - 100, 24)
  end
  y = y + 30
  Place(p .. "Info", grp .. "Info", M, y, W - 2 * M, 18, INFO)
  y = y + 26

  y = Section(receive and "Incoming Channels" or "Channels", M, y, W - 2 * M)
  for i = 0, cfg.count - 1 do
    local ch = cfg.first + i
    local col, row = i % cols, i // cols
    local x = M + col * CELL
    local cy = y + row * ROW_H
    Label(tostring(ch), x, cy, CELL - 8, LABEL_H, { size = 10, align = "Center", color = C.Mid })
    Place(p .. "Ch " .. ch, grp .. "Ch " .. ch, x + (CELL - 8 - KNOB) // 2, cy + LABEL_H, KNOB, KNOB,
      { Style = "Knob", Color = receive and C.Atlantic or C.Amber, IsReadOnly = receive or nil })
  end

-- ------------------------------------------------------------ setup
elseif CurrentPage == "Setup" then
  local count = ArtNetConfig.Count(props)
  local W = 600
  local H = LevoBrand.HeaderHeight + 2 + 120 + count * 62 + 190
  LevoBrand.Background(graphics, W, H)
  local y = LevoBrand.Header(graphics, W, LevoBrand.PluginName(PluginInfo), CurrentPage) + 12

  y = Section("Universes", M, y, W - 2 * M)
  local X_IP, X_NET, X_SUB, X_UNI, X_A, X_B = M + 92, M + 228, M + 282, M + 336, M + 398, M + 470
  local function Head(t, x, w, align) Label(t, x, y, w, 16, { size = 10, color = C.Mid, align = align or "Center" }) end

  for u = 1, count do
    local cfg = ArtNetConfig.Universe(props, u)
    local receive = cfg.mode == "Receive"
    local p = "U" .. u .. " "
    local grp = "Setup~Universe " .. u .. "~"
    Head(receive and "Source filter (optional)" or "Target IP", X_IP, 130, "Left")
    Head("Net", X_NET, 48); Head("Sub-Net", X_SUB, 48); Head("Universe", X_UNI, 48)
    if receive then Head("Timeout s", X_A, 60); Head("On loss", X_B, 80)
    else Head("Output", X_A, 64) end
    y = y + 18
    Label("Universe " .. u, M, y - 2, 86, 16, { style = "Bold" })
    Label(string.format("%s  %d-%d", cfg.mode, cfg.first, cfg.last), M, y + 12, 86, 14, { size = 9, color = C.Mid })
    if receive then
      Place(p .. "Source Filter", grp .. "Source Filter", X_IP, y, 130, 22, TEXT)
    else
      Place(p .. "Target IP", grp .. "Target IP", X_IP, y, 130, 22, TEXT)
    end
    Place(p .. "Net", grp .. "Net", X_NET, y, 48, 22, TEXT)
    Place(p .. "SubNet", grp .. "Sub-Net", X_SUB, y, 48, 22, TEXT)
    Place(p .. "Universe", grp .. "Universe", X_UNI, y, 48, 22, TEXT)
    if receive then
      Place(p .. "Timeout", grp .. "Timeout", X_A, y, 60, 22, TEXT)
      Place(p .. "On Loss", grp .. "On Loss", X_B, y, 80, 22, { Style = "ComboBox", FontSize = 11 })
    else
      Place(p .. "Enable", grp .. "Enable", X_A, y, 64, 22,
        { Style = "Button", Legend = "Enable", FontSize = 10, Color = C.Amber })
    end
    Place(p .. "Info", grp .. "Info", X_IP, y + 24, W - M - X_IP, 18, INFO)
    y = y + 50
  end

  y = Section("Network", M, y + 4, W - 2 * M)
  Place("Broadcast", "Setup~Broadcast", M, y, 90, 22,
    { Style = "Button", Legend = "Broadcast", FontSize = 10, Color = C.Amber })
  Label("Address", M + 100, y + 2, 56, 18, { align = "Right", color = C.Mid, size = 10 })
  Place("Broadcast Address", "Setup~Broadcast Address", M + 162, y, 130, 22, TEXT)
  Label("Send universes: off = unicast to Target IP", M + 302, y + 2, W - M - 302 - M, 18, { size = 10, color = C.Mid })
  y = y + 32
  Label("Node Name", M, y + 2, 80, 18, { color = C.Mid, size = 10 })
  Place("Node Name", "Setup~Node Name", M + 92, y, 160, 22, TEXT)
  Place("Discovery", "Setup~Discovery", M + 262, y + 2, W - M - 262 - M, 18, INFO)
  y = y + 32
  Place("Send in Emulation", "Setup~Send in Emulation", M, y, 90, 22,
    { Style = "Button", Legend = "Emulation TX", FontSize = 10, Color = C.Amber })
  Label("Send Art-Net while the design runs in Emulation mode", M + 100, y + 2, W - 2 * M - 100, 18, { size = 10, color = C.Mid })
  y = y + 32
  Label("Status", M, y + 2, 80, 18, { color = C.Mid, size = 10 })
  Place("Status", "Status", M + 92, y, W - 2 * M - 92, 24)

-- ------------------------------------------------------------ about
elseif CurrentPage == "About" then
  local W, H = 520, 400
  LevoBrand.Background(graphics, W, H)
  local y = LevoBrand.Header(graphics, W, LevoBrand.PluginName(PluginInfo), CurrentPage) + 16
  LevoBrand.About(graphics, M, y, W - 2 * M, PluginInfo)
end
