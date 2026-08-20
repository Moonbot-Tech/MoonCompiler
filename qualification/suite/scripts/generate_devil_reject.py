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
uses
{{$ifdef FPC}}
  mormot.core.fpcx64mm,
  {{$ifdef UNIX}}cthreads,{{$endif}}
{{$endif}}
  SysUtils;
"""

# (id, verdict, body) - body is the whole program after the header
CASES: list[tuple[str, str, str]] = [
    # dvl-0019: the standard Delphi callback types must exist in the RTL
    ("stdtype-tproc", "accept", """
var
  P: TProc;
  Seen: Integer;
begin
  Seen := 0;
  P := procedure
    begin
      Inc(Seen);
    end;
  P();
  WriteLn(Seen);
end."""),

    ("stdtype-tfunc", "accept", """
var
  F: TFunc<Integer>;
begin
  F := function: Integer
    begin
      Result := 7;
    end;
  WriteLn(F());
end."""),

    ("stdtype-tpredicate", "accept", """
var
  Test: TPredicate<Integer>;
begin
  Test := function(X: Integer): Boolean
    begin
      Result := X > 0;
    end;
  WriteLn(Test(1));
end."""),

    # dvl-0017 area: Delphi forbids an open array on an inline routine
    ("inline-open-array", "reject", """
function Total(const Items: array of Integer): Integer; inline;
begin
  Result := Length(Items);
end;

begin
  WriteLn(Total([1, 2, 3]));
end."""),

    # varargs is only meaningful on an imported routine
    # Delphi accepts varargs on a routine with a body (dvl-0021)
    ("varargs-without-external", "accept", """
function Broken(Fmt: PAnsiChar): Integer; cdecl; varargs;
begin
  Result := 0;
end;

begin
  WriteLn(Broken('x'));
end."""),

    ("asm-routine-ok", "accept", """
function Echo(X: NativeInt): NativeInt; assembler;
asm
  MOV RAX, RCX
end;

begin
  WriteLn(Echo(7));
end."""),

    # Delphi requires a named type for a procedural reference variable
    ("anonymous-reference-var", "reject", """
var
  Step: reference to procedure;
begin
  Step := procedure
    begin
      WriteLn(1);
    end;
  Step();
end."""),

    # Delphi rejects a constant shift count at or past the width of the type
    ("shift-count-past-width", "reject", """
var
  Value, Shifted: Cardinal;
begin
  Value := 1;
  Shifted := Value shr 64;
  WriteLn(Shifted);
