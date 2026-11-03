# Current validated baseline

This document is the concise handoff for the source baseline prepared on
2026-09-02. Raw captures, generated reports, ROM-derived data, and temporary
build trees are intentionally not part of this repository.

## Included functionality

- Street Fighter: The Movie v1.12, Time Killers v1.32, and BloodStorm v2.22
  share one production core and have release MRAs under `releases/`. Hard
  Yardage, Pairs, Hot Memory, Pairs Redemption, World Class Bowling, World
  Class Bowling Deluxe, and Shuffleshot were added on 2026-11-02 and await
  hardware testing (see the three 2026-11-02 test-build sections).
- Thirty-five compatible revisions of those games have checksum-pinned MRAs under
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

> Superseded on 2026-11-02: the `MAME Timings` option, its second source PLL,
> clock selector, transport PLL, and mode controller were removed (see
> "Audit changes test build"). The core again uses one free-running
> 47.727273 MHz `pll`. This section is kept as history.

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

## Audit changes test build (2026-11-02)

Changes from a code audit against the MiSTer framework and Cyclone V HDL
practice notes:

- NVRAM upload race fixed. The TG68 adapter can still present a cycle it
  captured just before an upload freezes the CPUs. The main bus previously
  served such an access from the host's address (CPU reads in Time Killers and
  BloodStorm work RAM; SFTM NVRAM writes landed at the host address). New CPU
  accesses now wait for the transfer, accepted ones drain with their own
  address, and only then does the host receive the RAM (`nvram_host_ready`).
  The new `nvram-upload-race` test fails on the previous design.
- Analog RGB is forced black outside the board's valid picture window. The
  framework mixer does not blank RGB, so blanking previously carried palette
  colour, which affects CRT and upscaler black-level clamping. HDMI is unaffected.
- The framework scanline effect is disabled while the analog H-scaler is
  active, so alternate 15 kHz picture lines are no longer dimmed.
- The SFTM `MAME Timings` option and its runtime clock switch were removed. The
  core uses one free-running `pll`, constrained by the stock `sys_top.sdc`;
  PLL use fell from 5 to 3 of 6.
- Menu: settings version `v,1` (saved options reset once to defaults), Stereo
  Mix, Audio Gain 1x/2x/4x (saturating, default 1x is unchanged), and Pause
  When OSD Open (default Off). The dead `D0` aspect-ratio prefix was removed.
- The SDC documents the six-clock pixel budget behind the palette multicycle
  exception; `itech32_board.sv` asserts it in simulation.
- Maintainability: the DDR service is split into the scheduler plus
  `itech32_ddr_main_cache`, `itech32_ddr_grom_cache`, and
  `itech32_ddr_sound_cache`; write-only served/cache bookkeeping for the three
  fronts was removed. Diagnostic video branches, hardware probes, and the debug
  hub hook were removed; the fallback raster moved to its own file.

Verification:

- The original tree passed 95 runs across 46 testbenches. The final tree passes
  94 runs across 45 testbenches (two clock-switch tests retired, one race test
  added); the graphics-queue sensitivity check rejects both mutants. A full
  `emu` Verilator lint is clean.
- Quartus Prime Lite 17.0.2 clean build: worst setup slack `+0.292 ns` (HDMI
  domain), core clock `+0.829 ns`; worst hold `+0.057 ns`; TNS `0` for setup
  and hold at all four corners; recovery, removal, and minimum pulse width
  positive; zero unconstrained clocks. The post-fit HDMI check reports
  physical C5.
- Utilization is 25,310 ALMs (60%), 32,298 registers, 3,434,992 block-memory
  bits (61%), 444 RAM blocks (80%), 48 DSP blocks (43%), and 3 of 6 PLLs.
  The RBF SHA-256 is
  `16C13CBF7E173A4F747DC5D8CC7D4514C5952665869324334363F0C283941B60`.
- Not yet hardware-qualified. Priorities: an NVRAM save while playing each
  board family, analog black level on a CRT or upscaler, the H-scaler with a
  scanline effect selected, Direct Video, and the new menu options. `sys/` is
  unchanged.

## Board-profile refactor (2026-11-02)

Preparation for further `itech32.cpp` games, with no intended behavior change:

- `rtl/itech32/itech32_profile_pkg.sv` defines `board_profile_t` and the
  selector table. The MRA selector byte (unchanged: 00 SFTM, 01 Time Killers,
  02 BloodStorm) is decoded and registered once; blocks read independent fields
  (MAME address-map family, input layout, palette format, framebuffer planes,
  sound-board revision and bank count, NVRAM layout, protection address,
  graphics-ROM pages, sample-bank slots) instead of game-identity bits. See
  "Board Profiles" in `docs/DEVELOPMENT.md`.
