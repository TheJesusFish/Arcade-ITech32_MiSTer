#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Verify MRA ROM parts and calculate Main_MiSTer's source-stream MD5.

Main_MiSTer updates the MRA checksum with each part's source bytes before
interleave mapping.  This tool follows that behavior, locating merged-set ROMs
by CRC across the archives named by the MRA.  It never writes ROM data.
"""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET
import zipfile


def parse_inline_hex(text: str | None) -> bytes:
    compact = re.sub(r"[\s,]+", "", text or "")
    if not compact:
        return b""
    if len(compact) % 2:
        return bytes.fromhex(compact[:-1]) + bytes((int(compact[-1], 16),))
    return bytes.fromhex(compact)


class ArchiveSearch:
    def __init__(self, rom_dir: Path, names: list[str]):
        self.archives: list[tuple[Path, zipfile.ZipFile]] = []
        for name in names:
            path = Path(name)
            if not path.is_absolute():
                path = rom_dir / path
            if path.is_file():
                self.archives.append((path, zipfile.ZipFile(path, "r")))

    def close(self) -> None:
        for _, archive in self.archives:
            archive.close()

    def read_crc(self, expected_name: str, expected_crc: int) -> bytes:
        for archive_path, archive in self.archives:
            matches = [info for info in archive.infolist() if info.CRC == expected_crc]
            if matches:
                exact = [
                    info for info in matches
                    if Path(info.filename).name.casefold() == expected_name.casefold()
                ]
                info = exact[0] if exact else matches[0]
                data = archive.read(info)
                if (zipfile.crc32(data) & 0xFFFFFFFF) != expected_crc:
                    raise RuntimeError(
                        f"CRC readback mismatch for {expected_name} in {archive_path}"
                    )
                return data
        searched = ", ".join(str(path) for path, _ in self.archives) or "no archives"
        raise FileNotFoundError(
            f"{expected_name} CRC {expected_crc:08x} not found; searched {searched}"
        )


def verify_mra(path: Path, rom_dir: Path) -> tuple[str, int, str | None]:
    root = ET.parse(path).getroot()
    roms = [node for node in root.findall("rom") if node.get("index", "0") == "0"]
    if len(roms) != 1:
        raise RuntimeError(f"{path}: expected exactly one index-0 ROM, found {len(roms)}")
    rom = roms[0]
    zip_names = [name for name in rom.get("zip", "").split("|") if name]
    search = ArchiveSearch(rom_dir, zip_names)
    digest = hashlib.md5()
    source_bytes = 0
    try:
        for part in rom.iter("part"):
            repeat = int(part.get("repeat", "1"), 0)
            name = part.get("name")
            if name:
                crc_text = part.get("crc")
                if not crc_text:
                    raise RuntimeError(f"{path}: named part {name} has no CRC")
                payload = search.read_crc(name, int(crc_text, 16))
                offset = int(part.get("offset", "0"), 0)
                length_text = part.get("length")
                payload = payload[offset:]
                if length_text:
                    payload = payload[:int(length_text, 0)]
            else:
                payload = parse_inline_hex(part.text)
            for _ in range(repeat):
                digest.update(payload)
                source_bytes += len(payload)
    finally:
        search.close()
    expected = rom.get("md5")
    return digest.hexdigest(), source_bytes, expected


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--rom-dir", required=True, type=Path)
    parser.add_argument("mras", nargs="+", type=Path)
    args = parser.parse_args()
    failed = False
    for mra in args.mras:
        try:
            actual, source_bytes, expected = verify_mra(mra, args.rom_dir)
            status = "CALCULATED"
            if expected and expected.casefold() != "none":
                status = "PASS" if actual.casefold() == expected.casefold() else "FAIL"
                failed |= status == "FAIL"
            print(
                f"{status} {mra}: md5={actual} source_bytes=0x{source_bytes:x}"
                + (f" expected={expected}" if expected else "")
            )
        except Exception as exc:
            failed = True
            print(f"ERROR {mra}: {exc}", file=sys.stderr)
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
