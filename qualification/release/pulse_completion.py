"""Bounded, resumable completion of rejected full-Pulse pairs."""

from __future__ import annotations

import argparse
import copy
import gzip
import hashlib
import json
import os
import platform
import subprocess
import sys
import time
from collections import defaultdict
from dataclasses import asdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "qualification/performance/tools"))
import pulse_full as full
import pulse_assessment
import pulse
import pulse_roundto_oracle
import qualify_measurement_method as method


MEASUREMENT_ROOT = "qualification/performance"
# Admission retries only: the first clean pair wins, regardless of its speed.
MAX_PAIR_ATTEMPTS = 32
ALLOWED_METHOD_BRIDGE = {
    "qualification/performance/tools/pulse_full.py": (
        "8ed152684df57941ffad9e2ad00427cb96f97d9e", "736a40608aaa6c5e492d8022e3ec80011fb35da9"),
    "qualification/performance/tools/test_pulse_full.py": (
        "83fffea8aabaa1f2849e484a4c8c153c88183898", "06a44b615b5526551868e33d676a4cdece6f660a"),
}
PREVIOUS_ADMISSION_BLOB = "f77b4c57581d5a176ec171085b2b5eb94d3bceff"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def refuse(message: str) -> None:
    raise ValueError(f"Pulse completion refused: {message}")


def git(*args: str) -> str:
    return subprocess.run(["git", *args], cwd=ROOT, text=True, check=True,
                          capture_output=True).stdout.strip()


def all_original_logs(value: object) -> set[str]:
    found: set[str] = set()

    def visit(item: object) -> None:
        if isinstance(item, dict):
            for key, child in item.items():
                if key == "log" and isinstance(child, str):
                    found.add(child)
                else:
                    visit(child)
        elif isinstance(item, list):
            for child in item:
                visit(child)

    visit(value)
    return found


def create_log_manifest(source: Path) -> dict:
    source = source.resolve()
    compact = json.loads((source / "result.json").read_text(encoding="utf-8"))
    raw_path = source / "result.raw.json.gz"
    raw_sha = sha256(raw_path)
    if compact.get("raw_sha256") != raw_sha:
        refuse("source compact report does not match the full raw")
    raw = json.loads(gzip.decompress(raw_path.read_bytes()))
    entries = {}
    for name in sorted(all_original_logs(raw)):
        path = Path(name)
        if not path.resolve().is_relative_to(source) or not path.is_file():
            refuse(f"original log is missing or escapes its output: {name}")
        entries[name] = sha256(path)
    manifest_path = source / "SOURCE_LOGS_SHA256.json"
    if manifest_path.exists():
        existing = json.loads(manifest_path.read_text(encoding="utf-8"))
        if existing != entries:
            refuse("existing source log manifest differs from current logs")
    else:
        manifest_path.write_text(json.dumps(entries, ensure_ascii=False, indent=2) + "\n",
                                 encoding="utf-8")
    return {"source_raw_sha256": raw_sha, "path": str(manifest_path),
            "sha256": sha256(manifest_path), "count": len(entries)}


def verify_log_manifest(raw: dict, source: Path, expected_sha: str) -> dict:
    source = source.resolve()
    manifest_path = source / "SOURCE_LOGS_SHA256.json"
    if sha256(manifest_path) != expected_sha:
        refuse("original log manifest SHA changed")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    logs = all_original_logs(raw)
    if set(manifest) != logs:
        refuse("original log manifest does not cover every raw log exactly")
    for name, digest in manifest.items():
        path = Path(name)
        if not path.resolve().is_relative_to(source):
            refuse(f"original log escapes its output: {name}")
        if not path.is_file() or sha256(path) != digest:
            refuse(f"original log changed: {name}")
    return {"path": str(manifest_path), "sha256": expected_sha, "count": len(logs)}


def measurement_blobs(head: str) -> dict[str, str]:
    result: dict[str, str] = {}
    for line in git("ls-tree", "-r", head, MEASUREMENT_ROOT).splitlines():
        metadata, name = line.split("\t", 1)
        if name.endswith(".md"):
            continue
        result[name] = metadata.split()[2]
    return result


def verify_method(old_head: str) -> dict[str, str]:
    if git("status", "--porcelain", "--untracked-files=no"):
        refuse("tracked source is dirty")
    old = measurement_blobs(old_head)
    current = measurement_blobs("HEAD")
    changed = sorted(name for name in old.keys() | current.keys() if old.get(name) != current.get(name))
    allowed = {name: {bridge} for name, bridge in ALLOWED_METHOD_BRIDGE.items()}
    name = "qualification/performance/tools/pulse_full.py"
    allowed[name].add((PREVIOUS_ADMISSION_BLOB, ALLOWED_METHOD_BRIDGE[name][1]))
    if any((old.get(name), current.get(name)) not in allowed.get(name, set()) for name in changed):
        refuse(f"build or measurement source changed since {old_head[:12]}: {changed[:8]}")
    return {"source_head": old_head, "completion_head": git("rev-parse", "HEAD"),
            "changed_git_blobs": {name: {"before": old[name], "after": current[name]} for name in changed}}


