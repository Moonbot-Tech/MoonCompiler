#!/usr/bin/env python3
"""Check compiler-process jump-list ownership, not the compiled program's heap.

Build an instrumented compiler in a disposable source copy, then compile that
compiler at O3. Count all OptPass1MOV jump-list lifetimes across the workload,
including exits unrelated to the original three leaks. Product code is untouched.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[3]


def replace_once(text: str, old: str, new: str) -> str:
    if text.count(old) != 1:
        raise RuntimeError(f"instrumentation anchor changed: {old!r}; review the probe")
    return text.replace(old, new, 1)


def instrument(text: str) -> str:
    text = replace_once(text, "    type\n      TJumpTrackingItem = class(TLinkedListItem)", """    var
      ProbeCreated, ProbeFreed: Int64;
    type
      TProbeJumpList = class(TLinkedList)
        constructor Create;
        destructor Destroy; override;
      end;
      TJumpTrackingItem = class(TLinkedListItem)""")
    text = replace_once(text, "    constructor TJumpTrackingItem.Create(ASymbol: TAsmSymbol);", """    constructor TProbeJumpList.Create;
      begin
        inherited Create;
        Inc(ProbeCreated);
      end;

    destructor TProbeJumpList.Destroy;
      begin
        Inc(ProbeFreed);
        inherited Destroy;
      end;

    constructor TJumpTrackingItem.Create(ASymbol: TAsmSymbol);""")
    text = replace_once(text, "JumpTracking := TLinkedList.Create", "JumpTracking := TProbeJumpList.Create")
    return replace_once(text, "\nend.", """
finalization
  writeln('JUMP_LISTS created=',ProbeCreated,' freed=',ProbeFreed,' outstanding=',ProbeCreated-ProbeFreed);
end.""")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bootstrap", type=Path, required=True, help="native x86-64 compiler backend")
    parser.add_argument("--config", type=Path, required=True, help="matching installed RTL/tool paths")
    parser.add_argument("--source", type=Path, default=ROOT)
    parser.add_argument("--output", type=Path, help="new directory for the evidence (default: a temporary one)")
    args = parser.parse_args()
    source = args.source.resolve() / "compiler"
    for path in (args.bootstrap, args.config, source / "msgidx.inc", source / "msgtxt.inc"):
        if not path.is_file():
            parser.error(f"missing {path}; build the source compiler first")
    if args.output:
        out = args.output.resolve()
        out.mkdir(parents=True, exist_ok=False)
    else:
        out = Path(tempfile.mkdtemp(prefix="mooncompiler-jump-resources-"))
    print(f"Evidence: {out}", flush=True)
    copy = out / "compiler"
    shutil.copytree(source, copy, ignore=shutil.ignore_patterns("*.exe", "*.ppu", "*.o", "*.a", "*.s", "units"))
    target = copy / "x86/aoptx86.pas"
    source_hash = hashlib.sha256(target.read_bytes()).hexdigest()
    target.write_text(instrument(target.read_text(encoding="utf-8-sig")), encoding="utf-8")
    suffix = ".exe" if os.name == "nt" else ""

    def build(compiler: Path, label: str, opt: str) -> tuple[Path, str]:
        dest = out / label
        units = dest / "units"
        units.mkdir(parents=True)
        exe = dest / ("ppc" + suffix)
        command = [str(compiler.resolve()), "-n", "@" + str(args.config.resolve()),
                   "-dMOONCOMPILER_VANILLA_RUNTIME", "-B", opt, "-dx86_64",
                   "-Fux86_64", "-Fusystems", "-Fux86", "-Fix86_64", "-Fix86",
                   "-FU" + str(units), "-FE" + str(dest), "-o" + exe.name, "pp.pas"]
        p = subprocess.run(command, cwd=copy, capture_output=True, text=True, timeout=120)
        log = p.stdout + p.stderr
        (dest / "build.log").write_text(log, encoding="utf-8")
        if p.returncode or not exe.is_file():
            raise RuntimeError(f"{label} failed\n{log[-3000:]}")
        return exe, log

    compiler, _ = build(args.bootstrap, "instrumented", "-O1")
    _, log = build(compiler, "workload", "-O3")
    matches = re.findall(r"^JUMP_LISTS created=(\d+) freed=(\d+) outstanding=(-?\d+)\s*$", log, re.M)
    if len(matches) != 1:
        raise RuntimeError("missing or ambiguous lifetime counters; a successful compile is not sufficient")
    created, freed, outstanding = map(int, matches[0])
    result = {"source_sha256": source_hash, "created": created, "freed": freed,
              "outstanding": outstanding, "pass": created > 0 and created == freed and outstanding == 0}
    (out / "result.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result), flush=True)
    return 0 if result["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
