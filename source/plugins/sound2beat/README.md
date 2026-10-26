# Sound2Beat – Q-SYS Plugin

Beat and BPM detection from the music running through Q-SYS, with **tempo sync to a
grandMA2 or grandMA3 speed master**. The plugin listens to a low-frequency level meter
(the kick drum), finds the tempo and keeps a beat clock running – also through
breakdowns. Every output is a plain Q-SYS control with its own pin.

Part of [levo AVL Q-SYS Plugins](../../../README.md).

> Status: **0.2 – in testing.** Not released yet.

## Tested on

| Console | Firmware | Q-SYS | Result |
|---|---|---|---|
| – | – | – | not yet tested on hardware |

## How it works

Q-SYS scripts cannot see audio samples, so the analysis is split:

1. **DSP (in your design):** music feed → mono sum → band-pass on the kick (about 50–120 Hz)
   → **Meter**.
2. **Plugin:** reads the meter every 10 ms and
   - detects onsets (level jumps above an adaptive threshold – independent of the volume),
   - finds the tempo with a histogram of the intervals between onsets (folded into the
     BPM range by octaves),
   - refines it by linear regression over the last beats – far more exact than a single
     meter update,
   - runs a beat clock that follows the kicks and keeps going when they stop.
3. **Console:** the tempo is set on the speed master directly ("Master 3.1 At BPM 128"),
   not tapped – so network jitter does not reach the lights. A new value is only sent
   when the tempo is locked and changed by more than the send hysteresis.

Works best with 4/4 music with a clear kick (house, techno, pop, hip-hop). Live bands
with a drifting tempo or music without a steady kick will lock less reliably; the plugin
then holds the last good tempo instead of sending wrong values.

## Design setup

Use the feed that goes to the amplifiers (post master), so what the plugin hears is what
the room hears.

```
                         ┌─► HPF 45 Hz ─► LPF 120 Hz ─► Meter ─► Sound2Beat "Level In"    (kick)
music feed ─► Mixer 2×1 ─┤
   (mono)                └─► HPF 150 Hz ─► LPF 400 Hz ─► Meter ─► Sound2Beat "Level In 2"  (snare, optional)
```

- **Tap point:** before the system limiter/compressor if possible – they flatten the kick.
- **No AGC / compressor in the branch.** The detection works on level rises in dB and is
  independent of the volume; a gain control only smooths the rises it needs.
- **Filters:** steep (Linkwitz-Riley 24 dB/oct or more). The high-pass at about 45 Hz keeps
  sub bass out, which would otherwise hold the level up between the kicks.
- **Meter:** the level must drop clearly between two kicks. Compare peak and RMS on the
  Debug page – use whichever makes `Onset Strength` jump most clearly on each kick.
- **Second band** (property `Input Bands` = 2): recommended for pop, rock and live bands,
  where the kick alone is syncopated or weak. `Band 2 Weight` sets how much it counts.
- **Wired Pin** (default): wire the meter's output pin to the plugin's `Level In` pin.
- **Named Component:** give the meter a Code Name, enable *Script Access*, and enter the
  name on the Setup page (control name usually `meter.1`).

The Debug page shows `Level Updates` – how often the level actually changes per second.
20/s or more is good; the tempo stays exact down to about 20/s (50 ms).

## Console setup

### grandMA2 (Telnet)
1. **Setup → Console → Global Settings → Telnet = "Login Enabled"**.
2. Use a user that is allowed to run commands; enter it on the Setup page
   (default `administrator`).
3. The Core must reach the console on **TCP 30000**.
4. Default command: `SpecialMaster 3.{master} At {bpm}` – check that your speed master
   shows the same BPM value (MA2 speed mode set to BPM). Change the template if needed.

### grandMA3 (OSC)
1. **Menu → In & Out → OSC:** add a line with the console's IP, port (default 8000),
   *Enable Input* and **Receive Command = Yes**. Optional prefix (e.g. `gma3`).
2. Enter IP, port and prefix on the Setup page.
3. Default command: `Master 3.{master} At BPM {bpm}`.
4. MA3 sends no reply over OSC – the plugin cannot confirm that commands arrive.

## Properties

