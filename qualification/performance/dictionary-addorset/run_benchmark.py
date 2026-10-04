#!/usr/bin/env python3
"""Black-box TDictionary<Integer,Integer>.AddOrSetValue A/B measurement."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import shutil
import statistics
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
SOURCE = HERE / "dictionary_addorset_bench.dpr"
COMMON = ROOT / "qualification" / "performance" / "common"
GENERICS = ROOT / "packages" / "rtl-generics" / "src"
GENERICS_INC = GENERICS / "inc"


def toolchain_paths(root: Path) -> tuple[Path, Path]:
    if os.name == "nt":
        return (
            root / "bin" / "x86_64-win64" / "ppcx64.exe",
            root / "bin" / "x86_64-win64" / "moon-base.cfg",
        )
    versions = sorted((root / "lib" / "fpc").glob("[0-9]*"))
    if len(versions) != 1:
        raise ValueError(f"cannot identify compiler under {root}")
    return versions[0] / "ppcx64", root / "etc" / "moon-base.cfg"


def pinned_mm(config: Path) -> Path:
    prefix = "--pinned-unit=mormot.core.fpcx64mm="
    for line in config.read_text(encoding="utf-8-sig").splitlines():
        if line.startswith(prefix):
            return Path(line[len(prefix):]).resolve()
    raise ValueError(f"{config}: pinned memory manager is missing")


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def compile_image(
    name: str,
    toolchain: Path,
    output: Path,
    common_generics: bool,
) -> dict:
    compiler, config = toolchain_paths(toolchain)
    mm = pinned_mm(config)
    target = output / "build" / name
    target.mkdir(parents=True)
    command = [
        str(compiler),
        "-n",
        "@" + str(config),
        "-Mdelphi",
        "-O3",
        "-B",
        "-gw3",
        "-Fu" + str(COMMON),
        "-Fi" + str(COMMON),
        "-Fo" + str(COMMON),
        "-FU" + str(target),
        "-FE" + str(target),
        "-dMOONCOMPILER_VANILLA_RUNTIME",
        "-dFPCMM_BOOSTER",
        "-dFPCMM_MOONSHARD",
        "-dNOPATCHRTL",
        "-dMOONBOT_MM_PROFILE_REQUIRED",
        f"--pinned-unit=mormot.core.fpcx64mm={mm}",
        "--required-first-unit=mormot.core.fpcx64mm",
        "-Fu" + str(mm.parent),
    ]
    if common_generics:
        command.extend(("-Fu" + str(GENERICS), "-Fi" + str(GENERICS_INC)))
    command.append(str(SOURCE))
    completed = subprocess.run(
        command,
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=300,
    )
    (target / "build.log").write_text(completed.stdout, encoding="utf-8")
    if completed.returncode:
        raise RuntimeError(f"{name} build failed: {target / 'build.log'}")
    executable = target / ("dictionary_addorset_bench.exe" if os.name == "nt"
                           else "dictionary_addorset_bench")
    return {
        "name": name,
        "compiler": str(compiler),
        "compiler_sha256": sha256(compiler),
        "config_sha256": sha256(config),
        "mm": str(mm),
        "mm_sha256": sha256(mm),
        "common_generics": common_generics,
        "executable": str(executable),
        "executable_sha256": sha256(executable),
        "command": command,
    }


def scenarios() -> list[tuple[str, int, int, str]]:
    rows = []
    for capacity in (256, 4096):
        for fill in (25, 50, 75, 90):
            rows.append(("update", capacity, fill, "default"))
    for capacity in (64, 256):
        for fill in (25, 50, 75, 90):
            rows.append(("update", capacity, fill, "collision"))
    for fill in (25, 50, 75, 90):
        rows.append(("insert", 1048576, fill, "default"))
    for fill in (25, 50, 75):
        rows.append(("mixed", 1048576, fill, "default"))
    return rows


def fields(line: str) -> dict[str, str]:
    return dict(token.split("=", 1) for token in line.split()[1:] if "=" in token)


def run_fresh(executable: Path, scenario: tuple[str, int, int, str]) -> list[dict]:
    with tempfile.TemporaryDirectory(prefix="dict-addorset-", dir=executable.parent) as directory:
        image = Path(directory) / executable.name
        shutil.copy2(executable, image)
        command = [str(image), *(str(item) for item in scenario)]
        completed = subprocess.run(
            command,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=120,
        )
    if completed.returncode or "DICT_END" not in completed.stdout:
        raise RuntimeError(f"benchmark failed: {command}\n{completed.stdout[-2000:]}")
    rows = [fields(line) for line in completed.stdout.splitlines()
            if line.startswith("DICT_SAMPLE ")]
    if len(rows) != 11:
        raise RuntimeError(f"{command}: expected 11 samples, got {len(rows)}")
    return rows


def percentile(values: list[float], quantile: float) -> float:
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, math.ceil(len(ordered) * quantile) - 1)]


def summarize(processes: list[list[dict]]) -> dict:
    metrics = ("wall_ns", "thread_cpu_ns", "process_cpu_ns", "thread_cycles", "tsc_ticks")
    result = {}
    operations = {int(sample["operations"]) for process in processes for sample in process}
    if len(operations) != 1:
        raise ValueError("operation count varies")
    operation_count = operations.pop()
    for metric in metrics:
        process_medians = [
            statistics.median(int(sample[metric]) / operation_count for sample in process)
            for process in processes
        ]
        samples = [
            int(sample[metric]) / operation_count
            for process in processes for sample in process
        ]
        result[metric] = {
            "median": statistics.median(process_medians),
            "minimum": min(process_medians),
            "maximum": max(process_medians),
            "p95_sample": percentile(samples, 0.95),
            "process_spread": (
                max(process_medians) / min(process_medians)
                if min(process_medians) > 0 else None
            ),
        }
    result["throughput_ops_s"] = 1e9 / result["wall_ns"]["median"]
    result["heap_delta"] = sorted({
        int(sample["heap_delta"]) for process in processes for sample in process
    })
    result["object_mod4096"] = sorted({
        int(sample["object_mod4096"]) for process in processes for sample in process
    })
    result["operations"] = operation_count
    result["digests"] = sorted({
        sample["digest"] for process in processes for sample in process
    })
    return result


def geomean(values: list[float]) -> float:
    return math.exp(statistics.mean(math.log(value) for value in values))


def write_report(output: Path, records: dict) -> None:
    rows = records["rows"]
    markdown = [
        "# TDictionary.AddOrSetValue black-box benchmark",
        "",
        "All values are medians of seven fresh-process medians; every process "
        "contains eleven fixed-operation samples on one pinned CPU.",
        "",
        "| mode | scenario | B cycles/op | C cycles/op | C/B | "
        "B wall ns/op | C wall ns/op | C/B wall | C Mops/s | "
        "C p95 cycles | heap delta |",
        "| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |",
    ]
    aggregates = {}
    for mode in ("product", "common-generics"):
        mode_rows = [row for row in rows if row["mode"] == mode]
        ratios_cycles = []
        ratios_wall = []
        baseline_cycles = []
        candidate_cycles = []
        baseline_wall = []
        candidate_wall = []
        for row in mode_rows:
            baseline = row["baseline"]
            candidate = row["candidate"]
            cycle_ratio = candidate["thread_cycles"]["median"] / baseline["thread_cycles"]["median"]
            wall_ratio = candidate["wall_ns"]["median"] / baseline["wall_ns"]["median"]
            ratios_cycles.append(cycle_ratio)
            ratios_wall.append(wall_ratio)
            baseline_cycles.append(baseline["thread_cycles"]["median"])
            candidate_cycles.append(candidate["thread_cycles"]["median"])
            baseline_wall.append(baseline["wall_ns"]["median"])
            candidate_wall.append(candidate["wall_ns"]["median"])
            markdown.append(
                f"| {mode} | {row['scenario']} | "
                f"{baseline['thread_cycles']['median']:.3f} | "
                f"{candidate['thread_cycles']['median']:.3f} | {cycle_ratio:.4f} | "
                f"{baseline['wall_ns']['median']:.3f} | "
                f"{candidate['wall_ns']['median']:.3f} | {wall_ratio:.4f} | "
                f"{candidate['throughput_ops_s'] / 1e6:.3f} | "
                f"{candidate['thread_cycles']['p95_sample']:.3f} | "
                f"{candidate['heap_delta']} |"
            )
        aggregates[mode] = {
            "scenarios": len(mode_rows),
            "baseline_geomean_cycles_per_op": geomean(baseline_cycles),
            "candidate_geomean_cycles_per_op": geomean(candidate_cycles),
            "candidate_over_baseline_cycles": geomean(ratios_cycles),
            "baseline_geomean_wall_ns_per_op": geomean(baseline_wall),
            "candidate_geomean_wall_ns_per_op": geomean(candidate_wall),
            "candidate_over_baseline_wall": geomean(ratios_wall),
        }
    records["aggregates"] = aggregates
    markdown.extend(["", "## Equal-scenario geometric means", ""])
    for mode, aggregate in aggregates.items():
        markdown.append(
            f"- `{mode}`: B `{aggregate['baseline_geomean_cycles_per_op']:.3f}` "
            f"cycles/op, C `{aggregate['candidate_geomean_cycles_per_op']:.3f}` "
            f"cycles/op, C/B `{aggregate['candidate_over_baseline_cycles']:.4f}`; "
            f"wall C/B `{aggregate['candidate_over_baseline_wall']:.4f}`."
        )
    (output / "REPORT.md").write_text("\n".join(markdown) + "\n", encoding="utf-8")
    (output / "summary.json").write_text(
        json.dumps(records, indent=2) + "\n", encoding="utf-8"
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", required=True, type=Path)
    parser.add_argument("--candidate", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    images = {}
    for mode, common_generics in (("product", False), ("common-generics", True)):
        images[mode] = {
            "baseline": compile_image(
                f"{mode}-baseline", args.baseline.resolve(), output, common_generics
            ),
            "candidate": compile_image(
                f"{mode}-candidate", args.candidate.resolve(), output, common_generics
            ),
        }
    records = {
        "source": str(SOURCE),
        "images": images,
        "process_repeats": 7,
        "samples_per_process": 11,
        "rows": [],
    }
    process_order = ("baseline", "candidate", "candidate", "baseline",
                     "baseline", "candidate", "candidate", "baseline",
                     "baseline", "candidate", "candidate", "baseline",
                     "baseline", "candidate")
    for mode in ("product", "common-generics"):
        for scenario in scenarios():
            name = f"{scenario[0]}-c{scenario[1]}-f{scenario[2]}-{scenario[3]}"
            print(f"SCENARIO mode={mode} name={name}", flush=True)
            process_rows = {"baseline": [], "candidate": []}
            for side in process_order:
                executable = Path(images[mode][side]["executable"])
                process_rows[side].append(run_fresh(executable, scenario))
            baseline = summarize(process_rows["baseline"])
            candidate = summarize(process_rows["candidate"])
            if baseline["digests"] != candidate["digests"]:
                raise RuntimeError(f"{mode}/{name}: semantic digest differs")
            records["rows"].append({
                "mode": mode,
                "scenario": name,
                "operation": scenario[0],
                "capacity": scenario[1],
                "fill_percent": scenario[2],
                "hash": scenario[3],
                "baseline": baseline,
                "candidate": candidate,
            })
    write_report(output, records)
    print(f"DICTIONARY_ADDORSET_BENCH_PASS {output / 'REPORT.md'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
