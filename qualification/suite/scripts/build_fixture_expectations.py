#!/usr/bin/env python3
"""Build reviewed fixture expectations from complete calibration runs."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

import runner  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("run_ids", nargs="+")
    parser.add_argument(
        "--output", default="research/fixture_expected_outcomes.json",
    )
    args = parser.parse_args()

    manifest = runner.load_manifest()
    tests = {test["id"]: test for test in manifest["fixtures"]}
    expected_keys = runner.fixture_matrix(manifest)
    outcomes: dict[str, dict[str, object]] = {}
    calibrations = []
    for run_id in args.run_ids:
        run_dir = ROOT / "results" / "runs" / run_id
        results_path = run_dir / "results.jsonl"
        snapshot_path = run_dir / "manifest.json"
        if not results_path.is_file() or not snapshot_path.is_file():
            raise RuntimeError(f"incomplete calibration run: {run_dir}")
        rows = [
            json.loads(line)
            for line in results_path.read_text(encoding="utf-8").splitlines()
            if line.strip()
        ]
        for row in rows:
            test_id = row["test_id"]
            if test_id not in tests:
                raise RuntimeError(f"unknown fixture result: {test_id}")
            key = runner.fixture_case_key(
                test_id,
                runner.fixture_exact_expectation_compiler(
                    manifest, row["compiler_id"],
                ),
                row["options_id"],
            )
            if key in outcomes:
                raise RuntimeError(f"duplicate fixture result: {key}")
            if key not in expected_keys:
                raise RuntimeError(f"fixture result outside current matrix: {key}")
            test = tests[test_id]
            compiler = manifest["compilers"][row["compiler_id"]]
            if (
                row.get("source_sha256") != runner.sha256(ROOT / test["source"])
                or row.get("compiler_artifact_sha256")
                != runner.compiler_provenance(compiler)
                or not row.get("expectation_met")
            ):
                raise RuntimeError(f"untrusted fixture calibration row: {key}")
            producer = test.get("producer_source")
            if producer and row.get("producer_source_sha256") != runner.sha256(
                ROOT / producer,
            ):
                raise RuntimeError(f"producer provenance mismatch: {key}")
            outcomes[key] = runner.fixture_observation(row, run_dir)
        snapshot = json.loads(snapshot_path.read_text(encoding="utf-8"))
        calibrations.append({
            "run_id": run_id,
            "results_sha256": runner.sha256(results_path),
            "runner_sha256": snapshot.get("_run", {}).get("runner_sha256"),
            "manifest_sha256": snapshot.get("_run", {}).get("input_manifest_sha256"),
        })

    if set(outcomes) != expected_keys:
        missing = sorted(expected_keys - set(outcomes))[:20]
        extra = sorted(set(outcomes) - expected_keys)[:20]
        raise RuntimeError(
            f"calibration matrix mismatch: expected={len(expected_keys)} "
            f"actual={len(outcomes)} missing={missing} extra={extra}"
        )

    payload = {
        "schema": 1,
        "calibrations": calibrations,
        "tests": {
            test_id: runner.fixture_test_provenance(test)
            for test_id, test in sorted(tests.items())
        },
        "outcomes": dict(sorted(outcomes.items())),
    }
    output = ROOT / args.output
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("x", encoding="utf-8") as stream:
        json.dump(payload, stream, indent=2, sort_keys=True)
        stream.write("\n")
    print(json.dumps({
        "cases": len(outcomes),
        "output": str(output.relative_to(ROOT)),
        "sha256": runner.sha256(output),
        "tests": len(tests),
    }, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
