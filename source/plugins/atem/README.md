# ATEM Switcher – Q-SYS Plugin

Control Blackmagic ATEM switchers from Q-SYS – **with feedback**. All models, including
multi-M/E switchers: pick the model in the properties and the plugin offers exactly the
M/Es, keyers and sources that switcher has. Every function is a plain Q-SYS control with
its own pin, so it can be dragged onto a UCI and styled freely.

Part of [levo AVL Q-SYS Plugins](../README.md).

> [!NOTE]
> Work in progress (0.x). Done: connection, M/E functions, upstream / downstream keyers,
> aux outputs, SuperSource boxes. Media, colour generators, macros, audio, streaming and
> recording follow.

## Tested on

| Switcher | Firmware | Q-SYS | Result |
|---|---|---|---|
| ATEM Mini Extreme | 10.3 | Designer 10.1 | ⏳ in test |

## Switcher setup

1. Give the switcher a fixed IP address (ATEM Setup → Configure → Network).
2. The Q-SYS Core (or the PC running Emulation) must reach the switcher on **UDP 9910**.
3. Enter the IP address on the plugin's Setup page.

The plugin connects like ATEM Software Control. ATEM switchers accept a limited number of
simultaneous control connections – close unused software panels if the connection is refused.

## Properties

| Property | Values | Default | |
|---|---|---|---|
| Model | all ATEM models, Custom | ATEM Mini Extreme | Decides which M/Es, keyers and sources the plugin has |
| Custom … | | | Counts for the *Custom* model (only shown for Custom) |
| Source Buttons | All Sources / Inputs Only / None | All Sources | Buttons per source on the program / preview buses and the SuperSource boxes. The combo boxes always list every source. |
| Aux Buttons | Auto / All Sources / Inputs Only / None | Auto | Buttons per source on every aux output. *Auto*: all sources up to 8 aux, inputs only up to 24 aux, none above (Constellation 4K Plus: 48 aux). |
| Keyer Setup Page | on / off | off | Page *Keyers*: fill / key source and type of the upstream keyers, fill / key source of the DSKs |
| SuperSource Page | on / off | off | Page *SuperSource*: box enable and source |

The plugin is meant as a remote control for operation. Setup details (keyer settings,
SuperSource layout …) stay in ATEM Software Control – the two setup pages are optional.
| Button Legends | Default Names / Device Names | Default Names | *Device Names* writes the switcher's short source names (e.g. `CAM1`) as button legends. This overrides legends set on UCI copies of the buttons. |
| Debug Print | None / Basic / Verbose | None | Basic: connection and user actions. Verbose: all protocol traffic. |

After connecting, the plugin compares the switcher with the selected model. On a mismatch
the status turns *Compromised* and names the switcher found.

## Controls

Source names in control names are fixed (`Input 1`, `Bars`, `Color 1`, `MP1`,
`SuperSource`, `ME2 PGM` …) and do not change when sources are renamed on the switcher.
The names set on the switcher are available as `Name <source>` and in the combo boxes.
Each name sits directly under the first button grid that contains the source (under the
program buttons on page M/E 1; sources that only exist on aux, e.g. clean feeds, on the
Aux page). On a UCI the same name control can be placed as often as needed.

Pages: `M/E n` · `Keyers` · `Aux` (`Aux 1-8`, `Aux 9-16` … above 8 aux) · `SuperSource` ·
`Setup` · `About` – depending on the model.

### M/E n (page `M/E n`, controls `MEn …`)

