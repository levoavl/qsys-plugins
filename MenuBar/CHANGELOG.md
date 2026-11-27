# Changelog – Menu Bar

All notable changes to this plugin are documented here.
Format: [Keep a Changelog](https://keepachangelog.com), versioning: `major.minor` (see [source/README.md](../source/README.md#versions)).

## [Unreleased]

## [1.1] – 2026-11-27

### Added
- 15 more icons for sources and inputs: settings_input_component, settings_input_svideo, instant_mix,
  input_circle, media_output, cable, bluetooth, airplay, queue_music, library_music, album,
  playlist_play, podcasts, speaker_group.

### Changed
- Item Width up to 4000 px and Item Height up to 2000 px (was 1000 / 600), for wide panels like iPads.

## [1.0] – 2026-11-25

First release (test versions 0.1–0.9).

### Added
- Menu bar for UCIs drawn as SVG – fixed look that UCI styles (CSS) cannot override.
  2–12 items, horizontal or vertical, item size via properties.
- Animated indicator: None, Line, Pill or Block, sliding from item to item (ease in/out,
  adjustable time). The indicator is clipped to the item shape, so it never sticks out over
  rounded corners or into gaps.
- Live setup page with preview: content (text, icon, icon + text), font, sizes, bold active
  label, filled active icon, item gap, corner radius (bar ends or each item), dividers
  (hidden under pill / block), indicator margins left/right and top/bottom, colours.
- Material Symbols (Rounded) icons by Google, selectable per item.
- Navigation per item: UCI page (`Uci.SetPage`) on one or more panels and/or several layers
  (`Uci.SetLayerVisibility`), combinable. Panel discovery via Script Access, automatic
  fallback from component code names to Inventory names.
- Pins: menu buttons, active LEDs, active menu number, lock, labels, status.
