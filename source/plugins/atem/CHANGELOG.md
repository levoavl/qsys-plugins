# Changelog – ATEM Switcher

All notable changes to this plugin are documented here.
Format: [Keep a Changelog](https://keepachangelog.com), versioning: `major.minor` (see [source/README.md](../source/README.md#versions)).

## [Unreleased]

Development versions: 0.1 connection + M/E, 0.2 keyers, aux, SuperSource.

### Added
- Model property with all ATEM models (generated from the Companion model table) and a
  Custom model; controls, pins and pages follow the selected model.
- ATEM protocol over UDP 9910: handshake, acknowledgements, resends, out-of-order and
  duplicate packets, watchdog and auto-reconnect with backoff (1 → 30 s), command queue.
- Model check after connecting (status Compromised on mismatch).
- Per M/E: program / preview (buttons + combo boxes with the switcher's source names),
  Cut, Auto, T-bar, Fade to Black with rate, transition style and rate, preview
  transition, next transition (background / keys), keyers on air.
- Source names from the switcher as outputs; optional device names as button legends.
- Preview bus above program, tally colours (preview green, program red), source order as in
  ATEM Software Control (inputs first).
- Rates as `s:ff` at the switcher's frame rate, like ATEM Software Control.
- Reconnect countdown in the status text.
- Downstream keyers: on air, tie, auto, rate, fill / key source.
- Upstream keyers: fill / key source, key type.
- Aux outputs: combo with every aux source plus buttons (property "Aux Buttons"), own
  page(s), 8 aux per page.
- SuperSource: box enable and source (combo + buttons).
- Source names from the switcher placed directly under the program buttons / grids.
- Keyer setup (now with key type) and SuperSource on optional pages, off by default.
- "Aux Buttons" = Auto: button count follows the switcher size.
- T-bar behaves like a hardware T-bar (no drop after Auto, direction flips).
