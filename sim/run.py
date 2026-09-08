#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Build and run the repository's synthetic, ROM-free Verilator regressions."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time


ROOT = Path(__file__).resolve().parents[1]
CORE = "rtl/itech32/"
SOUND = "rtl/sound/"
MEMORY = ["rtl/memory/itech32_ddr_memory.sv", "sys/f2sdram_safe_terminator.sv"]
ES5506 = [SOUND + "itech32_es5506_par.sv", SOUND + "itech32_es5506.sv"]
PAR_PINS = [SOUND + "itech32_es5506_par_pins.sv"]
BLOOD_BUS = [CORE + "itech32_main_bus.sv", CORE + "itech32_blitter.sv",
             "sim/tb/itech32_bloodstorm_bus_env.sv"]
SOUND_CACHE_PHASE = [CORE + "itech32_rate_enable.sv", *MEMORY,
                     SOUND + "third_party/mc6809i/mc6809i.v",
                     SOUND + "itech32_6809_phase_enable.sv",
                     SOUND + "itech32_sound_cpu.sv",
                     SOUND + "itech32_sound_rom_map.sv",
                     SOUND + "itech32_via6522.sv",
                     SOUND + "itech32_sound_ram.sv",
                     *PAR_PINS,
                     *ES5506,
                     SOUND + "itech32_sound_output.sv",
                     SOUND + "itech32_sound_board.sv"]


def test(top: str, sources: list[str], *, sound: bool = False,
         defines: tuple[str, ...] = (), compiler_args: tuple[str, ...] = (),
         runs: tuple[tuple[str, ...], ...] = ((),)) -> dict:
    folder = "sim/tb/sound/" if sound else "sim/tb/"
    return {"top": top, "sources": sources + [folder + top + ".sv"],
            "defines": defines, "compiler_args": compiler_args, "runs": runs}


