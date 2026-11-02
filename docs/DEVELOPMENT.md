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
battery-RAM layout, protection address, graphics-ROM size, and the ES5506
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
Yardage, `04` Pairs, Hot Memory, and Pairs Redemption. `03` and `04` share
BloodStorm's row (MAME's `bloodstm` machine) and change only the input layout.

The graphics-ROM page count is MAME's `grom` region size, not the amount of
ROM loaded: MAME wraps blitter reads at `m_grom.length()`. Every
`bloodstm`-machine set declares a `0x880000` region (17 pages) even when its
GROMs fill only part of it; the MRA zero-fills the rest as MAME does.

Current implementation limits: the graphics-ROM wrap supports 16-127 pages of
512 KiB, and sample banks map to two physical DDR slots (A and B) or to empty.

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
