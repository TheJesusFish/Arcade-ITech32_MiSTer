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

## Golden Tee test build (2026-11-02)

Adds the non-tournament Golden Tee sets (MAME `sftm` machine with
`init_gt_common`):

- Releases: Golden Tee 3D Golf v1.93N (`gt3d`), '97 v1.30 (`gt97`), '98 v1.10
  (`gt98`), '99 v1.00 (`gt99`), 2K v1.00 (`gt2k`) and Classic v1.00
  (`gtclassc`), with 21 alternatives. Selectors: `0a` single board, `0b`/`0c`
  the alternate-protection 2K and Classic sets, `0d` the one-trackball "S"
  board, `0e`/`0f` the three-tier Golden Tee 3D short and long ROM boards.
- Board features: two 1024-row framebuffer planes (Time Killers' two planes
  have 512 rows; the plane height is now its own profile field), the base
  `itech020_map` colour latches, the protection byte at `0x112f` and the fixed
  `0x680000` results of `init_gt2kp`/`init_gtclasscp`, a 12-page GROM, four
  trackball wirings (including 8-bit counters on the GT 3D short board),
  volume buttons on player 1's B3/B4, and a third ES5506 sample slot (C) at
  the top of the GROM window for the three-tier boards' bank 3. The itech020
  GROM bank bits now follow MAME's mask, so only SFTM uses them.
- Trackball counts now leave at a per-board rate, measured in MAME 0.288: the
  single and "S" boards read sixteen times per frame (gaps up to 1.57 ms,
  3600 Hz), the GT 3D long board eight (3.2 ms, 1600 Hz), and the short board
  reads its 8-bit counters every second or third frame (50 ms, 2200 Hz).
  Stick and d-pad speed are unchanged, as is bowling and Shuffleshot behavior.
- A MAME I/O census of six boards found no access to the serial DUART or the
  tournament timekeeper; protection is read only at `0x680002` (0x00 and 0x80
  on the alternate-protection sets, as modeled); the GROM bank bits are never
  set.
- The descriptors, releases included, are generated from a table emitted from
  MAME's ROM listing. All 27 streams match MAME's loaded regions byte-for-byte;
  all 72 repository descriptors reproduce their MD5s.
- Simulation: new `golden-tee-bus` and `scanout-planes` (MAME `screen_update`
  for one and two planes of both heights) benches; `trackball`,
  `family-inputs`, `game-selector`, `wcbowl-bus` and `ddr` (slot C) extended.
  The full suite passes 99 runs across 50 testbenches; four planted mutations
  (old plane height, unswapped colour latches, swapped GT 3D long trackball
  bytes, one release rate) were each rejected. Lint reports no new core-side
  warnings.
- Quartus Prime Lite 17.0.2 (default seed): worst setup slack `+0.461 ns` (HDMI
  scaler), core clock `+1.223 ns`, worst hold `+0.116 ns`, TNS `0` at all four
  corners; post-fit HDMI check reports physical C5. Utilization is 25,883 ALMs,
  32,606 registers, 444 RAM blocks, 48 DSP blocks, and 3 of 6 PLLs. RBF
  SHA-256: `92D0A9F13B1C5B3B7A131BE8098BF13FAD749DBECEF04C790189519806C9E68C`.
- Not yet hardware-tested. This RBF supersedes the 68EC020 trackball build.
  The tournament editions need the M48T02 timekeeper and are not supported.

### Hardware findings and fixes

The first hardware test (user report, then the USB-1 test MiSTer with the
capture card) found no sound in any Golden Tee game and a hang at the first
course (attract mode froze on a tip screen just before its gameplay demo).

- No sound: Golden Tee writes sound commands as a word at `0x480000`; the core
  decoded only the byte address `0x480001` (SFTM's byte write), so every
  command was dropped. The itech020 decode now takes the dword and gates on
  byte lane `+1`, as MAME's handler does. Hardware: Golden Tee '97's attract
  audio went from -91 dB (silence) to -26 dB mean.
- Hang: an on-chip recorder of the main CPU's bus (scratch diagnostic build,
  read over JTAG) showed the CPU spinning at `0x805042` on the blitter command
  queue's read pointer (`0x1994`) with the blitter idle and no interrupt
  pending. Golden Tee's queue code waits on video status bits 7:6 (busy/ready)
  before switching its blitter interrupt off; MAME, whose blits are instant,
  always reads "ready", and so did the core, whose blits take time. A queued
  blit's completion was then wiped by the polled loop's acknowledge and the
  queue deadlocked. The Golden Tee profile now reports live busy/ready bits.
