-- (c) levo AVL | Elias Jenny - MIT License
local C = LevoBrand.Colors
local counts = SlotCounts(props)
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

-- Page size depends on the slot counts; background and header are added at the
-- end (prepended to `graphics`) once W and H are known.
local W, H = 640, 400
local y = LevoBrand.HeaderHeight + 2 + 10

-- Executor strips: columns separated by hairlines, like the executor bar in MA.
-- The state lives in one place only - the colour of the main button.
local function Hairline(x, y1, w, h)
  table.insert(graphics, {
    Type = "GroupBox", Fill = C.Line, StrokeWidth = 0, CornerRadius = 0,
    Position = { x, y1 }, Size = { w, h },
  })
end

local function SlotHead(p, g, i, x, cy, cw)
  Label(tostring(i), x + 6, cy + 6, 24, 18, { size = 10, color = C.Mid })
  Place(p .. "Exec", g .. "Exec", x + cw - 54, cy + 6, 48, 18, { Style = "Text", FontSize = 10 })
end

-- read-only text that should look like a label, not like a field
local FLAT = { Style = "Text", Color = C.Porcelain, StrokeWidth = 0, CornerRadius = 0 }
local function Flat(extra)
  local t = {}
  for k, v in pairs(FLAT) do t[k] = v end
  for k, v in pairs(extra) do t[k] = v end
  return t
end

local function NameCue(p, g, x, yy, cw)
  Place(p .. "Name", g .. "Name", x + 4, yy, cw - 8, 18, Flat({ FontSize = 12, FontStyle = "Bold", TextColor = C.Onyx }))
  Place(p .. "Cue", g .. "Cue", x + 4, yy + 18, cw - 8, 15, Flat({ FontSize = 10, TextColor = C.Mid }))
  -- fade progress sits directly under the cue, as in MA
  Place(p .. "Progress", g .. "Progress", x + 6, yy + 34, cw - 12, 6, { Style = "Fader", IsReadOnly = true, Color = C.Amber })
  return yy + 46
end

