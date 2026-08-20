#!/usr/bin/env python3
"""Devil mutation stand: measure whether Devil actually kills real defects.

A test suite that never fails proves nothing.  This stand takes the semantic
repair commits of this very repository, reverts one of them at a time, rebuilds
the compiler with the defect back in place, and runs Devil against it.

A mutant that Devil does not kill is a hole in coverage, named and printed.
That number - killed / total - is the honest measure of the complex.

Usage:
    run_devil_mutation.py --list
    run_devil_mutation.py --mutants 3 --seeds 1,2,3 --cases 150
"""

from __future__ import annotations

import argparse
import json
import re
import os
import subprocess
import sys
import time
from pathlib import Path

SCRIPT_ROOT = Path(__file__).resolve().parents[3]   # tree these scripts live in
ROOT = SCRIPT_ROOT                                  # tree that gets mutated
SUITE = SCRIPT_ROOT / "qualification" / "suite"
GATE = SUITE / "scripts" / "run_devil_gate.py"
REJECT_GATE = SUITE / "scripts" / "run_devil_reject_gate.py"

# Semantic repairs of this repository, newest first.  Each one is a defect we
# already fixed; reverting it puts a known bug back into the compiler.
MUTANTS = [
    ("154129a3", "Isolate expression context in nested routine bodies"),
    ("50dd8feb", "Materialize non-encodable x86-64 modulus masks"),
    ("a4c9cf5e", "Match Delphi contextual UInt64 overload selection"),
    ("9e23ecd3", "Preserve complex Delphi with lvalue captures"),
    ("d158f58b", "Preserve source context during generic PPU replay"),
    ("df20d54f", "Keep RawByteString operations byte-preserving"),
    ("5ce876ee", "Preserve full precision in Win64 Currency multiplication"),
    ("9b5079f8", "Preserve runtime loop bounds through x86 peephole passes"),
    ("e8a9dea8", "Keep Win64 SEH loops safe and eligible for unrolling"),
    ("d60056a7", "Match Delphi mixed UInt64 integer semantics"),
    ("e11a5c3c", "Preserve Delphi unsigned narrow multiplication widening"),
    ("c1c34432", "Preserve function-reference load semantics during inlining"),
    ("5011a80c", "Normalize ByteBool or expressions in Delphi mode"),
    ("8f717edd", "Preserve overflow checks when lowering Inc and Dec"),
    ("b9eca32b", "Preserve required MOVSXD after x86 arithmetic"),
    ("fe7e94d0", "Match Delphi integer expression semantics"),
    ("416cdbdf", "Match Delphi Hi and Lo byte semantics"),
    ("aca435b0", "Match Delphi set storage and field alignment"),
    ("f61f1e48", "Keep inclusive floating selections branch-exact"),
    ("c4143c7f", "Match Delphi Val integer dialect and error results"),
]


def run(cmd: list[str], cwd: Path, timeout: int) -> tuple[int, str]:
    env = dict(os.environ, DEVIL_TOOLCHAIN_ROOT=str(ROOT))
    try:
        proc = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True,
                              timeout=timeout, env=env)
    except subprocess.TimeoutExpired:
        return 124, "<timeout>"
    return proc.returncode, (proc.stdout or "") + (proc.stderr or "")


def git(args: list[str], timeout: int = 300) -> tuple[int, str]:
    return run(["git"] + args, ROOT, timeout)


def rebuild(build_timeout: int) -> tuple[bool, str]:
    code, log = run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass",
                     "-File", str(ROOT / "build.ps1"), "compiler"],
                    ROOT, build_timeout)
    return code == 0, log[-2000:]


FINDING_RE = re.compile(r'"check": "([a-z0-9-]+)"|"note": "([a-z0-9-]+)"')


