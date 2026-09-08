# ROM-Free Simulations

These are focused SystemVerilog regressions for the production RTL. They use
synthetic transactions, small authored pixel patterns, and an authored 6809
test program. No game ROMs, extracted graphics, replay dumps, or recorded test
results are included.

## Running

Install Python 3.10 or newer, a Verilator 5.x release supporting `--binary` and
`--timing`, a C++ compiler with coroutine support, and GNU Make. Ensure the
compiler and Verilator are on `PATH` in the same environment.

From the repository root:

```sh
python3 sim/run.py --list
python3 sim/run.py
python3 sim/run.py inputs blood-inputs blood-bus blood-init
```

Select an executable explicitly with `--verilator` or the `VERILATOR` environment
variable. Use `--jobs` to control C++ build parallelism. The default output is
ignored `sim/build/rom-free/`; `--build-dir` can place all generated material
outside the checkout. Compilation and run logs are generated locally, never
checked in.

Native Windows packages may require their own compiler/runtime environment.
Set `VERILATOR_ROOT`, `PATH`, `CC`, and `CXX` as specified by the package. The
runner accepts `verilator_bin.exe` as well as the usual `verilator` launcher.
For packages needing an explicit libstdc++ ABI selection, use
`--cflags="-D_GLIBCXX_USE_CXX11_ABI=0 -O2"`. Additional version-specific switches
can be passed with, for example,
`--verilator-arg=--no-sched-zero-delay` on versions that support that option.

Only the `ddr`, `audio-arbitration`, `sound-service`, and `nvram-transfer` tests
add `-Wno-PROCASSWIRE`. The unchanged upstream framework modules used by those
tests contain procedural assignments to ports/nets declared as wires, which
newer Verilator versions otherwise reject. This compatibility waiver preserves
the actual framework modules and does not disable assertions.

The runner always enables assertions and uses deterministic zero initialization.
The BloodStorm initialization regression then verifies the RTL's own memory-fill
sequence; it does not supply a pre-filled game memory image.

### Mixed-language TG68 checks

Two additional ROM-free benches instantiate the production VHDL TG68 core and
therefore use ModelSim rather than Verilator. They verify the odd-addressed
longword sequence used by the early SFTM software, first through the CPU adapter
and then through the complete production SFTM main bus:

```powershell
vlib sim/build/modelsim-tg68-unaligned
vcom rtl/cpu/tg68k/TG68K_Pack.vhd rtl/cpu/tg68k/TG68K_ALU.vhd rtl/cpu/tg68k/TG68KdotC_Kernel.vhd
vlog -sv rtl/itech32/itech32_tg68_bus_adapter.sv rtl/itech32/itech32_tg68_cpu.sv rtl/itech32/itech32_main_bus.sv sim/tb/itech32_tg68_unaligned_tb.sv sim/tb/itech32_tg68_main_bus_unaligned_tb.sv
vsim -c -do "run -all; quit -f" itech32_tg68_unaligned_tb
vsim -c -do "run -all; quit -f" itech32_tg68_main_bus_unaligned_tb
```

`modelsim.ini` maps `work` to that ignored build directory. The startup
metavalue warnings originate in TG68's VHDL internals; both benches end in an
explicit `*_PASS` assertion message and zero simulation errors.

## Coverage

| Tests | Scope |
| --- | --- |
| `clocks`, `clocks-mame`, `clock-mode`, `crt-adjust`, `video-timing` | Board/MAME clock enables, DDR-quiesced and loader-retaining mode adoption, menu offset decode, and programmable raster timing |
| `game-selector` | Three board selectors plus unsupported-selector SFTM fallback |
| `nvram-save-request`, `nvram-io`, `nvram-memory`, `nvram-transfer` | One save per dirty OSD-opening edge, MiSTer upload/dirty protocol, all three backing stores, bounds and byte lanes, plus an exact WIDE=1 `hps_io` save/restore round trip |
| `inputs`, `blood-inputs` | Input and DIP mapping |
| `cpu-adapter` | TG68 bus-adapter handshake |
| `blitter`, `rle-prefetch` | Synthetic blits and RLE prefetch behavior |
| `sftm-protection` | SFTM zero-read protection source, protected-byte lane, and unchanged Time Killers/BloodStorm open-bus policy |
| `blood-bus`, `blood-init` | BloodStorm bus decode and initial-RAM behavior |
| `ddr` | Memory service, resident reads, reset, and write overlap |
| `audio-arbitration` | Audio qword service and cancellation/edge cases |
| `sound-service` | Registered SOUND resident hits, held signatures, cancellation, and bounded SAMPLE-grant quota |
| `es5506-host`, `es5506-audio`, `es5506-cadence` | Sound-device register and sample behavior |
| `es5506-start-miss` | ROM-independent and matched-phase STOP-to-RUN acknowledgement, word3 neighbor qualification, zero/freeze miss fallback, mixed hit/miss summation, cache identity, contention, and reset |
| `es5506-host-spec`, `es5506-native-host` | Byte protocol, deferred IRQ clearing, native carrier host/voice deadlines |
| `es5506-par` | Real host-path PAR snapshot/restart, 4096-enable discharge, CLK/4 measurement, common-page visibility and engine isolation |
| `es5506-par-pins` | Exact production 2FF comparator synchronization, four polarity combinations, reset and raw discharge polarity |
| `es5506-prefetch-collision` | Native host/voice overlaps reject undefined mixed-port RAM reads before descriptor capture |
| `es5506-arithmetic-spec`, `es5506-datapath-spec` | Independent signed filter/product vectors, guarded history/PCM pipeline, host-visible history truncation, STOP/restart behavior |
| `es5506-sample-format` | Both full-width companded neighbors decoded before interpolation, linear controls, warm format changes and bank identity |
| `es5506-control-spec`, `es5506-masks-mix` | Address/loop/envelope behavior, field masks, same-channel mixing, running-envelope order |
| `es5506-boundaries-spec` | Fractional boundary equality, masked START, IRQ-disabled crossings and repeated uni/bidirectional/transwave transitions |
| `es5506-channels-spec` | Six canonical stereo channels, per-channel clipping, PAGE40 writes and shared-store addition |
| `sound-phase`, `sound-rom-map`, `sound-cpu`, `via6522` | Sound clocking, decode, authored CPU program, and VIA behavior |
| `sound-cache-phase` | Real authored sound-CPU program crossing the registered two-way SOUND cache at native phase cadence |
| `sound-phase-overlap` | Paired architectural bus traces, interrupt handling and readiness invariants while inactive phases overlap memory latency |
| `sound-output` | Exhaustive signed 20-bit input conversion through the selected stereo swap and full-range, headroom-preserving 16-bit normalization |

The DDR runner uses the current two-edge resident-hit expectation and explicitly
enables write-overlap coverage. Audio arbitration runs all eight synthetic cases
and its edge-only case. The phase-overlap test contains a small whole-phase-hold
reference wrapper solely to compare the authored program's architectural trace;
it is not a second production CPU path.

These tests do **not** simulate the complete MiSTer scaler, an external Direct
Video receiver, or full games. They do not prove whole-game speed or complete
sound fidelity. The TG68K.C VHDL itself is not executed by this suite; its adapter
is tested with synthetic bus traffic. No simulator model substitutes for a
physical video-output compatibility test.

The sound specification choices and remaining interface abstractions are listed
in `docs/SOUND.md`. A diagnostic run completing is not a manufacturer-behavior
pass; use each test's stated assertions and scope when interpreting its output.