def source_raw(source: Path, expected_sha: str, logs_sha: str) -> tuple[dict, dict]:
    source = source.resolve()
    compact = json.loads((source / "result.json").read_text(encoding="utf-8"))
    path = source / "result.raw.json.gz"
    actual = sha256(path)
    if actual != expected_sha or compact.get("raw_sha256") != actual:
        refuse("original full raw SHA differs from explicit source and compact report")
    raw = json.loads(gzip.decompress(path.read_bytes()))
    old_status = str(raw.get("git_status", ""))
    if any(line and not line.startswith("?? ") for line in old_status.splitlines()) or not raw.get("git_head"):
        refuse("original source was dirty or has no HEAD")
    method_bridge = verify_method(raw["git_head"])
    if raw.get("pairs") != 12 or raw.get("scope", {}).get("cases") != "all":
        refuse("original run is not the full twelve-pair corpus")
    scope = raw["scope"]
    if (set(scope.get("programs", [])) | set(scope.get("left_out", {}))) != set(pulse.stand_programs(True)):
        refuse("original program scope differs from the stock full corpus")
    if any(systems != ["moon-baseline"] for systems in scope.get("left_out", {}).values()):
        refuse("original candidate left out a full-corpus program")
    if not raw.get("confirmation_required"):
        refuse("original release confirmation was not required")
    preflight_gap = repairable_preflight(raw)
    if (not (raw.get("preflight") or {}).get("passed") or not raw.get("confirmation_preflight")) and not preflight_gap:
        refuse("original A/A failed or confirmation A/A is missing")
    try:
        noncomparable = pulse_roundto_oracle.prove(raw)
    except ValueError as error:
        refuse(str(error))
    if any(not row["confirmation"]["final"].get("semantic_match")
           for row in raw["cases"].values() if "confirmation" in row):
        refuse("original confirmation is semantically invalid")
    if raw.get("l2_calibration", {}).get("machine") != platform.node():
        refuse("original host key differs from this host")
    if raw.get("machine", {}).get("platform") != platform.platform():
        refuse("original OS/platform description differs")
    if raw.get("machine", {}).get("logical_cpus") != os.cpu_count():
        refuse("original CPU topology differs")
    if raw.get("stack_phase") not in ("grid", "fixed"):
        refuse("unsupported original stack phase")
    logs = verify_log_manifest(raw, source, logs_sha)
    return raw, {"source": str(source), "raw_sha256": actual,
                 "source_head": raw["git_head"], "method_bridge": method_bridge,
                 "proved_noncomparable": noncomparable, "logs": logs}


def verify_binaries(raw: dict, baseline: Path, candidate: Path,
                    baseline_mm: Path, candidate_mm: Path) -> dict[str, dict[str, Path]]:
    if raw["baseline_toolchain"] != pulse.moon_toolchain_identity(baseline):
        refuse("baseline toolchain identity differs")
    if raw["candidate_toolchain"] != pulse.moon_toolchain_identity(candidate):
        refuse("candidate toolchain identity differs")
    for system, path in (("moon-baseline", baseline_mm), ("moon-candidate", candidate_mm)):
        if sha256(path) != raw["memory_managers"][system]["sha256"]:
            refuse(f"{system} memory manager differs")
    built = {
        system: {program: Path(name) for program, name in group.items()}
        for system, group in raw["built"].items()
    }
    image_hashes: dict[tuple[str, str], set[str]] = defaultdict(set)
    for row in raw["cases"].values():
        for part in (row["final"], row.get("confirmation", {}).get("final", {})):
            for record in part.get("records", []):
                image_hashes[record["variant"], record["program"]].add(record["sha256"])
    calibration_sha = sha256(built["moon-candidate"]["calibration"])
    for part in (raw.get("preflight"), raw.get("confirmation_preflight")):
        if part is None and repairable_preflight(raw):
            continue
        analysis = (part or {}).get("analysis", {})
        records = analysis.get("records", [])
        if (len(records) != 12 or not analysis.get("semantic_match") or
                (part.get("passed") and analysis.get("valid_pairs") != 6)):
            refuse("original A/A six-pair evidence is incomplete")
        for record in records:
            if record["program"] != "calibration" or record["sha256"] != calibration_sha:
                refuse("original A/A executable differs from candidate calibration")
    for (system, program), hashes in image_hashes.items():
        if len(hashes) != 1 or sha256(built[system][program]) not in hashes:
            refuse(f"measured executable changed: {system}/{program}")
    return built


