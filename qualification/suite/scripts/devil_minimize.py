#!/usr/bin/env python3
"""Cut a red Devil check down to a standalone program.

Takes the generated layer, keeps the single procedure that produced the check
plus the shared support declarations, and writes a small program that still
reproduces the disagreement.  Then it verifies the cut: the program is built at
the two optimization levels that disagreed and the outputs are compared.

    devil_minimize.py dvl-expr-00203-form --seed 1 --cases 200 \
        --profiles debug,release
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

import devil_toolchain as tc

ROOT = Path(__file__).resolve().parents[1]
DEVIL = ROOT / "tests" / "devil"
GENERATOR = ROOT / "scripts" / "generate_devil.py"

PROGRAM = """program devil_min;

{{ Cut from Devil layer {layer}, seed {seed}, case {case}. }}

{{$ifdef FPC}}
  {{$mode delphiunicode}}{{$H+}}
  {{$modeswitch advancedrecords}}
  {{$modeswitch anonymousfunctions}}
  {{$modeswitch functionreferences}}
  {{$modeswitch INLINEVARS}}
{{$endif}}
{{$APPTYPE CONSOLE}}
{{$Q-}}{{$R-}}

uses
{{$ifdef FPC}}
  {{$ifdef UNIX}}cthreads,{{$endif}}
{{$endif}}
  SysUtils, Classes, Math, TypInfo, Rtti, devil_runtime;

{{$I devil_support.inc}}

{body}

begin
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow,
    exUnderflow, exPrecision]);
  {call};
  Halt(DevilReport('DEVIL_MIN', {seed}));
end.
"""


def run(cmd: list[str], cwd: Path, timeout: int = 300) -> tuple[int, str]:
    try:
        p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True,
                           timeout=timeout)
    except subprocess.TimeoutExpired:
        return 124, "<timeout>"
    return p.returncode, (p.stdout or "") + (p.stderr or "")


def collect_routines(text: str) -> dict[str, tuple[int, int]]:
    """Map routine name to its [start, end) line range."""
    lines = text.splitlines()
    spans: dict[str, tuple[int, int]] = {}
    header = re.compile(r"^(?:procedure|function)\s+([A-Za-z_][\w.]*)")
    current, start, depth, seen_begin = None, 0, 0, False
    for i, line in enumerate(lines):
        m = header.match(line)
        if m and current is None:
            current, start, depth, seen_begin = m.group(1), i, 0, False
            continue
        if current is None:
            continue
        stripped = line.strip().lower()
        if stripped == "begin" or stripped.endswith(" do begin"):
            depth += 1
            seen_begin = True
        elif stripped.startswith("end;"):
            depth -= 1
            if seen_begin and depth <= 0:
                spans[current] = (start, i + 1)
                current = None
    return spans


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("name")
    p.add_argument("--seed", type=int, required=True)
    p.add_argument("--cases", type=int, default=200)
    p.add_argument("--profiles", default="debug,release")
    p.add_argument("--out", type=Path,
                   default=ROOT / "results" / "runs" / "devil-minimized")
    args = p.parse_args()

    generated = args.out.resolve().parent / (args.out.name + "-source")
    if generated.exists():
        shutil.rmtree(generated)
    code, log = run([sys.executable, str(GENERATOR), "--seed", str(args.seed),
                     "--cases", str(args.cases), "--out", str(generated)],
                    ROOT.parent.parent)
    if code != 0:
        shutil.rmtree(generated, ignore_errors=True)
        print("generator failed: " + (log.strip().splitlines()[-1]
                                      if log.strip() else "no diagnostic"))
        sys.exit(2)

    manifest = json.loads(
        (generated / "devil_manifest.json").read_text(encoding="utf-8"))
    case = None
    for c in manifest["cases"]:
        if args.name.startswith(c["name"]):
            case = c
            break
    if case is None:
        shutil.rmtree(generated, ignore_errors=True)
        print(f"no case for {args.name}")
        sys.exit(1)

    layer = case["layer"]
    inc = generated / f"devil_{layer}.inc"
    text = inc.read_text(encoding="utf-8")
    shutil.rmtree(generated)
    spans = collect_routines(text)
    index = case["name"].rsplit("-", 1)[-1]
    proc = "Dvl" + layer.capitalize() + index

    # the case procedure plus everything the generator emitted for it: types
    # declared right before it and helper routines carrying the same index
    wanted = [n for n in spans if index in n]
    if proc not in wanted:
        print(f"procedure {proc} not found in {inc.name}")
        sys.exit(1)
    lines = text.splitlines()
    keep: list[str] = []
    # type blocks that mention the case index
    for i, line in enumerate(lines):
        if line.strip() == "type" and any(index in lines[j]
                                          for j in range(i, min(i + 12, len(lines)))):
            j = i
            while j < len(lines) and lines[j].strip() != "":
                keep.append(lines[j])
                j += 1
            keep.append("")
    for name in sorted(wanted, key=lambda n: spans[n][0]):
        start, end = spans[name]
        keep.extend(lines[start:end])
        keep.append("")

    out = args.out
    out.mkdir(parents=True, exist_ok=True)
    shutil.copy(DEVIL / "devil_support.inc", out / "devil_support.inc")
    shutil.copy(DEVIL / "devil_runtime.pas", out / "devil_runtime.pas")
    program = PROGRAM.format(layer=layer, seed=args.seed, case=case["name"],
                             body="\n".join(keep), call=proc)
    (out / "devil_min.dpr").write_text(program, encoding="utf-8")
    print(f"cut {len(keep)} lines into {out / 'devil_min.dpr'}")

    results = {}
    compile_failed = False
    for profile in args.profiles.split(","):
        build = out / f"out-{profile}"
        if build.exists():
            shutil.rmtree(build)
        build.mkdir()
        code, log = run(tc.compile_command(out / "devil_min.dpr", build,
                                           profile), out)
        exe = build / "devil_min.exe"
        if not exe.exists():
            lines = log.strip().splitlines()
            results[profile] = "COMPILE FAILED: " + (lines[-1] if lines else "no diagnostic")
            compile_failed = True
            continue
        code, output = run([str(exe)], out)
        results[profile] = output.strip().splitlines()[-1] if output.strip() else "(no output)"
    for profile, line in results.items():
        print(f"{profile:8}: {line}")
    if compile_failed:
        print("MINIMIZATION FAILED: the cut does not compile")
        sys.exit(2)
    if len(set(results.values())) > 1:
        print("MINIMIZED: the cut still reproduces the disagreement")
    else:
        print("cut agrees everywhere: the trigger needs the surrounding forms")


if __name__ == "__main__":
    main()