end."""),

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
    # Delphi accepts an out-of-range element in a set literal (dvl-0022)
    ("set-element-out-of-range", "accept", """
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
    # dvl-0027: no candidate is closer to a float literal, so Delphi refuses to
    # choose - and choosing silently is the defect
    ("double-currency-float-literal", "reject", """
function Pick(const V: Double): Integer; overload;
begin
  Result := 1;
end;

function Pick(const V: Currency): Integer; overload;
begin
  Result := 2;
end;

begin
  WriteLn(Pick(1.5));
end."""),

    ("generic-param-named-integer", "accept", """
type
  TBox<Integer> = record
    function Take: Integer;
  end;

function TBox<Integer>.Take: Integer;
begin
  Result := Default(Integer);
end;

var
  B: TBox<Byte>;
begin
  WriteLn(SizeOf(B.Take));
end."""),

    ("overload-by-param-mode", "reject", """
function Pick(const V: Int64): Integer; overload;
begin
  Result := 1;
end;

function Pick(var V: Int64): Integer; overload;
begin
  Result := 2;
end;

var
  X: Int64;
begin
  X := 7;
  WriteLn(Pick(X));
end."""),

    ("case-string-selector", "reject", """
var
  S: string;
begin
  S := 'a';
  case S of
    'a': WriteLn('one');
  end;
end."""),

    ("duplicate-case-label", "reject", """
var
  X: Integer;
begin
  X := 1;
  case X of
    1: WriteLn('one');
    1: WriteLn('again');
  end;
end."""),

    ("array-const-wrong-count", "reject", """
const
  Items: array[0..1] of Integer = (1, 2, 3);
begin
  WriteLn(Items[0]);
end."""),

    ("assign-to-const-param", "reject", """
procedure Touch(const V: Integer);
begin
  V := 1;
end;

begin
  Touch(7);
  WriteLn('done');
end."""),

    ("exit-with-value-in-procedure", "reject", """
procedure Touch;
begin
  Exit(5);
end;

begin
  Touch;
  WriteLn('done');
end."""),

    ("threadvar-inside-routine", "reject", """
procedure Touch;
threadvar
  Slot: Integer;
begin
  Slot := 1;
  WriteLn(Slot);
end;

begin
  Touch;
end."""),

    ("helper-for-helper", "reject", """
type
  TBox = record
    Slot: Integer;
  end;
  TBoxHelper = record helper for TBox
    function Ask: Integer;
  end;
  TSecond = record helper for TBoxHelper
    function Ask2: Integer;
  end;

function TBoxHelper.Ask: Integer;
begin
  Result := 1;
end;

function TSecond.Ask2: Integer;
begin
  Result := 2;
end;

begin
  WriteLn('done');
end."""),

    ("supports-interface-without-guid", "reject", """
type
  IPlain = interface
    procedure Touch;
  end;
  TThing = class(TInterfacedObject, IPlain)
    procedure Touch;
  end;

procedure TThing.Touch;
begin
end;

var
  Held: IPlain;
begin
  WriteLn(Supports(TThing.Create, IPlain, Held));
end."""),

    ("goto-into-loop", "accept", """
var
  I: Integer;
label
  Inside;
begin
  goto Inside;
  for I := 1 to 2 do
  begin
Inside:
    WriteLn(I);
  end;
end."""),

    ("class-var-in-record", "accept", """
type
  TBox = record
    class var Shared: Integer;
    class function Ask: Integer; static;
  end;

class function TBox.Ask: Integer;
begin
  Result := Shared;
end;

begin
  TBox.Shared := 7;
  WriteLn(TBox.Ask);
end."""),

    ("absolute-over-local", "accept", """
var
  Wide: Integer;
  Low: Byte absolute Wide;
begin
  Wide := $01020304;
  WriteLn(Low);
end."""),

    ("pchar-from-literal", "accept", """
var
  P: PChar;
begin
  P := 'literal';
  WriteLn(P[0]);
end."""),

    ("inherited-in-class-method", "accept", """
type
  TBase = class
    class function Ask: Integer; virtual;
  end;
  TLeaf = class(TBase)
    class function Ask: Integer; override;
  end;

class function TBase.Ask: Integer;
begin
  Result := 1;
end;

class function TLeaf.Ask: Integer;
begin
  Result := inherited Ask + 1;
end;

begin
  WriteLn(TLeaf.Ask);
end."""),

    ("nested-routine-address-to-global-var", "reject", """
type
  TStep = procedure;

var
  Step: TStep;

procedure Host;
  procedure Inner;
  begin
    WriteLn('inner');
  end;
begin
  Step := Inner;
end;

begin
  Host;
  Step;
end."""),

    ("abstract-class-instantiated", "accept", """
type
  TBase = class
    procedure Touch; virtual; abstract;
  end;

var
  Held: TBase;
begin
  { a warning, not an error: the call would fail, the construction may not }
  Held := TBase.Create;
  Held.Free;
  WriteLn('done');
end."""),

    ("inline-var-in-except", "accept", """
begin
  try
    raise Exception.Create('x');
  except
    on E: Exception do
    begin
      var Seen := Length(E.Message);
      WriteLn(Seen);
    end;
  end;
end."""),

    ("attribute-marker-type", "accept", """
type
  MarkAttribute = class(TCustomAttribute)
  end;

type
  [Mark]
  TBox = class
  end;

begin
  WriteLn('ok');
end."""),
    ("attribute-ctor-type", "accept", """
type
  MarkAttribute = class(TCustomAttribute)
  public
    constructor Create; overload;
    constructor Create(const V: string); overload;
  end;

constructor MarkAttribute.Create;
begin
  inherited Create;
end;

constructor MarkAttribute.Create(const V: string);
begin
  inherited Create;
end;

type
  [Mark]
  TBox = class
  end;

begin
  WriteLn('ok');
end."""),
    ("attribute-marker-field", "accept", """
type
  MarkAttribute = class(TCustomAttribute)
  end;

type
  TBox = class
  public
    [Mark] Slot: Integer;
  end;

begin
  WriteLn('ok');
end."""),
    ("attribute-ctor-field", "accept", """
type
  MarkAttribute = class(TCustomAttribute)
  public
    constructor Create; overload;
    constructor Create(const V: string); overload;
  end;

constructor MarkAttribute.Create;
begin
  inherited Create;
end;

constructor MarkAttribute.Create(const V: string);
begin
  inherited Create;
end;

type
  TBox = class
  public
    [Mark] Slot: Integer;
  end;

begin
  WriteLn('ok');
end."""),
    ("attribute-marker-property", "accept", """
type
  MarkAttribute = class(TCustomAttribute)
  end;

type
  TBox = class
  private
    FSlot: Integer;
  public
    [Mark]
    property Slot: Integer read FSlot;
  end;

begin
  WriteLn('ok');
end."""),
    ("attribute-ctor-property", "accept", """
type
  MarkAttribute = class(TCustomAttribute)
  public
    constructor Create; overload;
    constructor Create(const V: string); overload;
  end;

constructor MarkAttribute.Create;
begin
  inherited Create;
end;

constructor MarkAttribute.Create(const V: string);
begin
  inherited Create;
end;

type
  TBox = class
  private
    FSlot: Integer;
  public
    [Mark]
    property Slot: Integer read FSlot;
  end;

begin
  WriteLn('ok');
end."""),
    ("attribute-marker-method", "accept", """
type
  MarkAttribute = class(TCustomAttribute)
  end;

type
  TBox = class
  public
    [Mark]
    procedure Touch;
  end;

procedure TBox.Touch;
begin
end;

begin
  WriteLn('ok');
end."""),
    ("attribute-ctor-method", "accept", """
type
  MarkAttribute = class(TCustomAttribute)
  public
    constructor Create; overload;
    constructor Create(const V: string); overload;
  end;

constructor MarkAttribute.Create;
begin
  inherited Create;
end;

constructor MarkAttribute.Create(const V: string);
begin
  inherited Create;
end;

type
  TBox = class
  public
    [Mark]
    procedure Touch;
  end;

procedure TBox.Touch;
begin
end;

begin
  WriteLn('ok');
end."""),
    ("attribute-marker-parameter", "accept", """
type
  MarkAttribute = class(TCustomAttribute)
  end;

procedure Touch([Mark] const V: Integer);
begin
end;

begin
  Touch(1);
  WriteLn('ok');
end."""),
    ("attribute-ctor-parameter", "accept", """
type
  MarkAttribute = class(TCustomAttribute)
  public
    constructor Create; overload;
    constructor Create(const V: string); overload;
  end;

constructor MarkAttribute.Create;
begin
  inherited Create;
end;

constructor MarkAttribute.Create(const V: string);
begin
  inherited Create;
end;

procedure Touch([Mark] const V: Integer);
begin
end;

begin
  Touch(1);
  WriteLn('ok');
end."""),
    ("attribute-marker-inline-var", "accept", """
type
  MarkAttribute = class(TCustomAttribute)
  end;

begin
  var [Mark] Slot: Integer;
  Slot := 1;
  WriteLn(Slot);
end."""),
    ("attribute-ctor-inline-var", "accept", """
type
  MarkAttribute = class(TCustomAttribute)
  public
    constructor Create; overload;
    constructor Create(const V: string); overload;
  end;

constructor MarkAttribute.Create;
begin
  inherited Create;
end;

constructor MarkAttribute.Create(const V: string);
begin
  inherited Create;
end;

begin
  var [Mark] Slot: Integer;
  Slot := 1;
  WriteLn(Slot);
end."""),

    ("bare-method-into-reference", "reject", """
type
  TStep = reference to function: Integer;

  TBox = class
  public
    Slot: Integer;
    function Make: TStep;
  end;

function TBox.Make: TStep;
begin
  Result :=
    function: Integer
    begin
      Result := Slot;
    end;
end;

var
  Held: TBox;
  Step: TStep;
begin
  Held := TBox.Create;
  try
    Held.Slot := 1;
    Step := Held.Make;
    WriteLn(Step());
  finally
    Held.Free;
  end;
end."""),

    ("record-operator-initialize", "accept", """
type
  TRec = record
    Slot: Integer;
    class operator Initialize(out Dest: TRec);
  end;

class operator TRec.Initialize(out Dest: TRec);
begin
  Dest.Slot := 5;
end;

var
  R: TRec;
begin
  WriteLn(R.Slot);
end."""),

    ("record-operator-finalize", "accept", """
type
  TRec = record
    Slot: Integer;
    class operator Finalize(var Dest: TRec);
  end;

class operator TRec.Finalize(var Dest: TRec);
begin
  WriteLn('gone');
end;

var
  R: TRec;
begin
  R.Slot := 1;
  WriteLn(R.Slot);
end."""),

    ("record-operator-assign", "accept", """
type
  TRec = record
    Slot: Integer;
    class operator Assign(var Dest: TRec; var Src: TRec);
  end;

class operator TRec.Assign(var Dest: TRec; var Src: TRec);
begin
  Dest.Slot := Src.Slot + 1;
end;

var
  A, B: TRec;
begin
  A.Slot := 1;
  B := A;
  WriteLn(B.Slot);
end."""),

    ("record-operator-assign-plain-const", "reject", """
type
  TRec = record
    Slot: Integer;
    class operator Assign(var Dest: TRec; const Src: TRec);
  end;

class operator TRec.Assign(var Dest: TRec; const Src: TRec);
begin
  Dest.Slot := Src.Slot;
end;

var
  A, B: TRec;
begin
  A.Slot := 1;
  B := A;
  WriteLn(B.Slot);
end."""),

    ("constref-parameter", "accept", """
procedure Touch(const [ref] V: Integer);
begin
  WriteLn(V);
end;

begin
  Touch(7);
end."""),

    ("constref-record-parameter", "accept", """
type
  TRec = record
    Slot: Integer;
  end;

procedure Touch(const [ref] V: TRec);
begin
  WriteLn(V.Slot);
end;

var
  R: TRec;
begin
  R.Slot := 7;
  Touch(R);
end."""),

    ("helper-name-as-type", "reject", """
type
  TBox = class
  end;
  TBoxHelper = class helper for TBox
  public
    class var HelperShared: Integer;
  end;

begin
  TBoxHelper.HelperShared := 5;
  WriteLn(TBoxHelper.HelperShared);
end."""),

    ("attribute-on-class-var", "accept", """
type
  MarkAttribute = class(TCustomAttribute)
  public
    Tag: Integer;
    constructor Create(ATag: Integer);
  end;

constructor MarkAttribute.Create(ATag: Integer);
begin
  inherited Create;
  Tag := ATag;
end;

type
  TBox = class
  public
    [Mark(1)]
    class var Shared: Integer;
  end;

begin
  TBox.Shared := 7;
  WriteLn(TBox.Shared);
end."""),

    ("int64-arg-vs-integer-cardinal", "accept", """
function Pick(const V: Integer): Integer; overload;
begin
  Result := 1;
end;

function Pick(const V: Cardinal): Integer; overload;
begin
  Result := 2;
end;

var
  W: Int64;
begin
  W := 7;
  WriteLn(Pick(W));
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
