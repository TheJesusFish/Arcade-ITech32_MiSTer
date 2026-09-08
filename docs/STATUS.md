# Current validated baseline

This document is the concise handoff for the source baseline prepared on
2026-09-02. Raw captures, generated reports, ROM-derived data, and temporary
build trees are intentionally not part of this repository.

## Included functionality

- Street Fighter: The Movie v1.12, Time Killers v1.32, and BloodStorm v2.22
  share one production core and have release MRAs under `releases/`.
- Seventeen compatible revisions of those games have checksum-pinned MRAs under
  `releases/alternatives/`. Every SFTM revision uses the hardware-qualified
  selector `00` and `0x7a6a` protection address. See
  `docs/CLONE_SUPPORT.md` for the complete inventory, reproduction commands,
  and hardware-validation boundary.
- The actual battery-backed storage used by each board profile is persistent:
  128 KiB for SFTM, the complete 64 KiB work RAM for BloodStorm, and the low
  16 KiB of work RAM for Time Killers. Save uploads pause both CPUs and sound
  service while the raster remains live. See `docs/NVRAM.md` for the transfer,
  byte-order, and first-run contract.
- Release MRAs expose only game-applicable switches. The obsolete Video Sync
  switches are gone, Service Mode is last in each MRA, and the duplicate
  momentary Service item has been removed from the core menu.
- The working video transport, PLL configuration, Direct Video boundary,
  scaler boundary, CPU/bus ordering, blitter scheduling, sound caches, and
  game-specific initialization are present in this tree.
- The ES5506 implementation retains signed internal filter guard bits while
  preserving the documented signed 18-bit host-register view. Exact arithmetic
  policy and its evidence boundary are recorded in `docs/SOUND.md`.
- Street Fighter: The Movie reads in the otherwise-unpopulated `0x578000`-
  `0x57ffff` window return zero, matching the MAME 0.288 behavioral model and
  the game's signed-offset control flow. Time Killers and BloodStorm retain the
  board's normal all-ones open-bus response at those physical addresses. The
  read acknowledgement schedule is unchanged.
- Simulation-only verification remains under `sim/` and is absent from
  `files.qip`. No ROM, capture, trace, generated result, or compiled core is
  required from a prior development tree to rebuild the project.

## Current build qualification

- The current clean production RBF has SHA-256
  `384AC9F25DFA36B6EE85C758B2899E46FF1672803C02D7EBA99128D0A33DF6FB`.
  It is source-, checksum-, simulation-, build-, and normal-scaler
  hardware-qualified.
- All 90 ROM-free Verilator runs across 43 testbenches passed. The coverage
  checks all board selectors and SFTM fallback behavior, NVRAM protocol and dirty
  transitions, one-shot save requests, profile size bounds, host/native byte
  order, and round trips through the reused RAM ports. The complete existing
  video, blitter, bus, and ES5506 suites also remain green.
- Four-corner production timing is positive. Worst setup slack is `+0.367 ns`,
  setup TNS is `0 ns`, and worst hold slack is `+0.106 ns`; recovery, removal,
  and minimum-pulse checks are also positive. The 47.727273 MHz core clock has
  at least `+1.091 ns` setup slack at the two slow corners.
- Fitter utilization is 25,056 ALMs (60%), 32,151 registers, 3,442,752
  block-memory bits (61%), 446 RAM blocks (81%), and 48 DSP blocks (43%). The
  host path reuses the existing work/NVRAM ports: no extra RAM blocks or DSPs
  were introduced.
- No file under `sys/` was edited in the feature batch qualified below. Those
  results therefore describe the previous framework snapshot and remain the
  hardware-tested baseline for comparison with the newer framework test build.

## Template framework refresh test build (2026-09-03)

