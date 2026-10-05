#!/usr/bin/env python3
"""Compare equal useful work in a fixed number of fresh paired processes."""

from __future__ import annotations

import argparse
import fnmatch
import gzip
import hashlib
import json
import math
import os
import platform
import shutil
import statistics
import sys
import threading
import time
import traceback
from concurrent.futures import ThreadPoolExecutor
from contextlib import nullcontext
from dataclasses import asdict, dataclass, replace
from pathlib import Path
from typing import Any

TOOLS = Path(__file__).resolve().parent
PERF = TOOLS.parent
sys.path.insert(0, str(TOOLS))

import check_program_placement  # noqa: E402
import linked_image  # noqa: E402
import pulse  # noqa: E402
import pulse_assessment  # noqa: E402
import qualify_measurement_method as method  # noqa: E402


SYSTEMS = ("moon-baseline", "moon-candidate")
VERDICT_FRACTION = 0.01
MEMORY_VERDICT_FRACTION = 0.05
PROCESS_BATCH_CASES = 32
STACK_PAGE = 4096
# Pair i calls the case at rsp = i * 336 mod 4096 on both sides.  336 = 16 * 21
# with 21 odd: 12 pairs spread over the page, 256 would visit every phase once.
STACK_PHASE_STEP = 336
# Measured by pulse_l2_calibration.py: L2 misses per 1000 cycles of each case,
# one section per machine, keyed by its host name.
L2_CALIBRATION = PERF / "pulse_l2_misses.json"
# A case runs alone when a neighbour on the shared L3 that doubles the latency
# of its L2 misses (an L3 hit, about 50 cycles) moves its cost by the verdict
# threshold: 1000 * 1% / 50 = 0.2 misses per 1000 cycles.
L3_HIT_CYCLES = 50
L2_EXCLUSIVE_PER_KCYCLE = 1000 * VERDICT_FRACTION / L3_HIT_CYCLES


@dataclass(frozen=True)
class Policy:
    initial_ms: int
    samples: int
    warmup_ms: int
    exclusive: bool


WINDOWS_OBSERVABLE_WORK_MS = 60 if os.name == "nt" else 0  # 50 ms counter window plus calibration margin.
POLICIES = {
    "single-cpu": Policy(max(6, WINDOWS_OBSERVABLE_WORK_MS), 3, 2, False),
    "memory-local": Policy(max(6, WINDOWS_OBSERVABLE_WORK_MS), 3, 2, False),
    "memory-global": Policy(max(15, WINDOWS_OBSERVABLE_WORK_MS), 3, 5, True),
    "memory-manager": Policy(max(9, WINDOWS_OBSERVABLE_WORK_MS), 3, 3, False),
    "fragmentation": Policy(max(15, WINDOWS_OBSERVABLE_WORK_MS), 3, 5, True),
    "multithread": Policy(20, 2, 10, True),
}

# Programs and cases that pin one worker thread to each CPU of the multithread
# set and refuse to start on fewer: pulse_threads (MaxThreadCount workers) and
# the padded-counter sentinel of pulse_repairs (four workers and its main
# thread).  A machine with fewer physical CPUs cannot host them: they are named
# in the result, not a failed pass.
PINNED_WORKERS = {"threads": 8, "repairs/padded-counters-4": 5}


@dataclass(frozen=True)
class Case:
    program: str
    name: str
    layer: str
    unit: str
    category: str
    l2_misses_per_kcycle: float | None = None

    @property
    def exclusive(self) -> bool:
        """The case shares L3 enough for a concurrent neighbour to move its cost,
        or this machine never measured it: unknown traffic is not light traffic."""
        return (
            self.l2_misses_per_kcycle is None
            or self.l2_misses_per_kcycle > L2_EXCLUSIVE_PER_KCYCLE
        )


def stack_phase_plan(text: str) -> str:
    if text in ("grid", "fixed"):
        return text
    value = int(text)
    if not 0 <= value < STACK_PAGE or value % 16:
        raise argparse.ArgumentTypeError(
            "stack phase is grid, fixed or a multiple of 16 below 4096"
        )
    return str(value)


def stack_phase(plan: str, pair: int) -> int | None:
    """rsp mod 4096 at the call into the case for fresh pair `pair`; None: fixed, no shift."""
    if plan == "fixed":
        return None
    if plan == "grid":
        return pair * STACK_PHASE_STEP % STACK_PAGE
    return int(plan)


def l2_calibration(
    cases: list[Case], table: Path = L2_CALIBRATION
) -> tuple[list[Case], dict[str, object]]:
    """Attach the L2 misses measured on this machine; a case without them runs alone.

    A calibration belongs to the host that measured it: another machine, even
    with the same OS, finds no section and every case stays unmeasured.
    """
    machine = platform.node()
    tables = json.loads(table.read_text(encoding="utf-8")) if table.is_file() else {}
    section = tables.get(machine) or {}
    rates = section.get("cases", {})
    measured = [
        replace(case, l2_misses_per_kcycle=rates.get(f"{case.program}/{case.name}"))
        for case in cases
    ]
    return measured, {
        "table": str(table),
        "machine": machine,
        "event": section.get("event"),
        "created_unix": section.get("created_unix"),
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline-toolchain", type=Path, required=True)
    parser.add_argument("--candidate-toolchain", type=Path, required=True)
    parser.add_argument("--baseline-mm-source", type=Path)
    parser.add_argument("--candidate-mm-source", type=Path)
    parser.add_argument("--programs", default=",".join(pulse.stand_programs(True)))
    parser.add_argument(
        "--cases",
        default="",
        help="comma-separated program/case glob patterns; empty selects every case",
    )
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--build-jobs", type=int, default=4)
    parser.add_argument("--pairs", type=int, default=12, help="fixed fresh process pairs per case (minimum 6)")
    parser.add_argument("--single-cpus", default="",
                        help="comma-separated physical CPUs for single-CPU pairs; multithread CPUs stay unchanged")
    parser.add_argument(
        "--stack-phase",
        type=stack_phase_plan,
        default="grid",
        help="grid: pair i calls the case at rsp = i*336 mod 4096; fixed: no shift; N: every pair at N",
    )
    parser.add_argument(
        "--qualification-preflight",
        action="store_true",
        help="run the slow five-process A/A and negative control before production Pulse",
    )
    parser.add_argument(
        "--core-rest-ms",
        type=float,
        default=method.MEASUREMENT_CORE_REST_SECONDS * 1000,
        help="idle a core keeps after the runner's own process before the next one "
        "(no foreign work in the 2 s before any process either way)",
    )
    parser.add_argument("--keep-machine-settings", action="store_true")
    parser.add_argument("--skip-preflight", action="store_true")
    return parser.parse_args()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def discover(executable: Path) -> dict[str, dict[str, str]]:
    completed = method.command([str(executable), "list", "all"])
    result: dict[str, dict[str, str]] = {}
    for line in completed.stdout.splitlines():
        if not line.startswith("PULSE_CASEDEF "):
            continue
        row = method.fields(line)
        name = row["case"]
        if name in result:
            raise RuntimeError(f"{executable}: duplicate case {name}")
        result[name] = row
    if not result:
        raise RuntimeError(f"{executable}: empty case matrix")
    return result


def classify(program: str, name: str, layer: str) -> str:
    layers = set(layer.split("+"))
    lower = name.lower()
    if program == "threads" or "threads" in layers or (
        program == "repairs" and name == "padded-counters-4"
    ):
        return "multithread"
    if program == "mm":
        return "fragmentation" if "fragment" in lower else "memory-manager"
    move_size = None
    if program == "move" and "-n" in lower:
        suffix = lower.rsplit("-n", 1)[-1]
        if suffix.isdigit():
            move_size = int(suffix)
    if (
        (program == "move" and lower.startswith("stream-"))
        or (program == "move" and lower.startswith("hot-") and (move_size or 0) > 131072)
        or (
            program == "move"
            and lower.startswith(("overlap-forward-", "overlap-backward-"))
            and (move_size or 0) > 262144
        )
        or "scan-dram" in lower
        or any(token in lower for token in ("scan-llc", "scan-strided", "scan-random", "pointer-chase"))
        or "asm-memory" in lower
        or "64mb" in lower
        or "64-mb" in lower
    ):
        return "memory-global"
    if program == "move" or "memory" in layers:
        return "memory-local"
    return "single-cpu"


def discover_matrix(
    built: dict[str, dict[str, Path]], programs: list[str]
) -> list[Case]:
    cases: list[Case] = []
    for program in programs:
        baseline = discover(built["moon-baseline"][program])
        candidate = discover(built["moon-candidate"][program])
        if list(baseline) != list(candidate):
            raise RuntimeError(
                f"case matrix differs for {program}: "
                f"Remote={list(baseline)} Current={list(candidate)}"
            )
        for name, row in baseline.items():
            other = candidate[name]
            for field in ("layer", "unit"):
                if row.get(field) != other.get(field):
                    raise RuntimeError(
                        f"{program}/{name}: {field} differs between systems"
                    )
            layer = row.get("layer", "")
            cases.append(
                Case(program, name, layer, row.get("unit", ""), classify(program, name, layer))
            )
    return cases


def image_copies(
    output: Path,
    built: dict[str, dict[str, Path]],
    programs: list[str],
    repeat_count: int = method.PROCESS_REPEATS,
) -> dict[tuple[str, str, int], Path]:
    copies: dict[tuple[str, str, int], Path] = {}
    root = output / "images"
    for system in SYSTEMS:
        for program in programs:
            source = built[system][program]
            expected = sha256(source)
            for repeat in range(repeat_count):
                target = root / system / program / str(repeat) / source.name
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source, target)
                shutil.copymode(source, target)
                if sha256(target) != expected:
                    raise RuntimeError(f"byte copy differs: {target}")
                copies[system, program, repeat] = target
    return copies


