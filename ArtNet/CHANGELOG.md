# Changelog – Art-Net

All notable changes to this plugin are documented here.
Format: [Keep a Changelog](https://keepachangelog.com), versioning: `major.minor` (see [source/README.md](../source/README.md#versions)).

## [Unreleased]

## [1.0] – 2026-11-25

First release.

### Added
- Art-Net 4 (ArtDmx) **send and receive** for up to 4 universes. Property *Mode U1…U4*
  picks Send or Receive per universe; both can be mixed in one plugin.
- Channel range per universe (*Start Channel*, *Channels*). Channel controls are named by
  their DMX channel (`U1 Ch 100` …), one page per universe with a knob grid
  (8 / 10 / 16 knobs per row).
- Send: always the full 512 slots with a correct length field – channels outside the range
  are sent as 0, so receivers never see undefined data. Unicast per universe or broadcast,
  Net / Sub-Net / Universe per universe, Blackout.
- Send mode *Continuous* (default, constant stream at the refresh rate like a console) or
  *On Change* (on change, rate-limited, keep-alive once per second).
- Receive: read-only knobs with output pins, Data LED, source IP and name, packets per
  second; optional source IP filter, timeout and *On loss* Hold / Zero. Several sources on
  one universe: latest packet wins, Status warns. The plugin's own packets are ignored.
- Discovery: answers ArtPoll with one ArtPollReply per universe (node name from the Setup
  page, design name in the long name), unicast and to the subnet broadcast; announces
  itself at start-up and on a name change. Learns sender names from ArtPollReply and polls
  every 30 s when receiving.
- Everything runs on one socket on UDP 6454 (Art-Net source port), so receivers list the
  plugin as a single node. Without port 6454 the plugin still sends from an ephemeral port.
- No output in Emulation mode unless *Emulation TX* is switched on (avoids a second sender
  next to the Core).
- Status (OK / Compromised / Fault / Missing) combined over send and receive, Debug Print
  None / Basic / Verbose.
