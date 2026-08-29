#!/usr/bin/env python3
"""Sabotage (mutation) gate of the effect-model tests (phase F1).

A test suite that never fails proves nothing.  This stand plants one named
defect at a time into the model source (compiler/opteffect.pas), rebuilds
the compiler, and runs the classification gate.  Every sabotage MUST be
killed (the gate must fail); a surviving sabotage is a hole in the corpus
and fails this stand.  The working tree is restored from git after every
mutant; sabotages are never committed.

Sabotages (one per closure guarantee).  A sabotage removes a LAW of the
model, not one source line: every anchor of that law is patched in one
mutant (the front end canonicalizes some tree forms away, so a law can have
both live and currently-unreachable carriers - the corpus kills the mutant
through the live ones):

  unknown_node_pure   an unknown node/intrinsic is classified pure
                      (walker default + intrinsic default)
  call_not_barrier    an opaque call loses its synchronization barrier
  ptr_write_narrow    a pointer write stops invalidating unknown memory
  managed_narrow      a managed operation gets a narrow effect
                      (managed assignment + string COW element store)
  addsym_noop         exact-local identity silently stops being collected
  conflict_false      effects_conflict answers "no conflict" for everything

Usage:
    run_effect_sabotage.py [--fpc PATH] [--make PATH] [--only NAME]
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
MODEL = ROOT / "compiler" / "opteffect.pas"
GATE = HERE / "run_effect_gate.py"

SABOTAGES = [
    (
        "unknown_node_pure",
        "an unknown node/intrinsic is classified pure",
        [
            (
                b"{ conservative closure: any node the model does not know reads\r\n"
                b"                and writes everything and carries every instruction effect }\r\n"
                b"              add_everything(ctx^);\r\n",
                b"{ SABOTAGE: unknown nodes silently classified pure }\r\n",
            ),
            (
                b"{ unknown intrinsic: conservative closure }\r\n"
                b"              add_everything(ctx);\r\n",
                b"{ SABOTAGE: unknown intrinsics silently classified pure }\r\n",
            ),
        ],
    ),
    (
        "call_not_barrier",
        "an opaque call loses its synchronization barrier",
        [
            (
                b"{ a call without a proven transitive summary is a full barrier: may\r\n"
                b"          read and write everything reachable, synchronize and throw }\r\n"
                b"        add_wide(ctx,true,true);\r\n"
                b"        ctx.e^.ieffects:=ctx.e^.ieffects+[ie_sync,ie_trap];\r\n",
                b"{ SABOTAGE: calls are no barrier }\r\n"
                b"        add_wide(ctx,true,true);\r\n"
                b"        ctx.e^.ieffects:=ctx.e^.ieffects+[ie_trap];\r\n",
            ),
        ],
    ),
    (
        "ptr_write_narrow",
        "a pointer write stops invalidating unknown memory",
        [
            (
                b"          derefn:\r\n"
                b"            begin\r\n"
                b"              add_wide(ctx,false,true);\r\n",
                b"          derefn:\r\n"
                b"            begin\r\n"
                b"              { SABOTAGE: pointer writes invalidate nothing }\r\n",
            ),
        ],
    ),
    (
        "managed_narrow",
        "a managed operation gets a narrow effect",
        [
            (
                b"              if is_managed_type(tbinarynode(n).left.resultdef) then\r\n"
                b"                begin\r\n"
                b"                  add_managed_opaque(ctx^);\r\n",
                b"              if is_managed_type(tbinarynode(n).left.resultdef) then\r\n"
                b"                begin\r\n"
                b"                  { SABOTAGE: managed assignment left narrow }\r\n",
            ),
            (
                b"                  include(ctx.e^.wclasses,ac_heapelem);\r\n"
                b"                  add_managed_opaque(ctx);\r\n"
                b"                  journal(ctx,n,er_string_cow,'');\r\n",
                b"                  include(ctx.e^.wclasses,ac_heapelem);\r\n"
                b"                  { SABOTAGE: string COW store left narrow }\r\n"
                b"                  journal(ctx,n,er_string_cow,'');\r\n",
            ),
        ],
    ),
    (
        "addsym_noop",
        "exact-local identity silently stops being collected",
        [
            (
                b"    procedure addsym(var list : TFPList; sym : tsym);\r\n"
                b"      begin\r\n"
                b"        if not assigned(list) then\r\n"
                b"          list:=TFPList.Create;\r\n"
                b"        if list.IndexOf(sym)<0 then\r\n"
                b"          list.Add(sym);\r\n"
                b"      end;\r\n",
                b"    procedure addsym(var list : TFPList; sym : tsym);\r\n"
                b"      begin\r\n"
                b"        { SABOTAGE: exact symbols not collected }\r\n"
                b"      end;\r\n",
            ),
        ],
    ),
    (
        "conflict_false",
        "effects_conflict answers no-conflict for everything",
        [
            (
                b"    function effects_conflict(const a,b : teffect) : boolean;\r\n"
                b"      begin\r\n"
                b"        result:=true;\r\n",
                b"    function effects_conflict(const a,b : teffect) : boolean;\r\n"
                b"      begin\r\n"
                b"        { SABOTAGE: nothing ever conflicts }\r\n"
                b"        result:=false;\r\n",
            ),
        ],
    ),
]


def find_tool(explicit: str | None, name: str) -> str:
    if explicit:
        return explicit
    env = os.environ.get("MOONBOT_BOOTSTRAP_FPC")
    if name == "fpc.exe" and env:
        return env
    found = shutil.which(name)
    if found:
        return found
    raise SystemExit(f"{name} not found; pass --{name.split('.')[0]}")


def rebuild(fpc: str, make: str) -> bool:
    for stamp in ROOT.glob("*build-stamp*"):
        stamp.unlink()
    env = dict(os.environ)
    env["PATH"] = str(Path(fpc).parent) + os.pathsep + env["PATH"]
    proc = subprocess.run(
        [make, "-C", str(ROOT), "-j1", "all", f"FPC={fpc}",
         "OPT=-O2 -dMOONCOMPILER_PRODUCT_RUNTIME -dMOONCOMPILER_VANILLA_RUNTIME",
         "CPU_TARGET=x86_64", "OS_TARGET=win64"],
        capture_output=True, text=True, timeout=3600, env=env)
    return proc.returncode == 0


def run_gate() -> int:
    proc = subprocess.run(
        [sys.executable, str(GATE),
         "--compiler", str(ROOT / "compiler" / "ppcx64.exe"),
         "--rtl", str(ROOT / "rtl" / "units" / "x86_64-win64")],
        capture_output=True, text=True, timeout=1200)
    return proc.returncode


def restore() -> None:
    subprocess.run(["git", "checkout", "--", str(MODEL)], cwd=ROOT, check=True)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--fpc")
    ap.add_argument("--make")
    ap.add_argument("--only")
    args = ap.parse_args()
    fpc = find_tool(args.fpc, "fpc.exe")
    make = find_tool(args.make, "make.exe")

    dirty = subprocess.run(["git", "status", "--short", "--", str(MODEL)],
                           cwd=ROOT, capture_output=True, text=True)
    if dirty.stdout.strip():
        raise SystemExit("opteffect.pas has local changes; commit or stash first")

    results = []
    source = MODEL.read_bytes()
    try:
        for name, title, patches in SABOTAGES:
            if args.only and name != args.only:
                continue
            mutated = source
            for anchor, replacement in patches:
                if mutated.count(anchor) != 1:
                    raise SystemExit(
                        f"{name}: anchor found {mutated.count(anchor)} times - "
                        f"update the sabotage to match the current model source")
                mutated = mutated.replace(anchor, replacement, 1)
            print(f"--- sabotage {name}: {title}", flush=True)
            MODEL.write_bytes(mutated)
            if not rebuild(fpc, make):
                restore()
                raise SystemExit(f"{name}: sabotaged compiler failed to build - "
                                 f"the sabotage is invalid, not a coverage fact")
            gate_rc = run_gate()
            killed = gate_rc != 0
            results.append((name, killed))
            print(f"    gate rc={gate_rc}: {'KILLED' if killed else 'SURVIVED'}", flush=True)
            restore()
    finally:
        restore()
        print("--- restoring pristine compiler")
        if not rebuild(fpc, make):
            print("WARNING: pristine rebuild failed; rebuild manually", file=sys.stderr)

    survived = [n for n, killed in results if not killed]
    print("\nSABOTAGE MATRIX:")
    for name, killed in results:
        print(f"  {name:20} {'killed' if killed else 'SURVIVED'}")
    if survived or not results:
        print(f"EFFECT SABOTAGE: FAIL ({len(survived)} survivors of {len(results)})")
        return 1
    print(f"EFFECT SABOTAGE: PASS ({len(results)}/{len(results)} killed)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
