#!/usr/bin/env python3
"""
Offline test harness for the Advanced Color Picker plugin (no Q-SYS needed).

Runs the built .qplug in Lua 5.3 (lupa) with mocks for Controls, Properties and
Timer, builds every layout page and checks colour maths, outputs, fades, user
presets and the two-way console link.

    pip install lupa
    python3 source/tools/build.py advancedcolorpicker
    python3 source/plugins/advancedcolorpicker/test/harness.py

(c) levo AVL | Elias Jenny - MIT License
"""

import sys
from pathlib import Path

from lupa.lua53 import LuaRuntime

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "tools"))
from build import output_path  # noqa: E402

QPLUG = output_path("advancedcolorpicker")

MOCKS = r"""
-- Controls behave like Q-SYS: knobs clamp to their range, Integer knobs round,
-- script writes do NOT fire the control's own EventHandler.
local function NewControl(def)
  local raw = { Value = 0, Position = 0, String = "", Boolean = false }
  local isKnob = def.ControlType == "Knob"
  local min, max = 0, 1
  if isKnob then min, max = def.Min, def.Max end
  local function setValue(v)
    if v < min then v = min elseif v > max then v = max end
    if def.ControlUnit == "Integer" then v = math.floor(v + 0.5) end
    raw.Value = v
    raw.Position = (v - min) / (max - min)
    raw.Boolean = v ~= 0
    if isKnob then raw.String = tostring(v) end
  end
  setValue(min)
  return setmetatable({ _def = def, Color = "", Legend = "", EventHandler = false }, {
    __index = function(t, k)
      if raw[k] ~= nil then return raw[k] end
      return rawget(t, k)
    end,
    __newindex = function(t, k, v)
      if k == "Value" then setValue(v)
      elseif k == "Position" then setValue(min + v * (max - min))
      elseif k == "Boolean" then setValue(v and 1 or 0)
      elseif k == "String" then
        raw.String = v
        if isKnob then local n = tonumber(v); if n then setValue(n) end end
      else rawset(t, k, v) end
    end,
  })
end

function MakeControls(defs, preset)
  Controls = {}
  for _, d in ipairs(defs) do
    assert(Controls[d.Name] == nil, "duplicate control " .. d.Name)
    Controls[d.Name] = NewControl(d)
  end
  for k, v in pairs(preset or {}) do
    if type(v) == "string" then Controls[k].String = v else Controls[k].Value = v end
  end
end

-- UI / pin change: set and fire the handler
function UserSet(name, field, value)
  local c = Controls[name]
  assert(c, "no control " .. name)
  c[field] = value
  if c.EventHandler then c.EventHandler(c) end
end

-- weak like the real Core: a timer nobody references gets garbage collected
Timers = setmetatable({}, { __mode = "v" })
Timer = { New = function()
  local t = { running = false }
  function t:Start(iv) self.interval = iv; self.running = true end
  function t:Stop() self.running = false end
  Timers[#Timers + 1] = t
  return t
end }
function TickAll()
  for _, t in pairs(Timers) do
    if t.running and t.EventHandler then t.EventHandler(t) end
  end
end
"""


class Harness:
    def __init__(self, props=None, preset=None):
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
        g.Properties = lprops
        g.MakeControls(g.GetControls(lprops), L.table_from(preset or {}))
        # every page must build and only reference existing controls
        pages = g.GetPages(lprops)
        for i in range(1, len(pages) + 1):
            lp = L.table()
            for k, v in lprops.items():
                lp[k] = v
            lp["page_index"] = L.table_from({"Value": i})
            layout, graphics = g.GetControlLayout(lp)
            for name in layout.keys():
                assert g.Controls[name] is not None, f"layout references unknown control {name}"
                pos = layout[name].Position
                assert float(pos[1]).is_integer() and float(pos[2]).is_integer(), f"non-integer position {name}"
        assert "Advanced Color Picker" in g.PluginInfo.Name
        L.execute(src)  # with Controls set -> runtime runs
        L.execute("collectgarbage() collectgarbage()")  # catch objects only held by locals
        self.g = g

    def c(self, name):
        ctl = self.g.Controls[name]
        assert ctl is not None, f"no control {name}"
        return ctl

    def v(self, name):
        return self.c(name).Value

    def s(self, name):
        return self.c(name).String

    def user(self, name, field, value):
        self.g.UserSet(name, field, value)

    def press(self, name):
        self.user(name, "Boolean", True)

    def tick(self, n=1):
        for _ in range(n):
            self.g.TickAll()

    def levels(self, lay):
        return [self.v(f"{lay} {ch}") for ch in lay]


