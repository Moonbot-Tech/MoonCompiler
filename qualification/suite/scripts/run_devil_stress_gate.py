#!/usr/bin/env python3
"""Devil stress gate: hunt for internal errors and hangs.

Every case is generated as its own program and compiled alone, so a compiler
that dies takes only that case with it.  The outcome under test is not a value
but the compiler itself: it must finish, must not report an internal error, and
must not exceed the time budget.

Shapes push on the places a compiler falls over: nesting depth, expression
width, inline chains, generic specialization depth, overload set size, long
literals, many locals, deep record nesting.
"""

from __future__ import annotations

import argparse
import json
import random
import shutil
import subprocess
import sys
import time
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / "tests" / "devil" / "stress"

HEADER = """program {name};
{{$ifdef FPC}}
  {{$mode delphiunicode}}{{$H+}}
  {{$modeswitch advancedrecords}}
  {{$modeswitch anonymousfunctions}}
  {{$modeswitch functionreferences}}
  {{$modeswitch INLINEVARS}}
{{$endif}}
{{$APPTYPE CONSOLE}}
{{$Q-}}{{$R-}}
uses SysUtils;
"""


def nested_expression(depth: int, rng: random.Random) -> str:
    expr = "1"
    for k in range(depth):
        op = rng.choice(("+", "-", "*", "or", "xor"))
        expr = f"({expr} {op} {k % 7 + 1})"
    return expr


def shape_deep_expression(rng: random.Random) -> str:
    return f"""
var
  R: Integer;
begin
  R := {nested_expression(rng.randrange(120, 400), rng)};
  WriteLn(R);
end."""


def shape_deep_nesting(rng: random.Random) -> str:
    depth = rng.randrange(20, 60)
    lines = ["var", "  R: Integer;", "begin", "  R := 0;"]
    for k in range(depth):
        lines.append("  " + "  " * k + f"if R >= {k} then")
        lines.append("  " + "  " * k + "begin")
    lines.append("  " + "  " * depth + "Inc(R);")
    for k in range(depth - 1, -1, -1):
        lines.append("  " + "  " * k + "end;")
    lines += ["  WriteLn(R);", "end."]
    return "\n" + "\n".join(lines)


def shape_inline_chain(rng: random.Random) -> str:
    depth = rng.randrange(20, 60)
    parts = []
    for k in range(depth):
        inner = "X" if k == 0 else f"F{k - 1}(X)"
        parts.append(f"""
function F{k}(X: Integer): Integer; inline;
begin
  Result := {inner} + {k};
end;""")
    return "".join(parts) + f"""

var
  R: Integer;
begin
  R := F{depth - 1}(1);
  WriteLn(R);
end."""


def shape_generic_depth(rng: random.Random) -> str:
    depth = rng.randrange(4, 9)
    lines = ["type", "  TBox<T> = record", "    Value: T;", "  end;", ""]
    spec = "Integer"
    for _ in range(depth):
        spec = f"TBox<{spec}>"
    lines += [f"var", f"  B: {spec};", "begin", "  WriteLn(SizeOf(B));", "end."]
    return "\n" + "\n".join(lines)


def shape_overload_set(rng: random.Random) -> str:
    count = rng.randrange(20, 60)
    types = ["ShortInt", "Byte", "SmallInt", "Word", "Integer", "Cardinal",
             "Int64", "UInt64", "Single", "Double", "Currency", "string",
             "AnsiString", "Boolean", "AnsiChar", "WideChar"]
    parts = []
    for k, t in enumerate(types[:count]):
        parts.append(f"""
function Pick(X: {t}): Integer; overload;
begin
  Result := {k};
end;""")
    return "".join(parts) + """

var
  I: Integer;
begin
  I := 1;
  WriteLn(Pick(I));
end."""


def shape_many_locals(rng: random.Random) -> str:
    count = rng.randrange(200, 600)
    lines = ["var"]
    lines += [f"  V{k}: Integer;" for k in range(count)]
    lines.append("begin")
    lines += [f"  V{k} := {k};" for k in range(count)]
    lines.append("  WriteLn(V0 + V%d);" % (count - 1))
    lines.append("end.")
    return "\n" + "\n".join(lines)


def shape_record_depth(rng: random.Random) -> str:
    depth = rng.randrange(8, 20)
    lines = ["type"]
    lines.append("  TLevel0 = record V: Integer; end;")
    for k in range(1, depth):
        lines.append(f"  TLevel{k} = record Inner: TLevel{k - 1}; V: Integer; end;")
    lines += ["var", f"  R: TLevel{depth - 1};", "begin",
              "  R.V := 1;", "  WriteLn(SizeOf(R));", "end."]
    return "\n" + "\n".join(lines)