def freeze_missing(raw: dict, pair_count: int = 12) -> tuple[dict[tuple[str, int], list[dict]], dict[tuple[str, str], tuple[int, int]]]:
    missing: dict[tuple[str, int], list[dict]] = {}
    iterations: dict[tuple[str, str], tuple[int, int]] = {}
    for name, row in raw["cases"].items():
        program, case = name.split("/", 1)
        records = row["final"]["records"]
        if len(records) != 2 * pair_count:
            refuse(f"original case does not have exactly {pair_count} pairs: {name}")
        by_repeat: dict[int, list[dict]] = defaultdict(list)
        for record in records:
            if record["program"] + "/" + record["case"] != name or record["category"] != row["category"]:
                refuse(f"original record belongs to another case/category: {name}")
            by_repeat[int(record["repeat"])].append(record)
        if set(by_repeat) != set(range(pair_count)) or any(
            len(pair) != 2 or {record["variant"] for record in pair} != set(full.SYSTEMS)
            for pair in by_repeat.values()
        ):
            refuse(f"incomplete or duplicate original repeat grid: {name}")
        if any(record["stack_phase"] != full.stack_phase(raw["stack_phase"], repeat)
               for repeat, pair in by_repeat.items() for record in pair):
            refuse(f"original stack phase differs from its fixed repeat: {name}")
        counts = {int(record["iterations"]) for record in records}
        durations = {int(record["duration_ms"]) for record in records}
        if (len(counts) != 1 or len(durations) != 1 or
                not all(record["fixed_work"] and "derived" in record for record in records)):
            refuse(f"original fixed work is inconsistent: {name}")
        iterations[program, case] = counts.pop(), durations.pop()
        bad = [repeat for repeat, pair in by_repeat.items()
               if not all(record["derived"]["valid"] for record in pair)]
        if row["final"]["valid_pairs"] != pair_count - len(bad):
            refuse(f"analysis and raw validity disagree: {name}")
        for repeat in bad:
            missing[name, repeat] = by_repeat[repeat]
    if not missing:
        refuse("source has no missing clean pairs")
    return missing, iterations


def repairable_preflight(raw: dict) -> dict | None:
    """Only a complete six-pair A/A with one admission gap and matching costs."""
    preflight = raw.get("preflight") or {}
    if preflight.get("passed"):
        return None
    analysis = preflight.get("analysis") or {}
    if analysis.get("valid_pairs") != 5 or not full.preflight_cost_matches(analysis):
        return None
    case = full.Case(**preflight["case"])
    if (case.program, case.name, case.category) != ("calibration", "asm-dependent-add", "single-cpu"):
        refuse("original A/A calibration case differs")
    matrix = {"stack_phase": raw["stack_phase"], "cases": {
        "calibration/asm-dependent-add": {**asdict(case), "case": case.name, "final": analysis}}}
    missing, iterations = freeze_missing(matrix, pair_count=6)
    if len(missing) != 1:
        refuse("original A/A does not have exactly one missing pair")
    for pair in missing.values():
        for record in pair:
            metrics = record["derived"]
            if not metrics["valid"] and (not metrics.get("sample_count")
                    or metrics.get("accepted_samples") != metrics["sample_count"]
                    or not (metrics.get("core_idle_valid") is False or metrics.get("sibling_guard_valid") is False)):
                return None
    return {"case": case, "missing": missing, "iterations": iterations}


def repair_original_preflight(raw: dict, built: dict, output: Path) -> dict:
    plan = repairable_preflight(raw)
    if plan is None:
        return copy.deepcopy(raw["preflight"])
    case = plan["case"]
    (name, repeat), old = next(iter(plan["missing"].items()))
    single = tuple(raw["machine"]["single_affinity"])
    multi = tuple(raw["machine"]["multithread_affinity"])
    assigned = original_cpu_pair(old, case.category, single, multi)
    original_image = built["moon-candidate"]["calibration"]
    images = full.image_copies(output / "original-preflight", {
        system: {"calibration": original_image} for system in full.SYSTEMS}, ["calibration"], 6)
    pool = full.PairPool([assigned])
    cpu_pair = pool.take()
    try:
        pair = full.run_pair(case, repeat, plan["iterations"][case.program, case.name][1], images,
            cpu_pair, multi, plan["iterations"], output, "original-preflight",
            not case.exclusive, 0 if old[0]["variant"] == full.SYSTEMS[0] else 1,
            raw["stack_phase"], max_attempts=MAX_PAIR_ATTEMPTS)
    finally:
        pool.give(cpu_pair)
    retain_attempt(output, ["original-preflight/" + name], repeat, pair)
    replacement_pair(name, repeat, old, pair, plan["iterations"][case.program, case.name])
    records = [record for record in raw["preflight"]["analysis"]["records"] if record["repeat"] != repeat] + pair
    result = full.preflight_result(records, case)
    if not result["passed"]:
        refuse("repaired original A/A does not pass the unchanged six-pair control")
    return result


