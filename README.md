# ITech32 MiSTer Core

This is a vibe coded, MAME-based Incredible Technologies ITech32 arcade core
for the MiSTer FPGA. It currently supports the 68000-based Time Killers and
BloodStorm boards and the 68EC020-based Street Fighter: The Movie board.

**This core is vibe coded based on MAME. Its built binaries and MRAs live in
the [Slop Core Repo](https://github.com/TheJesusFish/Slop-Core).**

## Hardware Reference

MAME 0.288 models the supported ITech32 boards as:

- Motorola 68000 main CPU at 12 MHz for Time Killers and BloodStorm.
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

The three games share one `Arcade-ITech32.rbf`. Their MRA descriptors are in
[`releases/`](releases/). Seventeen supported earlier and regional revisions are
provided in [`releases/alternatives/`](releases/alternatives/); the exact support
boundary and validation status are recorded in
[`docs/CLONE_SUPPORT.md`](docs/CLONE_SUPPORT.md). Game ROMs are not included.

Board NVRAM is persistent for all three families. On a first run with no saved
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
