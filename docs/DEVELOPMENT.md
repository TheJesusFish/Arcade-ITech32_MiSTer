# Development Notes

## Preserve the Working Interfaces

- Keep the production PLL, pixel-enable cadence, and the single framework video
  boundary stable during unrelated work. Analog, Direct Video, and the MiSTer
  scaler have different downstream requirements; validating one does not prove
  the others work.
- The core has one free-running PLL instantiated as `pll pll`, as the template
  expects. Do not reset or switch it at runtime: hps_io and the DDR interface run
  on that clock. The palette timing exception in `Arcade-ITech32.sdc` and Time
  Killers' intensity pipeline assume six carrier clocks per pixel.
- Registered memory requests must keep their address and payload stable while
  waiting for acknowledgement. Preserve CPU/blitter command ordering and the
  write fence when optimizing internal service time.
- Infer synchronous memories and register timing-critical decisions. Avoid bulk
  reset loops, wide combinational priority paths, and unqualified asynchronous
  crossings.
- Keep ROM loading and the game board's warm reset semantics separate. A warm
  reset must not accidentally invalidate already loaded ROM data.
- Preserve the BloodStorm initial-RAM behavior and game-specific input/maps.
  Test cold initialization as well as reset during an outstanding transaction.
- Persistent NVRAM reuses the game RAMs' existing synchronous ports during an
  index-2 transfer. Keep the CPU/sound hold, the drain-then-grant RAM
  ownership handshake, and the upload prefetch contract in `docs/NVRAM.md`; do
  not infer another writer or a third RAM port.
- Request at most one automatic NVRAM upload per OSD-opening edge. Do not request
  on each dirty transition: BloodStorm stores live work RAM in the persisted
  region and will otherwise retrigger saves continuously while the OSD is open.

## Board Profiles

Every per-game hardware difference lives in `rtl/itech32/itech32_profile_pkg.sv`
as a field of `board_profile_t`: CPU type, MAME address-map family, input
layout, palette format, framebuffer planes, sound-board revision and bank count,
battery-RAM layout, protection reads, ROM-board additions (trackball ports and
the zero-reading `0x578000` window), graphics-ROM size, and the ES5506
sample-bank map. The MRA writes one selector byte at index 1;
`itech32_game_selector` registers the matching profile, and each block reads
only the fields it needs. Blocks must not test game identity.

To add a game:

1. Read its MAME machine configuration and init function, then add a selector
   value and a profile row in `profile_for_selector`. Reuse existing field
   values wherever the hardware matches; several game families share one MAME
   address map.
2. Only when the game needs a behavior no existing value describes, add a new
   field value (for example a new `MAP_*`) and implement it where that field is
   consumed.
3. Generate MRAs that write the new selector before the ROM stream, then extend
   the ROM-free tests and the game-selector bench.