if CurrentPage == "Faders" then
  local cols, cw = 8, 92
  local cellH = 344
  for i = 1, counts.Faders do
    local col, row = (i - 1) % cols, (i - 1) // cols
    local x, cy = M + col * cw, y + row * (cellH + 12)
    local p, g = "Fader " .. i .. " ", "Faders~Fader " .. i .. "~"
    if col > 0 then Hairline(x, cy + 4, 1, cellH - 8) end
    SlotHead(p, g, i, x, cy, cw)
    local yy = NameCue(p, g, x, cy + 30, cw)
    for _, b in ipairs({ 3, 2 }) do
      Place(p .. "Button " .. b, g .. "Button " .. b, x + 6, yy, cw - 12, 24,
        { Style = "Button", Legend = "", FontSize = 10, Color = C.Line }); yy = yy + 28
    end
    Place(p .. "Level", g .. "Level", x + (cw - 32) // 2, yy + 2, 32, 150, { Style = "Fader", Color = C.Atlantic }); yy = yy + 158
    -- main button below the fader, coloured by the executor state at runtime
    Place(p .. "Button 1", g .. "Button 1", x + 6, yy, cw - 12, 34,
      { Style = "Button", Legend = "", FontSize = 11, FontStyle = "Bold", Color = C.Amber }); yy = yy + 38
    Place(p .. "Function", g .. "Function", x + 4, yy, cw - 8, 14, Flat({ FontSize = 9, TextColor = C.Mid }))
  end
  local rows = math.max(1, math.ceil(counts.Faders / cols))
  W = math.max(W, M * 2 + math.min(counts.Faders, cols) * cw)
  H = y + rows * (cellH + 12) + M

elseif CurrentPage == "Buttons" then
  local cols, cw = 6, 112
  local cellH = 136
  for i = 1, counts.Buttons do
    local col, row = (i - 1) % cols, (i - 1) // cols
    local x, cy = M + col * cw, y + row * cellH
    local p, g = "Button " .. i .. " ", "Buttons~Button " .. i .. "~"
    if col > 0 then Hairline(x, cy + 4, 1, cellH - 8) end
    if row > 0 then Hairline(x + 4, cy, cw - 8, 1) end
    SlotHead(p, g, i, x, cy, cw)
    Place(p .. "Press", g .. "Press", x + 6, cy + 30, cw - 12, 48,
      { Style = "Button", Legend = "", FontSize = 11, Color = C.Amber })
    NameCue(p, g, x, cy + 82, cw)
  end
  local rows = math.max(1, math.ceil(counts.Buttons / cols))
  W = math.max(W, M * 2 + math.min(counts.Buttons, cols) * cw)
  H = y + rows * cellH + M

elseif CurrentPage == "Macros" then
  local cols, cw, gap = 4, 150, 12
  for i = 1, counts.Macros do
    local col, row = (i - 1) % cols, (i - 1) // cols
    local x, ry = M + col * (cw + gap), y + row * 28
    Label("Macro " .. i, x, ry + 2, 50, 18)
    Place("Macro " .. i .. " Trigger", "Macros~Macro " .. i .. "~Trigger", x + 50, ry, 50, 22, { Style = "Button", Legend = "Go", Color = C.Amber })
    Place("Macro " .. i .. " Number", "Macros~Macro " .. i .. "~Number", x + 104, ry + 1, 44, 20, { Style = "Text" })
  end
  Label("Number = MA macro pool number. Sends \"Go Macro <n>\" - no running feedback from the console.",
    M, y + math.ceil(counts.Macros / cols) * 28 + 4, 600, 18, { size = 10, color = C.Mid })
  H = y + math.ceil(counts.Macros / cols) * 28 + 40

elseif CurrentPage == "Commands" then
  for i = 1, counts.Commands do
    local ry = y + (i - 1) * 28
    Label(tostring(i), M, ry + 2, 24, 18, { align = "Right" })
    Place("Command " .. i .. " Text", "Commands~Command " .. i .. "~Text", M + 32, ry, 480, 22, { Style = "Text" })
    Place("Command " .. i .. " Send", "Commands~Command " .. i .. "~Send", M + 520, ry, 70, 22, { Style = "Button", Legend = "Send", Color = C.Amber })
  end
  H = y + counts.Commands * 28 + M

elseif CurrentPage == "Setup" then
  local lw, fx = 110, M + 118
  y = Section("Connection", M, y, 608)
  local function Row(label, name, pretty, w, extra)
    Label(label, M, y + 1, lw, 20, { align = "Right" })
    Place(name, pretty, fx, y, w, 22, extra)
    y = y + 28
  end
  Row("IP Address", "IP Address", "Setup~IP Address", 160, { Style = "Text" })
  Row("Port", "Port", "Setup~Port", 70, { Style = "Text" })
  Row("Username", "Username", "Setup~Username", 160, { Style = "Text" })
  Row("Password", "Password", "Setup~Password", 160, { Style = "Text" })
  Label("Status", M, y + 1, lw, 20, { align = "Right" })
  Place("Status", "Status", fx, y, 300, 22)
  Place("Reconnect", "Setup~Reconnect", fx + 310, y, 90, 22, { Style = "Button", Legend = "Reconnect", Color = C.Amber })
  y = y + 28
  Label("Connected", M, y, lw, 18, { align = "Right" })
  Place("Connected", "Connected", fx, y + 1, 16, 16, { Color = C.Amber })
  Label("Logged In", fx + 30, y, 70, 18, { align = "Right" })
  Place("Logged In", "Logged In", fx + 106, y + 1, 16, 16, { Color = C.Amber })
  y = y + 26
  Row("Command TX", "Command TX", "Setup~Command TX", 300, { Style = "Text" })
  Label("Executors are assigned in each slot (field top right): page.exec as in MA, e.g. 1.101.",
    M, y, 608, 18, { size = 10, color = C.Mid })
  y = y + 18
  Label("Web remote must be enabled: Setup > Console > Global Settings > Remotes = Login Enabled.",
    M, y, 608, 18, { size = 10, color = C.Mid })
  y = y + 26

  y = Section("Debug", M, y, 608)
  Row("Session", "Session", "Debug~Session", 120, { Style = "Text" })
  Row("Reconnects", "Reconnects", "Debug~Reconnects", 120, { Style = "Text" })
  Row("Last Error", "Last Error", "Debug~Last Error", 480, { Style = "Text" })
  y = y + 6

  H = y + M

elseif CurrentPage == "About" then
  y = y + 4
  local endY = LevoBrand.About(graphics, M, y, W - 2 * M, PluginInfo)
  Label("WebSocket / web remote handling based on \"MA2 Remote\" by Locimation Pty Ltd (MIT License).",
    M, endY + 8, W - 2 * M, 18, { size = 10, color = C.Mid })
  H = endY + 40
end

-- Background and header go below everything else: prepend them.
local front = {}
LevoBrand.Background(front, W, H)
LevoBrand.Header(front, W, LevoBrand.PluginName(PluginInfo), CurrentPage)
for i = #front, 1, -1 do table.insert(graphics, 1, front[i]) end
