#!/usr/bin/env python3
"""Judge the same paired family rows printed by filler_summary.py.

Exit 0 accepts, 1 rejects proven regressions or invalid evidence, and 2
leaves unresolved timing/placement evidence open. ASM references and
calibration remain semantic checks, outside product speed aggregates.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import stand_compare
import check_program_placement


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("result", type=Path)
    parser.add_argument("--baseline", required=True)
    parser.add_argument("--candidate", required=True)
    parser.add_argument("--expect-faster", default="")
    parser.add_argument("--expect-ratio", type=float, default=.97)
    parser.add_argument("--allow-slower", default="")
    parser.add_argument("--programs", default="")
    parser.add_argument("--tolerance", type=float, default=.005)
    parser.add_argument("--max-regressions", type=int, default=0)
    parser.add_argument("--max-run-spread", type=float, default=1.15)
    parser.add_argument("--legacy-baseline-revision", help="explicit source revision of a frozen baseline predating profile.txt")
    args = parser.parse_args()
    cases, systems, manifest = stand_compare.collect_systems(args.result.resolve())
    problems = []
    notes = []
    quick_only = manifest.get("mode") == "quick"
    if quick_only:
        notes.append("quick is diagnostic only; use medium or long for acceptance")
    source_head = str(manifest.get("git_head", ""))
    if len(source_head) != 40 or any(char not in "0123456789abcdef" for char in source_head.lower()):
        problems.append("measurement manifest has no exact source Git HEAD")
    if str(manifest.get("git_status", "")).strip():
        problems.append("measurement source tree is dirty")
    if manifest.get("input_contract") != "fixed-alloc-block16384-v1":
        problems.append("missing fixed-input contract; rebuild the workload with the current harness")
    try:
        placements = check_program_placement.check(args.result.resolve(), [args.baseline, args.candidate])
        (args.result / "program-placement.json").write_text(
            json.dumps(placements, indent=2) + "\n", encoding="utf-8")
    except (ValueError, OSError, RuntimeError) as error:
        problems.append(f"placement provenance: {error}")
    by_case: dict[str, list[str]] = {}
    for program, case in cases:
        by_case.setdefault(case, []).append(f"{program}/{case}")

    def rows_named(option: str, value: str) -> set[str]:
        named = set()
        for name in (item.strip() for item in value.split(",")):
            if not name:
                continue
            if "/" in name:
                named.add(name)
            elif len(by_case.get(name, [])) > 1:
                problems.append(f"{option} {name}: ambiguous, name program/case")
            elif by_case.get(name):
                named.add(by_case[name][0])
            else:
                named.add(name)
        return named

    expect = rows_named("--expect-faster", args.expect_faster)
    allow = rows_named("--allow-slower", args.allow_slower)
    expected_systems = {family + suffix for family in (args.baseline, args.candidate) for suffix in ("", "1", "2", "3")}
    if set(systems) != expected_systems:
        problems.append(f"stand systems differ: got {sorted(systems)}, expected {sorted(expected_systems)}")
    identities = manifest.get("external_toolchains", {})
    for system in sorted(expected_systems):
        identity = identities.get(system, {})
        if not identity:
            problems.append(f"{system}: missing toolchain identity")
        for key in ("fpc_sha256", "backend_sha256", "config_sha256"):
            if not identity.get(key):
                problems.append(f"{system}: missing {key}")
        witnesses = {"system.ppu", "sysutils.o", "math.o", "generics.hashes.o"}
        missing = witnesses - set(identity.get("unit_sha256", {}))
        if missing:
            problems.append(f"{system}: missing installed unit hashes {', '.join(sorted(missing))}")
        if not identity.get("profile_sha256"):
            baseline_member = system in {args.baseline + suffix for suffix in ("", "1", "2", "3")}
            if baseline_member and args.legacy_baseline_revision:
                mm = manifest.get("external_memory_managers", {}).get(system, {})
                if not mm.get("sha256"):
                    problems.append(f"{system}: legacy baseline missing MM hash")
                notes.append(f"{system}: frozen legacy baseline {args.legacy_baseline_revision}; exact hashes recorded, old build profile unproven")
            else:
                problems.append(f"{system}: profile.txt is not hashed")
    try:
        rows = stand_compare.family_rows(cases, args.baseline, args.candidate,
                                         paired=bool(manifest.get("measurement_method")), max_run_spread=args.max_run_spread)
    except ValueError as error:
        problems.append(str(error))
        rows = {}
    if not rows:
        problems.append("no complete semantic family")
    for program in filter(None, map(str.strip, args.programs.split(","))):
        if not any(name.startswith(program + "/") for name in rows):
            problems.append(f"program {program} was asked for and has no judged row in the result")
    product = {name: row for name, row in rows.items() if not row["diagnostic"]}
    unresolved = {name: row for name, row in product.items() if row["verdict"] in ("UNRESOLVED", "PLACEMENT-DEPENDENT")}
    judged = {name: row for name, row in product.items() if name not in unresolved}
    mean = stand_compare.geomean([row["ratio"] for row in judged.values()])
    notes.append(f"cases {len(rows)}, product measured {len(judged)}/{len(product)}, diagnostic {len(rows) - len(product)}")
    if mean is not None:
        notes.append(f"geomean {args.candidate}/{args.baseline} = {mean:.4f}")
        if mean > 1 + args.tolerance:
            problems.append(f"geomean {mean:.4f} above 1+{args.tolerance}")
    for name in sorted(expect):
        row = rows.get(name)
        if row is None:
            problems.append(f"expected case {name} is not in the result")
        elif row["issues"] or any(ratio > args.expect_ratio for ratio in row["placement_ratios"]):
            problems.append(f"{name}: expected faster, got {row['ratio']:.3f} ({row['verdict']})")
        else:
            notes.append(f"{name}: {row['ratio']:.3f} ({row['verdict']})")
    slower = {name: row for name, row in judged.items() if row["verdict"] == "SLOWER" and name not in allow}
    for name, row in slower.items():
        notes.append(f"slower across placements: {name} {row['ratio']:.3f}")
    if len(slower) > args.max_regressions:
        problems.append(f"{len(slower)} cases slower, allowed {args.max_regressions}: " + ", ".join(slower))
    for name, row in unresolved.items():
        notes.append(f"unresolved: {name} {row['ratio']:.3f} ({row['verdict']}; {', '.join(row['issues'])})")
    for note in notes:
        print(f"- {note}")
    if problems:
        print("STAND_AB_GATE_FAIL")
        for problem in problems:
            print(f"  * {problem}")
        return 1
    if quick_only or unresolved or not product:
        print("STAND_AB_GATE_INCONCLUSIVE: unresolved measurements do not prove parity or a machine cause")
        return 2
    print(f"STAND_AB_GATE_PASS geomean={mean:.4f} expected={len(expect)} regressions={len(slower)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
