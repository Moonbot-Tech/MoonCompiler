#!/usr/bin/env python3
"""Mutation proof that the F2 gate kills removed LICM safety laws."""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
MODEL = ROOT / "compiler/opteffect.pas"
LOOP = ROOT / "compiler/optloop.pas"
GATE = HERE / "run_f2_gate.py"

SABOTAGES = (
    (
        "conflict_bypass",
        MODEL,
        "          if effects_conflict(ce,loopeffect) then\n"
        "            exit;\n",
        "          { SABOTAGE: loop writes do not invalidate candidates }\n",
    ),
    (
        "trap_bypass",
        MODEL,
        "          if ce.hastemps or ce.runbounded or ce.wunbounded or\n"
        "             (ce.ieffects<>[]) or (ce.wclasses<>[]) or\n",
        "          if ce.hastemps or ce.runbounded or ce.wunbounded or\n"
        "             ((ce.ieffects-[ie_trap])<>[]) or (ce.wclasses<>[]) or\n",
    ),
    (
        "latch_omitted",
        LOOP,
        "          tree_effect(n,plan.loopeffect);\n",
        "          { SABOTAGE: model only condition/body, omits lowered latch }\n"
        "          if assigned(tloopnode(n).left) then\n"
        "            tree_effect(tloopnode(n).left,plan.loopeffect);\n"
        "          if assigned(tloopnode(n).right) then\n"
        "            tree_effect(tloopnode(n).right,plan.loopeffect);\n",
    ),
)


def find_tool(explicit: str | None, name: str) -> str:
    if explicit:
        return explicit
    if name == "fpc.exe":
        env = os.environ.get("MOONBOT_BOOTSTRAP_FPC")
        if env:
            return env
        bundled = (ROOT.parent / "FPC/tools/fpc-3.2.2-win64/install/bin/"
                   "i386-Win32/fpc.exe")
        if bundled.is_file():
            return str(bundled)
    if name == "make.exe":
        bundled = (ROOT.parent / "FPC/tools/fpc-3.2.2-win64/install/bin/"
                   "i386-Win32/make.exe")
        if bundled.is_file():
            return str(bundled)
    found = shutil.which(name)
    if found:
        return found
    raise SystemExit(f"{name} not found; pass an explicit tool path")


def rebuild(fpc: str, make: str) -> bool:
    for stamp in ROOT.glob("*build-stamp*"):
        stamp.unlink()
    env = dict(os.environ)
    env["PATH"] = str(Path(fpc).parent) + os.pathsep + env["PATH"]
    proc = subprocess.run(
        [make, "-C", str(ROOT), "-j1", "all", f"FPC={fpc}",
         "OPT=-O2 -dMOONCOMPILER_PRODUCT_RUNTIME "
         "-dMOONCOMPILER_VANILLA_RUNTIME",
         "CPU_TARGET=x86_64", "OS_TARGET=win64"],
        capture_output=True, text=True, timeout=3600, env=env)
    if proc.returncode != 0:
        print(proc.stdout[-4000:])
        print(proc.stderr[-4000:], file=sys.stderr)
    return proc.returncode == 0


def run_gate() -> int:
    proc = subprocess.run(
        [sys.executable, str(GATE),
         "--compiler", str(ROOT / "compiler/ppcx64.exe"),
         "--rtl", str(ROOT / "rtl/units/x86_64-win64")],
        capture_output=True, text=True, timeout=1200)
    print(proc.stdout, end="")
    return proc.returncode


def restore(path: Path) -> None:
    subprocess.run(["git", "checkout", "--", str(path)], cwd=ROOT, check=True)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--fpc")
    ap.add_argument("--make")
    ap.add_argument("--only")
    args = ap.parse_args()
    fpc = find_tool(args.fpc, "fpc.exe")
    make = find_tool(args.make, "make.exe")
    touched = {item[1] for item in SABOTAGES}
    dirty = subprocess.run(
        ["git", "status", "--short", "--", *map(str, touched)], cwd=ROOT,
        capture_output=True, text=True, check=True)
    if dirty.stdout.strip():
        raise SystemExit("F2 compiler sources have local changes; commit first")

    results: list[tuple[str, bool]] = []
    try:
        for name, path, anchor, replacement in SABOTAGES:
            if args.only and args.only != name:
                continue
            source = path.read_text(encoding="utf-8")
            if source.count(anchor) != 1:
                raise SystemExit(
                    f"{name}: anchor found {source.count(anchor)} times")
            print(f"--- sabotage {name}", flush=True)
            path.write_text(source.replace(anchor, replacement, 1),
                            encoding="utf-8", newline="")
            if not rebuild(fpc, make):
                restore(path)
                raise SystemExit(f"{name}: mutant did not build")
            killed = run_gate() != 0
            results.append((name, killed))
            print("    " + ("KILLED" if killed else "SURVIVED"), flush=True)
            restore(path)
    finally:
        for path in touched:
            restore(path)
        print("--- restoring pristine compiler", flush=True)
        if not rebuild(fpc, make):
            print("WARNING: pristine rebuild failed", file=sys.stderr)

    survived = [name for name, killed in results if not killed]
    for name, killed in results:
        print(f"  {name:18} {'killed' if killed else 'SURVIVED'}")
    if survived or not results:
        print(f"F2 SABOTAGE: FAIL ({len(survived)} survivors)")
        return 1
    print(f"F2 SABOTAGE: PASS ({len(results)}/{len(results)} killed)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