TESTS = {
    "clocks": test("itech32_clock_enables_tb", [CORE + "itech32_rate_enable.sv",
                                               CORE + "itech32_clock_enables.sv"]),
	"clocks-mame": test("itech32_clock_enables_mame_tb",
						 [CORE + "itech32_rate_enable.sv",
						  CORE + "itech32_clock_enables.sv"]),
	"clock-mode": test("itech32_clock_mode_control_tb",
					   [CORE + "itech32_clock_mode_control.sv"]),
	"game-selector": test("itech32_game_selector_tb", [CORE + "itech32_game_selector.sv"]),
	"nvram-save-request": test("itech32_nvram_save_request_tb",
								 [CORE + "itech32_nvram_save_request.sv"]),
	"nvram-io": test("itech32_nvram_io_tb", [CORE + "itech32_nvram_io.sv"]),
	"nvram-memory": test("itech32_nvram_memory_tb", [CORE + "itech32_main_bus.sv"]),
	"nvram-transfer": test("itech32_nvram_transfer_tb", ["sys/hps_io.sv",
														 CORE + "itech32_nvram_io.sv",
														 CORE + "itech32_main_bus.sv"],
								 compiler_args=("-Wno-PROCASSWIRE",)),
    "crt-adjust": test("itech32_crt_adjust_decode_tb", [CORE + "itech32_crt_adjust_decode.sv"]),
    "video-timing": test("itech32_video_timing_tb", [CORE + "itech32_video_timing.sv"]),
    "inputs": test("itech32_inputs_tb", [CORE + "itech32_inputs.sv"]),
    "blood-inputs": test("itech32_bloodstorm_inputs_tb", [CORE + "itech32_inputs.sv"]),
    "cpu-adapter": test("itech32_tg68_bus_adapter_tb", [CORE + "itech32_tg68_bus_adapter.sv"]),
    "blitter": test("itech32_blitter_tb", [CORE + "itech32_blitter.sv"]),
    "rle-prefetch": test("itech32_rle_prefetch_tb", [CORE + "itech32_blitter.sv"]),
    "sftm-protection": test("itech32_sftm_protection_tb", [CORE + "itech32_main_bus.sv"]),
    "blood-bus": test("itech32_bloodstorm_main_bus_tb", BLOOD_BUS),
    "blood-init": test("itech32_blood_init_ram_tb", BLOOD_BUS),
    "ddr": test("itech32_ddr_memory_tb", MEMORY, defines=("ITECH32_WRITE_OVERLAP",),
                compiler_args=("-Wno-PROCASSWIRE",),
                runs=(("+EXPECT_MAIN_HIT_EDGES=2",),
                      ("+EXPECT_MAIN_HIT_EDGES=2", "+GROM_FRONT_ONLY"),
                      ("+EXPECT_MAIN_HIT_EDGES=2", "+WRITE_OVERLAP_ONLY"))),
    "audio-arbitration": test("itech32_audio_qword_tb", MEMORY,
                              defines=("ITECH32_WRITE_OVERLAP",),
                              compiler_args=("-Wno-PROCASSWIRE",),
                              runs=tuple((f"+CASE={case}",) for case in range(8))
                              + (("+EDGE_ONLY",),)),
    "sound-service": test("itech32_sound_service_tb", MEMORY,
                          defines=("ITECH32_WRITE_OVERLAP",),
                          compiler_args=("-Wno-PROCASSWIRE",)),
    "sound-cache-phase": test("itech32_sound_cache_phase_tb", SOUND_CACHE_PHASE,
                               sound=True, defines=("ITECH32_WRITE_OVERLAP",),
                               compiler_args=("-Wno-PROCASSWIRE",)),
    "es5506-host": test("itech32_es5506_host_tb", ES5506, sound=True),
    "es5506-host-spec": test("itech32_es5506_host_spec_tb", ES5506,
                             sound=True, runs=tuple((f"+CASE={case}",) for case in
                                 ("protocol", "deferred", "deferred-running", "stacked", "global",
                                  "multiple-acked", "deferred-underrun"))),
    "es5506-par": test("itech32_es5506_par_tb", ES5506, sound=True),
    "es5506-par-pins": test("itech32_es5506_par_pins_tb", PAR_PINS, sound=True),
    "es5506-audio": test("itech32_es5506_audio_tb", ES5506, sound=True),
    "es5506-arithmetic-spec": test("itech32_es5506_arithmetic_spec_tb",
                                   ES5506, sound=True),
    "es5506-sample-format": test("itech32_es5506_sample_format_tb",
                                 ES5506, sound=True,
                                 runs=tuple((f"+CASE={case}",) for case in
                                     ("formats", "warm-format", "warm-bank"))),
    "es5506-cadence": test("itech32_es5506_cadence_tb", ES5506, sound=True),
    "es5506-start-miss": test("itech32_es5506_start_miss_tb", ES5506,
                                sound=True,
                                runs=tuple((f"+CASE={case}",) for case in
                                    ("lower", "upper", "word3-zero", "ack-phase",
                                     "mixed-hit-miss", "new-bank", "contention",
                                     "hit", "reset"))),
    "es5506-bank-prewarm": test("itech32_es5506_start_miss_tb", ES5506,
                                  sound=True, defines=("TEST_PROGRAM_PREWARM",),
                                  runs=(("+CASE=prewarm",),
                                        ("+CASE=prewarm-priority",))),
    "es5506-native-host": test("itech32_es5506_native_host_tb",
                                ES5506, sound=True),
    "es5506-prefetch-collision": test("itech32_es5506_prefetch_collision_tb",
                                      [*ES5506,
                                       "sim/tb/sound/itech32_es5506_native_host_tb.sv"], sound=True),
    "es5506-control-spec": test("itech32_es5506_control_spec_tb",
                                ES5506, sound=True,
                                runs=(("+CASE=address",), ("+CASE=envelope",),
                                      ("+CASE=slow-free",))),
    "es5506-boundaries-spec": test("itech32_es5506_boundaries_spec_tb",
                                   ES5506, sound=True,
                                   runs=tuple((f"+CASE={case}",) for case in
                                       ("irqe-off", "fractional", "transwave", "continuation",
                                        "equal-nonzero"))),
    "es5506-datapath-spec": test("itech32_es5506_datapath_spec_tb",
                                 ES5506, sound=True,
                                 runs=tuple((f"+CASE={case}",) for case in
                                      ("histories", "filters", "panning", "stopped-flush",
                                       "stopped-restart", "interpolation", "equal-endpoint", "stop1-equal",
                                      "restart-underrun"))),
    "es5506-masks-mix": test("itech32_es5506_masks_mix_tb",
                             ES5506, sound=True,
                             runs=tuple((f"+CASE={case}",) for case in
                                 ("masks", "mix", "ca-diagnostic", "running-envelope"))),
    "es5506-channels-spec": test("itech32_es5506_channels_spec_tb",
                                 ES5506, sound=True,
                                 runs=tuple((f"+CASE={case}",) for case in
                                     ("channels", "page40", "page40-add", "undefined-ca"))),
    "sound-phase": test("itech32_6809_phase_enable_tb", [SOUND + "itech32_6809_phase_enable.sv"], sound=True),
    "sound-rom-map": test("itech32_sound_rom_map_tb", [SOUND + "itech32_sound_rom_map.sv"], sound=True),
    "sound-output": test("itech32_sound_output_tb", [SOUND + "itech32_sound_output.sv"], sound=True),
    "sound-cpu": test("itech32_sound_cpu_tb", [SOUND + "third_party/mc6809i/mc6809i.v",
                                              SOUND + "itech32_6809_phase_enable.sv",
                                              SOUND + "itech32_sound_cpu.sv"], sound=True),
    "sound-phase-overlap": test("itech32_sound_phase_overlap_tb",
                                 [CORE + "itech32_rate_enable.sv",
                                  SOUND + "third_party/mc6809i/mc6809i.v",
                                  SOUND + "itech32_6809_phase_enable.sv",
                                  SOUND + "itech32_sound_cpu.sv"], sound=True),
    "via6522": test("itech32_via6522_tb", [SOUND + "itech32_via6522.sv"], sound=True),
}


