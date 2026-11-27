# Menu Bar – Q-SYS Plugin

An animated menu bar for Q-SYS UCIs. The bar is drawn by the plugin as SVG, so it looks the
same on every touch panel and **UCI styles (CSS) cannot change it**. When you press a menu
item, the indicator (pill, block or line) slides over to it. Each item can switch the UCI
page, show and hide layers, or both.

Part of [levo AVL Q-SYS Plugins](../README.md).

<a href="https://github.com/levoavl/qsys-plugins/releases/download/menubar-v1.1/levo-menubar.qplug"><img src="https://img.shields.io/badge/-%E2%AC%87_Download_v1.1-FFB830?style=for-the-badge" alt="Download Menu Bar plugin v1.1"></a>
<a href="CHANGELOG.md"><img src="https://img.shields.io/badge/-Changelog-00468C?style=for-the-badge" alt="Changelog"></a>

![Menu Bar with default settings](menubar-default.png)

## Tested on

| Q-SYS | Panel | Result |
|---|---|---|
| Designer 10.1 (Emulation) | UCI Viewer app on iPad | ✅ page switching, several layers per item, animation, live setup |

If you run the plugin on other panels, please open an issue – positive reports are just as
welcome as bugs.

## Quick start

1. Drag **Menu Bar** from *Plugins → levo AVL* into the schematic. Set the number of items,
   orientation and item size in the properties.
2. Open the plugin, page **Control**: select all `Menu` buttons and copy them onto your UCI
   (ideally onto a shared layer that sits on every page). Keep their size and position.
3. Page **Setup**: set label and icon per item and adjust the look – the preview at the top
   updates live.
4. Navigation – fill in what you use, leave the rest empty:
   - **Pages:** add your touch panels / UCI viewers to *Panels* (see below) and enter a
     *Page* name per item.
   - **Layers:** enter the *UCI Name* and per item the *Page* and its *Layers*
     (comma-separated, e.g. `1-1, 1-2`).

## Navigation

When an item is pressed, the plugin

- switches every panel in *Panels* to the item's *Page* (`Uci.SetPage`), if *Panels* is set
  and the item has a page, and
- shows the item's *Layers* on its *Page* and hides the layers of all other items
  (`Uci.SetLayerVisibility` on *UCI Name*). A layer listed by the selected item stays
  visible even if another item lists it too.

Both can be combined. If you only use layers, leave *Panels* empty and enter the same page
for every item (e.g. `1`). Layers always need a page, because Q-SYS addresses a layer by UCI,
page and layer name.

### Panels

`Uci.SetPage` needs the panel's **Inventory name** (e.g. `UCI_Viewer_1`), not the code name
of its status component. The *Add Panel* list shows all touch panels and UCI viewers whose
status component has **Script Access** enabled – pick one to add it to *Panels*. You can
also type names, separated by commas.

If a name is not found, the plugin tries a few variants (it strips prefixes like
`UCI_Viewer_` and swaps `-` and `_`), so `UCI_Viewer_UCI_Viewer-1` finds `UCI_Viewer_1`.
With *Debug Print* on *Basic* the log shows which name worked.

> [!IMPORTANT]
> **UCI Viewer app:** connect the app as **UCI Viewer** (the UCI Viewer device from the
> design's Inventory), not by picking a UCI by name. Only then is the app a panel that
> `Uci.SetPage` can switch – opened by UCI name, page changes do nothing and only layers
> switch.

## Properties

These define the number and size of the controls, so they cannot change at runtime.
Everything else is on the Setup page.

| Property | Values | Default | |
|---|---|---|---|
| Menu Count | 2–12 | 4 | Number of menu items |
| Orientation | Horizontal / Vertical | Horizontal | |
| Item Width | 30–4000 | 200 | Button width in px |
| Item Height | 30–2000 | 60 | Button height in px |
| Debug Print | None / Basic / Verbose | None | Basic: start-up, panels, errors. Verbose: every page / layer call. |

## Pages

### Control

The menu bar at its real size, plus status and outputs. The buttons overlap by 2 px – Q-SYS
leaves a thin edge around a button's graphic and the overlap hides it. Use *Item Gap* for
visible gaps.

### Setup

All settings are live and saved with the design.

| Section | Setting | |
|---|---|---|
| Content | Content | Text, Icon or Icon + Text |
| | Font, Font Size, Bold Active | Label font; the active label can be bold |
| | Icon Size, Fill Active Icon | Icon size in px; the active icon can use the filled variant |
| Shape | Item Gap | Visible gap between the items, drawn inside the graphic |
| | Width / Height Correction | Enlarges the graphic if a panel draws it smaller than the button (normally 0) |
| | Corner Radius, Rounded Corners | Round only the bar ends or each item |
| | Dividers, Divider Length %, Divider Width | Lines between the items; hidden where a pill or block covers them |
| Indicator | Style | None, Line, Pill or Block (block follows the item's corners) |
| | Line Position, Line Size | Line at the bottom / right or top / left edge |
| | Margin Left/Right, Margin Top/Bottom | Distance of the indicator from the item edges |
| | Animation ms | Slide time, 0 = jump |
| Colours | Background, Text, Active Text, Indicator, Divider | Hex (`#00468C`) or `none` |
| Pages | Panels, Add Panel | See [Panels](#panels) |
| Layers | UCI Name, Transition | Layer transition: none, fade, left, right, top, bottom |
| Menu items | Label, Icon, Page, Layers | Per item |

The icons are [Material Symbols](https://fonts.google.com/icons) (Rounded) by Google – a
selection of common AV symbols is built in.

## Controls and pins

| Control | Pin | |
|---|---|---|
| `Menu 1…n` | in / out | The menu buttons for the UCI. Pressing one selects it; true while selected. |
| `Menu Active 1…n` | out | LED, true while the item is selected |
| `Active Menu` | in / out | Number of the selected item. Set it to select an item from logic. |
| `Lock` | in / out | While on, the bar is dimmed and ignores presses |
| `Label 1…n` | in / out | Item labels, e.g. for multi-language UCIs |
| `Status` | out | OK, or the last navigation error (panel / page / layer not found) |

## Licence

MIT – see [LICENSE](../LICENSE). The icons are © Google, Apache License 2.0 – see
[THIRD_PARTY_LICENSE_MaterialSymbols.md](THIRD_PARTY_LICENSE_MaterialSymbols.md).