Selectors in use: `00` SFTM, `01` Time Killers, `02` BloodStorm, `03` Hard
Yardage, `04` Pairs, Hot Memory, and Pairs Redemption, `05` World Class Bowling
v1.0-1.5, `06` World Class Bowling v1.3J. `03`-`06` share BloodStorm's row
(MAME's `bloodstm` machine). `03` and `04` change only the input layout; `05`
and `06` also take MAME `init_wcbowl`'s ROM-board additions: a trackball port at
`0x680000` (and `0x680040` on v1.3J), the security PIC result at `0x680080`
(MAME's model: the work-RAM word at `protection_address` `0x111c`), and zero
reads from `0x578000-0x57ffff`. `07` World Class Bowling v1.6-1.66, `08` World
Class Bowling Deluxe, and `09` Shuffleshot use the SFTM row (MAME's `sftm`
machine) with `init_shuffle_bowl_common`'s two trackball ports at `0x180800` and
`0x181000`, a six-bank sound ROM, samples in ES5506 banks 0 and 1, and the
itech020 protection byte at `0x1116` (v1.6x) or `0x111a`; Shuffleshot's
graphics ROM is 16 pages.

`0a`-`0f` are Golden Tee (MAME `sftm` machine with `init_gt_common`): two
1024-row framebuffer planes, the base `itech020_map` colour latches (`0x300003`
loads latch 1 and `0x380003` latch 0, the reverse of SFTM's init), the
protection byte at `0x112f`, a 12-page GROM without bank bits, and the volume
buttons on P3. The six selectors are its boards. `0a` is the single board
(`init_aama`): two 4-bit trackballs at `0x180800`/`0x181000` and samples in
ES5506 bank 0. `0b` and `0c` add `init_gt2kp`'s and `init_gtclasscp`'s fixed
`0x680000` dwords (`0x00010000` and `0x00008000`). `0d` is the one-trackball "S"
board (`init_s_ver`): the port at `0x200200` and samples in bank 2. `0e` and
`0f` are the three-tier Golden Tee 3D boards with samples in banks 0, 2 and 3:
`0e` (`init_gt3d`) reads one ball's 8-bit counters as the low word of
`0x200000`, and `0f` (`init_gt3dl`) packs both 4-bit ports into `0x200000`
(player 1 in bytes `+3`/`+1`, player 2 in `+2`/`+0`). Both replace P4.

Golden Tee also needs two behaviors MAME gives for free. It writes the sound
command as a word at `0x480000`; MAME's byte handler at `0x480001` takes any
write that includes that byte, and so does the core (byte lane `+1`). And its
blitter command queue polls video status bits 7:6 for busy (`01`) and ready
(`10`) before switching the blitter interrupt off and running polled blits,
whose loop acknowledges the blitter bit straight after each command. MAME's
blits are instant, so it simply returns the written status value, always
"ready". The core's blits take time: without live status bits, a queued blit
still running when Golden Tee enters polled mode has its completion wiped,
the queue's busy flag never clears, and the game hangs at its first course
(observed on hardware with an on-chip bus recorder).
`blitter_status_live` enables the live bits for Golden Tee only; the other
games acknowledge the blitter bit only in their interrupt handler and keep
MAME's static value.

`10` is Power Up Baseball (MAME `pubball` machine, `init_pubball`): the SFTM
row with two 1024-row planes, SFTM's colour latches, two 4-bit trackballs at
`0x180800`/`0x181000`, a 28-page GROM without bank bits, a six-bank sound ROM,
and samples in ES5506 banks 0 and 1. MAME never sets its protection address,
so the protection read returns work-RAM byte 0. P3 holds both players' Third
Base, Home and Power Up buttons in SFTM's positions; its unused bits 6/7 read
low.

`11` and `12` are the tournament editions: `11` is the Golden Tee single
board (`init_aamat`, `0a`'s row) and `12` the World Class Bowling Deluxe row
(`init_wcbowlt`), each with `timekeeper` set. MAME's `install_timekeeper` maps
the M48T02 as an 8-bit device on every byte lane of `0x681000-0x6817ff`, so CPU
address `0x681000 + n` is chip offset `n`; without the timekeeper the window
reads zero (Shuffleshot probes it). The main bus holds the chip's 2 KiB in four
byte lanes and saves it after the 128 KiB NVRAM; `itech32_timekeeper` holds the
eight clock registers at offsets `0x7f8-0x7ff` (control, seconds, minutes,
hours, day, date, month, year; BCD), following MAME's `timekpr.cpp`: the
counters tick each second unless ST (seconds bit 7) stops the oscillator or W
(control bit 7) is set; clearing W loads them from the registers; R (control
bit 6) freezes the registers the CPU reads, and clearing it refreshes them.
MAME starts the counters from the host clock; the core loads them from
`hps_io`'s RTC at each game load and follows its once-a-minute updates until
the game sets W to write its own time. MAME's day-of-week step runs 7, 0, 1;
the core counts 1-7 like the chip. The clock keeps time through board resets.

`13` is Must Shoot TV (MAME `shoottv_state`): the SFTM row with two 1024-row
planes, SFTM's colour-latch order, the fixed security-PIC dword `0x00002000` at
`0x680000`, a 17-page GROM, samples in bank 0, and two light guns
(`lightgun`). Its ports are the 16-bit boards' bytes in bits 23:16: P1/P2 hold
Coin and Start, P3 the two triggers, `0x200000` reads all ones. The board
ignores VINT (`vint_disabled`); instead `itech32_gun_irq` raises level 5 at
lines with `(vpos & 0x1f) == 0` and level 6 at 16, cleared by reads of
`0x183800-0x188003` and `0x183000`. The gun registers are the first dword of
each 2 KiB step at `0x190000` (X low byte, X bit 8, Y, zero; gun 2 at
`0x192000`). MAME's X range `0x1c-0x19b` and Y range `0x00-0xff` span the
384x256 visible area, so the core keeps aim points in visible pixels and adds
`0x1c` when the game reads X.

### Light guns

`itech32_lightgun` moves each aim point from mouse packets (one count per
pixel, player 1 only), the d-pad (500 pixels a second) or the stick (speed
from its deflection). With the OSD's Light Gun Stick set to Absolute, the
stick's full range maps onto the screen instead, which suits MiSTer light guns
that report through the analog stick. The mouse's left button is player 1's
trigger alongside B1. `itech32_crosshair` draws a cross for each gun over the
board's RGB: it counts active pixels and lines from the blanking edges, so it
needs no knowledge of the programmed raster, and it adds no register to the RGB
path (only a select), because Time Killers' palette pipeline already uses five
of the six clocks per pixel. Player 2's cross appears once that gun moves.

The itech020 plane latch's bits 7:6 select a 16 MiB GROM bank only where MAME's
`grom_bank_mask` (GROM length >> 24) allows it, which is SFTM alone
(`grom_banked`); the other itech020 games ignore them.

### Trackballs

`itech32_trackball` keeps the board-side state the game reads: two 8-bit
position counters per ball. Most boards read the low four bits of each, packed
`(Y << 4) | X` (MAME `trackball_r`); Golden Tee 3D's short ROM board reads all
eight (`trackball_8bit_r`).
The MiSTer side stands in for the ball: mouse packets (player 1), the left
stick, or the d-pad add movement to a saturating accumulator in 1/16 counts,
scaled by the OSD Trackball Speed (25% matches MAME's default sensitivity). The
stick and d-pad integrate on a fixed 1600 Hz tick; whole counts leave the
accumulator one per release strobe, whose rate is per board
(`trackball_rate`). The rates come from measurements: in MAME 0.288, World Class
Bowling reads the port in eight pairs per frame with a longest gap of about
3.5 ms (3.8 ms at this core's frame rate); the 68EC020 bowling and Shuffleshot
sets show the same pattern with a 3.8 ms gap. A 4-bit counter aliases beyond
seven counts between reads, and 1600 Hz keeps any gap under 4.375 ms within
seven. Golden Tee's single and "S" boards read sixteen times per frame with
gaps up to 1.6 ms, so they release at 3600 Hz; the long-ROM Golden Tee 3D board
reads eight times (3.2 ms gaps, 1600 Hz); the short-ROM board reads its 8-bit
counters only every second or third frame (up to 50 ms), and 2200 Hz keeps
that within 127 counts. A faster release lets a hard golf swing reach the game
at full speed. MAME's 68EC020 handler instead clamps each read to +-7 counts
and holds its value for one scanline; at these read rates both give the same
result. Orientation follows MAME's
ports: X is reversed and Y falls as the ball rolls forward. Main_MiSTer sends
PS/2 packets with +Y forward. Mouse packets are discarded while the OSD is
open.

### Keyboard

Main_MiSTer turns the keyboard into a joystick only when `MiSTer.ini` sets
`keyboard_as_joystick`, so `itech32_keyboard` decodes `hps_io`'s `ps2_key`
itself with MAME's default keys, and the top level ORs the result into
controllers 1 and 2 ahead of the OSD gate. On trackball boards the arrow keys
are the d-pad and so move the ball. `ps2_key[10]` toggles once per key event
and is edge-detected; it is not a level. Held keys are dropped while the OSD
is open, because releases made in the menu never reach the core. The right-hand
Ctrl and Alt keys (`0xE0` codes) and the keypad arrows are not mapped.

The graphics-ROM page count is MAME's `grom` region size, not the amount of
ROM loaded: MAME wraps blitter reads at `m_grom.length()`. Every
`bloodstm`-machine set declares a `0x880000` region (17 pages) even when its
GROMs fill only part of it; the MRA zero-fills the rest as MAME does.

Current implementation limits: the graphics-ROM wrap supports 16-127 pages of
512 KiB (4-127 for GROMs without bank bits), and sample banks map to three
physical DDR slots or to empty. Slots A and B follow the GROM window; slot C
is that window's last 4 MiB (`0x2200000`), usable only by profiles with at most
58 GROM pages.

## Verification Scope

The included Verilator suite is a focused, synthetic regression suite. It checks
selected input, bus, blitter, memory, timing-generator, and sound-device behavior.
It is not a full-game replay, a comparison recording, or a physical Direct Video
receiver. Its synthetic programs and pixels are authored test stimulus, not
extracted game content.

Use MAME source and documentation as behavioral references, while separating
observed emulator behavior, documented hardware facts, and assumptions.
Record the reference version and the reason for each compatibility decision.
Do not silently translate emulator clock estimates into verified board timings.

For production changes, run relevant simulations, build the clean production
configuration, and inspect setup/hold timing at all configured corners. Do not
quote timing from a build carrying debug counters as production timing.
Simulation-only code belongs under `sim/`, never in `files.qip`.

## Notes and Publication Boundaries

Keep concise design rationale and reproducible commands in source documentation.
Maintain detailed local experiment notes separately, including exact source/build
identity, tests performed, remaining limits, and how to resume the work.
Do not commit raw measurements, receipts, screenshots, traces, RAM dumps, captured
audio, credentials, local host paths, or ROM material.

The third-party licenses and attribution in `CREDITS.md` are part of the source
distribution. Preserve them when moving or adapting modules. Any future framework
update should be reviewed as a separate change rather than folded into a cleanup.
