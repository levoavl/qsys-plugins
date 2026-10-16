#!/usr/bin/env python3
"""
Offline test harness for the grandMA2 plugin (no Q-SYS needed).

Runs the built .qplug in Lua 5.3 (lupa) with mocks for Controls, Properties,
TcpSocket, Timer, Crypto and rapidjson, plays a fake MA2 web remote and checks
the plugin's behaviour. Optionally replays a debug log captured with the
Locimation "MA2 Remote" plugin (Verbose Debug) to check the state derivation
against real console data.

    pip install lupa
    python3 source/tools/build.py grandma2
    python3 source/plugins/grandma2/test/harness.py [log.txt ...]

(c) levo AVL | Elias Jenny - MIT License
"""

import base64
import hashlib
import json
import random
import sys
from pathlib import Path

from lupa.lua53 import LuaRuntime

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "tools"))
from build import output_path  # noqa: E402

QPLUG = output_path("grandma2")

MOCKS = r"""
local py = ...
-- ---------------------------------------------------------------- controls
local function NewControl(def)
  local c = { _def = def, Value = def.Min or 0, String = "", Boolean = false, Legend = "", EventHandler = nil }
  local mt = {}
  local raw = { Value = 0, Position = 0, String = "", Boolean = false }
  local min, max = def.Min or 0, def.Max or 1
  if def.ControlType == "Knob" or def.IndicatorType == "Meter" then
    if max == min then max = min + 1 end
  else
    min, max = 0, 1
  end
  local function setValue(v)
    raw.Value = v
    raw.Position = (max > min) and (v - min) / (max - min) or 0
    raw.Boolean = v ~= 0
    if def.ControlType == "Knob" or def.ControlType == "Button" or def.IndicatorType == "Led" or def.IndicatorType == "Status" then
      if def.ControlUnit == "Integer" then raw.String = tostring(math.floor(v)) end
    end
  end
  setValue(min)
  local obj = setmetatable({ _def = def, Legend = "", EventHandler = false }, {
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
  return obj
end

function MakeControls(defs)
  Controls = {}
  for _, d in ipairs(defs) do Controls[d.Name] = NewControl(d) end
end

-- user action: set and fire the handler like Q-SYS does for UI changes
function UserSet(name, field, value)
  local c = Controls[name]
  assert(c, "no control " .. name)
  c[field] = value
  if c.EventHandler then c.EventHandler(c) end
end

-- ---------------------------------------------------------------- timer
-- weak like the real Core: a timer nobody references gets garbage collected
Timers = setmetatable({}, { __mode = "v" })
Timer = { New = function()
  local t = { running = false }
  -- no strong reference here, like on the Core
  function t:Start(iv) self.interval = iv; self.running = true end
  function t:Stop() self.running = false end
  Timers[#Timers + 1] = t
  return t
end, CallAfter = function(fn, d) error("CallAfter not mocked") end }

function TickAll()
  for _, t in pairs(Timers) do
    if t.running and t.EventHandler then t.EventHandler(t) end
  end
end

-- ---------------------------------------------------------------- sockets
Sockets = {}
TcpSocket = { Events = { Connected = "CONNECTED", Reconnect = "RECONNECT", Data = "DATA",
  Closed = "CLOSED", Error = "ERROR", Timeout = "TIMEOUT" } }
function TcpSocket.New()
  local s = { rx = "", tx = {}, connected = false, BufferLength = 0 }
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

-- ---------------------------------------------------------------- crypto / json
Crypto = {
  MD5Compute = function(s) return py.md5(s) end,
  Base64Encode = function(s) return py.b64(s) end,
}
local function ToPy(v)
  return v
end
package.preload["rapidjson"] = function()
  return { encode = function(t) return py.encode(t) end, decode = function(s) return py.decode(s) end }
end
"""