FAILED = []


def check(cond, msg):
    print(("  ok    " if cond else "  FAIL  ") + msg)
    if not cond:
        FAILED.append(msg)


def test_start_and_presets():
    print("start / presets / mixing")
    h = Harness()
    check(h.v("Status") == 0, "status OK after start")
    check(h.s("Hex") == "#FFFFFF", "fresh instance starts white")
    check(h.v("Dimmer") == 100, "fresh instance dimmer 100 %")
    check(h.levels("RGB") == [255, 255, 255], "RGB white")
    check(h.levels("RGBW") == [0, 0, 0, 255], "RGBW white = W only")
    check(h.levels("RGBWA") == [0, 0, 0, 255, 0], "RGBWA white = W only")
    check(h.c("Preview").Color == "#FFFFFF", "preview swatch coloured")

    h.press("Preset 1")  # red
    check(h.s("Hex") == "#FF0000" and h.levels("RGBWA") == [255, 0, 0, 0, 0], "preset red")
    check(h.v("Hue") == 0 and h.v("Saturation") == 100, "HSV follows")

    h.press("Preset 14")  # warm white #FFB46B
    check(h.levels("RGBW") == [148, 73, 0, 107], f"warm white RGBW {h.levels('RGBW')}")
    # amber (#FFBF00) takes the warm part: k = min(1, 0.706 / 0.749) = 0.942
    check(h.levels("RGBA") == [15, 0, 107, 240], f"warm white RGBA {h.levels('RGBA')}")
    # white first (0.42), amber from the rest: min(0.58, 0.286 / 0.749) = 0.382
    check(h.levels("RGBWA") == [51, 0, 0, 107, 97], f"warm white RGBWA {h.levels('RGBWA')}")

    h.press("Preset 3")  # amber #FFBF00
    check(h.levels("RGBA") == [0, 0, 0, 255], f"amber preset = A only {h.levels('RGBA')}")


def test_inputs():
    print("hex / rgb / hsv / kelvin input")
    h = Harness()
    h.user("Hex", "String", "00f")
    check(h.s("Hex") == "#0000FF", "short hex accepted and normalized")
    h.user("Hex", "String", "nonsense")
    check(h.v("Status") == 1 and h.s("Hex") == "#0000FF", "invalid hex -> Compromised, field restored")
    h.user("Red", "Value", 128)
    check(h.s("Hex") == "#8000FF" and h.v("Status") == 0, "RGB knob sets colour, status back to OK")
    h.user("Hue", "Value", 120)
    check(h.s("Hex") == "#8000FF", "HSV input right after another change is held briefly")
    h.tick(8)
    check(h.s("Hex") == "#00FF00", f"... and applied after the hold: hue 120 = green ({h.s('Hex')})")
    h.user("Saturation", "Value", 0)
    check(h.s("Hex") == "#FFFFFF" and h.v("Hue") == 120, "saturation 0 keeps hue")
    h.user("Brightness", "Value", 0)
    h.user("Brightness", "Value", 100)
    check(h.v("Hue") == 120, "black keeps hue")
    h.user("Kelvin", "Value", 3000)
    r, g, b = h.levels("RGB")
    check(r == 255 and 150 < g < 200 and 80 < b < 130, f"3000 K is warm ({r},{g},{b})")


