#!/usr/bin/env python3
"""Build, pair-run and compare the Moon Compiler Pulse qualification suite."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import platform
import re
import shutil
import statistics
import subprocess
import sys
import time
from dataclasses import asdict, dataclass
from pathlib import Path


PERF_ROOT = Path(__file__).resolve().parents[1]
ROOT = PERF_ROOT.parents[1]
COMMON = PERF_ROOT / "common"
RESULTS = PERF_ROOT / "results" / "pulse"
IS_WINDOWS = os.name == "nt"
DCC64 = Path(r"C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\dcc64.exe")
if IS_WINDOWS:
    MOON_FPC = ROOT / ".moonbot" / "toolchain" / "bin" / "x86_64-win64" / "fpc.exe"
    MOON_CFG = ROOT / ".moonbot" / "toolchain" / "bin" / "x86_64-win64" / "fpc.cfg"
else:
    MOON_FPC = ROOT / ".moonbot" / "toolchain" / "bin" / "fpc"
    MOON_CFG = ROOT / ".moonbot" / "toolchain" / "etc" / "fpc.cfg"
MM_SOURCE = ROOT / "runtime" / "mm" / "mormot.core.fpcx64mm.pas"

PROGRAMS = {
    name: PERF_ROOT / name / f"pulse_{name}.dpr"
    for name in (
        "calibration",
        "abi",
        "codegen",
        "numeric",
        "loops",
        "layout",
        "move",
        "dispatch",
        "managed",
        "algorithms",
        "dictionary",
        "json",
        "mormot-json",
        "mm",
        "rtl",
        "rtl-collections",
        "threads",
        "workloads",
        "heartbeat",
        "kernels",
    )
}
PROGRAMS["local-pressure"] = PERF_ROOT / "local-pressure" / "pulse_local_pressure.dpr"
MORMOT_PRODUCT = ROOT / "qualification" / "vendor" / "mormot-product"
PROGRAM_UNIT_PATHS = {
    "mormot-json": [MORMOT_PRODUCT / "src" / "core"],
    "heartbeat": [MORMOT_PRODUCT / "src" / "core"],
}
SYSTEM_LABELS = {
    "delphi": "Delphi 12.2 + default FastMM4",
    "moon": "Moon Compiler + bundled fpcx64mm",
    "moon-default": "Moon Compiler + FPC default MM",
    "moon-baseline": "Moon Compiler baseline + bundled fpcx64mm",
    "moon-candidate": "Moon Compiler candidate + bundled fpcx64mm",
}
EXTERNAL_MOON_SYSTEMS = ("moon-baseline", "moon-candidate")


def run(command: list[str], *, cwd: Path = ROOT, capture: bool = False) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        cwd=cwd,
        check=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.STDOUT if capture else None,
    )


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def output_dir(program: str, system: str) -> Path:
    return PERF_ROOT / program / f"build-{system}"


def executable(program: str, system: str) -> Path:
    suffix = ".exe" if IS_WINDOWS else ""
    return output_dir(program, system) / f"{PROGRAMS[program].stem}{suffix}"


def build_delphi(program: str) -> Path:
    if not DCC64.is_file():
        raise FileNotFoundError(f"Delphi 12.2 dcc64.exe not found: {DCC64}")
    source = PROGRAMS[program]
    target = output_dir(program, "delphi")
    target.mkdir(parents=True, exist_ok=True)
    unit_paths = [COMMON, *PROGRAM_UNIT_PATHS.get(program, [])]
    run(
        [
            str(DCC64),
            "-B",
            "-Q",
            "-$O+",
            "--inline:auto",
            "-NSSystem;Winapi;System.Win;Data;Xml",
            *(f"-U{path}" for path in unit_paths),
            *(f"-I{path}" for path in unit_paths),
            f"-E{target}",
            f"-N0{target}",
            str(source),
        ]
    )
    return executable(program, "delphi")


def moon_toolchain_paths(toolchain: Path | None = None) -> tuple[Path, Path]:
    if toolchain is None:
        return MOON_FPC, MOON_CFG
    if IS_WINDOWS:
        return (
            toolchain / "bin" / "x86_64-win64" / "fpc.exe",
            toolchain / "bin" / "x86_64-win64" / "fpc.cfg",
        )
    return toolchain / "bin" / "fpc", toolchain / "etc" / "fpc.cfg"


def moon_toolchain_backends(toolchain: Path) -> list[Path]:
    return sorted(
        {
            path.resolve()
            for pattern in ("ppcx64", "ppcx64.exe")
            for path in toolchain.rglob(pattern)
            if path.is_file()
        },
        key=str,
    )


def moon_toolchain_backend(toolchain: Path) -> Path:
    backends = moon_toolchain_backends(toolchain)
    if len(backends) != 1:
        raise RuntimeError(
            f"external Moon toolchain must contain exactly one x86-64 backend: "
            f"{toolchain} has {backends}"
        )
    return backends[0]


def moon_toolchain_identity(toolchain: Path) -> dict[str, object]:
    moon_fpc, moon_cfg = moon_toolchain_paths(toolchain)
    backend = moon_toolchain_backend(toolchain)
    return {
        "root": str(toolchain.resolve()),
        "fpc": str(moon_fpc.resolve()),
        "fpc_sha256": sha256(moon_fpc),
        "config": str(moon_cfg.resolve()),
        "config_sha256": sha256(moon_cfg),
        "backend": str(backend),
        "backend_sha256": sha256(backend),
    }


def moon_mm_options(default_mm: bool) -> list[str]:
    if default_mm:
        return [
            "-dPULSE_DEFAULT_MM",
            "-dMOONCOMPILER_VANILLA_RUNTIME",
            "-Fafpwinmonitor" if IS_WINDOWS else "-Facthreads,cwstring,fpmonitor",
            "-uMOONBOT_MM_PROFILE_REQUIRED",
            "-uFPCMM_BOOSTER",
            "-uFPCMM_MOONSHARD",
        ]
    return [
        "-uMOONCOMPILER_VANILLA_RUNTIME",
        "-dFPCMM_BOOSTER",
        "-dFPCMM_MOONSHARD",
        "-dMOONBOT_MM_PROFILE_REQUIRED",
        f"--pinned-unit=mormot.core.fpcx64mm={MM_SOURCE.resolve()}",
        "--required-first-unit=mormot.core.fpcx64mm",
        f"-Fu{MM_SOURCE.parent}",
    ]


def build_moon(
    program: str,
    default_mm: bool,
    *,
    system: str | None = None,
    toolchain: Path | None = None,
    extra_options: list[str] | None = None,
) -> Path:
    moon_fpc, moon_cfg = moon_toolchain_paths(toolchain)
    moon_compiler = moon_toolchain_backend(toolchain) if toolchain else moon_fpc
    if not moon_compiler.is_file() or not moon_cfg.is_file():
        raise FileNotFoundError("Moon toolchain is not built; run ./build compiler")
    system = system or ("moon-default" if default_mm else "moon")
    target = output_dir(program, system)
    target.mkdir(parents=True, exist_ok=True)
    unit_paths = [COMMON, *PROGRAM_UNIT_PATHS.get(program, [])]
    args = [
        str(moon_compiler),
        "-n",
        f"@{moon_cfg}",
        "-Mdelphi",
        "-O3",
        "-B",
        *(f"-Fu{path}" for path in unit_paths),
        *(f"-Fi{path}" for path in unit_paths),
        f"-FE{target}",
        f"-FU{target}",
    ]
    args.extend(extra_options or [])
    args.extend(moon_mm_options(default_mm))
    run(args + [str(PROGRAMS[program])])
    return executable(program, system)


def build(
    programs: list[str],
    systems: list[str],
    external_toolchains: dict[str, Path] | None = None,
    external_options: dict[str, list[str]] | None = None,
) -> dict[str, dict[str, Path]]:
    external_toolchains = external_toolchains or {}
    external_options = external_options or {}
    built: dict[str, dict[str, Path]] = {}
    for system in systems:
        built[system] = {}
        for program in programs:
            print(f"BUILD system={system} program={program}", flush=True)
            if system == "delphi":
                path = build_delphi(program)
            elif system == "moon":
                path = build_moon(program, False)
            elif system == "moon-default":
                path = build_moon(program, True)
            elif system in EXTERNAL_MOON_SYSTEMS:
                path = build_moon(
                    program,
                    False,
                    system=system,
                    toolchain=external_toolchains[system],
                    extra_options=external_options.get(system),
                )
            else:
                raise ValueError(f"unknown system: {system}")
            built[system][program] = path
    return built


def git_text(*args: str) -> str:
    try:
        return run(["git", *args], capture=True).stdout.strip()
    except subprocess.CalledProcessError:
        return "<unavailable>"


def machine_metadata() -> dict[str, object]:
    metadata = {
        "platform": platform.platform(),
        "machine": platform.machine(),
        "processor": platform.processor(),
        "logical_cpu_count": os.cpu_count(),
    }
    if hasattr(os, "sched_getaffinity"):
        metadata["process_cpu_affinity"] = sorted(os.sched_getaffinity(0))
    return metadata


def qualification_input_hashes(
    external_toolchains: dict[str, Path] | None = None,
) -> dict[str, str]:
    inputs: dict[str, str] = {}
    fixed = [MOON_FPC, MOON_CFG, MM_SOURCE]
    fixed.extend(sorted((ROOT / ".moonbot" / "toolchain").rglob("ppcx64")))
    fixed.extend(sorted((ROOT / ".moonbot" / "toolchain").rglob("ppcx64.exe")))
    if IS_WINDOWS:
        fixed.append(DCC64)
    for toolchain in (external_toolchains or {}).values():
        moon_fpc, moon_cfg = moon_toolchain_paths(toolchain)
        fixed.extend((moon_fpc, moon_cfg))
        fixed.extend(sorted(toolchain.rglob("ppcx64")))
        fixed.extend(sorted(toolchain.rglob("ppcx64.exe")))
    for path in fixed:
        if path.is_file():
            resolved = path.resolve()
            key = (
                str(resolved.relative_to(ROOT))
                if resolved.is_relative_to(ROOT)
                else str(resolved)
            )
            inputs[key] = sha256(path)
    for path in sorted(PERF_ROOT.rglob("*")):
        if not path.is_file():
            continue
        relative = path.relative_to(PERF_ROOT)
        if any(
            part == "results"
            or part == "__pycache__"
            or part.startswith("build-")
            for part in relative.parts
        ):
            continue
        inputs[str(Path("qualification/performance") / relative)] = sha256(path)
    return inputs


def discover_cases(exe: Path) -> list[str]:
    discovery = run([str(exe), "list", "all"], capture=True).stdout
    cases = [
        parse_fields(line)["case"]
        for line in discovery.splitlines()
        if line.startswith("PULSE_CASEDEF ")
    ]
    if not cases or len(cases) != len(set(cases)):
        raise RuntimeError(f"invalid case discovery from {exe}")
    return cases


def run_suite(
    mode: str,
    programs: list[str],
    systems: list[str],
    tag: str,
    external_toolchains: dict[str, Path] | None = None,
    external_options: dict[str, list[str]] | None = None,
) -> Path:
    external_toolchains = external_toolchains or {}
    external_options = external_options or {}
    built = build(programs, systems, external_toolchains, external_options)
    result = RESULTS / tag
    result.mkdir(parents=True, exist_ok=False)
    repeats = {"quick": 2, "medium": 7, "long": 9}[mode]
    palindrome = systems + list(reversed(systems))
    order = palindrome * (repeats // 2)
    if repeats % 2:
        order.extend(systems)
    runs: list[dict[str, object]] = []
    schedule: list[tuple[int, str, str, str, Path]] = []
    if mode == "quick":
        for program in programs:
            for sequence, system in enumerate(order, 1):
                schedule.append((sequence, system, program, "all", built[system][program]))
    else:
        for program in programs:
            expected_cases: list[str] | None = None
            for system in systems:
                cases = discover_cases(built[system][program])
                if expected_cases is None:
                    expected_cases = cases
                elif cases != expected_cases:
                    raise RuntimeError(
                        f"case matrix differs for {program}: {systems[0]}={expected_cases}, "
                        f"{system}={cases}"
                    )
            assert expected_cases is not None
            for selected_case in expected_cases:
                for sequence, system in enumerate(order, 1):
                    schedule.append(
                        (sequence, system, program, selected_case, built[system][program])
                    )

    for sequence, system, program, selected_case, exe in schedule:
        suffix = "" if selected_case == "all" else f"-{selected_case}"
        log = result / f"{sequence:02d}-{system}-{program}{suffix}.log"
        print(
            f"RUN sequence={sequence} system={system} program={program} "
            f"mode={mode} case={selected_case}",
            flush=True,
        )
        try:
            completed = run([str(exe), mode, selected_case], capture=True)
        except subprocess.CalledProcessError as error:
            log.write_text(error.stdout or "", encoding="utf-8", newline="\n")
            raise RuntimeError(f"benchmark failed; complete output is in {log}") from error
        log.write_text(completed.stdout, encoding="utf-8", newline="\n")
        if "PULSE_END" not in completed.stdout or "status=PASS" not in completed.stdout:
            raise RuntimeError(f"missing PASS terminal in {log}")
        runs.append(
            {
                "sequence": sequence,
                "system": system,
                "program": program,
                "case": selected_case,
                "executable": str(exe.relative_to(ROOT)),
                "executable_sha256": sha256(exe),
                "log": log.name,
                "log_sha256": sha256(log),
            }
        )
    manifest = {
        "schema": 1,
        "project": "Moon Compiler Pulse",
        "created_unix": time.time(),
        "command": sys.argv,
        "mode": mode,
        "git_head": git_text("rev-parse", "HEAD"),
        "git_status": git_text("status", "--porcelain=v1"),
        "machine": machine_metadata(),
        "input_sha256": qualification_input_hashes(external_toolchains),
        "systems": {system: SYSTEM_LABELS[system] for system in systems},
        "external_toolchains": {
            system: moon_toolchain_identity(toolchain)
            for system, toolchain in external_toolchains.items()
        },
        "external_options": external_options,
        "runs": runs,
    }
    (result / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    write_report(result)
    print(f"PULSE_RESULT {result}")
    return result


def parse_fields(line: str) -> dict[str, str]:
    fields: dict[str, str] = {}
    for token in line.split()[1:]:
        if "=" in token:
            key, value = token.split("=", 1)
            fields[key] = value
    return fields


@dataclass(frozen=True)
class Stats:
    mode: float
    median: float
    mean: float
    minimum: float
    maximum: float
    kept: int
    rejected: int


def half_sample_mode(values: list[float]) -> float:
    window = sorted(values)
    while len(window) > 2:
        width = math.ceil(len(window) / 2)
        start = min(
            range(len(window) - width + 1),
            key=lambda index: window[index + width - 1] - window[index],
        )
        window = window[start : start + width]
    return statistics.mean(window)


def robust_stats(values: list[float], process_level: bool = False) -> Stats:
    center = statistics.median(values)
    mad = statistics.median(abs(value - center) for value in values)
    if process_level:
        high_limit = center * 1.25
    else:
        high_limit = center + max(12.0 * mad, center)
    kept = [value for value in values if value <= high_limit]
    if len(kept) < math.ceil(len(values) * 0.5):
        raise ValueError("no stable cluster contains at least half of the samples")
    return Stats(
        mode=half_sample_mode(kept),
        median=statistics.median(kept),
        mean=statistics.mean(kept),
        minimum=min(kept),
        maximum=max(kept),
        kept=len(kept),
        rejected=len(values) - len(kept),
    )


def robust_ratio_stats(values: list[float], maximum_spread: float = 1.25) -> Stats:
    """Select the narrowest largest reciprocal-symmetric ratio cluster."""
    window = sorted(value for value in values if value > 0)
    minimum_kept = math.ceil(len(values) * 0.5)
    candidates: list[list[float]] = []
    for start in range(len(window)):
        end = start
        while end < len(window) and window[end] / window[start] <= maximum_spread:
            end += 1
        candidates.append(window[start:end])
    kept = max(
        candidates,
        key=lambda candidate: (
            len(candidate),
            -(candidate[-1] / candidate[0]) if candidate else float("-inf"),
        ),
        default=[],
    )
    if len(kept) < minimum_kept:
        raise ValueError("no stable ratio cluster contains at least half of the pairs")
    return Stats(
        mode=half_sample_mode(kept),
        median=statistics.median(kept),
        mean=statistics.mean(kept),
        minimum=min(kept),
        maximum=max(kept),
        kept=len(kept),
        rejected=len(values) - len(kept),
    )


def process_balanced_stats(
    row: dict[str, object], metric: str = "tsc"
) -> tuple[Stats, list[Stats]]:
    run_stats = [
        robust_stats([sample[metric] for sample in samples if sample[metric] > 0])
        for samples in row["run_samples"]
    ]
    return robust_stats([stats.mode for stats in run_stats], True), run_stats


def process_balanced_cycles(row: dict[str, object]) -> Stats | None:
    run_modes: list[float] = []
    for samples in row["run_samples"]:
        values = [sample["cycles"] for sample in samples if sample["cycles"] > 0]
        if values:
            run_modes.append(robust_stats(values).mode)
    return robust_stats(run_modes, True) if run_modes else None


def metric_available(row: dict[str, object], metric: str) -> bool:
    """Return whether every process has at least one usable metric sample."""
    run_samples = row["run_samples"]
    return bool(run_samples) and all(
        any(sample[metric] > 0 for sample in samples) for samples in run_samples
    )


def select_primary_metric(
    program: str, rows: list[dict[str, object]]
) -> str:
    """Prefer scheduled cycles, with an explicit TSC fallback when unavailable."""
    if program in ("threads", "move"):
        return "tsc"
    return "cycles" if all(metric_available(row, "cycles") for row in rows) else "tsc"


def use_paired_process_ratios(program: str, metric: str) -> bool:
    """Pair frequency-sensitive TSC processes in the palindromic schedule."""
    return program == "move" or metric == "tsc"


def paired_ratio_stats(
    baseline: dict[str, object], candidate: dict[str, object], metric: str
) -> Stats:
    def modes_by_sequence(row: dict[str, object]) -> dict[int, float]:
        return {
            sequence: robust_stats(
                [sample[metric] for sample in samples if sample[metric] > 0]
            ).mode
            for sequence, samples in zip(row["run_sequences"], row["run_samples"])
        }

    baseline_modes = modes_by_sequence(baseline)
    candidate_modes = modes_by_sequence(candidate)
    events = sorted(
        [(sequence, "baseline", value) for sequence, value in baseline_modes.items()]
        + [(sequence, "candidate", value) for sequence, value in candidate_modes.items()]
    )
    ratios: list[float] = []
    index = 0
    while index + 1 < len(events):
        first, second = events[index], events[index + 1]
        if (second[0] == first[0] + 1) and (first[1] != second[1]):
            values = {first[1]: first[2], second[1]: second[2]}
            ratios.append(values["candidate"] / values["baseline"])
            index += 2
        else:
            index += 1
    if not ratios:
        raise ValueError("no adjacent baseline/candidate process pairs")
    return robust_ratio_stats(ratios)


def effective_core_stats(row: dict[str, object]) -> Stats | None:
    values = [
        total["effective_cores"]
        for total in row["totals"]
        if total["effective_cores"] > 0
    ]
    return robust_stats(values, True) if values else None


def collect(result: Path) -> tuple[dict[tuple[str, str, str], dict[str, object]], dict[str, object]]:
    manifest = json.loads((result / "manifest.json").read_text(encoding="utf-8"))
    rows: dict[tuple[str, str, str], dict[str, object]] = {}
    for item in manifest["runs"]:
        system = item["system"]
        program = item["program"]
        log_samples: dict[tuple[str, str, str], list[dict[str, float]]] = {}
        for line in (result / item["log"]).read_text(encoding="utf-8").splitlines():
            if line.startswith("PULSE_CASE "):
                fields = parse_fields(line)
                key = (system, program, fields["case"])
                row = rows.setdefault(
                    key, {
                        "samples": [], "run_samples": [], "run_sequences": [],
                        "totals": [], "oracles": []
                    }
                )
                row.update({name: fields[name] for name in ("layer", "unit")})
                row["oracles"].append(fields["oracle"])
            elif line.startswith("PULSE_SAMPLE "):
                fields = parse_fields(line)
                key = (system, program, fields["case"])
                operations = int(fields["operations"])
                sample = {
                    "wall": int(fields["wall_ns"]) / operations,
                    "tsc": int(fields["tsc_ticks"]) / operations,
                    "cycles": int(fields["thread_cycles"]) / operations,
                }
                rows.setdefault(
                    key, {
                        "samples": [], "run_samples": [], "run_sequences": [],
                        "totals": [], "oracles": []
                    }
                )["samples"].append(sample)
                log_samples.setdefault(key, []).append(sample)
            elif line.startswith("PULSE_TOTAL "):
                fields = parse_fields(line)
                key = (system, program, fields["case"])
                wall = int(fields["wall_ns"])
                cpu = int(fields["process_cpu_ns"])
                rows.setdefault(
                    key, {
                        "samples": [], "run_samples": [], "run_sequences": [],
                        "totals": [], "oracles": []
                    }
                )["totals"].append(
                    {"wall": wall, "process_cpu": cpu, "effective_cores": cpu / wall if wall else 0.0}
                )
        for key, samples in log_samples.items():
            rows[key]["run_samples"].append(samples)
            rows[key]["run_sequences"].append(int(item["sequence"]))
    return rows, manifest


def report_system_roles(systems: list[str]) -> tuple[str, str]:
    baseline = (
        "moon-baseline"
        if "moon-baseline" in systems
        else "delphi"
        if "delphi" in systems
        else "moon-default"
        if "moon-default" in systems
        else systems[0]
    )
    candidate = (
        "moon-candidate"
        if "moon-candidate" in systems
        else "moon"
        if "moon" in systems
        else systems[-1]
    )
    return baseline, candidate


def write_report(result: Path) -> None:
    rows, manifest = collect(result)
    systems = list(manifest["systems"])
    baseline, candidate = report_system_roles(systems)
    control = (
        "moon-default"
        if "delphi" in systems and "moon-default" in systems
        else None
    )
    cases = sorted({(program, case) for _, program, case in rows})
    details: dict[str, object] = {}
    markdown = [
        "# Moon Compiler Pulse result",
        "",
        f"Mode: `{manifest['mode']}`. Baseline: `{baseline}`. Candidate: `{candidate}`.",
        "",
        "Primary same-machine metric is actual scheduled thread cycles/op for single-thread cases;",
        "TSC ticks/op is used for multi-thread cases where one thread's cycle counter is incomplete.",
        "TSC is also used explicitly when scheduled thread cycles are unavailable for either system.",
        "",
        f"| Program | Case | Layer | Oracle | Metric | {baseline} stable/mean/max | {candidate} stable/mean/max | Candidate/baseline | Control/op | MM effect |",
        "| --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: |",
    ]
    oracle_failures: list[str] = []
    drift_failures: list[str] = []
    drift_notes: list[str] = []
    program_ratios: dict[str, list[float]] = {}
    layer_ratios: dict[str, list[float]] = {}
    mm_program_ratios: dict[str, list[float]] = {}
    ranked_ratios: list[tuple[float, str]] = []
    for program, case in cases:
        base = rows.get((baseline, program, case))
        cand = rows.get((candidate, program, case))
        if base is None or cand is None:
            continue
        control_row = rows.get((control, program, case)) if control else None
        metric_rows = [base, cand]
        if control_row is not None:
            metric_rows.append(control_row)
        primary_metric = select_primary_metric(program, metric_rows)
        try:
            base_primary, _ = process_balanced_stats(base, primary_metric)
            cand_primary, _ = process_balanced_stats(cand, primary_metric)
            base_tsc, _ = process_balanced_stats(base, "tsc")
            cand_tsc, _ = process_balanced_stats(cand, "tsc")
        except ValueError as error:
            raise ValueError(f"{program}/{case}: {error}") from error
        base_cycles = process_balanced_cycles(base)
        cand_cycles = process_balanced_cycles(cand)
        base_cores = effective_core_stats(base)
        cand_cores = effective_core_stats(cand)
        paired_ratio = None
        if use_paired_process_ratios(program, primary_metric):
            try:
                paired_ratio = paired_ratio_stats(base, cand, primary_metric)
            except ValueError as error:
                if program not in ("move", "threads"):
                    raise ValueError(f"{program}/{case}: {error}") from error
                drift_notes.append(
                    f"paired/{program}/{case} unavailable ({error}); "
                    "using process-balanced diagnostic ratio"
                )
        ratio = (
            paired_ratio.mode
            if paired_ratio is not None
            else cand_primary.mode / base_primary.mode
        )
        program_ratios.setdefault(program, []).append(ratio)
        for layer in str(base.get("layer", "")).split("+"):
            layer_ratios.setdefault(layer, []).append(ratio)
        ranked_ratios.append((ratio, f"{program}/{case}"))
        base_oracles = sorted(set(base["oracles"]))
        cand_oracles = sorted(set(cand["oracles"]))
        oracle_status = "MATCH" if base_oracles == cand_oracles else "DIFF"
        if oracle_status != "MATCH":
            oracle_failures.append(f"{program}/{case}")
        if paired_ratio is not None:
            if paired_ratio.minimum > 0:
                drift = paired_ratio.maximum / paired_ratio.minimum
                if drift > 1.25:
                    message = f"paired/{program}/{case} ratio drift {drift:.3f}x"
                    if program == "move":
                        drift_notes.append(message)
                    else:
                        drift_failures.append(message)
        else:
            for system, process_stats in (
                (baseline, base_primary),
                (candidate, cand_primary),
            ):
                if program not in ("threads", "move") and process_stats.minimum > 0:
                    drift = process_stats.maximum / process_stats.minimum
                    if drift > 1.25:
                        drift_failures.append(
                            f"{system}/{program}/{case} process drift {drift:.3f}x"
                        )
        control_primary = None
        mm_effect = None
        paired_mm_effect = None
        if control_row is not None:
            try:
                control_primary, _ = process_balanced_stats(
                    control_row, primary_metric
                )
            except ValueError as error:
                raise ValueError(f"{control}/{program}/{case}: {error}") from error
            if use_paired_process_ratios(program, primary_metric):
                try:
                    paired_mm_effect = paired_ratio_stats(
                        control_row, cand, primary_metric
                    )
                except ValueError as error:
                    if program not in ("move", "threads"):
                        raise ValueError(
                            f"{control}/{program}/{case}: {error}"
                        ) from error
                    drift_notes.append(
                        f"paired-mm/{program}/{case} unavailable ({error}); "
                        "using process-balanced diagnostic ratio"
                    )
                if paired_mm_effect is not None and paired_mm_effect.minimum > 0:
                    drift = paired_mm_effect.maximum / paired_mm_effect.minimum
                    if drift > 1.25:
                        drift_notes.append(
                            f"paired-mm/{program}/{case} ratio drift {drift:.3f}x"
                        )
            elif program not in ("threads", "move") and control_primary.minimum > 0:
                drift = control_primary.maximum / control_primary.minimum
                if drift > 1.25:
                    drift_failures.append(
                        f"{control}/{program}/{case} process drift {drift:.3f}x"
                    )
            mm_effect = (
                paired_mm_effect.mode
                if paired_mm_effect is not None
                else cand_primary.mode / control_primary.mode
            )
            mm_program_ratios.setdefault(program, []).append(mm_effect)
        markdown.append(
            f"| {program} | {case} | {base.get('layer', '')} | {oracle_status} | "
            f"{primary_metric} | {base_primary.mode:.3f}/{base_primary.mean:.3f}/{base_primary.maximum:.3f} | "
            f"{cand_primary.mode:.3f}/{cand_primary.mean:.3f}/{cand_primary.maximum:.3f} | {ratio:.3f} | "
            f"{control_primary.mode if control_primary else 0.0:.3f} | "
            f"{mm_effect if mm_effect is not None else 0.0:.3f} |"
        )
        details[f"{program}/{case}"] = {
            "layer": base.get("layer"),
            "unit": base.get("unit"),
            "primary_metric": primary_metric,
            "oracle_status": oracle_status,
            "oracles": {baseline: base_oracles, candidate: cand_oracles},
            baseline: {"tsc": asdict(base_tsc), "cycles": asdict(base_cycles) if base_cycles else None},
            candidate: {"tsc": asdict(cand_tsc), "cycles": asdict(cand_cycles) if cand_cycles else None},
            "candidate_over_baseline": ratio,
            "paired_candidate_over_baseline": (
                asdict(paired_ratio) if paired_ratio is not None else None
            ),
            "moon_mm_over_moon_default": mm_effect,
        }
        details[f"{program}/{case}"][baseline]["effective_cores"] = (
            asdict(base_cores) if base_cores else None
        )
        details[f"{program}/{case}"][candidate]["effective_cores"] = (
            asdict(cand_cores) if cand_cores else None
        )

    def geometric_mean(values: list[float]) -> float:
        return math.exp(statistics.mean(math.log(value) for value in values))

    def counts(values: list[float]) -> tuple[int, int, int]:
        faster = sum(value < 0.95 for value in values)
        parity = sum(0.95 <= value <= 1.05 for value in values)
        slower = sum(value > 1.05 for value in values)
        return faster, parity, slower

    summary = [
        "## Сводка по программам",
        "",
        "`< 0.95` — Moon быстрее, `0.95..1.05` — паритет, `> 1.05` — Moon медленнее.",
        "",
        "| Program | Cases | Geomean Moon/baseline | Faster | Parity | Slower | MM geomean |",
        "| --- | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]
    for program in sorted(program_ratios):
        values = program_ratios[program]
        faster, parity, slower = counts(values)
        mm_values = mm_program_ratios.get(program, [])
        summary.append(
            f"| {program} | {len(values)} | {geometric_mean(values):.3f} | "
            f"{faster} | {parity} | {slower} | "
            f"{geometric_mean(mm_values) if mm_values else 0.0:.3f} |"
        )
    summary.extend([
        "",
        "## Сводка по физическим слоям",
        "",
        "| Layer | Cases | Geomean Moon/baseline | Faster | Parity | Slower |",
        "| --- | ---: | ---: | ---: | ---: | ---: |",
    ])
    for layer in sorted(layer_ratios):
        values = layer_ratios[layer]
        faster, parity, slower = counts(values)
        summary.append(
            f"| {layer} | {len(values)} | {geometric_mean(values):.3f} | "
            f"{faster} | {parity} | {slower} |"
        )
    summary.extend(["", "## Крайние результаты", "", "### 15 самых быстрых", ""])
    summary.extend(
        f"- `{name}`: `{ratio:.3f}x`" for ratio, name in sorted(ranked_ratios)[:15]
    )
    summary.extend(["", "### 15 самых медленных", ""])
    summary.extend(
        f"- `{name}`: `{ratio:.3f}x`"
        for ratio, name in sorted(ranked_ratios, reverse=True)[:15]
    )
    if drift_notes:
        summary.extend([
        "## Диагностический process drift paired rows",
            "",
            "Эти cases остаются в таблице, но центральное отношение рассчитано "
            "по соседним зеркальным процессам; drift не подменяет semantic failure.",
            "",
        ])
        summary.extend(f"- `{note}`" for note in drift_notes)
    summary.extend(["", "## Все cases", ""])
    markdown = markdown[:8] + summary + markdown[8:]
    (result / "REPORT.md").write_text("\n".join(markdown) + "\n", encoding="utf-8")
    (result / "summary.json").write_text(
        json.dumps(details, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    if oracle_failures:
        raise ValueError(f"semantic oracle differs: {', '.join(oracle_failures)}")
    if drift_failures:
        raise ValueError("unstable process pairs: " + "; ".join(drift_failures))


def split_csv(value: str) -> list[str]:
    return [item.strip() for item in value.split(",") if item.strip()]


def main() -> None:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    run_parser = sub.add_parser("run")
    run_parser.add_argument("--mode", choices=("quick", "medium", "long"), default="quick")
    run_parser.add_argument("--programs", default=",".join(PROGRAMS))
    run_parser.add_argument(
        "--systems",
        default="delphi,moon,moon-default" if IS_WINDOWS else "moon,moon-default",
    )
    run_parser.add_argument("--moon-baseline-toolchain", type=Path)
    run_parser.add_argument("--moon-candidate-toolchain", type=Path)
    run_parser.add_argument("--moon-baseline-option", action="append", default=[])
    run_parser.add_argument("--moon-candidate-option", action="append", default=[])
    run_parser.add_argument("--tag")
    report_parser = sub.add_parser("report")
    report_parser.add_argument("result", type=Path)
    args = parser.parse_args()
    if args.command == "run":
        programs = split_csv(args.programs)
        systems = split_csv(args.systems)
        unknown_programs = sorted(set(programs) - PROGRAMS.keys())
        unknown_systems = sorted(set(systems) - SYSTEM_LABELS.keys())
        if not IS_WINDOWS and "delphi" in systems:
            unknown_systems.append("delphi (Windows-only)")
        if unknown_programs or unknown_systems:
            raise ValueError(f"unknown programs={unknown_programs} systems={unknown_systems}")
        external_toolchains = {
            system: path.resolve()
            for system, path in (
                ("moon-baseline", args.moon_baseline_toolchain),
                ("moon-candidate", args.moon_candidate_toolchain),
            )
            if path is not None
        }
        external_options = {
            "moon-baseline": args.moon_baseline_option,
            "moon-candidate": args.moon_candidate_option,
        }
        external_options = {
            system: options for system, options in external_options.items()
            if options
        }
        selected_external = set(systems) & set(EXTERNAL_MOON_SYSTEMS)
        if selected_external and selected_external != set(EXTERNAL_MOON_SYSTEMS):
            raise ValueError(
                "moon-baseline and moon-candidate must be selected together"
            )
        missing_toolchains = sorted(selected_external - external_toolchains.keys())
        unused_toolchains = sorted(external_toolchains.keys() - selected_external)
        if missing_toolchains or unused_toolchains:
            raise ValueError(
                f"missing external toolchains={missing_toolchains} "
                f"unused external toolchains={unused_toolchains}"
            )
        unused_options = sorted(external_options.keys() - selected_external)
        if unused_options:
            raise ValueError(f"unused external options={unused_options}")
        tag = args.tag or time.strftime("%Y%m%d-%H%M%S") + f"-{args.mode}"
        run_suite(
            args.mode, programs, systems, tag,
            external_toolchains, external_options)
    else:
        write_report(args.result.resolve())


if __name__ == "__main__":
    main()
