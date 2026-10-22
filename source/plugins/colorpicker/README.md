# Color Picker – Q-SYS Plugin

Colour picker for Q-SYS: fixed presets, a picker field with hue strip, HSV, Kelvin and hex entry, user
presets and fades. Outputs the colour as hex and as 0-255 levels for RGB, RGBW, RGBA and
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
| Picker Resolution | 8-24 (16) | Cells per side of the picker field; the hue strip gets twice as many |
| Dimmer | Scale Outputs / Separate Output | *Scale*: the dimmer is multiplied into every channel. *Separate*: channels stay at full level, the dimmer gets its own output (`Dimmer Level`, `Link Dimmer`) |
| White/Amber Mixing | Subtract (accurate) / Add (brighter) | *Subtract*: the white/amber part is taken out of R, G and B, the colour stays correct. *Add*: R, G, B unchanged, W/A added on top – brighter, colour shifts towards white |
| Console Link | Off / RGB / RGBW / RGBA / RGBWA | Channel layout of the Link controls |
| Debug Print | None / Basic / Verbose | Log output in the Debug window |

## Pages

- **Presets** – 16 fixed colours, user presets with **Store**
- **Picker** – saturation × brightness field, hue strip and hue fader (like the Q-SYS
  colour dialog), Saturation / Brightness faders, Kelvin
- **Outputs** – all level outputs and the Console Link values
- **Setup** – LED calibration, user preset hex values, status
- **About**

Every colour page shows the current colour at the top: preview, hex, R/G/B, fade time
and dimmer.

## Choosing a colour

| Input | Fades | Notes |
|---|---|---|
| Preset, picker field, hue strip, user preset, hex | yes | Uses `Fade Time` (0-10 s) |
| Red / Green / Blue, Hue / Saturation / Brightness, Kelvin, Dimmer | no | Continuous controls follow immediately |

Hex accepts `#RRGGBB`, `RRGGBB`, `#RGB` and `0xRRGGBB`. Invalid input sets the status to
*Compromised* and restores the field.

**Picker field:** saturation runs left → right, brightness top → bottom, for the current
hue. Pick the hue on the strip (or drag the hue fader), then tap the field. The field is
recoloured whenever the hue changes (at most every 0.15 s). Choosing a hue while the
colour is white or black gives the fully saturated, full brightness colour. Q-SYS buttons
react to taps only – dragging across the field does not work, use the faders for that.

**User presets:** switch **Store** on and press a slot to save the current colour – Store
switches off again. Press a slot to recall it. Slots can also be typed or set by pin on the
Setup page (`User n Hex`). Empty slots do nothing.

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

## UCIs

The plugin colours controls at runtime only where showing the colour is their job:
`Preview`, the `User n Swatch` indicators and the picker field cells (`Field r.c`, plugin UI
only, no pins). The field cells are toggles that the plugin keeps switched on, so they
always show their runtime colour. Preset, hue strip, user and Store buttons are never
restyled; their colours come from the plugin layout, so UCI copies can be styled freely.

## Persistence

All values (colour, dimmer, fade time, user presets, LED calibration) are plain control
values and are kept with the design and over Core restarts.

## Status

| Status | Meaning |
|---|---|
| OK | Running |
| Compromised | Invalid hex entered (colour, user preset or LED calibration) – clears on the next valid colour |
| Initializing | Starting |