def test_dimmer_and_fade():
    print("dimmer / fade")
    h = Harness()
    h.press("Preset 1")
    h.user("Dimmer", "Value", 50)
    check(h.levels("RGB") == [128, 0, 0], "dimmer scales outputs")
    check(h.s("Hex") == "#FF0000", "hex shows undimmed colour")
    check(abs(h.v("Link Red") - 50) < 0.01, "link includes dimmer")

    h.user("Dimmer", "Value", 100)
    h.user("Fade Time", "Value", 1.0)
    h.press("Preset 10")  # blue
    check(h.levels("RGB") == [255, 0, 0], "fade does not jump")
    h.tick(10)
    r, g, b = h.levels("RGB")
    check(120 <= r <= 135 and 120 <= b <= 135, f"half way after 0.5 s ({r},{g},{b})")
    h.tick(10)
    check(h.levels("RGB") == [0, 0, 255] and h.s("Hex") == "#0000FF", "fade done after 1 s")


def test_user_presets():
    print("user presets")
    h = Harness()
    check(h.s("User 1 Swatch") == "empty", "empty slot marked")
    h.press("Preset 6")  # green
    h.user("Store", "Boolean", True)
    h.press("User 1")
    check(h.s("User 1 Hex") == "#00FF00" and not h.c("Store").Boolean, "store saves and disarms")
    check(h.c("User 1 Swatch").Color == "#00FF00", "swatch shows stored colour")
    h.press("Preset 1")
    h.press("User 1")
    check(h.s("Hex") == "#00FF00", "recall")
    h.user("User 2 Hex", "String", "#ff8800")
    check(h.s("User 2 Hex") == "#FF8800" and h.c("User 2 Swatch").Color == "#FF8800", "typed hex normalized")
    h.press("User 3")
    check(h.s("Hex") == "#00FF00", "empty slot does nothing")

    h2 = Harness(preset={"Hex": "#123456", "Dimmer": 40, "User 1 Hex": "#ABCDEF"})
    check(h2.s("Hex") == "#123456" and h2.v("Dimmer") == 40, "restores colour and dimmer after restart")
    check(h2.c("User 1 Swatch").Color == "#ABCDEF", "restores user preset swatch")


class Console:
    """Fake console fader per link channel, wired both ways like in Q-SYS:
    picker output -> fader, fader -> picker input (with a little rounding)."""

    def __init__(self, h):
        self.h = h
        self.chans = [n for n in ("Red", "Green", "Blue", "White", "Amber", "Dimmer")
                      if h.g.Controls["Link " + n] is not None]
        self.level = {n: None for n in self.chans}

    def pull(self):
        for n in self.chans:
            v = self.h.v("Link " + n)
            if self.level[n] != v:
                self.level[n] = v

    def echo(self, offset=0.3):
        """Console reports its levels back (like MA2 feedback after its hold time)."""
        for n in self.chans:
            self.h.user("Link " + n, "Value", self.level[n] + offset if self.level[n] < 99 else self.level[n])

    def move(self, name, value):
        """Operator moves a fader on the console."""
        self.level[name] = value
        self.h.user("Link " + name, "Value", value)


