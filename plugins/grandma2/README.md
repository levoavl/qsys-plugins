# grandMA2 – Q-SYS Plugin

Control grandMA2 executors, macros and commands from Q-SYS – **with feedback**.
Every value is a plain Q-SYS control with its own pin, so it can be dragged onto a UCI and
styled freely.

Part of [levo AVL Q-SYS Plugins](../../README.md).

## Tested on

| Console | Firmware | Q-SYS | Result |
|---|---|---|---|
| grandMA2 onPC | 3.9.60.91 | Designer 10.1, Emulation | 🚧 in test |

## Console setup

1. **Setup → Console → Global Settings → Remotes = "Login Enabled"**.
2. Create a user for Q-SYS (or use an existing one). The plugin logs in like the MA web remote.
3. The Q-SYS Core (or the PC running Emulation) must reach the console on **TCP 80**.

## Properties

| Property | Range | Default | |
|---|---|---|---|
| Fader Count | 0–64 | 8 | Fader executor slots |
| Button Count | 0–128 | 16 | Button executor slots |
| Macro Count | 0–64 | 8 | Macro trigger slots |
| Command Count | 0–32 | 4 | Free command slots |
| Poll Interval (ms) | 100–2000 | 250 | How often executor states are requested |
| Button Legends | From console / Off | From console | Write MA button functions as button legends |
| Debug Print | None / Basic / Verbose | None | Verbose logs every executor state change |

Pages without slots are hidden. At maximum counts the plugin has about 2500 controls –
use what you need.

## Slots

Each fader and button slot has an **Exec** text field right in the slot (top right).
Enter the executor as in MA: `page.exec`, e.g. `1.5` or `1.101` (`101` alone = page 1,
a comma works too). The field is a normal control, so the assignment can also be changed
at runtime via pin or UCI. Invalid entries are reported in `Last Error`.
Defaults: Fader *n* → `1.n`, Button *n* → `1.(100+n)`, Macro *n* → macro *n*.

### Fader slot `Fader n …`

| Control | Type | Pin | |
|---|---|---|---|
| Level | Fader 0–100 % | in/out | Fader position, feedback from the console. Feedback is ignored for 0.6 s after a move so the fader does not jump. |
| Button 1 | Momentary | in/out | Main executor button (usually Go), **on while the executor runs** |
| Button 2–3 | Momentary | in/out | Further executor buttons (press and release are sent, so Flash/Temp work) |
| Button 1–3 Label | Text | out | Button function from the console ("Go", "On", "Off" …) – also shown as button legend |
| Name | Text | out | Executor / sequence name |
| Cue | Text | out | Current cue |
| Function | Text | out | Fader function ("LTP", "Master" …) |
| Active | LED | out | Executor is on. **Turns off immediately when a fade-out starts.** |
| Fading | LED | out | A fade (in or out) is running |
| State | Text | out | `Empty` / `Off` / `Fading In` / `On` / `Fading Out` / `Offline` |
| Progress | Meter 0–100 % | out | Fade progress |
| Exec | Text | in/out | Assigned executor, `page.exec` (e.g. `1.101`) |

### Button slot `Button n …`

Same as the fader slot without Level / Button 1–3, plus:

| Control | Type | Pin | |
|---|---|---|---|
| Press | Momentary | in/out | Executor button, **on while the executor runs** (legend = button function) |
| Function | Text | out | Button function ("Toggle", "Go", "Flash" …) |

### Macros, commands

| Control | Type | |
|---|---|---|
| Macro n Trigger | Trigger | Sends `Go Macro <Number>` (button "Go" under the number field) |
| Macro n Number | Integer | Macro pool number |
| Command n Text / Send | Text / Trigger | Free MA command line text |
| Command TX | Text input | Any string written to this pin is sent as command |

Macros give no running feedback – the web remote does not report it. If you need feedback,
put the macro on an executor button and use a button slot.

### Status

`Status` (OK / Compromised / Fault / Missing / Initializing), `Connected`, `Logged In`,
and on the Setup page `Session`, `Reconnects`, `Last Error`.

## Plugin UI and UCIs

The executor state is shown by the **main button itself**: it is *on* while the executor
runs and *off* otherwise (fader slots: button 1 below the fader, button slots: the button).
The plugin only switches the button on and off – it never writes colours or styles. Copy the
button onto a UCI and give it any shape, colour and on/off colours you like; it keeps
working and keeps its look.

- Pressing a main button that is already on works as expected (Q-SYS only reports the
  release in that case – the plugin sends it as a short press).
- The output pin of a main button carries the executor state, not the finger on the button.
- Legends: with **Button Legends = From console** the plugin writes the MA button functions
  ("Go", "Toggle" …) as legends. Set it to **Off** to use your own texts on the UCI.
- `Active`, `Fading`, `State` and `Progress` stay available as pins for logic and UCIs.

Fade progress is a meter directly under the cue, as on the console.

## How the state is detected

The plugin polls the executors (only the ones assigned to slots) like the MA web remote.
`isRun` tells whether an executor runs – including a running fade-out. The plugin compares the
fade progress between two polls: falling progress = **Fading Out** (Active off),
rising = **Fading In**. After a button press the expected result is shown immediately
(e.g. Off → Active off) and corrected if the console does not confirm it within 1.5 s.

## Limitations

- The MA2 web remote protocol is undocumented. It is stable on MA2 3.9.x, but MA could change it.
- Macro running state is not available.
- Executors with width > 1: each covered executor number can be used as its own slot;
  buttons of the second block are sent to that executor number.
- The password control is a plain text field.

## Development

```
python3 tools/build.py grandma2 --check
python3 plugins/grandma2/test/harness.py [locimation-verbose-log.txt ...]
```

The harness runs the built plugin with a mocked Q-SYS runtime and a fake console and can
replay logs captured with the Locimation plugin (Verbose Debug).

## Credits

The web remote protocol handling is based on **MA2 Remote** by Locimation Pty Ltd
([locimation/qsys-plugins](https://github.com/locimation/qsys-plugins)), MIT License,
Copyright 2020 Locimation Pty Ltd – see [THIRD_PARTY_LICENSE_Locimation.md](THIRD_PARTY_LICENSE_Locimation.md).
grandMA2 is a trademark of MA Lighting Technology GmbH. Not affiliated with or endorsed by MA Lighting.