- `sys/` was replaced wholesale and verified byte-for-byte against
  [Template_MiSTer commit `3ea1134cf05d62c2b1db30362277a823d739ced2`](https://github.com/MiSTer-devel/Template_MiSTer/commit/3ea1134cf05d62c2b1db30362277a823d739ced2).
- A clean Quartus Prime Lite 17.0.2 build completed successfully from empty
  `db/`, `incremental_db/`, and `output_files/` directories. The test RBF SHA-256
  is `F92E02E475F93F0242D2572A5929EDCED4526719BEFF6A848954BB5186D3ED3E`.
- The 47.727273 MHz core clock passes setup with `+0.227 ns` worst slack. All
  reported hold, recovery, removal, and minimum-pulse checks pass. The framework
  HDMI clock has the only setup miss: `-0.673 ns` WNS and `-4.482 ns` design-wide
  TNS at the slow 1100 mV, -40 C corner. This is inside the project's accepted
  `-2 ns` WNS / `-50 ns` TNS test-build ceiling, but is worse than the fully
  positive hardware-qualified baseline and should be treated as a test concern.
- Fitter utilization is 25,271 ALMs (60%), 32,261 registers, 3,442,752
  block-memory bits (61%), 446 RAM blocks (81%), and 48 DSP blocks (43%).
- This framework-refresh RBF has not yet been qualified on MiSTer hardware.

## Hardware qualification

- SFTM v1.10 and v1.11 both booted with coherent video using selector `00` and
  the common `0x7a6a` protection profile. Their saved-image sequence matched
  MAME 0.288: after initial bookkeeping and one additional warning/save cycle,
  the next cold MRA reload entered attract mode without the battery warning.
- BloodStorm v2.22 saved its complete 64 KiB work RAM and reported
  `SYSTEM STATUS OK` after reload. The one-shot OSD-edge request completed once
  and did not enter the former repeated-save loop while gameplay continued to
  modify work RAM.
- Time Killers v1.32 created and reloaded its 16 KiB image. All three parent
  games exposed only their applicable DIP switches, with Service Mode last, and
  had no separate momentary Service entry in the top-level menu.
- Hardware checks used the normal MiSTer scaler. This feature batch did not
  alter video transport or clocks, but the exact final RBF has not been
  requalified on a physical Direct Video receiver.

## Remaining evidence limits

- The manufacturer ES5506 documentation specifies the host-visible history
  width but does not prove the physical internal filter width. Signed guard-bit
  retention is the best compatibility-supported interpretation, not a claim of
  transistor-level or board-measured equivalence.
- MAME is a behavioral reference, not proof of original-board clocks or analog
  characteristics. Direct board measurements would still improve oscillator,
  analog-output, and collision-phase accuracy.
- No schematic or board measurement currently proves the electrical value of
  an unpopulated SFTM `0x578xxx` read. Returning zero is a compatibility choice
  supported by MAME 0.288 and the observed program control flow, not a claim
  about the physical open-bus level.
- Normal scaler and external-scaler behavior were exercised during development.
  The selector and NVRAM work does not alter the video transport, clocks, or
  framework logic, and upload deliberately leaves the raster running. Direct
  Video still needs requalification with the current RBF on an appropriate
  physical receiver.
- TimeQuest reports that the overall design is not fully constrained, an
  existing project/framework boundary. All explicitly reported clock domains
  pass setup and hold at every configured corner.

## SFTM timing investigation (2026-09-07)

- A MAME 0.288 memory-tap trace of SFTM v1.12 observed the stable tuple
  `HTOTAL=0x1fc`, `HSYNC=0x1d6`, `HBSTART=0x1a4`, `HBEND=0x24`,
  `VTOTAL=0x11e`, `VSYNC=0x119`, `VBSTART=0x103`, and `VBEND=0x3` after
  initialization: exactly 508x286 with a 384x256 visible window. It remained
  unchanged for 300 emulated seconds spanning the attract loop. No 262-line
  configuration appeared. The reusable probe is
  `sim/mame/sftm_video_timing_trace.lua`; generated logs remain outside the
  source tree.
- The local research pack's explicit 59.7612 Hz measurement belongs to later
  P/N 1083 Golden Tee 3D / World Class Bowling / Shuffleshot hardware, not an
  SFTM PCB. The rejected 508x262 experiment also produced severe horizontal
  slicing and stepped regions on three MiSTers, independent of
  `vsync_adjust`. That mode and its tests have therefore been removed.
- SFTM alone now exposes `MAME Timings: Off/On`. Both settings retain the ROM's
  native 508x286 geometry, blanking, sync positions, and 384x256 visible image.
  Off uses the existing 47.727273 MHz common carrier with exact divide-by-six
  pixels (about 54.750 Hz). On selects a 48 MHz common carrier with the same
  exact divider (about 55.063 Hz), matching MAME's live post-CRTC
  `frame_period` rather than its pre-configuration static XML metadata.
  Time Killers and BloodStorm cannot see or select the option.
- The selected clock remains one common source for the core, scanout, MiSTer
  scaler, analog/Y-C path, Direct Video, and DDR interface. Two continuously
  running source PLLs feed a dedicated Cyclone V clock selector while reset is
  asserted. A unity-ratio transport PLL then presents a direct PLL output to
  MiSTer's downstream HDMI/analog clock selectors. The core is released only
  after the selected transport PLL has relocked. There is still one video path.
- CPU and sound-board clock enables select a matching accumulator denominator,
  preserving their 25, 12, 16, 8, and 2 MHz target rates when the carrier
  changes. Only the exact divide-by-six pixel rate changes. A focused Verilator
  test covers each carrier and the reset-protected mode-control sequence.
- A separate accuracy-neutral optimization reduces each scanout read from 128
  to 97 64-bit words. The active 384-pixel window plus the maximum three-pixel
  qword-alignment offset needs at most 387 pixels, so the removed words were
  never displayed. This lowers scanout DDR traffic by 24.2% without changing
  pixel selection or arbitration priority.
- The Quartus 17.0.2 test build completed at 2026-09-07 17:09. All four corners
  have zero setup and hold TNS. Worst setup slack is `+0.111 ns`; worst hold
  slack is `+0.099 ns`. At the slowest corner, the 48 MHz transport domain is
  `+0.385 ns` and the 47.727273 MHz transport domain is `+0.514 ns`. Utilization
  is 25,385 ALMs (61%), 32,303 registers, 446 RAM blocks (81%), 48 DSP blocks
  (43%), and 5 of 6 PLLs. TimeQuest finds zero unconstrained clocks. Its
  not-fully-constrained notice is limited to existing template external I/O
  paths. The RBF SHA-256 is
  `6A1E8B0285EBE36A96B54179FE909EC578796CFFE57D9F3436423BE56F795E44`.
- This is a test mode, not a claim that an SFTM PCB used an 8 MHz pixel clock.
  The 48 MHz setting reproduces MAME's live cadence. Establishing which cadence
  is physically accurate still requires a traceable measurement from SFTM P/N
  1064 hardware. `sys/` is unchanged.

### Warm timing-switch correction

- Hardware testing of the first selectable-timing RBF found that the menu item
  changed state but the loaded game remained black afterward. The failure was
  deterministic in the reset topology: switching modes reset the unity
  transport PLL, its lock output participated in `memory_reset`, and the DDR
  service consequently cleared the retained `rom_loaded` flag. The framework
  menu could remain visible while the board stayed in its unloaded fallback.
- A deliberate mode change is now a staged warm transition. The controller
  first resets the board while the old carrier is still running, waits for an
  explicit DDR-idle acknowledgement, stops the transport PLL, switches the
  source, waits for stable relock, and only then releases the board. Loader,
  DIP, NVRAM, and game-selector state are retained across that intentional lock
  gap. Source-PLL failure or an unexpected transport-lock loss remains a cold
  memory boundary and still clears those states.
- The DDR acknowledgement cannot assert while an accepted physical read or
  write is active. The focused Verilator suite covers startup lock gating, two
  complete timing-mode round trips, preservation across planned relock,
  unexpected lock loss, source loss, and quiescing during an accepted scanout
  burst. The existing clock-enable and video-timing checks also pass.
- The corrective Quartus 17.0.2 RBF has SHA-256
  `FAF9C6B769489181E39E4989B5422899BCA891BA08889E6C70262DFEEAB42930`.
  Its design-wide worst setup result is `-0.301 ns` WNS and `-2.380 ns` TNS on
  the existing template HDMI domain at the slow 1100 mV, -40 C corner. The 48
  MHz MAME transport is `-0.211 ns` WNS / `-0.361 ns` TNS and the 47.727273 MHz
  board transport is `-0.082 ns` WNS / `-0.082 ns` TNS at that corner. The
  transport critical path is the unchanged TG68 register file, not the new mode
  controller. Worst hold slack is `+0.118 ns`; recovery, removal, and minimum
  pulse checks are positive. These small, sparse misses are within the accepted
  `-2 ns` WNS / `-50 ns` TNS test-build ceiling, but are a regression from the
  fully positive first selectable-timing fit and remain a qualification concern.
- Utilization is 25,288 ALMs (60%), 32,435 registers, 3,435,312 block-memory
  bits (61%), 446 RAM blocks (81%), 48 DSP blocks (43%), and 5 of 6 PLLs.
  `sys/` remains unchanged. The warm-switch behavior still requires physical
  qualification on both normal scaler and Direct Video outputs.

## Reproduction

Use Quartus Prime Lite 17.0.2 as described in `docs/BUILD.md`. Run the ROM-free
checks from `sim/README.md`, then inspect all configured setup and hold corners.
Do not reintroduce development counters, alternate video paths, generated
captures, or private experiment artifacts into a production build.
