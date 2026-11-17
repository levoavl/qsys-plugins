# Changelog – ATEM Switcher

All notable changes to this plugin are documented here.
Format: [Keep a Changelog](https://keepachangelog.com), versioning: `major.minor` (see [source/README.md](../source/README.md#versions)).

## [Unreleased]

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
