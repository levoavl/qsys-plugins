# Changelog – Art-Net

## 0.1 – unreleased

- First test build: Art-Net (ArtDmx) sender for 1–4 universes, 1–512 channels each.
- Always sends the full 512 slots (unused channels = 0), length field 512.
- Unicast per universe or broadcast, Net / Sub-Net / Universe per universe.
- Send on change, rate-limited to the refresh rate, keep-alive once per second.
- Blackout, Status, one page per universe, Setup and About page.
- No output in Emulation mode unless "Emulation TX" is switched on.
