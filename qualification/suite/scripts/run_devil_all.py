#!/usr/bin/env python3
"""Run every Devil gate in one go and report a single verdict.

Order matters: the cheap gates run first so an obvious break is reported in
seconds, and the expensive sweep runs last.

    run_devil_all.py [--dcc ... --dcc-lib ...] [--seeds 1,2,3] [--cases 200]
                     [--with-mutation]
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
import time
from pathlib import Path

import devil_toolchain as tc

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"


def run(cmd: list[str], timeout: int) -> tuple[int, str, float]:
    started = time.time()
    try:
        p = subprocess.run(cmd, cwd=ROOT.parent.parent, capture_output=True,
                           text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return 124, "<timeout>", time.time() - started
    return p.returncode, (p.stdout or "") + (p.stderr or ""), time.time() - started


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


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--dcc", type=Path)
    p.add_argument("--dcc-lib", type=Path)
    p.add_argument("--seeds", default="1,2,3")
    p.add_argument("--cases", type=int, default=200)
    p.add_argument("--stress-cases", type=int, default=30)
    p.add_argument("--with-mutation", action="store_true")
    p.add_argument("--mutation-repo", type=Path)
    p.add_argument("--timeout", type=int, default=7200)
    p.add_argument("--run-id")
    p.add_argument("--report", type=Path)
    args = p.parse_args()

    tc.preflight()
    if bool(args.dcc) != bool(args.dcc_lib):
        p.error("--dcc and --dcc-lib must be supplied together")
    if args.with_mutation and not args.mutation_repo:
        p.error("--with-mutation requires an explicitly disposable --mutation-repo")
    run_id = args.run_id or (
        "devil-all-" + time.strftime("%Y%m%d-%H%M%S")
        + "-%07x" % (time.time_ns() & 0x0FFFFFFF)
    )
    if not re.fullmatch(r"[A-Za-z0-9._-]+", run_id):
        p.error("run-id may contain only letters, digits, dot, underscore and dash")
    run_root = ROOT / "results" / "runs" / run_id
    try:
        run_root.mkdir(parents=True)
    except FileExistsError:
        p.error(f"run already exists: {run_root}")

    common: list[str] = []
    delphi = []
    if args.dcc and args.dcc_lib:
        delphi = ["--dcc", str(args.dcc), "--dcc-lib", str(args.dcc_lib)]

    stages = [
        ("codegen", [sys.executable, str(SCRIPTS / "run_devil_codegen_gate.py"),
                     "--work", str(run_root / "codegen"),
                     "--report", str(run_root / "codegen.json")] + common),
        ("reject", [sys.executable, str(SCRIPTS / "run_devil_reject_gate.py")]
         + common + delphi + ["--work", str(run_root / "reject"),
                              "--report", str(run_root / "reject.json")]),
        # ловушка на весь класс dvl-0041: код не должен зависеть ни от чего,
        # кроме исходника
        ("env", [sys.executable, str(SCRIPTS / "run_devil_env_gate.py")]
         + common + ["--work", str(run_root / "env"),
                     "--report", str(run_root / "env.json")]),
        ("stress", [sys.executable, str(SCRIPTS / "run_devil_stress_gate.py")]
         + common + ["--cases", str(args.stress_cases),
                     "--work", str(run_root / "stress"),
                     "--report", str(run_root / "stress.json")]),
        ("main", [sys.executable, str(SCRIPTS / "run_devil_gate.py")]
         + common + delphi + ["--seeds", args.seeds, "--cases", str(args.cases),
                              "--ppu-reuse", "--work", str(run_root / "main"),
                              "--report", str(run_root / "main.json")]),
    ]
    if args.with_mutation:
        stages.append(("mutation",
                       [sys.executable, str(SCRIPTS / "run_devil_mutation.py"),
                        "--repo", str(args.mutation_repo.resolve()),
                        "--seeds", args.seeds, "--cases", "60",
                        "--report", str(run_root / "mutation.json")]))

    results = []
    failed = []
    for name, cmd in stages:
        code, log, seconds = run(cmd, args.timeout)
        verdict = [l for l in log.splitlines()
                   if l.startswith(("DEVIL_", "  NEW", "  known"))][-8:]
        results.append({"stage": name, "code": code,
                        "seconds": round(seconds, 1), "tail": verdict})
        print(f"=== {name}: exit {code} in {seconds:.0f}s")
        for line in verdict:
            print("   " + line)
        if code != 0:
            failed.append(name)

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
                                       "stages": results},
                                      indent=2, ensure_ascii=False)
                           + "\n", encoding="utf-8")
    print(f"DEVIL_ALL {'OK' if not failed else 'FINDINGS in ' + ','.join(failed)}")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
