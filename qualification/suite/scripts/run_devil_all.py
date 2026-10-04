#!/usr/bin/env python3
"""Run every Devil gate in one go and report a single verdict.

Order matters: the cheap gates run first so an obvious break is reported in
seconds, and the expensive sweep runs last.

    run_devil_all.py [--dcc ... --dcc-lib ...] [--seeds 1,2,3] [--cases 200]
                     [--with-mutation]
"""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import hashlib
import json
import os
import queue
import re
import signal
import subprocess
import sys
import threading
import time
from pathlib import Path

import devil_toolchain as tc
from run_devil_gate import checkpoint_key, write_json

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"


def run(cmd: list[str], timeout: int, name: str) -> tuple[int, str, float]:
    started = time.monotonic()
    env = os.environ.copy()
    env["PYTHONUNBUFFERED"] = "1"
    # a stage prints UTF-8 and is read as UTF-8, whatever the caller's environment
    env["PYTHONIOENCODING"] = "utf-8"
    flags = subprocess.CREATE_NEW_PROCESS_GROUP if os.name == "nt" else 0
    process = subprocess.Popen(cmd, cwd=ROOT.parent.parent, stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT, encoding="utf-8", errors="replace",
                               env=env, creationflags=flags,
                               start_new_session=os.name != "nt")
    lines: queue.Queue[str | None] = queue.Queue()

    def collect() -> None:
        assert process.stdout is not None
        for line in process.stdout:
            lines.put(line)
        lines.put(None)

    threading.Thread(target=collect, daemon=True).start()
    output: list[str] = []
    timed_out = False

    def stop() -> None:
        if os.name == "nt":
            subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"], capture_output=True)
        else:
            os.killpg(process.pid, signal.SIGKILL)

    while True:
        elapsed = time.monotonic() - started
        if elapsed >= timeout and process.poll() is None and not timed_out:
            stop()
            timed_out = True
        try:
            wait = min(30, max(0.1, timeout - elapsed)) if process.poll() is None and not timed_out else 1
            line = lines.get(timeout=wait)
        except queue.Empty:
            print(f"=== {name}: running {time.monotonic() - started:.0f}s "
                  f"of {timeout}s", flush=True)
            continue
        if line is None:
            # EOF closes the log, not necessarily the process. Keep the same
            # deadline while it finishes without stdout/stderr.
            try:
                process.wait(timeout=max(0, timeout - (time.monotonic() - started)))
            except subprocess.TimeoutExpired:
                stop()
                timed_out = True
            break
        output.append(line)
        if line.startswith(("seed ", "DEVIL_PROGRESS", "DEVIL_BUDGET_",
                            "DEVIL_GATE", "  NEW")):
            print(f"   {line.rstrip()}", flush=True)
    code = process.wait()
    if process.stdout is not None:
        process.stdout.close()
    if timed_out:
        output.append("\n<TIMEOUT>\n")
    return (124 if timed_out else code), "".join(output), time.monotonic() - started


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def git_output(*args: str) -> str:
    proc = subprocess.run(["git", *args], cwd=tc.ROOT, capture_output=True,
                          text=True, timeout=30)
    return proc.stdout.strip() if proc.returncode == 0 else "<unavailable>"