| Control | Type | Pin | |
|---|---|---|---|
| Preview / Program | Combo box | in/out | Source by name (as set on the switcher) |
| Preview *source* / Program *source* | Toggle | in/out | One button per source, lit when selected (preview green, program red). Order as in ATEM Software Control: inputs, then Black, Bars, colours, media players … |
| Cut | Trigger | in | |
| Auto | Toggle | in/out | Starts the transition, lit while it runs |
| T-Bar | Fader 0–1 | in/out | Manual transition. Behaves like a hardware T-bar: it stays at the end it reached (also after Auto) and the next transition runs in the other direction. |
| In Transition | LED | out | |
| Fade to Black | Toggle | in/out | Starts FTB, lit while black or fading |
| Fade to Black Rate | Text `s:ff` | in/out | Like ATEM Software Control: `1:00` = 1 s at the switcher's frame rate. A plain number is taken as frames. |
| Transition Style | Combo box | in/out | Mix / Dip / Wipe / DVE / Stinger |
| Style Mix … Style Stinger | Toggle | in/out | Same as buttons |
| Transition Rate | Text `s:ff` | in/out | Rate of the selected style (Stinger has none), format as above |
| Preview Transition | Toggle | in/out | |
| Next Background, Next Key k | Toggle | in/out | Elements of the next transition. At least one stays selected. |
| Key k On Air | Toggle | in/out | Upstream keyer on air |

### Downstream keyers (`DSK n …`, page M/E 1; Fill / Key with Keyer Setup Page)

| Control | Type | Pin | |
|---|---|---|---|
| On Air | Toggle | in/out | |
| Tie | Toggle | in/out | |
| Auto | Toggle | in/out | Mixes the DSK on / off, lit while it mixes |
| In Transition | LED | out | |
| Rate | Text `s:ff` | in/out | |
| Fill, Key | Combo box | in/out | Fill and key (cut) source |

### Upstream keyers (`MEn Key k …`, page Keyers – property Keyer Setup Page)

| Control | Type | Pin | |
|---|---|---|---|
| Fill, Key | Combo box | in/out | Fill and key (cut) source |
| Type | Combo box | in/out | Luma / Chroma / Pattern / DVE |

On Air and Next Key are on the M/E page (see above).

### Aux (`Aux n …`, page Aux)

| Control | Type | Pin | |
|---|---|---|---|
| Aux n | Combo box | in/out | Every source the switcher allows on that aux (incl. clean feeds, program / preview, multiview …) |
| Aux n *source* | Toggle | in/out | Buttons for inputs, Black, Bars, colours, media players, SuperSource, clean feeds, M/E program / preview |

### SuperSource (`SSn Box b …`, page SuperSource – property SuperSource Page)

| Control | Type | Pin | |
|---|---|---|---|
| Enable | Toggle | in/out | Box on / off |
| Source | Combo box | in/out | Box source |
| *source* | Toggle | in/out | One button per source |

### Setup

| Control | Type | Pin | |
|---|---|---|---|
| IP Address | Text | in/out | Switcher IP address |
| Reconnect | Trigger | in | |
| Status | Status | out | OK / Compromised (model mismatch) / Fault / Missing / Initializing |
| Connected | LED | out | |
| Device | Text | out | Product name reported by the switcher |
| Protocol Version | Text | out | ATEM protocol version (e.g. `2.32`) |
| Last Error, Reconnects | Text | out | Diagnostics |
| Name *source* | Text | out | Source names as set on the switcher (placed under the button grids) |

## Connection behaviour

UDP 9910 with the ATEM's own acknowledge / resend scheme. After connecting, the switcher
sends its complete state (status *Initializing*), then the status turns *OK*. When the
switcher stops answering for 5 s, the plugin reconnects with backoff (1 → 30 s). Commands
are queued and sent in packets of up to 1416 bytes; fast T-bar moves are merged.

## Credits

ATEM protocol handling is based on [Sofie ATEM Connection](https://github.com/Sofie-Automation/sofie-atem-connection)
(MIT License, Copyright (c) 2023 Norsk rikskringkasting AS). The model table is generated
from the [Bitfocus Companion module bmd-atem](https://github.com/bitfocus/companion-module-bmd-atem)
(MIT License, Copyright (c) 2018 Bitfocus AS, William Viker & Håkon Nessjøen).

ATEM is a trademark of Blackmagic Design. This plugin is not affiliated with or endorsed by
Blackmagic Design.
