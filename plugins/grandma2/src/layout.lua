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
local y = LevoBrand.HeaderHeight + 3 + 12
if CurrentPage == "Faders" or CurrentPage == "Buttons" then
  Label("Executor per slot: enter page.exec as in MA (e.g. 1.5 or 1.101) in the field top right.",
    M, y - 4, 600, 16, { size = 10, color = C.Mid })
  y = y + 16
end

if CurrentPage == "Faders" then
  local cols, cw, gap = 8, 96, 8
  local cellH = 24 + 18 + 16 + 18 + 16 + 3 * 26 + 8 + 150 + 24
  for i = 1, counts.Faders do
    local col, row = (i - 1) % cols, (i - 1) // cols
    local x, cy = M + col * (cw + gap), y + row * (cellH + gap)
    local p, g = "Fader " .. i .. " ", "Faders~Fader " .. i .. "~"
    table.insert(graphics, {
      Type = "GroupBox", Fill = { 255, 255, 255 }, StrokeColor = { 210, 210, 206 }, StrokeWidth = 1,
      CornerRadius = 6, Position = { x, cy }, Size = { cw, cellH },
    })
    Label("Fader " .. i, x + 4, cy + 4, 40, 18, { size = 9, color = C.Mid })
    Place(p .. "Exec", g .. "Exec", x + cw - 52, cy + 3, 48, 18, { Style = "Text", FontSize = 10 })
    local yy = cy + 24
    Place(p .. "Name", g .. "Name", x + 4, yy, cw - 8, 18, { Style = "Text", FontSize = 11, FontStyle = "Bold" }); yy = yy + 18
    Place(p .. "Cue", g .. "Cue", x + 4, yy, cw - 8, 16, { Style = "Text", FontSize = 9 }); yy = yy + 18
    Place(p .. "Active", g .. "Active", x + 4, yy, 16, 16, { Color = C.Amber })
    Place(p .. "Fading", g .. "Fading", x + 22, yy, 16, 16, { Color = C.Atlantic })
    Place(p .. "State", g .. "State", x + 40, yy, cw - 44, 16, { Style = "Text", FontSize = 9 }); yy = yy + 18
    Place(p .. "Progress", g .. "Progress", x + 4, yy, cw - 8, 8, { Style = "Fader", IsReadOnly = true, Color = C.Atlantic }); yy = yy + 12
    for b = 1, 3 do
      Place(p .. "Button " .. b, g .. "Button " .. b, x + 4, yy, cw - 8, 22,
        { Style = "Button", Legend = "", FontSize = 10, Color = C.Amber }); yy = yy + 26
    end
    Place(p .. "Level", g .. "Level", x + (cw - 40) // 2, yy + 4, 40, 150, { Style = "Fader", Color = C.Atlantic }); yy = yy + 158
    Place(p .. "Function", g .. "Function", x + 4, yy, cw - 8, 16, { Style = "Text", FontSize = 9 })
  end
  local rows = math.max(1, math.ceil(counts.Faders / cols))
  W = math.max(W, M * 2 + math.min(counts.Faders, cols) * (cw + gap) - gap)
  H = y + rows * (cellH + gap) + M

elseif CurrentPage == "Buttons" then
  local cols, cw, gap = 6, 124, 8
  local cellH = 24 + 44 + 18 + 18 + 18 + 12 + 18 + 6
  for i = 1, counts.Buttons do
    local col, row = (i - 1) % cols, (i - 1) // cols
    local x, cy = M + col * (cw + gap), y + row * (cellH + gap)
    local p, g = "Button " .. i .. " ", "Buttons~Button " .. i .. "~"
    table.insert(graphics, {
      Type = "GroupBox", Fill = { 255, 255, 255 }, StrokeColor = { 210, 210, 206 }, StrokeWidth = 1,
      CornerRadius = 6, Position = { x, cy }, Size = { cw, cellH },
    })
    Label("Button " .. i, x + 4, cy + 4, 60, 18, { size = 9, color = C.Mid })
    Place(p .. "Exec", g .. "Exec", x + cw - 56, cy + 3, 52, 18, { Style = "Text", FontSize = 10 })
    local yy = cy + 24
    Place(p .. "Press", g .. "Press", x + 4, yy, cw - 8, 40, { Style = "Button", Legend = "", FontSize = 11, Color = C.Amber }); yy = yy + 44
    Place(p .. "Name", g .. "Name", x + 4, yy, cw - 8, 16, { Style = "Text", FontSize = 10, FontStyle = "Bold" }); yy = yy + 18
    Place(p .. "Cue", g .. "Cue", x + 4, yy, cw - 8, 16, { Style = "Text", FontSize = 9 }); yy = yy + 18
    Place(p .. "Active", g .. "Active", x + 4, yy, 16, 16, { Color = C.Amber })
    Place(p .. "Fading", g .. "Fading", x + 22, yy, 16, 16, { Color = C.Atlantic })
    Place(p .. "State", g .. "State", x + 40, yy, cw - 44, 16, { Style = "Text", FontSize = 9 }); yy = yy + 18
    Place(p .. "Progress", g .. "Progress", x + 4, yy, cw - 8, 8, { Style = "Fader", IsReadOnly = true, Color = C.Atlantic }); yy = yy + 12
    Place(p .. "Function", g .. "Function", x + 4, yy, cw - 8, 16, { Style = "Text", FontSize = 9 })
  end
  local rows = math.max(1, math.ceil(counts.Buttons / cols))
  W = math.max(W, M * 2 + math.min(counts.Buttons, cols) * (cw + gap) - gap)
  H = y + rows * (cellH + gap) + M

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
LevoBrand.Header(front, W, CurrentPage)
for i = #front, 1, -1 do table.insert(graphics, 1, front[i]) end
