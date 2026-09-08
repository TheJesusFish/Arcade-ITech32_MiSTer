# Development Notes

## Preserve the Working Interfaces

- Keep the production PLL, pixel-enable cadence, and the single framework video
  boundary stable during unrelated work. Analog, Direct Video, and the MiSTer
  scaler have different downstream requirements; validating one does not prove
  the others work.
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
  index-2 transfer. Keep the CPU/sound hold and upload prefetch contract in
  `docs/NVRAM.md`; do not infer another writer or a third RAM port.
- Request at most one automatic NVRAM upload per OSD-opening edge. Do not request
  on each dirty transition: BloodStorm stores live work RAM in the persisted
  region and will otherwise retrigger saves continuously while the OSD is open.

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
