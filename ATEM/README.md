# ATEM Switcher – Q-SYS Plugin

Control Blackmagic ATEM switchers from Q-SYS – **with feedback**. All models, including
multi-M/E switchers: pick the model in the properties and the plugin offers exactly the
M/Es, keyers and sources that switcher has. Every function is a plain Q-SYS control with
its own pin, so it can be dragged onto a UCI and styled freely.

Part of [levo AVL Q-SYS Plugins](../README.md).

<a href="https://github.com/levoavl/qsys-plugins/releases/download/atem-v1.0/levo-atem.qplug"><img src="https://img.shields.io/badge/-%E2%AC%87_Download_v1.0-FFB830?style=for-the-badge" alt="Download ATEM plugin v1.0"></a>
<a href="CHANGELOG.md"><img src="https://img.shields.io/badge/-Changelog-00468C?style=for-the-badge" alt="Changelog"></a>

The plugin is a remote control for operation – program / preview, transitions, keyers,
aux, media, macros, audio, streaming and recording. Setup details (keyer settings,
SuperSource layout, EQ / dynamics, stream keys …) stay in ATEM Software Control.

## Tested on

| Switcher | Firmware | Q-SYS | Result |
|---|---|---|---|
| ATEM Mini Extreme | 10.3 | Designer 10.1 | ✅ M/E, keyers, aux, SuperSource, media, macros, audio, recording |

Multi-M/E switchers (Constellation, 2 M/E …) and the classic audio mixer (older Production
Studio / Broadcast models) are implemented from the protocol but not yet tested on
hardware. If you run the plugin on one of them, please open an issue – positive reports
are just as welcome as bugs.

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
| Still Buttons | 0–96 | 20 | Buttons per media player for the first n stills (the combo lists all) |
| Macro Buttons | 0–100 | 20 | Buttons for the first n macros (the combo lists all used macros) |
| Audio | On / On incl. MADI / Off | On | Audio mixer page. MADI channels (Constellation) only with *On incl. MADI*. |
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

Pages: `M/E n` · `Keyers` · `Aux` (`Aux 1-8`, `Aux 9-16` … above 8 aux) · `Audio` ·
`Stream & Record` · `Media` · `Macros` ·
`SuperSource` · `Setup` · `About` – depending on the model and properties.

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

### Audio (`Audio <input> …`, page Audio)

Fairlight (ATEM Mini series, Television Studio, Constellation) or the classic audio mixer
(older Production Studio / Broadcast models), depending on the model. Inputs: `Input n`
(video inputs, embedded audio), `Mic 1/2`, `XLR n`, `RCA 1`, `MADI n` …

| Control | Type | Pin | |
|---|---|---|---|
| Level | Fader dB | in/out | Fairlight −100 … +10 dB, classic −60 … +6 dB |
| On | Toggle | in/out | Mix option On; pressed again: Off |
| AFV | Toggle | in/out | Audio Follow Video; pressed again: Off. Only inputs with video (embedded audio, media players) – not mic / XLR / RCA / MADI |
| Name | Text | out | Video input name or `Mic 1` … |
| Audio Master Level | Fader dB | in/out | |
| Audio Master AFV | Toggle | in/out | Master follows Fade to Black ("AFV" on the master in ATEM Software Control) |

Split stereo inputs (dual mono) are controlled through their first channel. EQ, dynamics,
delay and meters stay in ATEM Software Control.

### Streaming / recording (page Stream & Record, on models that support it)

| Control | Type | Pin | |
|---|---|---|---|
| Stream | Toggle | in/out | Start / stop, lit while connecting or streaming |
| Stream Status, Stream Duration | Text | out | Idle / Connecting / Streaming / Stopping, `hh:mm:ss` |
| Record | Toggle | in/out | Start / stop, lit while recording |
| Record Status | Text | out | incl. media problems (no media, full, unformatted …) |
| Record Duration, Record Time Remaining | Text | out | |
| Record ISO | Toggle | in/out | Record all inputs (ISO models) |

Stream key, server and recording disk are set up in ATEM Software Control.

### Media players (`MPn …`, page Media)

| Control | Type | Pin | |
|---|---|---|---|
| Source | Combo box | in/out | Still or clip, e.g. `Still 3: logo.png` |
| Still i | Toggle | in/out | Lit when the player shows still i |
| Clip i, Play, Loop, Rewind | Toggle / Trigger | in/out | Only on models with clips |
| Still i Name, Clip i Name | Text | out | File / clip names from the media pool (under the buttons of player 1) |

### Colour generators (`Color n …`, page Media)

| Control | Type | Pin | |
|---|---|---|---|
| Hue | Integer 0–359° | in/out | |
| Saturation, Luma | 0–100 % | in/out | |

### Macros (page Macros)

| Control | Type | Pin | |
|---|---|---|---|
| Macro i | Toggle | in/out | Runs macro i, lit while it runs. Pressing it again stops it. |
| Macro i Name | Text | out | |
| Macro + Macro Run | Combo box + Trigger | in | Run any used macro by name |
| Macro Stop | Trigger | in | |
| Macro Loop | Toggle | in/out | |
| Macro Running | LED | out | |
| Macro Running Name | Text | out | |

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
| Lua Memory, Plugin Uptime, Internal Errors | Text | out | Health: plugin memory (normal about 1 MB, event log warning above 10 MB), running time of the plugin (stops if it hangs), caught runtime errors (also in the Core event log) |
| Name *source* | Text | out | Source names as set on the switcher (placed under the button grids) |

## Connection behaviour

UDP 9910 with the ATEM's own acknowledge / resend scheme. After connecting, the switcher
sends its complete state (status *Initializing*), then the status turns *OK*. When the
switcher stops answering for 5 s, the plugin reconnects with backoff (1 → 30 s). Commands
are queued and sent in packets of up to 1416 bytes; fast T-bar moves are merged.

## Known limitations

- Continue after a macro user wait is not supported.
- After a restart / reconnect the plugin cannot know which end a T-bar was left at; it
  assumes the bottom.

## Credits

ATEM protocol handling is based on [Sofie ATEM Connection](https://github.com/Sofie-Automation/sofie-atem-connection)
(MIT License, Copyright (c) 2023 Norsk rikskringkasting AS). The model table is generated
from the [Bitfocus Companion module bmd-atem](https://github.com/bitfocus/companion-module-bmd-atem)
(MIT License, Copyright (c) 2018 Bitfocus AS, William Viker & Håkon Nessjøen). Their licence
texts are in this folder (`THIRD_PARTY_LICENSE_*.md`).

ATEM is a trademark of Blackmagic Design. This plugin is not affiliated with or endorsed by
Blackmagic Design.
