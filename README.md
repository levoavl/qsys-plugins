# levo AVL – Q-SYS Plugins

AI-assisted Q-SYS plugins by levo AVL – developed with Claude, tested on real Q-SYS hardware. Free and open source.

## Plugins

| Plugin | Description | Status | Tested on |
|---|---|---|---|
| [Blackmagic ATEM](plugins/atem) | Control of ATEM switchers incl. multi-M/E models | 🚧 In development | ATEM Mini Extreme |
| [grandMA2](plugins/grandma2) | Executors (faders, buttons), macros and commands via the MA2 web remote, with feedback | ✅ v1.0 | grandMA2 onPC 3.9.60.91 |
| [Sound2Beat](plugins/sound2beat) | Beat / BPM detection inside Q-SYS for lighting sync | 🚧 In development | – |

Planned: Resolume Arena, Pharos.

## Installation

1. Download the `.qplug` file of the plugin you need from the [Releases](../../releases) page.
2. Copy it to your Q-SYS plugin folder:
   `Documents\QSC\Q-SYS Designer\Plugins`
3. Restart Q-SYS Designer. The plugin appears in the Schematic Library under **Plugins → levo AVL**.

Each plugin has its own README with properties, controls and pin descriptions.

## How these plugins are made

These plugins are developed with the help of AI (Claude by Anthropic) and then tested
and refined on real Q-SYS hardware by an AV integrator. Each plugin lists the hardware
and firmware it has been tested with. If you test a plugin on other devices, please
open an issue and let us know – positive reports are just as welcome as bugs.

Target environment: Q-SYS Designer 10.1 and later.

## Repository structure

```
shared/      Shared assets and Lua helpers (branding, about page, connection handling)
tools/       Build tooling (src → .qplug), see docs/DEVELOPMENT.md
plugins/     One folder per plugin, each with src/, dist/, README.md and CHANGELOG.md
```

Releases are tagged per plugin, e.g. `grandma2-v1.0`.

## Contributing

Issues and pull requests are welcome. Please label issues with the plugin they concern.

## Disclaimer

This project is not affiliated with, endorsed by, or sponsored by QSC, LLC (Q-SYS),
Blackmagic Design, MA Lighting, or any other manufacturer. All product names and
trademarks are the property of their respective owners.

The plugins are provided "as is", without warranty of any kind. See [LICENSE](LICENSE).

The levo AVL name and logo are trademarks of levo AVL and are not covered by the MIT
License – see [shared/NOTICE.md](shared/NOTICE.md).

## About

**levo AVL** · Printzstraße 4 · 76139 Karlsruhe · Germany
[www.levo.de](https://www.levo.de) · [hello@levo.de](mailto:hello@levo.de)

Author: levo AVL | Elias Jenny
