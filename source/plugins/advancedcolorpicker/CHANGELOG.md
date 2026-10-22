# Changelog – Advanced Color Picker

All notable changes to this plugin are documented here.

## 0.1 – unreleased

- First version: fixed presets, colour wheel with brightness fader, HSV, Kelvin, hex entry,
  user presets with store
- Preset colours and colour wheel drawn as images with invisible touch buttons, so UCI
  styles (CSS) cannot override them; no CSS classes written at runtime, a class such as
  `levo-touch` is assigned on the UCI
- User presets: tap the colour itself, like the fixed presets
- Hue / Saturation / Brightness wire both ways to the Q-SYS Color Picker (echo suppression)
- Level outputs 0-255 for RGB, RGBW, RGBA and RGBWA with calibrated white/amber extraction
- Dimmer scaled into the outputs or as a separate output, fade time for discrete selections
- Two-way Console Link (percent, input + output pin) with echo suppression and hold time