def case_descriptors(raw: dict, built: dict[str, dict[str, Path]]) -> dict[str, full.Case]:
    if raw["policy"] != {name: asdict(policy) for name, policy in full.POLICIES.items()}:
        refuse("measurement policy differs from the original run")
    if raw["core_watch"] != full.core_watch_rule():
        refuse("core-watch clean-guard policy differs from the original run")
    cases = full.discover_matrix(built, raw["scope"]["programs"])
    cpu_set = tuple(raw["machine"]["multithread_affinity"])
    hostable_names, _ = full.hostable([f"{case.program}/{case.name}" for case in cases], cpu_set)
    allowed = set(hostable_names)
    cases = [case for case in cases if f"{case.program}/{case.name}" in allowed]
    original = {name: (row["program"], row["case"], row["layer"], row["unit"], row["category"])
                for name, row in raw["cases"].items()}
    actual = {f"{case.program}/{case.name}": (case.program, case.name, case.layer, case.unit, case.category)
              for case in cases}
    if actual != original or len(cases) != len(raw["cases"]):
        refuse("measured case set/metadata differs from executable discovery")
    cases, provenance = full.l2_calibration(cases)
    if provenance != {key: raw["l2_calibration"][key] for key in provenance}:
        refuse("host L2 calibration provenance differs")
    exclusive = sorted(f"{case.program}/{case.name}" for case in cases
                       if case.l2_misses_per_kcycle is not None
                       and case.l2_misses_per_kcycle > full.L2_EXCLUSIVE_PER_KCYCLE)
    unmeasured = sorted(f"{case.program}/{case.name}" for case in cases
                        if case.l2_misses_per_kcycle is None and not full.POLICIES[case.category].exclusive)
    if (exclusive != raw["l2_calibration"]["exclusive"] or
            unmeasured != raw["l2_calibration"]["unmeasured"]):
        refuse("L2 shared/exclusive classification differs")
    return {case.program + "/" + case.name: case for case in cases}


def move_batches(raw: dict, missing: dict[tuple[str, int], list[dict]]) -> tuple[list[tuple[list[str], int]], list[tuple[str, int]]]:
    batch_groups: set[tuple[str, str, int]] = set()
    individual: list[tuple[str, int]] = []
    for (name, repeat), pair in missing.items():
        logs = [Path(record["log"]).name for record in pair]
        if name.startswith("move/") and all("-batch-" in log for log in logs):
            prefix = logs[0].split("-moon-")[0]
            if any(log.split("-moon-")[0] != prefix for log in logs):
                refuse(f"original Move pair has different process batches: {name} repeat={repeat}")
            batch_groups.add((raw["cases"][name]["category"], prefix, repeat))
        else:
            individual.append((name, repeat))
    frozen_batches = []
    for category, prefix, repeat in sorted(batch_groups):
        if category not in ("single-cpu", "memory-local"):
            refuse(f"unsupported Move batch category: {category}")
        # Original case insertion order is the discovery order used by run_stage.
        members = [name for name, row in raw["cases"].items()
                   if row["program"] == "move" and row["category"] == category
                   and any(Path(record["log"]).name.split("-moon-")[0] == prefix
                           for record in row["final"]["records"] if record["repeat"] == repeat)]
        if not members or len(members) > full.PROCESS_BATCH_CASES:
            refuse(f"cannot recover complete Move batch: {prefix}")
        names = [name.split("/", 1)[1] for name in members]
        batch_hash = hashlib.sha256(",".join(names).encode()).hexdigest()[:8]
        if prefix != f"move-batch-{names[0]}-{len(names)}-{batch_hash}":
            refuse(f"Move batch order/hash differs: {prefix}")
        for name in members:
            pair = [record for record in raw["cases"][name]["final"]["records"]
                    if record["repeat"] == repeat]
            if (len(pair) != 2 or [Path(record["log"]).name.split("-moon-")[0] for record in pair] !=
                    [prefix, prefix]):
                refuse(f"Move batch member is incomplete: {name} repeat={repeat}")
        orders = {tuple(record["variant"] for record in raw["cases"][name]["final"]["records"]
                        if record["repeat"] == repeat) for name in members}
        if len(orders) != 1:
            refuse(f"Move batch variant order differs by member: {prefix}")
        frozen_batches.append((members, repeat))
    included = {(name, repeat) for members, repeat in frozen_batches for name in members
                if (name, repeat) in missing}
    if included | set(individual) != set(missing) or included & set(individual):
        refuse("frozen completion plan is not an exact partition of missing pairs")
    return frozen_batches, sorted(individual)


def replacement_pair(name: str, repeat: int, old: list[dict], measured: list[dict],
                     fixed: tuple[int, int]) -> list[dict]:
    if len(old) != 2 or all(record["derived"]["valid"] for record in old):
        refuse(f"attempted to replace an original valid pair: {name} repeat={repeat}")
    pair = [record for record in measured
            if record["program"] + "/" + record["case"] == name and record["repeat"] == repeat]
    if len(pair) != 2 or {record["variant"] for record in pair} != set(full.SYSTEMS):
        refuse(f"replacement does not contain one pair: {name} repeat={repeat}")
    if [record["variant"] for record in pair] != [record["variant"] for record in old]:
        refuse(f"replacement changed variant order: {name} repeat={repeat}")
    if any(not record["derived"]["valid"] or not record["fixed_work"] or
           record["iterations"] != fixed[0] or record["duration_ms"] != fixed[1]
           for record in pair):
        refuse(f"replacement is dirty or changed work: {name} repeat={repeat}")
    old_hashes = {record["variant"]: record["sha256"] for record in old}
    if any(record["sha256"] != old_hashes[record["variant"]] for record in pair):
        refuse(f"replacement executable differs: {name} repeat={repeat}")
    if any(tuple(record["affinity"]) != tuple(prior["affinity"]) for record, prior in zip(pair, old)):
        refuse(f"replacement CPU assignment differs: {name} repeat={repeat}")
    if any(record["stack_phase"] != old[0]["stack_phase"] for record in pair):
        refuse(f"replacement stack phase differs: {name} repeat={repeat}")
    return pair


