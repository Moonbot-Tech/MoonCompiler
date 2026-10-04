#!/usr/bin/env python3
"""Compare N Pulse systems from one result directory (RTL profile stand).

Reads the manifest and logs written by `pulse.py run --systems A,B,C,D ...`,
computes per-case robust cycles/op for every system and prints ratios against
the baseline system, per-layer geometric means, the RTL-versus-ASM-reference
pairs of the hot-rtl program, and (with --placement) where the measured case
procedures and selected RTL routines landed in every system's executable.

Usage:
    stand_compare.py RESULT_DIR [--baseline A] [--placement] [--match REGEX ...]
"""

from __future__ import annotations

import argparse
import json
import math
import re
import statistics
import sys
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS))

import pulse  # noqa: E402
import code_placement  # noqa: E402


RTL_PLACEMENT_PATTERNS = [
    r"SYSUTILS_\$\$_SAMETEXT\$UNICODESTRING\$UNICODESTRING",
    r"SYSUTILS_\$\$_COMPARETEXT\$UNICODESTRING\$UNICODESTRING",
    r"SYSUTILS_\$\$_UPPERCASE\$UNICODESTRING",
    r"SYSUTILS_\$\$_LOWERCASE\$UNICODESTRING",
    r"SYSUTILS_\$\$_TRIM\$UNICODESTRING",
    r"SYSUTILS_\$\$_INTTOSTR\$",
    r"SYSUTILS_\$\$_INTTOHEX\$",
    r"SYSUTILS_\$\$_TRYSTRTOINT",
    r"SYSUTILS_\$\$_STRINGREPLACE\$UNICODESTRING",
    r"SYSUTILS_\$\$_FORMAT\$UNICODESTRING\$array_of_const",
    r"SYSUTILS_\$\$_FLOATTOSTR",
    r"SYSUTILS_\$\$_NOW",
    r"STRUTILS_\$\$_(CONTAINSTEXT|STARTSTEXT|ENDSTEXT)",
    r"SYSTEM_\$\$_FPC_UNICODESTR_(CONCAT|COMPARE_EQUAL|SETLENGTH|UNIQUE|ASSIGN|COPY)",
    r"SYSTEM_\$\$_MOVE\$",
    r"SYSTEM_\$\$_FILLCHAR\$",
    r"SYSTEM_\$\$_UTF8ENCODE|SYSTEM_\$\$_UTF8TOSTRING",
    r"SYSTEM_\$\$_FPC_DYNARRAY_(SETLENGTH|COPY)",
    r"MATH_\$\$_(MAX|MIN|SAMEVALUE|CEIL|FLOOR)\$",
    r"GENERICS\.COLLECTIONS_\$\$_TLIST.*(ADD|INDEXOF|DELETE|INSERT)\$",
    r"GENERICS\.COLLECTIONS_\$\$_TDICTIONARY.*(TRYGETVALUE|FINDBUCKETINDEX|CONTAINSKEY)",
    r"CLASSES_\$\$_TSTRINGLIST.*(INDEXOF|FIND|DOCOMPARETEXT)",
    r"CLASSES_\$\$_TMEMORYSTREAM.*(WRITE|READ|SEEK)\$",
    r"VARIANTS_\$\$_VARTOSTR|SYSTEM_\$\$_FPC_VARIANT_",
]


def geomean(values: list[float]) -> float | None:
    values = [value for value in values if value > 0]
    if not values:
        return None
    return math.exp(sum(math.log(value) for value in values) / len(values))


def allocator_signature(program: str, case: str, row: dict) -> dict | None:
    if program != 'threads' or not case.startswith(('parallel-alloc-free-', 'cross-thread-free-')):
        return None
    if case.startswith('cross-thread-free-'):
        return {'error': 'main-thread producer allocator topology is not recorded; worker graph alone is insufficient'}
    count = int(case.rsplit('-', 1)[1])
    signatures = []
    for workers in row['workers']:
        if len(workers) != 8 or [worker['worker'] for worker in workers] != list(range(8)):
            return {'error': 'missing complete allocator worker identity'}
        active = workers[:count]
        if [worker['row'] for worker in active] != list(range(count)):
            return {'error': 'allocator preferred rows differ from the fixed input'}
        signature = {'rows': list(range(count))}
        for kind in ('class', 'owner'):
            addresses = {}
            groups = []
            for worker in active:
                for size in range(3):
                    address = worker[kind + str(size)]
                    if address == 0:
                        return {'error': 'missing actual bundled-MM class/owner identity'}
                    groups.append(addresses.setdefault(address, len(addresses)))
            signature[kind] = groups
        signatures.append(signature)
    if not signatures or any(value != signatures[0] for value in signatures):
        return {'error': 'allocator collision graph varies between processes'}
    return signatures[0]


