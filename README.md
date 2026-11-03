# ITech32 MiSTer Core

This is a vibe coded, MAME-based Incredible Technologies ITech32 arcade core
for the MiSTer FPGA. It currently supports the 68000-based Time Killers and
BloodStorm boards (BloodStorm's board also runs Hard Yardage, Pairs, Hot Memory,
Pairs Redemption, and the early trackball versions of World Class Bowling) and the
68EC020-based Street Fighter: The Movie board (which also runs the later World
Class Bowling versions, World Class Bowling Deluxe, Shuffleshot, Golden Tee 3D
Golf through Golden Tee Classic, and the Power Up Baseball and Must Shoot TV
prototypes).

**This core is vibe coded based on MAME. Its built binaries and MRAs live in
the [Slop Core Repo](https://github.com/TheJesusFish/Slop-Core).**

## Hardware Reference

MAME 0.288 models the supported ITech32 boards as:

- Motorola 68000 main CPU at 12 MHz for Time Killers and the BloodStorm board.
- Motorola 68EC020 main CPU at 25 MHz for Street Fighter: The Movie.
- Motorola 6809 sound CPU at 16 MHz / 8, or 2 MHz.
- Ensoniq ES5506 sound device at 16 MHz.
- Incredible Technologies' framebuffer/blitter video hardware with a nominal
  8 MHz pixel clock and a software-programmable raster. The supported games use
  384 visible horizontal pixels and either 240- or 256-line display modes.
- Battery-backed RAM whose mapped size and role vary by board revision.

The core keeps the game-programmed raster while using the board-derived
approximately 54.75 Hz timing target established during hardware testing. MAME
is a behavioral reference here, not proof of original-board oscillator or
analog characteristics.

## Supported Games

| Game | Version | MAME set |
| --- | --- | --- |
| Street Fighter: The Movie | 1.12 | `sftm` |
| Time Killers | 1.32 | `timekill` |
| BloodStorm | 2.22 | `bloodstm` |
| Hard Yardage | 1.20 | `hardyard` |
| Pairs | 1.2 | `pairs` |
| Hot Memory | 1.2 (Germany) | `hotmemry` |
| Pairs Redemption | 1.0 | `pairsred` |
| World Class Bowling | 1.66 | `wcbowl` |
| World Class Bowling Deluxe | 2.00 | `wcbowldx` |
| Shuffleshot | 1.40 | `shufshot` |
| Golden Tee 3D Golf | 1.93N | `gt3d` |
| Golden Tee '97 | 1.30 | `gt97` |
| Golden Tee '98 | 1.10 | `gt98` |
| Golden Tee '99 | 1.00 | `gt99` |
| Golden Tee 2K | 1.00 | `gt2k` |
| Golden Tee Classic | 1.00 | `gtclassc` |
| Power Up Baseball | prototype | `pubball` |
| Must Shoot TV | prototype | `shoottv` |

Hard Yardage, the Pairs family, World Class Bowling, and Shuffleshot are new and
not yet hardware-tested; Golden Tee, Power Up Baseball, the tournament editions,
and Must Shoot TV have had a first test on a MiSTer. See [`docs/STATUS.md`](docs/STATUS.md). Hard Yardage supports four
players. The trackball games are played with a USB mouse or trackball, the left
analog stick, the d-pad, or the keyboard's arrow keys; the OSD's Trackball Speed
sets the gain. Golden Tee's Volume Up/Down cabinet buttons are player 1's B3/B4.

The Golden Tee and World Class Bowling tournament editions run with their
battery-backed M48T02 clock, which starts from the MiSTer's clock. As in MAME,
their tournament network (the modem) is not emulated: a first run reports
tournament storage and hardware errors, and the game may check for the modem
for about 50 seconds before attract mode. Open the OSD once to save the battery
data; later runs report only the disabled tournament hardware.

Must Shoot TV is a two-gun shooter. Player 1 aims with a USB mouse (left button
fires), the left stick, the d-pad, or the arrow keys, and fires with B1 (Left
Ctrl); player 2 uses the second controller. Crosshairs show where each gun
points (OSD: Crosshair); player 2's appears once that gun moves. For MiSTer light
guns that report through the analog stick, set the OSD's Light Gun Stick to
Absolute.

A keyboard works as controllers 1 and 2 with MAME's default keys. Player 1:
arrow keys, Left Ctrl, Left Alt, Space, Left Shift, Z and X for B1-B6, 1 for
Start and 5 for Coin. Player 2: R, F, D and G for up, down, left and right; A,
S, Q and W for B1-B4; 2 for Start and 6 for Coin.

The games share one `Arcade-ITech32.rbf`. Their MRA descriptors are in
[`releases/`](releases/). Seventy supported earlier, regional, and tournament revisions are
provided in [`releases/alternatives/`](releases/alternatives/); the exact support
boundary and validation status are recorded in
[`docs/CLONE_SUPPORT.md`](docs/CLONE_SUPPORT.md). Game ROMs are not included.

Board NVRAM is persistent for every supported board. On a first run with no saved
NVRAM, SFTM and BloodStorm can still show the authentic battery-backup warning;
acknowledge it once and open the MiSTer OSD to save the initialized contents.
The next launch restores that data. See [`docs/NVRAM.md`](docs/NVRAM.md).

## Building

Use **Quartus Prime Lite 17.0.2** with Cyclone V device support. Open
`Arcade-ITech32.qpf` and compile, or use the command line:

```sh
quartus_sh --flow compile Arcade-ITech32
```

The output is `output_files/Arcade-ITech32.rbf`. See
[`docs/BUILD.md`](docs/BUILD.md) for the Windows helper and build notes.

This repository contains source, build files, MRAs, documentation, and ROM-free
simulation sources. Compiled cores, game data, captures, and simulation results
are deliberately excluded. See [`sim/README.md`](sim/README.md) to run the tests.
The final qualification summary and remaining evidence limits are recorded in
[`docs/STATUS.md`](docs/STATUS.md).

## Source Notes

- MiSTer framework and top-level structure:
  [MiSTer-devel / Template_MiSTer](https://github.com/MiSTer-devel/Template_MiSTer)
  and the MiSTer framework contributors.

- MC68000-compatible CPU core:
  [Tobias Gubener / TG68K.C](https://github.com/TobiFlex/TG68K.C)

- MC6809-compatible sound CPU core:
  [Greg Miller / mc6809](https://github.com/cavnex/mc6809), through
  [Jotego / JTFRAME](https://github.com/jotego/jtcores)

- CRT sync adjustment and analog horizontal scaling:
  [Jotego / JTFRAME](https://github.com/jotego/jtcores) and
  [Martin Donlon / Arcade-IGSPGM_MiSTer](https://github.com/MiSTer-devel/Arcade-IGSPGM_MiSTer)

- Behavioral references:
  [MAME ITech32 driver](https://github.com/mamedev/mame/blob/mame0288/src/mame/itech/itech32.cpp),
  [MAME ITech32 video](https://github.com/mamedev/mame/blob/mame0288/src/mame/itech/itech32_v.cpp),
  [MAME ES5506](https://github.com/mamedev/mame/blob/mame0288/src/devices/sound/es5506.cpp),
  and the [Ensoniq OTTO ES5506 specification](https://gjcp.net/pdf/es5506.pdf)

- Menu and repository organization:
  [Arcade-Batsugun_MiSTer](https://github.com/TheJesusFish/Arcade-Batsugun_MiSTer)
  and [Arcade-Cave_MiSTer](https://github.com/MiSTer-devel/Arcade-Cave_MiSTer)

See [`CREDITS.md`](CREDITS.md) for detailed provenance and license notices.
The project is distributed under [GPLv3](LICENSE), with the third-party terms
and exceptions described there. Original copyright and license notices are
retained in the source.
