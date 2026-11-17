-- (c) levo AVL | Elias Jenny - MIT License
local C = LevoBrand.Colors
local topo = AtemTopology.Resolve(props)
local mode = AtemTopology.ButtonMode(props)
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
  return y + 28
end

local function Place(name, pretty, x, y, w, h, extra)
  local def = { PrettyName = pretty, Position = { x, y }, Size = { w, h } }
  for k, v in pairs(extra or {}) do def[k] = v end
  layout[name] = def
end

local function Button(name, pretty, legend, x, y, w, h, color, extra)
  local def = { Style = "Button", Legend = legend, FontSize = 11, FontStyle = "Bold", Color = color or C.Amber }
  for k, v in pairs(extra or {}) do def[k] = v end
  Place(name, pretty, x, y, w, h, def)
end

local W, H = 640, 400
local y = LevoBrand.HeaderHeight + 2 + 10

local BW, BH, GAP = 60, 40, 4   -- source buttons
local meIndex = CurrentPage and tonumber(CurrentPage:match("^M/E (%d+)$"))

if meIndex then
  local me = meIndex
  local p = "ME" .. me .. " "
  local g = "M/E " .. me .. "~"
  local ids = AtemTopology.MEButtonSources(topo, me, mode)
  local n = #ids
  local rows = math.max(1, math.ceil(n / 16))
  local cols = math.max(1, math.ceil(n / rows))
  local gridW = cols * (BW + GAP) - GAP
  local contentW = math.max(gridW, 760)
  W = M * 2 + contentW

  local function Bus(bus, color)
    y = Section(bus, M, y, contentW)
    Label(bus .. " source", M + contentW - 330, y - 28, 120, 20, { align = "Right", color = C.Mid })
    Place(p .. bus, g .. bus .. "~Source", M + contentW - 200, y - 28, 200, 20, { Style = "ComboBox" })
    for i, id in ipairs(ids) do
      local key, short = AtemTopology.SourceKey(id)
      local col, row = (i - 1) % cols, (i - 1) // cols
      Button(p .. bus .. " " .. key, g .. bus .. "~" .. key, short,
        M + col * (BW + GAP), y + row * (BH + GAP), BW, BH, color)
    end
    if n == 0 then
      Label("Source buttons are off (property \"Source Buttons\") - use the combo box.", M, y, contentW, 18,
        { size = 10, color = C.Mid })
      y = y + 24
    else
      y = y + rows * (BH + GAP) + 8
    end
  end
  Bus("Program", C.Amber)
  Bus("Preview", C.Atlantic)

  -- Transition area: settings on the left, Cut / Auto / T-bar / FTB on the right
  y = Section("Transition", M, y, contentW)
  local top = y
  local lx, lw = M, 96
  local SW = 64
  Label("Style", lx, y + 6, lw - 8, 18, { align = "Right" })
  for i, style in ipairs(AtemTopology.TransitionStyles) do
    Button(p .. "Style " .. style, g .. "Transition~Style " .. style, style:upper(),
      lx + lw + (i - 1) * (SW + GAP), y, SW, 30, C.Atlantic, { FontSize = 10 })
  end
  y = y + 36
  Label("Next", lx, y + 6, lw - 8, 18, { align = "Right" })
  Button(p .. "Next Background", g .. "Transition~Next Background", "BKGD", lx + lw, y, SW, 30, C.Amber, { FontSize = 10 })
  for k = 1, topo.USKs do
    Button(p .. "Next Key " .. k, g .. "Transition~Next Key " .. k, "KEY " .. k,
      lx + lw + k * (SW + GAP), y, SW, 30, C.Amber, { FontSize = 10 })
  end
  y = y + 36
  if topo.USKs > 0 then
    Label("Key On Air", lx, y + 6, lw - 8, 18, { align = "Right" })
    for k = 1, topo.USKs do
      Button(p .. "Key " .. k .. " On Air", g .. "Keyers~Key " .. k .. " On Air", "ON AIR",
        lx + lw + k * (SW + GAP), y, SW, 30, C.Amber, { FontSize = 10 })
    end
    y = y + 36
  end
  Label("Rate (frames)", lx, y + 3, lw - 8, 18, { align = "Right" })
  Place(p .. "Transition Rate", g .. "Transition~Rate", lx + lw, y, SW, 22, { Style = "Text" })
  Label("Style", lx + lw + SW + 12, y + 3, 40, 18, { align = "Right" })
  Place(p .. "Transition Style", g .. "Transition~Style", lx + lw + SW + 56, y, 120, 22, { Style = "ComboBox" })
  y = y + 30
  Label("Preview Trans.", lx, y + 6, lw - 8, 18, { align = "Right" })
  Button(p .. "Preview Transition", g .. "Transition~Preview Transition", "PREV TRANS", lx + lw, y, SW * 2 + GAP, 30,
    C.Amber, { FontSize = 10 })
  local leftBottom = y + 36

  -- right block
  local rx = M + contentW - 300
  y = top
  Button(p .. "Cut", g .. "Transition~Cut", "CUT", rx, y, 90, 56, C.Atlantic, { FontSize = 14 })
  Button(p .. "Auto", g .. "Transition~Auto", "AUTO", rx, y + 64, 90, 56, C.Amber, { FontSize = 14 })
  Label("In Transition", rx - 4, y + 128, 80, 16, { size = 10, color = C.Mid })
  Place(p .. "In Transition", g .. "Transition~In Transition", rx + 76, y + 128, 14, 14, { Color = C.Amber })
  Place(p .. "T-Bar", g .. "Transition~T-Bar", rx + 110, y, 44, 150, { Style = "Fader", Color = C.Atlantic })
  Button(p .. "Fade to Black", g .. "Fade to Black~Fade to Black", "FTB", rx + 190, y, 90, 56, C.Amber, { FontSize = 14 })
  Label("FTB rate", rx + 190, y + 64, 90, 16, { size = 10, color = C.Mid })
  Place(p .. "Fade to Black Rate", g .. "Fade to Black~Rate", rx + 190, y + 80, 90, 22, { Style = "Text" })

  H = math.max(leftBottom, top + 160) + M

