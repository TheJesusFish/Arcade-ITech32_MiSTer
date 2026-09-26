#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""ROM-free upload-checker fixtures, including a real clean Git checkout."""
from pathlib import Path
import subprocess
import tempfile
import unittest

from check_source_tree import REQUIRED, ROOT, check_tree


class UploadCheckerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.candidates = set(REQUIRED) | {"rtl/test.sv"}
        for name in self.candidates:
            self.put(name, "// synthetic source\n")
        self.put("files.qip", "set_global_assignment -name SYSTEMVERILOG_FILE rtl/test.sv\n")
        self.put("Arcade-ITech32.qsf", 'source files.qip\nset_global_assignment -name '
                 'PRE_FLOW_SCRIPT_FILE "quartus_sh:sys/build_id.tcl"\n')
        for name in self.candidates:
            if name.endswith(".mra"):
                self.put(name, "<misterromdescription><rbf>ITech32</rbf></misterromdescription>")

    def put(self, name, text):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def check(self):
        return check_tree(self.root, self.candidates)

    def test_clean_without_generated_stamp(self):
        self.assertFalse((self.root / "build_id.v").exists())
        self.assertEqual([], self.check())

    def test_current_qip_all_six_settings(self):
        text = (ROOT / "files.qip").read_text()
        settings = [line for line in text.splitlines() if line.startswith("set_instance_assignment")]
        self.assertEqual(6, len(settings))
        self.put("files.qip", (self.root / "files.qip").read_text() + "\n".join(settings))
        self.assertEqual([], self.check())

    def test_wrong_rbf_and_malformed_xml(self):
        name = "releases/Time Killers (v1.32).mra"
        for target in ("OtherCore", "../ITech32", "ITech32.rbf"):
            with self.subTest(target=target):
                self.put(name, f"<misterromdescription><rbf>{target}</rbf></misterromdescription>")
                self.assertTrue(any("Unexpected RBF" in p for p in self.check()))
        self.put(name, "<misterromdescription>")
        self.assertTrue(any("Invalid MRA XML" in p for p in self.check()))

    def test_full_rbf_basename_supported(self):
        self.put("releases/Time Killers (v1.32).mra",
                 "<misterromdescription><rbf>Arcade-ITech32</rbf></misterromdescription>")
        self.assertEqual([], self.check())

    def test_missing_input_and_generator(self):
        for name in ("rtl/test.sv", "sys/build_id.tcl"):
            with self.subTest(name=name):
                self.candidates.remove(name)
                self.assertTrue(any(name in p for p in self.check()))
                self.candidates.add(name)

    def test_missing_generation_hook(self):
        self.put("Arcade-ITech32.qsf", "source files.qip\n")
        self.assertTrue(any("generation hook" in p for p in self.check()))

    def test_unknown_or_executable_qip_syntax_not_whitelisted(self):
        for line in ('set_instance_assignment -name OTHER_FILE private.sv -to "*"',
                     'set_instance_assignment -name PLL_AUTO_RESET DIRECT -to "*"',
                     'set_instance_assignment -name PLL_AUTO_RESET ON -to "[exec bad]"',
                     'set_instance_assignment -name PLL_AUTO_RESET ON -to "*"; source hidden.qip',
                     'source external.qip'):
            with self.subTest(line=line):
                self.put("files.qip", line)
                self.assertTrue(any("Unexpected files.qip syntax" in p for p in self.check()))

    def test_external_and_dynamic_source_paths(self):
        for path in ("../outside.sv", "/rtl/external.sv", "Q:/outside.sv", "$outside", "[exec]"):
            with self.subTest(path=path):
                self.put("files.qip", "set_global_assignment -name SYSTEMVERILOG_FILE " + path)
                self.assertTrue(any("Nonportable or dynamic" in p for p in self.check()))

    def test_private_and_generated_data_still_rejected(self):
        for name in ("roms/game.zip", "output_files/core.rbf", "sim/results/run.csv", ".env"):
            with self.subTest(name=name):
                self.candidates.add(name)
                self.put(name, "synthetic fixture, not actual data")
                self.assertTrue(any("Private/generated" in p and name in p for p in self.check()))
                self.candidates.remove(name)

    def test_secrets_and_inline_payload_still_rejected(self):
        self.put("rtl/test.sv", "-----BEGIN " + "PRIVATE KEY-----")
        self.assertTrue(any("Private-key" in p for p in self.check()))
        self.put("rtl/test.sv", "// synthetic source")
        self.put("releases/Time Killers (v1.32).mra", '<misterromdescription><rbf>ITech32</rbf>'
                 '<rom><part>' + 'AA' * 65 + '</part></rom></misterromdescription>')
        self.assertTrue(any("Large inline" in p for p in self.check()))

    def test_actual_unignored_git_candidate_set(self):
        self.put(".gitignore", "/build_id.v\n/output_files/\n")
        self.put("build_id.v", "// synthetic local generated stamp")
        self.put("output_files/core.rbf", "synthetic output")
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        subprocess.run(["git", "-C", str(self.root), "add", "."], check=True)
        def candidates():
            result = subprocess.check_output(["git", "-C", str(self.root), "ls-files", "-z",
                                              "--cached", "--others", "--exclude-standard"])
            return set(result.decode().rstrip("\0").split("\0"))
        self.assertNotIn("build_id.v", candidates())
        self.assertEqual([], check_tree(self.root, candidates()))
        # Ignoring a path must not conceal an accidentally tracked artifact.
        subprocess.run(["git", "-C", str(self.root), "add", "-f", "output_files/core.rbf"], check=True)
        self.assertTrue(any("Private/generated" in p for p in check_tree(self.root, candidates())))


if __name__ == "__main__":
    unittest.main()
