#!/usr/bin/env python3
"""
Offline test harness for the Art-Net plugin (no Q-SYS, no node needed).

Runs the built .qplug in Lua 5.3 (lupa) with mocks for Controls, Properties,
UdpSocket, Timer and System, and checks the ArtDmx packets byte by byte.

    pip install lupa
    python3 source/tools/build.py artnet
    python3 source/plugins/artnet/test/harness.py

(c) levo AVL | Elias Jenny - MIT License
"""

import struct
import sys
from pathlib import Path

from lupa.lua53 import LuaRuntime

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "tools"))
from build import output_path  # noqa: E402

QPLUG = output_path("artnet")
# lupa runs with latin-1 so binary packets survive; map the few non-latin-1 chars
SRC = QPLUG.read_text(encoding="utf-8").encode("latin-1", "replace").decode("latin-1")

MOCKS = r"""
local function NewControl(def)
  local raw = { Value = 0, Position = 0, String = "", Boolean = false }
  local min, max = def.Min or 0, def.Max or 1
  if def.ControlType ~= "Knob" then min, max = 0, 1 end
  local function setValue(v)
    raw.Value = v
    raw.Position = (max > min) and (v - min) / (max - min) or 0
    raw.Boolean = v ~= 0
    if def.ControlUnit == "Integer" then raw.String = tostring(math.floor(v)) end
  end
  setValue(min)
  return setmetatable({ _def = def, EventHandler = false }, {
    __index = function(t, k)
      if raw[k] ~= nil then return raw[k] end
      return rawget(t, k)
    end,
    __newindex = function(t, k, v)
      if k == "Value" then setValue(v)
      elseif k == "Boolean" then setValue(v and 1 or 0)
      elseif k == "String" then raw.String = v
      else rawset(t, k, v) end
    end,
  })
end

function MakeControls(defs)
  Controls = {}
  for _, d in ipairs(defs) do
    assert(Controls[d.Name] == nil, "duplicate control " .. d.Name)
    Controls[d.Name] = NewControl(d)
  end
end

function UserSet(name, field, value)
  local c = assert(Controls[name], "no control " .. name)
  c[field] = value
  if c.EventHandler then c.EventHandler(c) end
end

Now = 0
Timers = setmetatable({}, { __mode = "v" })   -- weak like on the Core
Timer = { New = function()
  local t = { running = false }
  function t:Start(iv) self.interval = iv; self.nextAt = Now + iv; self.running = true end
  function t:Stop() self.running = false end
  Timers[#Timers + 1] = t
  return t
end, Now = function() return Now end }

function Advance(seconds, step)
  step = step or 1 / 30
  local target = Now + seconds
  while Now < target - 1e-9 do
    collectgarbage("collect")   -- unreferenced timers die, like on the Core
    Now = Now + step
    for _, t in pairs(Timers) do
      -- fire like the Core: only when the timer's own interval has elapsed
      if t.running and t.EventHandler and Now >= t.nextAt - 1e-9 then
        t.nextAt = t.nextAt + t.interval
        if t.nextAt < Now then t.nextAt = Now + t.interval end
        t.EventHandler(t)
      end
    end
  end
end

Sent = {}
UdpSocket = { New = function()
  local s = { opened = false }
  function s:Open() self.opened = true end
  function s:Send(ip, port, data)
    assert(self.opened, "send on closed socket")
    Sent[#Sent + 1] = { ip = ip, port = port, data = data }
  end
  return s
end }
"""


class Harness:
    def __init__(self, props=None, emulating=False, no_timer_now=False):
        self.lua = LuaRuntime(unpack_returned_tuples=True, encoding="latin-1")
        g = self.lua.globals()
        self.lua.execute(MOCKS)
        self.lua.execute(f"System = {{ IsEmulating = {'true' if emulating else 'false'} }}")
        if no_timer_now:
            self.lua.execute("Timer.Now = nil")
        g.Controls = None
        self.lua.execute(SRC)
        # property table keyed by name, like Designer passes it
        plist = self.lua.eval("GetProperties()")
        pt = self.lua.table()
        for _, p in plist.items():
            pt[p.Name] = p
        for k, v in (props or {}).items():
            pt[k].Value = v
        pt["plugin_show_debug"] = self.lua.table_from({"Value": True})
        pt = self.lua.globals().RectifyProperties(pt)
        self.props = pt
        # layout must build for every page without errors
        pages = g.PageList(pt)
        for i in range(1, len(pages) + 1):
            pt["page_index"] = self.lua.table_from({"Value": i})
            g.GetControlLayout(pt)
        g.MakeControls(g.GetControls(pt))
        g.Properties = pt
        # run the runtime part (Controls now set)
        self.lua.execute(SRC)
        self.g = g

    def sent(self):
        return [(e.ip, e.port, e.data.encode("latin-1")) for _, e in self.g.Sent.items()]

    def clear(self):
        self.lua.execute("Sent = {}")

    def set(self, name, field, value):
        self.g.UserSet(name, field, value)

    def ctl(self, name):
        return self.g.Controls[name]

    def advance(self, s):
        self.g.Advance(s)


def parse(data):
    assert data[:8] == b"Art-Net\0", data[:8]
    op, ver = struct.unpack("<H", data[8:10])[0], struct.unpack(">H", data[10:12])[0]
    seq, phys, subuni, net = data[12], data[13], data[14], data[15]
    length = struct.unpack(">H", data[16:18])[0]
    return dict(op=op, ver=ver, seq=seq, port=(net << 8) | subuni, length=length, slots=data[18:])


