# Changelog – Advanced Color Picker

All notable changes to this plugin are documented here.
Format: [Keep a Changelog](https://keepachangelog.com), versioning: `major.minor` (see [source/README.md](../source/README.md#versions)).

## [Unreleased]

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
  with echo suppression and hold time. On start the console state is taken over without
  moving the faders.
- Two-way link to the Q-SYS Color Picker via Hue / Saturation / Brightness.
- Preset colours and colour wheel are images with invisible touch buttons, so UCI styles
  (CSS) cannot override them. The plugin writes no CSS class, colour or legend on buttons
  at runtime.
