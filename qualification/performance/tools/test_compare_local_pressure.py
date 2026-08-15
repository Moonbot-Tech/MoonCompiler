#!/usr/bin/env python3
"""Regression tests for the robust ticks-per-call statistics."""

from __future__ import annotations

import unittest

from compare_local_pressure import half_sample_mode, robust_stats


def rows(values: list[float]) -> list[dict[str, float]]:
    return [{"tsc": value} for value in values]


class RobustStatisticsTests(unittest.TestCase):
    def test_half_sample_mode_finds_dense_cluster(self) -> None:
        value = half_sample_mode([9.9, 10.0, 10.1, 10.2, 25.0, 40.0, 80.0])
        self.assertGreaterEqual(value, 9.9)
        self.assertLessEqual(value, 10.2)

    def test_ordinary_slow_variation_is_not_deleted(self) -> None:
        values = [10.0] * 20 + [10.5] * 5 + [11.5] * 6
        stats = robust_stats(rows(values), "tsc")
        self.assertEqual(stats.rejected, 0)
        self.assertEqual(stats.maximum, 11.5)

    def test_extreme_upper_outlier_is_deleted(self) -> None:
        values = [10.0] * 30 + [1000.0]
        stats = robust_stats(rows(values), "tsc")
        self.assertEqual(stats.kept, 30)
        self.assertEqual(stats.rejected, 1)
        self.assertEqual(stats.maximum, 10.0)

    def test_lower_fast_sample_is_never_hidden(self) -> None:
        values = [1.0] + [10.0] * 30
        stats = robust_stats(rows(values), "tsc")
        self.assertEqual(stats.rejected, 0)
        self.assertEqual(stats.minimum, 1.0)


if __name__ == "__main__":
    unittest.main()
