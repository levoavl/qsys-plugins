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
local NAME_H = 16
local nameOwner = AtemTopology.NamePlacement(topo, props)
local FLAT = { Style = "Text", Color = C.Porcelain, StrokeWidth = 0, FontSize = 11, TextColor = C.Onyx, HTextAlign = "Left" }

local function GridShape(n)
  local rows = math.max(1, math.ceil(n / 16))
  return math.max(1, math.ceil(n / rows)), rows
end

-- Buttons for `ids`; name(id) -> control name, pretty(id) -> pretty name
local function SourceGrid(ids, x, gy, color, name, pretty)
  local cols, rows = GridShape(#ids)
  for i, id in ipairs(ids) do
    local _, short = AtemTopology.SourceKey(id)
    local col, row = (i - 1) % cols, (i - 1) // cols
    Button(name(id), pretty(id), short, x + col * (BW + GAP), gy + row * (BH + GAP), BW, BH, color)
  end
  return rows * (BH + GAP)
end

-- Source names (from the switcher) in the grid columns of `ids`, for the ones
-- this grid owns. Returns the height used (0 when there is nothing to place).
local function NameGrid(gridKey, ids, x, gy)
  local owned = {}
  for _, id in ipairs(nameOwner[gridKey] or {}) do owned[id] = true end
  if not next(owned) then return 0 end
  local cols, rows = GridShape(#ids)
  for i, id in ipairs(ids) do
    if owned[id] then
      local key = AtemTopology.SourceKey(id)
      local col, row = (i - 1) % cols, (i - 1) // cols
      Place("Name " .. key, "Source Names~" .. key, x + col * (BW + GAP), gy + row * (NAME_H + 2), BW, NAME_H,
        { Style = "Text", Color = C.Porcelain, StrokeWidth = 0, FontSize = 9, TextColor = C.Mid, HTextAlign = "Center" })
    end
  end
  return rows * (NAME_H + 2) + 4
end

local function GridWidth(n)
  local cols = GridShape(n)
  return cols * (BW + GAP) - GAP
end

local function NoButtons(prop, x, gy, w)
  Label("Source buttons are off (property \"" .. prop .. "\") - use the combo box.", x, gy, w, 18,
    { size = 10, color = C.Mid })
  return 24
end

local meIndex = CurrentPage and tonumber(CurrentPage:match("^M/E (%d+)$"))
local auxFirst, auxLast = nil, nil
if CurrentPage == "Aux" then
  auxFirst, auxLast = 1, topo.Aux
elseif CurrentPage then
  local f, l = CurrentPage:match("^Aux (%d+)%-(%d+)$")
  if f then auxFirst, auxLast = tonumber(f), tonumber(l) end
end
local ssIndex = nil
if CurrentPage == "SuperSource" then ssIndex = 1
elseif CurrentPage then ssIndex = tonumber(CurrentPage:match("^SuperSource (%d+)$")) end

if meIndex then
  local me = meIndex
  local p = "ME" .. me .. " "
  local g = "M/E " .. me .. "~"
  local ids = AtemTopology.MEButtonSources(topo, me, mode)
  local contentW = math.max(GridWidth(#ids), 760)
  W = M * 2 + contentW

  local function Bus(bus, color)
    y = Section(bus, M, y, contentW)
    Label(bus .. " source", M + contentW - 330, y - 28, 120, 20, { align = "Right", color = C.Mid })
    Place(p .. bus, g .. bus .. "~Source", M + contentW - 200, y - 28, 200, 20, { Style = "ComboBox" })
    if #ids == 0 then
      y = y + NoButtons("Source Buttons", M, y, contentW)
    else
      y = y + SourceGrid(ids, M, y, color,
        function(id) return p .. bus .. " " .. AtemTopology.SourceKey(id) end,
        function(id) return g .. bus .. "~" .. AtemTopology.SourceKey(id) end) + 4
    end
  end
  Bus("Preview", C.TallyGreen)
  Bus("Program", C.TallyRed)
  y = y + NameGrid("me" .. me, ids, M, y) + 4

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
        lx + lw + k * (SW + GAP), y, SW, 30, C.TallyRed, { FontSize = 10 })
    end
    y = y + 36
  end
  Label("Rate", lx, y + 3, lw - 8, 18, { align = "Right" })
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
  Button(p .. "Auto", g .. "Transition~Auto", "AUTO", rx, y + 64, 90, 56, C.TallyRed, { FontSize = 14 })
  Label("In Transition", rx - 4, y + 128, 80, 16, { size = 10, color = C.Mid })
  Place(p .. "In Transition", g .. "Transition~In Transition", rx + 76, y + 128, 14, 14, { Color = C.Amber })
  Place(p .. "T-Bar", g .. "Transition~T-Bar", rx + 110, y, 44, 150, { Style = "Fader", Color = C.Atlantic })
  Button(p .. "Fade to Black", g .. "Fade to Black~Fade to Black", "FTB", rx + 190, y, 90, 56, C.TallyRed, { FontSize = 14 })
  Label("FTB rate", rx + 190, y + 64, 90, 16, { size = 10, color = C.Mid })
  Place(p .. "Fade to Black Rate", g .. "Fade to Black~Rate", rx + 190, y + 80, 90, 22, { Style = "Text" })
  y = math.max(leftBottom, top + 160)

  -- Downstream keyers act on the program output: on the first M/E page
  if me == 1 and topo.DSKs > 0 then
    y = Section("Downstream Keys", M, y, contentW)
    local gw = 380
    for n = 1, topo.DSKs do
      local col, row = (n - 1) % 2, (n - 1) // 2
      local x, ry = M + col * gw, y + row * 38
      local d, dg = "DSK " .. n .. " ", "DSK " .. n .. "~"
      Label("DSK " .. n, x, ry + 7, 44, 18, { style = "Bold" })
      Button(d .. "Tie", dg .. "Tie", "TIE", x + 48, ry, 56, 30, C.Amber, { FontSize = 10 })
      Button(d .. "On Air", dg .. "On Air", "ON AIR", x + 108, ry, 64, 30, C.TallyRed, { FontSize = 10 })
      Button(d .. "Auto", dg .. "Auto", "AUTO", x + 176, ry, 56, 30, C.TallyRed, { FontSize = 10 })
      Place(d .. "In Transition", dg .. "In Transition", x + 238, ry + 8, 14, 14, { Color = C.Amber })
      Label("Rate", x + 256, ry + 7, 36, 18, { align = "Right", size = 10, color = C.Mid })
      Place(d .. "Rate", dg .. "Rate", x + 296, ry + 4, 60, 22, { Style = "Text" })
    end
    y = y + math.ceil(topo.DSKs / 2) * 38
  end
  H = y + M

elseif CurrentPage == "Keyers" then
  W = 760
  local cw = W - 2 * M
  local function Header(cols)
    for _, c in ipairs(cols) do Label(c[1], c[2], y, c[3], 16, { size = 10, color = C.Mid }) end
    y = y + 18
  end
  for me = 1, (topo.USKs > 0 and topo.MEs or 0) do
    local p, g = "ME" .. me .. " ", "M/E " .. me .. "~"
    y = Section((topo.MEs > 1 and ("M/E " .. me .. " ") or "") .. "Upstream Keys", M, y, cw)
    Header({ { "Type", M + 70, 80 }, { "Fill source", M + 170, 200 }, { "Key source", M + 390, 200 } })
    for k = 1, topo.USKs do
      local q = p .. "Key " .. k .. " "
      Label("Key " .. k, M, y + 2, 60, 18, { style = "Bold" })
      Place(q .. "Type", g .. "Keyers~Key " .. k .. " Type", M + 70, y, 90, 22, { Style = "ComboBox" })
      Place(q .. "Fill", g .. "Keyers~Key " .. k .. " Fill", M + 170, y, 200, 22, { Style = "ComboBox" })
      Place(q .. "Key", g .. "Keyers~Key " .. k .. " Key", M + 390, y, 200, 22, { Style = "ComboBox" })
      y = y + 28
    end
    y = y + 6
  end
  if topo.DSKs > 0 then
    y = Section("Downstream Keys", M, y, cw)
    Header({ { "Fill source", M + 170, 200 }, { "Key source", M + 390, 200 } })
    for n = 1, topo.DSKs do
      local d, dg = "DSK " .. n .. " ", "DSK " .. n .. "~"
      Label("DSK " .. n, M, y + 2, 60, 18, { style = "Bold" })
      Place(d .. "Fill", dg .. "Fill", M + 170, y, 200, 22, { Style = "ComboBox" })
      Place(d .. "Key", dg .. "Key", M + 390, y, 200, 22, { Style = "ComboBox" })
      y = y + 28
    end
    Label("On Air, Tie, Auto and Rate of the downstream keys are on page M/E 1.", M, y + 2, cw, 16,
      { size = 10, color = C.Mid })
    y = y + 22
  end
  H = y + M

elseif auxFirst then
  local auxMode = AtemTopology.AuxMode(props, topo)
  local widest = 0
  for aux = auxFirst, auxLast do
    widest = math.max(widest, GridWidth(#AtemTopology.AuxButtonSources(topo, aux, auxMode)))
  end
  local contentW = math.max(widest, 760)
  W = M * 2 + contentW
  for aux = auxFirst, auxLast do
    local ids = AtemTopology.AuxButtonSources(topo, aux, auxMode)
    y = Section("Aux " .. aux, M, y, contentW)
    Label("Source", M + contentW - 330, y - 28, 120, 20, { align = "Right", color = C.Mid })
    Place("Aux " .. aux, "Aux " .. aux .. "~Source", M + contentW - 200, y - 28, 200, 20, { Style = "ComboBox" })
    if #ids == 0 then
      y = y + NoButtons("Aux Buttons", M, y, contentW)
    else
      y = y + SourceGrid(ids, M, y, C.Amber,
        function(id) return "Aux " .. aux .. " " .. AtemTopology.SourceKey(id) end,
        function(id) return "Aux " .. aux .. "~" .. AtemTopology.SourceKey(id) end)
      y = y + NameGrid("aux" .. aux, ids, M, y) + 6
    end
  end
  H = y + M

elseif CurrentPage == "Audio" then
  local audio = AtemTopology.AudioInputs(topo, props)
  local SW, PER_ROW = 70, 12
  local strips = #audio + 1   -- + master
  local cols = math.min(PER_ROW, strips)
  local contentW = math.max(cols * (SW + GAP) - GAP, 760)
  W = M * 2 + contentW
  y = Section("Audio Mixer (" .. topo.Audio .. ")", M, y, contentW)
  local STRIP_H = 18 + 4 + 2 * 30 + 4 + 170 + 10
  local function Strip(i, title, p, g, master, hasAfv)
    local col, row = (i - 1) % PER_ROW, (i - 1) // PER_ROW
    local x, sy = M + col * (SW + GAP), y + row * STRIP_H
    if master then
      Label(title, x, sy, SW, 18, { style = "Bold", align = "Center" })
      Button("Audio Master AFV", "Audio~Master~AFV", "AFV", x + 5, sy + 22, SW - 10, 26, C.Amber,
        { FontSize = 10 })
    else
      Place(p .. "Name", g .. "Name", x, sy, SW, 18,
        { Style = "Text", Color = C.Porcelain, StrokeWidth = 0, FontSize = 10, TextColor = C.Onyx, HTextAlign = "Center" })
      Button(p .. "On", g .. "On", "ON", x + 5, sy + 22, SW - 10, 26, C.TallyRed, { FontSize = 10 })
      if hasAfv then
        Button(p .. "AFV", g .. "AFV", "AFV", x + 5, sy + 52, SW - 10, 26, C.Amber, { FontSize = 10 })
      end
    end
    Place(p .. "Level", g .. "Level", x + (SW - 40) // 2, sy + 86, 40, 170, { Style = "Fader", Color = C.Atlantic })
  end
  for i, id in ipairs(audio) do
    local key = AtemTopology.AudioKey(id)
    Strip(i, key, "Audio " .. key .. " ", "Audio~" .. key .. "~", false, AtemTopology.AudioHasAFV(id))
  end
  Strip(strips, "MASTER", "Audio Master ", "Audio~Master~", true)
  y = y + math.ceil(strips / PER_ROW) * STRIP_H
  H = y + M

elseif CurrentPage == "Stream & Record" then
  W = 760
  local cw = W - 2 * M
  local function Row(label, name, pretty, w)
    Label(label, M + 140, y + 1, 110, 20, { align = "Right", color = C.Mid })
    Place(name, pretty, M + 256, y, w, 22, FLAT)
    y = y + 28
  end
  if topo.Streaming then
    y = Section("Streaming", M, y, cw)
    Button("Stream", "Streaming~Stream", "STREAM", M, y, 120, 56, C.TallyRed, { FontSize = 13 })
    Row("Status", "Stream Status", "Streaming~Status", 300)
    Row("Duration", "Stream Duration", "Streaming~Duration", 120)
    y = y + 10
  end
  if topo.Recording then
    y = Section("Recording", M, y, cw)
    Button("Record", "Recording~Record", "RECORD", M, y, 120, 56, C.TallyRed, { FontSize = 13 })
    Row("Status", "Record Status", "Recording~Status", 300)
    Row("Duration", "Record Duration", "Recording~Duration", 120)
    Row("Time remaining", "Record Time Remaining", "Recording~Time Remaining", 120)
    if topo.RecordISO then
      Button("Record ISO", "Recording~Record ISO", "ISO", M, y, 120, 30, C.Amber, { FontSize = 11 })
      Label("Record all inputs (ISO)", M + 130, y + 6, 300, 18, { color = C.Mid })
      y = y + 36
    end
  end
  Label("Stream key, server and recording disk are set up in ATEM Software Control.", M, y + 4, cw, 16,
    { size = 10, color = C.Mid })
  H = y + 28 + M

elseif CurrentPage == "Media" then
  local stills = AtemTopology.StillButtons(topo, props)
  local cols = math.min(10, math.max(1, stills))
  local contentW = math.max(cols * (BW + GAP) - GAP, 760)
  W = M * 2 + contentW
  -- buttons with the names (from the switcher) directly under each row
  local function ButtonRows(count, x, ry, name, pretty, legend, nameCtl)
    local rows = math.ceil(count / cols)
    for i = 1, count do
      local col, row = (i - 1) % cols, (i - 1) // cols
      local bx, by = x + col * (BW + GAP), ry + row * (BH + NAME_H + 6)
      Button(name(i), pretty(i), legend(i), bx, by, BW, BH, C.Amber)
      if nameCtl then
        Place(nameCtl(i), "Media Pool~" .. nameCtl(i), bx, by + BH + 1, BW, NAME_H,
          { Style = "Text", Color = C.Porcelain, StrokeWidth = 0, FontSize = 9, TextColor = C.Mid, HTextAlign = "Center" })
      end
    end
    return rows * (BH + NAME_H + 6)
  end
  for mp = 1, topo.MediaPlayers do
    local p, g = "MP" .. mp .. " ", "Media Player " .. mp .. "~"
    y = Section("Media Player " .. mp, M, y, contentW)
    Label("Source", M + contentW - 330, y - 28, 120, 20, { align = "Right", color = C.Mid })
    Place(p .. "Source", g .. "Source", M + contentW - 200, y - 28, 200, 20, { Style = "ComboBox" })
    if stills > 0 then
      y = y + ButtonRows(stills, M, y,
        function(i) return p .. "Still " .. i end, function(i) return g .. "Still " .. i end,
        function(i) return tostring(i) end,
        mp == 1 and function(i) return "Still " .. i .. " Name" end or nil) + 2
    end
    if topo.Clips > 0 then
      Label("Clips", M, y + 10, 50, 18, { color = C.Mid })
      y = y + ButtonRows(topo.Clips, M + 56, y,
        function(i) return p .. "Clip " .. i end, function(i) return g .. "Clip " .. i end,
        function(i) return "CLIP " .. i end,
        mp == 1 and function(i) return "Clip " .. i .. " Name" end or nil)
      local tx = M + 56 + topo.Clips * (BW + GAP) + 24
      local ty = y - (BH + NAME_H + 6)
      Button(p .. "Play", g .. "Play", "PLAY", tx, ty, BW, BH, C.TallyGreen, { FontSize = 10 })
      Button(p .. "Loop", g .. "Loop", "LOOP", tx + BW + GAP, ty, BW, BH, C.Amber, { FontSize = 10 })
      Button(p .. "Rewind", g .. "Rewind", "REWIND", tx + 2 * (BW + GAP), ty, BW, BH, C.Atlantic, { FontSize = 10 })
    end
    y = y + 4
  end

  y = Section("Color Generators", M, y, contentW)
  for n = 1, 2 do
    local p, g = "Color " .. n .. " ", "Color " .. n .. "~"
    Label("Color " .. n, M, y + 2, 70, 18, { style = "Bold" })
    local x = M + 80
    for _, part in ipairs({ "Hue", "Saturation", "Luma" }) do
      Label(part, x, y + 2, 70, 18, { align = "Right", size = 10, color = C.Mid })
      Place(p .. part, g .. part, x + 76, y, 120, 22, { Style = "Fader", Color = C.Atlantic })
      x = x + 210
    end
    y = y + 30
  end
  H = y + M

elseif CurrentPage == "Macros" then
  local macros = AtemTopology.MacroButtons(topo, props)
  local MW, cols = 72, 10
  local contentW = math.max(cols * (MW + GAP) - GAP, 760)
  W = M * 2 + contentW
  y = Section("Macros", M, y, contentW)
  Label("Macro", M, y + 3, 50, 18, { color = C.Mid })
  Place("Macro", "Macros~Macro", M + 54, y, 220, 22, { Style = "ComboBox" })
  Button("Macro Run", "Macros~Run", "RUN", M + 284, y - 4, 64, 30, C.TallyGreen, { FontSize = 10 })
  Button("Macro Stop", "Macros~Stop", "STOP", M + 352, y - 4, 64, 30, C.TallyRed, { FontSize = 10 })
  Button("Macro Loop", "Macros~Loop", "LOOP", M + 420, y - 4, 64, 30, C.Amber, { FontSize = 10 })
  y = y + 34
  Label("Running", M, y + 1, 50, 16, { size = 10, color = C.Mid })
  Place("Macro Running", "Macros~Running", M + 54, y + 2, 14, 14, { Color = C.TallyGreen })
  Place("Macro Running Name", "Macros~Running Name", M + 76, y, 300, 18, FLAT)
  y = y + 28
  for i = 1, macros do
    local col, row = (i - 1) % cols, (i - 1) // cols
    local bx, by = M + col * (MW + GAP), y + row * (BH + NAME_H + 6)
    Button("Macro " .. i, "Macros~Macro " .. i, tostring(i), bx, by, MW, BH, C.TallyGreen)
    Place("Macro " .. i .. " Name", "Macros~Macro " .. i .. " Name", bx, by + BH + 1, MW, NAME_H,
      { Style = "Text", Color = C.Porcelain, StrokeWidth = 0, FontSize = 9, TextColor = C.Mid, HTextAlign = "Center" })
  end
  y = y + math.ceil(macros / cols) * (BH + NAME_H + 6)
  H = y + M

elseif ssIndex then
  local ss = ssIndex
  local ids = AtemTopology.BoxButtonSources(topo, mode)
  local contentW = math.max(GridWidth(#ids), 760)
  W = M * 2 + contentW
  for box = 1, AtemTopology.BOXES do
    local p, g = "SS" .. ss .. " Box " .. box .. " ", "Box " .. box .. "~"
    y = Section("Box " .. box, M, y, contentW)
    Button(p .. "Enable", g .. "Enable", "ENABLE", M + contentW - 420, y - 30, 80, 24, C.Amber, { FontSize = 10 })
    Label("Source", M + contentW - 330, y - 28, 120, 20, { align = "Right", color = C.Mid })
    Place(p .. "Source", g .. "Source", M + contentW - 200, y - 28, 200, 20, { Style = "ComboBox" })
    if #ids == 0 then
      y = y + NoButtons("Source Buttons", M, y, contentW)
    else
      y = y + SourceGrid(ids, M, y, C.Amber,
        function(id) return p .. AtemTopology.SourceKey(id) end,
        function(id) return g .. AtemTopology.SourceKey(id) end)
      y = y + NameGrid("ss" .. ss .. "." .. box, ids, M, y) + 6
    end
  end
  H = y + M

elseif CurrentPage == "Setup" then
  local lw, fx = 120, M + 128
  W = 760
  y = Section("Connection", M, y, W - 2 * M)
  local function Row(label, name, pretty, w, extra)
    Label(label, M, y + 1, lw, 20, { align = "Right" })
    Place(name, pretty, fx, y, w, 22, extra)
    y = y + 28
  end
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
