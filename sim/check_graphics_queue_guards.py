#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Require the graphics integration test to reject two deliberately broken copies.

Accepts the same tool/compiler options as run.py, but no test-name arguments.
Only generated files below --build-dir are changed; production RTL is untouched.
"""
from pathlib import Path
import copy
import sys

import run as runner


def main() -> int:
    # Delegate argument handling/build execution to the normal regression runner.
    # Mutant paths are absolute, so ROOT / source in that runner preserves them.
    args = sys.argv[1:]
    output = runner.ROOT / "sim/build/graphics-guards"
    for i, arg in enumerate(args):
        if arg == "--build-dir":
            output = Path(args[i + 1]).resolve()
        elif arg.startswith("--build-dir="):
            output = Path(arg.split("=", 1)[1]).resolve()
    if output.is_relative_to(runner.ROOT) and not output.is_relative_to(runner.ROOT / "sim/build"):
        raise SystemExit("Mutation output must be outside source or below sim/build")
    mutants = (
        ("early-completion", "rtl/itech32/itech32_board.sv",
         "assign vram_writes_pending = vram_arbiter_writes_pending ||\n\t\tqwrite_slice_valid;",
         "assign vram_writes_pending = 1'b0;",
         ("drawing idle before write queue empty", "completion escaped pending graphics writes")),
        ("fifo-reorder", "rtl/itech32/itech32_vram_arbiter.sv",
         "fifo_ram_q <= write_fifo[fifo_rd_ptr];",
         "fifo_ram_q <= write_fifo[fifo_rd_ptr ^ 8'd1];",
         ("queue output lost/reordered/corrupted",)),
    )
    output.mkdir(parents=True, exist_ok=True)
    for label, source, old, new, messages in mutants:
        text = (runner.ROOT / source).read_text(encoding="utf-8")
        if text.count(old) != 1:
            raise SystemExit(f"Mutation anchor changed: {label}; review the sensitivity test")
        path = output / (label + ".sv")
        path.write_text(text.replace(old, new), encoding="utf-8")
        case = copy.deepcopy(runner.TESTS["graphics-queue"])
        case["sources"] = [str(path) if s == source else s for s in case["sources"]]
        case["runs"] = (("+SEED=305419896",),)
        runner.TESTS[label] = case
        log = output / label / "run-0.log"
        log.unlink(missing_ok=True)  # Never accept stale evidence after a compile failure.
        sys.argv = ["run.py", label, "--build-dir", str(output), *args]
        print(f"Expecting assertion failure: {label}", flush=True)
        result = runner.main()
        if result != 1 or not log.is_file() or not any(
                message in log.read_text(encoding="utf-8") for message in messages):
            raise SystemExit(f"FAIL: {label} did not fail at the intended assertion")
        print(f"PASS sensitivity: {label} rejected at the intended assertion", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