def collect_systems(result: Path, collected: tuple | None = None) -> tuple[dict, list[str], dict]:
    rows, manifest = collected if collected is not None else pulse.collect(result)
    systems = list(manifest["systems"])
    grouped: dict[tuple[str, str], dict[str, dict]] = {}
    for (system, program, case), row in rows.items():
        grouped.setdefault((program, case), {})[system] = row
    cases: dict[tuple[str, str], dict[str, dict]] = {}
    for (program, case), per_system in grouped.items():
        metric = pulse.select_primary_metric(program, list(per_system.values()))
        for system, row in per_system.items():
            stats, processes = pulse.process_balanced_stats(row, metric)
            run_centers = [item.median for item in processes]
            run_spread = stats.maximum / stats.minimum
            cases.setdefault((program, case), {})[system] = {
                "center": stats.median,
                "run_centers": run_centers,
                "run_sequences": row["run_sequences"],
                "run_spread": run_spread,
                "sample_spread": pulse.sample_spread(row, metric),
                "prior_instability": row["prior_instability"],
                "metric": metric,
                "oracles": sorted(set(row["oracles"])),
                "layer": row.get("layer", ""),
                "unit": row.get("unit", ""),
                "body_mod64": sorted({address % 64 for address in row.get("bodies", [])}),
                "allocator": allocator_signature(program, case, row),
                "work_mod64": sorted({address % 64 for address in row.get("work_bodies", [])}),
            }
    return cases, systems, manifest


def family_rows(cases: dict, baseline: str, candidate: str, *, paired: bool,
                max_run_spread: float = 1.15) -> dict[str, dict]:
    """One estimator and verdict for reports and acceptance; no selected timing cluster."""
    suffixes = ("", "1", "2", "3")
    expected = {family + suffix for family in (baseline, candidate) for suffix in suffixes}
    result = {}
    for (program, case), per_system in sorted(cases.items()):
        if set(per_system) != expected:
            raise ValueError(f"{program}/{case}: incomplete family, expected {sorted(expected)}")
        oracles = {tuple(item["oracles"]) for item in per_system.values()}
        if len(oracles) != 1 or len(next(iter(oracles))) != 1:
            raise ValueError(f"{program}/{case}: semantic oracles differ")
        layers = {item["layer"] for item in per_system.values()}
        if len(layers) != 1:
            raise ValueError(f"{program}/{case}: layers differ")
        centers = {family: [per_system[family + suffix]["center"] for suffix in suffixes]
                   for family in (baseline, candidate)}
        issues = [] if paired else ["legacy single-file/unpaired measurement"]
        issues.extend(f'{system}: {item["allocator"]["error"]}' for system, item in per_system.items()
                      if item['allocator'] is not None and 'error' in item['allocator'])
        if any(item["prior_instability"] for item in per_system.values()):
            issues.append("prior unstable timing remains in retry history")
        issues.extend(f"{system}: broad within-process timing variation"
                      for system, item in per_system.items() if item["sample_spread"] > max_run_spread)
        ratios = []
        pair_spreads = []
        for suffix in suffixes:
            left, right = per_system[baseline + suffix], per_system[candidate + suffix]
            if len(left["body_mod64"]) != 1 or len(right["body_mod64"]) != 1:
                issues.append(f"{baseline + suffix}/{candidate + suffix}: missing or unstable body placement")
            elif left["body_mod64"] != right["body_mod64"]:
                issues.append(f"{baseline + suffix}/{candidate + suffix}: measured body residues differ")
            if left['work_mod64'] != right['work_mod64']:
                issues.append(f'{baseline + suffix}/{candidate + suffix}: worker body residues differ')
            if left['allocator'] is not None and right['allocator'] is not None:
                if left['allocator'].get('class') != right['allocator'].get('class'):
                    issues.append(f'{baseline + suffix}/{candidate + suffix}: small-class collisions differ')
                if left['allocator'].get('owner') != right['allocator'].get('owner'):
                    issues.append(f'{baseline + suffix}/{candidate + suffix}: backing-owner collisions differ; resource explanation required')
            ratio = right["center"] / left["center"]
            if paired:
                try:
                    pairs = pulse.paired_centers(
                        dict(zip(left["run_sequences"], left["run_centers"])),
                        dict(zip(right["run_sequences"], right["run_centers"])))
                    ratio = pairs.median
                    pair_spread = pairs.maximum / pairs.minimum
                    pair_spreads.append(pair_spread)
                    if pair_spread > max_run_spread:
                        issues.append(f"{baseline + suffix}/{candidate + suffix}: pair spread {pair_spread:.3f}")
                except ValueError as error:
                    issues.append(str(error))
            ratios.append(ratio)
        ratio = statistics.median(ratios)
        if issues:
            verdict = "UNRESOLVED"
        elif all(value > 1.05 for value in ratios):
            verdict = "SLOWER"
        elif all(value < .95 for value in ratios):
            verdict = "faster"
        elif all(.95 <= value <= 1.05 for value in ratios):
            verdict = "within 5%"
        else:
            verdict = "PLACEMENT-DEPENDENT"
        layer = next(iter(layers))
        result[f"{program}/{case}"] = {
            "ratio": ratio, "verdict": verdict, "issues": issues, "layer": layer,
            "metric": next(iter(per_system.values()))["metric"],
            "diagnostic": pulse.diagnostic_layer(layer), "centers": centers,
            "placement_ratios": ratios, "pair_spreads": pair_spreads,
            "run_spreads": {system: item["run_spread"] for system, item in per_system.items()},
            "run_centers": {system: item["run_centers"] for system, item in per_system.items()},
            "allocator_signatures": {system: item['allocator'] for system, item in per_system.items()
                                     if item['allocator'] is not None},
        }
    return result


