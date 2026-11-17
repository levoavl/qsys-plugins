-- (c) levo AVL | Elias Jenny - MIT License
--
-- ATEM command encoding and state decoding. Command layouts follow Sofie ATEM
-- Connection (MIT License, Copyright (c) 2023 Norsk rikskringkasting AS).
-- Indexes inside the protocol are 0-based; everything in this table is 1-based
-- (M/E 1 = me[1]) except source ids, which are the switcher's own numbers.

AtemState = {}
local S = AtemState
local P = AtemProtocol

function S.New()
  return {
    version = 0,          -- protocol version, e.g. 0x00020020 = 2.32
    product = "",
    modelId = nil,
    top = nil,            -- topology reported by the switcher
    keyCount = {},        -- upstream keyers per M/E
    inputs = {},          -- [source id] = { long, short, port, sa, me, default }
    inputOrder = {},
    me = {},
    dsk = {},             -- [n] = { onAir, inTransition, isAuto, tie, rate, fill, key }
    aux = {},             -- [n] = source id
    ss = {},              -- [n] = { boxes = { [b] = { enabled, source } } }
    initDone = false,
  }
end

local function ME(st, i)
  local m = st.me[i]
  if not m then
    m = {
      program = nil, preview = nil, inTransition = false, remaining = 0, handle = 0,
      style = 0, selection = 1, nextStyle = 0, nextSelection = 1, previewTransition = false,
      ftbBlack = false, ftbInTransition = false, ftbRate = 0,
      rates = {}, keyOnAir = {}, keys = {},
    }
    st.me[i] = m
  end
  return m
end
S.ME = ME

function S.VersionString(v)
  if not v or v == 0 then return "" end
  return ("%d.%d"):format(v >> 16, v & 0xFFFF)
end

-- Decoders: name -> function(st, data) returning a change key (or nil)
local D = {}

D["_ver"] = function(st, d)
  st.version = P.U32(d, 0)
  return "device"
end

D["_pin"] = function(st, d)
  st.product = P.Str(d, 0, 40)
  st.modelId = P.U8(d, 40)
  return "device"
end

D["_top"] = function(st, d)
  -- one extra byte (multiviewers) since protocol 2.30
  local o = st.version > 0x0002001d and 1 or 0
  st.top = {
    MEs = P.U8(d, 0), sources = P.U8(d, 1), DSKs = P.U8(d, 2), Aux = P.U8(d, 3),
    MediaPlayers = P.U8(d, 5), DVEs = P.U8(d, 8 + o), Stingers = P.U8(d, 9 + o),
    SuperSources = P.U8(d, 10 + o),
  }
  return "device"
end

D["_MeC"] = function(st, d)
  st.keyCount[P.U8(d, 0) + 1] = P.U8(d, 1)
  return "device"
end

D["VidM"] = function(st, d)
  st.videoMode = P.U8(d, 0)
  return "video"
end

