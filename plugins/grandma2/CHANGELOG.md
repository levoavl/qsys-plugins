# Changelog – grandMA2

All notable changes to this plugin are documented here.
Format: [Keep a Changelog](https://keepachangelog.com), versioning: [SemVer](https://semver.org).

## [Unreleased]

## [0.1.0] – 2026-10-16

### Added
- Connection to the grandMA2 web remote (WebSocket, TCP 80) with login, session keepalive,
  watchdog and auto-reconnect with backoff (1 → 30 s).
- Fader slots: level (control + feedback, no jumping while touched), executor buttons 1–3
  with labels from the console, name, cue, function, Active / Fading / State / Progress.
- Button slots (executors 101+): press/release, name, cue, function, Active / Fading / State /
  Progress.
- State detection Off / Fading In / On / Fading Out from the fade progress; Active turns off
  immediately when an executor starts fading out. Optimistic update on button press.
- Executor assignment per slot as text field `page.exec` (e.g. `1.101`) directly in the slot,
  also changeable at runtime via pin.
- Macro slots ("Go Macro n") and free command slots, plus `Command TX` string input.
- Slot counts as properties (0–64 faders, 0–128 buttons, 0–64 macros, 0–32 commands),
  poll interval property, Debug Print (None / Basic / Verbose, Verbose logs state changes).
- Shared WebSocket client `shared/lua/levo_websocket.lua`.
- Offline test harness `test/harness.py` (mocked Q-SYS runtime + fake console).