class Harness:
    def __init__(self, props=None, ip="10.0.0.1"):
        self.lua = LuaRuntime(unpack_returned_tuples=True, encoding=None)
        L = self.lua
        helpers = L.table_from({
            b"md5": lambda s: hashlib.md5(bytes(s)).hexdigest().encode(),
            b"b64": lambda s: base64.b64encode(bytes(s)),
            b"encode": self._encode,
            b"decode": self._decode,
        })
        L.execute(MOCKS.encode(), helpers)
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
        lprops = L.table()
        for k, v in self.props.items():
            lprops[k.encode()] = L.table_from({b"Value": v.encode() if isinstance(v, str) else v})
        lprops[b"plugin_show_debug"] = L.table_from({b"Value": True})
        self.lprops = lprops
        g.Properties = lprops
        g.MakeControls(g.GetControls(lprops))
        g.Controls[b"IP Address"].String = ip.encode()
        g.Controls[b"Password"].String = b"secret"
        # layouts must build for every page
        pages = g.PageList(lprops)
        for i in range(1, len(pages) + 1):
            lp = L.table()
            for k, v in lprops.items():
                lp[k] = v
            lp[b"page_index"] = L.table_from({b"Value": i})
            layout, graphics = g.GetControlLayout(lp)
            for name in layout.keys():
                assert g.Controls[name] is not None, f"layout references unknown control {name}"
        L.execute(src)  # now with Controls set -> runtime runs
        L.execute(b"collectgarbage() collectgarbage()")  # catch objects only held by locals
        self.g = g

    # ---------------------------------------------------------------- utils
    @staticmethod
    def _s(x):
        return x.decode() if isinstance(x, bytes) else str(x)

    def _to_py(self, v):
        if self.lua.eval("type")(v) != b"table":
            return self._s(v) if isinstance(v, bytes) else v
        keys = list(v.keys())
        if keys and all(isinstance(k, int) for k in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
            return [self._to_py(v[k]) for k in sorted(keys)]
        return {self._s(k): self._to_py(v[k]) for k in keys}

    def _to_lua(self, o):
        if isinstance(o, dict):
            t = self.lua.table()
            for k, v in o.items():
                if v is not None:
                    t[k.encode()] = self._to_lua(v)
            return t
        if isinstance(o, list):
            t = self.lua.table()
            for i, v in enumerate(o, 1):
                t[i] = self._to_lua(v)
            return t
        if isinstance(o, str):
            return o.encode()
        return o

    def _encode(self, t):
        return json.dumps(self._to_py(t)).encode()

    def _decode(self, s):
        return self._to_lua(json.loads(bytes(s).decode()))

    def ctl(self, name):
        return self.g.Controls[name.encode()]

    def s(self, name):
        return self._s(self.ctl(name).String)

    def b(self, name):
        return bool(self.ctl(name).Boolean)

    def sock(self):
        return self.g.Sockets[len(self.g.Sockets)]

    def tick(self, n=1):
        for _ in range(n):
            self.g.TickAll()

    def user(self, name, field, value):
        self.g.UserSet(name.encode(), field.encode(), value)

    # ---------------------------------------------------------------- fake console
    @staticmethod
    def frame(text):
        data = text.encode()
        n = len(data)
        if n <= 125:
            head = bytes([0x81, n])
        elif n <= 0xFFFF:
            head = bytes([0x81, 126]) + n.to_bytes(2, "big")
        else:
            head = bytes([0x81, 127]) + n.to_bytes(8, "big")
        return head + data

    @staticmethod
    def unmask(raw):
        """Decode client frames (masked) into text payloads."""
        out, pos = [], 0
        while pos < len(raw):
            b1, b2 = raw[pos], raw[pos + 1]
            assert b2 & 0x80, "client frame not masked"
            n, hdr = b2 & 0x7F, 2
            if n == 126:
                n, hdr = int.from_bytes(raw[pos + 2:pos + 4], "big"), 4
            elif n == 127:
                n, hdr = int.from_bytes(raw[pos + 2:pos + 10], "big"), 10
            key = raw[pos + hdr:pos + hdr + 4]
            payload = bytes(c ^ key[i % 4] for i, c in enumerate(raw[pos + hdr + 4:pos + hdr + 4 + n]))
            out.append((b1 & 0x0F, payload.decode()))
            pos += hdr + 4 + n
        return out

    def take_tx(self, s=None):
        s = s or self.sock()
        raw = b"".join(bytes(s.tx[i]) for i in range(1, len(s.tx) + 1))
        for i in range(len(s.tx), 0, -1):
            del s.tx[i]
        return raw

    def take_msgs(self, s=None):
        return [json.loads(p) for op, p in self.unmask(self.take_tx(s)) if op == 1]

    def feed(self, data, chunked=True):
        s = self.sock()
        if not chunked:
            self.g.ServerFeed(s, data)
            return
        pos = 0
        while pos < len(data):  # random TCP fragmentation
            n = random.randint(1, 700)
            self.g.ServerFeed(s, data[pos:pos + n])
            pos += n

    def send_json(self, obj):
        self.feed(self.frame(json.dumps(obj) if not isinstance(obj, str) else obj))

    def handshake_and_login(self):
        s = self.sock()
        assert self._s(s.host) == "10.0.0.1" and s.port == 80
        self.g.ServerEvent(s, b"CONNECTED")
        req = self.take_tx(s).decode()
        assert req.startswith("GET /?ma=1 HTTP/1.1\r\n") and "Upgrade: websocket" in req, req
        self.feed(b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n"
                  + self.frame('{"status":"server ready","appType":"gma2"}'))
        assert self.take_msgs() == [{"session": 0}]
        self.send_json({"realtime": False, "session": 2, "forceLogin": True, "worldIndex": 0})
        login = self.take_msgs()
        assert login[0]["requestType"] == "login" and login[0]["password"] == hashlib.md5(b"secret").hexdigest(), login
        self.send_json({"realtime": False, "responseType": "login", "result": True, "worldIndex": 0})
        assert self.b("Logged In"), self.s("Status")


def check(cond, msg):
    if not cond:
        raise AssertionError(msg)
    print("  ok  " + msg)


def test_basics():
    print("test_basics")
    h = Harness()
    check(h.ctl("Status").Value == 5, "status Initializing while connecting")
    h.handshake_and_login()
    check(h.ctl("Status").Value == 0, "status OK after login")
    h.tick()
    polls = h.take_msgs()
    check(any(p.get("requestType") == "playbacks" and p["itemsType"] == [2] for p in polls), "fader poll sent")
    check(sum(1 for p in polls if p.get("requestType") == "playbacks") == 1, "only one poll in flight")
    # answer -> next poll goes out immediately
    h.send_json({"responseType": "playbacks", "iPage": 1, "itemGroups": [{"itemsType": 2, "items": []}]})
    polls = h.take_msgs()
    check(polls and polls[0]["itemsType"] == [3] and polls[0]["startIndex"] == [100], "button poll follows")

    # fader moves coalesce
    for v in (0.1, 0.2, 0.3, 0.5):
        h.user("Fader 1 Level", "Position", v)
    h.send_json({"responseType": "playbacks", "iPage": 1, "itemGroups": []})
    h.take_msgs()
    h.tick()
    msgs = [m for m in h.take_msgs() if m.get("requestType") == "playbacks_userInput"]
    check(len(msgs) == 1 and abs(msgs[0]["faderValue"] - 0.5) < 1e-6 and msgs[0]["execIndex"] == 0, "fader moves coalesced to last value")

    # macro + command
    h.user("Macro 3 Trigger", "Boolean", True)
    h.user("Command TX", "String", b"Go Executor 1.5")
    h.tick()
    cmds = [m["command"] for m in h.take_msgs() if m.get("requestType") == "command"]
    check(cmds == ["Go Macro 3", "Go Executor 1.5"], "macro and command sent")
    check(h.s("Command TX") == "", "Command TX cleared")

    # watchdog: no responses for > 3 s -> reconnect with backoff
    for _ in range(70):
        h.tick()
    check(h.ctl("Status").Value == 4 and not h.b("Logged In"), "timeout -> Missing")
    n = len(h.g.Sockets)
    for _ in range(30):
        h.tick()
    check(len(h.g.Sockets) == n + 1, "reconnect after backoff")

    # socket closed by peer
    h.handshake_and_login()
    h.g.ServerEvent(h.sock(), b"CLOSED")
    check(h.ctl("Status").Value == 4, "closed -> Missing, retry scheduled")
    check(h.s("Fader 1 State") == "Offline", "slots offline after disconnect")

    # wrong password
    for _ in range(50):
        h.tick()
    s = h.sock()
    h.g.ServerEvent(s, b"CONNECTED")
    h.take_tx(s)
    h.feed(b"HTTP/1.1 101 Switching Protocols\r\n\r\n" + h.frame('{"status":"server ready","appType":"gma2"}'))
    h.take_msgs()
    h.send_json({"session": 3, "forceLogin": True})
    h.take_msgs()
    h.send_json({"responseType": "login", "result": False})
    check(h.ctl("Status").Value == 2 and "Login failed" in h.s("Status"), "login failure -> Fault")

    # no IP -> Missing without error
    h2 = Harness(ip="")
    check(h2.ctl("Status").Value == 4 and len(h2.g.Sockets) == 0, "no IP -> Missing, no socket (emulation safe)")


def test_exec_assignment():
    print("test_exec_assignment")
    h = Harness()
    check(h.s("Fader 2 Exec") == "1.2" and h.s("Button 3 Exec") == "1.103", "default executor texts")
    h.handshake_and_login()
    h.user("Button 1 Exec", "String", b"2.105")
    h.user("Fader 1 Exec", "String", b"7")
    h.tick()
    polls = [m for m in h.take_msgs() if m.get("requestType") == "playbacks"]
    check(polls and polls[0]["pageIndex"] == 0, "polling restarts after reassignment")
    for _ in range(3):
        h.send_json({"responseType": "playbacks", "iPage": 1, "itemGroups": []})
        polls += [m for m in h.take_msgs() if m.get("requestType") == "playbacks"]
    check(any(p["pageIndex"] == 1 and p["startIndex"] == [100] and p["itemsType"] == [3] for p in polls),
          "2.105 polled on page 2")
    h.send_json({"responseType": "playbacks", "iPage": 2, "itemGroups": [{"itemsType": 3, "items": [[
        {"iExec": 104, "isRun": 1, "combinedItems": 1, "tt": {"t": "Page2"}, "oI": {"t": "9"},
         "cues": {"items": [{"t": "1", "pgs": {"v": 1.0}}]}, "bottomButtons": {"items": [{"n": {"t": "Go"}}]}}]]}]})
    check(h.s("Button 1 Name") == "Page2" and h.b("Button 1 Active"), "feedback mapped to 2.105")
    h.user("Button 1 Press", "Boolean", True)
    h.tick()
    ins = [m for m in h.take_msgs() if m.get("requestType") == "playbacks_userInput"]
    check(ins and ins[0]["pageIndex"] == 1 and ins[0]["execIndex"] == 104, "press goes to 2.105")
    h.user("Fader 2 Exec", "String", b"abc")
    check("invalid executor" in h.s("Last Error") and h.s("Fader 2 State") == "Offline", "invalid text reported")
    h.user("Fader 2 Exec", "String", b"1,2")
    check(h.s("Last Error") == "", "comma accepted (1,2 = 1.2)")


def test_main_button_feedback():
    print("test_main_button_feedback")
    h = Harness()
    h.handshake_and_login()
    item = lambda run: {"responseType": "playbacks", "iPage": 1, "itemGroups": [{"itemsType": 3, "items": [[
        {"iExec": 100, "isRun": run, "combinedItems": 1, "tt": {"t": "A"}, "oI": {"t": "5"},
         "cues": {"items": [{"t": "1", "pgs": {"v": 1.0}}]}, "bottomButtons": {"items": [{"n": {"t": "Toggle"}}]}}]]}]}
    h.send_json(item(1))
    check(h.b("Button 1 Press"), "main button is on while executor runs")
    check(h.ctl("Button 1 Press").Color is None, "plugin never writes Color (UCI styling stays)")
    h.take_msgs()
    # already on -> Q-SYS reports only the release: must be sent as press + release
    h.user("Button 1 Press", "Boolean", False)
    h.tick()
    ins = [(m["pressed"], m["released"]) for m in h.take_msgs() if m.get("requestType") == "playbacks_userInput"]
    check(ins == [(True, False), (False, True)], "release without press is sent as a tap")
    check(not h.b("Button 1 Press"), "optimistic: button off right after toggling off")
    # held button keeps its pressed look while polls report 'off'
    h.send_json(item(0))
    h.user("Button 1 Press", "Boolean", True)
    h.send_json(item(0))
    check(h.b("Button 1 Press"), "held button not overwritten by feedback")
    h.user("Button 1 Press", "Boolean", False)
    check(h.b("Button 1 Press"), "after release: shows predicted state (toggle on)")
    check(h._s(h.ctl("Button 1 Press").Legend) == "", "default: main button legend not written (free for UCI)")
    h2 = Harness({"Button Legends": "All"})
    h2.handshake_and_login()
    h2.send_json(item(1))
    check(h2._s(h2.ctl("Button 1 Press").Legend) == "Toggle", "Button Legends = All writes main legends")


def test_large_and_fragmented():
    print("test_large_and_fragmented")
    h = Harness()
    h.handshake_and_login()
    big = {"responseType": "playbacks", "iPage": 1, "itemGroups": [{"itemsType": 2, "items": [[
        {"iExec": 0, "isRun": 1, "combinedItems": 1, "tt": {"t": "X" * 70000}, "oI": {"t": "1"},
         "cues": {"items": [{"t": " 1 Cue", "pgs": {"v": 1.0}}]},
         "executorBlocks": [{"button1": {"t": "Go"}, "button2": {"t": "On"}, "button3": {"t": "Off"},
                             "fader": {"v": 0.25, "tt": "Master"}}]}]]}]}
    text = json.dumps(big)
    # split into a fragmented WebSocket message (text + continuation frame)
    a, b = text[:1000].encode(), text[1000:].encode()
    f1 = bytes([0x01, 126]) + len(a).to_bytes(2, "big") + a
    f2 = bytes([0x80, 127]) + len(b).to_bytes(8, "big") + b
    h.feed(f1 + f2)
    check(len(h.s("Fader 1 Name")) == 70000, "64-bit length + fragmented message reassembled")
    check(abs(h.ctl("Fader 1 Level").Position - 0.25) < 1e-6, "fader level feedback")
    check(h.s("Fader 1 Function") == "Master", "fader function")
    check(h.s("Fader 1 Button 3 Label") == "Off", "button label")
    # ping -> pong
    h.take_tx()
    h.feed(bytes([0x89, 2]) + b"hi")
    out = h.unmask(h.take_tx())
    check(out == [(0xA, "hi")], "ping answered with pong")


def replay(path):
    """Replay a Locimation verbose log: feed every received playbacks response."""
    print(f"replay {path}")
    h = Harness()
    h.handshake_and_login()
    states = {}
    last_t = None
    for line in Path(path).read_text(encoding="utf-8", errors="replace").splitlines():
        try:
            ts, rest = line.split("\t", 1)
        except ValueError:
            continue
        hh, mm, ss = ts.split("T")[1].split(":")
        t = int(hh) * 3600 + int(mm) * 60 + float(ss)
        if last_t is not None:
            for _ in range(int((t - last_t) / 0.05)):
                h.tick()
        last_t = t
        h.take_tx()  # discard the plugin's own polls
        if rest.startswith("< "):
            msg = rest[2:]
            if '"responseType":"playbacks"' in msg:
                h.send_json(msg)
        elif rest.startswith("> ") and '"playbacks_userInput"' in rest and '"pressed":true' in rest:
            m = json.loads(rest[2:])
            exec_no = m["execIndex"] + 1
            if exec_no > 100:
                slot = exec_no - 100
                h.user(f"Button {slot} Press", "Boolean", True)
                print(f"  {ts[11:]}  press Button {slot} (exec {exec_no}) -> {h.s(f'Button {slot} State')} "
                      f"active={h.b(f'Button {slot} Active')}")
                h.user(f"Button {slot} Press", "Boolean", False)
            else:
                b = m["buttonId"] + 1
                h.user(f"Fader {exec_no} Button {b}", "Boolean", True)
                print(f"  {ts[11:]}  press Fader {exec_no} button {b} "
                      f"({h.s(f'Fader {exec_no} Button {b} Label')}) -> {h.s(f'Fader {exec_no} State')} "
                      f"active={h.b(f'Fader {exec_no} Active')}")
                h.user(f"Fader {exec_no} Button {b}", "Boolean", False)
        for kind, n in (("Fader", 8), ("Button", 16)):
            for i in range(1, n + 1):
                key = f"{kind} {i}"
                st = (h.s(key + " Name"), h.s(key + " State"), h.b(key + " Active"),
                      round(h.ctl(key + " Progress").Position * 100))
                if st[0] and states.get(key) != st[:3]:
                    print(f"  {ts[11:]}  {key:9} {st[0]!r:14} {st[1]:11} active={st[2]} progress={st[3]}%")
                    states[key] = st[:3]
    return h


if __name__ == "__main__":
    random.seed(1)
    test_basics()
    test_exec_assignment()
    test_main_button_feedback()
    test_large_and_fragmented()
    for p in sys.argv[1:]:
        replay(p)
    print("all tests passed")
