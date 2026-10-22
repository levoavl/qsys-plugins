# Advanced Color Picker – Q-SYS Plugin

Colour picker for Q-SYS: fixed presets, a colour wheel, HSV, Kelvin and hex entry, user
presets and fades – and it works together with the built-in Q-SYS **Color Picker**. Outputs the colour as hex and as 0-255 levels for RGB, RGBW, RGBA and
RGBWA fixtures, plus a two-way **Console Link** for lighting console faders (e.g. the
levo AVL grandMA2 plugin).

No device, no network – runs the same on a Core and in Emulation mode.

## Tested on

| Device | Version | Q-SYS | Result |
|---|---|---|---|
| – | – | Designer 10.1 | not tested on hardware yet |

## Properties

| Property | Values | Meaning |
|---|---|---|
| User Presets | 0-32 (8) | Number of user preset slots |
| Picker Resolution | 11-41 (21) | Touch resolution of the colour wheel: diameter in touch cells (odd, even values are rounded up). The wheel image itself is always smooth |
| Dimmer | Scale Outputs / Separate Output | *Scale*: the dimmer is multiplied into every channel. *Separate*: channels stay at full level, the dimmer gets its own output (`Dimmer Level`, `Link Dimmer`) |
| White/Amber Mixing | Subtract (accurate) / Add (brighter) | *Subtract*: the white/amber part is taken out of R, G and B, the colour stays correct. *Add*: R, G, B unchanged, W/A added on top – brighter, colour shifts towards white |
| Console Link | Off / RGB / RGBW / RGBA / RGBWA | Channel layout of the Link controls |
| Debug Print | None / Basic / Verbose | Log output in the Debug window |

## Pages

- **Presets** – 16 fixed colours, user presets with **Store**
- **Picker** – colour wheel with brightness fader, Hue / Saturation faders, Kelvin
- **Outputs** – all level outputs and the Console Link values
- **Setup** – LED calibration, user preset hex values, status
- **About**

Every colour page shows the current colour at the top: preview, hex, R/G/B, fade time
and dimmer.

## Choosing a colour

| Input | Fades | Notes |
|---|---|---|
| Preset, colour wheel, user preset, hex | yes | Uses `Fade Time` (0-10 s) |
| Red / Green / Blue, Hue / Saturation / Brightness, Kelvin, Dimmer | no | Continuous controls follow immediately |

Hex accepts `#RRGGBB`, `RRGGBB`, `#RGB` and `0xRRGGBB`. Invalid input sets the status to
*Compromised* and restores the field.

**Colour wheel:** all colours in one plane – hue is the angle (red on top, clockwise),
saturation the distance from the white centre. The wheel is an image with invisible touch
cells on top; it is at full brightness, tapping keeps the current brightness (from black
it goes to full brightness), the vertical fader next to the wheel sets it. Taps only –
dragging across the wheel does not work. For dragging, use the Q-SYS Color Picker (below)
or the Hue / Saturation faders.

**User presets:** tap a colour to recall it, like the fixed presets. To save, switch
**Store** on and tap a slot – Store switches off again. Slots can also be typed or set by pin on the
Setup page (`User n Hex`). Empty slots do nothing.

## Q-SYS Color Picker (two-way)

The built-in **Color Picker** component (Schematic Library → Controls) has a real picker
surface. Use it on the UCI and let this plugin do presets, fades, outputs and the console:

1. Place a **Color Picker** next to the plugin.
2. Wire both ways, each pair in both directions:
   `Hue` ↔ `Hue`, `Saturation` ↔ `Saturation`, `Value` ↔ `Brightness`.
3. Put the picker surface on the UCI.

Dragging on the picker changes the colour here; presets, user presets, fades and console
moves move the picker. Values coming back that match what the plugin just wrote (hue ±1°,
saturation / brightness ±0.6 %) are its own echo and are ignored; differing values within
0.3 s after a write are checked after that time, so intermediate answers cannot make the
colour jump. During a fade the plugin owns the picker.

## Outputs

| Control | Range | Pin |
|---|---|---|
| `Hex` | `#RRGGBB` | in/out |
| `Red`, `Green`, `Blue` | 0-255 | in/out (colour without dimmer) |
| `RGB R/G/B`, `RGBW R/G/B/W`, `RGBA R/G/B/A`, `RGBWA R/G/B/W/A` | 0-255 | out (dimmer included unless *Separate Output*) |
| `Dimmer Level` | 0-255 | out (*Separate Output* only) |
| `Link Red/Green/Blue/White/Amber/Dimmer` | 0-100 % | in/out, see below |

**White and amber extraction** – white takes the part of the colour that all three
emitters share, amber the warm rest. Set the real colour of the fixture's white and amber
LEDs on the Setup page for accurate results (defaults `#FFFFFF` and `#FFBF00`). Example:
warm white `#FFB46B` in RGBW = R 148, G 73, B 0, W 107.

## Console Link (two-way)

The Link controls are percent controls (0-100 %) with an input and an output pin – the
same format as the fader levels of the levo AVL grandMA2 plugin.

1. Set **Console Link** to the fixture layout, e.g. `RGB`.
2. In MA, put one executor per colour channel on faders.
3. Wire each channel **both ways**: `Link Red` output → `Fader 1 Level` input, and
   `Fader 1 Level` output → `Link Red` input. Same for green, blue, …

What happens:

- Choosing a colour in Q-SYS moves the console faders.
- Moving a fader on the console updates the colour picker (preview, hex, HSV, all level
  outputs) without writing back.
- Values coming back that match what the picker just sent (±0.6 %) are its own echo and
  are ignored. For 1 s after the picker writes, console input is held and checked
  afterwards, so late feedback cannot make the colour jump.
- During a fade the picker owns the faders: console moves during the fade are overwritten.
- With *Scale Outputs* the console levels contain the dimmer. When the console is brighter
  than the dimmer allows, the dimmer goes up; all faders at 0 sets the dimmer to 0 and
  keeps the colour.
- On start the picker does not write the Link – the console keeps its state and the
  picker takes it over as soon as the console reports it.

## UCIs and UCI styles (CSS)

UCI styles override the colours of buttons. That is why all colour choices – presets, user
presets and the colour wheel – are colour displays with an invisible touch button on top
(`Preset n`, `User n`, `Wheel r.c`): images for the fixed colours and the wheel, the
`User n Swatch` indicators for the user presets. Copy display and button together onto the
UCI.

If your style gives every button a background, the touch buttons become visible and cover
the colours (the user presets then show no colour on the UCI). Select the touch buttons on
the UCI (`Preset n`, `User n`, and the wheel cells if needed) and give them a CSS class,
e.g. `levo-touch`, with this rule in your style sheet:

```css
.levo-touch { background-color: transparent; border-width: 0; }
```

The plugin never writes CSS classes, colours or legends of buttons at runtime, so anything
you set on a UCI copy stays when the design runs. The only runtime colours are `Preview`
and `User n Swatch` – showing the colour is their job; keep background rules of your style
away from them.

## Persistence

All values (colour, dimmer, fade time, user presets, LED calibration) are plain control
values and are kept with the design and over Core restarts.

## Status

| Status | Meaning |
|---|---|
| OK | Running |
| Compromised | Invalid hex entered (colour, user preset or LED calibration) – clears on the next valid colour |
| Initializing | Starting |
