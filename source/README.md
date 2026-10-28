# Source code & development

This folder holds everything needed to build the plugins. If you only want to use a
plugin, go back to the [main page](../README.md) – you don't need anything in here.

```
source/
├── plugins/<name>/   Lua sources (src/) and tests (test/) of each plugin
│   └── _template/    Starting point for new plugins
├── shared/lua/       Code shared by all plugins (branding, WebSocket client, logos)
└── tools/            build.py (src → .qplug), preview.py (layout preview), gen_picker_images.py
```

Released plugins have a public folder in the repository root (e.g. `grandMA2/`) with the
built `.qplug`, README (user manual), CHANGELOG and third-party licenses.

All commands below are run from the repository root.

## Building

Requirements: Python 3.9+, optional `pip install lupa` for the Lua 5.3 syntax check.

```
python3 source/tools/build.py               # build all plugins
python3 source/tools/build.py grandma2      # build one plugin
python3 source/tools/build.py --check       # build + Lua 5.3 syntax check
```

The result `levo-<name>.qplug` lands in the plugin's public folder in the repository root
(e.g. `grandMA2/levo-grandma2.qplug`). Plugins that are not released yet have no public
folder; their `.qplug` is written next to the sources in `source/plugins/<name>/`.

### Test builds

```
python3 source/tools/build.py beatanalyzer --dev
```

Writes a test copy to `source/.dev-build/` (not committed) that carries a stamp like
`dev beatanalyzer a1b2c3d+ 22.10. 12:41` – branch, commit (`+` = uncommitted changes) and
build time. Q-SYS Designer shows it in the schematic block under the plugin name and on the
About page. File name and plugin Id stay the same, so a new test build simply replaces the
previous one in the plugin folder and you always see which state you are testing.
The version gets the build time as a third part (`1.0` → `1.0.2610281135`), because
Designer only offers to update a plugin in a design when the plugin folder holds a newer
version. Released files never carry a stamp and keep the two-part version – after testing
with dev builds, replace the plugin in the test design once with the released file.

The Advanced Color Picker draws its colours as embedded PNGs. After changing the presets
or the wheel, regenerate them: `python3 source/tools/gen_picker_images.py`.

### Layout preview

```
python3 source/tools/preview.py grandma2 --demo source/plugins/grandma2/test/preview_demo.json --out preview/
```

Renders every control page as PNG (needs `pip install lupa pillow`). Fonts and control
chrome are approximations - good for checking alignment and hierarchy, the final look
is always checked in Q-SYS Designer.

## Plugin source layout

Every plugin follows the same structure (see `source/plugins/_template`):

| File | Purpose |
|---|---|
| `plugin.lua` | Entry file: Q-SYS plugin functions, `#include`s everything else |
| `info.lua` | `PluginInfo` – name, version, unique Id (GUID), author |
| `properties.lua` | Properties shown in the Designer property panel |
| `rectify.lua` | Show/hide properties depending on other properties |
| `controls.lua` | Control definitions (names, types, pins) |
| `layout.lua` | Page layouts and graphics |
| `runtime.lua` | Code running on the Core (connection, parsing, logic) |

Includes use the QSC compiler syntax `--[[ #include "file.lua" ]]` and are looked up
in the plugin's `src/` folder first, then in `source/shared/lua/`.

## Shared code

- `shared/lua/levo_brand.lua` – colours, company info, header bar, background and About page.
  Header: `LevoBrand.Header(graphics, width, LevoBrand.PluginName(PluginInfo), CurrentPage)`
  shows the levo wordmark, the plugin name and the current page.
- `shared/lua/levo_websocket.lua` – WebSocket client (RFC 6455, text frames) on top of TcpSocket.
- `shared/lua/levo_assets.lua` – levo AVL logos as base64 PNG. Generated from the logo
  originals, which are not part of this repository; do not edit by hand. The logos are
  trademarks of levo AVL and not covered by the MIT License, see [NOTICE.md](../NOTICE.md).

## Starting a new plugin

1. Copy `source/plugins/_template` to `source/plugins/<name>` (lowercase, e.g. `atem`).
2. Generate a new GUID for `PluginInfo.Id` – never reuse an Id.
3. Set `PluginInfo.Name` to `"levo AVL~<Device Name>"`.
4. While in development, README and CHANGELOG drafts live in `source/plugins/<name>/`.

## Releases

### Versions

Plugins use two-part versions `major.minor` (e.g. `1.0`, `1.1`, `2.0`):

- **minor** (`1.0` → `1.1`): fixes and additions that keep existing designs working.
- **major** (`1.x` → `2.0`): changes that break existing designs – renamed or removed
  controls/pins, changed property meaning.

`PluginInfo.Version` and `PluginInfo.BuildVersion` carry the same value.

### Publishing a release

1. **First release only:** create the public folder in the repository root, named like the
   product (e.g. `ATEM/`, `BeatAnalyzer/` – matched case-insensitively against the source
   folder name) and move README.md and CHANGELOG.md there.
2. Update `CHANGELOG.md` and the version in `info.lua`, then build – the `.qplug` now lands
   in the public folder.
3. Tag `<name>-v<major>.<minor>` (e.g. `atem-v1.0`) and create a GitHub release with the
   `.qplug` attached.
4. Update the plugin's section in the main README (copy the grandMA2 section for a new
   plugin): version and link of the yellow Download button
   `https://github.com/levoavl/qsys-plugins/releases/download/<tag>/levo-<name>.qplug`,
   "Tested on" line, and remove the plugin from "Coming soon". Update the Download button
   at the top of the plugin's own README the same way.

`source/media/` holds images used by the READMEs (e.g. screenshots).