- Ruled out on the way, by replay or simulation: all 61,113 blitter commands
  of Golden Tee '97's first 1,300 frames (captured from MAME, replayed through
  the core's blitter) complete; program-ROM reads above 512 KiB (Golden Tee is
  the first 2 MiB program) return correct data; the scanline-interrupt chain
  matches MAME (lines 1, 16 ... 224, 239; register 3 reads 0xef).
- Hardware check of the fixed core on the USB-1 test MiSTer (virtual gamepad
  through uinput, capture card for video and audio): Golden Tee '97 v1.30 runs
  its whole attract cycle including the gameplay demo, takes coins, selects
  players and Pine Creek, and plays a swing to the second stroke. Golden Tee
  3D v1.8 (short ROM board, sample slot C) and v1.92L (long ROM board), '97
  v1.21S ("S" board), '99, and the alternate-protection 2K and Classic sets
  each boot and run their attract demos with sound. The trackball responds to
  the stick and d-pad; a mouse was not exercised beyond small test moves.
- Fixed build, Quartus Prime Lite 17.0.2: the default seed missed by 0.282 ns
  on one HDMI-scaler path at the slow -40C corner, so the fitter was re-run
  with `--seed=7` on the same synthesis (`quartus_fit ... --seed=7`, then
  `quartus_asm` and `quartus_sta`). Worst setup slack `+0.404 ns` (HDMI
  scaler), core clock `+1.066 ns`, worst hold `+0.098 ns`, TNS `0` at all
  four corners; post-fit HDMI check reports physical C5. Utilization is
  25,880 ALMs, 32,506 registers, 444 RAM blocks, and 48 DSP blocks. RBF
  SHA-256: `19F699D734063B9A562DF139A0FDC655D38C126A4143D51D1D0B8DCA65B1F04C`.
  The full suite passes 99 runs across 50 testbenches; lint reports no new
  core-side warnings. This RBF supersedes the first Golden Tee build.

## Power Up Baseball and keyboard test build (2026-11-03)

Adds Power Up Baseball (MAME `pubball`, a 1996 prototype) and keyboard
controls for every game:

- Selector `10`: MAME's `pubball` machine is the SFTM board with
  `init_pubball`'s two 1024-row planes, SFTM's colour latches, two 4-bit
  trackballs at `0x180800`/`0x181000`, a 28-page (14 MiB) GROM without bank
  bits, a six-bank sound ROM, and samples in ES5506 banks 0 and 1. MAME never
  sets its protection address, so the read returns work-RAM byte 0 as MAME's
  does. P3 carries both players' Third Base, Home and Power Up buttons in
  SFTM's positions with bits 6/7 low; the input-layout field grew to four bits
  for it.
