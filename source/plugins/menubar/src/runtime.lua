-- (c) levo AVL | Elias Jenny - MIT License
-- Runtime: draws the menu items as SVG, animates the indicator and navigates the UCI.

local json = require("rapidjson")

local DebugLevel = ({ None = 0, Basic = 1, Verbose = 2 })[Properties["Debug Print"].Value] or 0
local function Log(level, msg)
  if level <= DebugLevel then print("[levo] " .. msg) end
end

local function SetStatus(value, text)
  Controls.Status.Value = value  -- 0 OK, 1 Compromised, 2 Fault, 3 Not present, 4 Missing, 5 Initializing
  Controls.Status.String = text or ""
end

-- Fixed configuration (properties) ---------------------------------------------
local P = function(name) return Properties[name].Value end
local N        = P("Menu Count")
local VERTICAL = P("Orientation") == "Vertical"
local IW, IH   = P("Item Width"), P("Item Height")

local SPAN  = VERTICAL and IH or IW   -- item length along the bar
local PITCH = SPAN                    -- items sit edge to edge on the UCI
local FRAME_S = 0.03                  -- ~33 frames per second

local function Trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
local function Hex(rgb) return string.format("#%02X%02X%02X", rgb[1], rgb[2], rgb[3]) end

-- Live configuration (Setup page) ----------------------------------------------------
local CHOICES = {
  ["Content"]          = { "Text", "Icon", "Icon + Text" },
  ["Font"]             = { "Arial", "Helvetica", "Verdana", "Tahoma", "Trebuchet MS", "Georgia" },
  ["Rounded Corners"]  = { "Bar Ends", "Each Item" },
  ["Indicator Style"]  = { "None", "Line", "Pill", "Block" },
  ["Line Position"]    = { "Bottom / Right", "Top / Left" },
  ["Layer Transition"] = { "none", "fade", "left", "right", "top", "bottom" },
}

-- Written once on the first start; afterwards the user's values are kept
local DEFAULTS = {
  ["Content"] = "Text", ["Font"] = "Arial", ["Font Size"] = 22, ["Bold Active"] = true,
  ["Icon Size"] = 36, ["Fill Active Icon"] = true,
  ["Item Gap"] = 0, ["Corner Radius"] = 0, ["Rounded Corners"] = "Bar Ends",
  ["Indicator Style"] = "Line", ["Line Position"] = "Bottom / Right",
  ["Indicator Size"] = 6, ["Indicator Margin"] = 0, ["Animation Time"] = 300,
  ["Dividers"] = false, ["Divider Length"] = 60, ["Divider Width"] = 2,
  ["Color Background"]  = Hex(LevoBrand.Colors.Porcelain),
  ["Color Text"]        = Hex(LevoBrand.Colors.Onyx),
  ["Color Active Text"] = Hex(LevoBrand.Colors.Atlantic),
  ["Color Indicator"]   = Hex(LevoBrand.Colors.Amber),
  ["Color Divider"]     = Hex(LevoBrand.Colors.Line),
  ["Layer Transition"]  = "fade",
}

for name, list in pairs(CHOICES) do
  if Controls[name] then Controls[name].Choices = list end
end

if Controls["Defaults Set"].String == "" then
  for name, v in pairs(DEFAULTS) do
    local ctl = Controls[name]
    if ctl then
      if type(v) == "boolean" then ctl.Boolean = v
      elseif type(v) == "number" then ctl.Value = v
      else ctl.String = v end
    end
  end
  for i = 1, N do Controls.Label[i].String = "Menu " .. i end
  Controls["Defaults Set"].String = "1"
end

local function S(name) return Controls[name].String end
local function V(name) return math.floor(Controls[name].Value + 0.5) end
local function B(name) return Controls[name].Boolean end

local GAP, RADIUS, EACH_ITEM, CONTENT, FONT, FONT_SIZE, BOLD, ICON_SIZE, FILL_ICON
local IND_STYLE, LINE_END, IND_SIZE, IND_MARGIN, DIVIDERS, DIV_LEN, DIV_W, ANIM_MS, TRANSITION
local COLORS, ITEMS = {}, {}

