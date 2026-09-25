"""ROM-free unit tests for the post-fit HDMI placement guard."""

from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from check_hdmi_pll import HDMI_COUNTER, check_netlist


def parameter(counter: int) -> str:
    return f"defparam \\{HDMI_COUNTER} .output_counter_index = {counter};\n"


class HdmiPlacementTests(unittest.TestCase):
    def check(self, text: str) -> int:
        with TemporaryDirectory() as temp:
            path = Path(temp) / "synthetic.vo"
            path.write_text(text, encoding="utf-8")
            return check_netlist(path)

    def test_c5_passes(self):
        self.assertEqual(self.check("// prefix\n" + parameter(5)), 2)

    def test_other_physical_counter_fails(self):
        for counter in (0, 7, 8):
            with self.subTest(counter=counter), self.assertRaises(ValueError):
                self.check(parameter(counter))

    def test_missing_parameter_fails(self):
        with self.assertRaises(ValueError):
            self.check(f"// logical name only: {HDMI_COUNTER}\n")

    def test_duplicate_parameter_fails(self):
        with self.assertRaises(ValueError):
            self.check(parameter(5) + parameter(5))

    def test_unrelated_counter_is_not_a_match(self):
        with self.assertRaises(ValueError):
            self.check(parameter(5).replace("pll_hdmi|", "pll_other|", 1))


if __name__ == "__main__":
    unittest.main()