def print_table(cases: dict, systems: list[str], baseline: str, pattern: re.Pattern | None) -> None:
    others = [system for system in systems if system != baseline]
    header = f"| program | case | layer | {baseline} cyc/op | " + " | ".join(f"{s}/{baseline}" for s in others) + " | oracle |"
    print(header)
    print("| --- | --- | --- | ---: | " + " | ".join("---:" for _ in others) + " | --- |")
    layer_ratios: dict[tuple[str, str], list[float]] = {}
    program_ratios: dict[tuple[str, str], list[float]] = {}
    flagged: list[str] = []
    for (program, case), per_system in sorted(cases.items()):
        if pattern and not pattern.search(case):
            continue
        base = per_system.get(baseline)
        if base is None:
            continue
        oracles = {tuple(item["oracles"]) for item in per_system.values()}
        oracle = "ok" if len(oracles) == 1 and len(next(iter(oracles))) == 1 else "MISMATCH"
        cells = []
        for system in others:
            item = per_system.get(system)
            if item is None:
                cells.append("-")
                continue
            ratio = item["center"] / base["center"]
            if (oracle == "ok" and not pulse.diagnostic_layer(base["layer"])
                    and max(base["run_spread"], item["run_spread"], base["sample_spread"], item["sample_spread"]) <= 1.15):
                layer_ratios.setdefault((system, base["layer"]), []).append(ratio)
                program_ratios.setdefault((system, program), []).append(ratio)
            mark = ""
            if ratio > 1.05:
                mark = " **slow**"
                flagged.append(f"{program}/{case}: {system}/{baseline} = {ratio:.3f}")
            elif ratio < 0.95:
                mark = " fast"
            cells.append(f"{ratio:.3f}{mark}")
        print(f"| {program} | {case} | {base['layer']} | {base['center']:.2f} | " + " | ".join(cells) + f" | {oracle} |")
    print()
    print("## Diagnostic per-system geometric means by program (not family acceptance)")
    print("| program | " + " | ".join(f"{s}/{baseline}" for s in others) + " |")
    print("| --- | " + " | ".join("---:" for _ in others) + " |")
    for program in sorted({program for program, _ in cases}):
        cells = []
        for system in others:
            value = geomean(program_ratios.get((system, program), []))
            cells.append(f"{value:.4f}" if value else "-")
        print(f"| {program} | " + " | ".join(cells) + " |")
    print()
    print("## Diagnostic per-system geometric means by layer (not family acceptance)")
    print("| layer | " + " | ".join(f"{s}/{baseline}" for s in others) + " |")
    print("| --- | " + " | ".join("---:" for _ in others) + " |")
    for layer in sorted({layer for (_, layer) in layer_ratios}):
        cells = []
        for system in others:
            value = geomean(layer_ratios.get((system, layer), []))
            cells.append(f"{value:.4f}" if value else "-")
        print(f"| {layer} | " + " | ".join(cells) + " |")
    if flagged:
        print()
        print("## Cells slower than 1.05x")
        for item in flagged:
            print(f"- {item}")