def run_stages(stages: list[tuple[str, list[str]]], args, run_root: Path) -> list[dict]:
    key = checkpoint_key(args) if args.resume else ""

    def execute_stage(item):
        name, command = item
        command = list(command)
        timeout = args.main_timeout if name == "main" else args.timeout
        if name == "main":
            command += ["--wall-budget", str(timeout), "--jobs", str(args.jobs)]
            if args.resume:
                command.append("--resume")
        signature = hashlib.sha256((key + json.dumps(command)).encode()).hexdigest()
        checkpoint = run_root / f"{name}.checkpoint.json"
        log_path = run_root / f"{name}.log"
        if args.resume and name != "mutation" and checkpoint.exists() and log_path.exists():
            saved = json.loads(checkpoint.read_text(encoding="utf-8"))
            if saved["signature"] == signature and saved["code"] == 0 and saved["log_sha256"] == sha256(log_path):
                print(f"DEVIL_RESUME stage={name}", flush=True)
                return saved
        print(f"=== {name}: start, limit {timeout}s", flush=True)
        code, log, seconds = run(command, timeout, name)
        log_path.write_text(log, encoding="utf-8")
        verdict = [line for line in log.splitlines() if line.startswith((
            "DEVIL_", "RESIDENT_", "CHIMERA_", "PLANT_", "ASM_ORACLE_", "  NEW", "  known"))][-8:]
        result = {"stage": name, "command": command, "code": code, "timeout_seconds": timeout,
                  "seconds": round(seconds, 1), "tail": verdict, "signature": signature,
                  "log_sha256": sha256(log_path)}
        write_json(checkpoint, result)
        print(f"=== {name}: exit {code} in {seconds:.0f}s", flush=True)
        return result

    results = []
    # Gates have separate work directories. The main stage gets all reserved
    # slots for its seed/profile workers; it never nests another full-size pool.
    groups = ([item for item in stages if item[0] in {"registry", "finalization", "codegen", "reject"}],
              [item for item in stages if item[0] not in {"registry", "finalization", "codegen", "reject", "main", "mutation"}],
              [item for item in stages if item[0] == "main"],
              [item for item in stages if item[0] == "mutation"])
    for group in groups:
        with ThreadPoolExecutor(max_workers=args.jobs) as pool:
            futures = [pool.submit(execute_stage, item) for item in group]
            results.extend(future.result() for future in as_completed(futures))
        if any(row["code"] for row in results) and not args.keep_going:
            break
    order = {name: index for index, (name, _) in enumerate(stages)}
    return sorted(results, key=lambda row: order[row["stage"]])


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--dcc", type=Path)
    p.add_argument("--dcc-lib", type=Path)
    p.add_argument("--seeds", default="1,2,3")
    p.add_argument("--cases", type=int, default=200)
    p.add_argument("--stress-cases", type=int, default=30)
    p.add_argument("--with-switches", action="store_true",
                   help="прогнать резидент по каждой оптимизации отдельно "
                        "(38 сборок, около восьми минут)")
    p.add_argument("--with-mutation", action="store_true")
    p.add_argument("--mutation-repo", type=Path)
    p.add_argument("--timeout", type=int, default=7200)
    p.add_argument(
        "--main-timeout", type=int, default=14400,
        help="wall-clock bound for the aggregate multi-seed main stage",
    )
    p.add_argument(
        "--program-timeout", type=int, default=300,
        help="runtime bound for each full generated Devil executable",
    )
    p.add_argument("--run-id")
    p.add_argument("--work", type=Path, help="persistent stage/seed evidence directory")
    p.add_argument("--jobs", type=int, default=1)
    p.add_argument("--resume", action="store_true")
    p.add_argument("--report", type=Path)
    p.add_argument("--keep-going", action="store_true",
                   help="run later stages after a failed stage")
    args = p.parse_args()
    if args.jobs < 1 or args.resume and args.work is None:
        p.error("positive --jobs and an explicit --work for --resume are required")

    if bool(args.dcc) != bool(args.dcc_lib):
        p.error("--dcc and --dcc-lib must be supplied together")
    if args.with_mutation and not args.mutation_repo:
        p.error("--with-mutation requires an explicitly disposable --mutation-repo")
    if args.cases <= 0 or args.stress_cases <= 0:
        p.error("case counts must be positive")
    if args.timeout <= 0 or args.main_timeout <= 0 or args.program_timeout <= 0:
        p.error("timeouts must be positive")
    try:
        seeds = [int(value.strip()) for value in args.seeds.split(",")
                 if value.strip()]
    except ValueError:
        p.error("--seeds must be a comma-separated list of integers")
    if not seeds or len(seeds) != len(set(seeds)):
        p.error("--seeds must be non-empty and unique")
    tc.preflight()
    if args.dcc:
        args.dcc = args.dcc.resolve()
        args.dcc_lib = args.dcc_lib.resolve()
    if args.report:
        args.report = args.report.resolve()
    run_id = args.run_id or (
        "devil-all-" + time.strftime("%Y%m%d-%H%M%S")
        + "-%07x" % (time.time_ns() & 0x0FFFFFFF)
    )
    if not re.fullmatch(r"[A-Za-z0-9._-]+", run_id):
        p.error("run-id may contain only letters, digits, dot, underscore and dash")
    run_root = args.work.resolve() if args.work else ROOT / "results" / "runs" / run_id
    try:
        run_root.mkdir(parents=True, exist_ok=args.resume)
    except FileExistsError:
        p.error(f"run already exists: {run_root}")

    delphi = []
    if args.dcc and args.dcc_lib:
        delphi = ["--dcc", str(args.dcc), "--dcc-lib", str(args.dcc_lib)]

    stages = [
        # A finding must be registered consistently in all reader-facing
        # Devil indexes before the more expensive gates start.
        ("registry", [sys.executable, str(SCRIPTS / "check_devil_registry.py")]),
        # A PASS is valid only after every unit finalized normally.  Exercise
        # the process-exit channel before trusting any generated result.
        ("finalization", [sys.executable,
                          str(SCRIPTS / "run_devil_finalization_gate.py")]
         + delphi + ["--work", str(run_root / "finalization"),
                     "--report", str(run_root / "finalization.json")]),
        ("codegen", [sys.executable, str(SCRIPTS / "run_devil_codegen_gate.py"),
                     "--work", str(run_root / "codegen"),
                     "--report", str(run_root / "codegen.json")]),
        ("reject", [sys.executable, str(SCRIPTS / "run_devil_reject_gate.py")]
         + delphi + ["--work", str(run_root / "reject"),
                              "--report", str(run_root / "reject.json")]),
        # ловушка на весь класс dvl-0041: код не должен зависеть ни от чего,
        # кроме исходника
        ("env", [sys.executable, str(SCRIPTS / "run_devil_env_gate.py")]
         + ["--work", str(run_root / "env"),
                     "--report", str(run_root / "env.json")]),
        # ключи сборки не имеют права менять поведение программы
        ("modes", [sys.executable, str(SCRIPTS / "run_devil_modes_gate.py")]
         + ["--work", str(run_root / "modes"),
                     "--report", str(run_root / "modes.json")]),
        ("resident", [sys.executable,
                      str(SCRIPTS / "run_devil_resident_gate.py"),
                      "--work", str(run_root / "resident"),
                      "--report", str(run_root / "resident.json")]),
        # Pascal bodies are checked against independent handwritten x86-64
        # implementations.  This is a codegen/ABI oracle, not a claim that
        # these synthetic Pascal bodies are the product mORMot path.
        ("asm-oracle", [sys.executable,
                        str(SCRIPTS / "run_asm_oracle_gate.py"),
                        "--work", str(run_root / "asm-oracle"),
                        "--report", str(run_root / "asm-oracle.json")]),
        # Устройство программы, а не её счёт: обёртка над чужой библиотекой,
        # менеджер с породами, сервисы на интерфейсах, циклы заголовков — и
        # всё это в матрице ключей и порядков инициализации.
        ("plant", [sys.executable, str(SCRIPTS / "run_plant_gate.py"),
                   "--work", str(run_root / "plant"),
                   "--report", str(run_root / "plant.json")]),
        # Кодоформы Арбитража и MoonBot: каждая работа несколькими телами
        # сразу, плюс сверка карты вставок — не исчезла ли ось, которую тест
        # собирался проверять.
        ("chimera", [sys.executable, str(SCRIPTS / "run_chimera_gate.py"),
                     "--work", str(run_root / "chimera"),
                     "--report", str(run_root / "chimera.json")]),
        # Топология графа юнитов × вид символа × способ переноса тела.
        ("topology", [sys.executable, str(SCRIPTS / "run_topology_gate.py"),
                      "--work", str(run_root / "topology"),
                      "--report", str(run_root / "topology.json")]),
        ("stress", [sys.executable, str(SCRIPTS / "run_devil_stress_gate.py")]
         + ["--cases", str(args.stress_cases),
                     "--work", str(run_root / "stress"),
                     "--report", str(run_root / "stress.json")]),
        ("main", [sys.executable, str(SCRIPTS / "run_devil_gate.py")]
         + delphi + ["--seeds", args.seeds, "--cases", str(args.cases),
                              "--program-timeout", str(args.program_timeout),
                              "--ppu-reuse", "--work", str(run_root / "main"),
                              "--report", str(run_root / "main.json")]),
    ]
    if args.with_switches:
        # Каждая оптимизация по отдельности на всём кольце резидента: тридцать
        # восемь сборок, поэтому не в основном наборе.
        stages.append(("switches",
                       [sys.executable, str(SCRIPTS / "run_resident_switch_matrix.py"),
                        "--work", str(run_root / "switches"),
                        "--report", str(run_root / "switches.json")]))
    if args.with_mutation:
        stages.append(("mutation",
                       [sys.executable, str(SCRIPTS / "run_devil_mutation.py"),
                        "--repo", str(args.mutation_repo.resolve()),
                        "--seeds", args.seeds, "--cases", "60",
                        "--report", str(run_root / "mutation.json")]))

    results = run_stages(stages, args, run_root)
    failed = [row["stage"] for row in results if row["code"]]

    report_path = args.report or run_root / "report.json"
    report_path.parent.mkdir(parents=True, exist_ok=True)
    compiler, config, target, _ = tc.toolchain()
    provenance = {
        "repo_head": git_output("rev-parse", "HEAD"),
        "tracked_clean": git_output("status", "--porcelain",
                                    "--untracked-files=no") == "",
        "compiler": str(compiler),
        "compiler_sha256": sha256(compiler),
        "config": str(config),
        "config_sha256": sha256(config),
        "mm_source": str(tc.MM_SOURCE),
        "mm_sha256": sha256(tc.MM_SOURCE),
        "target_options": target,
    }
    report_path.write_text(json.dumps({"run_id": run_id,
                                       "provenance": provenance,
                                       "planned_stages": [name for name, _ in stages],
                                       "not_run": [name for name, _ in stages
                                                   if name not in {row["stage"]
                                                                   for row in results}],
                                       "stages": results},
                                      indent=2, ensure_ascii=False)
                           + "\n", encoding="utf-8")
    print(f"DEVIL_ALL {'OK' if not failed else 'FINDINGS in ' + ','.join(failed)}")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
