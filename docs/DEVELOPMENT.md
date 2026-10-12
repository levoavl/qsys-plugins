# Development

## Building

Requirements: Python 3.9+, optional `pip install lupa` for the Lua 5.3 syntax check.

```
python3 tools/build.py            # build all plugins
python3 tools/build.py atem       # build one plugin
python3 tools/build.py --check    # build + Lua 5.3 syntax check
```

The result lands in `plugins/<name>/dist/levo-<name>.qplug`.

## Plugin source layout

Every plugin follows the same structure (see `plugins/_template`):

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
in the plugin's `src/` folder first, then in `shared/lua/`.

## Shared code

- `shared/lua/levo_brand.lua` – colours, company info, header bar, background and About page.
- `shared/lua/levo_assets.lua` – levo AVL logos as base64 PNG. Generated from the logo
  originals, which are not part of this repository; do not edit by hand. The logos are
  trademarks of levo AVL and not covered by the MIT License, see `shared/NOTICE.md`.

## Starting a new plugin

1. Copy `plugins/_template` to `plugins/<name>`.
2. Generate a new GUID for `PluginInfo.Id` – never reuse an Id.
3. Set `PluginInfo.Name` to `"levo AVL~<Device Name>"`.

## Releases

Tag per plugin: `<name>-v<major>.<minor>.<patch>`, e.g. `atem-v1.0.0`, and attach the
`.qplug` from `dist/` to the GitHub release. Update the plugin's `CHANGELOG.md` first.
