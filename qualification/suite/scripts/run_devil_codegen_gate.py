#!/usr/bin/env python3
"""Devil codegen gate: assert properties of the emitted machine code.

Some defects never change a value: an inline that silently stopped happening, a
bounds check that survived where it was proven redundant, a 64x64 multiply that
quietly became a library call.  This gate compiles small probes with assembly
output and checks the text of the code itself.

Each probe states what must and must not appear at a given optimization level,
so a regression in the optimizer is visible even while every value stays right.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / "tests" / "devil" / "codegen"

HEADER = """program {name};
{{$ifdef FPC}}
  {{$mode delphiunicode}}{{$H+}}
{{$endif}}
{{$APPTYPE CONSOLE}}
{{$Q-}}{{$R-}}
uses SysUtils;
"""

# name, option, body, must_match, must_not_match
PROBES = [
    ("inline_is_inlined", "O3", """
function Add3(X: Integer): Integer; inline;
begin
  Result := X + 3;
end;

var
  I, S: Integer;
begin
  S := 0;
  for I := 0 to 9 do
    S := S + Add3(I);
  WriteLn(S);
end.""",
     [], [r"call\s+.*ADD3"]),

    ("no_libcall_for_int64_mul", "O2", """
var
  A, B, R: Int64;
begin
  A := StrToInt64(ParamStr(0) + '1');
  B := 7;
  R := A * B;
  WriteLn(R);
end.""",
     [r"imul"], [r"call\s+.*MULINT64", r"call\s+.*fpc_mul_int64"]),

    ("shift_is_shift_not_div", "O2", """
var
  A, R: Integer;
begin
  A := Length(ParamStr(0));
  R := A div 8;
  WriteLn(R);
end.""",
     [r"sar|shr"], [r"idiv", r"call\s+.*DIV"]),

    ("currency_mul_uses_wide_path", "O2", """
var
  A, B, R: Currency;
begin
  A := Length(ParamStr(0));
  B := 2.5;
  R := A * B;
  WriteLn(R:0:4);
end.""",
     [r"imul|mul"], []),

    ("range_check_absent_when_off", "O2", """
var
  A: array[0..7] of Integer;
  I: Integer;
begin
  for I := 0 to 7 do
    A[I] := I;
  WriteLn(A[3]);
end.""",
     [], [r"call\s+.*RANGEERROR"]),

    ("bounds_check_present_when_on", "O2", """
{$R+}
var
  A: array[0..7] of Integer;
  I: Integer;
begin
  I := Length(ParamStr(0));
  A[I] := 1;
  WriteLn(A[0]);
end.""",
     [r"call\s+.*RANGEERROR|jae|jb\s"], []),

    ("try_finally_keeps_frame", "O3", """
var
  S: AnsiString;
  I, R: Integer;
begin
  R := 0;
  for I := 0 to 9 do
  begin
    S := AnsiString(IntToStr(I));
    try
      R := R + Length(S);
    finally
      S := '';
    end;
  end;
  WriteLn(R);
end.""",
     [r"fpc_ansistr_decr_ref|ANSISTR_DECR_REF"], []),

    ("const_folded_at_compile_time", "O2", """
var
  R: Integer;
begin
  R := 2 * 3 * 7;
  WriteLn(R);
end.""",
     [r"\$42|66"], [r"imul"]),

    ("empty_loop_removed", "O3", """
var
  I, S: Integer;
begin
  S := 0;
  for I := 0 to 999 do
    ;
  WriteLn(S);
end.""",
     [], [r"\.Lj\d+:\s*\n\s*add.*\$1"]),
]


def run(cmd: list[str], cwd: Path, timeout: int = 180) -> tuple[int, str]:
    try:
        p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True,
                           timeout=timeout)
    except subprocess.TimeoutExpired:
        return 124, "<timeout>"
    return p.returncode, (p.stdout or "") + (p.stderr or "")


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--fpc", type=Path, required=True)
    p.add_argument("--fpc-config", type=Path, required=True)
    p.add_argument("--work", type=Path, default=WORK)
    p.add_argument("--report", type=Path)
    args = p.parse_args()

    fpc = args.fpc.resolve()
    cfg = args.fpc_config.resolve()
    work = args.work.resolve()
    if work.exists():
        shutil.rmtree(work)
    work.mkdir(parents=True)

    findings = []
    for name, option, body, must, must_not in PROBES:
        source = work / f"{name}.dpr"
        source.write_text(HEADER.format(name=name) + body.lstrip("\n") + "\n",
                          encoding="utf-8")
        out = work / f"out-{name}"
        out.mkdir()
        code, log = run([str(fpc), "-n", f"@{cfg}", "-Mdelphi", f"-{option}",
                         "-al", f"-FU{out}", f"-FE{out}", source.name], work)
        asm_files = list(out.glob("*.s"))
        if not asm_files:
            findings.append({"probe": name, "kind": "no-assembly",
                             "detail": log.strip().splitlines()[-2:]})
            continue
        text = "\n".join(f.read_text(encoding="utf-8", errors="ignore")
                         for f in asm_files)
        for pattern in must:
            if not re.search(pattern, text, re.I):
                findings.append({"probe": name, "kind": "missing",
                                 "pattern": pattern, "option": option})
        for pattern in must_not:
            if re.search(pattern, text, re.I):
                findings.append({"probe": name, "kind": "unexpected",
                                 "pattern": pattern, "option": option})

    for f in findings:
        print(json.dumps(f, sort_keys=True))
    if args.report:
        args.report.write_text(json.dumps(findings, indent=2, sort_keys=True)
                               + "\n", encoding="utf-8")
    print(f"DEVIL_CODEGEN {'OK' if not findings else 'FINDINGS'} "
          f"probes={len(PROBES)} findings={len(findings)}")
    sys.exit(1 if findings else 0)


if __name__ == "__main__":
    main()
