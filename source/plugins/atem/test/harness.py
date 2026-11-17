#!/usr/bin/env python3
"""
Offline test harness for the ATEM plugin (no Q-SYS, no switcher needed).

Runs the built .qplug in Lua 5.3 (lupa) with mocks for Controls, Properties,
UdpSocket and Timer, plays a fake ATEM switcher on the protocol level (handshake,
acks, resends, out-of-order packets) and checks the plugin's behaviour.

    pip install lupa
    python3 source/tools/build.py atem
    python3 source/plugins/atem/test/harness.py

(c) levo AVL | Elias Jenny - MIT License
"""

import random
import struct
import sys
from pathlib import Path

from lupa.lua53 import LuaRuntime

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "tools"))
from build import output_path  # noqa: E402

QPLUG = output_path("atem")
TICK = 0.02

MOCKS = r"""
-- ---------------------------------------------------------------- controls
local function NewControl(def)
  local raw = { Value = 0, Position = 0, String = "", Boolean = false }
  local min, max = def.Min or 0, def.Max or 1
  if def.ControlType == "Knob" then
    if max == min then max = min + 1 end
  else
    min, max = 0, 1
  end
  local function setValue(v)
    raw.Value = v
    raw.Position = (max > min) and (v - min) / (max - min) or 0
    raw.Boolean = v ~= 0
    if def.ControlUnit == "Integer" then raw.String = tostring(math.floor(v)) end
  end
  setValue(min)
  return setmetatable({ _def = def, Legend = "", EventHandler = false, Choices = {} }, {
    __index = function(t, k)
      if k == "Value" or k == "Position" or k == "String" or k == "Boolean" then return raw[k] end
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
end

function MakeControls(defs)
  Controls = {}
  for _, d in ipairs(defs) do
    assert(Controls[d.Name] == nil, "duplicate control " .. d.Name)
    Controls[d.Name] = NewControl(d)
  end
end

-- user action: like Q-SYS, a toggle flips on press, then the handler runs
function UserSet(name, field, value)
  local c = Controls[name]
  assert(c, "no control " .. name)
  if field == "press" then
    if c._def.ButtonType == "Toggle" then c.Boolean = not c.Boolean else c.Boolean = true end
  else
    c[field] = value
  end
  if c.EventHandler then c.EventHandler(c) end
end

-- ---------------------------------------------------------------- timer
Timers = setmetatable({}, { __mode = "v" })   -- weak like on the Core
Timer = { New = function()
  local t = { running = false }
  function t:Start(iv) self.interval = iv; self.running = true end
  function t:Stop() self.running = false end
  Timers[#Timers + 1] = t
  return t
end, CallAfter = function() error("CallAfter not mocked") end }

function TickAll()
  for _, t in pairs(Timers) do
    if t.running and t.EventHandler then t.EventHandler(t) end
  end
end

-- ---------------------------------------------------------------- udp
UdpSockets = setmetatable({}, { __mode = "v" })
UdpSocket = { New = function()
  local s = { tx = {}, opened = false }
  function s:Open() self.opened = true end
  function s:Close() self.opened = false end
  function s:Send(ip, port, data)
    assert(self.opened, "send on closed socket")
    self.tx[#self.tx + 1] = { ip = ip, port = port, data = data }
  end
  UdpSockets[#UdpSockets + 1] = s
  return s
end }

function UdpFeed(s, address, data)
  s.EventHandler(s, { Address = address, Port = 9910, Data = data })
end
"""

# ---------------------------------------------------------------------- protocol
F_ACKREQ, F_HELLO, F_RETX, F_RETXREQ, F_ACK = 0x01, 0x02, 0x04, 0x08, 0x10


def header(flags, length, session, ack=0, retx=0, pid=0):
    return struct.pack(">HHHHHH", (flags << 11) | length, session, ack, retx, 0, pid)


def cmd(name, data):
    return struct.pack(">H", len(data) + 8) + b"\0\0" + name.encode() + data


def name_field(s, n):
    b = s.encode()[:n]
    return b + b"\0" * (n - len(b))


