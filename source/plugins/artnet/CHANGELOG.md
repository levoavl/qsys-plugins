# Changelog – Art-Net

## 0.6 – unreleased

- Receive mode: property "Mode U1..U4" (Send / Receive). Receive universes show the
  incoming values as read-only knobs with output pins, a Data LED, source IP and name,
  packets per second. Setup: optional source IP filter, timeout, on loss Hold / Zero.
  Several sources on one universe: latest wins, Status warns.
- Learns sender names from ArtPollReply and polls every 30 s when receiving.
- Channel range: property "Start Channel U1..U4", controls are named by their DMX
  channel (e.g. "U1 Ch 100"). Send: slots outside the range are 0.
- Note: changing Start Channel renames the channel controls (pins need rewiring).

## 0.5 – unreleased

- ArtPollReply now also goes to the subnet broadcast address (Art-Net 3 behaviour,
  some tools only listen for that) and carries the Core's MAC address.
- Unsolicited ArtPollReply at start-up and when the node name changes.
- ArtDmx is sent from UDP 6454 (the discovery socket) when available, so receivers
  no longer list the plugin twice (once as IP:port, once as node).

## 0.4 – unreleased

- Node name: answers ArtPoll with ArtPollReply (one per universe), so ArtNetominator,
  Resolume and consoles show the sender by name. "Node Name" on the Setup page.
  Needs UDP 6454 on the Core; "Discovery" on the Setup page shows whether it is active.
- Property "Send Mode": "On Change" (default, keep-alive 1/s) or "Continuous" (always
  at the refresh rate, for nodes that expect a constant stream).

## 0.3 – unreleased

- Fix: output stopped right after start-up on the Core – the send timer was only held
  by a local variable and got garbage collected. Kept reachable from a global now.

## 0.2 – unreleased

- Fix: no output on a Core without `Timer.Now()` – the start-up stopped before the
  send timer was started. Falls back to the timer's tick count now, timer starts first.
- Send errors now show in Status; "First packet sent" in the log (Debug Print Basic).

## 0.1 – unreleased

- First test build: Art-Net (ArtDmx) sender for 1–4 universes, 1–512 channels each.
- Always sends the full 512 slots (unused channels = 0), length field 512.
- Unicast per universe or broadcast, Net / Sub-Net / Universe per universe.
- Send on change, rate-limited to the refresh rate, keep-alive once per second.
- Blackout, Status, one page per universe, Setup and About page.
- No output in Emulation mode unless "Emulation TX" is switched on.
