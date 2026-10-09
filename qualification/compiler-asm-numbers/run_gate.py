#!/usr/bin/env python3
"""The x86-64 inline assembler reads every number as written.

forms.tsv holds the written forms of both readers - AT&T (raatt.pas, rax86att.pas) and Intel (rax86int.pas):
integers in every base, characters and strings, floating point, expressions, immediates, displacements,
scale factors and alignments.  A form is either

  accept  the bytes it assembles to.  The reference is GNU as 2.46 for AT&T and Delphi 12.2 (dcc64) or the
          written value for Intel; a float is the correctly rounded value.  The forms of one group are built
          into one program, each between marker bytes, and the program compares its own code with the table.
          `a|b` names two encodings of the same instruction (with optimization on, the reader turns [idx*2+d]
          into the shorter [idx+idx+d]); `HEX@GVX:N` is HEX followed by the eight bytes of the address of the
          variable GVX plus N, as the linker writes them; `HEX@REL32GVX:N` uses a four-byte RIP displacement;
          `align:N` means: the end of the form lies on N and
          the padding is shorter than N, `align:N:HEX` the same after the bytes HEX of the form;
  refuse  the form has no value the instruction or directive can carry, or no single reading; it must stop
          the compilation with the given message.

    run_gate.py [--compiler PPCX64] [--rtl UNITS/RTL] [--output DIR]
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
MARKER = "15,11,15,11,15,11,15,11"
# the names the forms use: constants, a record with its field B at 4, a variable
DECL = """const
  CFIVE = 5;
  CTWO = 2;

type
  TRR = record
    A, B: Integer;
  end;

var
  GVX: Integer;
"""


def default_compiler() -> Path:
    if os.name == "nt":
        return ROOT / "toolchain/bin/x86_64-win64/ppcx64.exe"
    return ROOT / "toolchain/bin/ppcx64"


def default_rtl() -> Path:
    if os.name == "nt":
        return ROOT / "toolchain/units/x86_64-win64/rtl"
    roots = sorted((ROOT / "toolchain/lib/fpc").glob("*/units/x86_64-linux/rtl"))
    if len(roots) != 1:
        raise SystemExit("cannot uniquely locate Linux RTL; pass --rtl")
    return roots[0]


def link_args() -> list[str]:
    if os.name == "nt":
        return []
    probe = subprocess.run(["gcc", "-print-file-name=libgcc_s.so"], capture_output=True, text=True, timeout=30)
    libgcc = Path(probe.stdout.strip())
    if probe.returncode != 0 or not libgcc.is_absolute() or not libgcc.exists():
        raise SystemExit("cannot locate libgcc_s")
    return [f"-Fl{libgcc.parent}"]


def load_forms() -> list[dict[str, str]]:
    forms = []
    for number, line in enumerate((HERE / "forms.tsv").read_text(encoding="utf-8").splitlines(), 1):
        if not line or line.startswith("#"):
            continue
        fields = line.split("\t")
        if len(fields) != 6 or fields[1] not in ("att", "intel") or fields[3] not in ("accept", "refuse"):
            raise SystemExit(f"forms.tsv:{number}: expected id, att|intel, group, accept|refuse, text, expected")
        forms.append(dict(zip(("id", "dialect", "group", "verdict", "text", "expected"), fields)))
    if len({form["id"] for form in forms}) != len(forms):
        raise SystemExit("forms.tsv: duplicate id")
    return forms


def body(form: dict[str, str]) -> str:
    marker = (".byte " if form["dialect"] == "att" else "db ") + MARKER
    lines = [marker] + [part.strip() for part in form["text"].split(";;")] + [marker]
    return "\n".join("  " + line for line in lines)


def pascal_string(text: str) -> str:
    return "'" + text.replace("'", "''") + "'"


def program(group: str, forms: list[dict[str, str]]) -> str:
    procs, checks = [], []
    for index, form in enumerate(forms):
        procs.append(f"{{$asmmode {form['dialect']}}}\nprocedure F{index}; assembler; nostackframe;\nasm\n"
                     f"{body(form)}\nend;\n")
        checks.append(f"  Check({pascal_string(form['id'])}, @F{index}, {pascal_string(form['expected'])});")
    return f"""program asm_numbers_{group};
{{$mode delphi}}{{$h+}}{{$pointermath on}}