class FakeAtem:
    """Switcher side of the protocol, enough for the plugin's needs."""

    SESSION = 0x8123

    def __init__(self, h, model_id=16, product="ATEM Mini Extreme", mes=1, keys=4):
        self.h = h
        self.model_id, self.product, self.mes, self.keys = model_id, product, mes, keys
        self.next_id = 1
        self.last_client_id = 0
        self.received = []          # (name, data) commands from the plugin
        self.sent = {}              # packet id -> raw packet (for resends)
        self.program = {m: 1 for m in range(mes)}
        self.preview = {m: 2 for m in range(mes)}
        self.next = {}
        self.boxes = {}
        self.colors = {}
        self.video_mode = 10   # 1080p25

    # -------- packets to the plugin
    def packet(self, commands, pid=None):
        payload = b"".join(commands)
        if pid is None:
            pid, self.next_id = self.next_id, self.next_id + 1
        raw = header(F_ACKREQ, 12 + len(payload), self.SESSION, pid=pid) + payload
        self.sent[pid] = raw
        return raw

    def feed(self, raw):
        self.h.g.UdpFeed(self.h.sock(), b"10.0.0.9", raw)

    def hello_reply(self):
        self.feed(header(F_HELLO, 20, 0x53AB, pid=0) + bytes([0x02]) + b"\0" * 7)

    def inputs(self):
        lst = [(0, "Black", "BLK", 1), (1000, "Color Bars", "BARS", 2), (2001, "Color 1", "COL1", 3),
               (2002, "Color 2", "COL2", 3)]
        lst += [(i, f"Camera {i}", f"CAM{i}", 0) for i in range(1, 9)]
        lst += [(3010, "Media Player 1", "MP1", 4), (3011, "Media Player 1 Key", "MP1K", 5),
                (3020, "Media Player 2", "MP2", 4), (3021, "Media Player 2 Key", "MP2K", 5),
                (6000, "Super Source", "SSRC", 6), (7001, "Clean Feed 1", "CFD1", 128),
                (10010, "Program", "PGM", 128), (10011, "Preview", "PVW", 128)]
        return lst

    def state_commands(self):
        c = [cmd("_ver", struct.pack(">I", 0x00020020)),
             cmd("_pin", name_field(self.product, 40) + bytes([self.model_id]) + b"\0" * 3)]
        top = bytearray(24)
        top[0], top[1], top[2], top[3], top[5] = self.mes, 24, 2, 3, 2
        top[11] = 1  # supersources (with v2.30 offset)
        c.append(cmd("_top", bytes(top)))
        c.append(cmd("VidM", bytes([self.video_mode, 0, 0, 0])))
        for m in range(self.mes):
            c.append(cmd("_MeC", bytes([m, self.keys, 0, 0])))
        for (i, long, short, port) in self.inputs():
            me_avail = 0 if (i >= 7000) else (1 << self.mes) - 1
            d = struct.pack(">H", i) + name_field(long, 20) + name_field(short, 4) + bytes([1, 0])
            d += struct.pack(">HH", 0, 2) + bytes([port, 0, 31, me_avail])
            c.append(cmd("InPr", d))
        for m in range(self.mes):
            c += [cmd("PrgI", bytes([m, 0]) + struct.pack(">H", self.program[m])),
                  cmd("PrvI", bytes([m, 0]) + struct.pack(">H", self.preview[m]) + b"\0\0\0\0"),
                  cmd("TrSS", bytes([m, 0, 1, 0, 1, 0, 0, 0])),
                  cmd("TrPr", bytes([m, 0, 0, 0])),
                  cmd("TrPs", bytes([m, 0, 25, 0, 0, 0, 0, 0])),
                  cmd("TMxP", bytes([m, 25, 0, 0])),
                  cmd("TDpP", bytes([m, 30, 0, 0])),
                  cmd("FtbS", bytes([m, 0, 0, 0])),
                  cmd("FtbP", bytes([m, 30, 0, 0]))]
            for k in range(self.keys):
                c.append(cmd("KeOn", bytes([m, k, 0, 0])))
                c.append(cmd("KeBP", bytes([m, k, 0, 0, 0, 0]) + struct.pack(">HH", 3010, 3011) + bytes(12)))
            c.append(cmd("Zzzz", b"\x01\x02\x03\x04"))   # unknown command must be ignored
        for n in range(2):
            c += [cmd("DskS", bytes([n, 0, 0, 0, 0, 0, 0, 0])),
                  cmd("DskP", bytes([n, 0, 25]) + bytes(17)),
                  cmd("DskB", bytes([n, 0]) + struct.pack(">HH", 3010, 3011) + b"\0\0")]
        for aux in range(3):
            c.append(cmd("AuxS", bytes([aux, 0]) + struct.pack(">H", 10010)))
        for box in range(4):
            c.append(cmd("SSBP", bytes([0, box, 1 if box == 0 else 0, 0]) + struct.pack(">H", box + 1) + bytes(18)))
        for mp in range(2):
            c += [cmd("MPCE", bytes([mp, 1, mp, 0])), cmd("RCPS", bytes([mp, 0, 0, 1, 0, 0, 0, 0]))]
        for i in range(20):
            name = f"still{i + 1}.png".encode() if i < 3 else b""
            c.append(cmd("MPfe", bytes([0, 0]) + struct.pack(">H", i) + bytes([1 if i < 3 else 0]) + bytes(18)
                         + bytes([len(name)]) + name + bytes((4 - (24 + len(name)) % 4) % 4)))
        for n in range(2):
            c.append(cmd("ColV", bytes([n, 0]) + struct.pack(">HHH", 1200, 500, 1000)))
        for i in range(100):
            name = b"Intro" if i == 0 else (b"Outro" if i == 4 else b"")
            used = 1 if name else 0
            c.append(cmd("MPrp", struct.pack(">H", i) + bytes([used, 0]) + struct.pack(">HH", len(name), 0)
                         + name + bytes((4 - len(name) % 4) % 4)))
        c.append(cmd("MRPr", bytes([0, 0]) + struct.pack(">H", 0xFFFF)))
        c.append(cmd("InCm", b"\x01\0\0\0"))
        return c

    def dump(self, shuffle=False, duplicate=False):
        """Send the initial state in several packets."""
        cmds = self.state_commands()
        packets, cur, size = [], [], 12
        for c in cmds:
            if size + len(c) > 160:   # small packets -> many of them
                packets.append(self.packet(cur))
                cur, size = [], 12
            cur.append(c)
            size += len(c)
        packets.append(self.packet(cur))
        order = list(packets)
        if shuffle:
            first, rest = order[0], order[1:]
            random.shuffle(rest)
            order = [first] + rest if random.random() < 0.5 else rest + [first]
        for p in order:
            self.feed(p)
            if duplicate:
                self.feed(p)
        return len(packets)

    # -------- packets from the plugin
    def take(self, acks=False):
        """Parse what the plugin sent (pure acks only with acks=True)."""
        s = self.h.sock()
        out = []
        for i in range(1, len(s.tx) + 1):
            e = s.tx[i]
            assert self.h._s(e.ip) == "10.0.0.9" and e.port == 9910
            raw = bytes(e.data)
            w0, session, ack, retx, _, pid = struct.unpack(">HHHHHH", raw[:12])
            flags, length = w0 >> 11, w0 & 0x7FF
            assert length == len(raw), "length field mismatch"
            cmds, pos = [], 12
            while pos < len(raw):
                n = struct.unpack(">H", raw[pos:pos + 2])[0]
                cmds.append((raw[pos + 4:pos + 8].decode(), raw[pos + 8:pos + n]))
                pos += n
            if acks or flags != F_ACK:
                out.append({"flags": flags, "session": session, "ack": ack, "pid": pid, "cmds": cmds, "raw": raw})
        for i in range(len(s.tx), 0, -1):
            del s.tx[i]
        return out

    def ack(self, pid):
        self.feed(header(F_ACK, 12, self.SESSION, ack=pid))

    def handle(self, packets, ack=True):
        """Apply plugin commands like a switcher would and answer with feedback."""
        feedback = []
        for p in packets:
            if not p["flags"] & F_ACKREQ:
                continue
            self.last_client_id = p["pid"]
            for name, d in p["cmds"]:
                self.received.append((name, d))
                me = d[0]
                if name == "CPgI":
                    self.program[me] = struct.unpack(">H", d[2:4])[0]
                    feedback.append(cmd("PrgI", bytes([me, 0]) + d[2:4]))
                elif name == "CPvI":
                    self.preview[me] = struct.unpack(">H", d[2:4])[0]
                    feedback.append(cmd("PrvI", bytes([me, 0]) + d[2:4] + b"\0\0\0\0"))
                elif name == "CAuS":
                    feedback.append(cmd("AuxS", bytes([d[1], 0]) + d[2:4]))
                elif name == "CDsL":
                    feedback.append(cmd("DskS", bytes([d[0], d[1], 0, 0, 0, 0, 0, 0])))
                elif name == "CSBP":
                    flag = struct.unpack(">H", d[0:2])[0]
                    box = self.boxes.setdefault(d[3], [0, d[3] + 1])
                    if flag & 1:
                        box[0] = d[4]
                    if flag & 2:
                        box[1] = struct.unpack(">H", d[6:8])[0]
                    feedback.append(cmd("SSBP", bytes([d[2], d[3], box[0], 0]) + struct.pack(">H", box[1]) + bytes(18)))
                elif name == "MPSS":
                    mp = d[1]
                    feedback.append(cmd("MPCE", bytes([mp, d[2], d[3], d[4]])))
                elif name == "MAct":
                    idx = struct.unpack(">H", d[0:2])[0]
                    if d[2] == 0:
                        feedback.append(cmd("MRPr", bytes([1, 0]) + struct.pack(">H", idx)))
                    elif d[2] == 1:
                        feedback.append(cmd("MRPr", bytes([0, 0]) + struct.pack(">H", 0xFFFF)))
                elif name == "CClV":
                    n = d[1]
                    old = self.colors.get(n, [1200, 500, 1000])
                    for bit, k in ((1, 0), (2, 1), (4, 2)):
                        if d[0] & bit:
                            old[k] = struct.unpack(">H", d[2 + 2 * k:4 + 2 * k])[0]
                    self.colors[n] = old
                    feedback.append(cmd("ColV", bytes([n, 0]) + struct.pack(">HHH", *old)))
                elif name == "CTTp":
                    me = d[1]
                    style, sel = self.next.get(me, (0, 1))
                    if d[0] & 1:
                        style = d[2]
                    if d[0] & 2:
                        sel = d[3]
                    self.next[me] = (style, sel)
                    feedback.append(cmd("TrSS", bytes([me, style, sel, style, sel, 0, 0, 0])))
            if ack:
                self.ack(p["pid"])
        if feedback:
            self.feed(self.packet(feedback))