| Property | Values | Default | |
|---|---|---|---|
| Level Source | Wired Pin / Named Component / Test Generator | Wired Pin | Where the kick level comes from. Test Generator simulates kicks (for Emulation). |
| Input Bands | 1 (Kick) / 2 (Kick + Snare) | 1 (Kick) | Analyse a second band together with the kick |
| Console Type | None / grandMA2 / grandMA3 | grandMA2 | Where the tempo goes. None = pins only. |
| Debug Print | None / Basic / Verbose | None | Verbose logs every onset and every command |

## Controls

### Control page – tempo overview

| Control | Type | Pin | |
|---|---|---|---|
| BPM | Float | out | Current tempo (0 = none yet) |
| BPM Text | Text | out | Tempo as text, `---` without tempo |
| Beat | LED | out | **Blinks on every beat** – keeps blinking in breakdowns |
| Downbeat | LED | out | Beat 1 of the bar |
| Bar 1–4 | LED | out | Position in the bar |
| Bar Position | Integer 1–4 | out | Position in the bar |
| Locked | LED | out | Tempo is stable and good enough to send |
| Detection State | Text | out | `Searching` / `Locked` / `Free Running` / `No Signal` / `Hold` / `Tap` / `Manual` |
| Confidence | Meter 0–100 % | out | How clearly one tempo wins |
| Input Level | Meter dB | out | Level seen by the detection |
| Tap | Trigger | in | Tap the tempo. The first tap is beat 1. With Auto on, the tap also tells the detection which octave you want. |
| Auto | Toggle | in/out | Off = manual: only Tap sets tempo and phase |
| Hold | Toggle | in/out | Freeze the tempo, send nothing new |
| Half / Double | Trigger | in | Tempo ×½ / ×2 (octave errors) |
| Resync | Trigger | in | The next kick becomes beat 1 |
| Shift Half Beat | Trigger | in | Beat sits on the offbeat → move it half a beat |
| Tempo Scale | Text | out | Current ×½/×2 factor |
| Send Enable | Toggle | in/out | Send the tempo to the console |
| Send Now | Trigger | in | Send the current tempo right away |
| Last Sent | Text | out | Last tempo sent |
| Status | Status | out | Console connection and input state |

### Setup page

| Control | | Default |
|---|---|---|
| Level In | dB input pin (Wired Pin source) | |
| Level In 2 | dB input pin, second band | |
| Meter Component / Meter Control | Named Component source | – / `meter.1` |
| Meter Component 2 / Meter Control 2 | Named Component source, second band | – / `meter.1` |
| Band 2 Weight | How much the second band counts | 50 % |
| Input Level 2 | Level of the second band (meter) | |
| BPM Min / BPM Max | Tempo range, at least one octave. Tempos outside are folded in (174 → 87). | 80 / 160 |
| Sensitivity | Higher = smaller level jumps count as kicks | 50 % |
| Min Confidence | Below this the tempo is not sent | 50 % |
| Beat Offset (ms) | Positive = beat outputs earlier (meter and network latency) | 0 |
| IP Address / Port | Console | – / 30000 (MA2), 8000 (MA3) |
| Username / Password | MA2 Telnet login | administrator / – |
| OSC Prefix | MA3 | – |
| Speed Master | Speed master number | 1 |
| Command Template | `{master}` and `{bpm}` are replaced | see above |
| Send Hysteresis | Minimum tempo change before a new value is sent (BPM) | 0.5 |
| Whole BPM | Send whole numbers (a new value only past ±0.7 BPM) | on |
| Connected / Logged In / Reconnect | MA2 connection | |

### Debug page

`Level Updates`, `Onset`, `Onset Strength`, `Onset Threshold`, `Onset Count`,
`Tempo Candidates` (strongest histogram peaks), `Last Command`, `Last Reply` (MA2),
`Last Error`. With the Test Generator: `Test BPM`, `Test Jitter`, `Test Dropout`,
`Test Update` (simulated meter interval) and `Test Breakdown`.

## Status

| Status | Meaning |
|---|---|
| OK | Console ready (MA2: logged in; MA3: socket open) or detection only |
| Compromised | Console OK, but no level updates / meter not found |
| Fault | MA2 login failed, MA3 UDP socket error |
| Missing | No IP address, or connection lost (retry with backoff 1 → 30 s) |
| Initializing | Connecting / logging in |

## Development

Sources in `src/`, offline tests in `test/harness.py` (mocked Q-SYS runtime, simulated
kicks, fake MA2 Telnet server, MA3 OSC packet check):

```
python3 source/tools/build.py sound2beat --check
python3 source/plugins/sound2beat/test/harness.py
```