local function LoadConfig()
  GAP        = V("Item Gap") / 2       -- half the gap on each side of an item
  RADIUS     = V("Corner Radius")
  EACH_ITEM  = S("Rounded Corners") == "Each Item"
  CONTENT    = S("Content")
  FONT       = S("Font") ~= "" and S("Font") or "Arial"
  FONT_SIZE  = V("Font Size")
  BOLD       = B("Bold Active")
  ICON_SIZE  = V("Icon Size")
  FILL_ICON  = B("Fill Active Icon")
  IND_STYLE  = S("Indicator Style")
  LINE_END   = S("Line Position") ~= "Top / Left"
  IND_SIZE   = V("Indicator Size")
  IND_MARGIN = V("Indicator Margin")
  DIVIDERS   = B("Dividers")
  DIV_LEN    = V("Divider Length") / 100
  DIV_W      = V("Divider Width")
  ANIM_MS    = V("Animation Time")
  TRANSITION = Controls["Layer Transition"] and S("Layer Transition") or "fade"
  if TRANSITION == "" then TRANSITION = "fade" end

  -- colours: hex or "none"; anything else falls back to the levo colour
  for _, name in ipairs({ "Background", "Text", "Active Text", "Indicator", "Divider" }) do
    local s = S("Color " .. name):gsub("%s", "")
    if s:match("^#%x%x%x%x%x%x$") or s:match("^#%x%x%x$") or s:lower() == "none" then
      COLORS[name] = s
    else
      COLORS[name] = DEFAULTS["Color " .. name]
    end
  end

  for i = 1, N do
    local icon = Trim(Controls.Icon[i].String)
    ITEMS[i] = {
      label  = Trim(Controls.Label[i].String),
      icon   = icon ~= "" and icon ~= "(none)" and icon or nil,
      page   = Controls.Page and Trim(Controls.Page[i].String) or "",
      layers = Controls.Layers and Controls.Layers[i].String or "",
    }
  end
end
LoadConfig()

local function Color(name) return COLORS[name] end

local function Fill(color)
  return color:lower() == "none" and 'fill="none"' or ('fill="' .. color .. '"')
end

-- State --------------------------------------------------------------------------
local current = math.max(1, math.min(N, math.floor(Controls["Active Menu"].Value + 0.5)))
local pos     = (current - 1) * PITCH         -- indicator position along the bar in px
local anim    = { from = pos, to = pos, t0 = 0, dur = 0 }
local animTimer = Timer.New()
local navError = nil

-- SVG helpers ----------------------------------------------------------------------
local function Escape(s)
  return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"))
end

-- Rectangle with individual corner radii: tl, tr, br, bl
local function RoundRect(x, y, w, h, tl, tr, br, bl, attrs)
  local max = math.min(w, h) / 2
  tl, tr, br, bl = math.min(tl, max), math.min(tr, max), math.min(br, max), math.min(bl, max)
  return string.format(
    '<path d="M%.1f,%.1f H%.1f A%.1f,%.1f 0 0 1 %.1f,%.1f V%.1f A%.1f,%.1f 0 0 1 %.1f,%.1f ' ..
    'H%.1f A%.1f,%.1f 0 0 1 %.1f,%.1f V%.1f A%.1f,%.1f 0 0 1 %.1f,%.1f Z" %s/>',
    x + tl, y, x + w - tr, tr, tr, x + w, y + tr,
    y + h - br, br, br, x + w - br, y + h,
    x + bl, bl, bl, x, y + h - bl,
    y + tl, tl, tl, x + tl, y, attrs)
end

-- Corner radii of item i: rounded outer ends of the bar, or every item
local function Corners(i)
  if RADIUS == 0 then return 0, 0, 0, 0 end
  if EACH_ITEM then return RADIUS, RADIUS, RADIUS, RADIUS end
  local first, last = (i == 1), (i == N)
  if VERTICAL then
    return first and RADIUS or 0, first and RADIUS or 0, last and RADIUS or 0, last and RADIUS or 0
  end
  return first and RADIUS or 0, last and RADIUS or 0, last and RADIUS or 0, first and RADIUS or 0
end