def select_cases(cases: list[Case], selectors: str) -> list[Case]:
    patterns = [item.strip().lower() for item in selectors.split(",") if item.strip()]
    if not patterns:
        return cases
    selected = [
        case
        for case in cases
        if any(
            fnmatch.fnmatchcase(f"{case.program}/{case.name}".lower(), pattern)
            for pattern in patterns
        )
    ]
    if not selected:
        raise ValueError(f"no Pulse cases match: {selectors}")
    return selected


def clean_records(
    records: list[dict[str, object]],
    duration: int,
    affinity: tuple[int, ...],
    output: Path,
    tag: str,
    variants: tuple[str, str] = SYSTEMS,
    retries: int = 3,
) -> list[dict[str, object]]:
    grouped: dict[tuple[str, str, int], list[dict[str, object]]] = {}
    for record in records:
        key = str(record["program"]), str(record["case"]), int(record["repeat"])
        grouped.setdefault(key, []).append(record)
    for (program, case, repeat), pair in grouped.items():
        if len(pair) != 2 or {str(record["variant"]) for record in pair} != set(variants):
            raise RuntimeError(f"invalid process pair: {program}/{case} repeat={repeat}")

    current = dict(grouped)
    rejected: dict[tuple[str, str, int], list[dict[str, object]]] = {
        key: [] for key in grouped
    }
    for attempt in range(retries):
        dirty: list[tuple[str, str, int]] = []
        for key, pair in current.items():
            category = str(pair[0]["category"])
            metrics = [
                method.record_metrics(record, category == "multithread")
                for record in pair
            ]
            if all(bool(value["valid"]) for value in metrics):
                continue
            dirty.append(key)
            rejected[key].extend(
                {
                    "attempt": attempt,
                    "variant": record["variant"],
                    "log": record["log"],
                    "runner": record.get("runner"),
                    "derived": value,
                }
                for record, value in zip(pair, metrics)
            )
        if not dirty:
            break

        retry_items = []
        for program, case, repeat in dirty:
            pair = current[program, case, repeat]
            category = str(pair[0]["category"])
            by_variant = {str(record["variant"]): record for record in pair}
            order = list(variants) if repeat % 2 == 0 else list(reversed(variants))
            for position, variant in enumerate(order):
                retry_items.append(
                    (
                        Path(str(by_variant[variant]["executable"])),
                        program,
                        case,
                        variant,
                        repeat,
                        category,
                        repeat * 2 + position,
                    )
                )

        retried = method.run_batch(
            retry_items,
            duration,
            affinity,
            output,
            f"{tag}-contamination-retry-{attempt + 1}",
            enable_xperf=False,
        )
        retry_groups: dict[tuple[str, str, int], list[dict[str, object]]] = {}
        for record in retried:
            key = str(record["program"]), str(record["case"]), int(record["repeat"])
            retry_groups.setdefault(key, []).append(record)
        for key in dirty:
            pair = retry_groups.get(key, [])
            if len(pair) != 2 or {str(record["variant"]) for record in pair} != set(variants):
                raise RuntimeError(f"invalid retry pair: {key}")
            current[key] = pair

    cleaned: list[dict[str, object]] = []
    for key, pair in current.items():
        multithread = str(pair[0]["category"]) == "multithread"
        metrics = [method.record_metrics(record, multithread) for record in pair]
        for record, value in zip(pair, metrics):
            record["accepted"] = bool(value["valid"])
            record["derived"] = value
            record["rejected_pair_attempts"] = rejected[key]
            cleaned.append(record)
    return cleaned