class Harness:
    def __init__(self, props=None, ip="10.0.0.9"):
        self.lua = LuaRuntime(unpack_returned_tuples=True, encoding=None)
        L = self.lua
        L.execute(MOCKS.encode())
        self.printed = []
        L.globals().print = lambda *a: self.printed.append(" ".join(self._s(x) for x in a))
        src = QPLUG.read_bytes()
        L.execute(b"Controls = nil\n" + src)  # define functions only (Controls nil -> no runtime)
        g = L.globals()
        props_list = g.GetProperties()
        self.props = {}
        for i in range(1, len(props_list) + 1):
            p = props_list[i]
            self.props[self._s(p.Name)] = p.Value
        self.props.update(props or {})
        lprops = self.make_props(self.props)
        g.Properties = lprops
        g.RectifyProperties(lprops)
        g.MakeControls(g.GetControls(lprops))
        g.Controls[b"IP Address"].String = ip.encode()
        self.layout_check(lprops)
        L.execute(src)  # now with Controls set -> runtime runs
        L.execute(b"collectgarbage() collectgarbage()")  # catch objects only held by locals
        self.g = g
        self.atem = FakeAtem(self)

    def make_props(self, values):
        L = self.lua
        lprops = L.table()
        for k, v in values.items():
            lprops[k.encode()] = L.table_from({b"Value": v.encode() if isinstance(v, str) else v})
        lprops[b"plugin_show_debug"] = L.table_from({b"Value": True})
        return lprops

    def layout_check(self, lprops):
        g, L = self.lua.globals(), self.lua
        pages = g.PageList(lprops)
        placed = set()
        for i in range(1, len(pages) + 1):
            lp = L.table()
            for k, v in lprops.items():
                lp[k] = v
            lp[b"page_index"] = L.table_from({b"Value": i})
            layout, graphics = g.GetControlLayout(lp)
            for name in layout.keys():
                assert g.Controls[name] is not None, f"layout references unknown control {name}"
                assert name not in placed, f"control placed twice: {name}"
                placed.add(name)
        missing = [self._s(k) for k in g.Controls.keys() if k not in placed]
        assert not missing, f"controls without a place in the layout: {missing[:10]}"

    @staticmethod
    def _s(x):
        return x.decode() if isinstance(x, bytes) else str(x)

    def ctl(self, name):
        c = self.g.Controls[name.encode()]
        assert c is not None, f"no control {name}"
        return c

    def s(self, name):
        return self._s(self.ctl(name).String)

    def b(self, name):
        return bool(self.ctl(name).Boolean)

    def status(self):
        return self.ctl("Status").Value, self.s("Status")

    def sock(self):
        return self.g.AtemRuntime.Udp

    def tick(self, n=1):
        for _ in range(n):
            self.g.TickAll()

    def user(self, name, field="press", value=None):
        self.g.UserSet(name.encode(), field.encode(), value)

    def connect(self, **dump):
        a = self.atem
        hello = a.take()
        assert hello[0]["flags"] == F_HELLO and len(hello[0]["raw"]) == 20, hello
        a.hello_reply()
        acks = a.take(acks=True)
        assert acks and acks[0]["flags"] == F_ACK and acks[0]["ack"] == 0, acks
        n = a.dump(**dump)
        self.tick()
        return n


