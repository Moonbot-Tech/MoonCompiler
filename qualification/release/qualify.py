#!/usr/bin/env python3
"""Run a release matrix with persistent evidence, failure collection and resume."""

from __future__ import annotations

import argparse
from concurrent.futures import FIRST_COMPLETED, ThreadPoolExecutor, wait
from datetime import datetime, timezone
import hashlib
import json
import os
import platform as host_platform
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import time


ROOT = Path(__file__).resolve().parents[2]
MATRIX = Path(__file__).with_name("matrix.json")
LEVELS = {"light": 0, "medium": 1, "full": 2}
sys.path.insert(0, str(Path(__file__).resolve().parent))
from inputs import digest_paths, product_identity


def stage(job: dict) -> int:
    return job.get("stage", LEVELS[job["mode"]])


def allocation(job: dict, workers: int, memory_mb: int) -> int:
    return min(job.get("slots", 1), workers, memory_mb // job.get("memory_mb_per_slot", 512))


def earlier(jobs: list[dict], job: dict) -> list[str]:
    return [row["id"] for row in jobs if stage(row) < stage(job)]


def parents(job: dict, platform: str) -> list[str]:
    return job.get("needs", []) + job.get("needs_by_platform", {}).get(platform, [])


def git(*args: str) -> str:
    result = subprocess.run(["git", *args], cwd=ROOT, capture_output=True,
                            text=True, check=True)
    return result.stdout.strip()


def save(path: Path, state: dict) -> None:
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(state, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


def load_matrix(path: Path, platform: str, mode: str,
                final: bool = False, skip_pulse: bool = False,
                pulse_single_cpus: str = "", pulse_completion: tuple[str, str, str] = ("", "", "")) -> list[dict]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if data.get("version") != 1:
        raise ValueError("matrix version must be 1")
    inputs = data.get("source_inputs", {})
    if set(inputs) != {row["id"] for row in data["jobs"]}:
        raise ValueError("source_inputs must name every matrix job exactly once")
    jobs = [row for row in data["jobs"] if platform in row["platforms"]
            and LEVELS[row["mode"]] <= LEVELS[mode]
            and (not skip_pulse or row["id"] != "pulse_report")
            and (final or not row.get("final_only", False))]
    for row in jobs:
        if row["id"] == "pulse_report":
            if pulse_single_cpus:
                row["commands"][platform] += ["--single-cpus", pulse_single_cpus]
            if pulse_completion[0]:
                row["commands"][platform] += ["--complete-from", pulse_completion[0],
                                              "--complete-sha256", pulse_completion[1],
                                              "--complete-logs-sha256", pulse_completion[2]]
    names = [row["id"] for row in jobs]
    if len(names) != len(set(names)):
        raise ValueError("duplicate job id")
    by_id = {row["id"]: row for row in jobs}
    for row in jobs:
        if any(parent not in names for parent in parents(row, platform)):
            raise ValueError(f"{row['id']}: dependency absent from {mode} mode")
        if row["timeout"] <= 0 or not row["commands"].get(platform):
            raise ValueError(f"{row['id']}: invalid timeout or command")
        sources = inputs[row["id"]]
        if not sources or any(not isinstance(item, str) or not item for item in sources):
            raise ValueError(f"{row['id']}: invalid source inputs")
        row["source_inputs"] = sources
        if row.get("slots", 1) < 1 or row.get("memory_mb_per_slot", 512) < 1:
            raise ValueError(f"{row['id']}: invalid resource budget")
        if any(stage(by_id[parent]) > stage(row)
               for parent in parents(row, platform)):
            raise ValueError(f"{row['id']}: dependency belongs to a later stage")
    visiting, visited = set(), set()
    def visit(name: str) -> None:
        if name in visiting:
            raise ValueError(f"matrix dependency cycle: {name}")
        if name in visited:
            return
        visiting.add(name)
        for parent in parents(by_id[name], platform):
            visit(parent)
        visiting.remove(name)
        visited.add(name)
    for name in names:
        visit(name)
    return jobs


def context(root: Path, run_dir: Path, platform: str, head: str,
            job_dir: Path, baseline: str) -> dict[str, str]:
    run_id = (f"qual-{hashlib.sha256(str(run_dir).encode()).hexdigest()[:8]}-"
              f"{job_dir.parents[2].name}-{job_dir.parent.name}-{head[:8]}-{job_dir.name}")
    if platform == "win64":
        bin_dir = root / "toolchain/bin/x86_64-win64"
        ide_dir = root / "toolchain/ide/bin/x86_64-win64"
        return {"root": str(root), "run_dir": str(run_dir),
                "job_dir": str(job_dir), "run_id": run_id,
                "head": head, "python": sys.executable, "baseline": baseline,
                "shell": shutil.which("pwsh") or "powershell",
                "dcc": r"C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\dcc64.exe",
                "dcc_lib": r"C:\Program Files (x86)\Embarcadero\Studio\23.0\lib\win64\release",
                "fpc": str(bin_dir / "fpc.exe"), "pp": str(bin_dir / "ppcx64.exe"),
                "cfg": str(bin_dir / "moon-base.cfg"),
                "rtl": str(root / "toolchain/units/x86_64-win64/rtl"),
                "ide_cfg": str(ide_dir / "fpc.cfg"),
                "msg2inc": str(ide_dir / "msg2inc.exe"),
                "legacy_fpc": os.environ.get("MOONBOT_BOOTSTRAP_FPC") or str(
                    Path(os.environ.get("LOCALAPPDATA", str(Path.home() / "AppData/Local"))) /
                    "MoonCompiler/bootstrap/3.2.2/bin/i386-win32/fpc.exe"),
                "objdump": str(bin_dir / "objdump.exe")}
    rtl_matches = list((root / "toolchain/lib/fpc").glob(
        "*/units/x86_64-linux/rtl/system.ppu"))
    if len(rtl_matches) > 1:
        raise ValueError(f"expected one installed Linux RTL, found {len(rtl_matches)}")
    rtl = (rtl_matches[0].parent if rtl_matches else
           root / "toolchain/lib/fpc/3.3.1/units/x86_64-linux/rtl")
    return {"root": str(root), "run_dir": str(run_dir),
            "job_dir": str(job_dir), "run_id": run_id,
            "head": head, "python": sys.executable, "baseline": baseline,
            "shell": "bash",
            "fpc": str(root / "toolchain/bin/fpc"),
            "pp": str(root / "toolchain/bin/ppcx64"),
            "cfg": str(root / "toolchain/etc/moon-base.cfg"),
            "rtl": str(rtl),
            "ide_cfg": str(root / "toolchain/ide/etc/fpc.cfg"),
            "msg2inc": str(root / "toolchain/ide/bin/msg2inc"),
            "legacy_fpc": os.environ.get("MOONBOT_BOOTSTRAP_FPC") or "/usr/bin/fpc",
            "objdump": shutil.which("objdump") or "objdump"}


def expand(value: str, values: dict[str, str]) -> str:
    for key, replacement in values.items():
        value = value.replace("{" + key + "}", replacement)
    if "{" in value or "}" in value:
        raise ValueError(f"unresolved matrix variable: {value}")
    return value


def fingerprint(job: dict, platform: str) -> str:
    fields = {key: job.get(key) for key in ("id", "needs", "needs_by_platform",
                                          "expected", "source_inputs")}
    fields["command"] = job["commands"][platform]
    fields["cwd"] = job.get("cwd", "{root}")
    return hashlib.sha256(json.dumps(fields, sort_keys=True).encode()).hexdigest()


def input_signatures(jobs: list[dict], platform: str, head: str,
                     product: str = "", baseline: str = "") -> dict[str, str]:
    selected = {job["id"]: job for job in jobs}
    tree_ids: dict[str, str] = {}
    signatures: dict[str, str] = {}

    def signature(name: str) -> str:
        if name not in signatures:
            job = selected[name]
            sources = {}
            for path in job["source_inputs"]:
                if path not in tree_ids:
                    tree_ids[path] = git("rev-parse", f"{head}:{path}")
                sources[path] = tree_ids[path]
            data = {"schema": 2, "job": fingerprint(job, platform), "sources": sources,
                    "parents": {parent: (product if parent == "build" and product else signature(parent))
                                for parent in parents(job, platform)}}
            if job.get("baseline_input"):
                data["baseline"] = baseline
            signatures[name] = hashlib.sha256(json.dumps(data, sort_keys=True).encode()).hexdigest()
        return signatures[name]

    for job in jobs:
        signature(job["id"])
    return signatures


def estimate(job: dict, platform: str) -> int | None:
    return job.get("estimated_seconds_by_platform", {}).get(platform)


def execute(job: dict, platform: str, head: str, run_dir: Path,
            attempt: int, phase: str, baseline: str, input_signature: str,
            slots: int = 1) -> dict:
    name = job["id"]
    phase_dir = run_dir / phase
    job_dir = phase_dir / "jobs" / name / f"attempt-{attempt:04d}"
    job_dir.mkdir(parents=True)
    values = context(ROOT, run_dir, platform, head, job_dir, baseline)
    values.update(job_slots=str(slots),
                  baseline_mm=job.get("baseline_mm", ""),
                  checkpoint_dir=str(run_dir / phase / "checkpoints" / name / input_signature[:16]))
    command = [expand(arg, values) for arg in job["commands"][platform]]
    cwd = Path(expand(job.get("cwd", "{root}"), values))
    log_path = phase_dir / "logs" / f"{name}-{attempt:04d}.log"
    started = time.monotonic()
    with log_path.open("w", encoding="utf-8", errors="replace") as log:
        if "verify_build" in job:
            # Replay against the artifact that passed Full, preserving its build provenance.
            log.write("VERIFY_QUALIFIED_PRODUCT " + json.dumps(job["verify_build"]) + "\n")
            code = 0 if product_identity(ROOT) == job["verify_build"]["product_identity"] else 2
            log.write(f"PRODUCT_IDENTITY {'PASS' if code == 0 else 'FAIL'}\n")
        else:
            log.write("COMMAND " + json.dumps(command) + "\n")
            log.flush()
            flags = subprocess.CREATE_NEW_PROCESS_GROUP if os.name == "nt" else 0
            process = subprocess.Popen(command, cwd=cwd, stdout=log,
                                       stderr=subprocess.STDOUT,
                                       creationflags=flags,
                                       start_new_session=os.name != "nt")
            try:
                code = process.wait(timeout=job["timeout"])
            except subprocess.TimeoutExpired:
                if os.name == "nt":
                    subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"], capture_output=True)
                else:
                    os.killpg(process.pid, signal.SIGKILL)
                process.wait()
                code = 124
                log.write("\n<TIMEOUT>\n")
    expected = job.get("expected")
    if code == 0 and expected is not None and "verify_build" not in job:
        if expected not in log_path.read_text(encoding="utf-8", errors="replace"):
            code = 125
    return {"status": "pass" if code == 0 else "fail", "code": code,
            "head": head, "seconds": round(time.monotonic() - started, 1),
            "log": str(log_path), "attempt": attempt,
            "log_identity": digest_paths([log_path]),
            "input_signature": input_signature,
            "finished_at": datetime.now(timezone.utc).isoformat()}


def evidence_intact(result: dict) -> bool:
    if not result.get("log_identity") or not result.get("log"):
        return False
    try:
        return digest_paths([Path(result["log"])]) == result["log_identity"]
    except OSError:
        return False


def show_status(jobs: list[dict], results: dict, head: str, signatures: dict[str, str]) -> None:
    counts = {"pass": 0, "carried": 0, "stale": 0, "fail": 0, "pending": 0, "blocked": 0}
    for job in jobs:
        result = results.get(job["id"], {})
        status = result.get("status", "pending")
        if status == "pass":
            if not evidence_intact(result) or result.get("input_signature") != signatures[job["id"]] or (
                    job.get("head_bound") and result.get("head") != head):
                status = "stale"
            elif result.get("head") != head:
                status = "carried"
        counts[status] = counts.get(status, 0) + 1
        print(f"{job['id']:30} {status:8} {result.get('seconds', '')}")
    print(" ".join(f"{key}={value}" for key, value in counts.items()))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("init", "run", "status", "plan"))
    parser.add_argument("--run-dir", type=Path, required=True)
    parser.add_argument("--matrix", type=Path, default=MATRIX)
    parser.add_argument("--platform", choices=("win64", "linux"),
                        default="win64" if os.name == "nt" else "linux")
    parser.add_argument("--mode", choices=tuple(LEVELS), default="full")
    parser.add_argument("--final", action="store_true",
                        help="rerun Light and audit history on one frozen exact HEAD")
    parser.add_argument("--skip-pulse", action="store_true",
                        help="qualify all correctness and delivery jobs without the Pulse comparison")
    parser.add_argument("--jobs", type=int, default=4, help="shared worker slots, including nested runners")
    parser.add_argument("--memory-mb", type=int, default=8192, help="budget for declared concurrent working sets")
    parser.add_argument("--expect-head", help="refuse a different candidate, including between host stages")
    parser.add_argument("--baseline-toolchain", type=Path,
                        help="installed origin baseline for full B/C Pulse")
    parser.add_argument("--baseline-mm-source", type=Path, help="MM source for an older baseline archive")
    parser.add_argument("--pulse-single-cpus", default="",
                        help="physical CPU pairs for single-CPU Pulse cases; pass identically on resume")
    parser.add_argument("--pulse-complete-from", type=Path,
                        help="previous full Pulse output to complete without replacing valid pairs")
    parser.add_argument("--pulse-complete-sha256", default="", help="expected original raw gzip SHA-256")
    parser.add_argument("--pulse-complete-logs-sha256", default="", help="expected original log manifest SHA-256")
    args = parser.parse_args()
    pulse_completion = (str(args.pulse_complete_from.resolve()) if args.pulse_complete_from else "",
                        args.pulse_complete_sha256, args.pulse_complete_logs_sha256)
    if any(pulse_completion) != all(pulse_completion):
        parser.error("Pulse completion requires source path, raw SHA-256, and log-manifest SHA-256 together")
    if any(sha and (len(sha) != 64 or any(character not in "0123456789abcdef" for character in sha))
           for sha in pulse_completion[1:]):
        parser.error("Pulse completion SHA-256 values must be 64 lowercase hex characters")
    if args.jobs < 1 or args.memory_mb < 1:
        parser.error("worker and memory budgets must be positive")
    if args.final and args.mode != "light":
        parser.error("the final replay is Light; use --mode light --final")
    if args.skip_pulse and args.pulse_single_cpus:
        parser.error("--pulse-single-cpus requires Pulse scope")
    if args.skip_pulse and pulse_completion[0]:
        parser.error("Pulse completion requires Pulse scope")
    head = git("rev-parse", "HEAD")
    if args.expect_head and head != args.expect_head:
        parser.error("candidate HEAD differs from --expect-head")
    if args.action in ("init", "run") and git("status", "--porcelain", "--untracked-files=no"):
        parser.error("commit tracked changes before qualifying")
    run_dir = args.run_dir.resolve()
    jobs = load_matrix(args.matrix, args.platform, args.mode, args.final, args.skip_pulse,
                       args.pulse_single_cpus, pulse_completion)
    if any(allocation(job, args.jobs, args.memory_mb) < 1 for job in jobs):
        parser.error("memory budget cannot fit one worker of every selected job")
    if args.action == "plan":
        estimates = sum(estimate(job, args.platform) or 0 for job in jobs)
        unknown = sum(estimate(job, args.platform) is None for job in jobs)
        ceilings = sum(job["timeout"] for job in jobs)
        print(f"MATRIX_PLAN platform={args.platform} mode={args.mode} final={args.final} "
              f"jobs={len(jobs)} sum_known_estimates={estimates}s "
              f"unknown_estimates={unknown} sum_timeout_ceilings={ceilings}s parallel_slots={args.jobs}")
        for job in jobs:
            seconds = estimate(job, args.platform)
            print(f"{job['id']:30} stage={stage(job)} slots={allocation(job, args.jobs, args.memory_mb)} "
                  f"estimate={str(seconds) + 's' if seconds is not None else 'unknown'} "
                  f"limit={job['timeout']}s needs={','.join(parents(job, args.platform))}")
        return 0
    state_path = run_dir / "state.json"
    if args.action == "init":
        run_dir.mkdir(parents=True, exist_ok=False)
        save(state_path, {"created_head": head, "platform": args.platform,
                          "baseline_toolchain": str(args.baseline_toolchain.resolve())
                          if args.baseline_toolchain else "",
                          "baseline_mm_source": str(args.baseline_mm_source.resolve()) if args.baseline_mm_source else "",
                          "results": {}, "final_results": {}, "final_head": None, "skip_pulse": args.skip_pulse,
                          "pulse_single_cpus": args.pulse_single_cpus,
                          "pulse_completion": pulse_completion})
        print(f"MATRIX_READY {run_dir} jobs={len(jobs)} head={head}")
        return 0
    if not state_path.exists():
        if args.action == "status":
            parser.error("run state does not exist")
        run_dir.mkdir(parents=True, exist_ok=True)
        save(state_path, {"created_head": head, "platform": args.platform,
                          "baseline_toolchain": str(args.baseline_toolchain.resolve())
                          if args.baseline_toolchain else "",
                          "baseline_mm_source": str(args.baseline_mm_source.resolve()) if args.baseline_mm_source else "",
                          "results": {}, "final_results": {}, "final_head": None, "skip_pulse": args.skip_pulse,
                          "pulse_single_cpus": args.pulse_single_cpus,
                          "pulse_completion": pulse_completion})
    state = json.loads(state_path.read_text(encoding="utf-8"))
    if state["platform"] != args.platform:
        parser.error("run state belongs to another platform")
    if state.get("skip_pulse", False) != args.skip_pulse:
        parser.error("Pulse scope changed; use a new run directory")
    if state.get("pulse_single_cpus", "") != args.pulse_single_cpus:
        parser.error("Pulse single-CPU selection changed; use a new run directory")
    state["pulse_single_cpus"] = args.pulse_single_cpus
    if tuple(state.get("pulse_completion", ("", "", ""))) != pulse_completion:
        parser.error("Pulse completion source changed; use a new run directory")
    state["pulse_completion"] = pulse_completion
    location = {"host": host_platform.node(), "root": str(ROOT.resolve())}
    if state.get("location", location) != location:
        parser.error("run state belongs to another host or checkout")
    state["location"] = location
    baseline = state.get("baseline_toolchain", "")
    baseline_mm = state.get("baseline_mm_source", "")
    if args.baseline_toolchain:
        supplied = str(args.baseline_toolchain.resolve())
        if baseline and supplied != baseline:
            parser.error("baseline toolchain changed; use a new run directory")
        baseline = supplied
        state["baseline_toolchain"] = baseline
    if args.baseline_mm_source:
        supplied = str(args.baseline_mm_source.resolve())
        if baseline_mm and supplied != baseline_mm:
            parser.error("baseline MM changed; use a new run directory")
        baseline_mm = supplied
    if baseline and not baseline_mm:
        baseline_mm = str(Path(baseline) / "runtime/mm/mormot.core.fpcx64mm.pas")
    state["baseline_mm_source"] = baseline_mm
    if args.action == "run" and args.mode == "full" and not args.skip_pulse and not baseline:
        parser.error("full mode requires --baseline-toolchain for Pulse")
    if baseline and not Path(baseline).is_dir():
        parser.error("baseline toolchain directory does not exist")
    has_build = any(job["id"] == "build" for job in jobs)
    installed = ROOT / "toolchain"
    product = product_identity(ROOT) if has_build and any(path.is_file() for path in installed.rglob("*")) else ""
    baseline_id = digest_paths([Path(baseline), Path(baseline_mm)]) if baseline else ""
    if baseline_id:
        if state.get("baseline_identity", baseline_id) != baseline_id:
            parser.error("baseline bytes changed; use a new run directory")
        state["baseline_identity"] = baseline_id
    signatures = input_signatures(jobs, args.platform, head, product, baseline_id)
    if has_build and product != state.get("product_identity"):
        state["results"].pop("build", None)
        state["final_results"].pop("build", None)
    if args.final:
        discovery = load_matrix(args.matrix, args.platform, "full", skip_pulse=args.skip_pulse,
                                pulse_single_cpus=args.pulse_single_cpus,
                                pulse_completion=pulse_completion)
        discovery_signatures = input_signatures(discovery, args.platform, head, product, baseline_id)
        incomplete = [job["id"] for job in discovery
                      if state["results"].get(job["id"], {}).get("status") != "pass"
                      or not evidence_intact(state["results"][job["id"]])
                      or state["results"][job["id"]].get("input_signature") != discovery_signatures[job["id"]]
                      or (job.get("head_bound") and state["results"][job["id"]].get("head") != head)]
        if args.action == "run" and incomplete:
            parser.error("full discovery is not green for current source inputs: "
                         + ", ".join(incomplete))
        if state["final_head"] not in (None, head):
            parser.error("final HEAD changed; use a new run directory")
        state["final_head"] = head
        results = state["final_results"]
    else:
        results = state["results"]
    if args.action == "status":
        show_status(jobs, results, head, signatures)
        return 0
    phase = "final" if args.final else "discovery"
    (run_dir / phase / "logs").mkdir(parents=True, exist_ok=True)
    save(state_path, state)
    selected = {job["id"]: job for job in jobs}
    for job in jobs:
        job["baseline_mm"] = baseline_mm
        if args.final and job["id"] == "build":
            job["verify_build"] = {"product_identity": product, "source_build": state["results"]["build"]}
    pending = set(selected)
    active: dict = {}
    resources: set[str] = set()
    started: dict[str, float] = {}
    seen: dict[str, int] = {}
    running_attempts: dict[str, int] = {}
    allocations: dict[str, int] = {}
    executed: set[str] = set()
    active_stage = None

    def reject_changed_inputs(message: str) -> int:
        for name in executed:
            results[name].update(status="fail", code=2, reason=message)
        save(state_path, state)
        print(f"QUALIFICATION_INPUTS_CHANGED: {message}", flush=True)
        return 2
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        while pending or active:
            reused = False
            available = args.jobs - sum(allocations.values())
            memory_available = args.memory_mb - sum(selected[name].get("memory_mb_per_slot", 512) * slots
                                                    for name, slots in allocations.items())
            for name in sorted(pending, key=lambda name: (stage(selected[name]), name)):
                if available == 0:
                    break
                job = selected[name]
                dependencies = parents(job, args.platform) + earlier(jobs, job)
                if any(parent in pending or parent in active.values() for parent in dependencies):
                    continue
                if any(results.get(parent, {}).get("status") != "pass" for parent in dependencies):
                    continue
                prior = results.get(name, {})
                if (prior.get("status") == "pass" and not job.get("always_run")
                        and prior.get("input_signature") == signatures[name]
                        and evidence_intact(prior)
                        and (prior.get("head") == head or not args.final and not job.get("head_bound", False))):
                    if prior["head"] != head:
                        print(f"CARRY {name} from {prior['head'][:12]} (discovery only)", flush=True)
                    pending.remove(name)
                    reused = True
                    continue
                if stage(job) != active_stage:
                    if git("rev-parse", "HEAD") != head or git("status", "--porcelain", "--untracked-files=no"):
                        return reject_changed_inputs("source changed before the next stage")
                    active_stage = stage(job)
                resource = job.get("resource", name)
                if resource in resources:
                    continue
                slots = allocation(job, args.jobs, args.memory_mb)
                memory = slots * job.get("memory_mb_per_slot", 512)
                if slots > available or memory > memory_available:
                    continue
                if (job.get("exclusive") and active) or any(
                        selected[running].get("exclusive") for running in active.values()):
                    continue
                attempts = run_dir / phase / "jobs" / name
                attempt = 1 + max((int(path.name.removeprefix("attempt-"))
                                   for path in attempts.glob("attempt-*")), default=0)
                print(f"START {name} attempt={attempt} limit={job['timeout']}s", flush=True)
                future = pool.submit(execute, job, args.platform, head, run_dir,
                                     attempt, phase, baseline, signatures[name], slots)
                active[future] = name
                resources.add(resource)
                started[name] = time.monotonic()
                seen[name] = 0
                running_attempts[name] = attempt
                allocations[name] = slots
                pending.remove(name)
                available -= slots
                memory_available -= memory
                if job.get("exclusive"):
                    break
            if not active:
                if reused and pending:
                    continue
                break
            done, _ = wait(active, timeout=30, return_when=FIRST_COMPLETED)
            if not done:
                for future, name in active.items():
                    elapsed = time.monotonic() - started[name]
                    estimate_seconds = estimate(selected[name], args.platform)
                    print(f"RUNNING {name} elapsed={elapsed:.0f}s "
                          f"estimate={str(estimate_seconds) + 's' if estimate_seconds is not None else 'unknown'}", flush=True)
                    log = run_dir / phase / "logs" / f"{name}-{running_attempts[name]:04d}.log"
                    if log.exists():
                        with log.open(encoding="utf-8", errors="replace") as stream:
                            stream.seek(seen[name])
                            chunk = stream.read()
                            seen[name] = stream.tell()
                        for line in chunk.splitlines():
                            if line.startswith(("DEVIL_PROGRESS", "DEVIL_BUDGET_",
                                                "PULSE_PROGRESS", "PULSE_START",
                                                "PULSE_RESULT", "PULSE_FAIL", "PULSE_REPORT_READY", "PULSE_CONFIRM",
                                                "ARCHIVE_START", "ARCHIVE_PASS",
                                                "ARCHIVE_SMOKE_FAIL")):
                                print(f"  {line}", flush=True)
                continue
            for future in done:
                name = active.pop(future)
                allocations.pop(name)
                resources.remove(selected[name].get("resource", name))
                try:
                    result = future.result()
                except Exception as error:
                    result = {"status": "fail", "code": 126, "head": head,
                              "seconds": round(time.monotonic() - started[name], 1),
                              "error": str(error),
                              "input_signature": signatures[name],
                              "attempt": running_attempts[name]}
                results[name] = result
                executed.add(name)
                if name == "build" and result["status"] == "pass":
                    product = product_identity(ROOT)
                    state["product_identity"] = product
                    signatures = input_signatures(jobs, args.platform, head, product, baseline_id)
                save(state_path, state)
                print(f"{result['status'].upper()} {name} {result['seconds']}s "
                      f"exit={result['code']} {result.get('log', result.get('error', ''))}",
                      flush=True)
    for name in sorted(pending):
        if name not in results or results[name].get("status") != "pass":
            results[name] = {"status": "blocked", "head": head,
                             "reason": "dependency failed or not run"}
    save(state_path, state)
    if git("rev-parse", "HEAD") != head or git("status", "--porcelain", "--untracked-files=no"):
        return reject_changed_inputs("source changed during the run")
    if has_build and state.get("product_identity") and product_identity(ROOT) != state["product_identity"]:
        return reject_changed_inputs("installed toolchain changed during tests")
    if baseline_id and digest_paths([Path(baseline), Path(baseline_mm)]) != baseline_id:
        return reject_changed_inputs("baseline changed during the run")
    if args.final:
        final_signatures = input_signatures(discovery, args.platform, head, product, baseline_id)
        if any(state["results"].get(job["id"], {}).get("input_signature") != final_signatures[job["id"]]
               for job in discovery):
            return reject_changed_inputs("final product differs from the full discovery inputs")
        if any(not evidence_intact(state["results"][job["id"]]) for job in discovery):
            return reject_changed_inputs("full discovery log changed during final replay")
    show_status(jobs, results, head, signatures)
    passed = all(results.get(job["id"], {}).get("status") == "pass"
                 and evidence_intact(results[job["id"]])
                 and results[job["id"]].get("input_signature") == signatures[job["id"]]
                 and (not args.final or results[job["id"]]["head"] == head)
                 for job in jobs)
    if passed:
        carried = any(results[job["id"]]["head"] != head for job in jobs)
        verdict = ("FINAL_EXACT_HEAD_PASS" if args.final else
                   "DISCOVERY_PROVISIONAL" if carried else "DISCOVERY_PASS")
        print(verdict
              + f" {head} platform={args.platform} mode={args.mode}"
              + (" scope=correctness-without-pulse" if args.skip_pulse else " scope=full"))
    else:
        print(f"QUALIFICATION_FINDINGS {head} platform={args.platform} mode={args.mode}")
    return 0 if passed else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"qualification control: {error}", file=sys.stderr)
        raise SystemExit(2)
