# Changelog – Menu Bar

All notable changes to this plugin are documented here.
Format: [Keep a Changelog](https://keepachangelog.com), versioning: `major.minor` (see [source/README.md](../source/README.md#versions)).

## [Unreleased]

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
