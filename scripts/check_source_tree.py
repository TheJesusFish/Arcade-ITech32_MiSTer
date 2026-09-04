#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Check Git's upload candidate for missing core inputs and private/generated data."""

from __future__ import annotations

from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]
BLOCKED_DIRS = {".git", ".tools", ".local", ".codex", ".agents", ".venv", ".idea",
                ".vscode", ".pytest_cache", "db", "incremental_db", "greybox_tmp",
                "roms", "games", "nvram", "cfg", "config", "snap", "captures",
                "results", "logs", "obj_dir", "scratch", "tmp", "references",
                "private", "tools", "work", "build"}
BLOCKED_SUFFIXES = {".rbf", ".rbf_cd", ".sof", ".pof", ".qar", ".qdb", ".qws",
                    ".qtl", ".qpg", ".rpt", ".summary", ".sld", ".log", ".jou",
                    ".vcd", ".fst", ".wlf", ".vstf",
                    ".exe", ".dll", ".o", ".a", ".pyc", ".pyo",
                    ".rom", ".bin", ".hex", ".mif", ".mem", ".chd", ".zip",
                    ".7z", ".rar", ".tar", ".gz", ".sav", ".nv", ".nvm",
                    ".aggregate", ".vram", ".raw",
                    ".wav", ".flac", ".mp3", ".mp4", ".mkv", ".avi", ".ppm", ".pgm",
                    ".pem", ".key", ".ppk"}
REQUIRED = {"Arcade-ITech32.qpf", "Arcade-ITech32.qsf", "Arcade-ITech32.sdc",
            "Arcade-ITech32.sv", "files.qip", "build_id.v", "README.md", "LICENSE",
            "CREDITS.md", "LICENSES/LGPL-3.0-or-later.txt",
            "LICENSES/BSD-3-Clause-Greg-Miller.txt", "sys/sys.qip", "sys/sys.tcl",
            "sys/sys_analog.tcl", "sys/emu_ports.vh", "rtl/pll.qip", "rtl/pll.v",
            "rtl/pll/pll_0002.qip", "rtl/pll/pll_0002.v",
            "releases/Street Fighter - The Movie (v1.12).mra",
            "releases/Time Killers (v1.32).mra", "releases/BloodStorm (v2.22).mra"}


def main() -> int:
    result = subprocess.run(["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
                            cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    if result.returncode:
        print("Run this checker inside a Git checkout with Git installed.", file=sys.stderr)
        return 1
    candidates = {name for name in result.stdout.decode("utf-8", errors="strict").split("\0") if name}
    problems: list[str] = []
    for name in sorted(candidates):
        relative = PurePosixPath(name)
        lower_parts = [part.lower() for part in relative.parts]
        suffix = relative.suffix.lower()
        if (relative.is_absolute() or ".." in relative.parts or
                any(part in BLOCKED_DIRS or part.startswith((".codex", "output_files"))
                    for part in lower_parts) or suffix in BLOCKED_SUFFIXES or
                name.startswith("sim/build/") or
                (name.startswith("sim/") and suffix in {".json", ".csv", ".png", ".jpg"}) or
                relative.name.lower().startswith(".env") or "known_hosts" in relative.name.lower()):
            problems.append(f"Private/generated file is an upload candidate: {name}")
            continue
        path = ROOT / name
        if path.is_symlink() or not path.is_file():
            problems.append(f"Missing or non-regular upload input: {name}")
            continue
        data = path.read_bytes()
        if b"\0" in data:
            problems.append(f"Unexpected binary file in source distribution: {name}")
            continue
        try:
            contents = data.decode("utf-8-sig")
        except UnicodeDecodeError:
            # Some preserved upstream comments use a legacy single-byte encoding.
            contents = data.decode("latin-1")
        if re.search(r"[A-Za-z]:[\\/]Users[\\/]", contents):
            problems.append(f"Personal absolute host path: {name}")
        if re.search(r"-----BEGIN (?:OPENSSH |RSA |EC )?PRIVATE KEY-----", contents):
            problems.append(f"Private-key material: {name}")
        if suffix == ".mra":
            try:
                mra = ET.fromstring(contents)
                if mra.findtext("rbf") != "Arcade-ITech32":
                    problems.append(f"Unexpected RBF target: {name}")
                for part in mra.findall(".//part"):
                    # ROM names/CRCs and short padding/config bytes are metadata.
                    # Long inline payloads need manual review; never embed a ROM.
                    inline = re.sub(r"\s+", "", part.text or "")
                    if not part.get("name") and len(inline) > 128:
                        problems.append(f"Large inline MRA payload needs review: {name}")
            except ET.ParseError as error:
                problems.append(f"Invalid MRA XML: {name}: {error}")
    required = set(REQUIRED)
    if (ROOT / "files.qip").is_file():
        for line in (ROOT / "files.qip").read_text(encoding="utf-8-sig").splitlines():
            match = re.fullmatch(r"set_global_assignment -name (?:SYSTEMVERILOG|VERILOG|VHDL|SDC)_FILE (\S+)", line)
            if match:
                required.add(match[1])
            elif line.strip() and not line.lstrip().startswith("#"):
                problems.append("Unexpected files.qip syntax; review build-input validation")
    for name in sorted(required - candidates):
        problems.append(f"Required source is absent or ignored: {name}")
    # Catch accidental references to local sibling experiments in active project files.
    qsf = ROOT / "Arcade-ITech32.qsf"
    if qsf.is_file():
        for line in qsf.read_text(encoding="utf-8-sig").splitlines():
            if line.lstrip().startswith("#"):
                continue
            source = re.fullmatch(r"source (\S+)", line.strip())
            if source and source[1] not in candidates:
                problems.append(f"Sourced project file is absent or ignored: {source[1]}")
            if re.search(r"(?:\.\./|[A-Za-z]:/|[A-Za-z]:\\| /rtl/)", line):
                problems.append("Nonportable external path in Arcade-ITech32.qsf")
                break
    if problems:
        for problem in problems:
            print("FAIL:", problem, file=sys.stderr)
        return 1
    print(f"PASS: {len(candidates)} source/documentation files eligible for upload; required core inputs present.")
    print("No detected ROM containers, binary artifacts, generated results, or personal host paths.")
    print("Still review staged additions before publishing; this is not a content-provenance guarantee.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