const
  Marker: array[0..7] of Byte = ({MARKER});
  Digits: array[0..15] of Char = '0123456789abcdef';

var
  Failures, Count: Integer;

{DECL}
{''.join(procs)}
function At(P: PByte): Boolean;
var
  I: Integer;
begin
  for I := 0 to 7 do
    if P[I] <> Marker[I] then
      Exit(False);
  Result := True;
end;

function Relocated(const Expected: string; CodeEnd: PByte): string;
{{ @GVX:N is an absolute address; @REL32GVX:N is relative to instruction end. }}
var
  Mark, Error, I, Width, Prefix: Integer;
  Addend: Int64;
  Value: QWord;
begin
  Mark := Pos('@GVX:', Expected);
  Width := 8;
  Prefix := 5;
  if Mark = 0 then
    begin
      Mark := Pos('@REL32GVX:', Expected);
      Width := 4;
      Prefix := 10;
    end;
  if Mark = 0 then Exit(Expected);
  Val(Copy(Expected, Mark + Prefix, Length(Expected)), Addend, Error);
  Value := QWord(PtrUInt(@GVX)) + QWord(Addend);
  if Width = 4 then Value := Value - QWord(PtrUInt(CodeEnd));
  Result := Copy(Expected, 1, Mark - 1);
  for I := 0 to Width - 1 do
    Result := Result + Digits[(Value shr (8 * I + 4)) and 15] + Digits[(Value shr (8 * I)) and 15];
end;

procedure Check(const Id: string; Code: Pointer; const Expected: string);
var
  P, First: PByte;
  Got, Lead: string;
  Size, Align: PtrUInt;
  Error, Colon: Integer;
begin
  Inc(Count);
  P := Code;
  while not At(P) do
    Inc(P);
  Inc(P, 8);
  First := P;
  Got := '';
  while not At(P) do
    begin
      Got := Got + Digits[P^ shr 4] + Digits[P^ and 15];
      Inc(P);
    end;
  if Copy(Expected, 1, 6) = 'align:' then
    begin
      Lead := Copy(Expected, 7, Length(Expected));
      Colon := Pos(':', Lead);
      if Colon = 0 then
        begin
          Val(Lead, Align, Error);
          Lead := '';
        end
      else
        begin
          Val(Copy(Lead, 1, Colon - 1), Align, Error);
          Delete(Lead, 1, Colon);
        end;
      Size := P - First - PtrUInt(Length(Lead) div 2);
      if (Copy(Got, 1, Length(Lead)) <> Lead) or ((PtrUInt(P) and (Align - 1)) <> 0) or (Size >= Align) then
        begin
          WriteLn('FAIL ', Id, ' got ', Got, ', end at ', PtrUInt(P) and (Align - 1), ' of ', Align);
          Inc(Failures);
        end;
    end
  else if Pos('|' + Got + '|', '|' + Relocated(Expected, P) + '|') = 0 then
    begin
      WriteLn('FAIL ', Id, ' got ', Got, ' expected ', Relocated(Expected, P));
      Inc(Failures);
    end;
end;

begin
{chr(10).join(checks)}
  if Failures = 0 then
    WriteLn('ASM_NUMBERS_OK ', Count)
  else
    Halt(1);
