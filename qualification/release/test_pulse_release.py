import json
from pathlib import Path
import tempfile
import unittest

from qualification.release import pulse_release


class ReleaseReportTests(unittest.TestCase):
    def test_measured_regression_is_reported_but_failed_measurement_blocks_completion(self):
        final = {"semantic_match": True, "valid_pairs": 12,
                 "primary_metrics": ["work_cycles_per_op"],
                 "metrics": {"work_cycles_per_op": {"decision": "WORSE", "median": 1.2}}}
        result = {"preflight": {"passed": True}, "confirmation_preflight": {"passed": True},
                  "scope": {"cases": "all", "programs": pulse_release.pulse.stand_programs(True)}, "pairs": 12,
                  "confirmation_required": True, "cases": {"rtl/inttostr-int64": {
                      "final": final, "confirmation": {"final": final}}}}
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "result.json"
            (path.parent / "REPORT.md").write_text("A real regression for review")
            path.write_text(json.dumps(result))
            pulse_release.validate_report(path)
            result["confirmation_preflight"]["passed"] = False
            path.write_text(json.dumps(result))
            with self.assertRaises(ValueError):
                pulse_release.validate_report(path)
            result["confirmation_preflight"]["passed"] = True
            result["scope"]["programs"] = ["rtl"]
            path.write_text(json.dumps(result))
            with self.assertRaises(ValueError):
                pulse_release.validate_report(path)

    def test_a_program_the_released_toolchain_cannot_build_is_named_not_a_hole(self):
        final = {"semantic_match": True, "valid_pairs": 12,
                 "primary_metrics": ["work_cycles_per_op"],
                 "metrics": {"work_cycles_per_op": {"decision": "SAME", "median": 1.0}}}
        measured = [program for program in pulse_release.pulse.stand_programs(True) if program != "zlib"]
        result = {"preflight": {"passed": True}, "confirmation_preflight": {"passed": True},
                  "scope": {"cases": "all", "programs": measured, "left_out": {"zlib": ["moon-baseline"]}},
                  "pairs": 12, "confirmation_required": True,
                  "cases": {"rtl/inttostr-int64": {"final": final, "confirmation": {"final": final}}}}
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "result.json"
            (path.parent / "REPORT.md").write_text("zlib: not compared, the release has no System.ZLib")
            path.write_text(json.dumps(result))
            pulse_release.validate_report(path)
            for left_out in ({"zlib": ["moon-candidate"]}, {"zlib": ["moon-baseline", "moon-candidate"]}, {}):
                with self.subTest(left_out=left_out):
                    result["scope"]["left_out"] = left_out
                    path.write_text(json.dumps(result))
                    with self.assertRaises(ValueError):
                        pulse_release.validate_report(path)


if __name__ == "__main__":
    unittest.main()