-- Indicator shape for an item, d = indicator start relative to this item (px along the bar)
local function Indicator(i, d)
  if IND_STYLE == "None" then return "" end
  local col = Fill(Color("Indicator"))
  local m = IND_MARGIN
  -- the gap shrinks the item along the bar axis
  local gx, gy = VERTICAL and 0 or GAP, VERTICAL and GAP or 0
  local x, y = (VERTICAL and 0 or d) + gx, (VERTICAL and d or 0) + gy
  local IW, IH = IW - 2 * gx, IH - 2 * gy
  if IND_STYLE == "Line" then
    -- the margin keeps the line away from the item edges (sides and outer edge)
    local r = IND_SIZE / 2
    if VERTICAL then
      local lx = LINE_END and (IW - IND_SIZE - m) or m
      return RoundRect(lx, y + m, IND_SIZE, IH - 2 * m, r, r, r, r, col)
    end
    local ly = LINE_END and (IH - IND_SIZE - m) or m
    return RoundRect(x + m, ly, IW - 2 * m, IND_SIZE, r, r, r, r, col)
  end
  local w, h = IW - 2 * m, IH - 2 * m
  if w <= 0 or h <= 0 then return "" end
  local r
  if IND_STYLE == "Pill" then
    r = math.min(w, h) / 2
  else -- Block follows the item's corner radius
    r = math.max(0, RADIUS - m)
  end
  return RoundRect(x + m, y + m, w, h, r, r, r, r, col)
end

local function Divider(i)
  if not DIVIDERS or i == N then return "" end
  local col = Fill(Color("Divider"))
  if VERTICAL then
    local len = IW * DIV_LEN
    return string.format('<rect x="%.1f" y="%.1f" width="%.1f" height="%d" %s/>',
      (IW - len) / 2, IH - DIV_W, len, DIV_W, col)
  end
  local len = IH * DIV_LEN
  return string.format('<rect x="%.1f" y="%.1f" width="%d" height="%.1f" %s/>',
    IW - DIV_W, (IH - len) / 2, DIV_W, len, col)
end

local function IconSvg(i, cx, top, color, active)
  local icon = ITEMS[i].icon and MenuIcons[ITEMS[i].icon]
  if not icon then return "" end
  local s = ICON_SIZE / 960
  return string.format('<g transform="translate(%.1f,%.1f) scale(%.5f)"><path d="%s" %s/></g>',
    cx - ICON_SIZE / 2, top + ICON_SIZE, s, (active and FILL_ICON) and icon.f or icon.o, Fill(color))
end

local function TextSvg(text, cx, baseline, color, active)
  return string.format(
    '<text x="%.1f" y="%.1f" %s font-family="%s, Arial, sans-serif" font-size="%d" font-weight="%s" ' ..
    'text-anchor="middle">%s</text>',
    cx, baseline, Fill(color), FONT, FONT_SIZE, (active and BOLD) and "bold" or "normal", Escape(text))
end

-- Content (icon and/or text), centred in the item
local function Content(i, active)
  local color = active and Color("Active Text") or Color("Text")
  local cx, cy = IW / 2, IH / 2
  local label = CONTENT ~= "Icon" and ITEMS[i].label or ""
  -- 0.35 em below the centre puts the cap height in the middle
  if CONTENT == "Text" then
    return TextSvg(label, cx, cy + FONT_SIZE * 0.35, color, active)
  elseif CONTENT == "Icon" then
    return IconSvg(i, cx, cy - ICON_SIZE / 2, color, active)
  end
  if label == "" then return IconSvg(i, cx, cy - ICON_SIZE / 2, color, active) end
  local gap = math.floor(FONT_SIZE * 0.3)
  local top = cy - (ICON_SIZE + gap + FONT_SIZE) / 2
  return IconSvg(i, cx, top, color, active) ..
    TextSvg(label, cx, top + ICON_SIZE + gap + FONT_SIZE * 0.8, color, active)
end

-- Drawing ------------------------------------------------------------------------
local function Background(tl, tr, br, bl)
  local gx, gy = VERTICAL and 0 or GAP, VERTICAL and GAP or 0
  return RoundRect(gx, gy, IW - 2 * gx, IH - 2 * gy, tl, tr, br, bl, Fill(Color("Background")))
end

local function Render(i)
  local active = (i == current)
  local tl, tr, br, bl = Corners(i)
  local opacity = Controls.Lock.Boolean and ' opacity="0.45"' or ""
  local svg = string.format(
    '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d"><g%s>%s%s%s%s</g></svg>',
    IW, IH, opacity,
    Background(tl, tr, br, bl),
    Indicator(i, pos - (i - 1) * PITCH),
    Divider(i),
    Content(i, active))
  Controls.Menu[i].Style = json.encode({
    IconData = Crypto.Base64Encode(svg), DrawChrome = false, Margin = 0, Padding = 0, Legend = "",
  })