def shape_case_width(rng: random.Random) -> str:
    arms = rng.randrange(200, 800)
    lines = ["var", "  I, R: Integer;", "begin", "  I := 7;", "  case I of"]
    for k in range(arms):
        lines.append(f"    {k}: R := {k * 3};")
    lines += ["  else", "    R := -1;", "  end;", "  WriteLn(R);", "end."]
    return "\n" + "\n".join(lines)


def shape_closure_depth(rng: random.Random) -> str:
    depth = rng.randrange(5, 15)
    lines = ["var", "  R: Integer;", "  P: TProc;", "begin", "  R := 0;"]
    for k in range(depth):
        lines.append("  " + "  " * k + "P := procedure")
        lines.append("  " + "  " * k + "begin")
        lines.append("  " + "  " * k + f"  Inc(R, {k});")
    for k in range(depth - 1, -1, -1):
        lines.append("  " + "  " * k + "end;")
    lines += ["  P();", "  WriteLn(R);", "end."]
    return "\n" + "\n".join(lines)


def shape_string_literal(rng: random.Random) -> str:
    parts = rng.randrange(50, 200)
    literal = " + ".join(f"'{chr(97 + k % 26) * 8}'" for k in range(parts))
    return f"""
var
  S: string;
begin
  S := {literal};
  WriteLn(Length(S));
end."""


SHAPES = {
    "deep-expression": shape_deep_expression,
    "deep-nesting": shape_deep_nesting,
    "inline-chain": shape_inline_chain,
    "generic-depth": shape_generic_depth,
    "overload-set": shape_overload_set,
    "many-locals": shape_many_locals,
    "record-depth": shape_record_depth,
    "case-width": shape_case_width,
    "closure-depth": shape_closure_depth,
    "string-literal": shape_string_literal,
}


def run(cmd: list[str], cwd: Path, timeout: int) -> tuple[int, str, float]:
    started = time.time()
    try:
        p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True,
                           timeout=timeout)
    except subprocess.TimeoutExpired:
        return 124, "<timeout>", time.time() - started
    return p.returncode, (p.stdout or "") + (p.stderr or ""), time.time() - started


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--fpc", type=Path, required=True)
    p.add_argument("--fpc-config", type=Path, required=True)
    p.add_argument("--seed", type=int, default=1)
    p.add_argument("--cases", type=int, default=30)
    p.add_argument("--options", default="O2")
    p.add_argument("--timeout", type=int, default=120)
    p.add_argument("--work", type=Path, default=WORK)
    p.add_argument("--report", type=Path)
    args = p.parse_args()

    fpc = args.fpc.resolve()
    cfg = args.fpc_config.resolve()
    work = args.work.resolve()
    if work.exists():
        shutil.rmtree(work)
    work.mkdir(parents=True)

    rng = random.Random((args.seed << 8) ^ zlib.crc32(b"stress"))
    findings, rows = [], []
    names = list(SHAPES)
    for index in range(args.cases):
        shape = names[index % len(names)]
        name = f"dvl_stress_{index:03d}_{shape.replace('-', '_')}"
        source = work / f"{name}.dpr"
        source.write_text(HEADER.format(name=name) + SHAPES[shape](rng).lstrip("\n")
                          + "\n", encoding="utf-8")
        for option in args.options.split(","):
            out = work / f"out-{name}-{option}"
            out.mkdir()
            code, log, seconds = run(
                [str(fpc), "-n", f"@{cfg}", "-Mdelphi", f"-{option}",
                 f"-FU{out}", f"-FE{out}", source.name], work, args.timeout)
            row = {"case": name, "shape": shape, "option": option,
                   "seconds": round(seconds, 1), "ok": code == 0}
            rows.append(row)
            if code == 124:
                findings.append({"kind": "compiler-hang", "case": name,
                                 "shape": shape, "option": option})
            elif "nternal error" in log:
                line = next((l.strip() for l in log.splitlines()
                             if "nternal error" in l), "")
                findings.append({"kind": "internal-error", "case": name,
                                 "shape": shape, "option": option, "detail": line})
            elif code != 0:
                line = next((l.strip() for l in log.splitlines()
                             if "Error" in l or "Fatal" in l), "")
                findings.append({"kind": "rejected", "case": name,
                                 "shape": shape, "option": option, "detail": line})

    for f in findings:
        print(json.dumps(f, sort_keys=True))
    slowest = sorted(rows, key=lambda r: -r["seconds"])[:3]
    print("slowest: " + ", ".join(f"{r['shape']} {r['seconds']}s" for r in slowest))
    if args.report:
        args.report.write_text(json.dumps({"rows": rows, "findings": findings},
                                          indent=2, sort_keys=True) + "\n",
                               encoding="utf-8")
    print(f"DEVIL_STRESS {'OK' if not findings else 'FINDINGS'} "
          f"cases={args.cases} findings={len(findings)}")
    sys.exit(1 if findings else 0)


if __name__ == "__main__":
    main()