def check(cond, msg):
    if not cond:
        raise AssertionError(msg)
    print("  ok  " + msg)


# ---------------------------------------------------------------------- tests
def test_connect():
    print("test_connect")
    h = Harness()
    check(h.status()[0] == 5, "status Initializing while connecting")
    sent = h.atem.take()
    check(sent[0]["raw"] == bytes.fromhex("101453ab00000000003a00000100000000000000"), "hello packet matches the original client")
    h.atem.sent.clear()
    h.atem.hello_reply()
    h.atem.take()
    check(h.status()[0] == 5 and h.b("Connected"), "connected, waiting for state")
    n = h.atem.dump(shuffle=True, duplicate=True)
    h.tick()
    check(n > 5, f"state dump in {n} packets (shuffled, duplicated)")
    check(h.status() == (0, "OK"), f"status OK after InCm: {h.status()}")
    check(h.s("Device") == "ATEM Mini Extreme" and h.s("Protocol Version") == "2.32", "device + protocol shown")
    check(h.b("ME1 Program Input 1") and not h.b("ME1 Program Input 2"), "program button feedback")
    check(h.b("ME1 Preview Input 2"), "preview button feedback")
    check(h.s("ME1 Program") == "Camera 1" and h.s("ME1 Preview") == "Camera 2", "combo shows device names")
    choices = [h._s(x) for x in h.ctl("ME1 Program").Choices.values()]
    check("Media Player 1 Key" in choices and "Program" not in choices, f"combo choices from switcher ({len(choices)})")
    check(h.s("Name Input 3") == "Camera 3", "source name output")
    check(h.s("ME1 Transition Rate") == "1:00" and h.s("ME1 Fade to Black Rate") == "1:05", "rates as s:ff (25 fps)")
    order = [h._s(x) for x in h.ctl("ME1 Program").Choices.values()]
    check(order[:9] == [f"Camera {i}" for i in range(1, 9)] + ["Black"], "inputs first, then Black (like Software Control)")
    check(h.b("ME1 Style Mix") and h.s("ME1 Transition Style") == "Mix", "style feedback")
    check(h.b("ME1 Next Background") and not h.b("ME1 Next Key 1"), "next transition feedback")
    acks = [p for p in h.atem.take(acks=True) if p["flags"] & F_ACK]
    check(acks and acks[-1]["ack"] == n, "all state packets acknowledged")
    check(not any("rror" in l for l in h.printed), "no errors printed")
    return h


