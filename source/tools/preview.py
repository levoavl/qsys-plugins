#!/usr/bin/env python3
"""
Approximate preview of a plugin's control pages as PNG - for layout work without
Q-SYS Designer. Fonts and control chrome are only approximations of Q-SYS.

    pip install lupa pillow
    python3 source/tools/build.py grandma2
    python3 source/tools/preview.py grandma2 [--set "Fader Count=4"] [--demo demo.json] [--out DIR] [--scale 2]

--demo: JSON {"<control name>": {"String": "...", "Legend": "...", "Color": "#RRGGBB",
"Position": 0.5}} to show sample runtime values.

(c) levo AVL | Elias Jenny - MIT License
"""

import argparse
import base64
import io
import json
from pathlib import Path

from lupa.lua53 import LuaRuntime
from PIL import Image, ImageDraw, ImageFont

from build import output_path

FONT_DIR = Path("/usr/share/fonts/truetype/dejavu")


def font(size, bold=False, scale=1):
    name = "DejaVuSans-Bold.ttf" if bold else "DejaVuSans.ttf"
    try:
        return ImageFont.truetype(str(FONT_DIR / name), max(6, int(size * scale)))
    except OSError:
        return ImageFont.load_default()


def rgb(c, default=(0, 0, 0)):
    if c is None:
        return default
    if isinstance(c, str):
        c = c.lstrip("#")
        return tuple(int(c[i:i + 2], 16) for i in (0, 2, 4))
    return tuple(int(v) for v in c)


def to_py(lua, v):
    if lua.eval("type")(v) != b"table":
        return v.decode() if isinstance(v, bytes) else v
    keys = list(v.keys())
    if keys and all(isinstance(k, int) for k in keys):
        return [to_py(lua, v[k]) for k in sorted(keys)]
    return {(k.decode() if isinstance(k, bytes) else k): to_py(lua, v[k]) for k in keys}


def load_plugin(name, overrides):
    lua = LuaRuntime(encoding=None)
    src = output_path(name).read_bytes()
    lua.execute(b"Controls = nil\n" + src)
    g = lua.globals()
    plist = to_py(lua, g.GetProperties())
    props = {p["Name"]: p["Value"] for p in plist}
    for k, v in overrides.items():
        props[k] = type(props.get(k, v))(v) if k in props else v
    props["plugin_show_debug"] = True

    def lprops(page=None):
        t = lua.table()
        for k, v in props.items():
            t[k.encode()] = lua.table_from({b"Value": v.encode() if isinstance(v, str) else v})
        if page:
            t[b"page_index"] = lua.table_from({b"Value": page})
        return t

    pages = to_py(lua, g.GetPages(lprops()))
    controls = {c["Name"]: c for c in to_py(lua, g.GetControls(lprops()))}
    out = []
    for i, p in enumerate(pages, 1):
        layout, graphics = g.GetControlLayout(lprops(i))
        out.append((p["name"], to_py(lua, layout) or {}, to_py(lua, graphics) or []))
    return out, controls


