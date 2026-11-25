# Art-Net – Q-SYS Plugin

Send and receive DMX over **Art-Net** from Q-SYS. Up to four universes, each one either
sending or receiving, with a free channel range per universe. Every channel is a plain
Q-SYS knob with its own pin – wire it to faders, gains, logic or UCIs.

Part of [levo AVL Q-SYS Plugins](../README.md).

<a href="https://github.com/levoavl/qsys-plugins/releases/download/artnet-v1.0/levo-artnet.qplug"><img src="https://img.shields.io/badge/-%E2%AC%87_Download_v1.0-FFB830?style=for-the-badge" alt="Download Art-Net plugin v1.0"></a>
<a href="CHANGELOG.md"><img src="https://img.shields.io/badge/-Changelog-00468C?style=for-the-badge" alt="Changelog"></a>

The plugin always sends the full 512 slots with a correct length field. Channels outside
the configured range go out as 0 – no flickering on unused channels.

## Tested on

| Q-SYS | Counterpart | Result |
|---|---|---|
| Core 24f · Designer 10.1 | Resolume Arena, ArtNetominator | ✅ send (unicast, broadcast, 2 universes), receive incl. timeout, node names in both directions |

If you run the plugin with other consoles or nodes, please open an issue – positive
reports are just as welcome as bugs.

## Network

- Art-Net uses **UDP 6454**. The Core needs a network interface in the same subnet as the
  nodes / consoles (typically 2.x.x.x, 10.x.x.x or the venue network).
- Prefer **unicast** to the node's IP address. Use broadcast only where a node requires it,
  and then a subnet broadcast address (e.g. `2.255.255.255`) rather than `255.255.255.255`.
- The plugin takes UDP 6454 for receiving and discovery. A port can normally be held by
  only one plugin instance per Core, so use one instance with several universes rather
  than several instances. A second instance still sends, but cannot receive
  (Setup → *Discovery* shows it).

## Emulation mode

In Emulation the plugin runs on your laptop and would send real Art-Net packets – next to
the Core running the same design, that means two senders on one universe and flickering
fixtures. So **nothing is sent in Emulation** until you switch on *Emulation TX* on the
Setup page. Receiving works in Emulation as usual.

## Properties

| Property | Values | Default | |
|---|---|---|---|
| Universe Count | 1–4 | 1 | One page per universe |
| Mode U1…U4 | Send / Receive | Send | Direction of each universe |
| Start Channel U1…U4 | 1–512 | 1 | First DMX channel of the range |
| Channels U1…U4 | 1–512 | 32 | Number of channels (clamped at channel 512) |
| Knobs per Row | 8 / 10 / 16 | 10 | Layout of the universe pages |
| Refresh Rate (Hz) | 1–44 | 30 | Maximum packet rate per send universe |
| Send Mode | Continuous / On Change | Continuous | *Continuous*: constant stream at the refresh rate, like a console. *On Change*: only on changes, plus a keep-alive once per second. |
| Debug Print | None / Basic / Verbose | None | Basic: start-up, sources, errors. Verbose: every packet. |

> [!WARNING]
> Channel controls are named by their DMX channel (`U1 Ch 100` …). Changing *Start Channel*
> renames them – wired pins and UCI controls of the old names are lost.

## Pages

**Universe 1…4 – Send:** Blackout, Status, info line (target, Port-Address, range) and one
knob per channel (0–255).

**Universe 1…4 – Receive:** Data LED, Status, info line (source IP and name, packets per
second, Port-Address) and one read-only knob per channel showing the incoming value.

**Setup:**

| Setting | |
|---|---|
| Target IP (send) | Unicast destination of this universe |
| Source filter (receive) | Optional: only accept packets from this IP |
| Net / Sub-Net / Universe | Art-Net Port-Address of the universe (0–127 / 0–15 / 0–15) |
| Enable (send) | Output on / off – off by default, nothing is sent until switched on |
| Timeout s (receive) | Seconds without packets until the Data LED goes off (default 3) |
| On loss (receive) | *Hold*: keep the last values. *Zero*: set all channels to 0 |
| Broadcast / Address | All send universes go to the broadcast address instead of their Target IP |
| Node Name | Name shown in consoles and tools (ArtPollReply), default "Q-SYS Art-Net" |
| Discovery | Shows whether UDP 6454 is available (receive and node name) |
| Emulation TX | Send while the design runs in Emulation |

> [!NOTE]
> Port-Address numbering: some tools count universes from 0, others from 1. The info
> line shows the plugin's value as `Port-Address n (Net:Sub-Net:Universe)`.

## Controls and pins

| Control | Pin | |
|---|---|---|
| `U<n> Ch <ch>` | in/out (send) · out (receive) | Channel value 0–255 |
| `U<n> Target IP`, `U<n> Enable` | in/out | Send universes |
| `U<n> Source Filter`, `U<n> Timeout`, `U<n> On Loss` | in/out | Receive universes |
| `U<n> Data` | out | LED: data received within the timeout |
| `U<n> Net`, `U<n> SubNet`, `U<n> Universe` | in/out | Port-Address |
| `U<n> Info` | out | Info line as text |
| `Blackout` | in/out | All send universes output 0 |
| `Broadcast`, `Broadcast Address`, `Node Name` | in/out | |
| `Discovery` | out | Text |
| `Status` | out | OK / Compromised / Fault / Missing |

## Status

| Status | Meaning |
|---|---|
| OK | Sending and / or receiving as configured |
| Compromised | Blackout active, Emulation without TX, or several sources on one receive universe |
| Missing | No send universe enabled (send only), or no data on a receive universe |
| Fault | Invalid target IP, socket error, or UDP 6454 not available for receiving |

## Limitations

- Several senders on one receive universe are not merged: the latest packet wins (no HTP).
- Art-Net only: no sACN (E1.31), no RDM, no ArtSync.
- Sending a channel range always sends the other channels of the universe as 0. Two senders
  that share one universe need a node or console that merges them.

## License

MIT License – see [LICENSE](../LICENSE). Art-Net™ Designed by and Copyright Artistic Licence
Engineering Ltd. Not affiliated with or endorsed by QSC, LLC or Artistic Licence.
