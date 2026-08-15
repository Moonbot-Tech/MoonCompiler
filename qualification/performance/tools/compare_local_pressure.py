#!/usr/bin/env python3
"""Compare two LOCAL_PRESSURE_SAMPLE logs without hiding raw measurements."""

from __future__ import annotations

import argparse
import math
import re
import statistics
from dataclasses import dataclass
from pathlib import Path


SAMPLE = re.compile(
    r"^LOCAL_PRESSURE_SAMPLE .*case=(?P<case>\S+) .*calls=(?P<calls>\d+) "
    r".*wall_ns=(?P<wall>\d+) .*thread_cpu_ns=(?P<cpu>\d+) "
    r".*tsc_ticks=(?P<tsc>\d+)"
)


def parse(path: Path) -> dict[str, list[dict[str, float]]]:
    result: dict[str, list[dict[str, float]]] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        match = SAMPLE.match(line)
        if match is None:
            continue
        calls = int(match["calls"])
        result.setdefault(match["case"], []).append(
            {
                "wall": int(match["wall"]) / calls,
                "cpu": int(match["cpu"]) / calls,
                "tsc": int(match["tsc"]) / calls,
            }
        )
    if not result:
        raise ValueError(f"no LOCAL_PRESSURE_SAMPLE rows in {path}")
    return result


def half_sample_mode(values: list[float]) -> float:
    """Estimate the center of the densest cluster without histogram bins."""
    window = sorted(values)
    while len(window) > 2:
        width = math.ceil(len(window) / 2)
        start = min(
            range(len(window) - width + 1),
            key=lambda index: window[index + width - 1] - window[index],
        )
        window = window[start : start + width]
    return statistics.mean(window)


@dataclass(frozen=True)
class RobustStats:
    mode: float
    median: float
    mean: float
    minimum: float
    maximum: float
    kept: int
    rejected: int


def robust_stats(rows: list[dict[str, float]], metric: str) -> RobustStats:
    raw = [row[metric] for row in rows]
    center = statistics.median(raw)
    mad = statistics.median(abs(value - center) for value in raw)
    high_limit = center + max(12.0 * mad, center)
    kept = [value for value in raw if value <= high_limit]
    if len(kept) < math.ceil(len(raw) * 0.75):
        raise ValueError("extreme outliers occupy more than 25% of samples")
    return RobustStats(
        mode=half_sample_mode(kept),
        median=statistics.median(kept),
        mean=statistics.mean(kept),
        minimum=min(kept),
        maximum=max(kept),
        kept=len(kept),
        rejected=len(raw) - len(kept),
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("baseline", type=Path)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--baseline-name", default="baseline")
    parser.add_argument("--candidate-name", default="candidate")
    args = parser.parse_args()

    baseline = parse(args.baseline)
    candidate = parse(args.candidate)
    if baseline.keys() != candidate.keys():
        raise ValueError("logs contain different case sets")

    baseline_stats = {
        case_name: robust_stats(rows, "tsc")
        for case_name, rows in baseline.items()
    }
    candidate_stats = {
        case_name: robust_stats(rows, "tsc")
        for case_name, rows in candidate.items()
    }
    if "empty" not in baseline_stats:
        raise ValueError("logs do not contain the required empty-call baseline")

    print("primary=half-sample-mode "
          "extreme_high_filter=median+max(12*MAD,median)")
    print(
        f"{'case':<24} {args.baseline_name + ' stable':>16} "
        f"{args.candidate_name + ' stable':>16} {'candidate/base':>15} "
        f"{'rej b/c':>9}"
    )
    for case_name in baseline:
        baseline_tsc = baseline_stats[case_name]
        candidate_tsc = candidate_stats[case_name]
        print(
            f"{case_name:<24} {baseline_tsc.mode:16.2f} "
            f"{candidate_tsc.mode:16.2f} "
            f"{candidate_tsc.mode / baseline_tsc.mode:15.3f} "
            f"{baseline_tsc.rejected}/{candidate_tsc.rejected:>5}"
        )
        print(
            f"  {args.baseline_name:<12} mode={baseline_tsc.mode:.2f} "
            f"median={baseline_tsc.median:.2f} mean={baseline_tsc.mean:.2f} "
            f"min={baseline_tsc.minimum:.2f} max={baseline_tsc.maximum:.2f} "
            f"kept={baseline_tsc.kept} rejected={baseline_tsc.rejected}"
        )
        print(
            f"  {args.candidate_name:<12} mode={candidate_tsc.mode:.2f} "
            f"median={candidate_tsc.median:.2f} mean={candidate_tsc.mean:.2f} "
            f"min={candidate_tsc.minimum:.2f} max={candidate_tsc.maximum:.2f} "
            f"kept={candidate_tsc.kept} rejected={candidate_tsc.rejected}"
        )

    print("\nnet_body_ticks=case_mode-empty_mode (derived; gross stays primary)")
    print(
        f"{'case':<24} {args.baseline_name + ' net':>16} "
        f"{args.candidate_name + ' net':>16} {'candidate/base':>15}"
    )
    baseline_empty = baseline_stats["empty"].mode
    candidate_empty = candidate_stats["empty"].mode
    for case_name in baseline:
        if case_name == "empty":
            continue
        baseline_net = baseline_stats[case_name].mode - baseline_empty
        candidate_net = candidate_stats[case_name].mode - candidate_empty
        if abs(baseline_net) < 0.01:
            baseline_net = 0.0
        if abs(candidate_net) < 0.01:
            candidate_net = 0.0
        ratio = (
            f"{candidate_net / baseline_net:.3f}"
            if baseline_net > 0.01
            else "n/a"
        )
        print(
            f"{case_name:<24} {baseline_net:16.2f} "
            f"{candidate_net:16.2f} {ratio:>15}"
        )


if __name__ == "__main__":
    main()
