# levo AVL – Q-SYS Plugins

<p>
  <img src="https://img.shields.io/badge/Q--SYS_Designer-10.1%2B-00468C?style=flat-square&labelColor=191919" alt="Q-SYS Designer 10.1+">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-00468C?style=flat-square&labelColor=191919" alt="MIT License"></a>
  <img src="https://img.shields.io/badge/Built_with-Claude-00468C?style=flat-square&labelColor=191919" alt="Built with Claude">
  <a href="https://www.levo.de"><img src="https://img.shields.io/badge/levo_AVL-www.levo.de-FFB830?style=flat-square&labelColor=191919" alt="levo AVL"></a>
</p>

AI-assisted Q-SYS plugins by levo AVL – developed with Claude, tested on real Q-SYS hardware. Free and open source.

## Plugins

### 🎛️ grandMA2

Executors (faders, buttons), macros and commands via the MA2 web remote – **with feedback**.
Every value is a plain Q-SYS control with its own pin, ready for UCIs.

<a href="https://github.com/levoavl/qsys-plugins/releases/download/grandma2-v1.0/levo-grandma2.qplug"><img src="https://img.shields.io/badge/-%E2%AC%87_Download_v1.0-FFB830?style=for-the-badge" alt="Download grandMA2 plugin v1.0"></a>
<a href="grandMA2"><img src="https://img.shields.io/badge/-Manual-00468C?style=for-the-badge" alt="grandMA2 manual"></a>

Tested on grandMA2 onPC 3.9.60.91 · Q-SYS Designer 10.1

### 🎨 Advanced Color Picker

Presets, colour wheel, HSV, Kelvin and hex entry, user presets and fades. Outputs
RGB / RGBW / RGBA / RGBWA levels 0–255 and links both ways to console faders (e.g. the
grandMA2 plugin) and to the Q-SYS Color Picker. Colours survive UCI styles (CSS).

<a href="https://github.com/levoavl/qsys-plugins/releases/download/advancedcolorpicker-v1.0/levo-advancedcolorpicker.qplug"><img src="https://img.shields.io/badge/-%E2%AC%87_Download_v1.0-FFB830?style=for-the-badge" alt="Download Advanced Color Picker plugin v1.0"></a>
<a href="AdvancedColorPicker"><img src="https://img.shields.io/badge/-Manual-00468C?style=for-the-badge" alt="Advanced Color Picker manual"></a>

Tested on Q-SYS Designer 10.1 (Emulation, UCI) · with grandMA2 onPC 3.9.60.91

### 🥁 Beat Analyzer

Beat and BPM detection from the music running through Q-SYS (kick and optional snare
meters), with tempo sync to a **grandMA2 or grandMA3 speed master**. Beat LED, bar
position, tap, hold and ½/2× – the beat keeps running through breakdowns.

<a href="https://github.com/levoavl/qsys-plugins/releases/download/beatanalyzer-v1.0/levo-beatanalyzer.qplug"><img src="https://img.shields.io/badge/-%E2%AC%87_Download_v1.0-FFB830?style=for-the-badge" alt="Download Beat Analyzer plugin v1.0"></a>
<a href="BeatAnalyzer"><img src="https://img.shields.io/badge/-Manual-00468C?style=for-the-badge" alt="Beat Analyzer manual"></a>

Tested on Core 24f · Q-SYS Designer 10.1 · with grandMA2 3.9.60.91

> [!NOTE]
> **Coming soon:** Blackmagic ATEM (all models incl. multi-M/E) · Resolume Arena · Pharos

## Installation

1. Download the `.qplug` file with the yellow button above (older versions: [Releases](../../releases)).
2. Copy it to your Q-SYS plugin folder:
   `Documents\QSC\Q-SYS Designer\Plugins`
3. Restart Q-SYS Designer. The plugin appears in the Schematic Library under **Plugins → levo AVL**.

> [!TIP]
> Each plugin's **Manual** covers the device setup, properties, controls and pins.

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
