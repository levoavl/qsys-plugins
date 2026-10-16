#!/usr/bin/env python3
"""
Offline test harness for the Sound2Beat plugin (no Q-SYS needed).

Runs the built .qplug in Lua 5.3 (lupa) with mocks for Controls, Properties, Timer,
TcpSocket, UdpSocket and Component, and checks:
  - every property combination builds its controls and every page layout,
    and the runtime runs without errors (as in Emulation, nothing connected)
  - beat engine accuracy over simulated kicks (BPM, meter update rate, jitter, dropouts)
  - grandMA2: Telnet login, tempo command, hysteresis, reconnect after close
  - grandMA3: OSC packet format
  - Named Component level source, Tap, Hold, Half/Double

    pip install lupa
    python3 source/tools/build.py sound2beat
    python3 source/plugins/sound2beat/test/harness.py

(c) levo AVL | Elias Jenny - MIT License
"""

import itertools
import struct
import sys
from pathlib import Path

from lupa.lua53 import LuaRuntime

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "tools"))
from build import output_path  # noqa: E402

QPLUG = output_path("sound2beat")

MOCKS = r"""
-- ---------------------------------------------------------------- controls
local function NewControl(def)
  local raw = { Value = 0, Position = 0, String = "", Boolean = false }
  local min, max = def.Min or 0, def.Max or 1
  local numeric = def.ControlType == "Knob" or def.IndicatorType == "Meter"
  if not numeric then min, max = 0, 1 end
  if max == min then max = min + 1 end
  local function setValue(v)
    if numeric then v = math.max(min, math.min(max, v)) end
    raw.Value = v
    raw.Position = (v - min) / (max - min)
    raw.Boolean = v ~= 0
    if numeric then raw.String = def.ControlUnit == "Integer" and tostring(math.floor(v)) or tostring(v) end
  end
  setValue(def.DefaultValue or min)
  local obj = setmetatable({ _def = def, Legend = "", EventHandler = false }, {
    __index = function(t, k)
      if raw[k] ~= nil then return raw[k] end
      return rawget(t, k)
    end,
    __newindex = function(t, k, v)
      if k == "Value" then setValue(v)
      elseif k == "Position" then setValue(min + v * (max - min))
      elseif k == "Boolean" then setValue(v and 1 or 0)
      elseif k == "String" then raw.String = v
      else rawset(t, k, v) end
    end,
  })
  return obj
end

function MakeControls(defs)
  Controls = {}
  for _, d in ipairs(defs) do
    assert(Controls[d.Name] == nil, "duplicate control " .. d.Name)
    Controls[d.Name] = NewControl(d)
  end
end

function UserSet(name, field, value)
  local c = Controls[name]
  assert(c, "no control " .. name)
  c[field] = value
  if c.EventHandler then c.EventHandler(c) end
end

function Press(name)
  local c = Controls[name]
  assert(c, "no control " .. name)
  if c.EventHandler then c.EventHandler(c) end
end

-- ---------------------------------------------------------------- timer
SimTime = 1000
Timers = setmetatable({}, { __mode = "v" })   -- weak, like the Core
Timer = {
  New = function()
    local t = { running = false }
    function t:Start(iv) self.interval = iv; self.running = true end
    function t:Stop() self.running = false end
    Timers[#Timers + 1] = t
    return t
  end,
  Now = function() return SimTime end,
  CallAfter = function() error("CallAfter not mocked") end,
}
function Advance(dt)
  SimTime = SimTime + dt
  for _, t in pairs(Timers) do
    if t.running and t.EventHandler then t.EventHandler(t) end
  end
end

-- ---------------------------------------------------------------- sockets
Sockets = {}
TcpSocket = { Events = { Connected = "CONNECTED", Reconnect = "RECONNECT", Data = "DATA",
  Closed = "CLOSED", Error = "ERROR", Timeout = "TIMEOUT" } }
function TcpSocket.New()
  local s = { rx = "", tx = {}, BufferLength = 0 }
  function s:Connect(host, port) self.host, self.port = host, port end
  function s:Disconnect() self.disconnected = true end
  function s:Write(data) self.tx[#self.tx + 1] = data end
  function s:Read(n)
    local d = self.rx:sub(1, n); self.rx = self.rx:sub(n + 1); self.BufferLength = #self.rx; return d
  end
  Sockets[#Sockets + 1] = s
  return s
end
function ServerFeed(s, data)
  s.rx = s.rx .. data; s.BufferLength = #s.rx
  s.EventHandler(s, TcpSocket.Events.Data)
end
function ServerEvent(s, evt) s.EventHandler(s, evt) end

UdpPackets = {}
UdpSocket = { New = function()
  local u = {}
  function u:Open() self.open = true end
  function u:Send(ip, port, data)
    assert(self.open, "UDP send before Open")
    UdpPackets[#UdpPackets + 1] = { ip = ip, port = port, data = data }
  end
  return u
end }

-- ---------------------------------------------------------------- named components
NamedComponents = {}
Component = { New = function(name)
  local c = NamedComponents[name]
  if not c then error("no component " .. tostring(name)) end
  return c
end }
"""


