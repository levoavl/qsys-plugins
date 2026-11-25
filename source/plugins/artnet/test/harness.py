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
Sockets = {}
PortBusy = false
UdpSocket = { New = function()
  local s = { opened = false }
  function s:Open(ip, port)
    if port == 6454 and PortBusy then error("address already in use") end
    self.opened, self.port = true, port
  end
  function s:Send(ip, port, data)
    assert(self.opened, "send on closed socket")
    Sent[#Sent + 1] = { ip = ip, port = port, data = data, from = self.port }
  end
  Sockets[#Sockets + 1] = s
  return s
end }

Network = { Interfaces = function()
  return { { Interface = "LAN A", Address = "192.168.1.10", Netmask = "255.255.255.0" },
           { Interface = "LAN B", Address = "10.0.0.10", Netmask = "255.255.255.0", MACAddress = "00:60:74:aa:bb:cc" } }
end }
Design = { GetStatus = function() return { DesignName = "Test Design" } end }

function Feed(from, data)
  for _, s in ipairs(Sockets) do
    if s.port == 6454 and s.EventHandler then s.EventHandler(s, { Address = from, Port = 6454, Data = data }) end
  end
end

function FeedPoll(from)
  for _, s in ipairs(Sockets) do
    if s.port == 6454 and s.EventHandler then
      s.EventHandler(s, { Address = from, Port = 6454,
        Data = "Art-Net\0" .. string.char(0x00, 0x20, 0, 14, 0, 0) })
    end
  end
end
"""


def artdmx(port_address, slots, seq=1, length=None):
    data = bytes(slots)
    if length is None:
        length = len(data)
    return (b"Art-Net\0" + struct.pack("<H", 0x5000) + struct.pack(">H", 14) + bytes([seq, 0])
            + bytes([port_address & 0xFF, (port_address >> 8) & 0x7F]) + struct.pack(">H", length) + data)


def artpollreply(ip, short):
    d = bytearray(239)
    d[0:8] = b"Art-Net\0"
    d[8:10] = struct.pack("<H", 0x2100)
    d[10:14] = bytes(int(x) for x in ip.split("."))
    d[26:26 + len(short)] = short.encode()
    return bytes(d)


class Harness:
    def __init__(self, props=None, emulating=False, no_timer_now=False, port_busy=False):
        self.lua = LuaRuntime(unpack_returned_tuples=True, encoding="latin-1")
        g = self.lua.globals()
        self.lua.execute(MOCKS)
        self.lua.execute(f"System = {{ IsEmulating = {'true' if emulating else 'false'} }}")
        if port_busy:
            self.lua.execute("PortBusy = true")
        if no_timer_now:
            self.lua.execute("Timer.Now = nil")
        g.Controls = None
        self.lua.execute(SRC)
        # property table keyed by name, like Designer passes it
        plist = self.lua.eval("GetProperties()")
        pt = self.lua.table()
        for _, p in plist.items():
            pt[p.Name] = p
        self.default_send_mode = pt["Send Mode"].Value
        # most tests check the on-change timing; continuous has its own test
        for k, v in {"Send Mode": "On Change", **(props or {})}.items():
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

    def feed(self, sender, data):
        self.g.Feed(sender, data.decode("latin-1"))

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
    check(h.g.Sent[len(pk)]["from"] == 6454, "DMX sent from source port 6454")

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


def test_discovery():
    print("discovery (ArtPoll / ArtPollReply)")
    h = Harness({"Universe Count": 2, "Channels U1": 8, "Channels U2": 8})
    check("active" in h.ctl("Discovery").String, "discovery socket bound to 6454")
    ann = [ip for ip, _, d in h.sent() if d[8:10] == bytes([0x00, 0x21])]
    check(len(ann) == 2 and set(ann) == {"192.168.1.255"}, "announcement at start-up to first subnet broadcast")
    h.set("Node Name", "String", "Kesselhaus Licht")
    h.set("U1 Target IP", "String", "10.0.0.50")
    h.set("U1 Enable", "Boolean", True)
    h.set("U2 SubNet", "Value", 1)
    h.set("U2 Universe", "Value", 1)
    h.clear()
    h.g.FeedPoll("10.0.0.99")
    replies = [(ip, port, d) for ip, port, d in h.sent() if d[8:10] == bytes([0x00, 0x21])]
    check(len(replies) == 4, "one ArtPollReply per universe, unicast + subnet broadcast")
    check({r[0] for r in replies} == {"10.0.0.99", "10.0.0.255"}, "targets: poller and 10.0.0.255")
    replies = [r for r in replies if r[0] == "10.0.0.99"]
    ip, port, d = replies[0]
    check(port == 6454, "reply goes to port 6454")
    check(d[201:207] == bytes([0x00, 0x60, 0x74, 0xAA, 0xBB, 0xCC]), "MAC of the interface")
    check(len(d) == 239, "reply length 239")
    check(d[10:14] == bytes([10, 0, 0, 10]), "own IP from the interface in the poller's subnet")
    check(d[26:44].rstrip(b"\0") == b"Kesselhaus Licht", "short name = Node Name")
    check(b"Test Design" in d[44:108], "long name carries the design name")
    check(d[178] == 0x80 and replies[1][2][178] == 0x00, "GoodInput: U1 active, U2 idle")
    d2 = replies[1][2]
    check(d2[18] == 0 and d2[19] == 1 and d2[186] == 1 and d2[211] == 2, "U2 Net/Sub/Uni + bind index 2")

    h2 = Harness({"Channels U1": 8}, port_busy=True)
    h2.set("U1 Target IP", "String", "10.0.0.50")
    h2.set("U1 Enable", "Boolean", True)
    h2.advance(0.2)
    check("not available" in h2.ctl("Discovery").String, "port busy -> discovery not available")
    check(len(h2.sent()) >= 1 and h2.ctl("Status").Value == 0, "sending still works without discovery")


def test_continuous():
    print("send mode continuous")
    check(Harness().default_send_mode == "Continuous", "Continuous is the default send mode")
    check(Harness().ctl("U1 Enable").Boolean is False, "Enable off by default")
    h = Harness({"Channels U1": 8, "Send Mode": "Continuous", "Refresh Rate (Hz)": 30})
    h.set("U1 Target IP", "String", "10.0.0.50")
    h.set("U1 Enable", "Boolean", True)
    h.advance(0.5)
    h.clear()
    h.advance(2.0)
    n = len(h.sent())
    check(55 <= n <= 62, f"~30 packets/s while idle ({n} in 2 s)")


def test_range():
    print("send channel range 100-130")
    h = Harness({"Start Channel U1": 100, "Channels U1": 31})
    check(h.ctl("U1 Ch 100") is not None and h.ctl("U1 Ch 130") is not None, "controls named Ch 100..130")
    check(h.ctl("U1 Ch 99") is None and h.ctl("U1 Ch 131") is None, "no controls outside the range")
    h.set("U1 Target IP", "String", "10.0.0.50")
    h.set("U1 Enable", "Boolean", True)
    h.set("U1 Ch 100", "Value", 11)
    h.set("U1 Ch 130", "Value", 22)
    h.advance(0.1)
    p = parse(h.sent()[-1][2])
    check(p["slots"][99] == 11 and p["slots"][129] == 22, "values at DMX 100 and 130")
    check(all(b == 0 for i, b in enumerate(p["slots"]) if i < 99 or i > 129), "everything else 0")
    h2 = Harness({"Start Channel U1": 500, "Channels U1": 32})
    check(h2.ctl("U1 Ch 512") is not None and h2.ctl("U1 Ch 513") is None, "range clamped at 512")


def test_receive():
    print("receive")
    h = Harness({"Mode U1": "Receive", "Start Channel U1": 10, "Channels U1": 5})
    check(h.ctl("U1 Target IP") is None, "no target IP on a receive universe")
    h.set("U1 Universe", "Value", 1)
    h.advance(1.1)
    check(h.ctl("Status").Value == 4, "Missing while no data")
    slots = [0] * 512
    slots[9], slots[13], slots[14] = 200, 77, 99   # DMX 10, 14 (in range), 15 (out of range)
    h.feed("192.168.1.239", artdmx(1, slots))
    check(h.ctl("U1 Ch 10").Value == 200 and h.ctl("U1 Ch 14").Value == 77, "values arrive on Ch 10 / Ch 14")
    check(h.ctl("U1 Data").Boolean, "Data LED on")
    h.feed("192.168.1.239", artdmx(2, [255] * 512))
    check(h.ctl("U1 Ch 10").Value == 200, "other port address ignored")
    h.feed("192.168.1.239", artdmx(1, [5] * 12))
    check(h.ctl("U1 Ch 12").Value == 5 and h.ctl("U1 Ch 13").Value == 0, "short packet: missing slots are 0")
    h.feed("192.168.1.10", artdmx(1, [250] * 512))
    check(h.ctl("U1 Ch 10").Value == 5, "own packets ignored")
    h.feed("192.168.1.239", artpollreply("192.168.1.239", "Arena"))
    for _ in range(30):
        h.feed("192.168.1.239", artdmx(1, [9] * 512))
        h.g.Advance(1 / 30)
    check(h.ctl("Status").Value == 0, "status OK while receiving")
    info = h.ctl("U1 Info").String
    check("Arena" in info and "pkt/s" in info, f"info shows sender name and rate ({info})")
    h.feed("192.168.1.240", artdmx(1, [1] * 512))
    h.advance(1.1)
    check(h.ctl("Status").Value == 1, "two sources -> Compromised")

    h.set("U1 Source Filter", "String", "192.168.1.239")
    h.feed("192.168.1.240", artdmx(1, [3] * 512))
    check(h.ctl("U1 Ch 10").Value != 3, "source filter blocks other IPs")

    h.advance(4.5)
    check(not h.ctl("U1 Data").Boolean and h.ctl("U1 Ch 10").Value != 0, "timeout: LED off, Hold keeps values")
    check(h.ctl("Status").Value == 4, "status Missing after timeout")
    h.set("U1 On Loss", "String", "Zero")
    h.feed("192.168.1.239", artdmx(1, [9] * 512))
    h.advance(4.5)
    check(h.ctl("U1 Ch 10").Value == 0, "timeout with Zero sets channels to 0")

    print("mixed send + receive")
    h = Harness({"Universe Count": 2, "Mode U2": "Receive", "Channels U1": 4, "Channels U2": 4})
    h.set("U1 Target IP", "String", "192.168.1.239")
    h.set("U1 Enable", "Boolean", True)
    h.set("U2 Universe", "Value", 3)
    h.feed("192.168.1.239", artdmx(3, [42] * 512))
    h.advance(1.1)
    check(h.ctl("U2 Ch 1").Value == 42, "U2 receives while U1 sends")
    check(h.ctl("Status").Value == 0 and "receiving 1" in h.ctl("Status").String, h.ctl("Status").String)
    polls = [ip for ip, _, d in h.sent() if d[8:10] == bytes([0x00, 0x20])]
    check(len(polls) >= 1, "sends ArtPoll to learn sender names")
    h.clear()
    h.g.FeedPoll("192.168.1.239")
    rep = [d for ip, _, d in h.sent() if d[8:10] == bytes([0x00, 0x21]) and ip == "192.168.1.239"]
    check(len(rep) == 2 and rep[0][174] == 0x40 and rep[1][174] == 0x80, "reply: U1 input port, U2 output port")
    check(rep[1][190] == 3, "U2 SwOut = universe 3")


test_basic()
test_range()
test_receive()
test_multi()
test_discovery()
test_continuous()
test_no_timer_now()
test_emulation()
print("\nall passed" if failures == 0 else f"\n{failures} FAILED")
sys.exit(1 if failures else 0)