def test_console_link():
    print("console link (two-way)")
    h = Harness()
    con = Console(h)
    con.pull()
    con.move("Red", 100)  # console state on start differs: adopt it
    con.move("Green", 0)
    con.move("Blue", 0)
    check(h.s("Hex") == "#FF0000", f"console state adopted on start ({h.s('Hex')})")

    h.press("Preset 10")  # blue
    con.pull()
    check(con.level["Blue"] == 100 and con.level["Red"] == 0, "picker drives console")
    con.echo(offset=0.3)
    check(h.s("Hex") == "#0000FF", "own echo ignored")

    h.tick(30)  # hold time over
    con.move("Red", 50)
    # green carries the 0.3 % echo offset -> 1/255
    check(h.s("Hex") in ("#8000FF", "#8001FF"), f"console move adopted ({h.s('Hex')})")
    check(h.v("Link Red") == 50 and h.v("Link Blue") == 100, "adopting does not write back")

    h.press("Preset 6")  # green
    con.pull()
    con.move("Blue", 40)  # operator moves during hold time
    check(h.s("Hex") == "#00FF00", "change during hold is postponed")
    h.tick(25)
    check(h.s("Hex") == "#00FF66", f"... and adopted after the hold ({h.s('Hex')})")

    h.user("Dimmer", "Value", 50)
    con.pull()
    h.tick(30)
    con.move("Green", 100)  # brighter than the dimmer allows
    check(h.v("Dimmer") == 100, f"dimmer raised when console exceeds it ({h.v('Dimmer')})")
    con.move("Green", 0)
    con.move("Blue", 0)
    check(h.v("Dimmer") == 0, "all faders down = dimmer 0")
    check(h.s("Hex") != "#000000", "colour kept when all faders are down")

    h.user("Dimmer", "Value", 100)
    h.user("Fade Time", "Value", 1.0)
    h.press("Preset 1")
    h.tick(5)
    con.move("Blue", 100)
    check(h.v("Link Red") > 0, "fade keeps running while console input arrives")
    h.tick(40)
    con.pull()
    # the fade owns the link: it keeps writing, so the console follows the picker
    check(h.s("Hex") == "#FF0000" and con.level["Blue"] == 0, "fade wins over console moves during the fade")


def test_link_rgbwa_separate():
    print("console link RGBWA, separate dimmer")
    h = Harness({"Console Link": "RGBWA", "Dimmer": "Separate Output"})
    con = Console(h)
    check(con.chans == ["Red", "Green", "Blue", "White", "Amber", "Dimmer"], "link controls created")
    h.user("Dimmer", "Value", 30)
    h.press("Preset 16")
    con.pull()
    check(con.level["White"] == 100 and con.level["Dimmer"] == 30, "white on W, dimmer separate")
    check(h.levels("RGB") == [255, 255, 255] and h.v("Dimmer Level") == 77, "level outputs undimmed + dimmer level")
    h.tick(30)
    con.move("White", 0)
    con.move("Amber", 100)
    check(h.s("Hex") == "#FFBF00", f"RGBWA unmix: amber ({h.s('Hex')})")
    con.move("Dimmer", 80)
    check(h.v("Dimmer") == 80, "separate dimmer feedback")

    h2 = Harness({"Console Link": "Off", "User Presets": 0})
    check(h2.g.Controls["Link Red"] is None and h2.g.Controls["User 1"] is None, "no link / user controls when off")


def test_picker_wheel():
    print("colour wheel")
    for n, expect in ((11, 11), (21, 21), (22, 23), (41, 41)):
        h = Harness({"Picker Resolution": n})
        c = (expect + 1) // 2
        check(h.g.Controls[f"Wheel {c}.{c}"] is not None and h.g.Controls["Wheel 1.1"] is None
              and h.g.Controls[f"Wheel 1.{c}"] is not None and h.g.Controls[f"Wheel {expect}.{c}"] is not None,
              f"resolution {n}: {expect} cells wide, round")
    h = Harness()  # 21: centre 11.11
    h.press("Wheel 1.11")
    check(h.s("Hex") == "#FF0000", f"top = red ({h.s('Hex')})")
    h.press("Wheel 11.21")
    check(h.v("Hue") == 90, f"right = 90 deg ({h.v('Hue')})")
    h.press("Wheel 21.11")
    check(h.s("Hex") == "#00FFFF", f"bottom = cyan ({h.s('Hex')})")
    h.press("Wheel 11.6")
    check(h.v("Hue") == 270 and 49 < h.v("Saturation") < 53, f"left half way = 270 deg, ~50 % ({h.v('Hue')}, {h.v('Saturation')})")
    h.press("Wheel 11.11")
    check(h.s("Hex") == "#FFFFFF" and h.v("Hue") == 270, "centre = white, hue kept")
    h.tick(10)
    h.user("Brightness", "Value", 50)
    h.press("Wheel 1.11")
    check(h.s("Hex") == "#800000", f"wheel keeps the brightness ({h.s('Hex')})")
    h.tick(10)
    h.user("Brightness", "Value", 0)
    h.press("Wheel 1.11")
    check(h.s("Hex") == "#FF0000", "from black a wheel choice gives full brightness")
    check(all(not h.c(n).CssClass for n in ("Wheel 1.11", "Preset 1", "User 1", "Preview", "User 1 Swatch")),
          "CSS classes are never written at runtime (UCI classes stay)")
    check(not h.c("Wheel 1.11").Color and not h.c("Preset 1").Color, "touch buttons are never coloured at runtime")
    h.tick(40)
    check(not h.g.Timers[1].running, "timer stops when nothing is pending")
    h.user("Fade Time", "Value", 0.5)
    h.press("Wheel 21.11")
    check(h.g.Timers[1].running, "timer wakes up for a fade")
    h.tick(10)
    check(h.s("Hex") == "#00FFFF", "fade runs after the timer slept")


