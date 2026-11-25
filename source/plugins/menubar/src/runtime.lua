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

-- Configuration ----------------------------------------------------------------
local N          = Properties["Menu Count"].Value
local VERTICAL   = Properties["Orientation"].Value == "Vertical"
local IW         = Properties["Item Width"].Value
local IH         = Properties["Item Height"].Value
local IND_STYLE  = Properties["Indicator Style"].Value
local IND_SIZE   = Properties["Indicator Size"].Value
local FONT_SIZE  = Properties["Font Size"].Value
local ANIM_MS    = Properties["Animation Time"].Value
local NAV        = Properties["Navigation"].Value
local TRANSITION = Properties["Layer Transition"].Value
local SPAN       = VERTICAL and IH or IW          -- length of one item along the bar
local FRAME_S    = 0.03                            -- ~33 frames per second

local function Hex(rgb) return string.format("#%02X%02X%02X", rgb[1], rgb[2], rgb[3]) end
local DEFAULT_COLORS = {
  ["Background"]  = Hex(LevoBrand.Colors.Porcelain),
  ["Text"]        = Hex(LevoBrand.Colors.Onyx),
  ["Active Text"] = Hex(LevoBrand.Colors.Atlantic),
  ["Indicator"]   = Hex(LevoBrand.Colors.Amber),
}

local function Color(name)
  local s = Controls["Color " .. name].String:gsub("%s", "")
  if s:match("^#%x%x%x%x%x%x$") then return s end
  return DEFAULT_COLORS[name]
end

local function Trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

-- State --------------------------------------------------------------------------
local current = math.max(1, math.min(N, math.floor(Controls["Active Menu"].Value + 0.5)))
local pos     = (current - 1) * SPAN               -- indicator position along the bar in px
local anim    = { from = pos, to = pos, t0 = 0, dur = 0 }
local animTimer = Timer.New()
local navError = nil

-- Drawing ------------------------------------------------------------------------
local function Escape(s)
  return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"))
end

