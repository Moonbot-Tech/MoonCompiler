#!/usr/bin/env python3
"""Print the exact family estimator/verdict used by stand_ab_gate.py."""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

import stand_compare


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("result", type=Path)
    parser.add_argument("--left", required=True)
    parser.add_argument("--right", required=True)
    parser.add_argument("--case")
    args = parser.parse_args()
    cases, systems, manifest = stand_compare.collect_systems(args.result.resolve())
    rows = stand_compare.family_rows(cases, args.left, args.right, paired=bool(manifest.get("measurement_method")))
    pattern = re.compile(args.case) if args.case else None
    print(f"# Placement-controlled comparison {args.right}/{args.left}: {args.result.name}")
    print(f"Mode {manifest['mode']}, systems {systems}. Ratio = median over placements of paired process ratios.")
    print("Unresolved rows retain diagnostic ratios and do not enter product aggregates. All raw process centers are retained.")
    print()
    print("| program/case | ratio | scope | verdict | raw process spread | pair spread |")
    print("| --- | ---: | --- | --- | ---: | ---: |")
    aggregates = {}
    for name, row in rows.items():
        if pattern and not pattern.search(name):
            continue
        scope = "diagnostic" if row["diagnostic"] else "product"
        print(f"| {name} | {row['ratio']:.4f} | {scope} | {row['verdict']} | "
              f"{max(row['run_spreads'].values()):.3f} | {max(row['pair_spreads'], default=0):.3f} |")
        if not row["diagnostic"] and row["verdict"] not in ("UNRESOLVED", "PLACEMENT-DEPENDENT"):
            aggregates.setdefault(name.split("/", 1)[0], []).append(row["ratio"])
    print()
    all_ratios = [value for values in aggregates.values() for value in values]
    value = stand_compare.geomean(all_ratios)
    print(f"Product measured cases: {len(all_ratios)}; geomean: {value:.4f}" if value else "No resolved product measurements.")
    for program, values in sorted(aggregates.items()):
        print(f"- {program}: {stand_compare.geomean(values):.4f} over {len(values)} cases")
    return 0


if __name__ == "__main__":
    sys.exit(main())
