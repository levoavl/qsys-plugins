-- (c) levo AVL | Elias Jenny - MIT License
-- Art-Net 4 packet building (ArtDmx only). Pure functions, no Q-SYS APIs, so the
-- same code runs in the offline test harness.

ArtNet = {
  PORT       = 6454,
  PROT_VER   = 14,
  OP_DMX     = 0x5000,
  SLOTS      = 512,
  MAX_NET    = 127,
  MAX_SUBNET = 15,
  MAX_UNI    = 15,
}

local function U16BE(n) return string.char((n >> 8) & 0xFF, n & 0xFF) end
local function U16LE(n) return string.char(n & 0xFF, (n >> 8) & 0xFF) end

-- "Art-Net\0", OpCode (little endian), ProtVer (big endian)
ArtNet.DMX_HEADER = "Art-Net\0" .. U16LE(ArtNet.OP_DMX) .. U16BE(ArtNet.PROT_VER)

local function Clamp(v, lo, hi)
  v = math.floor((tonumber(v) or 0) + 0.5)
  if v < lo then return lo elseif v > hi then return hi end
  return v
end
ArtNet.Clamp = Clamp

-- 15-bit Port-Address from Net / Sub-Net / Universe
function ArtNet.PortAddress(net, subnet, universe)
  return (Clamp(net, 0, ArtNet.MAX_NET) << 8) | (Clamp(subnet, 0, ArtNet.MAX_SUBNET) << 4)
    | Clamp(universe, 0, ArtNet.MAX_UNI)
end

-- ArtDmx packet. `slots` is a table with exactly 512 integers 0..255 (or nil for a
-- blackout). Always sends the full 512 slots: unused channels are explicit zeros,
-- so a receiver never sees undefined data beyond the channel count.
function ArtNet.Dmx(sequence, portAddress, slots)
  local data
  if slots then
    -- string.char with 512 arguments is fine in Lua 5.3; split anyway to stay
    -- well below any C-stack limit
    data = string.char(table.unpack(slots, 1, 256)) .. string.char(table.unpack(slots, 257, 512))
  else
    data = string.rep("\0", ArtNet.SLOTS)
  end
  return ArtNet.DMX_HEADER
    .. string.char(sequence & 0xFF, 0)              -- Sequence, Physical
    .. string.char(portAddress & 0xFF, (portAddress >> 8) & 0x7F)  -- SubUni, Net
    .. U16BE(ArtNet.SLOTS)                           -- Length
    .. data
end

function ArtNet.ValidIp(ip)
  if type(ip) ~= "string" then return false end
  local a, b, c, d = ip:match("^%s*(%d+)%.(%d+)%.(%d+)%.(%d+)%s*$")
  if not a then return false end
  for _, o in ipairs({ a, b, c, d }) do
    if tonumber(o) > 255 then return false end
  end
  return true
end
