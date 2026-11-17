# Changelog – ATEM Switcher

All notable changes to this plugin are documented here.
Format: [Keep a Changelog](https://keepachangelog.com), versioning: `major.minor` (see [source/README.md](../source/README.md#versions)).

## [Unreleased]

## [1.0] – 2026-11-17

First release.

### Added
- All ATEM models, including multi-M/E switchers, plus a Custom model: controls, pins and
  pages follow the model selected in the properties (model table generated from the
  Bitfocus Companion module). After connecting, the plugin checks the switcher against
  the selected model (status Compromised on a mismatch).
- ATEM protocol over UDP 9910: handshake, acknowledgements, resends, out-of-order and
  duplicate packets, watchdog, auto-reconnect with backoff (1 → 30 s, countdown in the
  status), command queue with merged T-bar / fader moves.
- M/E: preview / program buttons (tally colours, order as in ATEM Software Control) and
  combo boxes with the switcher's source names, Cut, Auto, T-bar that behaves like a
  hardware T-bar, Fade to Black, transition style and rate (`s:ff`), preview transition,
  next transition, upstream keyers on air.
- Downstream keyers: on air, tie, auto, rate.
- Aux outputs: combo with every aux source plus buttons (property "Aux Buttons", Auto by
  switcher size).
- Media players: stills (buttons + combo with media pool names), clips with play / loop /
  rewind on models with clips. Colour generators: hue, saturation, luma.
- Macros: run / stop buttons with names and running state, combo + run, stop, loop.
- Audio (Fairlight and classic mixer): level and On / AFV per input, master level and
  master AFV (follow Fade to Black).
- Streaming and recording: start / stop, status, duration, remaining recording time,
  ISO recording.
- Optional setup pages (off by default): keyer fill / key source and key type, DSK fill /
  key source, SuperSource boxes.
- Source names from the switcher as outputs, placed under the buttons; optional device
  short names as button legends.

### Known limitations
- Continue after a macro user wait is not supported.
- Tested on the ATEM Mini Extreme only. Multi-M/E models and the classic audio mixer are
  implemented from the protocol but not yet tested on hardware – reports are welcome.
