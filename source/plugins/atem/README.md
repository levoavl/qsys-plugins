# ATEM Switcher – Q-SYS Plugin

Control Blackmagic ATEM switchers from Q-SYS – **with feedback**. All models, including
multi-M/E switchers: pick the model in the properties and the plugin offers exactly the
M/Es, keyers and sources that switcher has. Every function is a plain Q-SYS control with
its own pin, so it can be dragged onto a UCI and styled freely.

Part of [levo AVL Q-SYS Plugins](../README.md).

> [!NOTE]
> Work in progress (0.x). This first stage covers the connection and the M/E functions
> (program / preview, transitions, fade to black, next transition, keyers on air).
> DSK, aux, SuperSource, media, macros, audio, streaming and recording follow.

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
| Source Buttons | All Sources / Inputs Only / None | All Sources | Buttons per source on the program and preview bus. The combo boxes always list every source. |
| Button Legends | Default Names / Device Names | Default Names | *Device Names* writes the switcher's short source names (e.g. `CAM1`) as button legends. This overrides legends set on UCI copies of the buttons. |
| Debug Print | None / Basic / Verbose | None | Basic: connection and user actions. Verbose: all protocol traffic. |

After connecting, the plugin compares the switcher with the selected model. On a mismatch
the status turns *Compromised* and names the switcher found.

## Controls

Source names in control names are fixed (`Input 1`, `Bars`, `Color 1`, `MP1`,
`SuperSource`, `ME2 PGM` …) and do not change when sources are renamed on the switcher.
The names set on the switcher are available as `Name <source>` (Setup page) and in the
combo boxes.

### M/E n (page `M/E n`, controls `MEn …`)

| Control | Type | Pin | |
|---|---|---|---|
| Program / Preview | Combo box | in/out | Source by name (as set on the switcher) |
| Program *source* / Preview *source* | Toggle | in/out | One button per source, lit when selected |
| Cut | Trigger | in | |
| Auto | Toggle | in/out | Starts the transition, lit while it runs |
| T-Bar | Fader 0–1 | in/out | Manual transition. Feedback shows the position while a transition runs. |
| In Transition | LED | out | |
| Fade to Black | Toggle | in/out | Starts FTB, lit while black or fading |
| Fade to Black Rate | Integer (frames) | in/out | |
| Transition Style | Combo box | in/out | Mix / Dip / Wipe / DVE / Stinger |
| Style Mix … Style Stinger | Toggle | in/out | Same as buttons |
| Transition Rate | Integer (frames) | in/out | Rate of the selected style (Stinger has none) |
| Preview Transition | Toggle | in/out | |
| Next Background, Next Key k | Toggle | in/out | Elements of the next transition. At least one stays selected. |
| Key k On Air | Toggle | in/out | Upstream keyer on air |

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
| Name *source* | Text | out | Source names as set on the switcher |

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
