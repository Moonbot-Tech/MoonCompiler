#!/usr/bin/env python3
"""Recompute statistics from saved pairs into a separate, explicitly derived report."""
from __future__ import annotations

import argparse
import gzip
import json
from pathlib import Path

import pulse_full


def reanalyze(path: Path, output: Path) -> dict:
    opener = gzip.open if path.suffix == ".gz" else open
    with opener(path, "rt", encoding="utf-8") as stream:
        result = json.load(stream)
    if result.get("raw_result"):
        raw = path.parent / result["raw_result"]
        if not result.get("raw_sha256") or pulse_full.sha256(raw) != result["raw_sha256"]:
            raise ValueError("raw/compact identity is unverified; pass a complete raw result explicitly")
        with gzip.open(raw, "rt", encoding="utf-8") as stream:
            result = json.load(stream)
    for row in result["cases"].values():
        case = pulse_full.Case(row["program"], row["case"], row["layer"], row["unit"], row["category"])
        records = row["final"]["records"]
        if not records or any("derived" not in record for record in records):
            raise ValueError("complete process records with machine-derived counters are required")
        # Windows and Linux use different counters: preserve the originating
        # machine's validated costs, never reinterpret them using this host OS.
        row["final"] = pulse_full.analyze_case(records, case)
        row["verdict"] = pulse_full.verdict(case, row["final"])
        if row.get("confirmation"):
            confirmation = row["confirmation"]
            if not confirmation["final"]["records"]:
                raise ValueError("raw confirmation records are required")
            confirmation["final"] = pulse_full.analyze_case(confirmation["final"]["records"], case)
            confirmation["verdict"] = pulse_full.verdict(case, confirmation["final"])
    result["reanalyzed_from"] = {"path": str(path), "sha256": pulse_full.sha256(path)}
    result["method"] = "pulse-fixed-work-median-v4-reanalysis"
    pulse_full.set_overall_verdict(result)
    output.mkdir(parents=True, exist_ok=False)
    pulse_full.write_result(output, result)
    return result


def run() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("result", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    reanalyze(args.result.resolve(), args.output.resolve())
    print(f"PULSE_REANALYZE output={args.output.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(run())