end.
"""


def compile_one(compiler: Path, rtl: Path, options: list[str], source: Path) -> subprocess.CompletedProcess[str]:
    # Delphi mode, as the product configuration (fpc.cfg) and the inventory: in it `dword ptr 5` is a constant
    cmd = [str(compiler), "-Mdelphi", "-n", "-dMOONCOMPILER_VANILLA_RUNTIME", f"-Fu{rtl}",
           f"-FE{source.parent}", f"-FU{source.parent}", "-vew"] + link_args() + options + [str(source)]
    return subprocess.run(cmd, capture_output=True, text=True, timeout=300)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--compiler", type=Path, default=default_compiler())
    ap.add_argument("--rtl", type=Path)
    ap.add_argument("--output", type=Path, help="keep the sources and logs here (must not exist)")
    args = ap.parse_args()
    args.rtl = args.rtl or default_rtl()
    forms = load_forms()
    if args.output:
        args.output.mkdir(parents=True)
        work = args.output
    else:
        work = Path(tempfile.mkdtemp(prefix="asm_numbers_"))
    failures: list[str] = []
    accepted = refused = 0
    try:
        groups: dict[str, list[dict[str, str]]] = {}
        for form in forms:
            if form["verdict"] == "accept":
                groups.setdefault(form["group"], []).append(form)
        for mode in ("-O-", "-O3"):
            for group, members in groups.items():
                directory = work / mode.strip("-") / group
                directory.mkdir(parents=True)
                source = directory / f"asm_numbers_{group}.pas"
                source.write_text(program(group, members), encoding="latin-1")
                built = compile_one(args.compiler, args.rtl, [mode], source)
                exe = source.with_suffix(".exe" if os.name == "nt" else "")
                if built.returncode != 0 or not exe.is_file():
                    failures.append(f"{mode} {group}: compile failed\n{(built.stdout + built.stderr)[-3000:]}")
                    continue
                run = subprocess.run([str(exe)], capture_output=True, text=True, timeout=60)
                if run.returncode != 0 or run.stdout.strip() != f"ASM_NUMBERS_OK {len(members)}":
                    failures.append(f"{mode} {group}: {run.stdout.strip()[-3000:]}")
                elif mode == "-O-":
                    accepted += len(members)
        directory = work / "refuse"
        directory.mkdir(parents=True)
        for form in forms:
            if form["verdict"] != "refuse":
                continue
            name = "r_" + form["id"].lower()
            source = directory / f"{name}.pas"
            source.write_text(f"unit {name};\ninterface\nimplementation\n{{$asmmode {form['dialect']}}}\n{DECL}\n"
                              f"procedure P; assembler; nostackframe;\nasm\n{body(form)}\nend;\nend.\n",
                              encoding="latin-1")
            built = compile_one(args.compiler, args.rtl, [], source)
            output = built.stdout + built.stderr
            if built.returncode == 0:
                failures.append(f"{form['id']}: `{form['text']}` compiled, it must be refused")
            elif form["expected"] not in output:
                failures.append(f"{form['id']}: `{form['text']}` refused without `{form['expected']}`:\n"
                                f"{output[-1500:]}")
            else:
                refused += 1
        if os.name == 'nt':
            # Win64's product image is above 4 GB. Explicit absolute disp32
            # cannot represent that address, even though RIP-relative can.
            source = directory / 'absolute_overflow.pas'
            source.write_text('program absolute_overflow;\n{$asmmode intel}\nvar G:Int64;\n'
                              'function ReadGlobal:Int64;assembler;\n'
                              'asm mov rcx,abs [G]; mov rax,rcx; end;\n'
                              'begin WriteLn(ReadGlobal); end.\n')
            built = compile_one(args.compiler, args.rtl, [], source)
            output = built.stdout + built.stderr
            (directory/'absolute_overflow.log').write_text(output)
            if built.returncode == 0 or '32-bit absolute relocation' not in output or 'cannot represent' not in output:
                failures.append('Absolute relocation overflow was not rejected at link time: '+output[-1500:])
    finally:
        if not args.output:
            shutil.rmtree(work, ignore_errors=True)
    if failures:
        print("\n".join(failures))
        print(f"ASM_NUMBERS_GATE_FAIL failures={len(failures)}")
        return 1
    print(f"ASM_NUMBERS_GATE_PASS accepted={accepted} refused={refused} modes=2")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