D["InPr"] = function(st, d)
  local id = P.U16(d, 0)
  local inp = st.inputs[id]
  if not inp then
    inp = {}
    st.inputs[id] = inp
    st.inputOrder[#st.inputOrder + 1] = id
  end
  inp.long = P.Str(d, 2, 20)
  inp.short = P.Str(d, 22, 4)
  inp.default = P.U8(d, 26) == 1
  inp.port = P.U8(d, 32)
  inp.sa = P.U8(d, 34)
  inp.me = P.U8(d, 35)
  return "input"
end

D["PrgI"] = function(st, d)
  ME(st, P.U8(d, 0) + 1).program = P.U16(d, 2)
  return "me"
end

D["PrvI"] = function(st, d)
  ME(st, P.U8(d, 0) + 1).preview = P.U16(d, 2)
  return "me"
end

D["TrPs"] = function(st, d)
  local m = ME(st, P.U8(d, 0) + 1)
  local was, lastHandle = m.inTransition, m.handle
  m.inTransition = P.U8(d, 1) == 1
  -- a completed transition (not one pulled back) flips the T-bar direction
  if was and not m.inTransition and lastHandle > 5000 then m.tbarFlipped = not m.tbarFlipped end
  m.remaining = P.U8(d, 2)
  m.handle = P.U16(d, 4)
  return "me"
end

D["TrSS"] = function(st, d)
  local m = ME(st, P.U8(d, 0) + 1)
  m.style = P.U8(d, 1)
  m.selection = P.U8(d, 2)
  m.nextStyle = P.U8(d, 3)
  m.nextSelection = P.U8(d, 4)
  return "me"
end

D["TrPr"] = function(st, d)
  ME(st, P.U8(d, 0) + 1).previewTransition = P.U8(d, 1) == 1
  return "me"
end

-- transition rates per style: 0 Mix, 1 Dip, 2 Wipe, 3 DVE
D["TMxP"] = function(st, d) ME(st, P.U8(d, 0) + 1).rates[0] = P.U8(d, 1) return "me" end
D["TDpP"] = function(st, d) ME(st, P.U8(d, 0) + 1).rates[1] = P.U8(d, 1) return "me" end
D["TWpP"] = function(st, d) ME(st, P.U8(d, 0) + 1).rates[2] = P.U8(d, 1) return "me" end
D["TDvP"] = function(st, d) ME(st, P.U8(d, 0) + 1).rates[3] = P.U8(d, 1) return "me" end

D["FtbS"] = function(st, d)
  local m = ME(st, P.U8(d, 0) + 1)
  m.ftbBlack = P.U8(d, 1) == 1
  m.ftbInTransition = P.U8(d, 2) == 1
  return "me"
end

D["FtbP"] = function(st, d)
  ME(st, P.U8(d, 0) + 1).ftbRate = P.U8(d, 1)
  return "me"
end

D["KeOn"] = function(st, d)
  ME(st, P.U8(d, 0) + 1).keyOnAir[P.U8(d, 1) + 1] = P.U8(d, 2) == 1
  return "me"
end

-- protocol 2.29 (firmware 8.0.1) and later
local function V801(st) return st.version >= 0x0002001d end
-- protocol 2.28 (firmware 8.0) and later
local function V80(st) return st.version >= 0x0002001c end
S.V80, S.V801 = V80, V801

local function Dsk(st, i)
  local d = st.dsk[i]
  if not d then
    d = { onAir = false, inTransition = false, isAuto = false, tie = false, rate = 0 }
    st.dsk[i] = d
  end
  return d
end

D["DskS"] = function(st, d)
  local k = Dsk(st, P.U8(d, 0) + 1)
  k.onAir = P.U8(d, 1) == 1
  k.inTransition = P.U8(d, 2) == 1
  k.isAuto = P.U8(d, 3) == 1
  return "dsk"
end

D["DskP"] = function(st, d)
  local k = Dsk(st, P.U8(d, 0) + 1)
  k.tie = P.U8(d, 1) == 1
  k.rate = P.U8(d, 2)
  return "dsk"
end

D["DskB"] = function(st, d)
  local k = Dsk(st, P.U8(d, 0) + 1)
  k.fill = P.U16(d, 2)
  k.key = P.U16(d, 4)
  return "dsk"
end

D["AuxS"] = function(st, d)
  st.aux[P.U8(d, 0) + 1] = P.U16(d, 2)
  return "aux"
end

D["KeBP"] = function(st, d)
  local m = ME(st, P.U8(d, 0) + 1)
  local k = P.U8(d, 1) + 1
  m.keys[k] = { type = P.U8(d, 2), fill = P.U16(d, 6), key = P.U16(d, 8) }
  return "me"
end

D["SSBP"] = function(st, d)
  local ssId, box, i = 0, nil, 0
  if V80(st) then
    ssId, box, i = P.U8(d, 0), P.U8(d, 1), 2
  else
    box = P.U8(d, 0)
  end
  local ss = st.ss[ssId + 1] or { boxes = {} }
  st.ss[ssId + 1] = ss
  ss.boxes[box + 1] = { enabled = P.U8(d, i > 0 and 2 or 1) == 1, source = P.U16(d, i + 2) }
  return "ss"
end

D["InCm"] = function(st, d)
  st.initDone = true
  return "init"
end

S.Decoders = D

-- Apply one received command. Returns change key, M/E index (if any) or nil when
-- the command is not handled.
function S.Apply(st, name, data)
  local fn = D[name]
  if not fn then return nil end
  local ok, key = pcall(fn, st, data)
  if not ok then return "error", key end
  local index = nil
  if key == "me" or key == "dsk" or key == "aux" then
    index = P.U8(data, 0) + 1
  elseif key == "ss" then
    index = V80(st) and P.U8(data, 0) + 1 or 1
  end
  return key, index
end

---------------------------------------------------------------------------
-- Encoders (me, keyer: 1-based)
---------------------------------------------------------------------------
local C = P.Command
local W8, W16 = P.W8, P.W16

S.Cmd = {}
local Cmd = S.Cmd

function Cmd.Program(me, source) return C("CPgI", W8(me - 1) .. "\0" .. W16(source)) end
function Cmd.Preview(me, source) return C("CPvI", W8(me - 1) .. "\0" .. W16(source)) end
function Cmd.Cut(me) return C("DCut", W8(me - 1) .. "\0\0\0") end
function Cmd.Auto(me) return C("DAut", W8(me - 1) .. "\0\0\0") end
function Cmd.FadeToBlack(me) return C("FtbA", W8(me - 1) .. "\0\0\0") end
function Cmd.FadeToBlackRate(me, rate) return C("FtbC", W8(1) .. W8(me - 1) .. W8(rate) .. "\0") end
function Cmd.TransitionPosition(me, pos) return C("CTPs", W8(me - 1) .. "\0" .. W16(pos)) end
function Cmd.PreviewTransition(me, on) return C("CTPr", W8(me - 1) .. W8(on and 1 or 0) .. "\0\0") end
function Cmd.NextStyle(me, style) return C("CTTp", W8(1) .. W8(me - 1) .. W8(style) .. "\0") end
function Cmd.NextSelection(me, mask) return C("CTTp", W8(2) .. W8(me - 1) .. "\0" .. W8(mask)) end
function Cmd.KeyOnAir(me, key, on) return C("CKOn", W8(me - 1) .. W8(key - 1) .. W8(on and 1 or 0) .. "\0") end

-- Downstream keyers (n: 1-based)
function Cmd.DskOnAir(n, on) return C("CDsL", W8(n - 1) .. W8(on and 1 or 0) .. "\0\0") end
function Cmd.DskTie(n, on) return C("CDsT", W8(n - 1) .. W8(on and 1 or 0) .. "\0\0") end
function Cmd.DskRate(n, rate) return C("CDsR", W8(n - 1) .. W8(rate) .. "\0\0") end
function Cmd.DskFill(n, source) return C("CDsF", W8(n - 1) .. "\0" .. W16(source)) end
function Cmd.DskKey(n, source) return C("CDsC", W8(n - 1) .. "\0" .. W16(source)) end
function Cmd.DskAuto(st, n)
  if S.V801(st) then return C("DDsA", "\0" .. W8(n - 1) .. "\0\0") end
  return C("DDsA", W8(n - 1) .. "\0\0\0")
end

function Cmd.Aux(aux, source) return C("CAuS", W8(1) .. W8(aux - 1) .. W16(source)) end

function Cmd.KeyType(me, key, keyType)
  return C("CKTp", W8(1) .. W8(me - 1) .. W8(key - 1) .. W8(keyType) .. P.Pad(4))
end
function Cmd.KeyFill(me, key, source) return C("CKeF", W8(me - 1) .. W8(key - 1) .. W16(source)) end
function Cmd.KeyKey(me, key, source) return C("CKeC", W8(me - 1) .. W8(key - 1) .. W16(source)) end

-- SuperSource box: flags 1 = enabled, 2 = source
function Cmd.SuperSourceBox(st, ss, box, enabled, source)
  local flag = (enabled ~= nil and 1 or 0) | (source and 2 or 0)
  if S.V80(st) then
    return C("CSBP", W16(flag) .. W8(ss - 1) .. W8(box - 1) .. W8(enabled and 1 or 0) .. "\0"
      .. W16(source or 0) .. P.Pad(16))
  end
  return C("CSBP", W16(flag) .. W8(box - 1) .. W8(enabled and 1 or 0) .. W16(source or 0) .. P.Pad(18))
end

-- Transition rate of a style (0 Mix, 1 Dip, 2 Wipe, 3 DVE); nil for styles without rate
function Cmd.TransitionRate(me, style, rate)
  rate = math.max(1, math.min(250, math.floor(rate)))
  if style == 0 then return C("CTMx", W8(me - 1) .. W8(rate) .. "\0\0") end
  if style == 1 then return C("CTDp", W8(1) .. W8(me - 1) .. W8(rate) .. P.Pad(5)) end
  if style == 2 then return C("CTWp", W16(1) .. W8(me - 1) .. W8(rate) .. P.Pad(16)) end
  if style == 3 then return C("CTDv", W16(1) .. W8(me - 1) .. W8(rate) .. P.Pad(16)) end
  return nil
end