def test_commands():
    print("test_commands")
    h = Harness({"Debug Print": "Basic"})
    h.connect()
    a = h.atem
    a.take()
    h.user("ME1 Program Input 4")
    check(not h.b("ME1 Program Input 4") and h.b("ME1 Program Input 1"), "toggle shows switcher state until feedback")
    pk = a.take()
    check(len(pk) == 1 and pk[0]["cmds"] == [("CPgI", bytes([0, 0, 0, 4]))], "CPgI sent")
    check(pk[0]["session"] == FakeAtem.SESSION and pk[0]["pid"] == 1, "session id + packet id 1")
    a.handle(pk)
    h.tick()
    check(h.b("ME1 Program Input 4") and not h.b("ME1 Program Input 1"), "program feedback applied")
    h.user("ME1 Preview", "String", b"Color Bars")
    pk = a.take()
    check(pk[0]["cmds"] == [("CPvI", bytes([0, 0]) + struct.pack(">H", 1000))] and pk[0]["pid"] == 2, "combo -> CPvI bars")
    a.handle(pk)
    h.tick()
    check(h.b("ME1 Preview Bars"), "preview bars lit")
    h.user("ME1 Cut")
    h.user("ME1 Auto")
    h.user("ME1 Fade to Black")
    names = [c[0] for p in a.take() for c in p["cmds"]]
    check(names == ["DCut", "DAut", "FtbA"], f"cut/auto/ftb: {names}")
    h.user("ME1 Style DVE")
    pk = a.take()
    check(pk[0]["cmds"] == [("CTTp", bytes([1, 0, 3, 0]))], "style DVE")
    a.handle(pk)
    h.tick()
    check(h.b("ME1 Style DVE") and not h.b("ME1 Style Mix"), "style feedback DVE")
    h.user("ME1 Next Key 2")
    pk = a.take()
    check(pk[0]["cmds"] == [("CTTp", bytes([2, 0, 0, 1 | 4]))], "next: background + key 2")
    a.handle(pk)
    h.tick()
    h.user("ME1 Next Background")
    pk = a.take()
    check(pk[0]["cmds"] == [("CTTp", bytes([2, 0, 0, 4]))], "background off, key 2 stays")
    a.handle(pk)
    h.tick()
    h.user("ME1 Next Key 2")
    check([c for p in a.take() for c in p["cmds"]] == [], "last next-transition element cannot be deselected")
    h.user("ME1 Transition Rate", "String", b"2:00")
    pk = a.take()
    check(pk[0]["cmds"] == [("CTDv", struct.pack(">H", 1) + bytes([0, 50]) + bytes(16))], "DVE rate 2:00 = 50 frames")
    h.user("ME1 Fade to Black Rate", "String", b"40")
    pk = a.take()
    check(pk[0]["cmds"] == [("FtbC", bytes([1, 0, 40, 0]))], "plain number = frames")
    h.user("ME1 Fade to Black Rate", "String", b"abc")
    check(a.take() == [] and h.s("ME1 Fade to Black Rate") == "1:05", "invalid rate ignored, shows switcher value")
    h.user("ME1 Key 3 On Air")
    pk = a.take()
    check(pk[0]["cmds"] == [("CKOn", bytes([0, 2, 1, 0]))], "key 3 on air")
    for v in (0.1, 0.3, 0.6):
        h.user("ME1 T-Bar", "Position", v)
    pk = a.take()
    last = pk[-1]["cmds"][-1]
    check(last == ("CTPs", bytes([0, 0]) + struct.pack(">H", 6000)), "T-bar position 6000")
    check(any("M/E 1 Cut" in l for l in h.printed), "basic log of user actions")
    return h


