-- (c) levo AVL | Elias Jenny - MIT License
-- Switcher topology: what the selected model (or the "Custom" settings) offers.
-- Used at design time (controls, pins, layout) and at runtime.

AtemTopology = {}

local T = AtemTopology

T.CUSTOM = "Custom"
T.DEFAULT_MODEL = "ATEM Mini Extreme"

-- ATEM internal port types (InPr)
T.Port = {
  External = 0, Black = 1, ColorBars = 2, ColorGenerator = 3, MediaPlayerFill = 4,
  MediaPlayerKey = 5, SuperSource = 6, ExternalDirect = 7,
  MEOutput = 128, Auxiliary = 129, Mask = 130, MultiViewer = 131, AudioMonitor = 132,
}

-- Source availability bits (InPr)
T.Avail = { Auxiliary = 1, Multiviewer = 2, SuperSourceArt = 4, SuperSourceBox = 8, KeySource = 16 }

T.TransitionStyles = { "Mix", "Dip", "Wipe", "DVE", "Stinger" }

-- Frames per second per ATEM video mode (VidM), as used for rates ("s:ff").
-- Interlaced modes count frames, 23.98/29.97/59.94 count like 24/30/60.
T.ModeFps = {
  [0] = 30, 25, 30, 25, 50, 60, 25, 30, 24, 24, 25, 30, 50, 60,
  24, 24, 25, 30, 50, 60, 24, 24, 25, 30, 50, 60, 30, 60,
}