def middle_half_spread(values: list[float]) -> float:
    ordered = sorted(values)
    if not ordered:
        return math.inf
    low = ordered[len(ordered) // 4]
    high = ordered[3 * len(ordered) // 4]
    center = statistics.median(ordered)
    return (high - low) / center * 100.0 if center else math.inf


def process_sample_spread(metrics: dict[str, object], metric: str) -> float:
    samples = [
        sample
        for sample in metrics["samples"]
        if bool(sample["valid"])
    ]
    return middle_half_spread([float(sample[metric]) for sample in samples])


def paired_ratios(
    rows: list[tuple[dict[str, object], dict[str, object]]], metric: str
) -> list[float]:
    ratios: list[float] = []
    repeats = sorted({int(record["repeat"]) for record, _ in rows})
    for repeat in repeats:
        current = [
            metrics
            for record, metrics in rows
            if int(record["repeat"]) == repeat
            and record["variant"] == "moon-candidate"
            and metrics["valid"]
        ]
        baseline = [
            metrics
            for record, metrics in rows
            if int(record["repeat"]) == repeat
            and record["variant"] == "moon-baseline"
            and metrics["valid"]
        ]
        if len(current) == len(baseline) == 1:
            denominator = float(baseline[0][metric])
            if denominator > 0:
                ratios.append(float(current[0][metric]) / denominator)
    return ratios


def ratio_summary(
    rows: list[tuple[dict[str, object], dict[str, object]]],
    metric: str,
    threshold: float,
) -> dict[str, object]:
    ratios = paired_ratios(rows, metric)
    lower = 1.0 - threshold
    upper = 1.0 + threshold
    center = statistics.median(ratios) if ratios else None
    ordered = sorted(ratios)
    if len(ordered) >= 5:
        low = ordered[max(0, math.floor((len(ordered) - 1) * 0.20))]
        high = ordered[min(len(ordered) - 1, math.ceil((len(ordered) - 1) * 0.80))]
    elif ordered:
        low, high = ordered[0], ordered[-1]
    else:
        low = high = math.nan
    precision = (
        (high - low) / (2.0 * center)
        if center is not None and center != 0.0
        else math.inf
    )
    if center is None:
        estimated = "UNAVAILABLE"
    elif center < lower:
        estimated = "BETTER"
    elif center > upper:
        estimated = "WORSE"
    else:
        estimated = "SAME"
    interval = median_interval(ratios)
    if interval is None:
        decision = "UNAVAILABLE"
    elif interval[1] < lower:
        decision = "BETTER"
    elif interval[0] > upper:
        decision = "WORSE"
    elif interval[0] >= lower and interval[1] <= upper:
        decision = "SAME"
    else:
        decision = "UNSTABLE"
    separated = separated_direction(rows, metric) if interval is not None else None
    if separated and decision in ("SAME", "UNSTABLE"):
        decision = separated
    return {
        "metric": metric,
        "ratios": ratios,
        "median": center,
        "minimum": min(ratios) if ratios else None,
        "maximum": max(ratios) if ratios else None,
        "median_interval_95": interval,
        "spread_percent": method.spread(ratios) if ratios else math.inf,
        "central_error_percent": precision * 100.0,
        "threshold_fraction": threshold,
        "estimated_decision": estimated,
        "decision": decision,
        "separated": bool(separated),
    }


def separated_direction(
    rows: list[tuple[dict[str, object], dict[str, object]]], metric: str
) -> str | None:
    """BETTER/WORSE when every Current process costs less/more than every Remote one.

    A median ratio inside the threshold then still is a direction, not SAME, and
    an interval across it is no UNSTABLE: with equal distributions such a split
    has the chance 2 / C(2n, n) - 7.4e-7 at the 12 processes a side of the plan,
    0.2% at the 6 a median interval needs at least.  Memory keeps its 5%
    threshold: equal allocations split by a page are no change worth a verdict.
    """
    if metric.startswith("memory_"):
        return None
    current, remote = (
        [float(metrics[metric]) for record, metrics in rows if record["variant"] == system and metrics["valid"]]
        for system in ("moon-candidate", "moon-baseline")
    )
    if max(current) < min(remote):
        return "BETTER"
    if min(current) > max(remote):
        return "WORSE"
    return None


def median_interval(values: list[float]) -> list[float] | None:
    """Exact, distribution-free >=95% interval for the population median.

    Invert the two-sided sign test. No observations are removed: the full
    range remains separately reported. Fewer than six pairs cannot establish
    even the [min, max] interval at 95% coverage.
    """
    ordered = sorted(values)
    n = len(ordered)
    tail = 0
    index = None
    for k in range(n // 2):
        tail += math.comb(n, k)
        if 2 * tail / 2**n > 0.05:
            break
        index = k
    return [ordered[index], ordered[-index - 1]] if index is not None else None


def entry_phase(record: dict[str, object]) -> int | None:
    """rsp mod 4096 the harness saw at the case's first instruction."""
    rsp = record.get("case_definition", {}).get("stack_rsp")
    return int(str(rsp), 16) % STACK_PAGE if rsp else None


def process_range(
    rows: list[tuple[dict[str, object], dict[str, object]]], metric: str
) -> dict[str, dict[str, object]]:
    """Each side's fastest and slowest process: the tail a median hides."""
    result: dict[str, dict[str, object]] = {}
    for system in SYSTEMS:
        values = [
            (float(metrics[metric]), entry_phase(record))
            for record, metrics in rows
            if record["variant"] == system and metrics["valid"]
        ]
        if values:
            low = min(values, key=lambda item: item[0])
            high = max(values, key=lambda item: item[0])
            result[system] = {
                "minimum": low[0],
                "minimum_phase": low[1],
                "maximum": high[0],
                "maximum_phase": high[1],
            }
    return result


def median_by_system(
    rows: list[tuple[dict[str, object], dict[str, object]]], metric: str
) -> dict[str, float]:
    result: dict[str, float] = {}
    for system in SYSTEMS:
        values = [
            float(metrics[metric])
            for record, metrics in rows
            if record["variant"] == system and metrics["valid"]
        ]
        result[system] = statistics.median(values) if values else 0.0
    return result


def analyze_case(records: list[dict[str, object]], case: Case) -> dict[str, object]:
    multithread = case.category == "multithread"
    rows = [
        (
            record,
            record.get("derived")
            or method.record_metrics(
                record, multithread, work_only=not multithread
            ),
        )
        for record in records
    ]
    valid_counts = {
        system: sum(
            bool(metrics["valid"])
            for record, metrics in rows
            if record["variant"] == system
        )
        for system in SYSTEMS
    }
    metric_names = [
        "ticks_per_op",
        "work_cycles_per_op",
        "process_cpu_per_op",
        "operations_per_second",
        "latency_p99_ns",
        "effective_cores",
    ]
    if case.category in ("memory-manager", "fragmentation", "multithread"):
        metric_names.extend(
            [
                "memory_peak_resident",
                "memory_after_private",
                "memory_cooldown_private",
            ]
        )
    metric_thresholds = {
        name: MEMORY_VERDICT_FRACTION if name.startswith("memory_") else VERDICT_FRACTION
        for name in metric_names
    }
    summaries = {
        name: ratio_summary(
            rows,
            name,
            metric_thresholds[name],
        )
        for name in metric_names
    }
    if case.category in ("memory-manager", "fragmentation"):
        primary_names = (
            "work_cycles_per_op",
            "memory_peak_resident",
            "memory_after_private",
            "memory_cooldown_private",
        )
    elif case.category == "multithread":
        primary_names = ("ticks_per_op", "work_cycles_per_op")
        if any(token in case.name.lower() for token in ("alloc", "free")):
            primary_names += (
                "memory_peak_resident",
                "memory_after_private",
                "memory_cooldown_private",
            )
    else:
        primary_names = ("work_cycles_per_op",)
    sample_metric = "ticks_per_op" if multithread else "work_cycles_per_op"
    sample_spreads = [
        process_sample_spread(metrics, sample_metric)
        for _, metrics in rows
        if metrics["valid"]
    ]
    stable = (
        all(
            summaries[name]["decision"] not in ("UNAVAILABLE", "UNSTABLE")
            for name in primary_names
        )
    )
    digests = {
        system: sorted(
            {
                str(record["case_definition"].get("oracle", ""))
                for record, _ in rows
                if record["variant"] == system
            }
        )
        for system in SYSTEMS
    }
    semantic_match = (
        len(digests["moon-baseline"]) == 1
        and digests["moon-baseline"] == digests["moon-candidate"]
    )
    # Every measured pair must perform equal work and produce equal results,
    # not merely agree on the one-iteration discovery oracle.
    for repeat in {record["repeat"] for record, _ in rows}:
        pair = [record for record, _ in rows if record["repeat"] == repeat]
        if len(pair) == 2 and all(record.get("fixed_work") for record in pair):
            signatures = [tuple((sample["operations"], sample["digest"]) for sample in record["samples"]) for record in pair]
            semantic_match = semantic_match and signatures[0] == signatures[1]
    attempted_pairs = len({int(record["repeat"]) for record, _ in rows})
    valid_pairs = len(summaries[primary_names[0]]["ratios"])
    return {
        "stable": stable,
        "semantic_match": semantic_match,
        "digests": digests,
        "valid_processes": valid_counts,
        "attempted_pairs": attempted_pairs,
        "valid_pairs": valid_pairs,
        "sample_spread_percent": max(sample_spreads) if sample_spreads else math.inf,
        "primary_metrics": primary_names,
        "metrics": summaries,
        "centers": {
            name: median_by_system(rows, name) for name in metric_names
        },
        "process_range": process_range(rows, sample_metric),
        "records": records,
    }


def build_negative_control(
    toolchain: Path,
    mm_source: Path,
    output: Path,
) -> tuple[Path, Path]:
    control = pulse.build_moon(
        "repairs",
        False,
        system="pulse-fast-negative-control",
        toolchain=toolchain,
        mm_source=mm_source,
        extra_options=["-dPULSE_FILLER_3", "-gw3", "-Xs-"],
    )
    directory = output / "negative-control"
    directory.mkdir(parents=True, exist_ok=True)
    suffix = ".exe" if os.name == "nt" else ""
    baseline = directory / f"pulse_repairs_work64{suffix}"
    more_work = directory / f"pulse_repairs_work66{suffix}"
    shutil.copyfile(control, baseline)
    shutil.copymode(control, baseline)
    method.patch_negative_control(baseline, more_work)
    return baseline, more_work


def run_preflight(
    built: dict[str, dict[str, Path]],
    candidate_toolchain: Path,
    candidate_mm: Path,
    affinity: tuple[int, ...],
    output: Path,
) -> dict[str, object]:
    source = built["moon-candidate"]["codegen"]
    aa_dir = output / "preflight-aa"
    aa_dir.mkdir(parents=True, exist_ok=True)
    copies = []
    for side in ("A", "B"):
        target = aa_dir / side / source.name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
        shutil.copymode(source, target)
        copies.append((side, target))
    aa_items = []
    for repeat in range(method.PROCESS_REPEATS):
        variants = copies if repeat % 2 == 0 else list(reversed(copies))
        for position, (variant, executable) in enumerate(variants):
            aa_items.append(
                (
                    executable,
                    "codegen",
                    "dep-add",
                    variant,
                    repeat,
                    "single-cpu",
                    repeat * 2 + position,
                )
            )
    aa_records = method.run_batch(
        aa_items,
        200,
        affinity,
        output,
        "preflight-aa",
        enable_xperf=False,
    )
    aa_records = clean_records(
        aa_records,
        200,
        affinity,
        output,
        "preflight-aa",
        variants=("A", "B"),
        retries=10,
    )
    aa = method.analyze_aa(aa_records, "single-cpu")

    baseline, more_work = build_negative_control(
        candidate_toolchain, candidate_mm, output
    )
    control: dict[str, object] | None = None
    for duration in (200, 1000):
        items = []
        for repeat in range(method.PROCESS_REPEATS):
            variants = [("work64", baseline), ("work66", more_work)]
            if repeat % 2:
                variants.reverse()
            for position, (variant, executable) in enumerate(variants):
                items.append(
                    (
                        executable,
                        "repairs-control",
                        "stddev-4",
                        variant,
                        repeat,
                        "control",
                        repeat * 2 + position,
                    )
                )
        records = method.run_batch(
            items,
            duration,
            affinity,
            output,
            f"preflight-control-{duration}",
            enable_xperf=False,
        )
        records = clean_records(
            records,
            duration,
            affinity,
            output,
            f"preflight-control-{duration}",
            variants=("work64", "work66"),
            retries=10,
        )
        control = method.analyze_control(records)
        if control["passed"]:
            control["chosen_duration_ms"] = duration
            break
    assert control is not None
    return {"aa": aa, "negative_control": control, "passed": bool(aa["passed"] and control["passed"])}


def benchmark_cpu_sets(single_override: str = "") -> tuple[tuple[int, ...], tuple[int, ...]]:
    physical = (
        method.windows_physical_cpus(None)
        if os.name == "nt"
        else method.linux_physical_cpus(None)
    )
    if len(physical) < 4:
        raise RuntimeError(f"Pulse needs at least four physical cores, found {physical}")
    if single_override:
        parts = [part.strip() for part in single_override.split(",")]
        if any(not part.isascii() or not part.isdecimal() for part in parts):
            raise ValueError(f"--single-cpus requires comma-separated physical CPU numbers: {single_override!r}")
        selected = tuple(int(part) for part in parts)
        if len(selected) < 2 or len(selected) % 2 or len(selected) > len(physical) - 2:
            raise ValueError("--single-cpus needs complete pairs and two other physical cores for the runner")
        if len(set(selected)) != len(selected) or any(cpu not in physical for cpu in selected):
            raise ValueError(f"--single-cpus must name distinct available physical CPUs: {physical}")
    if os.name == "nt":
        single = physical[-min(6, len(physical) - 2) :]
        multithread = physical[: min(8, len(physical))]
    else:
        single = physical[: min(14, len(physical) - 2)]
        multithread = physical[: min(9, len(physical))]
    if len(single) < 2:
        raise RuntimeError(f"Pulse needs two benchmark cores, found {physical}")
    if len(single) % 2:
        single = single[:-1]
    if single_override:
        single = selected
    return tuple(single), tuple(multithread)


def hostable(
    names: list[str], multithread_cpus: tuple[int, ...]
) -> tuple[list[str], dict[str, int]]:
    """(the programs or program/case names this machine can run, name -> the
    workers it pins but the multithread set has not got)."""
    unhostable = {
        name: PINNED_WORKERS[name]
        for name in names
        if len(multithread_cpus) < PINNED_WORKERS.get(name, 0)
    }
    for name, workers in unhostable.items():
        print(
            f"PULSE_LEFT_OUT {'case' if '/' in name else 'program'}={name} workers={workers} "
            f"multithread_cpus={len(multithread_cpus)}",
            flush=True,
        )
    return [name for name in names if name not in unhostable], unhostable


def scaled_iterations(
    cache: dict[tuple[str, str], tuple[int, int]],
    case: Case,
    duration_ms: int,
) -> int | None:
    cached = cache.get((case.program, case.name))
    if cached is None:
        return None
    iterations, calibrated_ms = cached
    return max(1, round(iterations * duration_ms / calibrated_ms))


class PairPool:
    """The pairs of measurement cores, a clean one first.  A pair whose core ran
    foreign work in the watch's horizon, or whose SMT sibling was busy in the
    last second, waits while another pair is clean or still at work: a build on
    some cores costs the pass those cores instead of rejected processes.  When
    every pair is free and none has been clean for the horizon, the first free
    pair is handed out, and its processes are judged as always."""

    def __init__(self, cpu_pairs: list[tuple[int, int]], quiet=None) -> None:
        self.pairs = list(cpu_pairs)
        self.free = list(cpu_pairs)
        self.condition = threading.Condition()
        if quiet is None:
            siblings = {cpu: method.processor_sibling(cpu) for pair in cpu_pairs for cpu in pair}
            quiet = lambda cpu: method.CORE_WATCH.quiet(cpu, siblings[cpu])  # noqa: E731
        self.quiet = quiet
        self.dirty_since: float | None = None

    def take(self) -> tuple[int, int]:
        with self.condition:
            while True:
                for pair in self.free:
                    if all(self.quiet(cpu) for cpu in pair):
                        self.free.remove(pair)
                        self.dirty_since = None
                        return pair
                if len(self.free) == len(self.pairs):
                    now = time.monotonic()
                    if self.dirty_since is None:
                        self.dirty_since = now
                    elif now - self.dirty_since >= method.MEASUREMENT_CORE_IDLE_SECONDS:
                        self.dirty_since = None
                        return self.free.pop(0)
                self.condition.wait(0.05)

    def give(self, pair: tuple[int, int]) -> None:
        with self.condition:
            self.free.append(pair)
            self.condition.notify_all()


def on_cpu_pairs(tasks: list, pool: PairPool, work) -> list:
    """work(index, task, cpu_pair) for every task, each on a CPU pair of its own:
    a pair takes the next task as soon as it is free and clean, so a slow series
    holds back only its own pair.  Results in the order of the tasks."""

    def run(index: int, task: object) -> object:
        pair = pool.take()
        try:
            return work(index, task, pair)
        finally:
            pool.give(pair)

    with ThreadPoolExecutor(max_workers=len(pool.pairs)) as executor:
        futures = [executor.submit(run, index, task) for index, task in enumerate(tasks)]
        return [future.result() for future in futures]


def run_pair(
    case: Case,
    repeat: int,
    duration_ms: int,
    images: dict[tuple[str, str, int], Path],
    cpu_pair: tuple[int, int],
    multithread_cpus: tuple[int, ...],
    iteration_cache: dict[tuple[str, str], tuple[int, int]],
    output: Path,
    tag: str,
    concurrent: bool,
    orientation: int,
    stack_plan: str = "grid",
) -> list[dict[str, object]]:
    policy = POLICIES[case.category]
    phase = stack_phase(stack_plan, repeat)
    variants = list(SYSTEMS)
    if orientation % 2:
        variants.reverse()
    rejected: list[dict[str, object]] = []
    calibration: list[dict[str, object]] = []
    case_id = hashlib.sha256(f"{case.program}/{case.name}".encode()).hexdigest()[:24]
    for attempt in range(3):
        attempt_dir = output / "logs" / tag / f"{case_id}-r{repeat}-a{attempt}"
        attempt_dir.mkdir(parents=True, exist_ok=True)
        fixed = scaled_iterations(iteration_cache, case, duration_ms)

        def launch(variant: str, cpu: int, gate: tuple[Path, Path, threading.Barrier] | None) -> dict[str, object]:
            if case.category == "multithread":
                reserved = multithread_cpus
            else:
                reserved = (cpu,)
            start_gate = ready_file = barrier = None
            if gate is not None:
                start_gate, ready_file, barrier = gate
            return method.run_one(
                images[variant, case.program, repeat],
                case.program,
                case.name,
                variant,
                repeat,
                duration_ms,
                case.category,
                reserved,
                attempt_dir,
                fixed_iterations=fixed,
                samples_per_process=policy.samples,
                warmup_ms=policy.warmup_ms,
                timeout_seconds=30.0,
                start_gate=start_gate,
                ready_file=ready_file,
                gate_barrier=barrier,
                stack_phase=phase,
            )

        if concurrent:
            gate = attempt_dir / "start.gate"
            gate.unlink(missing_ok=True)
            barrier = threading.Barrier(2)
            assignments = [
                (variants[0], cpu_pair[0], (gate, attempt_dir / "left.ready", barrier)),
                (variants[1], cpu_pair[1], (gate, attempt_dir / "right.ready", barrier)),
            ]
            for _, _, (_, ready, _) in assignments:
                ready.unlink(missing_ok=True)
            with ThreadPoolExecutor(max_workers=2) as executor:
                futures = [executor.submit(launch, variant, cpu, gate_info) for variant, cpu, gate_info in assignments]
                pair = [future.result() for future in futures]
        else:
            assignments = [(variants[0], cpu_pair[0]), (variants[1], cpu_pair[1])]
            pair = [launch(variant, cpu, None) for variant, cpu in assignments]

        if fixed is None:
            common = max(int(record["iterations"]) for record in pair)
            iteration_cache[case.program, case.name] = common, duration_ms
            calibration = pair
            continue  # Calibration performs unequal work and is never evidence.
        derived = [
            method.record_metrics(
                record,
                case.category == "multithread",
                work_only=case.category != "multithread",
            )
            for record in pair
        ]
        for record, metrics in zip(pair, derived):
            record["derived"] = metrics
            record["accepted"] = bool(metrics["valid"])
            record["pair_attempt"] = attempt
        pair_valid = all(bool(metrics["valid"]) for metrics in derived)
        if pair_valid:
            for record in pair:
                record["rejected_pair_attempts"] = rejected
            pair[0]["calibration_records"] = calibration
            return pair
        rejected.extend(
            {
                "attempt": attempt,
                "variant": record["variant"],
                "log": record["log"],
                "runner": record.get("runner"),
                "derived": metrics,
            }
            for record, metrics in zip(pair, derived)
        )
    for record in pair:
        record["rejected_pair_attempts"] = rejected
    return pair


def run_case_batch_pair(
    cases: list[Case],
    repeat: int,
    duration_ms: int,
    images: dict[tuple[str, str, int], Path],
    cpu_pair: tuple[int, int],
    output: Path,
    tag: str,
    swap_key: int,
    iteration_cache: dict[tuple[str, str], tuple[int, int]],
    stack_plan: str = "grid",
) -> list[dict[str, object]]:
    if not cases or len({case.program for case in cases}) != 1:
        raise ValueError("a process batch must contain cases from one program")
    category = cases[0].category
    if category not in ("single-cpu", "memory-local") or any(
        case.category != category for case in cases
    ):
        raise ValueError("only CPU/private-cache cases may share a process")
    policy = POLICIES[category]
    variants = list(SYSTEMS)
    if swap_key % 2:
        variants.reverse()
    rejected: list[dict[str, object]] = []
    calibration: list[dict[str, object]] = []
    pair: list[dict[str, object]] = []
    batch_id = hashlib.sha256(
        ",".join(case.name for case in cases).encode()
    ).hexdigest()[:8]
    for attempt in range(3):
        fixed = {case.name: scaled_iterations(iteration_cache, case, duration_ms) for case in cases}
        fixed = fixed if all(value is not None for value in fixed.values()) else None
        attempt_dir = output / "gates" / tag / (
            f"{cases[0].program}-batch-{batch_id}-{repeat}-a{attempt}"
        )
        attempt_dir.mkdir(parents=True, exist_ok=True)
        gate = attempt_dir / "start.gate"
        gate.unlink(missing_ok=True)
        barrier = threading.Barrier(2)
        assignments = [
            (variants[0], cpu_pair[0], attempt_dir / "left.ready"),
            (variants[1], cpu_pair[1], attempt_dir / "right.ready"),
        ]
        for _, _, ready in assignments:
            ready.unlink(missing_ok=True)

        def launch(
            variant: str, cpu: int, ready: Path
        ) -> list[dict[str, object]]:
            executable = images[variant, cases[0].program, repeat]
            return method.run_many(
                executable,
                cases[0].program,
                [case.name for case in cases],
                variant,
                repeat,
                duration_ms,
                category,
                (cpu,),
                output / "logs" / tag,
                policy.samples,
                policy.warmup_ms,
                30.0,
                gate,
                ready,
                barrier,
                fixed_iterations=fixed,
                stack_phase=stack_phase(stack_plan, repeat),
            )

        with ThreadPoolExecutor(max_workers=2) as executor:
            futures = [
                executor.submit(launch, variant, cpu, ready)
                for variant, cpu, ready in assignments
            ]
            pair = [record for future in futures for record in future.result()]
        if fixed is None:
            for case in cases:
                common = max(int(row["iterations"]) for row in pair if row["case"] == case.name)
                iteration_cache[case.program, case.name] = common, duration_ms
            calibration = pair
            continue
        derived = [
            method.record_metrics(record, False, work_only=True)
            for record in pair
        ]
        for record, metrics in zip(pair, derived):
            record["derived"] = metrics
            record["accepted"] = bool(metrics["valid"])
            record["pair_attempt"] = attempt
        grouped: dict[str, list[tuple[dict[str, object], dict[str, object]]]] = {}
        for record, metrics in zip(pair, derived):
            grouped.setdefault(str(record["case"]), []).append((record, metrics))
        dirty = [
            name
            for name, rows in grouped.items()
            if len(rows) != 2 or not all(bool(metrics["valid"]) for _, metrics in rows)
        ]
        if not dirty:
            for record in pair:
                record["rejected_pair_attempts"] = [
                    row
                    for row in rejected
                    if row["case"] == record["case"]
                ]
            pair[0]["calibration_records"] = calibration
            return pair
        rejected.extend(
            {
                "attempt": attempt,
                "variant": record["variant"],
                "case": record["case"],
                "log": record["log"],
                "runner": record.get("runner"),
                "derived": metrics,
            }
            for record, metrics in zip(pair, derived)
            if str(record["case"]) in dirty
        )
    for record in pair:
        record["rejected_pair_attempts"] = [
            row for row in rejected if row["case"] == record["case"]
        ]
    return pair


def run_stage(
    cases: list[Case],
    repeat_start: int,
    repeat_count: int,
    duration_ms: int,
    images: dict[tuple[str, str, int], Path],
    single_cpus: tuple[int, ...],
    multithread_cpus: tuple[int, ...],
    iteration_cache: dict[tuple[str, str], tuple[int, int]],
    output: Path,
    tag: str,
    batch_processes: bool = True,
    stack_plan: str = "grid",
) -> list[dict[str, object]]:
    if not cases or repeat_count <= 0:
        return []
    category = cases[0].category
    if any(case.category != category for case in cases):
        raise ValueError("run_stage requires one semantic category")
    planned_pairs = len(cases) * repeat_count
    completed_pairs = 0

    def progress(done: list[dict[str, object]]) -> None:
        nonlocal completed_pairs
        previous = completed_pairs
        completed_pairs += len(done) // 2
        if previous // 64 != completed_pairs // 64 or completed_pairs == planned_pairs:
            print(
                f"PULSE_PROGRESS stage={tag} completed_case_pairs={completed_pairs} "
                f"planned_case_pairs={planned_pairs}",
                flush=True,
            )

    cpu_pairs = [
        (single_cpus[index], single_cpus[index + 1])
        for index in range(0, len(single_cpus), 2)
    ]
    pool = PairPool(cpu_pairs)

    def pair(task: tuple[int, Case, int], cpu_pair: tuple[int, int]) -> list[dict[str, object]]:
        case_index, case, repeat = task
        return run_pair(
            case,
            repeat,
            duration_ms,
            images,
            cpu_pair,
            multithread_cpus,
            iteration_cache,
            output,
            tag,
            not (POLICIES[category].exclusive or case.exclusive),
            repeat + case_index,
            stack_plan,
        )

    def batch_pair(task: tuple[int, list[Case], int], cpu_pair: tuple[int, int]) -> list[dict[str, object]]:
        batch_index, batch, repeat = task
        return run_case_batch_pair(
            batch,
            repeat,
            duration_ms,
            images,
            cpu_pair,
            output,
            tag,
            repeat + batch_index,
            iteration_cache,
            stack_plan,
        )

    def in_rounds(items: list, work) -> list[dict[str, object]]:
        """Pair r of every item before pair r + 1 of any: a case's pairs spread
        over the whole stage, not over a second or two of it, so a passing
        disturbance of the machine meets one pair of many cases, not every pair
        of one.  The first round, which holds each case's calibration, is done
        before the others start: they take its iteration count."""
        rows: list[dict[str, object]] = []
        repeats = range(repeat_start, repeat_start + repeat_count)
        rounds = [[(index, item, repeat) for index, item in enumerate(items)] for repeat in repeats]
        for tasks in (rounds[0], [task for tasks in rounds[1:] for task in tasks]):
            for done in on_cpu_pairs(tasks, pool, lambda _, task, cpu_pair: work(task, cpu_pair)):
                rows.extend(done)
                progress(done)
        return rows

    records: list[dict[str, object]] = []
    # An exclusive case runs alone: its two sides one after the other, no
    # other pair on the machine.  The concurrent cases go first.
    alone = [case for case in cases if POLICIES[category].exclusive or case.exclusive]
    cases = [case for case in cases if case not in alone]
    if batch_processes and category in ("single-cpu", "memory-local"):
        # Move cases only touch byte buffers whose contents are not benchmark
        # state. Other programs keep process-per-case isolation: their global
        # containers/caches can be changed by a neighboring case even when the
        # final semantic digest happens to stay equal.
        batchable = [case for case in cases if case.program == "move"]
        individual = [case for case in cases if case.program != "move"]
        by_program: dict[str, list[Case]] = {}
        for case in batchable:
            by_program.setdefault(case.program, []).append(case)
        batches = [
            program_cases[start : start + PROCESS_BATCH_CASES]
            for program_cases in by_program.values()
            for start in range(0, len(program_cases), PROCESS_BATCH_CASES)
        ]
        if batches:
            records.extend(in_rounds(batches, batch_pair))
        cases = individual
    if cases:
        records.extend(in_rounds(cases, pair))
    for index, case in enumerate(alone):
        if not POLICIES[category].exclusive:
            rate = case.l2_misses_per_kcycle
            print(
                f"PULSE_EXCLUSIVE case={case.program}/{case.name} "
                f"l2_misses_per_kcycle={'unmeasured' if rate is None else f'{rate:.3f}'}",
                flush=True,
            )
    # One at a time, in rounds as well: nothing else on the machine meanwhile.
    for repeat in range(repeat_start, repeat_start + repeat_count):
        for index, case in enumerate(alone):
            cpu_pair = pool.take()
            try:
                done = pair((index, case, repeat), cpu_pair)
                records.extend(done)
                progress(done)
            finally:
                pool.give(cpu_pair)
    return records


def run_fast_preflight(
    built: dict[str, dict[str, Path]],
    single_cpus: tuple[int, ...],
    multithread_cpus: tuple[int, ...],
    output: Path,
    stack_plan: str = "grid",
) -> dict[str, object]:
    [case], _ = l2_calibration(
        [Case("calibration", "asm-dependent-add", "calibration", "instruction", "single-cpu")]
    )
    source = built["moon-candidate"]["calibration"]
    images: dict[tuple[str, str, int], Path] = {}
    for repeat in range(6):
        for system in SYSTEMS:
            target = output / "preflight-fast" / system / str(repeat) / source.name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)
            shutil.copymode(source, target)
            images[system, "calibration", repeat] = target
    records = run_stage(
        [case],
        0,
        6,
        POLICIES[case.category].initial_ms,
        images,
        single_cpus,
        multithread_cpus,
        {},
        output,
        "preflight-fast",
        stack_plan=stack_plan,
    )
    analysis = analyze_case(records, case)
    work = analysis["metrics"]["work_cycles_per_op"]
    passed = (
        analysis["semantic_match"]
        and analysis["valid_pairs"] == 6
        and len(work["ratios"]) == 6
        and 0.99 <= float(work["median"]) <= 1.01
        and float(work["central_error_percent"]) <= 1.5
    )
    return {"passed": passed, "case": asdict(case), "analysis": analysis}


def verdict(case: Case, final: dict[str, object]) -> str:
    if not final["semantic_match"]:
        return "SEMANTIC_MISMATCH"
    if int(final["valid_pairs"]) < 3 and int(final["attempted_pairs"]) < 3:
        return "STAND_LIMITED"
    if int(final["valid_pairs"]) < 3:
        return "STAND_CONTAMINATED"
    if not final["stable"]:
        return "UNSTABLE"
    metrics = final["metrics"]
    decisions = [str(metrics[name]["decision"]) for name in final["primary_metrics"]]
    improvements = "BETTER" in decisions
    regressions = "WORSE" in decisions
    if improvements and regressions:
        return "TRADEOFF"
    if regressions:
        return "WORSE"
    if improvements:
        return "BETTER"
    return "SAME"


def runner_rejections(result: dict[str, Any]) -> dict[str, int] | None:
    """Processes judged by the core they measured on and how many of them were
    rejected: the core was not idle before the process or its SMT sibling was
    busy during it.  None when no record carries it."""
    counts = {"processes": 0, "rejected": 0, "core_not_idle": 0, "sibling_busy": 0}
    seen: set[str] = set()

    def judge(process: dict[str, Any]) -> None:
        if not process.get("runner") or process["log"] in seen:
            return
        seen.add(process["log"])
        derived = process["derived"]
        core = derived["core_idle_valid"]
        sibling = derived.get("sibling_guard_valid", derived["lifetime_sibling_valid"])
        counts["processes"] += 1
        counts["rejected"] += not (core and sibling)
        counts["core_not_idle"] += not core
        counts["sibling_busy"] += not sibling

    finals = [row["final"] for row in result["cases"].values()]
    finals += [row["confirmation"]["final"] for row in result["cases"].values() if "confirmation" in row]
    finals += [result[name]["analysis"] for name in ("preflight", "confirmation_preflight")
               if (result.get(name) or {}).get("analysis")]
    for final in finals:
        for record in final["records"]:
            if record.get("derived"):
                judge(record)
            for attempt in record.get("rejected_pair_attempts", []):
                judge(attempt)
    return counts if counts["processes"] else None


def set_overall_verdict(result: dict[str, Any]) -> None:
    result["runner_rejections"] = runner_rejections(result)
    result["assessment"] = pulse_assessment.assess({"local": result})
    result["overall_verdict"] = result["assessment"]["outcome"]
    result["passed"] = result["assessment"]["complete"] and result["overall_verdict"] in ("BETTER", "SAME")
    result["measurement_completed"] = pulse_assessment.measurement_completed(result)


def confirm_changes(result, built, cases, single_cpus, multithread_cpus, iteration_cache, output,
                    stack_plan="grid"):
    """Independently check the release shortlist, retaining the complete screen."""
    names = {
        entry[1] for decision in ("BETTER", "WORSE")
        for entry in pulse_assessment.ranked_changes({"local": result}, decision)
    }
    move_result = {**result, "cases": {name: row for name, row in result["cases"].items() if name.startswith("move/")}}
    names.update(entry[1] for entry in pulse_assessment.ranked_changes({"local": move_result}, "BETTER", 4))
    if "repairs/roundto-minus2" in result["cases"]:
        names.add("repairs/roundto-minus2")
    result["confirmation_required"] = True
    selected = [case for case in cases if f"{case.program}/{case.name}" in names]
    if not selected or not (result.get("preflight") or {}).get("passed"):
        return
    directory = output / "confirmation"
    programs = sorted({case.program for case in selected})
    images = image_copies(directory, built, programs, 12)
    result["confirmation_preflight"] = run_fast_preflight(
        built, single_cpus, multithread_cpus, directory, stack_plan)
    for category, policy in POLICIES.items():
        group = [case for case in selected if case.category == category]
        if not group:
            continue
        print(f"PULSE_CONFIRM category={category} cases={len(group)} pairs=12", flush=True)
        records = run_stage(group, 0, 12, policy.initial_ms, images, single_cpus, multithread_cpus,
                            iteration_cache, directory, category, batch_processes=False,
                            stack_plan=stack_plan)
        for case in group:
            final = analyze_case([record for record in records if record["program"] == case.program
                                  and record["case"] == case.name], case)
            result["cases"][f"{case.program}/{case.name}"]["confirmation"] = {
                "final": final,
                "verdict": verdict(case, final),
                "stand_preflight_failed": not result["confirmation_preflight"]["passed"],
            }


def executable_for(
    manifest_builds: dict[str, dict[str, str]], system: str, program: str
) -> Path:
    return Path(manifest_builds[system][program])


def shape_evidence(
    executable: Path,
    definition: dict[str, object],
    cache: dict[Path, linked_image.ImageShapes],
) -> dict[str, object]:
    shapes = cache.get(executable)
    if shapes is None:
        shapes = linked_image.ImageShapes(executable)
        cache[executable] = shapes
    body_offset = int(str(definition["body"]), 16) - int(str(definition["anchor"]), 16)
    body_address = shapes.anchor + body_offset
    body = shapes[body_address]
    callees = [
        shapes[call["target"]]
        for call in body["calls"]
        if call["target"] in shapes
    ]
    evidence: dict[str, object] = {
        "body": body,
        "direct_callees": callees,
    }
    work_text = str(definition.get("workbody", "0"))
    if int(work_text, 16):
        work_offset = int(work_text, 16) - int(str(definition["anchor"]), 16)
        work = shapes[shapes.anchor + work_offset]
        evidence["work_body"] = work
        evidence["work_direct_callees"] = [
            shapes[call["target"]]
            for call in work["calls"]
            if call["target"] in shapes
        ]
    return evidence


def proof_signature(evidence: dict[str, object]) -> tuple[object, ...]:
    result: list[object] = [
        evidence["body"]["proof_sha256"],
        tuple(
            sorted(
                (callee["name"], callee["proof_sha256"])
                for callee in evidence.get("direct_callees", [])
            )
        ),
    ]
    if "work_body" in evidence:
        result.extend(
            [
                evidence["work_body"]["proof_sha256"],
                tuple(
                    sorted(
                        (callee["name"], callee["proof_sha256"])
                        for callee in evidence.get("work_direct_callees", [])
                    )
                ),
            ]
        )
    return tuple(result)


def attach_placement_evidence(
    rows: dict[str, dict[str, object]],
    built_paths: dict[str, dict[str, str]],
) -> list[str]:
    errors: list[str] = []
    cache: dict[Path, linked_image.ImageShapes] = {}
    for name, row in rows.items():
        final = row["final"]
        if row["verdict"] not in ("WORSE", "TRADEOFF"):
            continue
        definitions: dict[str, dict[str, object]] = {}
        for system in SYSTEMS:
            candidates = [
                record["case_definition"]
                for record in final["records"]
                if record["variant"] == system and record.get("case_definition")
            ]
            if candidates:
                definitions[system] = candidates[0]
        if set(definitions) != set(SYSTEMS):
            errors.append(f"{name}: missing body definitions")
            continue
        try:
            evidence = {
                system: shape_evidence(
                    executable_for(built_paths, system, row["program"]),
                    definitions[system],
                    cache,
                )
                for system in SYSTEMS
            }
            same_code = (
                proof_signature(evidence["moon-baseline"])
                == proof_signature(evidence["moon-candidate"])
            )
            same_placement = (
                check_program_placement.effective_signature(evidence["moon-baseline"])
                == check_program_placement.effective_signature(evidence["moon-candidate"])
            )
            row["code_evidence"] = {
                "same_code": same_code,
                "same_effective_placement": same_placement,
                "baseline": evidence["moon-baseline"],
                "candidate": evidence["moon-candidate"],
            }
            if same_code and not same_placement and row["verdict"] == "WORSE":
                row["diagnosis"] = "placement_suspected"
            elif same_code and same_placement and row["verdict"] == "WORSE":
                row["diagnosis"] = "same_code_same_effective_placement"
        except Exception as error:
            errors.append(f"{name}: {error}")
    return errors


def scaling_rows(rows: dict[str, dict[str, object]]) -> list[dict[str, object]]:
    groups: dict[tuple[str, str], dict[int, dict[str, object]]] = {}
    for name, row in rows.items():
        if row["category"] != "multithread":
            continue
        case = row["case"]
        parts = case.rsplit("-", 1)
        if len(parts) != 2 or not parts[1].isdigit():
            continue
        workers = int(parts[1])
        if workers not in (1, 2, 4, 8):
            continue
        groups.setdefault((row["program"], parts[0]), {})[workers] = row
    output = []
    for (program, family), members in sorted(groups.items()):
        if 1 not in members:
            continue
        for workers, row in sorted(members.items()):
            if workers == 1:
                continue
            base = members[1]["final"]["centers"]["operations_per_second"]
            current = row["final"]["centers"]["operations_per_second"]
            output.append(
                {
                    "program": program,
                    "family": family,
                    "workers": workers,
                    "remote_scaling": (
                        current["moon-baseline"] / (workers * base["moon-baseline"])
                        if base["moon-baseline"]
                        else 0.0
                    ),
                    "current_scaling": (
                        current["moon-candidate"] / (workers * base["moon-candidate"])
                        if base["moon-candidate"]
                        else 0.0
                    ),
                }
            )
    return output


def process_range_text(final: dict[str, object]) -> str:
    parts = []
    for label, system in (("R", "moon-baseline"), ("C", "moon-candidate")):
        item = final.get("process_range", {}).get(system)
        if item:
            phase = "" if item["maximum_phase"] is None else f"@{item['maximum_phase']:03x}"
            parts.append(f"{label} {item['minimum']:.3f}..{item['maximum']:.3f}{phase}")
    return " / ".join(parts) or "-"


def write_measurements(output: Path, result: dict[str, object]) -> None:
    rows: dict[str, dict[str, object]] = result["cases"]
    calibration = result.get("l2_calibration")
    rejections = result.get("runner_rejections")
    lines = [
        "# Pulse Remote vs Current",
        "",
        f"Remote: `{result['baseline_toolchain']['backend_sha256']}`.",
        f"Current: `{result['candidate_toolchain']['backend_sha256']}`.",
        f"Machine: `{result['machine']['platform']}`.",
        f"CPU work unit: `{result['machine']['cpu_work_unit']}`; multithread topology: "
        f"`{result['machine']['multithread_topology']}`.",
        f"Cases: `{len(rows)}`; elapsed: `{result['elapsed_seconds']:.1f} s`.",
        f"Stack phase: `{result.get('stack_phase', 'fixed')}` "
        "(grid: pair i calls the case at rsp = i*336 mod 4096 on both sides).",
        "Run alone by measured L2 misses: "
        + (
            "no L2 calibration; concurrent cases were not checked."
            if calibration is None
            # Saved without the event: that runner ran the cases missing from
            # its calibration concurrently, and this is the sentence it wrote.
            else f"`{', '.join(calibration['exclusive']) or 'none'}` "
            f"(over {calibration['exclusive_per_kcycle']:.2f} per 1000 cycles); "
            f"not in the calibration: `{', '.join(calibration['unmeasured']) or 'none'}`."
            if "event" not in calibration
            else f"no L2 calibration for `{calibration['machine']}`: every case ran alone."
            if calibration["event"] is None
            else f"`{', '.join(calibration['exclusive']) or 'none'}` "
            f"(over {calibration['exclusive_per_kcycle']:.2f} per 1000 cycles of "
            f"`{calibration['event']}` on `{calibration['machine']}`); "
            f"not in the calibration: `{', '.join(calibration['unmeasured']) or 'none'}` (run alone)."
        ),
        (
            "Runner: the core's idle before each process and its SMT sibling during it were not recorded."
            if rejections is None
            else f"Runner: {core_watch_text(result.get('core_watch'))}; rejected `{rejections['rejected']}` of "
            f"`{rejections['processes']}` processes (core not clean before: `{rejections['core_not_idle']}`, "
            f"SMT sibling under {method.MINIMUM_SIBLING_IDLE_RATIO:.0%} idle during: "
            f"`{rejections['sibling_busy']}`); a rejected pair is repeated within its three attempts."
        ),
        "",
        "Practical interpretation: [REPORT.md](REPORT.md).",
        "",
        "## All cases",
        "",
        "Ranges below are the observed minimum and maximum of adjacent Current/Remote process pairs. "
        "Process range: each side's cheapest..dearest process (CPU work/op; time/op for multithread), "
        "@ the case-entry rsp mod 4096 of the dearest one. "
        "p99 is the p99 of batch-average ns/op, not individual-operation latency.",
        "",
        "| Program | Case | Class | pairs | ms | Time C/R ±error [range] | CPU work C/R ±error [range] | Work/op R→C | Process range | Ops/s R→C | Cores R→C | Batch p99 R→C | Peak/after/cool C/R | Verdict | Diagnosis |",
        "| --- | --- | --- | ---: | ---: | --- | --- | ---: | --- | ---: | ---: | ---: | --- | --- | --- |",
    ]
    for name, row in sorted(rows.items()):
        final = row["final"]
        metrics = final["metrics"]
        centers = final["centers"]
        time_ratio = metrics["ticks_per_op"]["median"] or math.nan
        work_ratio = metrics["work_cycles_per_op"]["median"] or math.nan
        time_min = metrics["ticks_per_op"]["minimum"] or math.nan
        time_max = metrics["ticks_per_op"]["maximum"] or math.nan
        work_min = metrics["work_cycles_per_op"]["minimum"] or math.nan
        work_max = metrics["work_cycles_per_op"]["maximum"] or math.nan
        time_error = metrics["ticks_per_op"]["central_error_percent"]
        work_error = metrics["work_cycles_per_op"]["central_error_percent"]
        memory_ratios = [
            metrics.get(metric, {}).get("median")
            for metric in (
                "memory_peak_resident",
                "memory_after_private",
                "memory_cooldown_private",
            )
        ]
        absolute_work = centers.get("work_cycles_per_op", {})
        ops = centers.get("operations_per_second", {})
        cores = centers.get("effective_cores", {})
        p99 = centers.get("latency_p99_ns", {})
        cores_text = (
            f"{cores.get('moon-baseline', 0):.2f}→{cores.get('moon-candidate', 0):.2f}"
            if row["category"] == "multithread"
            else "-"
        )
        memory_text = (
            "/".join(f"{value:.3f}" for value in memory_ratios if value is not None)
            or "-"
        )
        separated = any(metrics[metric].get("separated") for metric in final["primary_metrics"])
        lines.append(
            f"| {row['program']} | {row['case']} | {row['category']} | "
            f"{final['valid_pairs']}/{final['attempted_pairs']} | "
            f"{row['chosen_duration_ms']} | "
            f"{time_ratio:.4f} ±{time_error:.2f}% [{time_min:.4f}..{time_max:.4f}] | "
            f"{work_ratio:.4f} ±{work_error:.2f}% [{work_min:.4f}..{work_max:.4f}] | "
            f"{absolute_work.get('moon-baseline', 0):.3f}→{absolute_work.get('moon-candidate', 0):.3f} | "
            f"{process_range_text(final)} | "
            f"{ops.get('moon-baseline', 0):.0f}→{ops.get('moon-candidate', 0):.0f} | "
            f"{cores_text} | "
            f"{p99.get('moon-baseline', 0):.3f}→{p99.get('moon-candidate', 0):.3f} | "
            f"{memory_text} | {row['verdict']}{', non-overlapping' if separated else ''} | "
            f"{row.get('diagnosis', '')} |"
        )
    scales = result["scaling"]
    if scales:
        lines.extend(
            [
                "",
                "## Multithread scaling",
                "",
                "| Program | Family | Threads | Remote | Current |",
                "| --- | --- | ---: | ---: | ---: |",
            ]
        )
        for row in scales:
            lines.append(
                f"| {row['program']} | {row['family']} | {row['workers']} | "
                f"{row['remote_scaling']:.3f} | {row['current_scaling']:.3f} |"
            )
    unstable = [
        name for name, row in rows.items() if row["verdict"] == "UNSTABLE"
    ]
    if unstable:
        lines.extend(
            [
                "",
                "## Residual unstable cases",
                "",
                "They remain in raw results and are excluded from aggregates:",
                "",
                *(f"- `{name}`" for name in sorted(unstable)),
            ]
        )
    if result["placement_errors"]:
        lines.extend(
            [
                "",
                "## Placement evidence gaps",
                "",
                *(f"- `{error}`" for error in result["placement_errors"]),
            ]
        )
    (output / "MEASUREMENTS.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_report(output: Path, result: dict[str, object]) -> None:
    write_measurements(output, result)
    pulse_assessment.write_report(output, {"local": result})


def write_result(output: Path, result: dict) -> None:
    serializable = json.loads(
        json.dumps(result, default=lambda value: asdict(value) if hasattr(value, "__dataclass_fields__") else str(value))
    )
    with gzip.open(output / "result.raw.json.gz", "wt", encoding="utf-8") as stream:
        json.dump(serializable, stream, ensure_ascii=False, separators=(",", ":"))
        stream.write("\n")
    compact = dict(serializable)
    compact["raw_result"] = "result.raw.json.gz"
    compact["raw_sha256"] = sha256(output / "result.raw.json.gz")
    compact["cases"] = {
        name: {
            **row,
            "final": {
                **row["final"],
                "records": [],
            },
            **({"confirmation": {**row["confirmation"], "final": {**row["confirmation"]["final"], "records": []}}}
               if "confirmation" in row else {}),
        }
        for name, row in serializable["cases"].items()
    }
    if compact.get("preflight") and compact["preflight"].get("analysis"):
        compact["preflight"]["analysis"]["records"] = []
    if compact.get("confirmation_preflight"):
        compact["confirmation_preflight"]["analysis"]["records"] = []
    (output / "result.json").write_text(
        json.dumps(compact, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    write_report(output, compact)


def core_watch_rule() -> dict[str, float]:
    """The rule the runner started every single-CPU process under, as a result keeps it."""
    return {
        "horizon_seconds": method.MEASUREMENT_CORE_IDLE_SECONDS,
        "idle_ratio": method.MEASUREMENT_CORE_IDLE_RATIO,
        "rest_seconds": method.MEASUREMENT_CORE_REST_SECONDS,
        "sibling_ratio": method.MINIMUM_SIBLING_IDLE_RATIO,
    }


def core_watch_text(rule: dict[str, float] | None) -> str:
    """How a result's processes were started, in the words of its own rule; a
    result from before the watch slept its horizon before every process."""
    if not rule:
        return (f"every single-CPU process started after its core was watched "
                f"{method.MEASUREMENT_CORE_IDLE_SECONDS:g} s idle")
    return (f"no single-CPU process started on a core that ran foreign work in the "
            f"{rule['horizon_seconds']:g} s before it (under {rule['idle_ratio']:.0%} idle "
            f"once the runner's own processes are taken out) or that was not idle "
            f"{rule['rest_seconds'] * 1000:g} ms since its own last process")


def machine_description(
    single_cpus: tuple[int, ...], multithread_cpus: tuple[int, ...]
) -> dict[str, object]:
    """The machine of a result, with the unit its CPU costs are in: the one
    sample_metrics computes, which MEASUREMENTS and REPORT print from here."""
    return {
        "platform": platform.platform(),
        "processor": platform.processor(),
        "logical_cpus": os.cpu_count(),
        "single_affinity": single_cpus,
        "multithread_affinity": multithread_cpus,
        "cpu_work_unit": method.CPU_WORK_UNIT,
        "multithread_topology": "dedicated coordinator"
        if len(multithread_cpus) >= 9
        else "8-core saturation; coordinator shares worker logical CPU",
    }


def run() -> int:
    args = parse_args()
    started = time.perf_counter()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    programs = [name.strip() for name in args.programs.split(",") if name.strip()]
    unknown = sorted(set(programs) - pulse.PROGRAMS.keys())
    if unknown:
        raise ValueError(f"unknown programs: {unknown}")
    patterns = [item.strip().lower() for item in args.cases.split(",") if item.strip()]
    if patterns:
        programs = [name for name in programs if any(
            "/" not in pattern or fnmatch.fnmatchcase(name.lower(), pattern.split("/", 1)[0])
            for pattern in patterns
        )]
        if not programs:
            raise ValueError(f"no selected program matches: {args.cases}")
    baseline_toolchain = args.baseline_toolchain.resolve()
    candidate_toolchain = args.candidate_toolchain.resolve()
    baseline_mm = (
        args.baseline_mm_source.resolve()
        if args.baseline_mm_source
        else baseline_toolchain / "runtime" / "mm" / "mormot.core.fpcx64mm.pas"
    )
    candidate_mm = (
        args.candidate_mm_source.resolve()
        if args.candidate_mm_source
        else candidate_toolchain / "runtime" / "mm" / "mormot.core.fpcx64mm.pas"
    )
    for path in (baseline_mm, candidate_mm):
        if not path.is_file():
            raise FileNotFoundError(f"memory manager source is missing: {path}")

    external_toolchains = {
        "moon-baseline": baseline_toolchain,
        "moon-candidate": candidate_toolchain,
    }
    external_mm = {
        "moon-baseline": baseline_mm,
        "moon-candidate": candidate_mm,
    }
    single_cpus, multithread_cpus = benchmark_cpu_sets(args.single_cpus)
    print(f"PULSE_CPU_PLAN single={single_cpus} multithread={multithread_cpus} "
          f"single_pairs={len(single_cpus) // 2}", flush=True)
    programs, unhostable = hostable(programs, multithread_cpus)
    if not programs:
        raise ValueError(f"no selected program can run on this machine: {unhostable}")
    build_programs = list(programs)
    if not args.skip_preflight and "calibration" not in build_programs:
        build_programs.append("calibration")
    if args.qualification_preflight and "codegen" not in build_programs:
        build_programs.append("codegen")
    built = pulse.build(
        build_programs,
        list(SYSTEMS),
        external_toolchains,
        external_mm,
        build_jobs=args.build_jobs,
    )
    # a program the baseline cannot build (a release without its unit) has no
    # side to compare with: named in the result, not a failed run
    programs, left_out = pulse.buildable_everywhere(built, programs)
    if not programs:
        raise ValueError(f"no selected program is built by both toolchains: {left_out}")
    cases, calibration = l2_calibration(select_cases(discover_matrix(built, programs), args.cases))
    names, unhostable_cases = hostable([f"{case.program}/{case.name}" for case in cases], multithread_cpus)
    cases = [case for case, name in zip(cases, [f"{case.program}/{case.name}" for case in cases]) if name in set(names)]
    unhostable.update(unhostable_cases)
    if calibration["event"] is None:
        print(
            f"PULSE_EXCLUSIVE calibration=missing machine={calibration['machine']} "
            f"table={calibration['table']}",
            flush=True,
        )
    if args.pairs < 6:
        raise ValueError("--pairs must be at least 6")
    if args.core_rest_ms < 0:
        raise ValueError("--core-rest-ms must not be negative")
    method.MEASUREMENT_CORE_REST_SECONDS = args.core_rest_ms / 1000
    if calibration["event"] is None or len(single_cpus) < 4:
        print(
            f"PULSE_ADVISORY machine={calibration['machine']} cases={len(cases)} "
            f"planned_case_pairs={len(cases) * args.pairs} core_pairs={len(single_cpus) // 2}: "
            "Missing host L2 calibration makes unmeasured cases run serially; "
            "few measurement cores also limit parallelism. Review the selected scope, "
            "calibration and free cores in doc/PERFORMANCE_QUALIFICATION.md before measuring.",
            file=sys.stderr,
            flush=True,
        )
    images = image_copies(output, built, programs, args.pairs)
    # Off every measurement core before the first window of the watch opens.
    for cpu in single_cpus:
        method.keep_runner_off(cpu)
    settings = (
        method.windows_machine_settings
        if os.name == "nt"
        else method.linux_machine_settings
    )
    result: dict[str, Any] = {
        "schema": 4,
        "method": "pulse-fixed-work-median-v4",
        "scope": {
            "programs": programs,
            "cases": args.cases or "all",
            "left_out": left_out,
            "unhostable": {
                program: {"workers": workers, "multithread_cpus": len(multithread_cpus)}
                for program, workers in unhostable.items()
            },
        },
        "git_head": pulse.git_text("rev-parse", "HEAD"),
        "git_status": pulse.git_text("status", "--porcelain=v1"),
        "machine": machine_description(single_cpus, multithread_cpus),
        "policy": {name: asdict(policy) for name, policy in POLICIES.items()},
        "pairs": args.pairs,
        "stack_phase": args.stack_phase,
        "core_watch": core_watch_rule(),
        "l2_calibration": {
            **calibration,
            "exclusive_per_kcycle": L2_EXCLUSIVE_PER_KCYCLE,
            "exclusive": sorted(
                f"{case.program}/{case.name}"
                for case in cases
                if case.l2_misses_per_kcycle is not None
                and case.l2_misses_per_kcycle > L2_EXCLUSIVE_PER_KCYCLE
            ),
            # Ran alone for want of a rate: cases added after the calibration,
            # or every case on a machine without one.
            "unmeasured": sorted(
                f"{case.program}/{case.name}"
                for case in cases
                if case.l2_misses_per_kcycle is None and not POLICIES[case.category].exclusive
            ),
        },
        "baseline_toolchain": pulse.moon_toolchain_identity(baseline_toolchain),
        "candidate_toolchain": pulse.moon_toolchain_identity(candidate_toolchain),
        "memory_managers": {
            "moon-baseline": {"path": str(baseline_mm), "sha256": sha256(baseline_mm)},
            "moon-candidate": {"path": str(candidate_mm), "sha256": sha256(candidate_mm)},
        },
        "built": {
            system: {
                program: str(path.resolve())
                for program, path in programs_built.items()
            }
            for system, programs_built in built.items()
        },
        "cases": {},
        "preflight": None,
    }
    cases_by_category = {
        category: [case for case in cases if case.category == category]
        for category in POLICIES
    }
    records_by_case: dict[tuple[str, str], list[dict[str, object]]] = {
        (case.program, case.name): [] for case in cases
    }
    iteration_cache: dict[tuple[str, str], tuple[int, int]] = {}
    next_repeat = {category: 0 for category in POLICIES}

    def refresh(case: Case) -> None:
        name = f"{case.program}/{case.name}"
        analysis = analyze_case(records_by_case[case.program, case.name], case)
        row = {
            "program": case.program,
            "case": case.name,
            "layer": case.layer,
            "unit": case.unit,
            "category": case.category,
            "chosen_duration_ms": POLICIES[case.category].initial_ms,
            "final": analysis,
        }
        row["verdict"] = verdict(case, analysis)
        result["cases"][name] = row

    def checkpoint() -> None:
        snapshot = dict(result)
        snapshot["cases"] = {
            name: {
                **row,
                "final": {
                    **row["final"],
                    "records": [],
                },
            }
            for name, row in result["cases"].items()
        }
        snapshot["elapsed_seconds"] = time.perf_counter() - started
        serializable = json.loads(
            json.dumps(
                snapshot,
                default=lambda value: asdict(value)
                if hasattr(value, "__dataclass_fields__")
                else str(value),
            )
        )
        temporary = output / "result.partial.json.tmp"
        temporary.write_text(
            json.dumps(serializable, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        temporary.replace(output / "result.partial.json")

    def execute_stage(category: str, selected: list[Case], pair_count: int, label: str) -> None:
        if not selected or pair_count <= 0:
            return
        policy = POLICIES[category]
        repeat_start = next_repeat[category]
        print(
            f"PULSE_FAST_STAGE category={category} pairs={pair_count} "
            f"cases={len(selected)} label={label}",
            flush=True,
        )
        records = run_stage(
            selected,
            repeat_start,
            pair_count,
            policy.initial_ms,
            images,
            single_cpus,
            multithread_cpus,
            iteration_cache,
            output,
            f"{category}-{label}-r{repeat_start}",
            stack_plan=args.stack_phase,
        )
        next_repeat[category] += pair_count
        for record in records:
            records_by_case[str(record["program"]), str(record["case"])].append(record)
        for case in selected:
            refresh(case)
        checkpoint()
        rejections = runner_rejections(result)
        print(
            f"PULSE_STAGE_DONE category={category} label={label} "
            f"completed_case_pairs={len(records) // 2} planned_case_pairs={len(selected) * pair_count} "
            f"total_rejected_processes={rejections['rejected'] if rejections else 'unavailable'}",
            flush=True,
        )

    context = (
        nullcontext({"unchanged": True})
        if args.keep_machine_settings
        else settings()
    )
    with context as machine_state:
        result["machine_settings"] = machine_state
        time.sleep(0.2)
        if not args.skip_preflight:
            result["preflight"] = (
                run_preflight(
                    built,
                    candidate_toolchain,
                    candidate_mm,
                    multithread_cpus,
                    output,
                )
                if args.qualification_preflight
                else run_fast_preflight(
                    built, single_cpus, multithread_cpus, output, args.stack_phase
                )
            )
            result["stand_preflight_failed"] = not result["preflight"]["passed"]
        measurement_started = time.perf_counter()

        # The sample count is fixed before observing results. No optional
        # stopping, confirmation starvation or replacement of inconvenient data.
        for category, category_cases in cases_by_category.items():
            execute_stage(
                category,
                category_cases,
                args.pairs,
                "coverage",
            )

        confirm_changes(result, built, cases, single_cpus, multithread_cpus, iteration_cache, output,
                        args.stack_phase)

        result["measurement_seconds"] = time.perf_counter() - measurement_started
    result["machine_settings_restored"] = not args.keep_machine_settings
    result["placement_errors"] = attach_placement_evidence(
        result["cases"], result["built"]
    )
    result["scaling"] = scaling_rows(result["cases"])
    result["elapsed_seconds"] = time.perf_counter() - started
    set_overall_verdict(result)
    write_result(output, result)
    print(
        f"PULSE_REPORT_READY measurement_completed={result['measurement_completed']} report={output / 'REPORT.md'}",
        flush=True,
    )
    return 0 if result["measurement_completed"] else 2


if __name__ == "__main__":
    try:
        raise SystemExit(run())
    except Exception:
        failure = traceback.format_exc()
        print(failure, file=sys.stderr)
        try:
            args = parse_args()
            args.output.with_suffix(".failure.log").write_text(
                failure, encoding="utf-8"
            )
        except Exception:
            pass
        raise SystemExit(1)
