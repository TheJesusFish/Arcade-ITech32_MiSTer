#!/usr/bin/env python3
"""Check the physical HDMI counter in a Quartus post-fit Verilog netlist.

The logical HDL name counter[0] is not the physical counter number. The stock
MiSTer HDMI reconfiguration controller programs physical C5, so a successfully
compiled design using another C counter will select incorrect HDMI frequencies.
Generate this netlist from the same fitted database as the RBF being qualified.
"""

import argparse
from pathlib import Path
import re
import sys


HDMI_COUNTER = (
    "pll_hdmi|pll_hdmi_inst|altera_pll_i|cyclonev_pll|"
    "counter[0].output_counter"
)
COUNTER_PARAMETER = re.compile(
    r"^\s*defparam\s+\\" + re.escape(HDMI_COUNTER)
    + r"\s+\.output_counter_index\s*=\s*(\d+)\s*;\s*$"
)


def check_netlist(path: Path) -> int:
    # Stream the file: full-game post-fit netlists can exceed 100 MB.
    matches = []
    with path.open(encoding="utf-8", errors="strict") as source:
        for line_number, line in enumerate(source, 1):
            match = COUNTER_PARAMETER.match(line)
            if match:
                matches.append((line_number, int(match[1])))
    if len(matches) != 1:
        raise ValueError(
            f"Expected exactly one HDMI physical-counter parameter; found {len(matches)}. "
            "Check the netlist type and hierarchy; do not assume a missing match passes."
        )
    line_number, counter = matches[0]
    if counter != 5:
        raise ValueError(
            f"{path}:{line_number}: HDMI uses physical C{counter}, "
            "but stock pll_cfg_hdmi programs C5."
        )
    return line_number


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("netlist", type=Path, help="Quartus post-fit .vo file")
    args = parser.parse_args()
    try:
        line = check_netlist(args.netlist)
    except (OSError, UnicodeError, ValueError) as error:
        print(f"HDMI_PLL_CHECK_FAIL: {error}", file=sys.stderr)
        return 1
    print(f"HDMI_PLL_CHECK_PASS: physical C5 at {args.netlist}:{line}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