class Plugin:
    def __init__(self, props=None, setup=None):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        L = self.lua
        L.execute(MOCKS)
        self.printed = []
        L.globals().print = lambda *a: self.printed.append(" ".join(str(x) for x in a))
        src = QPLUG.read_text(encoding="utf-8")
        L.execute("Controls = nil\n" + src)  # define functions only
        g = L.globals()
        plist = g.GetProperties()
        self.props = {plist[i].Name: plist[i].Value for i in range(1, len(plist) + 1)}
        self.props.update(props or {})
        lprops = L.table()
        for k, v in self.props.items():
            lprops[k] = L.table_from({"Value": v})
        lprops["plugin_show_debug"] = L.table_from({"Value": True})
        g.RectifyProperties(lprops)
        g.Properties = lprops
        g.MakeControls(g.GetControls(lprops))
        self.g = g
        # every page must build and reference existing controls only
        pages = g.GetPages(lprops)
        for i in range(1, len(pages) + 1):
            lp = L.table()
            for k, v in lprops.items():
                lp[k] = v
            lp["page_index"] = L.table_from({"Value": i})
            layout, graphics = g.GetControlLayout(lp)
            for name in layout.keys():
                assert g.Controls[name] is not None, f"page {pages[i].name}: unknown control {name}"
            assert len(graphics) > 3
        if setup:
            setup(self)
        L.execute(src)  # with Controls set -> runtime starts
        L.execute("collectgarbage() collectgarbage()")  # objects only held by locals die here

    def c(self, name):
        ctl = self.g.Controls[name]
        assert ctl is not None, f"no control {name}"
        return ctl

    def run(self, seconds, level_fn=None, tick=0.01):
        n = int(round(seconds / tick))
        for _ in range(n):
            if level_fn:
                level_fn(self, self.g.SimTime)
            self.g.Advance(tick)
        errors = [p for p in self.printed if "error" in p.lower()]
        assert not str(self.c("Last Error").String).startswith("Runtime error"), self.c("Last Error").String
        return errors

    def sockets(self):
        s = self.g.Sockets
        return [s[i] for i in range(1, len(s) + 1)]


def kick_level(bpm, update=0.02, start=1000.5):
    """Level function: meter of a kick drum at `bpm`, updated every `update` s."""
    state = {"next": 0.0, "db": -45.0}
    P = 60.0 / bpm

    def fn(p, t):
        if t >= state["next"]:
            age = (t - start) % P if t >= start else 99
            state["db"] = (-8 - age / 0.18 * 37) if age < 0.18 else -45.0
            state["next"] = t + update
        p.c("Level In").Value = state["db"]
    return fn


def check(cond, msg):
    print(("  ok    " if cond else "  FAIL  ") + msg)
    if not cond:
        check.failed += 1


check.failed = 0


def test_all_combinations():
    print("Property combinations (controls, layouts, emulation run):")
    for source, console, dbg in itertools.product(
            ["Wired Pin", "Named Component", "Test Generator"],
            ["None", "grandMA2", "grandMA3"], ["None", "Verbose"]):
        p = Plugin({"Level Source": source, "Console Type": console, "Debug Print": dbg})
        p.run(3)
        st = p.c("Status")
        check(st.Value in (0, 1, 4), f"{source:15} / {console:8} / {dbg:7}: status {int(st.Value)} '{st.String}'")


def test_engine_accuracy():
    print("Detection via Level In pin:")
    for bpm, upd in [(128, 0.01), (128, 0.05), (124, 0.03), (95, 0.03), (140, 0.02), (174, 0.03)]:
        p = Plugin({"Level Source": "Wired Pin", "Console Type": "None"})
        p.run(25, kick_level(bpm, upd))
        got = p.c("BPM").Value
        expect = bpm if bpm <= 160 else bpm / 2
        check(abs(got - expect) < 0.5 and p.c("Locked").Boolean,
              f"{bpm} BPM, meter {int(upd*1000)} ms -> {got:.1f} BPM, {p.c('Detection State').String}, "
              f"confidence {int(p.c('Confidence').Value)}%")