- Equivalence: a differential simulation ran the previous main bus, input
  mapper, and graphics-ROM front beside the profile versions on identical random
  traffic for all three boards, including board switches, NVRAM transfers, and
  page-boundary GROM addresses: 1,440,047 compared cycles, zero mismatches. A
  deliberately wrong profile is rejected immediately. The sample-bank map was
  compared exhaustively. The full suite passes 94 runs across 45 testbenches.
- Quartus Prime Lite 17.0.2 (fitter seed 7): worst setup slack `+0.065 ns` (HDMI
  scaler), core clock `+1.178 ns`, worst hold `+0.064 ns`, TNS `0` at all four
  corners; post-fit HDMI check reports physical C5. The default seed placed the
  framework `ascal` vertical filter `-0.153 ns` short at the slow -40 C corner
  while the core clock was `+1.138 ns`. Utilization is 25,318 ALMs, 32,322
  registers, 444 RAM blocks, 48 DSP blocks, and 3 of 6 PLLs. RBF SHA-256:
  `2984ADF51A6241D6B21E29388ADC504EA08B011C49B5B7EE16047BF2C716A85D`.

## Phase-1 games test build (2026-11-02)

Adds the MAME `bloodstm`-machine joystick games, which share BloodStorm's board
profile and differ only in controls:

- Hard Yardage v1.20 (`hardyard`, selector `03`) with alternatives v1.10 and
  v1.00. Four players: MiSTer joysticks 3 and 4 now reach the board's P3/P4
  ports. Players 3/4 have no coin input, as in MAME.
- Pairs V1.2 (`pairs`), Hot Memory V1.2 (`hotmemry`), and Pairs Redemption V1.0
  (`pairsred`), all selector `04`, with alternatives Pairs V1 and Hot Memory
  V1.1. One button per player. The redemption ticket dispenser is not read back
  by MAME's input ports, and the core matches that.
