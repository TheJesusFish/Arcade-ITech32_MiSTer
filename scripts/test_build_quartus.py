#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Check stamp/WhatIf policy without starting Quartus or modifying the checkout."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest

SHELL = shutil.which("pwsh") or shutil.which("powershell")
ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(os.name == "nt" and SHELL, "Windows PowerShell helper tests")
class BuildStampTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "scripts").mkdir()
        shutil.copyfile(ROOT / "scripts/build_quartus.ps1", self.root / "scripts/build_quartus.ps1")
        for name in ("Arcade-ITech32.qpf", "Arcade-ITech32.qsf", "files.qip"):
            (self.root / name).touch()
        self.bin = self.root / "quartus/bin64"
        self.bin.mkdir(parents=True)
        # Deliberately non-executable placeholders satisfy discovery but fail
        # at the process boundary. No fake build can be mistaken for success.
        for tool in ("map", "fit", "asm", "sta"):
            (self.bin / f"quartus_{tool}.exe").touch()
        self.stamp = self.root / "build_id.v"

    def run_helper(self, flow="map", dry=False):
        command = [SHELL, "-NoProfile", "-NonInteractive", "-File",
                   str(self.root / "scripts/build_quartus.ps1"),
                   "-QuartusRoot", str(self.bin.parent), "-Flow", flow]
        if dry:
            command.append("-WhatIf")
        return subprocess.run(command, capture_output=True, text=True, timeout=30)

    def test_whatif_does_not_create_stamp(self):
        result = self.run_helper(dry=True)
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertFalse(self.stamp.exists())

    def test_map_creates_stamp_before_tool_invocation(self):
        result = self.run_helper()
        self.assertNotEqual(0, result.returncode)  # Placeholder is not Quartus.
        self.assertRegex(self.stamp.read_text(), r'^`define BUILD_DATE "[0-9]{6}"$')

    def test_existing_stamp_preserved(self):
        contents = b'`define BUILD_DATE "260101"'
        self.stamp.write_bytes(contents)
        self.assertNotEqual(0, self.run_helper().returncode)
        self.assertEqual(contents, self.stamp.read_bytes())

    def test_later_stage_cannot_invent_stamp(self):
        result = self.run_helper(flow="fit")
        self.assertNotEqual(0, result.returncode)
        self.assertIn("Run a map/compile first", result.stderr)
        self.assertFalse(self.stamp.exists())


if __name__ == "__main__":
    unittest.main()