def render(page, layout, graphics, controls, demo, scale):
    W = H = 0
    for item in list(graphics) + list(layout.values()):
        x, y = item["Position"]
        w, h = item["Size"]
        W, H = max(W, x + w), max(H, y + h)
    img = Image.new("RGB", (int(W * scale), int(H * scale)), (255, 255, 255))
    d = ImageDraw.Draw(img)
    S = lambda *v: [int(a * scale) for a in v]

    def text(t, x, y, w, h, size, color, bold=False, align="Left", valign="Center"):
        f = font(size, bold, scale)
        t = str(t)
        while t and d.textlength(t, font=f) > w * scale - 2:
            t = t[:-1]
        tw = d.textlength(t, font=f)
        tx = {"Left": x * scale + 2, "Center": (x + w / 2) * scale - tw / 2, "Right": (x + w) * scale - tw - 2}[align]
        asc, desc = f.getmetrics()
        ty = {"Top": y * scale, "Center": (y + h / 2) * scale - (asc + desc) / 2, "Bottom": (y + h) * scale - asc - desc}[valign]
        d.text((tx, ty), t, fill=color, font=f)

    for gr in graphics:
        x, y = gr["Position"]
        w, h = gr["Size"]
        t = gr["Type"]
        if t == "GroupBox":
            r = gr.get("CornerRadius", 0) * scale
            fill = rgb(gr["Fill"]) if gr.get("Fill") else None
            sw = gr.get("StrokeWidth", 1)
            outline = rgb(gr.get("StrokeColor"), (0, 0, 0)) if sw else None
            d.rounded_rectangle(S(x, y, x + w - 1, y + h - 1), radius=r, fill=fill, outline=outline, width=max(1, int(sw * scale)) if sw else 0)
            if gr.get("Text"):
                text(gr["Text"], x + 4, y + 2, w - 8, 16, gr.get("FontSize", 11), rgb(gr.get("Color")), True, valign="Top")
        elif t in ("Text", "Header", "Label"):
            text(gr.get("Text", ""), x, y, w, h, gr.get("FontSize", 11), rgb(gr.get("Color")),
                 gr.get("FontStyle") == "Bold", gr.get("HTextAlign", "Center"))
        elif t == "Image":
            im = Image.open(io.BytesIO(base64.b64decode(gr["Image"]))).convert("RGBA")
            im = im.resize((int(w * scale), int(h * scale)), Image.LANCZOS)
            img.paste(im, (int(x * scale), int(y * scale)), im)

    for name, c in layout.items():
        x, y = c["Position"]
        w, h = c["Size"]
        cdef = controls.get(name, {})
        dv = demo.get(name, {})
        style = c.get("Style") or {"Knob": "Knob", "Button": "Button", "Text": "Text"}.get(cdef.get("ControlType"), "Text")
        ind = cdef.get("IndicatorType")
        if ind == "Led" and not c.get("Style"):
            col = rgb(c.get("Color"), (0, 160, 0))
            on = dv.get("Boolean", False)
            d.ellipse(S(x, y, x + w - 1, y + h - 1), fill=col if on else (90, 90, 90), outline=(60, 60, 60))
        elif style == "Button" and not dv.get("Color") and len(c.get("Color") or ()) == 4 and c["Color"][3] == 0:
            pass  # invisible touch button (alpha 0) over an image
        elif style == "Button":
            col = rgb(dv.get("Color") or c.get("Color"), (128, 128, 128))[:3]
            pressed = dv.get("Boolean", False)
            # Q-SYS draws a button in its off state light grey, in its on state in Color
            off = rgb(c["OffColor"])[:3] if c.get("OffColor") else (222, 222, 220)
            fill = col if pressed or dv.get("Color") else off
            d.rounded_rectangle(S(x, y, x + w - 1, y + h - 1), radius=3 * scale, fill=fill, outline=(70, 70, 70))
            lum = 0.3 * fill[0] + 0.59 * fill[1] + 0.11 * fill[2]
            text(dv.get("Legend", c.get("Legend", "")), x, y, w, h, c.get("FontSize", 11),
                 (0, 0, 0) if lum > 140 else (255, 255, 255), c.get("FontStyle") == "Bold", "Center")
        elif style == "Fader":
            pos = dv.get("Position", 0.7 if not c.get("IsReadOnly") else 0.45)
            col = rgb(c.get("Color"), (0, 70, 140))
            d.rectangle(S(x, y, x + w - 1, y + h - 1), fill=(60, 60, 60))
            if h >= w:  # vertical
                fy = min(y + h - 2, y + h - pos * h)
                if pos > 0:
                    d.rectangle(S(x + 2, fy, x + w - 3, y + h - 2), fill=col)
                if not c.get("IsReadOnly"):
                    d.rectangle(S(x - 2, fy - 4, x + w + 1, fy + 4), fill=(225, 225, 225), outline=(40, 40, 40))
            else:
                if pos > 0:
                    d.rectangle(S(x + 1, y + 1, x + 1 + pos * (w - 2), y + h - 2), fill=col)
        elif ind == "Meter" and not c.get("Style"):
            pos = dv.get("Position", 0.5)
            col = rgb(c.get("Color"), (0, 160, 0))
            d.rectangle(S(x, y, x + w - 1, y + h - 1), fill=(60, 60, 60))
            if pos > 0:
                d.rectangle(S(x + 1, y + 1, x + 1 + pos * (w - 3), y + h - 2), fill=col)
        elif cdef.get("IndicatorType") == "Status":
            d.rectangle(S(x, y, x + w - 1, y + h - 1), fill=(0, 140, 0), outline=(60, 60, 60))
            text(dv.get("String", "OK"), x, y, w, h, 11, (255, 255, 255), False, "Center")
        else:  # text field / indicator
            editable = cdef.get("ControlType") in ("Text", "Knob")
            bg = rgb(dv.get("Color") or c["Color"]) if (dv.get("Color") or c.get("Color")) else ((255, 255, 255) if editable else (238, 238, 236))
            line = None if c.get("StrokeWidth") == 0 else ((150, 150, 150) if editable else (225, 225, 222))
            d.rectangle(S(x, y, x + w - 1, y + h - 1), fill=bg, outline=line)
            sample = dv.get("String", "")
            text(sample, x, y, w, h, c.get("FontSize", 11), rgb(c.get("TextColor"), (25, 25, 25)), c.get("FontStyle") == "Bold",
                 c.get("HTextAlign", "Center"))
    return img


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("plugin")
    ap.add_argument("--set", action="append", default=[], help='property override, e.g. "Fader Count=4"')
    ap.add_argument("--demo", help="JSON with sample control values")
    ap.add_argument("--out", default=".", help="output folder")
    ap.add_argument("--scale", type=float, default=1.5)
    a = ap.parse_args()
    overrides = {}
    for s in a.set:
        k, v = s.split("=", 1)
        overrides[k.strip()] = int(v) if v.strip().lstrip("-").isdigit() else v.strip()
    demo = json.loads(Path(a.demo).read_text()) if a.demo else {}
    pages, controls = load_plugin(a.plugin, overrides)
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    for name, layout, graphics in pages:
        img = render(name, layout, graphics, controls, demo, a.scale)
        f = out / f"{a.plugin}-{name.lower()}.png"
        img.save(f)
        print(f"  {f}  {img.size[0]}x{img.size[1]}")


if __name__ == "__main__":
    main()