def run_logged(command: list[str], log: Path, cwd: Path, timeout: int) -> str:
    """Keep generated output in the build directory, not among the test sources."""
    with log.open("w", encoding="utf-8") as output:
        output.write("Command: " + repr(command) + "\n\n")
        output.flush()
        try:
            result = subprocess.run(command, cwd=cwd, stdout=output,
                                    stderr=subprocess.STDOUT, timeout=timeout, check=False)
        except subprocess.TimeoutExpired as error:
            raise RuntimeError(f"Timed out after {timeout}s; see {log}") from error
    transcript = log.read_text(encoding="utf-8", errors="replace")
    if result.returncode:
        tail = "\n".join(transcript.splitlines()[-35:])
        raise RuntimeError(f"Command failed ({result.returncode}); see {log}\n{tail}")
    return transcript


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tests", nargs="*", help="Test names; defaults to all tests")
    parser.add_argument("--list", action="store_true", help="List tests without running tools")
    parser.add_argument("--verilator", default=os.environ.get("VERILATOR", "verilator"),
                        help="Verilator executable (or set VERILATOR)")
    parser.add_argument("--jobs", type=int, default=2, help="C++ build parallelism (default: 2)")
    parser.add_argument("--build-dir", type=Path, default=ROOT / "sim/build/rom-free")
    parser.add_argument("--compile-timeout", type=int, default=600)
    parser.add_argument("--run-timeout", type=int, default=120)
    parser.add_argument("--verilator-arg", action="append", default=[],
                        help="Extra option; use --verilator-arg=--option for a leading dash")
    parser.add_argument("--cflags", default="-O2", help="C++ flags passed through -CFLAGS")
    args = parser.parse_args()
    if args.list:
        for name, case in TESTS.items():
            print(f"{name:19} {case['top']} ({len(case['runs'])} run(s))")
        return 0
    names = args.tests or list(TESTS)
    unknown = sorted(set(names) - set(TESTS))
    if unknown:
        parser.error("Unknown tests: " + ", ".join(unknown))
    if min(args.jobs, args.compile_timeout, args.run_timeout) < 1:
        parser.error("Job count and timeouts must be positive")
    build_root = args.build_dir.resolve()
    if build_root.is_relative_to(ROOT) and not build_root.is_relative_to(ROOT / "sim/build"):
        parser.error("In-repository output must be below sim/build; do not overwrite source directories")
    verilator = shutil.which(args.verilator)
    if not verilator:
        parser.error("Verilator not found; install it or set --verilator/VERILATOR")
    verilator = str(Path(verilator).resolve())
    for name in names:
        for source in TESTS[name]["sources"]:
            if not (ROOT / source).is_file():
                parser.error(f"Missing source for {name}: {source}")
    build_root.mkdir(parents=True, exist_ok=True)
    started = time.monotonic()
    passed = 0
    for name in names:
        case = TESTS[name]
        build_dir = build_root / name
        build_dir.mkdir(parents=True, exist_ok=True)
        print(f"Building {name} ...", flush=True)
        command = [verilator, "--binary", "--timing", "--assert", "--x-initial", "0",
                   "--threads", "1", "-j", str(args.jobs), "-Wall", "-Wno-fatal",
                   "--top-module", case["top"], "--Mdir", build_dir.as_posix(),
                   "-I" + (ROOT / "sim/tb").as_posix(), "-CFLAGS", args.cflags]
        command.extend("-D" + define for define in case["defines"])
        command.extend(case["compiler_args"])
        command.extend(args.verilator_arg)
        command.extend((ROOT / source).as_posix() for source in case["sources"])
        try:
            run_logged(command, build_dir / "compile.log", ROOT, args.compile_timeout)
            executable = build_dir / ("V" + case["top"] + (".exe" if os.name == "nt" else ""))
            if not executable.is_file():
                raise RuntimeError(f"Verilator did not create {executable}")
            for index, plusargs in enumerate(case["runs"]):
                log = build_dir / f"run-{index}.log"
                transcript = run_logged([str(executable), *plusargs], log, build_dir, args.run_timeout)
                if "PASS" not in transcript:
                    raise RuntimeError(f"Test exited without a PASS marker; see {log}")
                passed += 1
                print(f"PASS {name} {' '.join(plusargs)}".rstrip(), flush=True)
        except (OSError, RuntimeError) as error:
            print(f"FAIL {name}: {error}", file=sys.stderr, flush=True)
            return 1
    print(f"Passed {passed} runs across {len(names)} testbenches in {time.monotonic() - started:.1f}s.")
    print(f"Generated output: {build_root}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