-- 25 frames at 25 fps -> "1:00"
function T.FormatRate(frames, fps)
  fps = fps or 25
  return ("%d:%02d"):format(frames // fps, frames % fps)
end

-- "1:00" -> 25 (at 25 fps); a plain number is taken as frames. nil if invalid.
function T.ParseRate(text, fps)
  fps = fps or 25
  text = tostring(text or ""):gsub("%s", "")
  local s, f = text:match("^(%d+)[:%.,](%d+)$")
  local frames
  if s then
    frames = tonumber(s) * fps + tonumber(f)
  else
    frames = tonumber(text:match("^(%d+)$") or "")
  end
  if not frames or frames < 1 or frames > 250 then return nil end
  return math.floor(frames)
end

function T.ModelNames()
  local names = {}
  for _, m in ipairs(AtemModels) do names[#names + 1] = m.Name end
  table.sort(names)
  names[#names + 1] = T.CUSTOM
  return names
end

local function FindModel(name)
  for _, m in ipairs(AtemModels) do
    if m.Name == name then return m end
  end
end

function T.ModelById(id)
  for _, m in ipairs(AtemModels) do
    if m.Id == id then return m end
  end
end

local function Unpack(flat, width)
  local rows = {}
  for i = 1, #flat, width do
    local row = {}
    for k = 0, width - 1 do row[k + 1] = flat[i + k] end
    rows[#rows + 1] = row
  end
  return rows
end

-- Generic source list for the "Custom" model, modelled on the real switchers
local function CustomSources(c)
  local P, A = T.Port, T.Avail
  local allMe = (1 << c.MEs) - 1
  local base = A.Auxiliary | A.Multiviewer | A.KeySource
  if c.SuperSources > 0 then base = base | A.SuperSourceArt | A.SuperSourceBox end
  local list = {}
  local function add(id, port, sa, me) list[#list + 1] = { id, port, sa, me } end
  add(0, P.Black, base, allMe)
  for i = 1, c.Inputs do add(i, P.External, base, allMe) end
  add(1000, P.ColorBars, base, allMe)
  add(2001, P.ColorGenerator, base & ~A.KeySource, allMe)
  add(2002, P.ColorGenerator, base & ~A.KeySource, allMe)
  for i = 1, c.MediaPlayers do
    add(3000 + i * 10, P.MediaPlayerFill, base, allMe)
    add(3001 + i * 10, P.MediaPlayerKey, base, allMe)
  end
  for i = 1, c.SuperSources do
    add(5999 + i, P.SuperSource, base & ~A.SuperSourceArt & ~A.SuperSourceBox, allMe)
  end
  for i = 1, c.MEs do add(7000 + i, P.MEOutput, A.Auxiliary | A.Multiviewer, 0) end
  for i = 1, c.Aux do add(8000 + i, P.Auxiliary, A.Multiviewer, 0) end
  for n = 1, c.MEs do
    -- the output of M/E n can be used on the M/Es before it (re-entry)
    local me = (1 << (n - 1)) - 1
    add(10000 + n * 10, P.MEOutput, A.Auxiliary | A.Multiviewer | (n > 1 and A.SuperSourceBox or 0), me)
    add(10001 + n * 10, P.MEOutput, A.Auxiliary | A.Multiviewer | (n > 1 and A.SuperSourceBox or 0), me)
  end
  return list
end

local function PropValue(props, name, default)
  local p = props[name]
  if p == nil or p.Value == nil then return default end
  return p.Value
end

local function PropInt(props, name, default, min, max)
  local v = math.floor(tonumber(PropValue(props, name, default)) or default)
  return math.max(min, math.min(max, v))
end

-- Resolve the topology from the plugin properties.
function T.Resolve(props)
  local name = PropValue(props, "Model", T.DEFAULT_MODEL)
  local m = FindModel(name)
  local topo
  if m then
    topo = {
      Name = m.Name, Id = m.Id, MEs = m.MEs, USKs = m.USKs, DSKs = m.DSKs,
      SuperSources = m.SuperSources, Aux = m.Aux, MediaPlayers = m.MediaPlayers,
      Stills = m.Stills, Clips = m.Clips, Macros = m.Macros,
      Streaming = m.Streaming, Recording = m.Recording, RecordISO = m.RecordISO,
      Audio = m.Audio, AudioInputs = Unpack(m.AudioInputs, 2), Sources = Unpack(m.Sources, 4),
    }
  else
    local c = {
      MEs = PropInt(props, "Custom M/Es", 1, 1, 4),
      Inputs = PropInt(props, "Custom Inputs", 8, 1, 80),
      USKs = PropInt(props, "Custom Keyers per M/E", 4, 0, 4),
      DSKs = PropInt(props, "Custom Downstream Keyers", 2, 0, 4),
      Aux = PropInt(props, "Custom Aux Outputs", 2, 0, 48),
      MediaPlayers = PropInt(props, "Custom Media Players", 2, 0, 4),
      SuperSources = PropInt(props, "Custom SuperSources", 0, 0, 2),
    }
    local audio = PropValue(props, "Custom Audio", "Fairlight")
    local audioInputs = {}
    if audio ~= "None" then
      for i = 1, c.Inputs do audioInputs[#audioInputs + 1] = { i, 1 } end
    end
    topo = {
      Name = T.CUSTOM, Id = nil, MEs = c.MEs, USKs = c.USKs, DSKs = c.DSKs,
      SuperSources = c.SuperSources, Aux = c.Aux, MediaPlayers = c.MediaPlayers,
      Stills = 20, Clips = 0, Macros = 100,
      Streaming = PropValue(props, "Custom Streaming / Recording", false) == true,
      Recording = PropValue(props, "Custom Streaming / Recording", false) == true,
      RecordISO = false,
      Audio = audio, AudioInputs = audioInputs, Sources = CustomSources(c),
    }
  end
  topo.SourceById = {}
  for _, s in ipairs(topo.Sources) do topo.SourceById[s[1]] = s end
  return topo
end

---------------------------------------------------------------------------
-- Source names
---------------------------------------------------------------------------
-- Key: stable part of control names ("ME1 Program Input 3"), never changes with
-- the names set on the switcher. Short: default button legend.
function T.SourceKey(id)
  if id == 0 then return "Black", "BLK" end
  if id >= 1 and id < 1000 then return "Input " .. id, tostring(id) end
  if id == 1000 then return "Bars", "BARS" end
  if id == 2001 or id == 2002 then return "Color " .. (id - 2000), "COL" .. (id - 2000) end
  if id == 3210 then return "Thunderbolt", "TB" end
  if id == 3211 then return "Thunderbolt Key", "TBK" end
  if id > 3000 and id < 3100 then
    local n = (id - 3000) // 10
    if id % 10 == 1 then return "MP" .. n .. " Key", "MP" .. n .. "K" end
    return "MP" .. n, "MP" .. n
  end
  if id >= 4000 and id < 5000 then return "Key Mask " .. ((id - 4000) // 10), "MSK" end
  if id >= 5000 and id < 6000 then return "DSK Mask " .. ((id - 5000) // 10), "MSK" end
  if id == 6000 then return "SuperSource", "SS" end
  if id > 6000 and id < 6010 then return "SuperSource " .. (id - 5999), "SS" .. (id - 5999) end
  if id > 7000 and id < 7100 then return "Clean Feed " .. (id - 7000), "CF" .. (id - 7000) end
  if id > 8000 and id < 8100 then return "Aux " .. (id - 8000), "AUX" .. (id - 8000) end
  if id > 9000 and id < 9100 then return "Multiview " .. (id - 9000), "MV" .. (id - 9000) end
  if id >= 10010 and id < 10100 then
    local n = (id - 10000) // 10
    if id % 10 == 1 then return "ME" .. n .. " PVW", "M" .. n .. "PV" end
    return "ME" .. n .. " PGM", "M" .. n .. "PG"
  end
  if id > 11000 and id < 11100 then return "Direct " .. (id - 11000), "DIR" .. (id - 11000) end
  return "Source " .. id, tostring(id)
end

-- Order like ATEM Software Control: external inputs first, then Black, Bars,
-- colours, media players ... (stable: keeps the given order inside both groups).
-- portOf(id) returns the internal port type of a source.
function T.SortSources(ids, portOf)
  local inputs, rest = {}, {}
  for _, id in ipairs(ids) do
    if portOf(id) == T.Port.External then inputs[#inputs + 1] = id else rest[#rest + 1] = id end
  end
  for _, id in ipairs(rest) do inputs[#inputs + 1] = id end
  return inputs
end

local function TopoPort(topo)
  return function(id)
    local s = topo.SourceById[id]
    return s and s[2]
  end
end

-- Sources that get a button on the M/E buses. Mode: "All Sources" | "Inputs Only" | "None"
local ME_BUTTON_PORTS = {
  [T.Port.External] = true, [T.Port.Black] = true, [T.Port.ColorBars] = true,
  [T.Port.ColorGenerator] = true, [T.Port.MediaPlayerFill] = true,
  [T.Port.SuperSource] = true, [T.Port.MEOutput] = true,
}

function T.MEButtonSources(topo, me, mode)
  local ids = {}
  if mode == "None" then return ids end
  local bit = 1 << (me - 1)
  for _, s in ipairs(topo.Sources) do
    local id, port, _, meAvail = s[1], s[2], s[3], s[4]
    if meAvail & bit ~= 0 then
      if (mode == "Inputs Only" and port == T.Port.External) or (mode ~= "Inputs Only" and ME_BUTTON_PORTS[port]) then
        ids[#ids + 1] = id
      end
    end
  end
  return T.SortSources(ids, TopoPort(topo))
end

-- All sources that can go on an M/E bus (combo boxes)
function T.MESources(topo, me)
  local ids, bit = {}, 1 << (me - 1)
  for _, s in ipairs(topo.Sources) do
    if s[4] & bit ~= 0 then ids[#ids + 1] = s[1] end
  end
  return T.SortSources(ids, TopoPort(topo))
end

-- Source availability for aux n (the Mini Extreme has extra bits for aux 1 / 2)
function T.AuxAvailable(aux, sa)
  if sa & T.Avail.Auxiliary ~= 0 then return true end
  if aux == 1 and sa & 32 ~= 0 then return true end
  if aux == 2 and sa & 64 ~= 0 then return true end
  return false
end

-- Button sources for aux, SuperSource boxes: same ports as the M/E buttons
local function ButtonSources(topo, mode, accept)
  local ids = {}
  if mode == "None" then return ids end
  for _, s in ipairs(topo.Sources) do
    local id, port, sa = s[1], s[2], s[3]
    if accept(sa) and ((mode == "Inputs Only" and port == T.Port.External)
        or (mode ~= "Inputs Only" and ME_BUTTON_PORTS[port])) then
      ids[#ids + 1] = id
    end
  end
  return T.SortSources(ids, TopoPort(topo))
end

function T.AuxButtonSources(topo, aux, mode)
  return ButtonSources(topo, mode, function(sa) return T.AuxAvailable(aux, sa) end)
end

function T.BoxButtonSources(topo, mode)
  return ButtonSources(topo, mode, function(sa) return sa & T.Avail.SuperSourceBox ~= 0 end)
end

T.BOXES = 4   -- boxes per SuperSource
T.AUX_PER_PAGE = 8

function T.AuxMode(props)
  return PropValue(props, "Aux Buttons", "All Sources")
end

-- All button grids in page order. A source name is placed under the first grid
-- that contains the source (a control can only be placed once in the layout).
function T.Grids(topo, props)
  local mode, auxMode = T.ButtonMode(props), T.AuxMode(props)
  local grids = {}
  for me = 1, topo.MEs do
    grids[#grids + 1] = { key = "me" .. me, ids = T.MEButtonSources(topo, me, mode) }
  end
  for aux = 1, topo.Aux do
    grids[#grids + 1] = { key = "aux" .. aux, ids = T.AuxButtonSources(topo, aux, auxMode) }
  end
  local boxIds = T.BoxButtonSources(topo, mode)
  for ss = 1, topo.SuperSources do
    for box = 1, T.BOXES do
      grids[#grids + 1] = { key = "ss" .. ss .. "." .. box, ids = boxIds }
    end
  end
  return grids
end

-- { grid key -> list of source ids whose name goes under that grid }, and the
-- list of all named sources in order
function T.NamePlacement(topo, props)
  local seen, owner, all = {}, {}, {}
  for _, g in ipairs(T.Grids(topo, props)) do
    owner[g.key] = {}
    for _, id in ipairs(g.ids) do
      if not seen[id] then
        seen[id] = true
        table.insert(owner[g.key], id)
        all[#all + 1] = id
      end
    end
  end
  return owner, all
end

-- Pages of the plugin
function T.Pages(topo)
  local pages = {}
  for me = 1, topo.MEs do pages[#pages + 1] = "M/E " .. me end
  if topo.USKs > 0 or topo.DSKs > 0 then pages[#pages + 1] = "Keyers" end
  if topo.Aux > 0 then
    if topo.Aux <= T.AUX_PER_PAGE then
      pages[#pages + 1] = "Aux"
    else
      for first = 1, topo.Aux, T.AUX_PER_PAGE do
        pages[#pages + 1] = ("Aux %d-%d"):format(first, math.min(topo.Aux, first + T.AUX_PER_PAGE - 1))
      end
    end
  end
  for ss = 1, topo.SuperSources do
    pages[#pages + 1] = topo.SuperSources > 1 and ("SuperSource " .. ss) or "SuperSource"
  end
  pages[#pages + 1] = "Setup"
  pages[#pages + 1] = "About"
  return pages
end

function T.ButtonMode(props)
  return PropValue(props, "Source Buttons", "All Sources")
end