def test_block2():
    print("test_block2 (DSK, keyer sources, aux, SuperSource)")
    h0 = Harness()
    pages = [h0._s(x) for x in h0.g.PageList(h0.g.Properties).values()]
    check(pages == ["M/E 1", "Aux", "Media", "Macros", "Setup", "About"], f"default pages: {pages}")
    check(h0.g.Controls[b"ME1 Key 1 Fill"] is None and h0.g.Controls[b"SS1 Box 1 Enable"] is None,
          "keyer / SuperSource setup off by default")
    h = Harness({"Keyer Setup Page": True, "SuperSource Page": True})
    h.connect()
    a = h.atem
    a.take()
    check(h.s("ME1 Key 1 Fill") == "Media Player 1" and h.s("ME1 Key 1 Type") == "Luma", "USK sources + type")
    check(h.s("DSK 1 Fill") == "Media Player 1" and h.s("DSK 2 Rate") == "1:00", "DSK sources + rate")
    check(h.b("Aux 1 ME1 PGM") and h.s("Aux 2") == "Program", "aux feedback")
    check(h.s("Name ME1 PGM") == "Program" and h.s("Name Clean Feed 1") == "Clean Feed 1", "aux-only names on the aux page")
    aux_choices = [h._s(x) for x in h.ctl("Aux 1").Choices.values()]
    check("Clean Feed 1" in aux_choices and "Preview" in aux_choices, f"aux combo lists aux sources ({len(aux_choices)})")
    check(h.b("SS1 Box 1 Enable") and h.b("SS1 Box 1 Input 1") and h.b("SS1 Box 2 Input 2"), "SuperSource feedback")
    check(h.s("SS1 Box 3 Source") == "Camera 3", "box combo")

    h.user("Aux 2 Input 5")
    pk = a.take()
    check(pk[0]["cmds"] == [("CAuS", bytes([1, 1, 0, 5]))], "aux 2 -> input 5")
    a.handle(pk)
    h.tick()
    check(h.b("Aux 2 Input 5") and not h.b("Aux 2 ME1 PGM"), "aux button feedback")
    h.user("Aux 3", "String", b"Clean Feed 1")
    pk = a.take()
    check(pk[0]["cmds"] == [("CAuS", bytes([1, 2]) + struct.pack(">H", 7001))], "aux combo -> clean feed")

    h.user("DSK 1 On Air")
    pk = a.take()
    check(pk[0]["cmds"] == [("CDsL", bytes([0, 1, 0, 0]))], "DSK 1 on air")
    a.handle(pk)
    h.tick()
    check(h.b("DSK 1 On Air"), "DSK feedback")
    h.user("DSK 2 Auto")
    h.user("DSK 2 Tie")
    h.user("DSK 2 Rate", "String", b"0:12")
    names = [c for p in a.take() for c in p["cmds"]]
    check(names == [("DDsA", bytes([0, 1, 0, 0])), ("CDsT", bytes([1, 1, 0, 0])), ("CDsR", bytes([1, 12, 0, 0]))],
          f"DSK auto (v8 format), tie, rate: {names}")
    h.user("DSK 1 Key", "String", b"Camera 2")
    pk = a.take()
    check(pk[0]["cmds"] == [("CDsC", bytes([0, 0, 0, 2]))], "DSK key source")
    h.user("ME1 Key 2 Fill", "String", b"Color Bars")
    pk = a.take()
    check(pk[0]["cmds"] == [("CKeF", bytes([0, 1]) + struct.pack(">H", 1000))], "USK fill source")
    h.user("ME1 Key 3 Type", "String", b"Chroma")
    pk = a.take()
    check(pk[0]["cmds"] == [("CKTp", bytes([1, 0, 2, 1, 0, 0, 0, 0]))], "USK type chroma")

    h.user("SS1 Box 2 Enable")
    pk = a.take()
    check(pk[0]["cmds"] == [("CSBP", struct.pack(">H", 1) + bytes([0, 1, 1, 0]) + bytes(18))], "box 2 enable")
    a.handle(pk)
    h.user("SS1 Box 4 Bars")
    pk = a.take()
    check(pk[0]["cmds"] == [("CSBP", struct.pack(">H", 2) + bytes([0, 3, 0, 0]) + struct.pack(">H", 1000) + bytes(16))],
          "box 4 source bars")
    a.handle(pk)
    h.tick()
    check(h.b("SS1 Box 2 Enable") and h.b("SS1 Box 4 Bars"), "box feedback")
    return h


