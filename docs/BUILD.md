# Building the Core

## Requirements

- Intel Quartus Prime Lite **17.0.2**, including Cyclone V device support.
- A local checkout containing `rtl/`, `sys/`, and the root project files.
- No game ROMs are required to synthesize the core.

The target is the DE10-Nano's `5CSEBA6U23I7`, and the Quartus top entity is
`sys_top`. The user-core wrapper is `emu` in `Arcade-ITech32.sv`.
All required HDL is vendored; there are no Git submodules or generated CPU models
to fetch before building. Quartus itself supplies its device and megafunction
libraries.

`.gitattributes` preserves the bundled source bytes instead of silently changing
upstream line endings during checkout. `scripts/quartus_vendor.tcl` locates the
required vendor library relative to the running Quartus installation.

## Standard Build

Open `Arcade-ITech32.qpf` in Quartus and choose **Start Compilation**, or run this
from the repository root with the Quartus tools on `PATH`:

```sh
quartus_sh --flow compile Arcade-ITech32
```

The resulting bitstream is `output_files/Arcade-ITech32.rbf`. Check the fitter and
TimeQuest reports before distributing a newly built core; a completed assembler
alone does not establish timing closure.

`sys/build_id.tcl` is the standard pre-flow hook. A full flow regenerates the build
date in `build_id.v` and the local JTAG programming description `jtag.cdf`.
The checked-in build stamp also permits direct-stage builds. Updating the date,
using another Quartus version, or rerouting can change the RBF bytes; source
availability is not a claim of bit-for-bit reproducibility across tool versions.

## Windows Direct-Stage Helper

`scripts/build_quartus.ps1` runs map, fit, assembly, and timing analysis while
preventing the individual stages from exporting rewritten project settings.
It accepts the Quartus installation root and an optional temporary drive mapping;
see its parameter block for the available stage and path options.

```powershell
./scripts/build_quartus.ps1 -QuartusRoot C:/intelFPGA_lite/17.0/quartus -WhatIf
./scripts/build_quartus.ps1 -QuartusRoot C:/intelFPGA_lite/17.0/quartus -SubstDrive Q:
```

`-WhatIf` checks the planned invocation without building or creating a drive
mapping. Omit `-SubstDrive` when the normal checkout path works. Tool discovery
also supports `QUARTUS_ROOTDIR`, `QUARTUS_ROOTDIR_OVERRIDE`, or the tools on
`PATH`. `-Flow` selects `compile`, `map`, `fit`, `asm`, or `sta`.

Prefer a short checkout path without spaces when using older Quartus releases.
The optional drive mapping is useful when Quartus 17's Tcl mishandles a Windows
known-folder path. Do not reuse a drive letter already assigned to another task.

## Source Layout

| Path | Purpose |
| --- | --- |
| `Arcade-ITech32.sv` | MiSTer `emu` wrapper and menu |
| `files.qip` | Core RTL and constraint input list |
| `rtl/itech32/` | CPU interface, board, blitter, inputs, and video |
| `rtl/memory/` | DDR memory service |
| `rtl/sound/` | Sound board, 6809 interface, VIA, and ES5506 behavior |
| `rtl/cpu/tg68k/` | Vendored TG68K.C source |
| `rtl/pll*` | Core PLL source and Quartus metadata |
| `sys/` | Bundled MiSTer framework snapshot |
| `releases/*.mra` | Game selection and ROM assembly descriptors, not ROM data |
| `sim/` | ROM-free simulation sources and runner |

Add core HDL through `files.qip`, not the Quartus IDE's file list. Keep the
bundled `sys/` and PLL sources intact when reproducing this implementation.
The legacy Quartus-13 project and abandoned save-state experiments are not part
of this source distribution.

## Upload Hygiene

Run `python scripts/check_source_tree.py` and review Git's proposed additions.
The repository must not contain game archives, ROM-derived fixtures, compiled
cores, build databases, logs, captures, or actual simulation results. Generate
test output under ignored `sim/build/` or outside the checkout. `.gitignore`
helps prevent accidents but does not make previously tracked data safe.

Install a locally built RBF with the matching MRA descriptors on your MiSTer.
Supply any required game ROMs separately; they are not part of the source tree.
