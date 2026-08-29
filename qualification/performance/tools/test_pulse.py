from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("pulse.py")
SPEC = importlib.util.spec_from_file_location("pulse", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
PULSE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = PULSE
SPEC.loader.exec_module(PULSE)


class PulseStatisticsTests(unittest.TestCase):
    def test_half_sample_mode_selects_dense_cluster(self) -> None:
        values = [10.0, 10.1, 10.2, 10.15, 10.05, 40.0, 80.0]
        self.assertAlmostEqual(PULSE.half_sample_mode(values), 10.075, places=3)

    def test_robust_stats_rejects_only_extreme_high_tail(self) -> None:
        stats = PULSE.robust_stats([10.0, 10.1, 10.2, 10.0, 10.1, 1000.0])
        self.assertEqual(stats.rejected, 1)
        self.assertEqual(stats.kept, 5)

    def test_robust_stats_keeps_dense_mode_with_large_high_tail(self) -> None:
        values = [10.0 + index * 0.001 for index in range(23)] + [25.0] * 14
        stats = PULSE.robust_stats(values)
        self.assertEqual(stats.kept, 23)
        self.assertEqual(stats.rejected, 14)
        self.assertLess(stats.mode, 10.1)

    def test_process_stats_rejects_one_slow_process(self) -> None:
        stats = PULSE.robust_stats(
            [10.0, 10.1, 10.0, 10.2, 10.1, 10.0, 18.0],
            process_level=True,
        )
        self.assertEqual(stats.kept, 6)
        self.assertEqual(stats.rejected, 1)
        self.assertLess(stats.maximum / stats.minimum, 1.03)

    def test_ratio_stats_rejects_high_and_low_outliers(self) -> None:
        stats = PULSE.robust_ratio_stats([0.5, 0.99, 1.0, 1.01, 1.02, 1.6, 2.0])
        self.assertEqual(stats.kept, 4)
        self.assertEqual(stats.rejected, 3)
        self.assertLessEqual(stats.maximum / stats.minimum, 1.25)

    def test_ratio_stats_requires_a_majority_cluster(self) -> None:
        with self.assertRaisesRegex(ValueError, "at least half"):
            PULSE.robust_ratio_stats([0.5, 0.7, 1.0, 1.4, 2.0])

    def test_parse_fields_keeps_dash_values(self) -> None:
        fields = PULSE.parse_fields(
            "PULSE_CASE program=pulse_codegen case=for-runtime-0-255 layer=codegen"
        )
        self.assertEqual(fields["case"], "for-runtime-0-255")

    def test_primary_metric_uses_cycles_when_every_process_has_them(self) -> None:
        row = {"run_samples": [[{"cycles": 10.0}], [{"cycles": 11.0}]]}
        self.assertEqual(PULSE.select_primary_metric("abi", [row, row]), "cycles")

    def test_primary_metric_falls_back_to_tsc_when_cycles_are_unavailable(self) -> None:
        cycles = {"run_samples": [[{"cycles": 10.0}], [{"cycles": 11.0}]]}
        no_cycles = {"run_samples": [[{"cycles": 0.0}], [{"cycles": 0.0}]]}
        self.assertEqual(
            PULSE.select_primary_metric("abi", [cycles, no_cycles]), "tsc"
        )

    def test_move_and_threads_always_use_tsc(self) -> None:
        row = {"run_samples": [[{"cycles": 10.0}]]}
        self.assertEqual(PULSE.select_primary_metric("move", [row]), "tsc")
        self.assertEqual(PULSE.select_primary_metric("threads", [row]), "tsc")

    def test_tsc_fallback_uses_adjacent_process_pairs(self) -> None:
        self.assertTrue(PULSE.use_paired_process_ratios("abi", "tsc"))
        self.assertTrue(PULSE.use_paired_process_ratios("move", "cycles"))
        self.assertFalse(PULSE.use_paired_process_ratios("abi", "cycles"))


if __name__ == "__main__":
    unittest.main()
