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

    def test_parse_fields_keeps_dash_values(self) -> None:
        fields = PULSE.parse_fields(
            "PULSE_CASE program=pulse_codegen case=for-runtime-0-255 layer=codegen"
        )
        self.assertEqual(fields["case"], "for-runtime-0-255")


if __name__ == "__main__":
    unittest.main()
