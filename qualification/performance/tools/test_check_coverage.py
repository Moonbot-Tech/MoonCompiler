from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("check_coverage.py")
SPEC = importlib.util.spec_from_file_location("check_coverage", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
CHECK_COVERAGE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = CHECK_COVERAGE
SPEC.loader.exec_module(CHECK_COVERAGE)


class PulseCaseContractTests(unittest.TestCase):
    def test_extracts_ordered_literal_pulse_case_matrix(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary) / "pulse_sample.dpr"
            source.write_text(
                "PulseRunCase('pulse_sample', 'first', 'layer', 'unit', nil);\n"
                "PulseRunCase(\n  'pulse_sample', 'second', 'layer', 'unit', nil);\n",
                encoding="utf-8",
            )
            self.assertEqual(
                CHECK_COVERAGE.declared_pulse_cases(source, "PulseRunCase/v1"),
                ["first", "second"],
            )

    def test_extracts_heartbeat_wrapper_case_matrix(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary) / "pulse_sample.dpr"
            source.write_text(
                "Add('first', 'layer', 'description', @First, 1);\n"
                "Add(\n  'second', 'layer', 'description', @Second, 1);\n",
                encoding="utf-8",
            )
            self.assertEqual(
                CHECK_COVERAGE.declared_pulse_cases(source, "PulseAdd/v1"),
                ["first", "second"],
            )

    def test_rejects_unknown_case_contract(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary) / "pulse_sample.dpr"
            source.write_text("", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "unknown Pulse case contract"):
                CHECK_COVERAGE.declared_pulse_cases(source, "unknown")


if __name__ == "__main__":
    unittest.main()