elseif CurrentPage == "Setup" then
  local lw, fx = 120, M + 128
  W = 760
  y = Section("Connection", M, y, W - 2 * M)
  local function Row(label, name, pretty, w, extra)
    Label(label, M, y + 1, lw, 20, { align = "Right" })
    Place(name, pretty, fx, y, w, 22, extra)
    y = y + 28
  end
  local FLAT = { Style = "Text", Color = C.Porcelain, StrokeWidth = 0, FontSize = 11, TextColor = C.Onyx, HTextAlign = "Left" }
  Row("IP Address", "IP Address", "Setup~IP Address", 160, { Style = "Text" })
  Label("Status", M, y + 1, lw, 20, { align = "Right" })
  Place("Status", "Status", fx, y, 360, 22)
  Button("Reconnect", "Setup~Reconnect", "Reconnect", fx + 370, y, 100, 22, C.Amber, { FontSize = 11, FontStyle = "Regular" })
  y = y + 28
  Label("Connected", M, y, lw, 18, { align = "Right" })
  Place("Connected", "Connected", fx, y + 1, 16, 16, { Color = C.Amber })
  y = y + 26
  Label("Plugin model", M, y + 1, lw, 20, { align = "Right" })
  Label(topo.Name, fx + 4, y + 1, 400, 20)
  y = y + 26
  Row("Device", "Device", "Setup~Device", 360, FLAT)
  Row("Protocol", "Protocol Version", "Setup~Protocol Version", 120, FLAT)
  Row("Last Error", "Last Error", "Debug~Last Error", 560, { Style = "Text" })
  Row("Reconnects", "Reconnects", "Debug~Reconnects", 80, { Style = "Text" })
  y = y + 6

  local ids = AtemTopology.ButtonSourceUnion(topo, mode)
  if #ids > 0 then
    y = Section("Source Names (from switcher)", M, y, W - 2 * M)
    local cols, cw = 3, (W - 2 * M) // 3
    for i, id in ipairs(ids) do
      local key = AtemTopology.SourceKey(id)
      local col, row = (i - 1) % cols, (i - 1) // cols
      local x, ry = M + col * cw, y + row * 24
      Label(key, x, ry + 1, 90, 18, { align = "Right", size = 10, color = C.Mid })
      Place("Name " .. key, "Source Names~" .. key, x + 96, ry, cw - 104, 20, FLAT)
    end
    y = y + math.ceil(#ids / cols) * 24 + 6
  end
  H = y + M

elseif CurrentPage == "About" then
  y = y + 4
  local endY = LevoBrand.About(graphics, M, y, W - 2 * M, PluginInfo)
  Label("ATEM protocol handling based on Sofie ATEM Connection (NRK, MIT License); model data from the",
    M, endY + 8, W - 2 * M, 16, { size = 10, color = C.Mid })
  Label("Bitfocus Companion module bmd-atem (Bitfocus AS, MIT License). ATEM is a trademark of Blackmagic Design.",
    M, endY + 24, W - 2 * M, 16, { size = 10, color = C.Mid })
  H = endY + 52
end

-- Background and header go below everything else: prepend them.
local front = {}
LevoBrand.Background(front, W, H)
LevoBrand.Header(front, W, LevoBrand.PluginName(PluginInfo), CurrentPage)
for i = #front, 1, -1 do table.insert(graphics, 1, front[i]) end
