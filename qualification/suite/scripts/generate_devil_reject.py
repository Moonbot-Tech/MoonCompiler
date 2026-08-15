#!/usr/bin/env python3
"""Devil reject layer: compilation itself is the observable.

Each case is a whole tiny program plus a verdict the language requires:

  * `accept` - the program is valid Delphi and must compile; a rejection is a
    false positive of the compiler;
  * `reject` - the program is invalid and must be rejected; compiling it is a
    false negative, and the emitted diagnostic is compared across compilers.

Nothing here needs a captured answer: the verdict follows from the language,
and Delphi 12.2 arbitrates the wording when it is available.
"""

from __future__ import annotations

import argparse
import json
import random
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "tests" / "devil" / "reject"

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

# (id, verdict, body) - body is the whole program after the header
CASES: list[tuple[str, str, str]] = [
    ("assign-const", "reject", """
const
  C = 5;
begin
  C := 6;
  WriteLn(C);
end."""),
    ("type-mismatch-string-int", "reject", """
var
  S: string;
begin
  S := 5;
  WriteLn(S);
end."""),
    ("undeclared-identifier", "reject", """
begin
  WriteLn(NoSuchIdentifier);
end."""),
    ("wrong-argument-count", "reject", """
procedure P(A, B: Integer);
begin
  WriteLn(A + B);
end;
begin
  P(1);
end."""),
    ("missing-result-type", "reject", """
function F: ;
begin
end;
begin
end."""),
    ("duplicate-identifier", "reject", """
var
  X: Integer;
  X: Integer;
begin
  X := 1;
end."""),
    ("case-duplicate-label", "reject", """
var
  I: Integer;
begin
  I := 1;
  case I of
    1: WriteLn('a');
    1: WriteLn('b');
  end;
end."""),
    ("for-counter-not-ordinal", "reject", """
var
  D: Double;
begin
  for D := 1.0 to 2.0 do
    WriteLn(D);
end."""),
    ("abstract-instantiation-ok", "accept", """
type
  TBase = class
    procedure P; virtual; abstract;
  end;
  TDerived = class(TBase)
    procedure P; override;
  end;
procedure TDerived.P;
begin
  WriteLn('ok');
end;
var
  B: TBase;
begin
  B := TDerived.Create;
  B.P;
  B.Free;
end."""),
    ("inline-var-scope", "accept", """
begin
  if Random(1) = 0 then
  begin
    var Inner := 42;
    WriteLn(Inner);
  end;
end."""),
    ("inline-const-runtime", "accept", """
var
  Base: Integer;
begin
  Base := 3;
  const Derived = 2 * Base + 1;
  WriteLn(Derived);
end."""),
    ("assign-to-inline-const", "reject", """
var
  Base: Integer;
begin
  Base := 3;
  const Derived = 2 * Base;
  Derived := 9;
  WriteLn(Derived);
end."""),
    ("generic-specialization", "accept", """
type
  TBox<T> = record
    Value: T;
  end;
var
  B: TBox<Integer>;
begin
  B.Value := 7;
  WriteLn(B.Value);
end."""),
    ("generic-wrong-arity", "reject", """
type
  TBox<T> = record
    Value: T;
  end;
var
  B: TBox<Integer, string>;
begin
  WriteLn(SizeOf(B));
end."""),
    ("interface-missing-method", "reject", """
type
  IThing = interface
    function Val: Integer;
  end;
  TThing = class(TInterfacedObject, IThing)
  end;
var
  T: IThing;
begin
  T := TThing.Create;
  WriteLn(T.Val);
end."""),
    ("overload-ambiguous", "accept", """
procedure P(X: Integer); overload;
begin
  WriteLn('i', X);
end;
procedure P(X: Int64); overload;
begin
  WriteLn('l', X);
end;
var
  C: Cardinal;
begin
  C := 1;
  P(C);
end."""),
    ("class-var-access", "accept", """
type
  TCounter = class
    class var Count: Integer;
  end;
begin
  TCounter.Count := 3;
  WriteLn(TCounter.Count);
end."""),
    ("record-method-static-self", "reject", """
type
  TRec = record
    class function F: Integer; static;
  end;
class function TRec.F: Integer;
begin
  Result := Self.F;
end;
begin
  WriteLn(TRec.F);
end."""),
    ("string-index-assign", "accept", """
var
  S: AnsiString;
begin
  S := 'abc';
  UniqueString(S);
  S[1] := 'z';
  WriteLn(string(S));
end."""),
    ("const-param-write", "reject", """
procedure P(const X: Integer);
begin
  X := 5;
end;
begin
  P(1);
end."""),
    ("array-const-index-out-of-range", "reject", """
var
  A: array[0..3] of Integer;
begin
  A[9] := 1;
  WriteLn(A[0]);
end."""),
    ("goto-into-block", "accept", """
label
  Target;
begin
  goto Target;
  if True then
  begin
Target:
    WriteLn('here');
  end;
end."""),
    ("nested-function-capture-in-closure", "reject", """
procedure Outer;
  procedure Inner;
  begin
    WriteLn('inner');
  end;
var
  P: TProc;
begin
  P := procedure
       begin
         Inner;
       end;
  P();
end;
begin
  Outer;
end."""),
    ("with-ambiguous-ok", "accept", """
type
  TA = record
    X: Integer;
  end;
  TB = record
    Y: Integer;
  end;
var
  A: TA;
  B: TB;
begin
  A.X := 1;
  B.Y := 2;
  with A, B do
    WriteLn(X + Y);
end."""),
    ("interface-no-guid-supports", "reject", """
type
  INoGuid = interface
    function V: Integer;
  end;
var
  I: INoGuid;
  O: TObject;
begin
  O := TObject.Create;
  if Supports(O, INoGuid, I) then
    WriteLn(I.V);
  O.Free;
end."""),
    ("class-abstract-direct", "accept", """
type
  TBase = class
    procedure P; virtual; abstract;
  end;
var
  B: TBase;
begin
  B := TBase.Create;
  B.Free;
  WriteLn('created');
end."""),
    ("var-param-literal", "reject", """
procedure P(var X: Integer);
begin
  X := 1;
end;
begin
  P(5);
end."""),
    ("out-param-const", "reject", """
procedure P(out X: Integer);
begin
  X := 1;
end;
const
  C = 5;
begin
  P(C);
end."""),
    ("generic-constraint-violation", "reject", """
type
  TNeedsClass<T: class> = record
    Value: T;
  end;
var
  R: TNeedsClass<Integer>;
begin
  WriteLn(SizeOf(R));
end."""),
    ("string-to-pchar-implicit", "reject", """
var
  P: PAnsiChar;
  I: Integer;
begin
  I := 5;
  P := I;
  WriteLn(P);
end."""),
    ("set-element-out-of-range", "reject", """
type
  TSmall = set of 0..7;
var
  S: TSmall;
begin
  S := [9];
  WriteLn(SizeOf(S));
end."""),
    ("inherited-without-parent", "accept", """
type
  TThing = class
    procedure P;
  end;
procedure TThing.P;
begin
  inherited;
  WriteLn('ok');
end;
var
  T: TThing;
begin
  T := TThing.Create;
  T.P;
  T.Free;
end."""),
    ("set-of-too-large", "reject", """
type
  TBig = set of Integer;
var
  S: TBig;
begin
  S := [1];
  WriteLn(SizeOf(S));
end."""),
]


def variants(rng: random.Random, count: int) -> list[tuple[str, str, str]]:
    """Deterministic selection with light shuffling, so different seeds put the
    same case under a different neighbour set."""
    pool = list(CASES)
    rng.shuffle(pool)
    return pool[:count] if count < len(pool) else pool


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--count", type=int, default=len(CASES))
    parser.add_argument("--out", type=Path, default=OUT)
    args = parser.parse_args()

    rng = random.Random((args.seed << 8) ^ zlib.crc32(b"reject"))
    out = args.out
    out.mkdir(parents=True, exist_ok=True)
    for old in out.glob("*.dpr"):
        old.unlink()

    manifest = []
    for case_id, verdict, body in variants(rng, args.count):
        name = "dvl_reject_%s" % case_id.replace("-", "_")
        source = HEADER.format(name=name) + body.lstrip("\n") + "\n"
        (out / (name + ".dpr")).write_text(source, encoding="utf-8")
        manifest.append({"case": case_id, "program": name, "verdict": verdict})
    (out / "manifest.json").write_text(
        json.dumps({"schema": 1, "seed": args.seed, "cases": manifest},
                   indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({"cases": len(manifest), "seed": args.seed}, sort_keys=True))


if __name__ == "__main__":
    main()