def test_block3():
    print("test_block3 (media, colour generators, macros)")
    h = Harness()
    h.connect()
    a = h.atem
    a.take()
    check(h.b("MP1 Still 1") and h.b("MP2 Still 2") and not h.b("MP1 Still 2"), "media player still feedback")
    check(h.s("Still 2 Name") == "still2.png" and h.s("Still 5 Name") == "", "still names")
    check(h.s("MP1 Source") == "Still 1: still1.png", "media combo")
    check(h.ctl("Color 1 Hue").Value == 120 and h.ctl("Color 1 Saturation").Value == 50, "colour feedback")
    check(h.s("Macro 1 Name") == "Intro" and h.s("Macro 5 Name") == "Outro", "macro names")
    choices = [h._s(x) for x in h.ctl("Macro").Choices.values()]
    check(choices == ["1: Intro", "5: Outro"], f"macro combo lists used macros: {choices}")

    h.user("MP2 Still 3")
    pk = a.take()
    check(pk[0]["cmds"] == [("MPSS", bytes([3, 1, 1, 2, 0, 0, 0, 0]))], "MP2 -> still 3")
    a.handle(pk)
    h.tick()
    check(h.b("MP2 Still 3") and h.s("MP2 Source") == "Still 3: still3.png", "still feedback")
    h.user("MP1 Source", "String", b"Still 2: still2.png")
    pk = a.take()
    check(pk[0]["cmds"] == [("MPSS", bytes([3, 0, 1, 1, 0, 0, 0, 0]))], "combo -> still 2")
    a.handle(pk)

    h.user("Macro 5")
    pk = a.take()
    check(pk[0]["cmds"] == [("MAct", bytes([0, 4, 0, 0]))], "run macro 5")
    a.handle(pk)
    h.tick()
    check(h.b("Macro 5") and h.b("Macro Running") and h.s("Macro Running Name") == "5: Outro", "macro running")
    check(h.g.Controls[b"Macro Continue"] is None, "no continue (not supported yet)")
    h.user("Macro 5")
    pk = a.take()
    check(pk[0]["cmds"] == [("MAct", bytes([0xFF, 0xFF, 1, 0]))], "pressing the running macro stops it")
    a.handle(pk)
    h.tick()
    check(not h.b("Macro 5") and not h.b("Macro Running"), "macro stopped")
    h.user("Macro", "String", b"1: Intro")
    h.user("Macro Run")
    pk = a.take()
    check(pk[0]["cmds"] == [("MAct", bytes([0, 0, 0, 0]))], "combo + run")
    a.handle(pk)

    for v in (10, 20, 30):
        h.user("Color 2 Luma", "Value", v)
    pk = a.take()
    check(pk[-1]["cmds"][-1] == ("CClV", bytes([4, 1, 0, 0, 0, 0]) + struct.pack(">H", 300)), "colour 2 luma 30 %")
    a.handle(pk)
    h.tick(2)
    check(h.ctl("Color 2 Luma").Value == 30, "no jump while dragging")
    h.tick(40)
    check(h.ctl("Color 2 Luma").Value == 30 and h.ctl("Color 2 Hue").Value == 120, "feedback after hold")


def test_tbar():
    print("test_tbar")
    h = Harness()
    h.connect()
    a = h.atem

    def trps(inside, handle):
        a.feed(a.packet([cmd("TrPs", bytes([0, 1 if inside else 0, 10, 0]) + struct.pack(">H", handle) + b"\0\0")]))
        h.tick(30)   # past the T-bar hold time

    for v in (2000, 6000, 9600):
        trps(True, v)
    check(abs(h.ctl("ME1 T-Bar").Position - 0.96) < 0.01, "auto: fader follows up")
    trps(False, 0)
    check(h.ctl("ME1 T-Bar").Position == 1, "after auto the fader stays at the top")
    trps(True, 3000)
    check(abs(h.ctl("ME1 T-Bar").Position - 0.7) < 0.01, "next transition moves the fader down")
    trps(True, 9800)
    trps(False, 0)
    check(h.ctl("ME1 T-Bar").Position == 0, "and it stays at the bottom")
    a.take()
    h.user("ME1 T-Bar", "Position", 0.25)
    pk = a.take()
    a.handle(pk)
    last = pk[-1]["cmds"][-1]
    check(last == ("CTPs", bytes([0, 0]) + struct.pack(">H", 2500)), "from the bottom: position = progress")
    trps(True, 2500)
    trps(True, 9900)
    trps(False, 0)
    h.user("ME1 T-Bar", "Position", 0.75)
    pk = a.take()
    a.handle(pk)
    last = pk[-1]["cmds"][-1]
    check(last == ("CTPs", bytes([0, 0]) + struct.pack(">H", 2500)), "from the top: moving down = progress")
    trps(True, 1000)
    trps(False, 0)   # pulled back -> no flip
    check(h.ctl("ME1 T-Bar").Position == 1, f"aborted transition does not flip ({h.ctl('ME1 T-Bar').Position})")


def test_resend():
    print("test_resend")
    h = Harness()
    h.connect()
    a = h.atem
    a.take()
    h.user("ME1 Program Input 5")
    first = a.take()
    h.tick(3)
    check(a.take() == [], "no resend before timeout")
    h.tick(3)
    again = a.take()
    check(again and again[0]["raw"] == first[0]["raw"], "unacknowledged packet resent")
    a.ack(again[0]["pid"])
    h.tick(20)
    check(not [p for p in a.take() if p["flags"] & F_ACKREQ], "nothing resent after ack")
    # switcher asks for a resend of an in-flight packet
    h.user("ME1 Program Input 6")
    p6 = a.take()[0]
    a.feed(header(F_RETXREQ, 12, a.SESSION, retx=p6["pid"]))
    again = a.take()
    check(again and again[0]["raw"] == p6["raw"], "resend on switcher request")
    a.ack(p6["pid"])
    # a packet the switcher sends twice is acked again but applied once
    raw = a.packet([cmd("PrgI", bytes([0, 0, 0, 7]))])
    a.feed(raw)
    a.feed(raw)
    acks = [p for p in a.take(acks=True) if p["flags"] & F_ACK]
    check(len(acks) == 2 and acks[-1]["ack"] == a.next_id - 1, "duplicate re-acknowledged")
    h.tick()
    check(h.b("ME1 Program Input 7"), "duplicate applied once")
    # never acked -> connection restarts
    h.user("ME1 Program Input 8")
    ticks = 0
    while h.status()[0] != 4 and ticks < 200:
        h.tick()
        a.feed(a.packet([]))   # switcher still alive
        ticks += 1
    check(0.8 < ticks * TICK < 1.5, f"gave up after {ticks * TICK:.2f} s")
    check(h.status()[0] == 4 and "retry" in h.status()[1], f"gave up after max resends: {h.status()}")
    return h