def test_beat_outputs():
    print("Beat LED, bar position, free running:")
    p = Plugin({"Level Source": "Wired Pin", "Console Type": "None"})
    p.run(10, kick_level(120))
    beats, bars, last = 0, set(), False
    def count(pl, t):
        nonlocal beats, last
        b = pl.c("Beat").Boolean
        if b and not last:
            beats += 1
            bars.add(int(pl.c("Bar Position").Value))
        last = b
        kick_level(120)(pl, t)
    p.run(10, count)
    check(19 <= beats <= 21, f"10 s at 120 BPM -> {beats} beat pulses")
    check(bars == {1, 2, 3, 4}, f"bar positions {sorted(bars)}")
    # silence: beat keeps blinking, state free running
    beats = 0
    def silent(pl, t):
        nonlocal beats, last
        pl.c("Level In").Value = -100
        b = pl.c("Beat").Boolean
        if b and not last:
            beats += 1
        last = b
    p.run(5, silent)
    check(beats >= 9 and p.c("Detection State").String == "Free Running",
          f"5 s silence -> {beats} beats, state {p.c('Detection State').String}")


def ma2_setup(p):
    p.c("IP Address").String = "10.0.0.5"
    p.c("Password").String = "secret"


def test_ma2():
    print("grandMA2 Telnet:")
    p = Plugin({"Level Source": "Wired Pin", "Console Type": "grandMA2"}, ma2_setup)
    socks = p.sockets()
    check(len(socks) == 1 and socks[0].host == "10.0.0.5" and socks[0].port == 30000, "connects to 10.0.0.5:30000")
    s = socks[0]
    p.g.ServerEvent(s, "CONNECTED")
    tx = "".join(s.tx[i] for i in range(1, len(s.tx) + 1))
    check('Login "administrator" "secret"\r\n' in tx, "sends login")
    p.g.ServerFeed(s, "\xff\xfb\x01Welcome\r\n\x1b[32mLogged in as User 'administrator'\x1b[0m\r\n[Channel]>")
    p.run(0.2)
    check(p.c("Logged In").Boolean and p.c("Status").Value in (0, 1), f"logged in, status '{p.c('Status').String}'")
    n0 = len(s.tx)
    p.run(20, kick_level(128, 0.02))
    sent = [s.tx[i] for i in range(n0 + 1, len(s.tx) + 1) if "SpecialMaster" in s.tx[i]]
    first = float(sent[0].split(" At ")[1]) if sent and sent[0].startswith("SpecialMaster 3.1 At ") else 0
    check(abs(first - 128) <= 0.3, f"tempo command {sent[:1]}")
    check(len(sent) <= 3, f"hysteresis keeps sends low ({len(sent)} in 20 s)")
    check(p.c("Last Sent").String.endswith(" BPM"), f"Last Sent '{p.c('Last Sent').String}'")
    p.g.ServerFeed(s, "Error #72: COMMAND NOT EXECUTED\r\n")
    check("Error #72" in p.c("Last Error").String, "MA2 error shown in Last Error")
    # connection lost -> backoff -> new socket, tempo sent again after login
    p.g.ServerEvent(s, "CLOSED")
    p.run(0.02)
    check(p.c("Status").Value == 4, f"status after close: '{p.c('Status').String}'")
    p.run(1.5, kick_level(128, 0.02))
    socks = p.sockets()
    check(len(socks) == 2, "reconnects after backoff")
    s2 = socks[-1]
    p.g.ServerEvent(s2, "CONNECTED")
    p.run(3.5, kick_level(128, 0.02))   # no login answer -> assumed after grace time
    tx2 = "".join(s2.tx[i] for i in range(1, len(s2.tx) + 1))
    check("SpecialMaster 3.1 At 12" in tx2, "tempo sent again after reconnect")
    # login failure
    p2 = Plugin({"Level Source": "Wired Pin", "Console Type": "grandMA2"}, ma2_setup)
    s3 = p2.sockets()[0]
    p2.g.ServerEvent(s3, "CONNECTED")
    p2.g.ServerFeed(s3, "Error: Login failed - wrong password\r\n")
    p2.run(0.1)
    check(p2.c("Status").Value == 2, f"login failure -> Fault '{p2.c('Status').String}'")