failures = 0


def check(cond, msg):
    global failures
    print(("  ok    " if cond else "  FAIL  ") + msg)
    if not cond:
        failures += 1


def test_basic():
    print("basic unicast, 1 universe, 28 channels")
    h = Harness({"Channels U1": 28})
    check(h.ctl("Status").Value == 4, "status Missing with no universe enabled")
    h.set("U1 Target IP", "String", "10.0.0.50")
    h.set("U1 Enable", "Boolean", True)
    check(h.ctl("Status").Value == 0, "status OK after enable")
    h.set("U1 Ch 1", "Value", 255)
    h.set("U1 Ch 28", "Value", 128)
    h.advance(0.1)
    pk = h.sent()
    check(len(pk) >= 1, "packet sent after change")
    ip, port, data = pk[-1]
    p = parse(data)
    check(ip == "10.0.0.50" and port == 6454, "unicast to target ip:6454")
    check(p["op"] == 0x5000 and p["ver"] == 14, "OpDmx, ProtVer 14")
    check(p["length"] == 512 and len(p["slots"]) == 512, "length field 512 = payload 512")
    check(p["slots"][0] == 255 and p["slots"][27] == 128, "channel values in place")
    check(all(b == 0 for b in p["slots"][28:]), "slots 29..512 are all zero")
    check(len(data) == 18 + 512, "total packet size 530")

    h.clear()
    h.advance(3.0)
    n = len(h.sent())
    check(2 <= n <= 4, f"keep-alive ~1/s when idle ({n} packets in 3 s)")

    h.clear()
    for v in range(0, 256, 5):
        h.set("U1 Ch 2", "Value", v)
        h.g.Advance(1 / 300, 1 / 300)
    h.advance(0.2)
    n = len(h.sent())
    check(n <= 30 * (0.2 + 52 / 300) + 2, f"rate limited to refresh rate ({n} packets)")
    seqs = [parse(d)["seq"] for _, _, d in h.sent()]
    check(all(1 <= s <= 255 for s in seqs), "sequence never 0")

    h.set("Blackout", "Boolean", True)
    h.clear()
    h.advance(0.1)
    check(all(b == 0 for b in parse(h.sent()[-1][2])["slots"]), "blackout sends all zeros")
    h.set("Blackout", "Boolean", False)
    h.clear()
    h.advance(0.1)
    check(parse(h.sent()[-1][2])["slots"][0] == 255, "values restored after blackout")


def test_multi():
    print("two universes, port address, broadcast")
    h = Harness({"Universe Count": 2, "Channels U1": 16, "Channels U2": 512})
    h.set("U1 Target IP", "String", "10.0.0.50")
    h.set("U2 Target IP", "String", "10.0.0.51")
    h.set("U2 Net", "Value", 1)
    h.set("U2 SubNet", "Value", 2)
    h.set("U2 Universe", "Value", 3)
    h.set("U1 Enable", "Boolean", True)
    h.set("U2 Enable", "Boolean", True)
    h.set("U2 Ch 512", "Value", 77)
    h.advance(0.1)
    by_ip = {ip: parse(d) for ip, _, d in h.sent()}
    check(by_ip["10.0.0.50"]["port"] == 0, "U1 port address 0")
    check(by_ip["10.0.0.51"]["port"] == 0x123, "U2 port address 1:2:3 = 0x123")
    check(by_ip["10.0.0.51"]["slots"][511] == 77, "U2 channel 512 set")
    h.set("Broadcast", "Boolean", True)
    h.set("Broadcast Address", "String", "2.255.255.255")
    h.clear()
    h.advance(0.1)
    check({ip for ip, _, _ in h.sent()} == {"2.255.255.255"}, "broadcast goes to broadcast address only")
    h.set("U1 Target IP", "String", "not an ip")
    h.set("Broadcast", "Boolean", False)
    check(h.ctl("Status").Value == 2, "invalid IP -> Fault")


def test_emulation():
    print("emulation")
    h = Harness({"Channels U1": 8}, emulating=True)
    h.set("U1 Target IP", "String", "10.0.0.50")
    h.set("U1 Enable", "Boolean", True)
    h.advance(2.0)
    check(len(h.sent()) == 0, "nothing sent in emulation by default")
    check(h.ctl("Status").Value == 1, "status Compromised with hint")
    h.set("Send in Emulation", "Boolean", True)
    h.advance(0.1)
    check(len(h.sent()) >= 1, "sends after Emulation TX is enabled")


def test_no_timer_now():
    print("firmware without Timer.Now")
    h = Harness({"Channels U1": 8}, no_timer_now=True)
    h.set("U1 Target IP", "String", "10.0.0.50")
    h.set("U1 Enable", "Boolean", True)
    h.advance(0.2)
    check(len(h.sent()) >= 1, "sends without Timer.Now")
    h.clear()
    h.advance(3.0)
    n = len(h.sent())
    check(2 <= n <= 4, f"keep-alive still ~1/s ({n} packets in 3 s)")


test_basic()
test_multi()
test_no_timer_now()
test_emulation()
print("\nall passed" if failures == 0 else f"\n{failures} FAILED")
sys.exit(1 if failures else 0)