class QsysPicker:
    """Fake Q-SYS Color Picker, Hue/Saturation/Value wired both ways to the plugin's
    Hue/Saturation/Brightness. Like the real one it rounds to whole numbers and
    answers every input with all three outputs."""

    def __init__(self, h):
        self.h = h
        self.hsv = [0, 0, 100]

    def pull(self):
        """Plugin outputs -> picker inputs, picker echoes all three values."""
        names = ("Hue", "Saturation", "Brightness")
        self.hsv = [round(self.h.v(n)) for n in names]
        for n, v in zip(names, self.hsv):
            self.h.user(n, "Value", v)

    def drag(self, hue, sat, val):
        """Operator drags on the picker surface: outputs one after another."""
        self.hsv = [hue, sat, val]
        for n, v in zip(("Hue", "Saturation", "Brightness"), self.hsv):
            self.h.user(n, "Value", v)


def test_qsys_color_picker():
    print("Q-SYS Color Picker wired both ways")
    h = Harness()
    qp = QsysPicker(h)
    h.tick(8)
    qp.drag(240, 100, 100)
    check(h.s("Hex") == "#0000FF", f"picker drives the plugin ({h.s('Hex')})")
    h.press("Preset 1")
    qp.pull()
    check(qp.hsv == [0, 100, 100] and h.s("Hex") == "#FF0000", "preset moves the picker, echo ignored")

    h.user("Fade Time", "Value", 1.0)
    h.press("Preset 10")  # blue
    for _ in range(20):
        h.tick()
        qp.pull()  # picker answers every fade step
    check(h.s("Hex") == "#0000FF", f"fade not interrupted by the picker echo ({h.s('Hex')})")
    h.tick(10)
    qp.drag(120, 100, 100)
    check(h.s("Hex") == "#00FF00", f"picker drag after the fade adopted ({h.s('Hex')})")

    h.user("Fade Time", "Value", 0)
    h.press("Preset 14")  # warm white, picker rounds its values
    qp.pull()
    check(h.s("Hex") == "#FFB46B", f"rounded echo does not change the colour ({h.s('Hex')})")
    qp.drag(30, 50, 100)  # within the hold time
    check(h.s("Hex") == "#FFB46B", "picker input during the hold is postponed")
    h.tick(8)
    check(h.s("Hex") == "#FFBF80", f"... and adopted after the hold ({h.s('Hex')})")


def test_calibration():
    print("LED calibration")
    h = Harness()
    h.user("White LED Color", "String", "#FFE0C0")  # warm white LED
    h.press("Preset 16")
    check(h.levels("RGBW") == [0, 31, 63, 255], f"white point with warm W {h.levels('RGBW')}")
    h.user("Amber LED Color", "String", "xyz")
    check(h.v("Status") == 1 and h.s("Amber LED Color") == "#FFBF00", "invalid calibration rejected")


def main():
    for t in (test_start_and_presets, test_inputs, test_dimmer_and_fade, test_user_presets,
              test_console_link, test_link_rgbwa_separate, test_picker_wheel, test_qsys_color_picker, test_calibration):
        t()
    print()
    if FAILED:
        print(f"{len(FAILED)} check(s) failed")
        sys.exit(1)
    print("all checks passed")


if __name__ == "__main__":
    main()