def test_ma3():
    print("grandMA3 OSC:")
    def setup(p):
        p.c("IP Address").String = "10.0.0.6"
        p.c("OSC Prefix").String = "gma3"
    p = Plugin({"Level Source": "Wired Pin", "Console Type": "grandMA3"}, setup)
    p.run(20, kick_level(126, 0.02))
    pk = p.g.UdpPackets
    check(len(pk) >= 1, f"{len(pk)} OSC packet(s)")
    if len(pk):
        d = pk[1]
        data = d.data.encode("latin-1") if isinstance(d.data, str) else bytes(d.data)
        head = b"/gma3/cmd\x00\x00\x00,s\x00\x00Master 3.1 At BPM "
        bpm = float(data[len(head):].rstrip(b"\x00") or 0) if data.startswith(head) else 0
        check(d.ip == "10.0.0.6" and d.port == 8000 and abs(bpm - 126) <= 0.3, f"packet {data!r}")
        check(len(data) % 4 == 0, "OSC packet 4-byte aligned")


def test_named_component():
    print("Named Component source:")
    meter = {}
    def setup(p):
        p.c("Meter Component").String = "KickMeter"
        L = p.lua
        meter["ctl"] = L.table_from({"Value": -100})
        p.g.NamedComponents["KickMeter"] = L.table_from({"meter.1": meter["ctl"]})
    p = Plugin({"Level Source": "Named Component", "Console Type": "None"}, setup)
    fn = kick_level(130, 0.02)
    def level(pl, t):
        fn(pl, t)   # writes Level In? not present -> write to the named control instead
    state = {"next": 0, "db": -45}
    def comp_level(pl, t):
        P = 60 / 130
        if t >= state["next"]:
            age = (t - 1000.5) % P
            state["db"] = (-8 - age / 0.18 * 37) if age < 0.18 else -45
            state["next"] = t + 0.02
        meter["ctl"].Value = state["db"]
    p.run(20, comp_level)
    check(abs(p.c("BPM").Value - 130) < 0.5, f"130 BPM from named meter -> {p.c('BPM').Value:.1f}")
    p2 = Plugin({"Level Source": "Named Component", "Console Type": "None"},
                lambda p: setattr(p.c("Meter Component"), "String", "Missing"))
    p2.run(1)
    check(p2.c("Status").Value == 1 and "not found" in p2.c("Status").String,
          f"missing component -> '{p2.c('Status').String}'")


def test_user_functions():
    print("Tap, Hold, Half/Double:")
    p = Plugin({"Level Source": "Wired Pin", "Console Type": "None"})
    p.run(1)
    for _ in range(5):
        p.g.Press("Tap")
        p.run(0.5)                      # 120 BPM
    check(abs(p.c("BPM").Value - 120) < 0.5 and p.c("Detection State").String == "Tap",
          f"tapped 120 -> {p.c('BPM').Value:.1f} ({p.c('Detection State').String})")
    p = Plugin({"Level Source": "Wired Pin", "Console Type": "None"})
    p.run(15, kick_level(128))
    p.g.Press("Half")
    p.run(0.2, kick_level(128))
    check(abs(p.c("BPM").Value - 64) < 0.5 and p.c("Tempo Scale").String == "x1/2", f"half -> {p.c('BPM').Value:.1f}")
    p.g.Press("Double"); p.g.Press("Double")
    p.run(0.2, kick_level(128))
    check(abs(p.c("BPM").Value - 256) < 1 and p.c("Tempo Scale").String == "x2", f"double -> {p.c('BPM').Value:.1f}")
    p.g.Press("Half")
    p.g.UserSet("Hold", "Boolean", True)
    p.run(10, kick_level(100))
    check(abs(p.c("BPM").Value - 128) < 0.5 and p.c("Detection State").String == "Hold",
          f"hold keeps 128 while music is 100 -> {p.c('BPM').Value:.1f}")
    p.g.UserSet("Hold", "Boolean", False)
    p.run(20, kick_level(100))
    check(abs(p.c("BPM").Value - 100) < 0.5, f"after hold: new song 100 -> {p.c('BPM').Value:.1f}")


def test_generator():
    print("Test Generator (Emulation):")
    p = Plugin({"Level Source": "Test Generator", "Console Type": "None"})
    p.run(20)
    check(abs(p.c("BPM").Value - 128) < 0.5 and p.c("Locked").Boolean,
          f"generator 128 -> {p.c('BPM').Value:.1f}, {p.c('Detection State').String}, updates {p.c('Level Updates').String}")


if __name__ == "__main__":
    test_all_combinations()
    test_engine_accuracy()
    test_beat_outputs()
    test_ma2()
    test_ma3()
    test_named_component()
    test_user_functions()
    test_generator()
    print(f"\n{'All tests passed' if not check.failed else f'{check.failed} test(s) FAILED'}")
    sys.exit(1 if check.failed else 0)