end

local function RenderAll()
  for i = 1, N do Render(i) end
end

-- Redraw only the items the indicator touched between a and b
local function RenderRange(a, b)
  local lo, hi = math.min(a, b), math.max(a, b) + SPAN
  for i = 1, N do
    local s = (i - 1) * PITCH
    if s < hi and s + SPAN > lo then Render(i) end
  end
end

local function Ease(t) return t < 0.5 and 2 * t * t or 1 - (-2 * t + 2) ^ 2 / 2 end

animTimer.EventHandler = function()
  local t = (Timer.Now() - anim.t0) / anim.dur
  local last = pos
  if t >= 1 then
    pos = anim.to
    animTimer:Stop()
  else
    pos = anim.from + (anim.to - anim.from) * Ease(t)
  end
  RenderRange(last, pos)
end

local function SlideTo(target)
  animTimer:Stop()
  if ANIM_MS <= 0 or IND_STYLE == "None" or target == pos then
    local last = pos
    pos = target
    RenderRange(last, pos)
    return
  end
  anim.from, anim.to, anim.t0, anim.dur = pos, target, Timer.Now(), ANIM_MS / 1000
  animTimer:Start(FRAME_S)
end

-- Navigation ---------------------------------------------------------------------
local function SplitList(s)
  local list = {}
  for item in s:gmatch("[^,;]+") do
    item = Trim(item)
    if item ~= "" then table.insert(list, item) end
  end
  return list
end

-- Uci.SetPage needs the Inventory name. A status block's code name often differs
-- (e.g. "UCI_Viewer_UCI_Viewer-1" for the Inventory name "UCI_Viewer_1"), so we try a few
-- variants once and remember the one that works.
local resolved = {}