local function IndicatorSvg(offset)
  -- offset = indicator start relative to this item, in px along the bar
  local col = Color("Indicator")
  if IND_STYLE == "Block" then
    if VERTICAL then
      return string.format('<rect x="0" y="%.1f" width="%d" height="%d" fill="%s"/>', offset, IW, IH, col)
    end
    return string.format('<rect x="%.1f" y="0" width="%d" height="%d" fill="%s"/>', offset, IW, IH, col)
  elseif IND_STYLE == "Pill" then
    local pad = math.max(4, IND_SIZE)
    local w, h = IW - 2 * pad, IH - 2 * pad
    local r = math.min(w, h) // 2
    if VERTICAL then
      return string.format('<rect x="%d" y="%.1f" width="%d" height="%d" rx="%d" fill="%s"/>',
        pad, offset + pad, w, h, r, col)
    end
    return string.format('<rect x="%.1f" y="%d" width="%d" height="%d" rx="%d" fill="%s"/>',
      offset + pad, pad, w, h, r, col)
  end
  -- Line
  if VERTICAL then
    return string.format('<rect x="0" y="%.1f" width="%d" height="%d" rx="%d" fill="%s"/>',
      offset, IND_SIZE, IH, IND_SIZE // 2, col)
  end
  return string.format('<rect x="%.1f" y="%d" width="%d" height="%d" rx="%d" fill="%s"/>',
    offset, IH - IND_SIZE, IW, IND_SIZE, IND_SIZE // 2, col)
end

local function Render(i)
  local active = (i == current)
  local label = Trim(Controls.Label[i].String)
  if label == "" then label = "Menu " .. i end
  local textColor = active and Color("Active Text") or Color("Text")
  local opacity = Controls.Lock.Boolean and ' opacity="0.45"' or ""
  local svg = string.format(
    '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d">' ..
    '<rect x="0" y="0" width="%d" height="%d" fill="%s"/>' ..
    '%s' ..
    '<text x="%d" y="%d" fill="%s" font-family="Arial, Helvetica, sans-serif" font-size="%d" ' ..
    'font-weight="%s" text-anchor="middle" dominant-baseline="central"%s>%s</text>' ..
    '</svg>',
    IW, IH, IW, IH, Color("Background"),
    IndicatorSvg(pos - (i - 1) * SPAN),
    IW // 2, IH // 2, textColor, FONT_SIZE, active and "bold" or "normal", opacity, Escape(label))
  Controls.Menu[i].Style = json.encode({
    IconData = Crypto.Base64Encode(svg), DrawChrome = false, Margin = 0, Legend = "",
  })
end

local function RenderAll()
  for i = 1, N do Render(i) end
end

-- Only the items the indicator is currently over need a new frame
local function RenderRange(a, b)
  local first = math.max(1, math.floor(math.min(a, b) / SPAN) + 1)
  local last  = math.min(N, math.floor(math.max(a, b) / SPAN) + 2)
  for i = first, last do Render(i) end
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
  if ANIM_MS <= 0 or target == pos then
    local last = pos
    pos = target
    RenderRange(last, pos)
    return
  end
  anim.from, anim.to, anim.t0, anim.dur = pos, target, Timer.Now(), ANIM_MS / 1000
  animTimer:Start(FRAME_S)
end

-- Navigation ---------------------------------------------------------------------
local function SplitPanels()
  local list = {}
  for name in Controls.Panels.String:gmatch("[^,;]+") do
    name = Trim(name)
    if name ~= "" then table.insert(list, name) end
  end
  return list
end

local function Navigate(i)
  navError = nil
  if NAV == "Page" then
    local page = Trim(Controls.Page[i].String)
    if page == "" then return end
    local panels = SplitPanels()
    if #panels == 0 then navError = "No panel set" end
    for _, panel in ipairs(panels) do
      local ok, err = pcall(Uci.SetPage, panel, page)
      if ok then
        Log(2, ('SetPage "%s" -> "%s"'):format(panel, page))
      else
        navError = ('Page "%s" on "%s": %s'):format(page, panel, tostring(err))
        Log(1, navError)
      end
    end
  elseif NAV == "Layer" then
    local uci = Trim(Controls["UCI Name"].String)
    if uci == "" then navError = "No UCI name set"; return end
    -- hide the other layers first, then show the selected one
    for n = 1, N do
      local layer, page = Trim(Controls.Layer[n].String), Trim(Controls.Page[n].String)
      if n ~= i and layer ~= "" and page ~= "" then
        local ok, err = pcall(Uci.SetLayerVisibility, uci, page, layer, false, TRANSITION)
        if not ok then navError = ('Layer "%s" on "%s": %s'):format(layer, page, tostring(err)) end
      end
    end
    local layer, page = Trim(Controls.Layer[i].String), Trim(Controls.Page[i].String)
    if layer ~= "" and page ~= "" then
      local ok, err = pcall(Uci.SetLayerVisibility, uci, page, layer, true, TRANSITION)
      if ok then
        Log(2, ('Layer "%s" on "%s" shown'):format(layer, page))
      else
        navError = ('Layer "%s" on "%s": %s'):format(layer, page, tostring(err))
      end
    end
    if navError then Log(1, navError) end
  end
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
  SlideTo((i - 1) * SPAN)
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
  Controls.Label[n].EventHandler = function() Render(n) end
end

Controls["Active Menu"].EventHandler = function(ctl)
  Select(math.floor(ctl.Value + 0.5), true)
end

Controls.Lock.EventHandler = function()
  RenderAll()
  UpdateStatus()
end

for c in pairs(DEFAULT_COLORS) do
  local ctl = Controls["Color " .. c]
  if Trim(ctl.String) == "" then ctl.String = DEFAULT_COLORS[c] end
  ctl.EventHandler = RenderAll
end

-- Panel discovery (Page mode): offer touch panels / UCI viewers that have Script Access
if NAV == "Page" then
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
  Log(1, #found .. " panel(s) found: " .. table.concat(found, ", "))

  Controls["Add Panel"].EventHandler = function(ctl)
    local name = Trim(ctl.String)
    if name == "" then return end
    local list = SplitPanels()
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
Log(1, ("Menu Bar started: %d items, %s, %s navigation"):format(N, VERTICAL and "vertical" or "horizontal", NAV))