def test_timeout_and_reconnect():
    print("test_timeout_and_reconnect")
    h = Harness()
    h.connect()
    a = h.atem
    a.take()
    h.tick(int(4 / TICK))
    check(h.status()[0] == 0, "still OK after 4 s silence")
    h.tick(int(1.5 / TICK))
    check(h.status()[0] == 4 and not h.b("ME1 Program Input 1"), f"lost after 5 s silence: {h.status()}")
    check(not h.b("Connected"), "connected LED off")
    a.take()
    h.tick(int(1.2 / TICK))
    hello = a.take()
    check(hello and hello[0]["flags"] == F_HELLO, "reconnect with hello after backoff")
    check(h.s("Reconnects") == "1", "reconnect counter")
    a.next_id = 1
    a.hello_reply()
    a.take()
    a.dump()
    h.tick()
    check(h.status() == (0, "OK"), "OK again after reconnect")
    return h


def test_no_device():
    print("test_no_device (emulation without switcher)")
    h = Harness()
    for _ in range(int(20 / TICK)):
        h.tick()
    v, txt = h.status()
    check(v == 4 and txt.startswith("No answer from switcher - retry in"), f"status Missing: {txt}")
    first = txt
    h.tick(int(1.0 / TICK))
    check(h.status()[1] != first or "retry in 1s" in first, f"countdown: {first} -> {h.status()[1]}")
    hellos = [p for p in h.atem.take() if p["flags"] == F_HELLO]
    check(10 <= len(hellos) <= 25, f"hello retried with backoff ({len(hellos)} in 20 s)")
    h.user("ME1 Cut")
    check(not [p for p in h.atem.take() if p["flags"] & F_ACKREQ], "commands dropped while not connected")
    h.ctl("IP Address").String = b""
    h.user("IP Address", "String", b"")
    check(h.status() == (4, "No IP address set"), "empty IP")
    h.user("IP Address", "String", b"10.0.0.300")
    check(h.status()[0] == 2, "invalid IP -> Fault")
    return h


def test_wrong_model():
    print("test_wrong_model")
    h = Harness()
    h.atem.model_id, h.atem.product = 3, "ATEM 2 M/E Production Switcher"
    h.connect()
    v, txt = h.status()
    check(v == 1 and "2 M/E Production" in txt, f"Compromised on model mismatch: {txt}")
    return h


def test_legends():
    print("test_legends")
    h = Harness({"Button Legends": "Device Names"})
    h.connect()
    check(h._s(h.ctl("ME1 Program Input 2").Legend) == "CAM2", "device short name as legend")
    h2 = Harness()
    h2.connect()
    check(h2._s(h2.ctl("ME1 Program Input 2").Legend) == "", "default: legends untouched")


def test_two_me():
    print("test_two_me")
    h = Harness({"Model": "ATEM 2 M/E Constellation HD"})
    h.atem = FakeAtem(h, model_id=19, product="ATEM 2 M/E Constellation HD", mes=2, keys=4)
    h.connect()
    check(h.status()[0] == 0, f"2 M/E OK: {h.status()}")
    h.user("ME2 Program Input 3")
    pk = h.atem.take()
    check(pk[-1]["cmds"] == [("CPgI", bytes([1, 0, 0, 3]))], "M/E 2 program")


def test_all_models():
    print("test_all_models")
    h = Harness()
    names = [h._s(x) for x in h.g.AtemTopology.ModelNames().values()]
    worst = (0, "")
    for name in names:
        for mode in ("All Sources", "Inputs Only", "None"):
            props = dict(h.props, Model=name)
            props["Source Buttons"] = mode
            if name == "Custom":
                props.update({"Custom M/Es": 4, "Custom Inputs": 40, "Custom Aux Outputs": 24})
            lp = h.make_props(props)
            h.g.RectifyProperties(lp)
            ctrls = h.g.GetControls(lp)
            h.g.MakeControls(ctrls)
            h.layout_check(lp)
            if len(ctrls) > worst[0]:
                worst = (len(ctrls), f"{name} / {mode}")
    check(True, f"{len(names)} models x 3 button modes: controls + layouts build; largest {worst[1]} with {worst[0]} controls")


def main():
    random.seed(1)
    test_connect()
    test_commands()
    test_block2()
    test_tbar()
    test_block3()
    test_resend()
    test_timeout_and_reconnect()
    test_no_device()
    test_wrong_model()
    test_legends()
    test_two_me()
    test_all_models()
    print("all tests passed")


if __name__ == "__main__":
    main()
