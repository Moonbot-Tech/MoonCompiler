from __future__ import annotations

import importlib.util
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("pulse_both.py")
SPEC = importlib.util.spec_from_file_location("pulse_both", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
BOTH = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = BOTH
SPEC.loader.exec_module(BOTH)


def result(overall: str, cases: dict[str, str]) -> dict[str, object]:
    rows = {}
    for name, verdict in cases.items():
        ratio = {"BETTER": 0.8, "WORSE": 1.2}.get(verdict, 1.0)
        rows[name] = {
            "verdict": verdict,
            "final": {
                "semantic_match": True, "valid_pairs": 3,
                "primary_metrics": ["work_cycles_per_op"],
                "metrics": {"work_cycles_per_op": {
                    "metric": "work_cycles_per_op", "decision": verdict,
                    "median": ratio, "minimum": ratio, "maximum": ratio,
                }},
            },
        }
    return {
        "overall_verdict": overall,
        "elapsed_seconds": 1.0,
        "measurement_seconds": 0.5,
        "cases": rows,
    }


class PulseBothTests(unittest.TestCase):
    def test_synced_runner_contains_negative_control_dependencies(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            for relative in BOTH.SYNC_FILES:
                target = directory / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(BOTH.ROOT / relative, target)
            tools = directory / "qualification/performance/tools"
            subprocess.run([sys.executable, "-I", "-c",
                            "import sys; sys.path.insert(0,sys.argv[1]); import qualify_measurement_method",
                            str(tools)], check=True, capture_output=True, text=True)

    def test_gain_on_one_machine_and_same_on_other_preserves_gain(self) -> None:
        merged = BOTH.merge_results(
            result("BETTER", {"codegen/dep-add": "BETTER"}),
            result("SAME", {"codegen/dep-add": "SAME"}),
            0,
            0,
        )
        self.assertEqual(merged["overall_verdict"], "BETTER")
        self.assertEqual(merged["cases"]["codegen/dep-add"]["verdict"], "BETTER")
        self.assertTrue(merged["passed"])

    def test_opposite_platform_effects_are_a_tradeoff(self) -> None:
        merged = BOTH.merge_results(
            result("BETTER", {"heartbeat/end-to-end-100": "BETTER"}),
            result("WORSE", {"heartbeat/end-to-end-100": "WORSE"}), 0, 1,
        )
        self.assertEqual(merged["overall_verdict"], "TRADEOFF")
        self.assertEqual(merged["cases"]["heartbeat/end-to-end-100"]["verdict"], "TRADEOFF")
        self.assertFalse(merged["passed"])

    def test_noop_and_calibration_cannot_outvote_useful_work(self) -> None:
        cases = {"heartbeat/end-to-end-100": "BETTER", "calibration/asm-dependent-add": "WORSE"}
        cases.update({f"move/same-a0-n{size}": "WORSE" for size in range(100)})
        merged = BOTH.merge_results(result("WORSE", cases), result("WORSE", cases), 1, 1)
        self.assertEqual(merged["overall_verdict"], "BETTER")

    def test_partial_evidence_cannot_become_a_complete_answer(self) -> None:
        cases = {"heartbeat/end-to-end-100": "BETTER", "rtl/strtofloat-double": "UNSTABLE"}
        merged = BOTH.merge_results(result("UNSTABLE", cases), result("UNSTABLE", cases), 1, 1)
        self.assertEqual(merged["overall_verdict"], "BETTER")
        self.assertFalse(merged["assessment"]["complete"])
        self.assertFalse(merged["passed"])

    def test_missing_metrics_do_not_count_as_evidence(self) -> None:
        missing = {"cases": {"heartbeat/end-to-end-100": {"verdict": "BETTER"}}}
        merged = BOTH.merge_results(missing, missing, 0, 0)
        self.assertFalse(merged["assessment"]["complete"])
        self.assertEqual(merged["overall_verdict"], "UNRESOLVED")

    def test_unknown_memory_does_not_hide_a_proven_cpu_cost(self) -> None:
        partial = result("UNSTABLE", {"mm/alloc-free-64": "WORSE"})
        row = partial["cases"]["mm/alloc-free-64"]
        row["verdict"] = "UNSTABLE"
        row["final"]["primary_metrics"].append("memory_peak_resident")
        row["final"]["metrics"]["memory_peak_resident"] = {"decision": "UNSTABLE"}
        merged = BOTH.merge_results(partial, partial, 1, 1)
        self.assertEqual(merged["overall_verdict"], "WORSE")
        self.assertFalse(merged["assessment"]["complete"])

    def test_failed_aa_does_not_establish_a_speed_gain(self) -> None:
        failed = result("BETTER", {"heartbeat/end-to-end-100": "BETTER"})
        failed["stand_preflight_failed"] = True
        merged = BOTH.merge_results(failed, failed, 1, 1)
        self.assertFalse(merged["passed"])
        self.assertEqual(merged["overall_verdict"], "UNRESOLVED")

    def test_report_explains_effects_without_count_verdict(self) -> None:
        cases = {"heartbeat/end-to-end-100": "BETTER", "rtl/strtofloat-double": "WORSE"}
        merged = BOTH.merge_results(result("WORSE", cases), result("WORSE", cases), 1, 1)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            BOTH.write_report(path, merged)
            report = (path / "REPORT.md").read_text(encoding="utf-8")
            self.assertIn("Хуже: топ-10 для TODO", report)
            self.assertIn("Обычные операции", report)
            self.assertIn("CASES.md", report)
            self.assertNotIn("INCONCLUSIVE", report)
            self.assertNotIn("Counts", report)

    def test_worse_on_one_machine_is_worse(self) -> None:
        merged = BOTH.merge_results(
            result("WORSE", {"threads/locked-increment-4": "WORSE"}),
            result("SAME", {"threads/locked-increment-4": "SAME"}),
            1,
            0,
        )
        self.assertEqual(merged["overall_verdict"], "WORSE")
        self.assertEqual(merged["cases"]["threads/locked-increment-4"]["verdict"], "WORSE")

    def test_missing_machine_is_incomplete(self) -> None:
        merged = BOTH.merge_results(
            result("SAME", {"codegen/dep-add": "SAME"}), None, 0, 2
        )
        self.assertFalse(merged["assessment"]["complete"])
        self.assertFalse(merged["passed"])
        self.assertEqual(merged["cases"]["codegen/dep-add"]["verdict"], "INCOMPLETE")

    def test_missing_useful_case_is_not_platform_inapplicable(self) -> None:
        merged = BOTH.merge_results(
            result("SAME", {"heartbeat/end-to-end-100": "SAME", "rtl/strtofloat-double": "SAME"}),
            result("SAME", {"heartbeat/end-to-end-100": "SAME"}), 0, 0,
        )
        self.assertFalse(merged["assessment"]["complete"])
        self.assertEqual(merged["cases"]["rtl/strtofloat-double"]["verdict"], "INCOMPLETE")

    def test_control_semantics_remain_mandatory(self) -> None:
        measured = result("BETTER", {"heartbeat/end-to-end-100": "BETTER", "calibration/asm-dependent-add": "SAME"})
        measured["cases"]["calibration/asm-dependent-add"]["final"]["semantic_match"] = False
        merged = BOTH.merge_results(measured, measured, 1, 1)
        self.assertEqual(merged["overall_verdict"], "SEMANTIC_MISMATCH")
        self.assertFalse(merged["passed"])

    def test_release_top_deduplicates_sizes_and_excludes_diagnostic_instructions(self) -> None:
        measured = result("BETTER", {
            "repairs/roundto-minus2": "BETTER", "repairs/roundto-minus4": "BETTER",
            "codegen/dep-add": "BETTER", "heartbeat/end-to-end-100": "BETTER",
        })
        top = BOTH.pulse_assessment.ranked_changes({"windows": measured}, "BETTER")
        self.assertEqual(len(top), 2)
        self.assertTrue(all(not entry[1].startswith("codegen/") for entry in top))

    def test_completed_measurement_with_losses_is_not_release_acceptance(self) -> None:
        measured = result("WORSE", {"rtl/inttostr-int64": "WORSE"})
        measured["preflight"] = {"passed": True}
        measured["cases"]["rtl/inttostr-int64"]["final"]["valid_pairs"] = 12
        merged = BOTH.merge_results(measured, measured, 0, 0)
        self.assertTrue(merged["measurement_completed"])
        self.assertFalse(merged["passed"])

    def test_repair_abi_probe_and_json_scan_are_diagnostics(self) -> None:
        self.assertEqual(BOTH.pulse_assessment.context("repairs/return-record24-cross-unit", {"layer": "abi"})[0], "mechanism")
        self.assertEqual(BOTH.pulse_assessment.context("json/byte-scan-large-4096", {"layer": "codegen"})[0], "mechanism")

    def test_unreproduced_effect_cannot_enter_release_top_or_be_replaced_by_runner_up(self) -> None:
        measured = result("WORSE", {"rtl/inttostr-int64": "WORSE", "rtl/dictionary-capacity-1024": "WORSE"})
        measured["confirmation_required"] = True
        repeat = result("SAME", {"rtl/inttostr-int64": "SAME"})["cases"]["rtl/inttostr-int64"]
        repeat["final"]["valid_pairs"] = 12
        measured["cases"]["rtl/inttostr-int64"]["confirmation"] = repeat
        self.assertEqual(BOTH.pulse_assessment.ranked_changes({"windows": measured}, "WORSE"), [])
        self.assertEqual(BOTH.pulse_assessment.metric_decisions(measured["cases"]["rtl/inttostr-int64"]), ["UNSTABLE"])

    def test_confirmation_correctness_failure_cannot_be_hidden_by_primary_oracle(self) -> None:
        measured = result("BETTER", {"rtl/inttostr-int64": "BETTER"})
        repeated = result("BETTER", {"rtl/inttostr-int64": "BETTER"})["cases"]["rtl/inttostr-int64"]
        repeated["final"]["semantic_match"] = False
        measured["cases"]["rtl/inttostr-int64"]["confirmation"] = repeated
        merged = BOTH.merge_results(measured, measured, 0, 0)
        self.assertEqual(merged["overall_verdict"], "SEMANTIC_MISMATCH")
        self.assertFalse(merged["measurement_completed"])


if __name__ == "__main__":
    unittest.main()