def print_asm_pairs(cases: dict, systems: list[str]) -> None:
    pairs = [
        (key, (program, case[4:]))
        for key in cases
        for program, case in [key]
        if case.startswith("asm-") and (program, case[4:]) in cases
    ]
    if not pairs:
        return
    print()
    print("## RTL routine versus full-cost ASM reference (RTL / ASM, same binary)")
    print("| case | " + " | ".join(systems) + " |")
    print("| --- | " + " | ".join("---:" for _ in systems) + " |")
    for asm_key, rtl_key in sorted(pairs, key=lambda item: item[1]):
        cells = []
        for system in systems:
            asm = cases[asm_key].get(system)
            rtl = cases[rtl_key].get(system)
            if asm and rtl:
                cells.append(f"{rtl['center'] / asm['center']:.3f} ({rtl['center']:.1f}/{asm['center']:.1f})")
            else:
                cells.append("-")
        print(f"| {rtl_key[1]} | " + " | ".join(cells) + " |")


def print_placement(result: Path, manifest: dict, systems: list[str], baseline: str, extra: list[str]) -> None:
    executables: dict[tuple[str, str], Path] = {}
    for run in manifest["runs"]:
        executables.setdefault((run["system"], run["program"]), pulse.ROOT / run["executable"])
    programs = sorted({program for _, program in executables})
    patterns = RTL_PLACEMENT_PATTERNS + [r"_\$\$_CASE[A-Z0-9_]+\$LONGINT\$\$QWORD"] + extra
    print()
    print("## Code placement per system (entry mod 64 / loop heads mod 64 / normalized code hash)")
    for program in programs:
        scans: dict[str, dict[str, dict]] = {}
        for system in systems:
            exe = executables.get((system, program))
            if exe is None or not exe.is_file():
                continue
            report = code_placement.scan(exe, patterns, False)
            scans[system] = {item["name"]: item for item in report["procedures"]}
        if baseline not in scans:
            continue
        print()
        print(f"### {program}")
        print("| procedure | " + " | ".join(systems) + " | code vs " + baseline + " |")
        print("| --- | " + " | ".join("---" for _ in systems) + " | --- |")
        names = sorted(set().union(*(set(items) for items in scans.values())))
        for name in names:
            cells = []
            base = scans[baseline].get(name)
            same: list[str] = []
            for system in systems:
                item = scans.get(system, {}).get(name)
                if item is None:
                    cells.append("-")
                    continue
                loops = ",".join(str(loop["target_mod64"]) for loop in item["loops"]) or "-"
                cells.append(f"e{item['entry_mod64']} l[{loops}] {item['size']}B")
                if base is not None and system != baseline:
                    same.append(f"{system}:{'same' if item['normalized_sha256'] == base['normalized_sha256'] else 'DIFF'}")
            print(f"| `{name}` | " + " | ".join(cells) + " | " + " ".join(same) + " |")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("result", type=Path)
    parser.add_argument("--baseline")
    parser.add_argument("--placement", action="store_true")
    parser.add_argument("--match", action="append", default=[], help="placement: extra procedure regex")
    parser.add_argument("--case", help="only cases matching this regex")
    args = parser.parse_args()
    result = args.result.resolve()
    cases, systems, manifest = collect_systems(result)
    baseline = args.baseline or systems[0]
    if baseline not in systems:
        raise SystemExit(f"baseline {baseline} not in {systems}")
    print(f"# Stand comparison: {result.name}")
    print(f"Mode `{manifest['mode']}`, systems {systems}, baseline `{baseline}`. Centre = median of process medians; all processes retained.")
    print()
    print_table(cases, systems, baseline, re.compile(args.case) if args.case else None)
    print_asm_pairs(cases, systems)
    if args.placement:
        print_placement(result, manifest, systems, baseline, args.match)
    return 0


if __name__ == "__main__":
    sys.exit(main())
