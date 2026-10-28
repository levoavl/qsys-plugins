# Changelog – Advanced Color Picker

All notable changes to this plugin are documented here.
Format: [Keep a Changelog](https://keepachangelog.com), versioning: `major.minor` (see [source/README.md](../source/README.md#versions)).

## [Unreleased]

## [1.1] – 2026-10-28

### Fixed
- Console Link: the console state is taken over on start without moving the faders
  (Q-SYS fires no event for values the wired pins already hold). All Link inputs at 0
  (nothing wired, fresh instance) keep the picker's colour.
- A wired Q-SYS Color Picker no longer writes its stale state to the console on start; it
  is ignored for 2 s and then gets the current colour.
- Console moves no longer lag or get overwritten: the hold times only start when new values
  were really sent, and a picker report that gives the same colour is ignored.

## [1.0] – 2026-10-26

First release.

### Added
- Colour selection: 16 fixed presets, colour wheel (hue × saturation) with brightness fader,
  Hue / Saturation / Brightness faders, Kelvin (1000–10000 K), hex entry (`#RRGGBB`,
  `#RGB`, `0xRRGGBB`) and R / G / B entry.
- User presets (0–32): tap to recall, *Store* + tap to save; kept with the design and over
  Core restarts.
- Fade time (0–10 s) for presets, wheel, user presets and hex.
- Level outputs 0–255 for RGB, RGBW, RGBA and RGBWA; white / amber extraction with
  calibrated LED colours, *Subtract* (accurate) or *Add* (brighter).
- Dimmer, scaled into the outputs or as a separate output.
- Two-way Console Link (percent, input + output pin), e.g. to the grandMA2 plugin faders,
  with echo suppression and hold time.
- Two-way link to the Q-SYS Color Picker via Hue / Saturation / Brightness.
- Preset colours and colour wheel are images with invisible touch buttons, so UCI styles
  (CSS) cannot override them. The plugin writes no CSS class, colour or legend on buttons
  at runtime.