local function Candidates(name)
  local list, seen = {}, {}
  local function add(c) if c ~= "" and not seen[c] then seen[c] = true; table.insert(list, c) end end
  local bases = { name }
  for _, prefix in ipairs({ "UCI_Viewer_", "TSC_Status_", "Touch_Screen_Status_", "TSC_" }) do
    if name:sub(1, #prefix) == prefix then table.insert(bases, name:sub(#prefix + 1)) end
  end
  for _, b in ipairs(bases) do
    add(b); add((b:gsub("%-", "_"))); add((b:gsub("_", "-")))
  end
  return list
end

local function SetPage(panel, page)
  if resolved[panel] then return pcall(Uci.SetPage, resolved[panel], page) end
  local lastErr
  for _, name in ipairs(Candidates(panel)) do
    local ok, err = pcall(Uci.SetPage, name, page)
    if ok then
      resolved[panel] = name
      if name ~= panel then Log(1, ('Panel "%s" found as "%s"'):format(panel, name)) end
      return true
    end
    lastErr = err
  end
  return false, lastErr
end

local function NavigatePage(i)
  local page = ITEMS[i].page
  if page == "" then return end
  local panels = SplitList(S("Panels"))
  if #panels == 0 then navError = "No panel set"; return end
  for _, panel in ipairs(panels) do
    local ok, err = SetPage(panel, page)
    if ok then
      Log(2, ('SetPage "%s" -> "%s"'):format(resolved[panel] or panel, page))
    else
      navError = ('Page "%s" on "%s": %s'):format(page, panel, tostring(err))
      Log(1, navError)
    end
  end
end

local function NavigateLayers(i)
  local uci = Trim(S("UCI Name"))
  if uci == "" then navError = "No UCI name set"; return end
  -- layers of the selected item stay visible even if other items list them too
  local keep = {}
  local selPage = ITEMS[i].page
  for _, layer in ipairs(SplitList(ITEMS[i].layers)) do keep[selPage .. "\0" .. layer] = true end

  local function Set(page, layer, visible)
    local ok, err = pcall(Uci.SetLayerVisibility, uci, page, layer, visible, TRANSITION)
    if not ok then
      navError = ('Layer "%s" on "%s": %s'):format(layer, page, tostring(err))
      Log(1, navError)
    else
      Log(2, ('Layer "%s" on "%s" %s'):format(layer, page, visible and "shown" or "hidden"))
    end
  end

  for n = 1, N do
    local page = ITEMS[n].page
    if n ~= i and page ~= "" then
      for _, layer in ipairs(SplitList(ITEMS[n].layers)) do
        if not keep[page .. "\0" .. layer] then Set(page, layer, false) end
      end
    end
  end
  if selPage ~= "" then
    for _, layer in ipairs(SplitList(ITEMS[i].layers)) do Set(selPage, layer, true) end
  elseif Trim(ITEMS[i].layers) ~= "" then
    navError = ("Menu %d: Layers need a Page"):format(i)
  end
end

local function Navigate(i)
  navError = nil
  -- both are optional: pages switch when Panels is set, layers when the item lists some
  if Trim(S("Panels")) ~= "" then NavigatePage(i) end
  local anyLayers = false
  for n = 1, N do if Trim(ITEMS[n].layers) ~= "" then anyLayers = true end end
  if anyLayers then NavigateLayers(i) end
end

local function UpdateStatus()
  if navError then
    SetStatus(1, navError)
  elseif Controls.Lock.Boolean then
    SetStatus(0, "Locked")
  else
    SetStatus(0, "Menu " .. current)
  end
end

local function SyncOutputs()
  for n = 1, N do
    Controls.Menu[n].Boolean = (n == current)
    Controls["Menu Active"][n].Boolean = (n == current)
  end
  Controls["Active Menu"].Value = current
end

local function Select(i, navigate)
  i = math.max(1, math.min(N, i))
  local old = current
  current = i
  SyncOutputs()
  if old ~= i then Render(old) end
  SlideTo((i - 1) * PITCH)
  Render(i)
  if navigate then Navigate(i) end
  UpdateStatus()
end

-- Event handlers -------------------------------------------------------------------
for n = 1, N do
  Controls.Menu[n].EventHandler = function()
    if Controls.Lock.Boolean then
      SyncOutputs()               -- undo the press while locked
      return
    end
    Select(n, true)
  end
end

Controls["Active Menu"].EventHandler = function(ctl)
  Select(math.floor(ctl.Value + 0.5), true)
end

Controls.Lock.EventHandler = function()
  RenderAll()
  UpdateStatus()
end

-- Every look setting is live: reload and redraw
local function Live()
  LoadConfig()
  animTimer:Stop()
  pos = (current - 1) * PITCH
  RenderAll()
end
for name in pairs(DEFAULTS) do
  if Controls[name] then Controls[name].EventHandler = Live end
end

local iconChoices = { "(none)" }
for _, name in ipairs(MenuIconNames) do table.insert(iconChoices, name) end
for n = 1, N do
  Controls.Icon[n].Choices = iconChoices
  Controls.Icon[n].EventHandler = Live
  Controls.Label[n].EventHandler = Live
  Controls.Page[n].EventHandler = LoadConfig
  Controls.Layers[n].EventHandler = LoadConfig
end

-- Panel discovery (Page mode): touch panels / UCI viewers with Script Access
do
  local found = {}
  for _, comp in ipairs(Component.GetComponents()) do
    local t = tostring(comp.Type):lower()
    Log(2, ('Component "%s" type "%s"'):format(comp.Name, comp.Type))
    if t:find("uci") or t:find("touch") or t:find("tsc") or t:find("panel") then
      table.insert(found, comp.Name)
    end
  end
  table.sort(found)
  Controls["Add Panel"].Choices = found
  if #found > 0 then
    Log(1, #found .. " panel(s) found: " .. table.concat(found, ", "))
  else
    Log(1, "No panels found. Enable Script Access on the touch panel / UCI viewer status block, or type the Inventory name into Panels.")
  end

  Controls["Add Panel"].EventHandler = function(ctl)
    local name = Trim(ctl.String)
    if name == "" then return end
    local list = SplitList(S("Panels"))
    for _, p in ipairs(list) do if p == name then ctl.String = ""; return end end
    table.insert(list, name)
    Controls.Panels.String = table.concat(list, ", ")
    ctl.String = ""
  end
end

-- Start ----------------------------------------------------------------------------
SyncOutputs()
RenderAll()
UpdateStatus()
Log(1, ("Menu Bar started: %d items, %s"):format(N, VERTICAL and "vertical" or "horizontal"))