def devil_findings(seeds: str, cases: int, timeout: int) -> set[str]:
    """Names of everything the gate reports as NEW for the installed compiler."""
    code, log = run([sys.executable, str(GATE),
                     "--seeds", seeds, "--cases", str(cases)],
                    ROOT, timeout)
    names: set[str] = set()
    for line in log.splitlines():
        stripped = line.strip()
        if not stripped.startswith("NEW"):
            continue
        for check, note in FINDING_RE.findall(stripped):
            names.add(check or note)
        if "internal-error" in stripped or "compile-failed" in stripped:
            names.add("build:" + stripped[:70])
    return names


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--repo", type=Path,
                   help="tree to mutate; defaults to the tree of these scripts."
                        " Point it at a worktree to leave the working copy alone")
    p.add_argument("--seeds", default="1,2,3")
    p.add_argument("--cases", type=int, default=150)
    p.add_argument("--mutants", type=int, default=len(MUTANTS))
    p.add_argument("--from-index", type=int, default=0)
    p.add_argument("--build-timeout", type=int, default=3600)
    p.add_argument("--gate-timeout", type=int, default=1800)
    p.add_argument("--report", type=Path)
    p.add_argument("--list", action="store_true")
    p.add_argument("--only", default="", help="comma separated commit shas")
    args = p.parse_args()

    if args.repo:
        global ROOT
        ROOT = args.repo.resolve()
        if not (ROOT / "build.ps1").is_file():
            raise SystemExit(f"not a compiler tree: {ROOT}")

    if args.list:
        for i, (sha, subject) in enumerate(MUTANTS):
            print(f"{i:3d}  {sha}  {subject}")
        return

    # untracked Devil files are fine; only modified tracked files would be
    # swallowed by the revert/restore cycle
    code, status = git(["status", "--porcelain", "--untracked-files=no"])
    if status.strip():
        print("working tree is dirty; mutation reverts and hard-resets the tree,"
              " which would destroy uncommitted work")
        print(status)
        sys.exit(2)

    # findings the clean compiler already produces are noise for every mutant:
    # only what a mutant adds on top of them says Devil saw the defect
    print("measuring the clean baseline")
    baseline = devil_findings(args.seeds, args.cases, args.gate_timeout)
    print(f"baseline: {len(baseline)} findings")

    results = []
    if args.only:
        wanted = [x.strip() for x in args.only.split(",") if x.strip()]
        selected = [m for m in MUTANTS if m[0] in wanted]
    else:
        selected = MUTANTS[args.from_index:args.from_index + args.mutants]
    for sha, subject in selected:
        started = time.time()
        row = {"sha": sha, "subject": subject}
        code, log = git(["revert", "--no-edit", "--no-commit", sha])
        if code != 0:
            # an old repair may conflict with later ones; that is a limit of the
            # stand, not a verdict about Devil
            row.update({"outcome": "skipped-conflict", "detail": log[-200:]})
            git(["revert", "--abort"])
            git(["reset", "--hard", "HEAD"])
            results.append(row)
            print(json.dumps(row, ensure_ascii=False))
            continue

        built, build_log = rebuild(args.build_timeout)
        if not built:
            # a compiler that no longer builds is also a killed mutant: the
            # defect is detectable, just at build time
            row.update({"outcome": "killed-by-build", "detail": build_log[-300:]})
        else:
            found = devil_findings(args.seeds, args.cases, args.gate_timeout)
            fresh = sorted(found - baseline)
            row.update({"outcome": "killed" if fresh else "survived",
                        "new_findings": fresh[:8],
                        "new_count": len(fresh)})
        row["seconds"] = round(time.time() - started, 1)
        results.append(row)
        print(json.dumps(row, ensure_ascii=False))

        # a revert can delete files, so only a hard reset restores the tree;
        # untracked Devil files are left alone by it
        git(["reset", "--hard", "HEAD"])
        git(["clean", "-fdq", "compiler", "rtl", "packages"])
        # the toolchain still holds the mutant binary at this point; rebuilding
        # from the restored tree is part of restoring, not an optional step
        rebuild(args.build_timeout)

    usable = [r for r in results if r["outcome"] != "skipped-conflict"]
    killed = sum(1 for r in usable if r["outcome"].startswith("killed"))
    print(f"DEVIL_MUTATION killed={killed}/{len(usable)} "
          f"skipped={len(results) - len(usable)}")
    if args.report:
        args.report.write_text(json.dumps(results, indent=2, ensure_ascii=False)
                               + "\n", encoding="utf-8")
    # a surviving mutant is a coverage hole, and that is a failure of Devil
    sys.exit(0 if killed == len(usable) else 1)


if __name__ == "__main__":
    main()
