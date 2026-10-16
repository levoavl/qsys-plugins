# levo AVL – Q-SYS Plugins

AI-assisted Q-SYS plugins by levo AVL – developed with Claude, tested on real Q-SYS hardware. Free and open source.

## Plugins

| Plugin | Description | Version | Tested on | Download |
|---|---|---|---|---|
| [grandMA2](grandMA2) | Executors (faders, buttons), macros and commands via the MA2 web remote, with feedback | 1.0 | grandMA2 onPC 3.9.60.91 | [levo-grandma2.qplug](https://github.com/levoavl/qsys-plugins/releases/download/grandma2-v1.0/levo-grandma2.qplug) |

**Coming soon:** Blackmagic ATEM (all models incl. multi-M/E), Sound2Beat (beat / BPM
detection for lighting sync), Resolume Arena, Pharos.

## Installation

1. Download the `.qplug` file from the table above (older versions: [Releases](../../releases)).
2. Copy it to your Q-SYS plugin folder:
   `Documents\QSC\Q-SYS Designer\Plugins`
3. Restart Q-SYS Designer. The plugin appears in the Schematic Library under **Plugins → levo AVL**.

Click a plugin name for its manual: setup, properties, controls and pins.

## How these plugins are made

These plugins are developed with the help of AI (Claude by Anthropic) and then tested
and refined on real Q-SYS hardware by an AV integrator. Each plugin lists the hardware
and firmware it has been tested with. If you test a plugin on other devices, please
open an issue and let us know – positive reports are just as welcome as bugs.

Target environment: Q-SYS Designer 10.1 and later.

## Source code

Everything needed to build and modify the plugins is in [source/](source).

## Contributing

Issues and pull requests are welcome. Please label issues with the plugin they concern.

## Disclaimer

This project is not affiliated with, endorsed by, or sponsored by QSC, LLC (Q-SYS),
Blackmagic Design, MA Lighting, or any other manufacturer. All product names and
trademarks are the property of their respective owners.

The plugins are provided "as is", without warranty of any kind. See [LICENSE](LICENSE).

The levo AVL name and logo are trademarks of levo AVL and are not covered by the MIT
License – see [NOTICE.md](NOTICE.md).

## About

**levo AVL** · Printzstraße 4 · 76139 Karlsruhe · Germany
[www.levo.de](https://www.levo.de) · [hello@levo.de](mailto:hello@levo.de)

Author: levo AVL | Elias Jenny