- Button names and DIP meanings come from the Strata operator manuals
  ([Hard Yardage](https://www.arcade-museum.com/manuals-videogames/N/NFLHardYardage.pdf),
  [Pairs](https://www.arcade-museum.com/manuals-videogames/P/Pairs.pdf)). Their
  JAMMA tables put Hard Yardage Pass/Jump on button 1 and Select on button 2
  (players 3/4 likewise on their own harnesses), and Pairs Select on button 1
  with button 2 unwired, matching MAME's port bits. Both manuals' SW1 tables
  agree with the MRA switch polarity. Pairs also has an operator "Control
  Configurations" menu (one or two joysticks/Start buttons) that must match how
  it is played. The Pairs Redemption control layout is assumed from Pairs.
- No graphics-ROM wrap change was needed: MAME wraps at the declared `0x880000`
  region for every one of these sets, so all use BloodStorm's 17 pages.
- Each new ROM stream was compared byte-for-byte with the regions that MAME
  0.288's `ROM_START` definitions load, at the core's DDR offsets (BloodStorm
  passed as a control), and every MD5 reproduces from merged archives.
- Simulation: new `family-inputs` bench (216 checks against a table written from
  MAME's port definitions; rejects two planted wiring mutations). The full suite
  passes 95 runs across 46 testbenches. Full-design lint reports no new
  core-side warnings.
- Quartus Prime Lite 17.0.2 (default seed): worst setup slack `+0.376 ns` (HDMI
  scaler), core clock `+1.271 ns`, worst hold `+0.111 ns`, TNS `0` at all four
  corners; post-fit HDMI check reports physical C5. Utilization is 25,259 ALMs,
  32,336 registers, 444 RAM blocks, 48 DSP blocks, and 3 of 6 PLLs. RBF SHA-256:
  `88DADE563985EF070B653404856B2AF70244080B35044C3D2983B313A67787C3`.
- Not yet hardware-tested. This RBF also carries every audit change above, so it
  supersedes the audit test build for hardware testing.

## World Class Bowling test build (2026-11-02)

Adds the 68000 World Class Bowling sets, the first trackball game:

- World Class Bowling v1.5 (`wcbowl15`, selector `05`) with alternatives v1.4,
  v1.3, v1.2, v1.1, v1.0, and v1.3J (`wcbowl13j`, selector `06`, second
  trackball port). They use BloodStorm's board plus MAME `init_wcbowl`'s ROM-board
  additions: trackball ports, the security PIC result word, and zero reads from
  `0x578000-0x57ffff`. SFTM's existing zero window now comes from the same
  profile field.
- Trackball: board-side 4-bit X/Y counters read as `(Y << 4) | X`; a USB mouse or
  trackball, the left stick, or the d-pad drives them through a saturating
  accumulator released at one count per 1600 Hz tick. The OSD's Trackball Speed
  (25/50/100/200%) sets the gain. The release rate comes from a MAME 0.288
  measurement: the game reads the port in eight pairs per frame with a longest
  gap of about 3.5 ms. Main_MiSTer's PS/2 packets carry +Y forward. See
  "Trackballs" in `docs/DEVELOPMENT.md`.
- Button names come from the operator
  [manual](https://www.arcade-museum.com/manuals-videogames/W/World_Class_Bowling__1995__Incredible_Technologies.pdf):
  Hook Left (JAMMA button 1) and Hook Right (button 2) add spin, and the
  trackball rolls the ball. The service menus are also trackball-driven.
- All seven ROM streams match MAME's loaded regions byte-for-byte and reproduce
  their MD5s from the merged archive.
- Simulation: new `trackball` bench (directed cases plus a 200,000-cycle
  randomized reference-model run) and `wcbowl-bus` bench; `family-inputs` and
  `game-selector` extended. The full suite passes 97 runs across 48 testbenches.
  Five planted mutations (mouse X sign, release rate, PIC word half, zero window
  scope, OSD mouse gating) were each rejected. Full-design lint reports no new
  core-side warnings.
- Quartus Prime Lite 17.0.2 (default seed): worst setup slack `+0.532 ns` (HDMI
  scaler), core clock `+1.262 ns`, worst hold `+0.091 ns`, TNS `0` at all four
  corners; post-fit HDMI check reports physical C5. Utilization is 25,693 ALMs,
  32,525 registers, 444 RAM blocks, 48 DSP blocks, and 3 of 6 PLLs. RBF SHA-256:
  `533BE1C9F7B78B2A03F5A89DA961BE8352450379E79A501C8E2C71A607FD9834`.
- Not yet hardware-tested. This RBF supersedes the phase-1 test build.

## 68EC020 trackball games test build (2026-11-02)

Adds the trackball games on the SFTM board (MAME `sftm` machine with
`init_shuffle_bowl_common`):

- World Class Bowling v1.66 (`wcbowl`, selector `07`; now the release
  descriptor) with alternatives v1.65, v1.61, and v1.6; World Class Bowling
  Deluxe v2.00 (`wcbowldx`, `08`); Shuffleshot v1.40 (`shufshot`, `09`) with
  alternatives v1.39, v1.38, v1.37, and v1.35. The 68000 v1.5 descriptor moved
  to `_World Class Bowling`.
- Board additions: trackball ports at `0x180800`/`0x181000` with the byte in
  both halves of the 32-bit word, the itech020 protection byte at `0x1116`
  (v1.6x) or `0x111a`, a six-bank sound ROM, samples in ES5506 banks 0 and 1,
  and a 16-page GROM for Shuffleshot. Buttons follow MAME: Hook Left/Right for
  bowling, Zoom/Wax for Shuffleshot.
- MAME 0.288 measurements decided the design: both families read the trackball
  in eight pairs per frame (longest gap about 3.8 ms), so the existing 1600 Hz
  release needs no change. Neither touches the serial DUART at `0x680800`; both
  read the zero-reading `0x578000` window; Shuffleshot probes the absent
  tournament timekeeper at `0x681000-0x6817ff`, which reads zero here as in MAME.
- All ten new ROM streams match MAME's loaded regions byte-for-byte; the full
  release set of 45 descriptors reproduces its MD5s.
- Simulation: `game-selector`, `wcbowl-bus`, and `family-inputs` extended (both
  trackball maps, both protection addresses, the new input layout, SFTM
  unchanged). The full suite passes 97 runs across 48 testbenches; four planted
  mutations were each rejected. Lint reports no new core-side warnings.
- Quartus Prime Lite 17.0.2 (default seed): worst setup slack `+0.281 ns` (HDMI
  scaler), core clock `+0.861 ns` (worst paths inside the TG68 ALU), worst hold
  `+0.116 ns`, TNS `0` at all four corners; post-fit HDMI check reports
  physical C5. Utilization is 25,789 ALMs, 32,542 registers, 444 RAM blocks,
  48 DSP blocks, and 3 of 6 PLLs. RBF SHA-256:
  `7B423347EEB9DAE8E758E67AC8466E3E3DA183ED264699C93DC908C5F9038548`.
- Not yet hardware-tested. This RBF supersedes the World Class Bowling build.

## Reproduction

Use Quartus Prime Lite 17.0.2 as described in `docs/BUILD.md`. Run the ROM-free
checks from `sim/README.md`, then inspect all configured setup and hold corners.
Do not reintroduce development counters, alternate video paths, generated
captures, or private experiment artifacts into a production build.