def original_cpu_pair(old: list[dict], category: str, single_cpus: tuple[int, ...],
                      multithread_cpus: tuple[int, ...]) -> tuple[int, int] | None:
    if category == "multithread":
        if any(tuple(record["affinity"]) != multithread_cpus for record in old):
            refuse("original multithread CPU allocation differs")
        return None
    if len(old) != 2 or any(len(record["affinity"]) != 1 for record in old):
        refuse("original CPU pair is incomplete")
    assigned = tuple(record["affinity"][0] for record in old)
    allowed = {(single_cpus[index], single_cpus[index + 1]) for index in range(0, len(single_cpus), 2)}
    if assigned not in allowed:
        refuse(f"original CPU pair is outside the measured allocation: {assigned}")
    return assigned


def shortlist(result: dict) -> set[str]:
    names = {
        entry[1] for decision in ("BETTER", "WORSE")
        for entry in pulse_assessment.ranked_changes({"local": result}, decision)
    }
    move_result = {**result, "cases": {name: row for name, row in result["cases"].items()
                                       if name.startswith("move/")}}
    names.update(entry[1] for entry in pulse_assessment.ranked_changes({"local": move_result}, "BETTER", 4))
    if "repairs/roundto-minus2" in result["cases"]:
        names.add("repairs/roundto-minus2")
    return names


def retain_attempt(output: Path, members: list[str], repeat: int, measured: list[dict]) -> None:
    with (output / "COMPLETION_ATTEMPTS.jsonl").open("a", encoding="utf-8") as stream:
        stream.write(json.dumps({"members": members, "repeat": repeat, "records": measured},
                                ensure_ascii=False, separators=(",", ":")) + "\n")


def resume_pairs(output: Path, plan: dict, missing: dict, iterations: dict) -> tuple[dict, list[dict]]:
    """Keep the first clean observation from earlier attempts of this exact job."""
    replacement, receipts = {}, []
    attempt = output.parent.name
    if output.name != "out" or not attempt.startswith("attempt-") or not attempt[8:].isdigit():
        return replacement, receipts
    expected = json.loads(json.dumps(plan))
    allowed = {(tuple(row["members"]), row["repeat"]) for row in plan["frozen_move_batches"]}
    batched = {(name, repeat) for members, repeat in allowed for name in members}
    allowed.update(((name,), repeat) for name, repeat in missing if (name, repeat) not in batched)
    for directory in sorted(output.parent.parent.glob("attempt-*/out")):
        number = directory.parent.name[8:]
        journal = directory / "COMPLETION_ATTEMPTS.jsonl"
        preflight = directory / "COMPLETION_PREFLIGHT.json"
        prior_plan = directory / "COMPLETION_ORIGIN.json"
        if (not number.isdigit() or int(number) >= int(attempt[8:]) or not journal.is_file()
                or not preflight.is_file() or not prior_plan.is_file()):
            continue
        prior = json.loads(prior_plan.read_text(encoding="utf-8"))
        # The current completion HEAD may differ only in controller code, not measurement code.
        keys = ("source", "raw_sha256", "source_head", "logs")
        if (any(prior["origin"].get(key) != expected["origin"].get(key) for key in keys)
                or any(prior.get(key) != expected.get(key)
                       for key in ("frozen_missing", "frozen_move_batches", "max_attempts"))):
            continue
        if not json.loads(preflight.read_text(encoding="utf-8")).get("passed"):
            continue
        bridge = verify_method(prior["completion_head"])
        data = journal.read_bytes()
        receipt = {"source": str(directory), "method_bridge": bridge,
                   "plan_sha256": sha256(prior_plan), "preflight_sha256": sha256(preflight),
                   "journal_sha256": hashlib.sha256(data).hexdigest(), "logs": {}, "pairs": []}
        parsed_logs, image_hashes = {}, {}
        for line in data.splitlines(keepends=True):
            if not line.endswith(b"\n"):
                break  # An interrupted append cannot supply evidence.
            stage = json.loads(line)
            members, repeat = stage["members"], stage["repeat"]
            if members == ["original-preflight/calibration/asm-dependent-add"]:
                continue  # Original A/A recovery is checked separately on every invocation.
            if (tuple(members), repeat) not in allowed:
                refuse(f"resumed stage changed its frozen process context: {journal}")
            measured = stage["records"]
            if len(measured) != 2 * len(members):
                refuse(f"resumed stage has incomplete records: {journal}")
            for name in members:
                key = name, repeat
                if key not in missing or key in replacement:
                    continue
                pair = [row for row in measured if row["program"] + "/" + row["case"] == name
                        and row["repeat"] == repeat]
                if len(pair) != 2:
                    refuse(f"resumed stage has an incomplete pair: {name}")
                for row, old in zip(pair, missing[key]):
                    if row["category"] != old["category"]:
                        refuse(f"resumed category differs: {name}")
                    multithread = row["category"] == "multithread"
                    metrics = method.record_metrics(row, multithread, work_only=not multithread)
                    if metrics != row["derived"]:
                        refuse(f"resumed metrics differ from original raw counters: {name}")
                if not all(row["derived"]["valid"] for row in pair):
                    continue
                replacement_pair(name, repeat, missing[key], pair, iterations[tuple(name.split("/", 1))])
                for row in pair:
                    log, image = Path(row["log"]), Path(row["executable"])
                    if not log.resolve().is_relative_to(directory.resolve()) or not log.is_file():
                        refuse(f"resumed log is missing or outside its attempt: {log}")
                    if not image.resolve().is_relative_to(directory.resolve()) or not image.is_file():
                        refuse(f"resumed executable is missing or outside its attempt: {image}")
                    if image not in image_hashes:
                        image_hashes[image] = sha256(image)
                    if image_hashes[image] != row["sha256"]:
                        refuse(f"resumed executable changed: {image}")
                    if log not in parsed_logs:
                        parsed_logs[log] = method.parse_measurement_output(
                            log.read_text(encoding="utf-8"), row["program"],
                            [item.split("/", 1)[1] for item in members], len(row["samples"]), log)
                        receipt["logs"][str(log)] = sha256(log)
                    definitions, samples = parsed_logs[log]
                    if definitions[row["case"]] != row["case_definition"] or samples[row["case"]] != row["samples"]:
                        refuse(f"resumed record differs from its process log: {log}")
                replacement[key] = pair
                receipt["pairs"].append([name, repeat])
        if receipt["pairs"]:
            snapshot = output / (directory.parent.name + "-COMPLETION_ATTEMPTS.jsonl")
            snapshot.write_bytes(data)
            receipt["journal_snapshot"] = str(snapshot)
            receipts.append(receipt)
    return replacement, receipts


