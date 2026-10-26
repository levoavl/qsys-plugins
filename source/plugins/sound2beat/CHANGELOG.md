# Changelog – Sound2Beat

All notable changes to this plugin are documented here.
Format: [Keep a Changelog](https://keepachangelog.com), versioning: `major.minor` (see [source/README.md](../../README.md#versions)).

## [Unreleased]

## [0.2] – 2026-10-26

### Added
- Property `Input Bands`: optional second band (e.g. snare 150–400 Hz) via `Level In 2` or
  `Meter Component 2` / `Meter Control 2`, analysed together with the kick
  (weighted sum of both level rises, `Band 2 Weight`). Locks pop and syncopated
  patterns far more reliably. Test generator adds a snare on 2 and 4.
- `Whole BPM` toggle (default on): tempo is sent as a whole number; a new value only when
  the tempo is more than 0.7 BPM away from the last one, so 127.5 does not flap. The big
  BPM display follows the toggle; the BPM pin and the Debug page keep the exact value.

### Changed
- Beat vs. offbeat: the half of the beat grid with clearly more onsets is the beat;
  loudness only decides when both halves have about as many (kick vs. offbeat bass).

## [0.1] – 2026-10-16

First test version.

### Added
- Level input from a wired meter pin, a named meter component, or a built-in test
  generator (simulated kicks with jitter, dropouts, breakdown and meter update rate –
  for Emulation without audio).
- Onset detection in the dB domain with an adaptive threshold (volume independent).
- Tempo from a decaying interval histogram, folded into the BPM range by octaves; vote
  width follows the measured meter update rate.
- Tempo refinement by linear regression over the last 32 onsets on a half-beat grid
  (folded tempos and offbeat bass stay exact); the beat moves to the louder half of the
  grid (kick vs. offbeat bass).
- Beat clock that keeps running through breakdowns, with Beat, Downbeat, Bar 1–4 and
  Bar Position outputs, and a Beat Offset to compensate latency.
- Tap (first tap = beat 1, also hints the octave to the detection), Auto/Manual, Hold,
  ×½ / ×2, Resync, Shift Half Beat.
- Tempo output to grandMA2 (Telnet, login, reconnect with backoff 1 → 30 s) and grandMA3
  (OSC `/cmd`, optional prefix) with a command template, send hysteresis and rate limit.
  Only locked and regression-refined tempos are sent.
- Pages Control (tempo overview), Setup, Debug, About.
- Offline test harness `test/harness.py`.