- A MAME 0.288 census of the game's I/O (Lua taps, earlier session) found
  SFTM-style colour writes, the sound command as SFTM's byte at `0x480001`,
  one protection read, and the blitter interrupt acknowledged only in its
  handler (so MAME's static status value is kept). The trackballs are read
  sixteen times per frame with gaps up to 3.84 ms, inside the 1600 Hz
  release rate's seven-count reach.
- `Power Up Baseball (prototype).mra`: odd-sized program and sample ROMs; the
  program region's tail is `0xff` as MAME's `ROMREGION_ERASEFF` leaves it.
  The stream matches MAME's loaded regions byte-for-byte and reproduces MD5
  `469af21ca1932a34e2d560faa47a2848`. The game has no clones.
- Keyboard: `itech32_keyboard` decodes `hps_io`'s `ps2_key` with MAME's
  default keys and ORs them into controllers 1 and 2 ahead of the OSD gate,
  so the arrow keys also move the trackballs (Main_MiSTer maps a keyboard to
  a joystick only with `keyboard_as_joystick`). Held keys clear while the OSD
  is open.
- Simulation: new `keyboard` bench (73 checks); `family-inputs` (334 checks,
  Power Up Baseball's ports and release rate) and `game-selector` (17
  profiles) extended. The full suite passes 100 runs across 51 testbenches.
- Quartus Prime Lite 17.0.2 (default seed): worst setup slack `+0.046 ns`
  (HDMI scaler, slow -40C corner), core clock `+0.709 ns`, worst hold
  `+0.058 ns`, TNS `0` at all four corners. Synthesis reports the same 53
  warnings as the previous build. Utilization is 25,948 ALMs, 32,593
  registers, 444 RAM blocks, and 48 DSP blocks. RBF SHA-256:
  `C010981C7DA19288A216FA6972B81D4B2F12ED360903C230609BA69C8536F0E4`.
- Hardware, USB-1 test MiSTer (a uinput virtual keyboard driven over SSH and
  the capture card): the game boots to its attract cycle (high scores, MLB
  licence screens, player cards). Key `5` inserts coins with sound and `1`
  buys innings. On the "play ball / enter initials / draft team" menu the
  Down and Up arrows move the trackball cursor down and up, and Right and Left
  move it as well. A batting inning plays with sound (peaks near -6 dB); the
  batter swung and changed stance when Left Ctrl and Left Alt were pressed.
  This RBF supersedes the Golden Tee fixed build.

## Tournament editions test build (2026-11-03)

Adds the twelve Golden Tee and two World Class Bowling tournament editions
(MAME `tourny` machine: `sftm` plus the M48T02 timekeeper):

- Selectors `11` (`init_aamat`: the single Golden Tee board) and `12`
  (`init_wcbowlt`: the Deluxe bowling row), with a `timekeeper` profile field.
  The 2 KiB at `0x681000-0x6817ff` is four byte-lane RAMs in the main bus;
  `itech32_timekeeper` holds the clock registers after MAME's `timekpr.cpp`
  and starts from the MiSTer RTC (`hps_io` `RTC`, now connected) at each game
  load. The saved image grows to 133120 bytes for these sets (the NVRAM host
  address is now 18 bits); the other games' images are unchanged.
- Descriptors: 14 alternatives (69 generated in all). The Golden Tee table
  gains the tournament sets (4 MiB programs; GT 3D v2.11's two-group GROM; the
  Diamond and Supreme third GROM groups); the bowling sets are built from the
  Deluxe release. All 14 streams match MAME's loaded regions byte-for-byte and
  reproduce their MD5s. The Golden Tee "Trackball Orientation" switch is now
  "Trackball Mount" (Normal/45 Degrees): the MiSTer OSD line was too short to
  show the old setting text.
- MAME 0.288 reference runs: a fresh `gt97t243` reports reset tables plus
  "TOURNAMENT STORAGE FAILURE F8", "TOURNAMENT HARDWARE DISABLE F8" and
  "PROMO BATTERY RAM FAILURE"; after Start it checks for its modem ("ITS
  CALL ... CHECKING MODEM", about 50 s, then "NO MODEM FOUND"). With saved
  NVRAM only "TOURNAMENT HARDWARE DISABLE F8" remains and the game plays.
  `wcbowl140` behaves the same way.
- Simulation: new `timekeeper` (23 checks) and `timekeeper-bus` (29 checks)
  benches; `game-selector` (19 profiles) and the NVRAM benches updated for the
  wider host address. The full suite passes 102 runs across 53 testbenches;
  lint reports no new core-side warnings (the unconnected `RTC` pin warning is
  gone).
- Quartus Prime Lite 17.0.2 (default seed): worst setup slack `+0.082 ns`
  (HDMI scaler, slow -40C corner), core clock `+1.094 ns`, worst hold
  `+0.089 ns`, TNS `0` at all four corners; synthesis reports the same 53
  warnings. Utilization is 26,357 ALMs, 32,907 registers, 448 RAM blocks (the
  timekeeper adds four), and 48 DSP blocks. RBF SHA-256:
  `1C4DC18C52017BA5E44F0C2B7A8B3709B1C7020747F3D36BFCA13C3CE79DFBD8`.
- Hardware, USB-1 test MiSTer (virtual keyboard and capture card):
  - Golden Tee '97 Tournament v2.43T: the first run shows MAME's messages
    except "PROMO BATTERY RAM FAILURE" (MAME fills a fresh timekeeper with
    0xff; the FPGA RAM starts at zero), then the ITS modem check. Opening the
    OSD saved a 133120-byte image whose timekeeper part holds the game's
    tournament data; on reload only "TOURNAMENT HARDWARE DISABLE F8" remains.
    Attract plays with sound, keys 5 and 1 coin and start, and the arrow keys
    move the "How many players?" ball. In service mode, the board self-test
    passes (4 MiB program, palette and video RAM, all GROM and PROM
    checksums), the Player Controls test lights the trackball arrows from the
    keys, and the Tournament menu's Display Timers shows the MiSTer date and
    time (26-11-03 08:38:19, then 08:38:26 seven seconds later).
  - World Class Bowling Tournament v1.40T: the same first-run sequence, a
    133120-byte save, only the hardware-disable message on reload, the modem
    check timing out to attract, and the player-count screen from the keys.
  This RBF supersedes the Power Up Baseball build.

## Must Shoot TV test build (2026-11-03)

Adds Must Shoot TV (MAME `shoottv`, a prototype light-gun game):

- Selector `13`: the SFTM row with two 1024-row planes, SFTM's colour-latch
  order, the fixed security-PIC dword `0x00002000`, a 17-page GROM and samples
  in bank 0, plus two new profile fields: `lightgun` (gun registers at
  `0x190000`/`0x192000`, interrupt clears at `0x183000` and
  `0x183800-0x188003`) and `vint_disabled` (MAME's `shoottv_state` drops
  VINT). `itech32_gun_irq` raises level 5 at lines 0 mod 32 and level 6 at 16
  mod 32 (MAME `gun_interrupt`).
- Aiming: `itech32_lightgun` per gun (mouse, stick, d-pad and arrow keys;
  OSD Light Gun Stick: Relative or Absolute for MiSTer light guns). The mouse's
  left button is player 1's trigger alongside B1. `itech32_crosshair` draws a
  red (player 1) and blue (player 2, once moved) cross; it adds only a select
  to the RGB path, keeping Time Killers' five-clock palette budget. OSD:
  Crosshair On/Off.
- A MAME I/O census of the game (4000 frames, coin, start and firing) found
  only the mapped windows, plus reads at `0x181800`/`0x182000` that MAME and
  the core both leave unmapped (zero). The game is 384x256, so the gun's X
  range (`0x1c-0x19b`) and Y range (`0x00-0xff`) are visible pixels.
- `Must Shoot TV (prototype).mra`: odd-sized program, GROM and sample ROMs,
  the program region's tail `0xff` (MAME `ROMREGION_ERASEFF`). The stream
  matches MAME's loaded regions byte-for-byte; MD5
  `669d0f3b369096c9d9baaca9e79f1fd7`.
- Simulation: new `lightgun`, `gun-irq`, `crosshair` (every active pixel of
  four synthetic frames against a reference) and `shoottv-bus` benches;
  `game-selector` (20 profiles) and `family-inputs` (364 checks) extended. The
  full suite passes 106 runs across 57 testbenches; lint reports no new
  core-side warnings.
- Quartus Prime Lite 17.0.2 (default seed): worst setup slack `+0.301 ns`
  (HDMI scaler, slow -40C corner), core clock `+1.243 ns`, worst hold
  `+0.111 ns`, TNS `0` at all four corners; synthesis reports the same 53
  warnings. Utilization is 26,577 ALMs, 33,045 registers, 448 RAM blocks, and
  48 DSP blocks. RBF SHA-256:
  `D448795B7165254DF8F9A354C18D5C945FD8BC67A0B45329570F01763FF93290`.
- Hardware, USB-1 test MiSTer (virtual keyboard and mouse, capture card): the
  game boots through MAME's attract sequence with the red crosshair centred;
  coins and Start come from keys 5 and 1 with sound. The channel guide
  highlights the row under the crosshair and a shot (Left Ctrl) selects it.
  In the "High Noonish" stage mouse moves and arrow keys move the crosshair
  (a 0.25 s Left press about 125 pixels), each shot takes a bullet, and a
  cowboy under the crosshair falls (an unarmed one, which the game marks with
  its "NO" penalty). The stage then timed out to the quota screen and Game
  Over. Player 2's gun was not exercised (one virtual controller).
  This RBF supersedes the tournament build.

## Reproduction

Use Quartus Prime Lite 17.0.2 as described in `docs/BUILD.md`. Run the ROM-free
checks from `sim/README.md`, then inspect all configured setup and hold corners.
Do not reintroduce development counters, alternate video paths, generated
captures, or private experiment artifacts into a production build.