def complete(source: Path, source_sha: str, source_logs_sha: str, output: Path,
             baseline: Path, candidate: Path, baseline_mm: Path, candidate_mm: Path,
             expected_single_cpus: str = "") -> None:
    started = time.perf_counter()
    raw, origin = source_raw(source, source_sha, source_logs_sha)
    built = verify_binaries(raw, baseline, candidate, baseline_mm, candidate_mm)
    missing, iterations = freeze_missing(raw)
    cases = case_descriptors(raw, built)
    batches, individual = move_batches(raw, missing)
    single_cpus = tuple(raw["machine"]["single_affinity"])
    multithread_cpus = tuple(raw["machine"]["multithread_affinity"])
    if len(single_cpus) < 2 or len(single_cpus) % 2:
        refuse("original single-CPU allocation is malformed")
    if expected_single_cpus and tuple(int(cpu.strip()) for cpu in expected_single_cpus.split(",")) != single_cpus:
        refuse("requested single-CPU plan differs from original measured plan")
    if output.exists() and any(output.iterdir()):
        refuse("completion output already contains files")
    output.mkdir(parents=True, exist_ok=True)
    for cpu in single_cpus:
        method.keep_runner_off(cpu)
    programs = sorted({name.split("/", 1)[0] for name, _ in missing} |
                      {name.split("/", 1)[0] for members, _ in batches for name in members})
    images = full.image_copies(output, built, programs, 12)
    frozen_missing = []
    for (name, repeat), old in sorted(missing.items()):
        cpu_pair = original_cpu_pair(old, cases[name].category, single_cpus, multithread_cpus)
        fixed = iterations[tuple(name.split("/", 1))]
        frozen_missing.append({
            "case": name, "repeat": repeat, "category": cases[name].category,
            "variant_order": [record["variant"] for record in old],
            "affinities": [record["affinity"] for record in old],
            "cpu_pair": cpu_pair, "stack_phase": old[0]["stack_phase"],
            "iterations": fixed[0], "duration_ms": fixed[1],
            "executables_sha256": [record["sha256"] for record in old],
        })
    fresh_context: list[dict] = []
    result = copy.deepcopy(raw)
    result["git_head"] = git("rev-parse", "HEAD")
    result["git_status"] = git("status", "--porcelain=v1")
    if origin["proved_noncomparable"]:
        result["release_validation"] = {"proved_noncomparable": origin["proved_noncomparable"]}
    result["completion"] = {
        "origin": origin,
        "max_attempts": MAX_PAIR_ATTEMPTS,
        "completion_head": result["git_head"],
        "original_runner_rejections": raw.get("runner_rejections"),
        "frozen_missing": frozen_missing,
        "frozen_move_batches": [{"members": members, "repeat": repeat} for members, repeat in batches],
        "old_invalid_records": {f"{name}@{repeat}": pair for (name, repeat), pair in missing.items()},
        "new_repair_records": {},
        "new_context_records": fresh_context,
        "fresh_preflight": None,
        "original_preflight": copy.deepcopy(raw["preflight"]),
        "original_confirmation_preflight": copy.deepcopy(raw.get("confirmation_preflight")),
        "original_confirmations": {name: copy.deepcopy(row["confirmation"])
                                   for name, row in raw["cases"].items() if row.get("confirmation")},
        "new_confirmations": [],
    }
    plan = {"origin": origin, "completion_head": result["git_head"], "max_attempts": MAX_PAIR_ATTEMPTS,
            "frozen_missing": frozen_missing, "frozen_move_batches": result["completion"]["frozen_move_batches"]}
    (output / "COMPLETION_ORIGIN.json").write_text(json.dumps(plan, indent=2) + "\n", encoding="utf-8")
    replacement, receipts = resume_pairs(output, plan, missing, iterations)
    result["completion"]["resumed_attempts"] = receipts
    (output / "COMPLETION_RESUME.json").write_text(json.dumps(receipts, indent=2) + "\n", encoding="utf-8")
    print(f"PULSE_COMPLETION_RESUMED pairs={len(replacement)} remaining={len(missing) - len(replacement)}", flush=True)
    cpu_pairs = [(single_cpus[index], single_cpus[index + 1])
                 for index in range(0, len(single_cpus), 2)]
    pair_pools = {pair: full.PairPool([pair]) for pair in cpu_pairs}
    multithread_pool = full.PairPool(cpu_pairs)
    settings = method.windows_machine_settings if os.name == "nt" else method.linux_machine_settings
    with settings() as machine_state:
        result["completion"]["machine_settings"] = machine_state
        result["preflight"] = repair_original_preflight(raw, built, output)
        result["stand_preflight_failed"] = not result["preflight"]["passed"]
        (output / "COMPLETION_ORIGINAL_PREFLIGHT.json").write_text(
            json.dumps(result["preflight"], indent=2) + "\n", encoding="utf-8")
        result["completion"]["fresh_preflight"] = full.run_fast_preflight(
            built, single_cpus, multithread_cpus, output, raw["stack_phase"], max_attempts=MAX_PAIR_ATTEMPTS)
        (output / "COMPLETION_PREFLIGHT.json").write_text(
            json.dumps(result["completion"]["fresh_preflight"], ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        if not result["completion"]["fresh_preflight"]["passed"]:
            refuse("fresh A/A preflight failed")
        for members, repeat in batches:
            if all((name, repeat) not in missing or (name, repeat) in replacement for name in members):
                continue
            name = next(name for name in members if (name, repeat) in missing)
            old = missing[name, repeat]
            orientation = 0 if old[0]["variant"] == full.SYSTEMS[0] else 1
            categories = {cases[item].category for item in members}
            durations = {iterations[tuple(item.split("/", 1))][1] for item in members}
            if len(categories) != 1 or len(durations) != 1:
                refuse(f"Move batch has inconsistent category/duration: {members[0]}")
            category = next(iter(categories))
            assigned = original_cpu_pair(old, category, single_cpus, multithread_cpus)
            if any(original_cpu_pair([record for record in raw["cases"][item]["final"]["records"]
                                      if record["repeat"] == repeat], category, single_cpus, multithread_cpus)
                   != assigned for item in members):
                refuse(f"original Move batch members used different CPU pairs: {members[0]}")
            pair_pool = pair_pools[assigned]
            cpu_pair = pair_pool.take()
            try:
                measured = full.run_case_batch_pair(
                    [cases[item] for item in members], repeat, durations.pop(),
                    images, cpu_pair, output, "completion-" + category, orientation,
                    iterations, raw["stack_phase"], max_attempts=MAX_PAIR_ATTEMPTS,
                    required_names={item.split("/", 1)[1] for item in members
                                    if (item, repeat) in missing and (item, repeat) not in replacement})
            finally:
                pair_pool.give(cpu_pair)
            retain_attempt(output, members, repeat, measured)
            if len(measured) != 2 * len(members):
                refuse(f"Move batch changed its case count: {members[0]} repeat={repeat}")
            for item in members:
                pair = [record for record in measured
                        if record["program"] + "/" + record["case"] == item]
                if (item, repeat) in missing and (item, repeat) not in replacement:
                    replacement[item, repeat] = replacement_pair(
                        item, repeat, missing[item, repeat], pair,
                        iterations[tuple(item.split("/", 1))])
                else:
                    fresh_context.extend(pair)
        for name, repeat in individual:
            if (name, repeat) in replacement:
                continue
            case = cases[name]
            old = missing[name, repeat]
            orientation = 0 if old[0]["variant"] == full.SYSTEMS[0] else 1
            assigned = original_cpu_pair(old, case.category, single_cpus, multithread_cpus)
            pair_pool = pair_pools[assigned] if assigned is not None else multithread_pool
            cpu_pair = pair_pool.take()
            try:
                measured = full.run_pair(
                    case, repeat, iterations[case.program, case.name][1], images,
                    cpu_pair, multithread_cpus, iterations, output,
                    "completion-" + case.category,
                    not (full.POLICIES[case.category].exclusive or case.exclusive),
                    orientation, raw["stack_phase"], max_attempts=MAX_PAIR_ATTEMPTS)
            finally:
                pair_pool.give(cpu_pair)
            retain_attempt(output, [name], repeat, measured)
            replacement[name, repeat] = replacement_pair(
                name, repeat, old, measured, iterations[case.program, case.name])
        if set(replacement) != set(missing):
            refuse("completion did not return every frozen missing pair")
        for name, row in result["cases"].items():
            relevant = {repeat: pair for (key, repeat), pair in replacement.items() if key == name}
            if not relevant:
                continue
            original = row["final"]["records"]
            merged = []
            inserted = set()
            for record in original:
                repeat = record["repeat"]
                if repeat not in relevant:
                    merged.append(record)
                elif repeat not in inserted:
                    merged.extend(relevant[repeat])
                    inserted.add(repeat)
                    result["completion"]["new_repair_records"][f"{name}@{repeat}"] = relevant[repeat]
            if inserted != set(relevant):
                refuse(f"original repeat disappeared during completion: {name}")
            final = full.analyze_case(merged, cases[name])
            if final["valid_pairs"] != 12 or final["attempted_pairs"] != 12 or not final["semantic_match"]:
                refuse(f"completed case still fails semantics or twelve-pair coverage: {name}")
            row["final"] = final
            row["verdict"] = full.verdict(cases[name], final)
        needed = shortlist(result)
        original_confirmed = set(result["completion"]["original_confirmations"])
        repeat_confirmations = (not (raw.get("confirmation_preflight") or {}).get("passed") or
                                any(row["final"]["valid_pairs"] != 12
                                    for row in result["completion"]["original_confirmations"].values()))
        confirmation_names = needed | original_confirmed if repeat_confirmations else needed - original_confirmed
        new_confirmations = [cases[name] for name in sorted(confirmation_names) if name in result["cases"]]
        if new_confirmations:
            directory = output / "confirmation"
            confirm_images = full.image_copies(directory, built,
                                               sorted({case.program for case in new_confirmations}), 12)
            confirm_preflight = full.run_fast_preflight(
                built, single_cpus, multithread_cpus, directory, raw["stack_phase"], max_attempts=MAX_PAIR_ATTEMPTS)
            result["completion"]["confirmation_preflight"] = confirm_preflight
            (output / "COMPLETION_CONFIRMATION_PREFLIGHT.json").write_text(
                json.dumps(confirm_preflight, ensure_ascii=False, indent=2) + "\n",
                encoding="utf-8",
            )
            if not confirm_preflight["passed"]:
                refuse("new confirmation A/A preflight failed")
            if repeat_confirmations:
                result["confirmation_preflight"] = confirm_preflight
            for category, policy in full.POLICIES.items():
                group = [case for case in new_confirmations if case.category == category]
                if not group:
                    continue
                measured = full.run_stage(
                    group, 0, 12, policy.initial_ms, confirm_images, single_cpus,
                    multithread_cpus, iterations, directory, category,
                    batch_processes=False, stack_plan=raw["stack_phase"], max_attempts=MAX_PAIR_ATTEMPTS)
                (output / f"COMPLETION_CONFIRMATION_{category}.json").write_text(
                    json.dumps(measured, ensure_ascii=False, separators=(",", ":")) + "\n",
                    encoding="utf-8",
                )
                for case in group:
                    name = case.program + "/" + case.name
                    pair_records = [record for record in measured if record["program"] == case.program
                                    and record["case"] == case.name]
                    final = full.analyze_case(pair_records, case)
                    if final["valid_pairs"] != 12 or not final["semantic_match"]:
                        refuse(f"new confirmation is dirty or semantically wrong: {name}")
                    result["cases"][name]["confirmation"] = {
                        "final": final, "verdict": full.verdict(case, final),
                        "stand_preflight_failed": False,
                    }
                    result["completion"]["new_confirmations"].append(name)
    result["completion"]["machine_settings_restored"] = True
    result["completion"]["measurement_seconds"] = time.perf_counter() - started
    result["measurement_seconds"] += result["completion"]["measurement_seconds"]
    result["elapsed_seconds"] += result["completion"]["measurement_seconds"]
    result["scaling"] = full.scaling_rows(result["cases"])
    full.set_overall_verdict(result)
    comparable_cases = {name: row for name, row in result["cases"].items()
                        if name != pulse_roundto_oracle.CASE or not origin["proved_noncomparable"]}
    if not pulse_assessment.measurement_completed({**result, "cases": comparable_cases}):
        refuse("completed matrix failed stock semantic or A/A assessment")
    full.write_result(output, result)
    print(f"PULSE_COMPLETION_READY repaired_pairs={len(missing)} "
          f"new_confirmations={len(result['completion']['new_confirmations'])} "
          f"report={output / 'REPORT.md'}", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("manifest",))
    parser.add_argument("--source", type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(create_log_manifest(args.source), sort_keys=True))
