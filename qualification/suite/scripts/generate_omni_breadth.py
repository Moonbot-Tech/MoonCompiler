#!/usr/bin/env python3
"""Generate the broad, cross-mechanism layer of Omni.

The committed Pascal include is the product.  The generator makes thousands
of distinct source forms reviewable and reproducible; it is not counted as a
test by itself.  Delphi 12.2 Win64 supplies reference values where its behavior
is the contract.  Language semantics and explicit invariants override Delphi
for known Delphi defects and implementation-dependent lifetime details.
"""

from __future__ import annotations

import argparse
import json
import re
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OMNI = ROOT / "tests" / "mega" / "omni"
GENERATED = OMNI / "omni_generated_breadth.inc"
PROBE = OMNI / "omni_generated_breadth_oracle.dpr"
ORACLE = OMNI / "omni_generated_breadth_oracle.json"
MANIFEST = OMNI / "omni_generated_breadth_manifest.json"


class Emitter:
    def __init__(self, oracle: dict[str, str]):
        self.lines: list[str] = []
        self.oracle = oracle
        self.names: list[str] = []
        self.families: Counter[str] = Counter()

    def line(self, value: str = "") -> None:
        self.lines.append(value)

    def check(
        self,
        family: str,
        name: str,
        expression: str,
        indent: str = "  ",
        expected: str | None = None,
    ) -> None:
        if name in self.names:
            raise ValueError(f"duplicate check name: {name}")
        self.names.append(name)
        self.families[family] += 1
        expected = expected or self.oracle.get(name, "0000000000000000")
        self.line(
            f"{indent}GeneratedCheckU('{name}', UInt64({expression}), "
            f"UInt64(${expected}));"
        )


def emit_support(e: Emitter) -> None:
    e.line("type")
    e.line("  IGBValue = interface")
    e.line("    ['{E74DCE82-7979-43B0-9540-A65B699EBF62}']")
    e.line("    function GetValue: Integer;")
    e.line("  end;")
    e.line()
    e.line("  TGBValueObject = class(TInterfacedObject, IGBValue)")
    e.line("  private")
    e.line("    FValue: Integer;")
    e.line("  public")
    e.line("    class var Alive: Integer;")
    e.line("    constructor Create(AValue: Integer);")
    e.line("    destructor Destroy; override;")
    e.line("    function GetValue: Integer;")
    e.line("  end;")
    e.line()
    e.line("  TGBBase = class")
    e.line("  protected")
    e.line("    FValue: Integer;")
    e.line("  public")
    e.line("    constructor Create(AValue: Integer); virtual;")
    e.line("    function Step(X: Integer): Integer; virtual;")
    e.line("    function CallInherited(X: Integer): Integer; virtual;")
    e.line("  end;")
    e.line("  TGBMid = class(TGBBase)")
    e.line("    function Step(X: Integer): Integer; override;")
    e.line("    function CallInherited(X: Integer): Integer; override;")
    e.line("  end;")
    e.line("  TGBLeaf = class(TGBMid)")
    e.line("    function Step(X: Integer): Integer; override;")
    e.line("    function CallInherited(X: Integer): Integer; override;")
    e.line("  end;")
    e.line("  TGBBaseClass = class of TGBBase;")
    e.line()
    e.line("  TGBManaged = record")
    e.line("    S: AnsiString;")
    e.line("    U: UnicodeString;")
    e.line("    A: TArray<Integer>;")
    e.line("    I: IGBValue;")
    e.line("    N: Integer;")
    e.line("  end;")
    e.line("  TGBManagedArray = array of TGBManaged;")
    e.line("  TGBIntArray = array of Integer;")
    e.line("  TGBStringBox = record")
    e.line("    A: AnsiString;")
    e.line("    U: UnicodeString;")
    e.line("    S: ShortString;")
    e.line("  end;")
    e.line("  TGBLegacyRec = record")
    e.line("    A: Integer;")
    e.line("    B: Word;")
    e.line("    C: Byte;")
    e.line("    Text: AnsiString;")
    e.line("  end;")
    e.line()
    e.line("  TGBVariant = packed record")
    e.line("    case Byte of")
    e.line("      0: (Q: UInt64);")
    e.line("      1: (D: Double);")
    e.line("      2: (W: array[0..3] of Word);")
    e.line("      3: (B: array[0..7] of Byte);")
    e.line("  end;")
    e.line()
    e.line("  TGBEnum = (gbeZero, gbeOne, gbeThree = 3, gbeSeven = 7);")
    e.line("  TGBEnumSet = set of TGBEnum;")
    e.line("  TGBSubrange = -17..23;")
    e.line("  TGBDenseEnum = (gbdZero, gbdOne, gbdTwo, gbdThree, gbdFour, gbdFive);")
    e.line("  TGBByteSet = set of Byte;")
    e.line()
    e.line("  TGBNumber = record")
    e.line("    Raw: Int64;")
    e.line("    class operator Add(const A, B: TGBNumber): TGBNumber;")
    e.line("    class operator Multiply(const A: TGBNumber; B: Integer): TGBNumber;")
    e.line("    class operator Implicit(A: Integer): TGBNumber;")
    e.line("    class operator Explicit(const A: TGBNumber): Int64;")
    e.line("  end;")
    e.line("  TGBNumberHelper = record helper for TGBNumber")
    e.line("    function Twisted(Factor: Integer): Int64;")
    e.line("  end;")
    e.line()
    e.line("  TGBPropertyBox = class")
    e.line("  private")
    e.line("    FData: array[0..15] of Integer;")
    e.line("    function GetItem(Index: Integer): Integer;")
    e.line("    procedure SetItem(Index, Value: Integer);")
    e.line("  public")
    e.line("    property Items[Index: Integer]: Integer read GetItem write SetItem; default;")
    e.line("  end;")
    e.line()
    e.line("  TGBInlineConstOwner = class")
    e.line("  private")
    e.line("    FIconSize: Integer;")
    e.line("    FIconGap: Integer;")
    e.line("  public")
    e.line("    constructor Create(AIconSize, AIconGap: Integer);")
    e.line("    function Minimum: Integer;")
    e.line("  end;")
    e.line()
    e.line("  TGBGenericBox<T> = record")
    e.line("    Value: T;")
    e.line("    class function Make(const AValue: T): TGBGenericBox<T>; static;")
    e.line("    function Read: T;")
    e.line("  end;")
    e.line()
    e.line("  TGBGenericClass<T> = class")
    e.line("  private")
    e.line("    FValue: T;")
    e.line("  public")
    e.line("    constructor Create(const AValue: T);")
    e.line("    function Read: T;")
    e.line("  end;")
    e.line()
    e.line("  TGBGenericOps<T> = record")
    e.line("    class function Echo(const Value: T): T; static;")
    e.line("    class function InlineConstValue(Base: Integer): Integer; static;")
    e.line("    class procedure Swap(var A, B: T); static;")
    e.line("  end;")
    e.line()
    e.line("{$ifndef GB_SKIP_MANAGED_RECORD}")
    e.line("  TGBTracked = record")
    e.line("    Value: Integer;")
    e.line("    class operator Initialize({$ifdef FPC}var{$else}out{$endif} Dest: TGBTracked);")
    e.line("    class operator Finalize(var Dest: TGBTracked);")
    e.line("{$ifdef FPC}")
    e.line("    class operator Copy(constref Src: TGBTracked; var Dest: TGBTracked);")
    e.line("{$else}")
    e.line("    class operator Assign(var Dest: TGBTracked; const [ref] Src: TGBTracked);")
    e.line("{$endif}")
    e.line("  end;")
    e.line("  TGBTrackedArray = array of TGBTracked;")
    e.line("{$endif}")
    e.line()
    e.line("  TGBCallRec = record")
    e.line("    I: Integer;")
    e.line("    U: UInt64;")
    e.line("    S: AnsiString;")
    e.line("  end;")
    e.line()
    e.line("  TGBOrdinalSource = record")
    e.line("  private")
    e.line("    function GetSigned: Integer;")
    e.line("    function GetUnsigned: UInt64;")
    e.line("  public")
    e.line("    SignedField: Integer;")
    e.line("    UnsignedField: UInt64;")
    e.line("    property SignedProperty: Integer read GetSigned;")
    e.line("    property UnsignedProperty: UInt64 read GetUnsigned;")
    e.line("  end;")
    e.line()
    e.line("  TGBFloatRec = packed record")
    e.line("    S: Single;")
    e.line("    D: Double;")
    e.line("    I: Int64;")
    e.line("  end;")
    e.line()
    e.line("  TGBPlainCallback = function(A, B: Integer): Integer;")
    e.line()
    e.line("  TGBLifecycle = class")
    e.line("  public")
    e.line("    class var Alive, Created, Destroyed, Aftered, Befored: Integer;")
    e.line("    Value: Integer;")
    e.line("    constructor Create(AValue: Integer; ShouldFail: Boolean);")
    e.line("    destructor Destroy; override;")
    e.line("    procedure AfterConstruction; override;")
    e.line("    procedure BeforeDestruction; override;")
    e.line("  end;")
    e.line()
    e.line("  TGBThreadProbe = class(TThread)")
    e.line("  public")
    e.line("    Seed, Iterations: Integer;")
    e.line("    Digest: UInt64;")
    e.line("    Text: AnsiString;")
    e.line("    constructor Create(ASeed, AIterations: Integer);")
    e.line("    procedure Execute; override;")
    e.line("  end;")
    e.line()
    e.line("{$ifdef HAS_ANON}")
    e.line("  TGBIntFunc = reference to function(X: Integer): Integer;")
    e.line("  TGBFuncBox = record")
    e.line("    Func: TGBIntFunc;")
    e.line("    Tag: AnsiString;")
    e.line("  end;")
    e.line("  TGBClosureOwner = class")
    e.line("  private")
    e.line("    FBase: Integer;")
    e.line("    FText: AnsiString;")
    e.line("  public")
    e.line("    constructor Create(ABase: Integer);")
    e.line("    function MakeFunc(Bias: Integer): TGBIntFunc;")
    e.line("  end;")
    e.line("{$endif}")
    e.line()
    e.line("const")
    e.line("  GBUntypedOne = 1;")
    e.line("  GBTypedIntegerOne: Integer = 1;")
    e.line("  GBTypedInt64One: Int64 = 1;")
    e.line("  GBTypedUInt64One: UInt64 = 1;")
    e.line()
    e.line("{$ifndef GB_SKIP_MANAGED_RECORD}")
    e.line("var")
    e.line("  GBTrackedInit, GBTrackedFini, GBTrackedAssign: Integer;")
    e.line("{$endif}")
    e.line()
    e.line("threadvar")
    e.line("  GBThreadOrdinal: Integer;")
    e.line("  GBThreadText: AnsiString;")
    e.line()
    e.line("constructor TGBValueObject.Create(AValue: Integer);")
    e.line("begin")
    e.line("  inherited Create;")
    e.line("  Inc(Alive);")
    e.line("  FValue := AValue;")
    e.line("end;")
    e.line()
    e.line("destructor TGBValueObject.Destroy;")
    e.line("begin")
    e.line("  Dec(Alive);")
    e.line("  inherited Destroy;")
    e.line("end;")
    e.line()
    e.line("function TGBValueObject.GetValue: Integer;")
    e.line("begin")
    e.line("  Result := FValue;")
    e.line("end;")
    e.line()
    e.line("constructor TGBBase.Create(AValue: Integer);")
    e.line("begin")
    e.line("  inherited Create;")
    e.line("  FValue := AValue;")
    e.line("end;")
    e.line()
    e.line("function TGBBase.Step(X: Integer): Integer;")
    e.line("begin")
    e.line("  Result := FValue + X + 1;")
    e.line("end;")
    e.line()
    e.line("function TGBBase.CallInherited(X: Integer): Integer;")
    e.line("begin")
    e.line("  Result := Step(X) + 10;")
    e.line("end;")
    e.line()
    e.line("function TGBMid.Step(X: Integer): Integer;")
    e.line("begin")
    e.line("  Result := inherited Step(X) * 3 + 2;")
    e.line("end;")
    e.line()
    e.line("function TGBMid.CallInherited(X: Integer): Integer;")
    e.line("begin")
    e.line("  Result := inherited CallInherited(X) + inherited Step(X) + 20;")
    e.line("end;")
    e.line()
    e.line("function TGBLeaf.Step(X: Integer): Integer;")
    e.line("begin")
    e.line("  Result := inherited Step(X) xor $55AA;")
    e.line("end;")
    e.line()
    e.line("function TGBLeaf.CallInherited(X: Integer): Integer;")
    e.line("begin")
    e.line("  Result := inherited CallInherited(X) + inherited Step(X) + 30;")
    e.line("end;")
    e.line()
    e.line("class function TGBGenericBox<T>.Make(const AValue: T): TGBGenericBox<T>;")
    e.line("begin")
    e.line("  Result.Value := AValue;")
    e.line("end;")
    e.line()
    e.line("function TGBGenericBox<T>.Read: T;")
    e.line("begin")
    e.line("  Result := Value;")
    e.line("end;")
    e.line()
    e.line("constructor TGBGenericClass<T>.Create(const AValue: T);")
    e.line("begin")
    e.line("  inherited Create;")
    e.line("  FValue := AValue;")
    e.line("end;")
    e.line()
    e.line("function TGBGenericClass<T>.Read: T;")
    e.line("begin")
    e.line("  Result := FValue;")
    e.line("end;")
    e.line()
    e.line("class function TGBGenericOps<T>.Echo(const Value: T): T;")
    e.line("begin")
    e.line("  Result := Value;")
    e.line("end;")
    e.line()
    e.line("class function TGBGenericOps<T>.InlineConstValue(Base: Integer): Integer;")
    e.line("begin")
    e.line("  Result := Base;")
    e.line("  const RuntimeValue = Base + SizeOf(T);")
    e.line("  const RuntimeTyped: Integer = RuntimeValue * 2;")
    e.line("  Result := Result + RuntimeValue + RuntimeTyped;")
    e.line("end;")
    e.line()
    e.line("class procedure TGBGenericOps<T>.Swap(var A, B: T);")
    e.line("var Temp: T;")
    e.line("begin")
    e.line("  Temp := A;")
    e.line("  A := B;")
    e.line("  B := Temp;")
    e.line("end;")
    e.line()
    e.line("{$ifndef GB_SKIP_MANAGED_RECORD}")
    e.line("class operator TGBTracked.Initialize({$ifdef FPC}var{$else}out{$endif} Dest: TGBTracked);")
    e.line("begin")
    e.line("  Dest.Value := 7;")
    e.line("  Inc(GBTrackedInit);")
    e.line("end;")
    e.line()
    e.line("class operator TGBTracked.Finalize(var Dest: TGBTracked);")
    e.line("begin")
    e.line("  Inc(GBTrackedFini);")
    e.line("end;")
    e.line()
    e.line("{$ifdef FPC}")
    e.line("class operator TGBTracked.Copy(constref Src: TGBTracked; var Dest: TGBTracked);")
    e.line("{$else}")
    e.line("class operator TGBTracked.Assign(var Dest: TGBTracked; const [ref] Src: TGBTracked);")
    e.line("{$endif}")
    e.line("begin")
    e.line("  Dest.Value := Src.Value;")
    e.line("  Inc(GBTrackedAssign);")
    e.line("end;")
    e.line("{$endif}")
    e.line()
    e.line("constructor TGBLifecycle.Create(AValue: Integer; ShouldFail: Boolean);")
    e.line("begin")
    e.line("  inherited Create;")
    e.line("  Inc(Created);")
    e.line("  Inc(Alive);")
    e.line("  Value := AValue;")
    e.line("  if ShouldFail then raise EArgumentException.Create('lifecycle');")
    e.line("end;")
    e.line()
    e.line("destructor TGBLifecycle.Destroy;")
    e.line("begin")
    e.line("  Inc(Destroyed);")
    e.line("  Dec(Alive);")
    e.line("  inherited Destroy;")
    e.line("end;")
    e.line()
    e.line("procedure TGBLifecycle.AfterConstruction;")
    e.line("begin")
    e.line("  Inc(Aftered);")
    e.line("  inherited AfterConstruction;")
    e.line("end;")
    e.line()
    e.line("procedure TGBLifecycle.BeforeDestruction;")
    e.line("begin")
    e.line("  Inc(Befored);")
    e.line("  inherited BeforeDestruction;")
    e.line("end;")
    e.line()
    e.line("class operator TGBNumber.Add(const A, B: TGBNumber): TGBNumber;")
    e.line("begin")
    e.line("  Result.Raw := A.Raw + B.Raw;")
    e.line("end;")
    e.line()
    e.line("class operator TGBNumber.Multiply(const A: TGBNumber; B: Integer): TGBNumber;")
    e.line("begin")
    e.line("  Result.Raw := A.Raw * B;")
    e.line("end;")
    e.line()
    e.line("class operator TGBNumber.Implicit(A: Integer): TGBNumber;")
    e.line("begin")
    e.line("  Result.Raw := A;")
    e.line("end;")
    e.line()
    e.line("class operator TGBNumber.Explicit(const A: TGBNumber): Int64;")
    e.line("begin")
    e.line("  Result := A.Raw;")
    e.line("end;")
    e.line()
    e.line("function TGBNumberHelper.Twisted(Factor: Integer): Int64;")
    e.line("begin")
    e.line("  Result := (Self.Raw * Factor) xor (Self.Raw shr 7);")
    e.line("end;")
    e.line()
    e.line("function TGBPropertyBox.GetItem(Index: Integer): Integer;")
    e.line("begin")
    e.line("  Result := FData[Index and 15];")
    e.line("end;")
    e.line()
    e.line("procedure TGBPropertyBox.SetItem(Index, Value: Integer);")
    e.line("begin")
    e.line("  FData[Index and 15] := Value;")
    e.line("end;")
    e.line()
    e.line("constructor TGBInlineConstOwner.Create(AIconSize, AIconGap: Integer);")
    e.line("begin")
    e.line("  inherited Create;")
    e.line("  FIconSize := AIconSize;")
    e.line("  FIconGap := AIconGap;")
    e.line("end;")
    e.line()
    e.line("function TGBInlineConstOwner.Minimum: Integer;")
    e.line("begin")
    e.line("  Result := 1;")
    e.line("  const MinInner = 2 * FIconSize + FIconGap;")
    e.line("  Result := Result + MinInner;")
    e.line("end;")
    e.line()
    e.line("function GBHashAnsi(const S: AnsiString): UInt64;")
    e.line("var")
    e.line("  I: Integer;")
    e.line("begin")
    e.line("  Result := UInt64($CBF29CE484222325);")
    e.line("  for I := 1 to Length(S) do")
    e.line("    Result := (Result xor Byte(S[I])) * UInt64($100000001B3);")
    e.line("end;")
    e.line()
    e.line("function GBHashUnicode(const S: UnicodeString): UInt64;")
    e.line("var")
    e.line("  I: Integer;")
    e.line("begin")
    e.line("  Result := UInt64($CBF29CE484222325);")
    e.line("  for I := 1 to Length(S) do")
    e.line("  begin")
    e.line("    Result := (Result xor Word(S[I])) * UInt64($100000001B3);")
    e.line("    Result := (Result xor (Word(S[I]) shr 8)) * UInt64($100000001B3);")
    e.line("  end;")
    e.line("end;")
    e.line()
    e.line("function GBMakeManaged(Seed: Integer): TGBManaged;")
    e.line("begin")
    e.line("  Result.S := AnsiString('a') + AnsiString(IntToStr(Seed));")
    e.line("  Result.U := UnicodeString('u') + UnicodeString(IntToStr(Seed * 3));")
    e.line("  SetLength(Result.A, 3);")
    e.line("  Result.A[0] := Seed;")
    e.line("  Result.A[1] := Seed * 7;")
    e.line("  Result.A[2] := Seed xor $55AA;")
    e.line("  Result.I := TGBValueObject.Create(Seed * 11);")
    e.line("  Result.N := Seed * 13;")
    e.line("end;")
    e.line()
    e.line("function GBManagedDigest(const M: TGBManaged): UInt64;")
    e.line("begin")
    e.line("  Result := GBHashAnsi(M.S) xor (GBHashUnicode(M.U) shl 1) xor")
    e.line("    UInt64(M.A[0] * 3 + M.A[1] * 5 + M.A[2] * 7 + M.I.GetValue * 11 + M.N * 13);")
    e.line("end;")
    e.line()
    e.line("function GBIdentity(X: Integer): Integer; inline;")
    e.line("begin")
    e.line("  Result := X;")
    e.line("end;")
    e.line()
    e.line("function GBNoInline(X: Integer): Integer;")
    e.line("begin")
    e.line("  Result := X xor Integer(RtZero);")
    e.line("end;")
    e.line()
    e.line("function GBUInt64NoInline(X: UInt64): UInt64;")
    e.line("begin")
    e.line("  Result := X xor UInt64(RtZero);")
    e.line("end;")
    e.line()
    e.line("function GBOpenArrayDigest(const A: array of Integer): UInt64;")
    e.line("var I: Integer;")
    e.line("begin")
    e.line("  Result := UInt64($CBF29CE484222325);")
    e.line("  for I := Low(A) to High(A) do")
    e.line("    Result := (Result xor UInt32(A[I])) * UInt64($100000001B3);")
    e.line("end;")
    e.line()
    e.line("procedure GBMutateArray(var A: TGBIntArray; Delta: Integer);")
    e.line("var I: Integer;")
    e.line("begin")
    e.line("  for I := 0 to High(A) do")
    e.line("    A[I] := A[I] + Delta * (I + 1);")
    e.line("end;")
    e.line()
    e.line("procedure GBOutArray(out A: TGBIntArray; Count, Seed: Integer);")
    e.line("var I: Integer;")
    e.line("begin")
    e.line("  SetLength(A, Count);")
    e.line("  for I := 0 to High(A) do A[I] := Seed xor (I * 65537);")
    e.line("end;")
    e.line()
    e.line("function GBReturnArray(Count, Seed: Integer): TGBIntArray;")
    e.line("begin")
    e.line("  GBOutArray(Result, Count, Seed);")
    e.line("end;")
    e.line()
    e.line("function GBInterfaceByValue(I: IGBValue; X: Integer): Integer;")
    e.line("begin")
    e.line("  Result := I.GetValue + X;")
    e.line("end;")
    e.line()
    e.line("function GBInterfaceByConst(const I: IGBValue; X: Integer): Integer;")
    e.line("begin")
    e.line("  Result := I.GetValue xor X;")
    e.line("end;")
    e.line()
    e.line("{$ifdef HAS_ANON}")
    e.line("constructor TGBClosureOwner.Create(ABase: Integer);")
    e.line("begin")
    e.line("  inherited Create;")
    e.line("  FBase := ABase;")
    e.line("  FText := AnsiString('owner:') + AnsiString(IntToStr(ABase));")
    e.line("end;")
    e.line()
    e.line("function TGBClosureOwner.MakeFunc(Bias: Integer): TGBIntFunc;")
    e.line("var Local: Integer; Hold: AnsiString;")
    e.line("begin")
    e.line("  Local := Bias;")
    e.line("  Hold := FText;")
    e.line("  Result := function(X: Integer): Integer")
    e.line("    begin")
    e.line("      Inc(Local, X);")
    e.line("      Result := FBase + Local + Length(Hold);")
    e.line("    end;")
    e.line("end;")
    e.line()
    e.line("function GBCallFunc(const F: TGBIntFunc; X: Integer): Integer;")
    e.line("begin")
    e.line("  Result := F(X);")
    e.line("end;")
    e.line("{$endif}")
    e.line()
    e.line("procedure GBInterfaceOut(out I: IGBValue; Value: Integer);")
    e.line("begin")
    e.line("  I := TGBValueObject.Create(Value);")
    e.line("end;")
    e.line()
    e.line("procedure GBUntypedXor(var Value; Count: Integer; Seed: Byte);")
    e.line("var I: Integer; P: PByte;")
    e.line("begin")
    e.line("  P := @Value;")
    e.line("  for I := 0 to Count - 1 do P[I] := P[I] xor Byte(Seed + I * 17);")
    e.line("end;")
    e.line()
    e.line("function GBArrayConstDigest(const Values: array of const): UInt64;")
    e.line("var I: Integer;")
    e.line("begin")
    e.line("  Result := UInt64($CBF29CE484222325);")
    e.line("  for I := 0 to High(Values) do")
    e.line("  begin")
    e.line("    case Values[I].VType of")
    e.line("      vtInteger:")
    e.line("        begin")
    e.line("          Result := (Result xor 1) * UInt64($100000001B3);")
    e.line("          Result := (Result xor UInt32(Values[I].VInteger)) * UInt64($100000001B3);")
    e.line("        end;")
    e.line("      vtBoolean:")
    e.line("        begin")
    e.line("          Result := (Result xor 2) * UInt64($100000001B3);")
    e.line("          Result := (Result xor Ord(Values[I].VBoolean)) * UInt64($100000001B3);")
    e.line("        end;")
    e.line("      vtInt64:")
    e.line("        begin")
    e.line("          Result := (Result xor 3) * UInt64($100000001B3);")
    e.line("          Result := (Result xor UInt64(Values[I].VInt64^)) * UInt64($100000001B3);")
    e.line("        end;")
    e.line("      vtAnsiString:")
    e.line("        begin")
    e.line("          Result := (Result xor 4) * UInt64($100000001B3);")
    e.line("          Result := Result xor GBHashAnsi(AnsiString(Values[I].VAnsiString));")
    e.line("        end;")
    e.line("      vtUnicodeString:")
    e.line("        begin")
    e.line("          Result := (Result xor 5) * UInt64($100000001B3);")
    e.line("          Result := Result xor GBHashUnicode(UnicodeString(Values[I].VUnicodeString));")
    e.line("        end;")
    e.line("    else")
    e.line("      Result := (Result xor $FF) * UInt64($100000001B3);")
    e.line("    end;")
    e.line("  end;")
    e.line("end;")
    e.line()
    e.line("function GBOverload(A: Integer): Int64; overload;")
    e.line("begin")
    e.line("  Result := Int64(A) * 3 + 1;")
    e.line("end;")
    e.line()
    e.line("function TGBOrdinalSource.GetSigned: Integer;")
    e.line("begin")
    e.line("  Result := SignedField;")
    e.line("end;")
    e.line()
    e.line("function TGBOrdinalSource.GetUnsigned: UInt64;")
    e.line("begin")
    e.line("  Result := UnsignedField;")
    e.line("end;")
    e.line()
    e.line("function GBIntegerValue(Value: Integer): Integer;")
    e.line("begin")
    e.line("  Result := Value;")
    e.line("end;")
    e.line()
    e.line("function GBUInt64Value(Value: UInt64): UInt64;")
    e.line("begin")
    e.line("  Result := Value;")
    e.line("end;")
    e.line()
    e.line("function GBOrdinalKind(Value: Integer): UInt64; overload;")
    e.line("begin")
    e.line("  Result := 1;")
    e.line("end;")
    e.line()
    e.line("function GBOrdinalKind(Value: Cardinal): UInt64; overload;")
    e.line("begin")
    e.line("  Result := 2;")
    e.line("end;")
    e.line()
    e.line("function GBOrdinalKind(Value: Int64): UInt64; overload;")
    e.line("begin")
    e.line("  Result := 3;")
    e.line("end;")
    e.line()
    e.line("function GBOrdinalKind(Value: UInt64): UInt64; overload;")
    e.line("begin")
    e.line("  Result := 4;")
    e.line("end;")
    e.line()
    e.line("function GBPairKind(A, B: Int64): UInt64; overload;")
    e.line("begin")
    e.line("  Result := 3;")
    e.line("end;")
    e.line()
    e.line("function GBPairKind(A, B: UInt64): UInt64; overload;")
    e.line("begin")
    e.line("  Result := 4;")
    e.line("end;")
    e.line()
    e.line("function GBOverload(A: Int64; B: Integer = 5): Int64; overload;")
    e.line("begin")
    e.line("  Result := A * 7 + B;")
    e.line("end;")
    e.line()
    e.line("function GBOverload(const A: AnsiString): Int64; overload;")
    e.line("begin")
    e.line("  Result := Int64(GBHashAnsi(A));")
    e.line("end;")
    e.line()
    e.line("function GBMakeCallRec(Seed: Integer): TGBCallRec;")
    e.line("begin")
    e.line("  Result.I := Seed * 3 + 1;")
    e.line("  Result.U := UInt64(UInt32(Seed)) * UInt64($100000001B3);")
    e.line("  Result.S := AnsiString('call:') + AnsiString(IntToStr(Seed));")
    e.line("end;")
    e.line()
    e.line("procedure GBCallMix(const A: TGBCallRec; var B: TGBCallRec; out C: TGBCallRec);")
    e.line("begin")
    e.line("  C.I := A.I xor B.I;")
    e.line("  C.U := A.U + B.U;")
    e.line("  C.S := A.S + AnsiString('|') + B.S;")
    e.line("  B.I := B.I + A.I;")
    e.line("  B.U := B.U xor A.U;")
    e.line("  B.S := B.S + A.S;")
    e.line("end;")
    e.line()
    e.line("function GBCallRecDigest(const R: TGBCallRec): UInt64;")
    e.line("begin")
    e.line("  Result := UInt64(UInt32(R.I)) xor (R.U * UInt64(257)) xor GBHashAnsi(R.S);")
    e.line("end;")
    e.line()
    e.line("function GBPlainCallback(A, B: Integer): Integer;")
    e.line("begin")
    e.line("  Result := (A * 31) xor (B * 17);")
    e.line("end;")
    e.line()
    e.line("function GBInvokeCallback(F: TGBPlainCallback; A, B: Integer): Integer;")
    e.line("begin")
    e.line("  Result := F(A, B);")
    e.line("end;")
    e.line()
    e.line("function GBMakeFloatRec(Seed: Integer): TGBFloatRec;")
    e.line("begin")
    e.line("  Result.S := Seed / 8.0;")
    e.line("  Result.D := Seed * 0.125 + 1024.0;")
    e.line("  Result.I := Int64(Seed) * 1000003;")
    e.line("end;")
    e.line()
    e.line("function GBFloatRecDigest(Value: TGBFloatRec; Extra: Double): UInt64;")
    e.line("var SBits: UInt32; DBits: UInt64;")
    e.line("begin")
    e.line("  Value.D := Value.D + Extra;")
    e.line("  Move(Value.S, SBits, SizeOf(SBits));")
    e.line("  Move(Value.D, DBits, SizeOf(DBits));")
    e.line("  Result := UInt64(SBits) xor (DBits * UInt64(257)) xor UInt64(Value.I);")
    e.line("end;")
    e.line()
    e.line("{$ifndef GB_SKIP_MANAGED_RECORD}")
    e.line("function GBMakeTracked(AValue: Integer): TGBTracked;")
    e.line("begin")
    e.line("  Result.Value := AValue;")
    e.line("end;")
    e.line("{$endif}")
    e.line()
    e.line("constructor TGBThreadProbe.Create(ASeed, AIterations: Integer);")
    e.line("begin")
    e.line("  inherited Create(True);")
    e.line("  FreeOnTerminate := False;")
    e.line("  Seed := ASeed;")
    e.line("  Iterations := AIterations;")
    e.line("end;")
    e.line()
    e.line("procedure TGBThreadProbe.Execute;")
    e.line("var I: Integer; A: TGBIntArray; S: AnsiString;")
    e.line("begin")
    e.line("  GBThreadOrdinal := Seed;")
    e.line("  GBThreadText := AnsiString('thread:') + AnsiString(IntToStr(Seed));")
    e.line("  Digest := UInt64($CBF29CE484222325);")
    e.line("  for I := 0 to Iterations - 1 do")
    e.line("  begin")
    e.line("    SetLength(A, (I + Seed) and 31);")
    e.line("    if Length(A) > 0 then A[High(A)] := GBThreadOrdinal xor I;")
    e.line("    S := GBThreadText + AnsiString(':') + AnsiString(IntToStr(I and 15));")
    e.line("    Digest := (Digest xor GBOpenArrayDigest(A) xor GBHashAnsi(S)) * UInt64($100000001B3);")
    e.line("    Inc(GBThreadOrdinal, I + 1);")
    e.line("  end;")
    e.line("  Text := GBThreadText + AnsiString(':') + AnsiString(IntToStr(GBThreadOrdinal));")
    e.line("end;")
    e.line()


def emit_control_forms(e: Emitter) -> list[str]:
    calls: list[str] = []
    e.line("{$ifndef GB_SKIP_CONTROL}")
    for case_id in range(96):
        proc = f"GBControl{case_id:04d}"
        calls.append(proc)
        seed = (case_id * 37 + 11) & 255
        shape = case_id % 8
        e.line(f"procedure {proc};")
        e.line("var")
        e.line("  I, J, K, Sum, FinallyCount: Integer;")
        e.line("begin")
        e.line(f"  K := GBNoInline({seed});")
        e.line("  Sum := 0;")
        e.line("  FinallyCount := 0;")
        if shape == 0:
            e.line("  for I := -3 to 9 do")
            e.line("    case (I + K) and 7 of")
            e.line("      0, 3: Inc(Sum, I * 5);")
            e.line("      1..2: Dec(Sum, I * 3);")
            e.line("    else")
            e.line("      Sum := (Sum xor (I + K)) + 7;")
            e.line("    end;")
        elif shape == 1:
            e.line("  I := -7;")
            e.line("  while I <= 13 do")
            e.line("  begin")
            e.line("    Inc(I);")
            e.line("    if ((I + K) and 3) = 0 then Continue;")
            e.line("    if I = 11 then Break;")
            e.line("    Sum := Sum + I * (K or 1);")
            e.line("  end;")
        elif shape == 2:
            e.line("  I := 0;")
            e.line("  repeat")
            e.line("    Sum := (Sum * 3) xor (I + K);")
            e.line("    Inc(I);")
            e.line("  until I = 17;")
        elif shape == 3:
            e.line("  for I := 0 to 7 do")
            e.line("    for J := 7 downto 0 do")
            e.line("      if ((I * 11 + J * 7 + K) mod 5) <> 0 then")
            e.line("        Inc(Sum, I * 101 + J);")
        elif shape == 4:
            e.line("  try")
            e.line("    for I := 0 to 12 do")
            e.line("    begin")
            e.line("      try")
            e.line("        if ((I + K) mod 7) = 0 then Continue;")
            e.line("        if I = 10 then Break;")
            e.line("        Inc(Sum, I * 17 + K);")
            e.line("      finally")
            e.line("        Inc(FinallyCount);")
            e.line("      end;")
            e.line("    end;")
            e.line("  finally")
            e.line("    Inc(Sum, FinallyCount * 19);")
            e.line("  end;")
        elif shape == 5:
            e.line("  try")
            e.line("    try")
            e.line("      Sum := K * 31;")
            e.line("      if (K and 1) <> 0 then")
            e.line("        raise Exception.Create('gb');")
            e.line("      Inc(Sum, 7);")
            e.line("    except")
            e.line("      on Exception do Inc(Sum, 13);")
            e.line("    end;")
            e.line("  finally")
            e.line("    Inc(Sum, 23);")
            e.line("  end;")
        elif shape == 6:
            e.line("  I := 0;")
            e.line("  J := 0;")
            e.line("  while I < 12 do")
            e.line("  begin")
            e.line("    Inc(I);")
            e.line("    repeat")
            e.line("      Inc(J);")
            e.line("      Sum := Sum xor (I * 257 + J + K);")
            e.line("    until (J mod 5) = 0;")
            e.line("  end;")
        else:
            e.line("  for I := 0 to 31 do")
            e.line("  begin")
            e.line("    if ((I < 7) and ((K and 1) <> 0)) or")
            e.line("       ((I >= 7) and ((K and 2) <> 0)) then")
            e.line("      Inc(Sum, I xor K)")
            e.line("    else")
            e.line("      Dec(Sum, I + K);")
            e.line("  end;")
        e.check("control", f"gb-control-{case_id:04d}-sum", "UInt32(Sum)")
        e.check("control", f"gb-control-{case_id:04d}-finally", "UInt32(FinallyCount)")
        e.line("end;")
        e.line()
    e.line("{$endif}")
    return calls


def emit_abi_forms(e: Emitter) -> list[str]:
    calls: list[str] = []
    e.line("{$ifndef GB_SKIP_ABI}")
    sizes = [1, 2, 3, 5, 7, 8, 9, 12, 15, 16, 17, 24, 31, 32, 33, 48]
    conventions = [("", "pas"), ("cdecl", "cdecl"), ("stdcall", "stdcall")]
    for size in sizes:
        typ = f"TGBBytes{size:02d}"
        e.line("type")
        e.line(f"  {typ} = packed record")
        e.line(f"    Data: array[0..{size - 1}] of Byte;")
        e.line("  end;")
        e.line()
        for conv, slug in conventions:
            suffix = f"; {conv}" if conv else ""
            e.line(f"function GBAbiMake{size:02d}_{slug}(Seed: Integer): {typ}{suffix};")
            e.line("var I: Integer;")
            e.line("begin")
            e.line(f"  for I := 0 to {size - 1} do")
            e.line("    Result.Data[I] := Byte(Seed + I * 29);")
            e.line("end;")
            e.line()
            e.line(f"function GBAbiRead{size:02d}_{slug}(Value: {typ}; A: Byte; B: Int64; C: Word): UInt64{suffix};")
            e.line("var I: Integer;")
            e.line("begin")
            e.line("  Result := UInt64(A) xor UInt64(B) xor UInt64(C);")
            e.line(f"  for I := 0 to {size - 1} do")
            e.line("    Result := (Result * UInt64(257)) xor Value.Data[I];")
            e.line("  if SizeOf(Value) > 0 then Value.Data[0] := Value.Data[0] xor $FF;")
            e.line("end;")
            e.line()
            e.line(f"procedure GBAbiMutate{size:02d}_{slug}(var Value: {typ}; Delta: Byte){suffix};")
            e.line("begin")
            e.line(f"  Value.Data[{(size * 7) % size}] := Value.Data[{(size * 7) % size}] + Delta;")
            e.line("end;")
            e.line()
            for case in range(4):
                proc = f"GBAbiCase{size:02d}_{slug}_{case}"
                calls.append(proc)
                seed = size * 13 + case * 41
                e.line(f"procedure {proc};")
                e.line("var")
                e.line(f"  R: {typ};")
                e.line("  Before, V: UInt64;")
                e.line("begin")
                e.line(f"  R := GBAbiMake{size:02d}_{slug}(GBNoInline({seed}));")
                e.line("  Before := R.Data[0];")
                e.line(f"  V := GBAbiRead{size:02d}_{slug}(R, Byte({case * 17 + 3}), Int64({seed * 65537}), Word({size * 257 + case}));")
                e.check("abi", f"gb-abi-{size:02d}-{slug}-{case}-read", "V")
                e.check("abi", f"gb-abi-{size:02d}-{slug}-{case}-value-isolation", "R.Data[0] xor Before")
                e.line(f"  GBAbiMutate{size:02d}_{slug}(R, Byte({case + 1}));")
                e.check("abi", f"gb-abi-{size:02d}-{slug}-{case}-mutate", f"R.Data[{(size * 7) % size}]")
                e.line("end;")
                e.line()
    e.line("{$endif}")
    return calls


def emit_array_pointer_forms(e: Emitter) -> list[str]:
    calls: list[str] = []
    e.line("{$ifndef GB_SKIP_ARRAY_POINTER}")
    bounds = [(-17, 23), (-1, 1), (0, 0), (0, 7), (5, 19), (100, 355)]
    for case_id in range(144):
        low, high = bounds[case_id % len(bounds)]
        typ = f"TGBArray{case_id:04d}"
        proc = f"GBArrayCase{case_id:04d}"
        calls.append(proc)
        e.line("type")
        e.line(f"  {typ} = array[{low}..{high}] of Integer;")
        e.line(f"procedure {proc};")
        e.line("var")
        e.line(f"  A, B: {typ};")
        e.line("  I, Sum, Index: Integer;")
        e.line("  P: PInteger;")
        e.line("begin")
        e.line(f"  for I := {low} to {high} do")
        e.line(f"    A[I] := (I * {case_id + 3}) xor {case_id * 97 + 11};")
        e.line("  B := A;")
        e.line("  Sum := 0;")
        e.line(f"  for I := {low} to {high} do")
        e.line("    Inc(Sum, B[I]);")
        e.line("  P := @B[Low(B)];")
        e.line(f"  Index := GBNoInline({case_id * 11 + 3}) mod Length(B);")
        e.line("  Inc(P[Index], 123);")
        e.check("array-pointer", f"gb-array-{case_id:04d}-sum", "UInt32(Sum)")
        e.check("array-pointer", f"gb-array-{case_id:04d}-pointer", "UInt32(B[Low(B) + Index])")
        e.check("array-pointer", f"gb-array-{case_id:04d}-copy", "UInt32(A[Low(A) + Index])")
        e.line("end;")
        e.line()
    e.line("{$endif}")
    return calls


def emit_dispatch_forms(e: Emitter) -> list[str]:
    calls: list[str] = []
    e.line("{$ifndef GB_SKIP_DISPATCH}")
    classes = ["TGBBase", "TGBMid", "TGBLeaf"]
    for case_id in range(96):
        proc = f"GBDispatch{case_id:04d}"
        calls.append(proc)
        cls = classes[case_id % len(classes)]
        seed = case_id * 19 + 7
        e.line(f"procedure {proc};")
        e.line("var")
        e.line("  O: TGBBase;")
        e.line("  C: TGBBaseClass;")
        e.line("  M: function(X: Integer): Integer of object;")
        e.line("  V: Integer;")
        e.line("begin")
        e.line(f"  C := {cls};")
        e.line(f"  O := C.Create({seed});")
        e.line("  try")
        e.line("    M := O.Step;")
        e.line(f"    V := M(GBNoInline({case_id - 31}));")
        e.line(f"    V := V xor O.CallInherited({case_id * 3 - 17});")
        e.check("dispatch", f"gb-dispatch-{case_id:04d}-value", "UInt32(V)")
        e.check("dispatch", f"gb-dispatch-{case_id:04d}-is-base", "Ord(O is TGBBase)")
        e.check("dispatch", f"gb-dispatch-{case_id:04d}-is-leaf", "Ord(O is TGBLeaf)")
        e.check("dispatch", f"gb-dispatch-{case_id:04d}-class", "Ord(O.ClassType = C)")
        e.line("  finally")
        e.line("    O.Free;")
        e.line("  end;")
        e.line("end;")
        e.line()
    e.line("{$endif}")
    return calls


def emit_managed_forms(e: Emitter) -> list[str]:
    calls: list[str] = []
    e.line("{$ifndef GB_SKIP_MANAGED}")
    for case_id in range(128):
        proc = f"GBManaged{case_id:04d}"
        calls.append(proc)
        seed = case_id * 23 + 5
        shape = case_id % 8
        e.line(f"procedure {proc};")
        e.line("var")
        e.line("  A, B: TGBManaged;")
        e.line("  D: TGBManagedArray;")
        e.line("  S: AnsiString;")
        e.line("  I: IGBValue;")
        e.line("  Before: Integer;")
        e.line("begin")
        e.line("  Before := TGBValueObject.Alive;")
        e.line(f"  A := GBMakeManaged({seed});")
        if shape == 0:
            e.line("  B := A;")
            e.line("  B.S[1] := 'z';")
            e.line("  B.A := Copy(A.A);")
            e.line("  Inc(B.A[1], 17);")
        elif shape == 1:
            e.line("  SetLength(D, 3);")
            e.line("  D[0] := A;")
            e.line(f"  D[1] := GBMakeManaged({seed + 1});")
            e.line("  D[2] := D[0];")
            e.line("  B := D[2];")
        elif shape == 2:
            e.line("  B := GBMakeManaged(A.N mod 97);")
            e.line("  A := B;")
            e.line("  B := A;")
        elif shape == 3:
            e.line("  try")
            e.line("    B := A;")
            e.line("    S := B.S + AnsiString(':try');")
            e.line("    if (A.N and 1) <> 0 then raise Exception.Create('gb');")
            e.line("  except")
            e.line("    S := A.S + AnsiString(':except');")
            e.line("  end;")
        elif shape == 4:
            e.line("  B := Default(TGBManaged);")
            e.line("  B := A;")
            e.line("  B := Default(TGBManaged);")
            e.line("  B := A;")
        elif shape == 5:
            e.line("  I := A.I;")
            e.line("  A.I := I;")
            e.line("  B := A;")
            e.line("  B.I := A.I;")
        elif shape == 6:
            e.line("  SetLength(D, 2);")
            e.line("  D[0] := A;")
            e.line("  D[1] := D[0];")
            e.line("  SetLength(D, 1);")
            e.line("  B := D[0];")
        else:
            e.line("  B := A;")
            e.line("  S := B.S;")
            e.line("  UniqueString(S);")
            e.line("  S := S + AnsiString(':tail');")
        e.check("managed", f"gb-managed-{case_id:04d}-a", "GBManagedDigest(A)")
        e.check("managed", f"gb-managed-{case_id:04d}-b", "GBManagedDigest(B)")
        e.check("managed", f"gb-managed-{case_id:04d}-s", "GBHashAnsi(S)")
        e.check("managed", f"gb-managed-{case_id:04d}-alive", "UInt32(TGBValueObject.Alive - Before)")
        e.line("  D := nil;")
        e.line("  I := nil;")
        e.line("  A := Default(TGBManaged);")
        e.line("  B := Default(TGBManaged);")
        e.check(
            "managed",
            f"gb-managed-{case_id:04d}-drain",
            "Ord(((TGBValueObject.Alive - Before) >= 0) and "
            "((TGBValueObject.Alive - Before) <= 1))",
            expected="0000000000000001",
        )
        e.line("end;")
        e.line()
    e.line("{$endif}")
    return calls


def emit_closure_forms(e: Emitter) -> list[str]:
    calls: list[str] = []
    e.line("{$ifdef HAS_ANON}")
    e.line("{$ifndef GB_SKIP_CLOSURE}")
    for case_id in range(96):
        maker = f"GBMakeClosure{case_id:04d}"
        proc = f"GBClosure{case_id:04d}"
        calls.append(proc)
        seed = case_id * 31 + 9
        shape = case_id % 4
        e.line(f"function {maker}(Seed: Integer): TGBIntFunc;")
        e.line("var")
        e.line("  Captured: Integer;")
        e.line("  Text: AnsiString;")
        e.line("  Intf: IGBValue;")
        e.line("begin")
        e.line(f"  Captured := Seed xor {case_id * 7 + 3};")
        e.line("  Text := AnsiString('c') + AnsiString(IntToStr(Seed));")
        e.line("  Intf := TGBValueObject.Create(Seed * 5);")
        if shape == 0:
            e.line("  Result := function(X: Integer): Integer")
            e.line("    begin Result := Captured + X + Length(Text) + Intf.GetValue; end;")
        elif shape == 1:
            e.line("  Result := function(X: Integer): Integer")
            e.line("    begin Inc(Captured, X); Result := Captured xor Intf.GetValue; end;")
        elif shape == 2:
            e.line("  Result := function(X: Integer): Integer")
            e.line("    var I, V: Integer;")
            e.line("    begin")
            e.line("      V := Captured;")
            e.line("      for I := 0 to (X and 7) do V := V * 3 + I;")
            e.line("      Result := V + Length(Text) + Intf.GetValue;")
            e.line("    end;")
        else:
            e.line("  Result := function(X: Integer): Integer")
            e.line("    begin")
            e.line("      try Result := Captured div (X and 3); except Result := Captured + Intf.GetValue; end;")
            e.line("    end;")
        e.line("end;")
        e.line()
        e.line(f"procedure {proc};")
        e.line("var")
        e.line("  F, G: TGBIntFunc;")
        e.line("  A, B, Before: Integer;")
        e.line("begin")
        e.line("  Before := TGBValueObject.Alive;")
        e.line(f"  F := {maker}(GBNoInline({seed}));")
        e.line("  G := F;")
        e.line(f"  A := F({case_id % 13});")
        e.line(f"  B := G({(case_id * 3) % 17});")
        e.check("closure", f"gb-closure-{case_id:04d}-a", "UInt32(A)")
        e.check("closure", f"gb-closure-{case_id:04d}-b", "UInt32(B)")
        e.check("closure", f"gb-closure-{case_id:04d}-alive", "UInt32(TGBValueObject.Alive - Before)")
        e.line("  F := nil;")
        e.line("  G := nil;")
        e.check("closure", f"gb-closure-{case_id:04d}-drain", "UInt32(TGBValueObject.Alive - Before)")
        e.line("end;")
        e.line()
    e.line("{$endif}")
    e.line("{$endif}")
    e.line()
    return calls


def emit_generic_forms(e: Emitter) -> list[str]:
    calls: list[str] = []
    e.line("{$ifndef GB_SKIP_GENERIC}")
    types = [
        ("Integer", "i32", lambda n: str(n)),
        ("Int64", "i64", lambda n: f"Int64({n} * 1000003)"),
        ("AnsiString", "astr", lambda n: f"AnsiString('g{n}')"),
        ("UnicodeString", "ustr", lambda n: f"UnicodeString('u{n}')"),
    ]
    for case_id in range(96):
        pas, slug, value = types[case_id % len(types)]
        proc = f"GBGeneric{case_id:04d}"
        calls.append(proc)
        literal = value(case_id * 17 + 5)
        e.line(f"procedure {proc};")
        e.line("var")
        e.line(f"  B: TGBGenericBox<{pas}>;")
        e.line(f"  C: TGBGenericClass<{pas}>;")
        e.line(f"  A: TArray<{pas}>;")
        e.line("begin")
        e.line(f"  B := TGBGenericBox<{pas}>.Make({literal});")
        e.line(f"  C := TGBGenericClass<{pas}>.Create(B.Read);")
        e.line("  try")
        e.line("    SetLength(A, 3);")
        e.line("    A[0] := B.Read;")
        e.line("    A[1] := C.Read;")
        e.line("    A[2] := A[0];")
        if pas in ("Integer", "Int64"):
            e.check("generic", f"gb-generic-{case_id:04d}-box", "UInt64(B.Read)")
            e.check("generic", f"gb-generic-{case_id:04d}-class", "UInt64(C.Read)")
            e.check("generic", f"gb-generic-{case_id:04d}-array", "UInt64(A[2])")
        elif pas == "AnsiString":
            e.check("generic", f"gb-generic-{case_id:04d}-box", "GBHashAnsi(B.Read)")
            e.check("generic", f"gb-generic-{case_id:04d}-class", "GBHashAnsi(C.Read)")
            e.check("generic", f"gb-generic-{case_id:04d}-array", "GBHashAnsi(A[2])")
        else:
            e.check("generic", f"gb-generic-{case_id:04d}-box", "GBHashUnicode(B.Read)")
            e.check("generic", f"gb-generic-{case_id:04d}-class", "GBHashUnicode(C.Read)")
            e.check("generic", f"gb-generic-{case_id:04d}-array", "GBHashUnicode(A[2])")
        e.line("  finally")
        e.line("    C.Free;")
        e.line("  end;")
        e.line("end;")
        e.line()
    e.line("{$endif}")
    return calls


def emit_layout_rtti_variant_forms(e: Emitter) -> list[str]:
    calls: list[str] = []
    e.line("{$ifndef GB_SKIP_LAYOUT_RTTI_VARIANT}")
    for case_id in range(128):
        proc = f"GBLayout{case_id:04d}"
        calls.append(proc)
        e.line(f"procedure {proc};")
        e.line("var")
        e.line("  R: TGBVariant;")
        e.line("  V: Variant;")
        e.line("  S: TGBEnumSet;")
        e.line("  E: TGBEnum;")
        e.line("  Sub: TGBSubrange;")
        e.line("  TV: TValue;")
        e.line("  TVValue, TVOk: Integer;")
        e.line("begin")
        e.line(f"  R.Q := UInt64(${(case_id * 0x9E3779B97F4A7C15) & 0xFFFFFFFFFFFFFFFF:016X});")
        e.line(f"  R.B[{case_id % 8}] := R.B[{case_id % 8}] xor Byte({case_id * 13 + 7});")
        e.line(f"  E := TGBEnum((1 shl ({case_id} mod 4)) - 1);")
        e.line("  S := [gbeZero, gbeThree];")
        e.line("  Include(S, E);")
        e.line(f"  Sub := TGBSubrange(({case_id * 7} mod 41) - 17);")
        e.line(f"  V := Int64({case_id * 100003 - 700001});")
        e.line("  V := V * 3 + Sub;")
        e.line("  TVOk := 1;")
        e.line("  try")
        e.line("    TV := TValue.From<TGBEnum>(E);")
        e.line("    TVValue := Ord(TV.AsType<TGBEnum>);")
        e.line("  except")
        e.line("    TVOk := 0;")
        e.line("    TVValue := -1;")
        e.line("  end;")
        e.check("layout-rtti-variant", f"gb-layout-{case_id:04d}-record", "R.Q")
        e.check(
            "layout-rtti-variant",
            f"gb-layout-{case_id:04d}-set",
            "UInt32(Byte(S))",
            expected=f"{(9, 11, 9, 137)[case_id % 4]:016X}",
        )
        e.check(
            "layout-rtti-variant",
            f"gb-layout-{case_id:04d}-enum",
            "Ord(E)",
            expected=f"{(0, 1, 3, 7)[case_id % 4]:016X}",
        )
        e.check("layout-rtti-variant", f"gb-layout-{case_id:04d}-subrange", "UInt32(Sub)")
        e.check("layout-rtti-variant", f"gb-layout-{case_id:04d}-variant", "UInt64(Int64(V))")
        e.check(
            "layout-rtti-variant",
            f"gb-layout-{case_id:04d}-tvalue",
            "UInt32(TVValue)",
            expected="00000000FFFFFFFF",
        )
        e.check(
            "layout-rtti-variant",
            f"gb-layout-{case_id:04d}-tvalue-ok",
            "TVOk",
            expected="0000000000000000",
        )
        e.check("layout-rtti-variant", f"gb-layout-{case_id:04d}-sizeof", "SizeOf(R)")
        e.check("layout-rtti-variant", f"gb-layout-{case_id:04d}-typekind", "Ord(PTypeInfo(TypeInfo(TGBVariant))^.Kind = tkRecord)")
        e.line("end;")
        e.line()
    e.line("{$endif}")
    return calls


def emit_composed_optimizer_forms(e: Emitter) -> list[str]:
    calls: list[str] = []
    e.line("{$ifndef GB_SKIP_COMPOSED}")
    for case_id in range(256):
        proc = f"GBCompose{case_id:04d}"
        calls.append(proc)
        seed = case_id * 43 + 17
        shape = case_id % 8
        e.line(f"procedure {proc};")
        e.line("var")
        e.line("  A, B, C, I: Integer;")
        e.line("  R: TGBVariant;")
        e.line("  M: TGBManaged;")
        e.line("  O: TGBBase;")
        e.line("begin")
        e.line(f"  A := GBNoInline({seed});")
        e.line("  B := GBIdentity(A xor $13579BDF);")
        e.line("  C := 0;")
        if shape == 0:
            e.line("  R.Q := UInt64(UInt32(A)) shl 32 or UInt32(B);")
            e.line("  for I := 0 to 7 do C := C xor (R.B[I] * (I + 1));")
        elif shape == 1:
            e.line("  M := GBMakeManaged(A and 255);")
            e.line("  for I := 0 to High(M.A) do C := C + M.A[I] * (I + 3);")
            e.line("  C := C xor Integer(GBHashAnsi(M.S));")
        elif shape == 2:
            e.line("  O := TGBLeaf.Create(A and 1023);")
            e.line("  try C := O.Step(B and 255) xor O.CallInherited(A and 127); finally O.Free; end;")
        elif shape == 3:
            e.line("  M := GBMakeManaged(A and 255);")
            e.line("  C := M.A[0] + M.A[1] * 3 + M.A[2] * 5;")
            e.line("  C := GBIdentity(C) xor M.I.GetValue;")
        elif shape == 4:
            e.line("  try")
            e.line("    C := A div (B and 3);")
            e.line("  except")
            e.line("    C := A xor B;")
            e.line("  end;")
            e.line("  C := GBIdentity(C) + 19;")
        elif shape == 5:
            e.line("  I := 0;")
            e.line("  repeat")
            e.line("    case (A + I) and 3 of")
            e.line("      0: C := C + B;")
            e.line("      1: C := C xor A;")
            e.line("      2: C := C - I;")
            e.line("    else C := C + I * 7;")
            e.line("    end;")
            e.line("    Inc(I);")
            e.line("  until I = 11;")
        elif shape == 6:
            e.line("  M := GBMakeManaged(A and 63);")
            e.line("  O := TGBMid.Create(M.N and 255);")
            e.line("  try C := O.Step(M.A[1]) xor M.I.GetValue; finally O.Free; end;")
        else:
            e.line("  R.Q := UInt64(UInt32(A)) * UInt64($100000001) + UInt32(B);")
            e.line("  M := GBMakeManaged(R.B[0]);")
            e.line("  C := Integer(R.W[1]) xor M.A[2] xor M.I.GetValue;")
        e.check("composed", f"gb-compose-{case_id:04d}-a", "UInt32(A)")
        e.check("composed", f"gb-compose-{case_id:04d}-b", "UInt32(B)")
        e.check("composed", f"gb-compose-{case_id:04d}-c", "UInt32(C)")
        e.line("  M := Default(TGBManaged);")
        e.line("end;")
        e.line()
    e.line("{$endif}")
    return calls


def emit_string_forms(e: Emitter) -> list[str]:
    calls: list[str] = []
    e.line("{$ifndef GB_SKIP_STRING}")
    for case_id in range(192):
        proc = f"GBString{case_id:04d}"
        calls.append(proc)
        seed = case_id * 29 + 7
        shape = case_id % 12
        e.line(f"procedure {proc};")
        e.line("var")
        e.line("  A, B: AnsiString;")
        e.line("  U, V: UnicodeString;")
        e.line("  S: ShortString;")
        e.line("  Box: TGBStringBox;")
        e.line("  P: PAnsiChar;")
        e.line("  I: Integer;")
        e.line("begin")
        e.line(f"  A := AnsiString('left:{seed}:') + AnsiString(#0) + AnsiString('right');")
        e.line(f"  U := UnicodeString('wide:{seed}:') + UnicodeString(WideChar($03A9)) + UnicodeString(WideChar($20AC));")
        e.line(f"  S := ShortString('short:{seed}');")
        if shape == 0:
            e.line("  B := A;")
            e.line("  B := B + B + Copy(B, 2, 5);")
        elif shape == 1:
            e.line("  B := A;")
            e.line("  Delete(B, 2, Length(B) div 3);")
            e.line("  Insert(AnsiString('INS'), B, 2);")
        elif shape == 2:
            e.line("  B := Copy(A, 1, MaxInt);")
            e.line("  UniqueString(B);")
            e.line("  B[1] := AnsiChar(Byte(B[1]) xor $20);")
        elif shape == 3:
            e.line("  P := PAnsiChar(A);")
            e.line("  B := AnsiString(P);")
            e.line("  B := B + AnsiString(':') + A;")
        elif shape == 4:
            e.line("  Box.A := A;")
            e.line("  Box.U := U;")
            e.line("  Box.S := S;")
            e.line("  B := Box.A + AnsiString(Box.S);")
            e.line("  V := Box.U + UnicodeString(Box.S);")
        elif shape == 5:
            e.line("  SetLength(B, Length(A) + 5);")
            e.line("  for I := 1 to Length(A) do B[I] := A[Length(A) - I + 1];")
            e.line("  for I := Length(A) + 1 to Length(B) do B[I] := AnsiChar(64 + I - Length(A));")
        elif shape == 6:
            e.line("  B := LowerCase(A) + UpperCase(A);")
            e.line("  B := Copy(B, 2, Length(B) - 2);")
        elif shape == 7:
            e.line("  V := U;")
            e.line("  V := Copy(V, 2, Length(V)) + V[1];")
            e.line("  B := UTF8Encode(V);")
        elif shape == 8:
            e.line("  B := A + AnsiString(IntToHex(UInt32(GBNoInline(" + str(seed) + ")), 8));")
            e.line("  V := UnicodeString(B) + U;")
        elif shape == 9:
            e.line("  B := StringOfChar(AnsiChar(65 + (" + str(case_id) + " mod 26)), (" + str(case_id) + " mod 31) + 1);")
            e.line("  B := A + B + A;")
        elif shape == 10:
            e.line("  B := A;")
            e.line("  if Pos(AnsiString(#0), B) > 0 then B := B + AnsiString(':nul');")
            e.line("  V := U + UnicodeString(B);")
        else:
            e.line("  Box.A := A;")
            e.line("  B := Box.A;")
            e.line("  Box.A := B + AnsiString(':box');")
            e.line("  B := Box.A + B;")
        e.check("string", f"gb-string-{case_id:04d}-a", "GBHashAnsi(A)")
        e.check("string", f"gb-string-{case_id:04d}-b", "GBHashAnsi(B)")
        e.check("string", f"gb-string-{case_id:04d}-u", "GBHashUnicode(U)")
        e.check("string", f"gb-string-{case_id:04d}-v", "GBHashUnicode(V)")
        e.check("string", f"gb-string-{case_id:04d}-short", "GBHashAnsi(AnsiString(S))")
        e.line("end;")
        e.line()
    e.line("{$endif}")
    return calls


def emit_exception_forms(e: Emitter) -> list[str]:
    calls: list[str] = []
    e.line("{$ifndef GB_SKIP_EXCEPTION}")
    for case_id in range(128):
        func = f"GBExceptionFunc{case_id:04d}"
        proc = f"GBException{case_id:04d}"
        calls.append(proc)
        seed = case_id * 47 + 13
        shape = case_id % 8
        e.line(f"function {func}(Seed: Integer; var Trail: AnsiString): Integer;")
        e.line("var")
        e.line("  I: Integer;")
        e.line("begin")
        e.line("  Result := Seed;")
        if shape == 0:
            e.line("  try")
            e.line("    Trail := Trail + 'A';")
            e.line("    Exit(Result + 7);")
            e.line("  finally")
            e.line("    Trail := Trail + 'F';")
            e.line("    Inc(Result, 11);")
            e.line("  end;")
        elif shape == 1:
            e.line("  try")
            e.line("    try")
            e.line("      Trail := Trail + 'A';")
            e.line("      raise EArgumentException.Create('x');")
            e.line("    except")
            e.line("      on EArgumentException do begin Trail := Trail + 'E'; Inc(Result, 17); end;")
            e.line("    end;")
            e.line("  finally")
            e.line("    Trail := Trail + 'F'; Inc(Result, 19);")
            e.line("  end;")
        elif shape == 2:
            e.line("  for I := 0 to 9 do")
            e.line("    try")
            e.line("      if (I + Seed) mod 4 = 0 then Continue;")
            e.line("      if I = 8 then Break;")
            e.line("      Inc(Result, I * 3);")
            e.line("    finally")
            e.line("      Trail := Trail + AnsiChar(65 + I);")
            e.line("    end;")
        elif shape == 3:
            e.line("  try")
            e.line("    Trail := Trail + '1';")
            e.line("    try")
            e.line("      Trail := Trail + '2';")
            e.line("      raise Exception.Create('inner');")
            e.line("    finally")
            e.line("      Trail := Trail + '3';")
            e.line("    end;")
            e.line("  except")
            e.line("    Trail := Trail + '4'; Inc(Result, 23);")
            e.line("  end;")
        elif shape == 4:
            e.line("  I := 0;")
            e.line("  repeat")
            e.line("    try")
            e.line("      Inc(Result, I xor Seed);")
            e.line("    finally")
            e.line("      Inc(I);")
            e.line("      Trail := Trail + AnsiChar(48 + (I mod 10));")
            e.line("    end;")
            e.line("  until I = 7;")
        elif shape == 5:
            e.line("  try")
            e.line("    if (Seed and 1) <> 0 then raise Exception.Create(IntToStr(Seed));")
            e.line("    Inc(Result, 29);")
            e.line("  except")
            e.line("    on E: Exception do begin Trail := Trail + AnsiString(E.Message); Result := Length(E.Message); end;")
            e.line("  end;")
        elif shape == 6:
            e.line("  try")
            e.line("    Trail := Trail + 'X';")
            e.line("  finally")
            e.line("    try")
            e.line("      if Seed > 0 then raise Exception.Create('nested');")
            e.line("    except")
            e.line("      Trail := Trail + 'N'; Inc(Result, 31);")
            e.line("    end;")
            e.line("  end;")
        else:
            e.line("  try")
            e.line("    Trail := Trail + 'B';")
            e.line("    Result := Result xor $13579BDF;")
            e.line("  except")
            e.line("    Result := -1;")
            e.line("  end;")
            e.line("  Trail := Trail + 'D';")
        e.line("end;")
        e.line()
        e.line(f"procedure {proc};")
        e.line("var Trail: AnsiString; Value: Integer;")
        e.line("begin")
        e.line("  Trail := '';")
        e.line(f"  Value := {func}(GBNoInline({seed}), Trail);")
        e.check("exception", f"gb-exception-{case_id:04d}-value", "UInt32(Value)")
        e.check("exception", f"gb-exception-{case_id:04d}-trail", "GBHashAnsi(Trail)")
        e.line("end;")
        e.line()
    e.line("{$endif}")
    return calls


def emit_nested_forms(e: Emitter) -> list[str]:
    calls: list[str] = []
    e.line("{$ifndef GB_SKIP_NESTED}")
    for case_id in range(128):
        proc = f"GBNested{case_id:04d}"
        calls.append(proc)
        seed = case_id * 53 + 3
        shape = case_id % 8
        e.line(f"procedure {proc};")
        e.line("var")
        e.line("  Captured, Calls: Integer;")
        e.line("  Text: AnsiString;")
        e.line("  function Inner(X: Integer): Integer;")
        e.line("  var I, V: Integer;")
        e.line("  begin")
        e.line("    Inc(Calls);")
        if shape == 0:
            e.line("    Result := Captured + X + Length(Text);")
        elif shape == 1:
            e.line("    Captured := Captured xor X; Result := Captured;")
        elif shape == 2:
            e.line("    V := Captured; for I := 0 to (X and 7) do V := V * 3 + I; Result := V;")
        elif shape == 3:
            e.line("    if X <= 0 then Exit(Captured); Result := Inner(X - 1) + X;")
        elif shape == 4:
            e.line("    try Result := Captured div (X and 3); except Result := Captured + X; end;")
        elif shape == 5:
            e.line("    Result := Ord(Text[(X mod Length(Text)) + 1]) + Captured;")
        elif shape == 6:
            e.line("    Result := Captured; for I := X downto 0 do Result := Result xor (I * 257);")
        else:
            e.line("    V := X; repeat V := V - 1; Inc(Captured, V); until V <= 0; Result := Captured;")
        e.line("  end;")
        e.line("begin")
        e.line(f"  Captured := GBNoInline({seed});")
        e.line(f"  Text := AnsiString('nested:{case_id}:');")
        e.line("  Calls := 0;")
        e.check("nested", f"gb-nested-{case_id:04d}-first", f"UInt32(Inner({case_id % 11}))")
        e.check("nested", f"gb-nested-{case_id:04d}-second", f"UInt32(Inner({(case_id * 3) % 9}))")
        e.check("nested", f"gb-nested-{case_id:04d}-captured", "UInt32(Captured)")
        e.check("nested", f"gb-nested-{case_id:04d}-calls", "Calls")
        e.line("end;")
        e.line()
    e.line("{$endif}")
    return calls


def emit_array_lifetime_forms(e: Emitter) -> list[str]:
    calls: list[str] = []
    e.line("{$ifndef GB_SKIP_DYNARRAY}")
    for case_id in range(192):
        proc = f"GBDynArray{case_id:04d}"
        calls.append(proc)
        count = case_id % 17
        seed = case_id * 61 + 5
        shape = case_id % 8
        e.line(f"procedure {proc};")
        e.line("var")
        e.line("  A, B: TGBIntArray;")
        e.line("  I: Integer;")
        e.line("begin")
        e.line(f"  GBOutArray(A, {count}, GBNoInline({seed}));")
        if shape == 0:
            e.line("  B := A;")
            e.line("  GBMutateArray(B, 3);")
        elif shape == 1:
            e.line("  B := Copy(A);")
            e.line("  GBMutateArray(B, -2);")
        elif shape == 2:
            e.line(f"  B := GBReturnArray({count + 1}, {seed + 1});")
            e.line("  A := B;")
        elif shape == 3:
            e.line("  SetLength(B, Length(A) + 3);")
            e.line("  for I := 0 to High(A) do B[High(B) - I] := A[I];")
        elif shape == 4:
            e.line("  B := A + GBReturnArray(3, 77);")
        elif shape == 5:
            e.line("  B := Copy(A, Length(A) div 3, Length(A));")
        elif shape == 6:
            e.line("  B := A;")
            e.line("  SetLength(B, Length(B) + 1);")
            e.line("  if Length(B) > 0 then B[High(B)] := 1234567;")
        else:
            e.line("  B := GBReturnArray(5, A[0] * Ord(Length(A) > 0));") if count > 0 else e.line("  B := GBReturnArray(5, 0);")
        e.check("dynarray", f"gb-dynarray-{case_id:04d}-a", "GBOpenArrayDigest(A)")
        e.check("dynarray", f"gb-dynarray-{case_id:04d}-b", "GBOpenArrayDigest(B)")
        e.check("dynarray", f"gb-dynarray-{case_id:04d}-alen", "Length(A)")
        e.check("dynarray", f"gb-dynarray-{case_id:04d}-blen", "Length(B)")
        e.line("end;")
        e.line()
    e.line("{$endif}")
    return calls


def emit_property_operator_forms(e: Emitter) -> list[str]:
    calls: list[str] = []
    e.line("{$ifndef GB_SKIP_PROPERTY_OPERATOR}")
    for case_id in range(128):
        proc = f"GBPropertyOperator{case_id:04d}"
        calls.append(proc)
        seed = case_id * 67 + 11
        shape = case_id % 8
        e.line(f"procedure {proc};")
        e.line("var")
        e.line("  A, B, C: TGBNumber;")
        e.line("  Box: TGBPropertyBox;")
        e.line("  I, V: Integer;")
        e.line("begin")
        e.line(f"  A := GBNoInline({seed});")
        e.line(f"  B := GBNoInline({case_id * 7 - 19});")
        if shape == 0:
            e.line("  C := (A + B) * 3;")
        elif shape == 1:
            e.line("  C := A * 5 + B * 7;")
        elif shape == 2:
            e.line("  C := (A + B) * (GBNoInline(3) + 1);")
        elif shape == 3:
            e.line("  C := A; for I := 0 to 5 do C := (C + B) * (I + 1);")
        elif shape == 4:
            e.line("  if A.Raw > B.Raw then C := A * 11 else C := B * 13;")
        elif shape == 5:
            e.line("  C := TGBNumber(Integer(A.Raw xor B.Raw));")
        elif shape == 6:
            e.line("  C := A + TGBNumber(Integer(B.Raw * 3));")
        else:
            e.line("  C := A; C.Raw := C.Twisted(7) + B.Twisted(3);")
        e.line("  Box := TGBPropertyBox.Create;")
        e.line("  try")
        e.line("    for I := 0 to 31 do Box[I] := Integer(C.Raw) xor (I * 257);")
        e.line(f"    V := Box[GBNoInline({case_id})] + Box[{case_id + 17}];")
        e.check("property-operator", f"gb-propop-{case_id:04d}-raw", "UInt64(Int64(C))")
        e.check("property-operator", f"gb-propop-{case_id:04d}-helper", "UInt64(C.Twisted(5))")
        e.check("property-operator", f"gb-propop-{case_id:04d}-property", "UInt32(V)")
        e.line("  finally")
        e.line("    Box.Free;")
        e.line("  end;")
        e.line("end;")
        e.line()
    e.line("{$endif}")
    return calls


def emit_interface_forms(e: Emitter) -> list[str]:
    calls: list[str] = []
    e.line("{$ifndef GB_SKIP_INTERFACE}")
    for case_id in range(128):
        proc = f"GBInterface{case_id:04d}"
        calls.append(proc)
        seed = case_id * 71 + 17
        shape = case_id % 8
        e.line(f"procedure {proc};")
        e.line("var")
        e.line("  A, B: IGBValue;")
        e.line("  Before, V: Integer;")
        e.line("begin")
        e.line("  Before := TGBValueObject.Alive;")
        e.line(f"  A := TGBValueObject.Create({seed});")
        if shape == 0:
            e.line(f"  V := GBInterfaceByValue(A, {case_id});")
        elif shape == 1:
            e.line(f"  V := GBInterfaceByConst(A, {case_id});")
        elif shape == 2:
            e.line("  B := A; V := GBInterfaceByValue(B, A.GetValue);")
        elif shape == 3:
            e.line(f"  GBInterfaceOut(B, {seed + 1}); V := A.GetValue xor B.GetValue;")
        elif shape == 4:
            e.line("  B := A; A := nil; V := B.GetValue;")
        elif shape == 5:
            e.line("  B := A; A := B; B := A; V := A.GetValue + B.GetValue;")
        elif shape == 6:
            e.line("  V := GBInterfaceByConst(A, GBInterfaceByValue(A, 3));")
        else:
            e.line(f"  GBInterfaceOut(A, {seed + 2}); V := A.GetValue;")
        e.check("interface", f"gb-interface-{case_id:04d}-value", "UInt32(V)")
        e.check("interface", f"gb-interface-{case_id:04d}-alive", "UInt32(TGBValueObject.Alive - Before)")
        e.line("  A := nil; B := nil;")
        e.check("interface", f"gb-interface-{case_id:04d}-drain", "UInt32(TGBValueObject.Alive - Before)")
        e.line("end;")
        e.line()
    e.line("{$endif}")
    return calls


def emit_legacy_project_forms(e: Emitter) -> list[str]:
    calls: list[str] = []
    e.line("{$ifndef GB_SKIP_LEGACY_PROJECT}")
    for case_id in range(192):
        proc = f"GBLegacyProject{case_id:04d}"
        calls.append(proc)
        seed = case_id * 79 + 23
        shape = case_id % 12
        e.line(f"procedure {proc};")
        e.line("label Again, Finished;")
        e.line("var")
        e.line("  R, R2: TGBLegacyRec;")
        e.line("  Overlay: TGBVariant;")
        e.line("  Bytes: array[0..7] of Byte absolute Overlay;")
        e.line("  Words: array[0..3] of Word absolute Overlay;")
        e.line("  Box: TGBPropertyBox;")
        e.line("  Method: function(X: Integer): Integer of object;")
        e.line("  Obj: TGBBase;")
        e.line("  D: TGBIntArray;")
        e.line("  I, J, Value: Integer;")
        e.line("  Digest: UInt64;")
        e.line("begin")
        e.line("  FillChar(Overlay, SizeOf(Overlay), 0);")
        e.line(f"  R.A := GBNoInline({seed}); R.B := Word({seed}); R.C := Byte({seed});")
        e.line(f"  R.Text := AnsiString('legacy:{case_id}');")
        e.line("  Value := 0; Digest := 0; I := 0; J := 0;")
        if shape == 0:
            e.line("  with R do begin A := A xor B; Inc(C, 3); Text := Text + AnsiString(':with'); end;")
            e.line("  with R do Value := A + B + C + Length(Text);")
        elif shape == 1:
            e.line("  Overlay.Q := UInt64(UInt32(R.A)) shl 32 or UInt32(R.B);")
            e.line("  GBUntypedXor(Bytes, SizeOf(Bytes), R.C);")
            e.line("  Value := Words[0] xor Words[1] xor Words[2] xor Words[3];")
        elif shape == 2:
            e.line("Again:")
            e.line("  Inc(I);")
            e.line("  Value := Value xor (I * 257 + R.A);")
            e.line("  if I < 11 then goto Again;")
            e.line("  goto Finished;")
            e.line("Finished:")
            e.line("  Inc(Value, I);")
        elif shape == 3:
            e.line(f"  GBOutArray(D, {case_id % 19}, R.A);")
            e.line("  Digest := GBOpenArrayDigest(D);")
            e.line("  D := nil;")
            e.line("  GBOutArray(D, 3, R.B);")
            e.line("  Value := Length(D) + D[0] + D[2];")
        elif shape == 4:
            e.line("  Digest := GBArrayConstDigest([R.A, R.C <> 0, Int64(R.A) * 100003, R.Text, UnicodeString(R.Text)]);")
            e.line("  Value := Integer(Digest);")
        elif shape == 5:
            e.line("  Obj := TGBLeaf.Create(R.A and 255);")
            e.line("  try Method := Obj.Step; Value := Method(R.B) xor Obj.CallInherited(R.C); finally Obj.Free; end;")
        elif shape == 6:
            e.line("  R2 := R;")
            e.line("  with R2 do begin Inc(A, 17); B := B xor $55AA; Text[1] := 'L'; end;")
            e.line("  Value := R.A xor R2.A xor R.B xor R2.B;")
            e.line("  Digest := GBHashAnsi(R.Text) xor GBHashAnsi(R2.Text);")
        elif shape == 7:
            e.line("  case TGBEnum((R.C mod 4) * 2 - Ord((R.C mod 4) = 2)) of")
            e.line("    gbeZero: Value := R.A;")
            e.line("    gbeOne: Value := R.B;")
            e.line("    gbeThree: Value := R.C;")
            e.line("    gbeSeven: Value := R.A xor R.B;")
            e.line("  else Value := -1;")
            e.line("  end;")
        elif shape == 8:
            e.line("  Box := TGBPropertyBox.Create;")
            e.line("  try with Box do begin Items[0] := R.A; Items[17] := R.B; Value := Items[0] xor Items[1]; end; finally Box.Free; end;")
        elif shape == 9:
            e.line("  Overlay.Q := UInt64($0123456789ABCDEF);")
            e.line("  Move(Bytes[1], Bytes[0], 7);")
            e.line("  Move(Bytes[0], Bytes[1], 7);")
            e.line("  Value := Bytes[0] + Bytes[7] * 257;")
        elif shape == 10:
            e.line("  for I := 0 to 15 do")
            e.line("    for J := 15 downto 0 do")
            e.line("      if (I xor J xor R.C) and 3 = 0 then goto Finished;")
            e.line("Finished:")
            e.line("  Value := I * 257 + J;")
        else:
            e.line("  R2 := Default(TGBLegacyRec);")
            e.line("  R2 := R;")
            e.line("  GBUntypedXor(R2.A, SizeOf(R2.A), R.C);")
            e.line("  Value := R2.A xor R.A;")
            e.line("  Digest := GBHashAnsi(R2.Text);")
        e.check("legacy-project", f"gb-legacy-{case_id:04d}-value", "UInt32(Value)")
        e.check("legacy-project", f"gb-legacy-{case_id:04d}-digest", "Digest")
        e.check("legacy-project", f"gb-legacy-{case_id:04d}-overlay", "Overlay.Q")
        e.check("legacy-project", f"gb-legacy-{case_id:04d}-record", "UInt32(R.A xor R.B xor R.C)")
        e.line("end;")
        e.line()
    e.line("{$endif}")
    return calls


def emit_rtti_value_forms(e: Emitter) -> list[str]:
    calls: list[str] = []
    e.line("{$ifndef GB_SKIP_RTTI_VALUE}")
    kinds = ("integer", "int64", "double", "ansi", "unicode", "enum", "record", "dynarray")
    for case_id in range(128):
        proc = f"GBRttiValue{case_id:04d}"
        calls.append(proc)
        kind = kinds[case_id % len(kinds)]
        seed = case_id * 83 + 29
        e.line(f"procedure {proc};")
        e.line("var")
        e.line("  TV: TValue;")
        e.line("  Ok: Boolean;")
        e.line("  Digest: UInt64;")
        e.line("  I32, I32Out: Integer;")
        e.line("  I64, I64Out: Int64;")
        e.line("  D, DOut: Double;")
        e.line("  A, AOut: AnsiString;")
        e.line("  U, UOut: UnicodeString;")
        e.line("  E, EOut: TGBEnum;")
        e.line("  R, ROut: TGBVariant;")
        e.line("  Arr, ArrOut: TGBIntArray;")
        e.line("begin")
        e.line("  Ok := True; Digest := 0;")
        if kind == "integer":
            e.line(f"  I32 := GBNoInline({seed});")
            e.line("  try TV := TValue.From<Integer>(I32); I32Out := TV.AsType<Integer>; Digest := UInt32(I32Out); except Ok := False; Digest := UInt64(-1); end;")
        elif kind == "int64":
            e.line(f"  I64 := Int64(GBNoInline({seed})) * 1000003;")
            e.line("  try TV := TValue.From<Int64>(I64); I64Out := TV.AsType<Int64>; Digest := UInt64(I64Out); except Ok := False; Digest := UInt64(-1); end;")
        elif kind == "double":
            e.line(f"  D := GBNoInline({seed}) / 7.0;")
            e.line("  try TV := TValue.From<Double>(D); DOut := TV.AsType<Double>; Move(DOut, Digest, SizeOf(DOut)); except Ok := False; Digest := UInt64(-1); end;")
        elif kind == "ansi":
            e.line(f"  A := AnsiString('rtti:{seed}:') + AnsiString(#0) + AnsiString('x');")
            e.line("  try TV := TValue.From<AnsiString>(A); AOut := TV.AsType<AnsiString>; Digest := GBHashAnsi(AOut); except Ok := False; Digest := UInt64(-1); end;")
        elif kind == "unicode":
            e.line(f"  U := UnicodeString('rtti:{seed}:') + WideChar($03A9);")
            e.line("  try TV := TValue.From<UnicodeString>(U); UOut := TV.AsType<UnicodeString>; Digest := GBHashUnicode(UOut); except Ok := False; Digest := UInt64(-1); end;")
        elif kind == "enum":
            enum_value = (0, 1, 3, 7)[case_id % 4]
            e.line(f"  E := TGBEnum({enum_value});")
            e.line("  try TV := TValue.From<TGBEnum>(E); EOut := TV.AsType<TGBEnum>; Digest := Ord(EOut); except Ok := False; Digest := UInt64(-1); end;")
        elif kind == "record":
            e.line(f"  R.Q := UInt64(${(seed * 0x100000001B3) & 0xFFFFFFFFFFFFFFFF:016X});")
            e.line("  try TV := TValue.From<TGBVariant>(R); ROut := TV.AsType<TGBVariant>; Digest := ROut.Q; except Ok := False; Digest := UInt64(-1); end;")
        else:
            e.line(f"  GBOutArray(Arr, {(case_id % 9) + 1}, {seed});")
            e.line("  try TV := TValue.From<TGBIntArray>(Arr); ArrOut := TV.AsType<TGBIntArray>; Digest := GBOpenArrayDigest(ArrOut); except Ok := False; Digest := UInt64(-1); end;")
        # Delphi TypeInfo(T) is nil for a sparse enum, so TValue cannot
        # construct a value without inventing an unsafe partial PTypeInfo.
        semantic_ok = "0000000000000000" if kind == "enum" else None
        semantic_digest = "FFFFFFFFFFFFFFFF" if kind == "enum" else None
        semantic_empty = "0000000000000001" if kind == "enum" else None
        e.check(
            "rtti-value",
            f"gb-rtti-{case_id:04d}-ok",
            "Ord(Ok)",
            expected=semantic_ok,
        )
        e.check(
            "rtti-value",
            f"gb-rtti-{case_id:04d}-digest",
            "Digest",
            expected=semantic_digest,
        )
        e.check(
            "rtti-value",
            f"gb-rtti-{case_id:04d}-empty",
            "Ord(TV.IsEmpty)",
            expected=semantic_empty,
        )
        e.line("  TV := TValue.Empty;")
        e.line("  Arr := nil; ArrOut := nil;")
        e.line("end;")
        e.line()
    e.line("{$endif}")
    return calls


def emit_inline_const_forms(e: Emitter) -> list[str]:
    calls: list[str] = []
    e.line("{$ifdef HAS_INLINEVAR}")
    e.line("{$ifndef GB_SKIP_INLINE_CONST}")
    for case_id in range(144):
        proc = f"GBInlineConst{case_id:04d}"
        calls.append(proc)
        seed = case_id * 67 + 11
        shape = case_id % 12
        e.line(f"procedure {proc};")
        e.line("var")
        e.line("  Base, Acc: Integer;")
        e.line("  Box: TGBPropertyBox;")
        e.line("  Owner: TGBInlineConstOwner;")
        e.line("begin")
        e.line(f"  Base := GBNoInline({seed});")
        if shape == 0:
            e.line("  Acc := Base xor 7;")
            e.line(f"  const Value = Base + GBNoInline({case_id % 23});")
            e.check("inline-const", f"gb-inline-const-{case_id:04d}-scalar", "UInt32(Value xor Acc)")
        elif shape == 1:
            e.line("  Acc := Base + 1;")
            e.line(f"  const Value: Integer = Acc * 3 - GBNoInline({case_id % 17});")
            e.check("inline-const", f"gb-inline-const-{case_id:04d}-typed", "UInt32(Value)")
        elif shape == 2:
            e.line("  Acc := Base and 255;")
            e.line(f"  const Values = [Acc, GBNoInline({case_id + 5}), Acc xor {case_id * 3 + 1}];")
            e.check("inline-const", f"gb-inline-const-{case_id:04d}-array-len", "Length(Values)")
            e.check("inline-const", f"gb-inline-const-{case_id:04d}-array-data", "UInt32(Values[0] * 257 + Values[1] * 17 + Values[2])")
            e.line(f"  const StaticValues = [{case_id}, {case_id + 1}];")
            e.line(f"  StaticValues[0] := {case_id + 9};")
            e.check("inline-const", f"gb-inline-const-{case_id:04d}-static-array-mutate", "UInt32(StaticValues[0] * 17 + StaticValues[1])")
        elif shape == 3:
            e.line("  Acc := Base and 31;")
            e.line(f"  const Text = AnsiString('inline:{case_id}:') + AnsiString(IntToStr(Acc));")
            e.check("inline-const", f"gb-inline-const-{case_id:04d}-string", "GBHashAnsi(Text)")
        elif shape == 4:
            e.line("  Acc := 0;")
            e.line(f"  for var I := 0 to {case_id % 7} do")
            e.line("  begin")
            e.line("    const Value = Base + I * 3;")
            e.line("    Acc := (Acc * 33) xor Value;")
            e.line("  end;")
            e.check("inline-const", f"gb-inline-const-{case_id:04d}-loop", "UInt32(Acc)")
        elif shape == 5:
            e.line("  Acc := 0;")
            e.line("  try")
            e.line(f"    const Value = Base xor GBNoInline({case_id * 5 + 3});")
            e.line("    Acc := Value + 9;")
            e.line("  finally")
            e.line("    Acc := Acc xor 85;")
            e.line("  end;")
            e.check("inline-const", f"gb-inline-const-{case_id:04d}-try", "UInt32(Acc)")
        elif shape == 6:
            e.line("  Acc := Base;")
            e.line("  begin")
            e.line(f"    const Value = Acc + GBNoInline({case_id % 19});")
            e.line("    Acc := Value * 5;")
            e.line("  end;")
            e.check("inline-const", f"gb-inline-const-{case_id:04d}-nested", "UInt32(Acc)")
        elif shape == 7:
            e.line("  Box := TGBPropertyBox.Create;")
            e.line("  try")
            e.line(f"    Box[{case_id % 16}] := Base xor {case_id * 13 + 1};")
            e.line(f"    const Value = Box[{case_id % 16}] + GBNoInline({case_id % 11});")
            e.check("inline-const", f"gb-inline-const-{case_id:04d}-property", "UInt32(Value)")
            e.line("  finally")
            e.line("    Box.Free;")
            e.line("  end;")
        elif shape == 8:
            e.line(f"  const Value = IGBValue(TGBValueObject.Create(Base xor {case_id + 1}));")
            e.check("inline-const", f"gb-inline-const-{case_id:04d}-interface", "UInt32(Value.GetValue)")
            e.check("inline-const", f"gb-inline-const-{case_id:04d}-alive", "TGBValueObject.Alive")
        elif shape == 9:
            e.line(f"  var Offset := GBNoInline({case_id % 29});")
            e.line("  Owner := TGBInlineConstOwner.Create(Base and 127, Offset);")
            e.line("  try")
            e.line("    const Value = Owner.Minimum;")
            e.check("inline-const", f"gb-inline-const-{case_id:04d}-field-method", "UInt32(Value)")
            e.line("  finally")
            e.line("    Owner.Free;")
            e.line("  end;")
        elif shape == 10:
            e.line("  const Value: TGBCallRec = GBMakeCallRec(Base);")
            e.check("inline-const", f"gb-inline-const-{case_id:04d}-record", "GBCallRecDigest(Value)")
        else:
            e.line("  const Value = TGBGenericOps<Int64>.InlineConstValue(Base);")
            e.check("inline-const", f"gb-inline-const-{case_id:04d}-generic", "UInt32(Value)")
        e.line("end;")
        e.line()
    e.line("{$endif}")
    e.line("{$endif}")
    return calls


def emit_modern_project_forms(e: Emitter) -> list[str]:
    calls: list[str] = []
    e.line("{$ifdef HAS_ANON}")
    e.line("{$ifdef HAS_INLINEVAR}")
    e.line("{$ifndef GB_SKIP_MODERN_PROJECT}")
    for case_id in range(160):
        proc = f"GBModernProject{case_id:04d}"
        calls.append(proc)
        seed = case_id * 73 + 19
        shape = case_id % 10
        e.line(f"procedure {proc};")
        e.line("var")
        e.line("  Owner: TGBClosureOwner;")
        e.line("  Box, Box2: TGBFuncBox;")
        e.line("  Outer: TGBIntFunc;")
        e.line("  Value: Integer;")
        e.line("begin")
        e.line(f"  Owner := TGBClosureOwner.Create(GBNoInline({seed}));")
        e.line("  try")
        e.line(f"    var Bias := GBNoInline({case_id * 3 - 17});")
        e.line("    Box.Func := Owner.MakeFunc(Bias);")
        e.line(f"    Box.Tag := AnsiString('box:{case_id}');")
        if shape == 0:
            e.line(f"    Value := Box.Func({case_id % 17});")
            e.line(f"    Value := Value xor Box.Func({(case_id * 3) % 19});")
        elif shape == 1:
            e.line("    Box2 := Box;")
            e.line(f"    Value := GBCallFunc(Box2.Func, {case_id % 23});")
            e.line("    Box := Default(TGBFuncBox);")
            e.line(f"    Inc(Value, GBCallFunc(Box2.Func, {(case_id * 5) % 29}));")
        elif shape == 2:
            e.line("    var Managed := GBMakeManaged(Bias and 255);")
            e.line("    Outer := function(X: Integer): Integer")
            e.line("      begin Result := Box.Func(X) + Managed.A[1] + Managed.I.GetValue; end;")
            e.line(f"    Value := Outer({case_id % 13});")
            e.line("    Managed := Default(TGBManaged);")
        elif shape == 3:
            e.line("    var Values := GBReturnArray((Bias and 7) + 1, Bias);")
            e.line("    Outer := function(X: Integer): Integer")
            e.line("      begin Result := Box.Func(X) xor Values[X mod Length(Values)]; end;")
            e.line(f"    Value := Outer({case_id % 11});")
            e.line("    Values := nil;")
        elif shape == 4:
            e.line("    Value := 0;")
            e.line("    for var I := 0 to 9 do")
            e.line("    begin")
            e.line("      var Local := Box.Func(I) xor (I * 257);")
            e.line("      Inc(Value, Local);")
            e.line("    end;")
        elif shape == 5:
            e.line("    try")
            e.line("      Outer := function(X: Integer): Integer")
            e.line("        begin if X = 0 then raise Exception.Create(Box.Tag); Result := Box.Func(X); end;")
            e.line(f"      Value := Outer({case_id % 3});")
            e.line("    except")
            e.line("      on E: Exception do Value := Length(E.Message) + Bias;")
            e.line("    end;")
        elif shape == 6:
            e.line("    Box2.Func := function(X: Integer): Integer")
            e.line("      begin Result := Box.Func(X + 1) + Box.Func(X + 2); end;")
            e.line("    Box2.Tag := Box.Tag + AnsiString(':nested');")
            e.line(f"    Value := Box2.Func({case_id % 7});")
        elif shape == 7:
            e.line("    var Intf: IGBValue := TGBValueObject.Create(Bias * 7);")
            e.line("    Outer := function(X: Integer): Integer")
            e.line("      begin Result := Box.Func(X) + Intf.GetValue; end;")
            e.line(f"    Value := GBCallFunc(Outer, {case_id % 9});")
            e.line("    Intf := nil;")
        elif shape == 8:
            e.line("    var LocalText := Box.Tag + AnsiString(':local');")
            e.line("    Outer := function(X: Integer): Integer")
            e.line("      begin LocalText := LocalText + AnsiString(IntToStr(X)); Result := Box.Func(X) + Length(LocalText); end;")
            e.line(f"    Value := Outer({case_id % 5});")
            e.line(f"    Inc(Value, Outer({(case_id + 1) % 5}));")
        else:
            e.line("    Value := 0;")
            e.line("    for var I := 0 to 5 do")
            e.line("      try")
            e.line("        var Current := Box.Func(I + Bias and 3);")
            e.line("        Value := Value xor Current;")
            e.line("      finally")
            e.line("        Inc(Value, I);")
            e.line("      end;")
        e.check("modern-project", f"gb-modern-{case_id:04d}-value", "UInt32(Value)")
        e.check("modern-project", f"gb-modern-{case_id:04d}-tag", "GBHashAnsi(Box.Tag)")
        e.line("    Outer := nil;")
        e.line("    Box := Default(TGBFuncBox);")
        e.line("    Box2 := Default(TGBFuncBox);")
        e.line("  finally")
        e.line("    Owner.Free;")
        e.line("  end;")
        e.line("end;")
        e.line()
    e.line("{$endif}")
    e.line("{$endif}")
    e.line("{$endif}")
    return calls


def emit_ordinal_flow_forms(e: Emitter) -> list[str]:
    calls: list[str] = []
    e.line("{$ifndef GB_SKIP_ORDINAL_FLOW}")
    for case_id in range(128):
        proc = f"GBOrdinalFlow{case_id:04d}"
        calls.append(proc)
        seed = case_id * 97 + 3
        shape = case_id % 8
        e.line(f"procedure {proc};")
        e.line("var")
        e.line("  B, BLo, BHi: Byte;")
        e.line("  SI, SILo, SIHi: ShortInt;")
        e.line("  W, WLo, WHi: Word;")
        e.line("  Small, SmallLo, SmallHi: SmallInt;")
        e.line("  Flag: Boolean;")
        e.line("  Ch, ChLo, ChHi: AnsiChar;")
        e.line("  E, ELo, EHi: TGBDenseEnum;")
        e.line("  R, RLo, RHi: TGBSubrange;")
        e.line("  Count: Integer;")
        e.line("  Digest: UInt64;")
        e.line("begin")
        e.line("  Count := 0;")
        e.line("  Digest := UInt64($CBF29CE484222325);")
        if shape == 0:
            lo = 0 if case_id == 0 else (seed & 239)
            hi = 255 if case_id == 0 else min(255, lo + (case_id % 17))
            e.line(f"  BLo := Byte(GBNoInline({lo}));")
            e.line(f"  BHi := Byte(GBNoInline({hi}));")
            e.line("  for B := BLo to BHi do")
            e.line("  begin Inc(Count); Digest := (Digest xor B) * UInt64($100000001B3); end;")
        elif shape == 1:
            lo = -128 if case_id == 1 else -100 + (case_id % 80)
            hi = 127 if case_id == 1 else min(127, lo + (case_id % 19))
            e.line(f"  SILo := ShortInt(GBNoInline({lo}));")
            e.line(f"  SIHi := ShortInt(GBNoInline({hi}));")
            e.line("  for SI := SILo to SIHi do")
            e.line("  begin Inc(Count); Digest := (Digest xor UInt32(SI)) * UInt64($100000001B3); end;")
        elif shape == 2:
            lo = 65520 - (case_id % 8)
            hi = min(65535, lo + (case_id % 12))
            e.line(f"  WLo := Word(GBNoInline({lo}));")
            e.line(f"  WHi := Word(GBNoInline({hi}));")
            e.line("  for W := WLo to WHi do")
            e.line("  begin Inc(Count); Digest := (Digest xor W) * UInt64($100000001B3); end;")
        elif shape == 3:
            hi = 30000 + case_id
            lo = hi - (case_id % 23)
            e.line(f"  SmallHi := SmallInt(GBNoInline({hi}));")
            e.line(f"  SmallLo := SmallInt(GBNoInline({lo}));")
            e.line("  for Small := SmallHi downto SmallLo do")
            e.line("  begin Inc(Count); Digest := (Digest xor UInt32(Small)) * UInt64($100000001B3); end;")
        elif shape == 4:
            e.line("  for Flag := False to True do")
            e.line("  begin Inc(Count); Digest := (Digest xor Ord(Flag)) * UInt64($100000001B3); end;")
        elif shape == 5:
            lo = 32 + (case_id % 40)
            hi = lo + (case_id % 15)
            e.line(f"  ChLo := AnsiChar(GBNoInline({lo}));")
            e.line(f"  ChHi := AnsiChar(GBNoInline({hi}));")
            e.line("  for Ch := ChLo to ChHi do")
            e.line("  begin Inc(Count); Digest := (Digest xor Ord(Ch)) * UInt64($100000001B3); end;")
        elif shape == 6:
            e.line(f"  ELo := TGBDenseEnum(GBNoInline({case_id % 3}));")
            e.line(f"  EHi := TGBDenseEnum(GBNoInline({3 + case_id % 3}));")
            e.line("  for E := ELo to EHi do")
            e.line("  begin Inc(Count); Digest := (Digest xor Ord(E)) * UInt64($100000001B3); end;")
        else:
            lo = -17 + (case_id % 20)
            hi = min(23, lo + (case_id % 11))
            e.line(f"  RLo := TGBSubrange(GBNoInline({lo}));")
            e.line(f"  RHi := TGBSubrange(GBNoInline({hi}));")
            e.line("  for R := RLo to RHi do")
            e.line("  begin Inc(Count); Digest := (Digest xor UInt32(R)) * UInt64($100000001B3); end;")
        e.check("ordinal-flow", f"gb-ordinal-{case_id:04d}-count", "Count")
        e.check("ordinal-flow", f"gb-ordinal-{case_id:04d}-digest", "Digest")
        e.line("end;")
        e.line()
    e.line("{$endif}")
    return calls


def emit_set_range_forms(e: Emitter) -> list[str]:
    calls: list[str] = []
    e.line("{$ifndef GB_SKIP_SET_RANGE}")
    for case_id in range(128):
        proc = f"GBSetRange{case_id:04d}"
        calls.append(proc)
        e.line(f"procedure {proc};")
        e.line("var")
        e.line("  S, T: TGBByteSet;")
        e.line("  Lo, Hi: Byte;")
        e.line("  I, J, Count: Integer;")
        e.line("  Digest: UInt64;")
        e.line("begin")
        e.line("  S := [];")
        e.line("  T := [];")
        e.line("  for J := 0 to 5 do")
        e.line("  begin")
        e.line(f"    Lo := Byte(GBNoInline(({case_id} * 37 + J * 53 + 228) and 255));")
        e.line(f"    Hi := Byte(GBNoInline(({case_id} * 19 + J * 29 + 110) and 255));")
        e.line("    S := S + [Lo..Hi];")
        e.line("    if Lo <= Hi then")
        e.line("      for I := Lo to Hi do Include(T, Byte(I));")
        e.line("  end;")
        e.line("  Count := 0;")
        e.line("  Digest := UInt64($CBF29CE484222325);")
        e.line("  for I := 0 to 255 do")
        e.line("    if Byte(I) in S then")
        e.line("    begin Inc(Count); Digest := (Digest xor UInt32(I)) * UInt64($100000001B3); end;")
        e.check("set-range", f"gb-setrange-{case_id:04d}-count", "Count")
        e.check("set-range", f"gb-setrange-{case_id:04d}-digest", "Digest")
        e.check("set-range", f"gb-setrange-{case_id:04d}-model", "Ord(S = T)")
        e.line("end;")
        e.line()
    e.line("{$endif}")
    return calls


def emit_call_overload_forms(e: Emitter) -> list[str]:
    calls: list[str] = []
    e.line("{$ifndef GB_SKIP_CALL_OVERLOAD}")
    for case_id in range(160):
        proc = f"GBCallOverload{case_id:04d}"
        calls.append(proc)
        seed = case_id * 101 + 17
        shape = case_id % 8
        e.line(f"procedure {proc};")
        e.line("var")
        e.line("  A, B, C: TGBCallRec;")
        e.line("  Callback: TGBPlainCallback;")
        e.line("  V: Int64;")
        e.line("begin")
        e.line(f"  A := GBMakeCallRec(GBNoInline({seed}));")
        e.line(f"  B := GBMakeCallRec(GBNoInline({seed + 1}));")
        e.line("  C := Default(TGBCallRec);")
        if shape == 0:
            e.line("  V := GBOverload(A.I);")
        elif shape == 1:
            e.line("  V := GBOverload(Int64(A.I));")
        elif shape == 2:
            e.line(f"  V := GBOverload(Int64(A.I), {case_id % 31});")
        elif shape == 3:
            e.line("  V := GBOverload(A.S);")
        elif shape == 4:
            e.line("  GBCallMix(A, B, C); V := C.I xor B.I;")
        elif shape == 5:
            e.line("  C := GBMakeCallRec(B.I); GBCallMix(A, C, B); V := Integer(C.U xor B.U);")
        elif shape == 6:
            e.line("  Callback := GBPlainCallback; V := GBInvokeCallback(Callback, A.I, B.I);")
        else:
            e.line("  Callback := @GBPlainCallback; V := Callback(A.I, B.I) + GBOverload(Int64(B.I), A.I and 7);")
        e.check("call-overload", f"gb-call-{case_id:04d}-value", "UInt64(V)")
        e.check("call-overload", f"gb-call-{case_id:04d}-a", "GBCallRecDigest(A)")
        e.check("call-overload", f"gb-call-{case_id:04d}-b", "GBCallRecDigest(B)")
        e.check("call-overload", f"gb-call-{case_id:04d}-c", "GBCallRecDigest(C)")
        e.line("end;")
        e.line()
    e.line("{$endif}")
    return calls


CROSS_AXIS_SOURCES = (
    ("literal-small", "1"),
    ("untyped-const", "GBUntypedOne"),
    ("typed-integer-const", "GBTypedIntegerOne"),
    ("integer-local", "I"),
    ("integer-field", "Source.SignedField"),
    ("integer-property", "Source.SignedProperty"),
    ("integer-result", "GBIntegerValue(I)"),
    ("integer-generic-result", "TGBGenericOps<Integer>.Echo(I)"),
    ("typed-int64-const", "GBTypedInt64One"),
    ("int64-local", "I64"),
    ("typed-uint64-const", "GBTypedUInt64One"),
    ("uint64-local", "U2"),
    ("uint64-field", "Source.UnsignedField"),
    ("uint64-property", "Source.UnsignedProperty"),
    ("uint64-result", "GBUInt64Value(U2)"),
    ("uint64-generic-result", "TGBGenericOps<UInt64>.Echo(U2)"),
    ("literal-int32-high", "2147483647"),
    ("literal-uint32-low", "2147483648"),
    ("literal-uint32-high", "4294967295"),
    ("literal-int64-low", "4294967296"),
)

CROSS_AXIS_OPERATORS = (
    ("add", "+"),
    ("sub", "-"),
    ("mul", "*"),
    ("or", "or"),
    ("xor", "xor"),
    ("and", "and"),
    ("div", "div"),
    ("mod", "mod"),
)

CROSS_AXIS_CONSUMERS = (
    "kind",
    "pair-left",
    "pair-right",
    "pair-both",
    "assignment",
    "case",
    "loop-bound",
    "array-index",
)

CROSS_AXIS_CONTEXTS = (
    "direct",
    "runtime-if",
    "single-loop",
    "try-finally",
    "repeat-until",
    "nested-function",
    "with-record",
    "case-branch",
)


def cross_axis_consumer_lines(
    consumer: str, expression: str, target: str, indent: str
) -> list[str]:
    if consumer == "kind":
        return [f"{indent}{target} := GBOrdinalKind({expression});"]
    if consumer == "pair-left":
        return [f"{indent}{target} := GBPairKind(U, {expression});"]
    if consumer == "pair-right":
        return [f"{indent}{target} := GBPairKind({expression}, U);"]
    if consumer == "pair-both":
        return [f"{indent}{target} := GBPairKind({expression}, {expression});"]
    if consumer == "assignment":
        return [
            f"{indent}AssignedValue := {expression};",
            f"{indent}{target} := AssignedValue;",
        ]
    if consumer == "case":
        return [
            f"{indent}case UInt64({expression}) and 3 of",
            f"{indent}  0: {target} := 17;",
            f"{indent}  1: {target} := 34;",
            f"{indent}  2: {target} := 51;",
            f"{indent}else",
            f"{indent}  {target} := 68;",
            f"{indent}end;",
        ]
    if consumer == "loop-bound":
        return [
            f"{indent}{target} := 0;",
            f"{indent}for var LoopIndex := 0 to Integer(UInt64({expression}) and 7) do",
            f"{indent}  {target} := {target} + UInt64(LoopIndex + 1);",
        ]
    if consumer == "array-index":
        return [f"{indent}{target} := Values[Byte(UInt64({expression}))];"]
    raise ValueError(consumer)


def emit_cross_axis_forms(e: Emitter) -> list[str]:
    """Full source/operator/consumer product braided through AST contexts."""
    calls: list[str] = []
    e.line("{$ifndef GB_SKIP_CROSS_AXIS}")
    for source_id, (source_name, source_expression) in enumerate(CROSS_AXIS_SOURCES):
        for operator_id, (operator_name, operator_token) in enumerate(CROSS_AXIS_OPERATORS):
            expression = f"U {operator_token} {source_expression}"
            for consumer_id, consumer_name in enumerate(CROSS_AXIS_CONSUMERS):
                context_id = (source_id + 3 * operator_id + 5 * consumer_id) % len(CROSS_AXIS_CONTEXTS)
                context_name = CROSS_AXIS_CONTEXTS[context_id]
                proc = f"GBCrossAxisS{source_id:02d}O{operator_id:02d}C{consumer_id:02d}"
                calls.append(proc)
                actual_expression = expression
                if context_name == "with-record":
                    actual_expression = actual_expression.replace("Source.SignedField", "SignedField")
                    actual_expression = actual_expression.replace("Source.UnsignedField", "UnsignedField")
                    actual_expression = actual_expression.replace("Source.SignedProperty", "SignedProperty")
                    actual_expression = actual_expression.replace("Source.UnsignedProperty", "UnsignedProperty")
                name = f"gb-cross-{source_name}-{operator_name}-{consumer_name}-{context_name}"
                e.line(f"procedure {proc};")
                e.line("var")
                e.line("  Source: TGBOrdinalSource;")
                e.line("  U, U2, Actual: UInt64;")
                if consumer_name == "assignment":
                    e.line("  AssignedValue: UInt64;")
                e.line("  I: Integer;")
                e.line("  I64: Int64;")
                if (consumer_name == "array-index") or (context_name == "single-loop"):
                    e.line("  J: Integer;")
                if consumer_name == "array-index":
                    e.line("  Values: array[Byte] of Byte;")
                if context_name == "nested-function":
                    e.line("  function NestedEvaluate: UInt64;")
                    e.line("  begin")
                    for line in cross_axis_consumer_lines(
                        consumer_name, expression, "Result", "    "
                    ):
                        e.line(line)
                    e.line("  end;")
                e.line("begin")
                e.line("  U := 41;")
                e.line("  U2 := 1;")
                e.line("  I := 1;")
                e.line("  I64 := 1;")
                e.line("  Source.SignedField := 1;")
                e.line("  Source.UnsignedField := 1;")
                if consumer_name == "array-index":
                    e.line("  for J := 0 to High(Values) do")
                    e.line("    Values[J] := Byte(J xor $A5);")
                e.line("  Actual := 0;")
                if context_name == "direct":
                    for line in cross_axis_consumer_lines(
                        consumer_name, actual_expression, "Actual", "  "
                    ):
                        e.line(line)
                elif context_name == "runtime-if":
                    e.line("  if GBUInt64NoInline(U) = 41 then")
                    e.line("  begin")
                    for line in cross_axis_consumer_lines(
                        consumer_name, actual_expression, "Actual", "    "
                    ):
                        e.line(line)
                    e.line("  end")
                    e.line("  else")
                    e.line("    Actual := High(UInt64);")
                elif context_name == "single-loop":
                    e.line("  for J := 0 to Integer(GBUInt64NoInline(0)) do")
                    e.line("  begin")
                    for line in cross_axis_consumer_lines(
                        consumer_name, actual_expression, "Actual", "    "
                    ):
                        e.line(line)
                    e.line("  end;")
                elif context_name == "try-finally":
                    e.line("  try")
                    for line in cross_axis_consumer_lines(
                        consumer_name, actual_expression, "Actual", "    "
                    ):
                        e.line(line)
                    e.line("  finally")
                    e.line("    U2 := U2 xor 0;")
                    e.line("  end;")
                elif context_name == "repeat-until":
                    e.line("  repeat")
                    for line in cross_axis_consumer_lines(
                        consumer_name, actual_expression, "Actual", "    "
                    ):
                        e.line(line)
                    e.line("  until GBUInt64NoInline(1) = 1;")
                elif context_name == "nested-function":
                    e.line("  Actual := NestedEvaluate;")
                elif context_name == "with-record":
                    e.line("  with Source do")
                    e.line("  begin")
                    for line in cross_axis_consumer_lines(
                        consumer_name, actual_expression, "Actual", "    "
                    ):
                        e.line(line)
                    e.line("  end;")
                elif context_name == "case-branch":
                    e.line("  case Integer(GBUInt64NoInline(U) and 1) of")
                    e.line("    1:")
                    e.line("    begin")
                    for line in cross_axis_consumer_lines(
                        consumer_name, actual_expression, "Actual", "      "
                    ):
                        e.line(line)
                    e.line("    end;")
                    e.line("  else")
                    e.line("    Actual := High(UInt64);")
                    e.line("  end;")
                else:
                    raise ValueError(context_name)
                e.check("cross-axis", name, "Actual")
                e.line("end;")
                e.line()
    e.line("{$endif}")
    return calls


def cross_axis_manifest() -> dict[str, object]:
    tuples = []
    for source_id in range(len(CROSS_AXIS_SOURCES)):
        for operator_id in range(len(CROSS_AXIS_OPERATORS)):
            for consumer_id in range(len(CROSS_AXIS_CONSUMERS)):
                context_id = (source_id + 3 * operator_id + 5 * consumer_id) % len(CROSS_AXIS_CONTEXTS)
                tuples.append((source_id, operator_id, consumer_id, context_id))
    dimensions = (
        len(CROSS_AXIS_SOURCES),
        len(CROSS_AXIS_OPERATORS),
        len(CROSS_AXIS_CONSUMERS),
        len(CROSS_AXIS_CONTEXTS),
    )
    required_tuples = dimensions[0] * dimensions[1] * dimensions[2]
    if len(tuples) != required_tuples:
        raise AssertionError(
            f"cross-axis product is incomplete: {len(tuples)} != {required_tuples}"
        )
    pair_coverage: dict[str, dict[str, int]] = {}
    for left in range(len(dimensions)):
        for right in range(left + 1, len(dimensions)):
            covered = {(row[left], row[right]) for row in tuples}
            possible = dimensions[left] * dimensions[right]
            if len(covered) != possible:
                raise AssertionError(
                    f"cross-axis pair {left}-{right} is incomplete: "
                    f"{len(covered)} != {possible}"
                )
            pair_coverage[f"{left}-{right}"] = {
                "covered": len(covered),
                "possible": possible,
            }
    return {
        "dimensions": {
            "sources": [name for name, _ in CROSS_AXIS_SOURCES],
            "operators": [name for name, _ in CROSS_AXIS_OPERATORS],
            "consumers": list(CROSS_AXIS_CONSUMERS),
            "contexts": list(CROSS_AXIS_CONTEXTS),
        },
        "tuple_count": len(tuples),
        "full_source_operator_consumer_product": True,
        "pair_coverage": pair_coverage,
    }


def emit_managed_record_forms(e: Emitter) -> list[str]:
    calls: list[str] = []
    e.line("{$ifndef GB_SKIP_MANAGED_RECORD}")
    for case_id in range(96):
        body = f"GBManagedRecordBody{case_id:04d}"
        proc = f"GBManagedRecord{case_id:04d}"
        calls.append(proc)
        seed = case_id * 107 + 31
        shape = case_id % 8
        e.line(f"procedure {body}(out Value: Integer);")
        e.line("var")
        e.line("  A, B: TGBTracked;")
        e.line("  D: TGBTrackedArray;")
        e.line("begin")
        e.line(f"  A.Value := GBNoInline({seed});")
        if shape == 0:
            e.line("  B := A; Value := B.Value;")
        elif shape == 1:
            e.line(f"  B := GBMakeTracked({seed + 1}); A := B; Value := A.Value;")
        elif shape == 2:
            e.line("  SetLength(D, 3); D[0] := A; D[1] := D[0]; D[2] := GBMakeTracked(A.Value + 2); Value := D[0].Value + D[1].Value + D[2].Value;")
        elif shape == 3:
            e.line("  try B := A; Value := B.Value; finally B.Value := B.Value xor 17; end;")
        elif shape == 4:
            e.line("  B := A; B := B; A := A; Value := A.Value xor B.Value;")
        elif shape == 5:
            e.line("  SetLength(D, 4); D[3] := A; SetLength(D, 1); B := D[0]; Value := B.Value;")
        elif shape == 6:
            e.line("  B := Default(TGBTracked); B := A; Value := B.Value;")
        else:
            e.line("  B := GBMakeTracked(A.Value + 7); D := TGBTrackedArray.Create(A, B); Value := D[0].Value xor D[1].Value;")
        e.line("end;")
        e.line()
        e.line(f"procedure {proc};")
        e.line("var Init0, Value: Integer;")
        e.line("begin")
        e.line("  Init0 := GBTrackedInit;")
        e.line(f"  {body}(Value);")
        e.check("managed-record", f"gb-mrecord-{case_id:04d}-value", "UInt32(Value)")
        e.check(
            "managed-record",
            f"gb-mrecord-{case_id:04d}-init",
            "Ord((GBTrackedInit - Init0) > 0)",
            expected="0000000000000001",
        )
        e.line("end;")
        e.line()
    e.line("{$endif}")
    return calls


def emit_lifecycle_forms(e: Emitter) -> list[str]:
    calls: list[str] = []
    e.line("{$ifndef GB_SKIP_LIFECYCLE}")
    for case_id in range(96):
        proc = f"GBLifecycle{case_id:04d}"
        calls.append(proc)
        seed = case_id * 109 + 13
        fail = "True" if case_id % 3 == 1 else "False"
        e.line(f"procedure {proc};")
        e.line("var O: TGBLifecycle; Alive0, Created0, Destroyed0, After0, Before0, Value: Integer;")
        e.line("begin")
        e.line("  Alive0 := TGBLifecycle.Alive; Created0 := TGBLifecycle.Created;")
        e.line("  Destroyed0 := TGBLifecycle.Destroyed; After0 := TGBLifecycle.Aftered; Before0 := TGBLifecycle.Befored;")
        e.line("  O := nil; Value := -1;")
        e.line("  try")
        e.line(f"    O := TGBLifecycle.Create(GBNoInline({seed}), {fail});")
        e.line("    Value := O.Value;")
        e.line("  except")
        e.line("    on EArgumentException do Value := -2;")
        e.line("  end;")
        e.line("  O.Free;")
        e.check("lifecycle", f"gb-lifecycle-{case_id:04d}-value", "UInt32(Value)")
        e.check("lifecycle", f"gb-lifecycle-{case_id:04d}-alive", "UInt32(TGBLifecycle.Alive - Alive0)")
        e.check("lifecycle", f"gb-lifecycle-{case_id:04d}-created", "UInt32(TGBLifecycle.Created - Created0)")
        e.check("lifecycle", f"gb-lifecycle-{case_id:04d}-destroyed", "UInt32(TGBLifecycle.Destroyed - Destroyed0)")
        e.check("lifecycle", f"gb-lifecycle-{case_id:04d}-after", "UInt32(TGBLifecycle.Aftered - After0)")
        e.check("lifecycle", f"gb-lifecycle-{case_id:04d}-before", "UInt32(TGBLifecycle.Befored - Before0)")
        e.line("end;")
        e.line()
    e.line("{$endif}")
    return calls


def emit_float_abi_forms(e: Emitter) -> list[str]:
    calls: list[str] = []
    e.line("{$ifndef GB_SKIP_FLOAT_ABI}")
    for case_id in range(128):
        proc = f"GBFloatAbi{case_id:04d}"
        calls.append(proc)
        seed = case_id * 113 - 7000
        shape = case_id % 4
        e.line(f"procedure {proc};")
        e.line("var A, B: TGBFloatRec; Digest: UInt64; SBits: UInt32; DBits: UInt64;")
        e.line("begin")
        e.line(f"  A := GBMakeFloatRec(GBNoInline({seed}));")
        if shape == 0:
            e.line("  B := A; Digest := GBFloatRecDigest(B, 0.5);")
        elif shape == 1:
            e.line(f"  B := GBMakeFloatRec({seed + 3}); Digest := GBFloatRecDigest(A, B.S);")
        elif shape == 2:
            e.line("  B := A; B.S := B.S * 2.0; B.D := B.D / 4.0; Digest := GBFloatRecDigest(B, A.S);")
        else:
            e.line("  B := Default(TGBFloatRec); B.D := A.S + A.D; B.S := A.S - 0.25; B.I := A.I; Digest := GBFloatRecDigest(B, -0.5);")
        e.line("  Move(B.S, SBits, SizeOf(SBits)); Move(B.D, DBits, SizeOf(DBits));")
        e.check("float-abi", f"gb-floatabi-{case_id:04d}-digest", "Digest")
        e.check("float-abi", f"gb-floatabi-{case_id:04d}-single", "SBits")
        e.check("float-abi", f"gb-floatabi-{case_id:04d}-double", "DBits")
        e.check("float-abi", f"gb-floatabi-{case_id:04d}-integer", "UInt64(B.I)")
        e.line("end;")
        e.line()
    e.line("{$endif}")
    return calls


def emit_generic_composed_forms(e: Emitter) -> list[str]:
    calls: list[str] = []
    e.line("{$ifndef GB_SKIP_GENERIC_COMPOSED}")
    for case_id in range(128):
        proc = f"GBGenericComposed{case_id:04d}"
        calls.append(proc)
        seed = case_id * 127 + 5
        shape = case_id % 4
        e.line(f"procedure {proc};")
        e.line("var")
        e.line("  I, J: Integer;")
        e.line("  A, B: AnsiString;")
        e.line("  R1, R2: TGBCallRec;")
        e.line("  D: TArray<TGBCallRec>;")
        e.line("  G: TGBGenericClass<TGBCallRec>;")
        e.line("  Digest: UInt64;")
        e.line("begin")
        e.line(f"  I := GBNoInline({seed}); J := I xor $55AA;")
        e.line(f"  A := AnsiString('generic:{case_id}'); B := A + AnsiString(':b');")
        e.line("  R1 := GBMakeCallRec(I); R2 := GBMakeCallRec(J);")
        if shape == 0:
            e.line("  TGBGenericOps<Integer>.Swap(I, J); Digest := UInt64(UInt32(I)) shl 32 or UInt32(J);")
        elif shape == 1:
            e.line("  TGBGenericOps<AnsiString>.Swap(A, B); Digest := GBHashAnsi(TGBGenericOps<AnsiString>.Echo(A + B));")
        elif shape == 2:
            e.line("  TGBGenericOps<TGBCallRec>.Swap(R1, R2); Digest := GBCallRecDigest(TGBGenericOps<TGBCallRec>.Echo(R1));")
        else:
            e.line("  G := TGBGenericClass<TGBCallRec>.Create(R1);")
            e.line("  try R2 := G.Read; SetLength(D, 3); D[0] := R1; D[1] := R2; D[2] := TGBGenericOps<TGBCallRec>.Echo(D[0]); Digest := GBCallRecDigest(D[2]); finally G.Free; end;")
        e.check("generic-composed", f"gb-genericx-{case_id:04d}-digest", "Digest")
        e.check("generic-composed", f"gb-genericx-{case_id:04d}-i", "UInt32(I)")
        e.check("generic-composed", f"gb-genericx-{case_id:04d}-a", "GBHashAnsi(A)")
        e.check("generic-composed", f"gb-genericx-{case_id:04d}-record", "GBCallRecDigest(R2)")
        e.line("end;")
        e.line()
    e.line("{$endif}")
    return calls


def emit_thread_runtime_forms(e: Emitter) -> list[str]:
    calls: list[str] = []
    e.line("{$ifndef GB_SKIP_THREAD_RUNTIME}")
    for case_id in range(24):
        proc = f"GBThreadRuntime{case_id:04d}"
        calls.append(proc)
        e.line(f"procedure {proc};")
        e.line("var Workers: array[0..3] of TGBThreadProbe; I: Integer;")
        e.line("begin")
        e.line(f"  GBThreadOrdinal := {case_id * 1000 + 7};")
        e.line(f"  GBThreadText := AnsiString('main:{case_id}');")
        e.line("  for I := 0 to 3 do")
        e.line(f"    Workers[I] := TGBThreadProbe.Create({case_id * 211 + 17} + I * 37, {40 + case_id % 17});")
        e.line("  for I := 0 to 3 do Workers[I].Start;")
        e.line("  for I := 0 to 3 do Workers[I].WaitFor;")
        for worker in range(4):
            e.check("thread-runtime", f"gb-thread-{case_id:04d}-{worker}-digest", f"Workers[{worker}].Digest")
            e.check("thread-runtime", f"gb-thread-{case_id:04d}-{worker}-text", f"GBHashAnsi(Workers[{worker}].Text)")
        e.line("  for I := 0 to 3 do Workers[I].Free;")
        e.check("thread-runtime", f"gb-thread-{case_id:04d}-main-ordinal", "UInt32(GBThreadOrdinal)")
        e.check("thread-runtime", f"gb-thread-{case_id:04d}-main-text", "GBHashAnsi(GBThreadText)")
        e.line("end;")
        e.line()
    e.line("{$endif}")
    return calls


def emit_tracker_interaction_forms(e: Emitter) -> list[str]:
    """Compose independent tracker seeds instead of copying focused repros."""
    calls: list[str] = []
    e.line("type")
    e.line("  TGBTrackerRecord = packed record")
    e.line("    A: Int64;")
    e.line("    B: Integer;")
    e.line("    C: Word;")
    e.line("  end;")
    e.line("  TGBTrackerRecordArray = array of TGBTrackerRecord;")
    e.line()
    e.line("function GBTrackerEarly(Value: Integer): Boolean; inline;")
    e.line("begin")
    e.line("  Result := False;")
    e.line("  if Value = 0 then Exit;")
    e.line("  Result := True;")
    e.line("end;")
    e.line()
    e.line("function GBTrackerArray(A, B: Integer): TGBIntArray;")
    e.line("begin Result := TGBIntArray.Create(A, B); end;")
    e.line()
    e.line("function GBTrackerOpenDigest(const Records: array of TGBTrackerRecord;")
    e.line("  const Values: array of Integer): UInt64;")
    e.line("var I: Integer;")
    e.line("begin")
    e.line("  Result := UInt64(Length(Records)) xor (UInt64(Length(Values)) shl 32);")
    e.line("  for I := 0 to High(Records) do Result := Result xor UInt64(Records[I].A + Records[I].B * 17 + Records[I].C * 257);")
    e.line("  for I := 0 to High(Values) do Result := Result xor (UInt64(UInt32(Values[I])) shl ((I and 7) * 8));")
    e.line("end;")
    e.line()
    for case_id in range(128):
        proc = f"GBTrackerInteraction{case_id:04d}"
        calls.append(proc)
        seed = case_id * 7919 + 37
        lo = case_id & 0xFF
        hi = min(255, lo + (case_id % 9))
        e.line(f"procedure {proc};")
        e.line("var R: TGBTrackerRecord; A: TGBIntArray; B: Byte; Count: Integer; Digest: UInt64;")
        e.line("begin")
        e.line(f"  R.A := Int64({seed}) * 4294967295 + {case_id};")
        e.line(f"  R.B := {seed} xor $5A5A5A5A;")
        e.line(f"  R.C := Word({seed} and $FFFF);")
        e.line(f"  A := GBTrackerArray({seed}, {seed + 1}) + GBTrackerArray({seed + 2}, {seed + 3});")
        e.line(f"  Digest := GBTrackerOpenDigest([R], A) xor UInt64(R.A mod 3600000000) xor UInt64(R.A div 4294967295);")
        e.line("  Count := 0;")
        e.line(f"  for B := {lo} to {hi} do Inc(Count, B + 1);")
        e.check("tracker-interaction", f"gb-tracker-{case_id:04d}-digest", "Digest")
        e.check("tracker-interaction", f"gb-tracker-{case_id:04d}-count", "UInt32(Count)")
        e.check("tracker-interaction", f"gb-tracker-{case_id:04d}-early0", "Ord(GBTrackerEarly(0))")
        e.check("tracker-interaction", f"gb-tracker-{case_id:04d}-early1", f"Ord(GBTrackerEarly({case_id + 1}))")
        e.check("tracker-interaction", f"gb-tracker-{case_id:04d}-array", "UInt32(A[0] xor A[1] xor A[2] xor A[3])")
        e.line("end;")
        e.line()
    return calls


def guard_for_call(call: str) -> str:
    prefixes = (
        ("GBControl", "GB_SKIP_CONTROL"),
        ("GBAbiCase", "GB_SKIP_ABI"),
        ("GBArrayCase", "GB_SKIP_ARRAY_POINTER"),
        ("GBDispatch", "GB_SKIP_DISPATCH"),
        ("GBManagedRecord", "GB_SKIP_MANAGED_RECORD"),
        ("GBManaged", "GB_SKIP_MANAGED"),
        ("GBClosure", "GB_SKIP_CLOSURE"),
        ("GBGenericComposed", "GB_SKIP_GENERIC_COMPOSED"),
        ("GBGeneric", "GB_SKIP_GENERIC"),
        ("GBLayout", "GB_SKIP_LAYOUT_RTTI_VARIANT"),
        ("GBCompose", "GB_SKIP_COMPOSED"),
        ("GBString", "GB_SKIP_STRING"),
        ("GBException", "GB_SKIP_EXCEPTION"),
        ("GBNested", "GB_SKIP_NESTED"),
        ("GBDynArray", "GB_SKIP_DYNARRAY"),
        ("GBPropertyOperator", "GB_SKIP_PROPERTY_OPERATOR"),
        ("GBInterface", "GB_SKIP_INTERFACE"),
        ("GBLegacyProject", "GB_SKIP_LEGACY_PROJECT"),
        ("GBRttiValue", "GB_SKIP_RTTI_VALUE"),
        ("GBOrdinalFlow", "GB_SKIP_ORDINAL_FLOW"),
        ("GBSetRange", "GB_SKIP_SET_RANGE"),
        ("GBCallOverload", "GB_SKIP_CALL_OVERLOAD"),
        ("GBCrossAxis", "GB_SKIP_CROSS_AXIS"),
        ("GBLifecycle", "GB_SKIP_LIFECYCLE"),
        ("GBFloatAbi", "GB_SKIP_FLOAT_ABI"),
        ("GBThreadRuntime", "GB_SKIP_THREAD_RUNTIME"),
        ("GBTrackerInteraction", "GB_SKIP_TRACKER_INTERACTION"),
        ("GBModernProject", "GB_SKIP_MODERN_PROJECT"),
    )
    for prefix, guard in prefixes:
        if call.startswith(prefix):
            return guard
    raise ValueError(f"no diagnostic guard for {call}")


def generate(oracle: dict[str, str]) -> tuple[str, list[str], dict[str, int], int]:
    e = Emitter(oracle)
    e.line("{ Generated by scripts/generate_omni_breadth.py. Do not edit. }")
    e.line("{ Broad cross-mechanism source forms; each check has a fixed Delphi oracle. }")
    e.line("{$POINTERMATH ON}")
    e.line()
    emit_support(e)
    calls: list[str] = []
    calls += emit_control_forms(e)
    calls += emit_abi_forms(e)
    calls += emit_array_pointer_forms(e)
    calls += emit_dispatch_forms(e)
    calls += emit_managed_forms(e)
    closure_calls = emit_closure_forms(e)
    calls += emit_generic_forms(e)
    calls += emit_layout_rtti_variant_forms(e)
    calls += emit_composed_optimizer_forms(e)
    calls += emit_string_forms(e)
    calls += emit_exception_forms(e)
    calls += emit_nested_forms(e)
    calls += emit_array_lifetime_forms(e)
    calls += emit_property_operator_forms(e)
    calls += emit_interface_forms(e)
    calls += emit_legacy_project_forms(e)
    calls += emit_rtti_value_forms(e)
    calls += emit_ordinal_flow_forms(e)
    calls += emit_set_range_forms(e)
    calls += emit_call_overload_forms(e)
    calls += emit_cross_axis_forms(e)
    calls += emit_managed_record_forms(e)
    calls += emit_lifecycle_forms(e)
    calls += emit_float_abi_forms(e)
    calls += emit_generic_composed_forms(e)
    calls += emit_thread_runtime_forms(e)
    calls += emit_tracker_interaction_forms(e)
    inline_const_calls = emit_inline_const_forms(e)
    modern_project_calls = emit_modern_project_forms(e)
    e.line("procedure RunGeneratedBreadthCoreForms;")
    e.line("begin")
    for call in calls:
        guard = guard_for_call(call)
        e.line(f"{{$ifndef {guard}}}")
        e.line(f"  {call};")
        if call.startswith("GBManaged") and not call.startswith("GBManagedRecord"):
            case_id = int(call.removeprefix("GBManaged"))
            e.check("managed", f"gb-managed-{case_id:04d}-post", "TGBValueObject.Alive")
        e.line("{$endif}")
    e.line("end;")
    e.line()
    e.line("{$ifdef HAS_ANON}")
    e.line("procedure RunGeneratedBreadthModernForms;")
    e.line("begin")
    for call in closure_calls:
        e.line("{$ifndef GB_SKIP_CLOSURE}")
        e.line(f"  {call};")
        e.line("{$endif}")
    e.line("{$ifdef HAS_INLINEVAR}")
    for call in inline_const_calls:
        e.line("{$ifndef GB_SKIP_INLINE_CONST}")
        e.line(f"  {call};")
        e.check("inline-const", f"{call.lower()}-post", "TGBValueObject.Alive")
        e.line("{$endif}")
    for call in modern_project_calls:
        e.line("{$ifndef GB_SKIP_MODERN_PROJECT}")
        e.line(f"  {call};")
        e.line("{$endif}")
    e.line("{$endif}")
    e.line("end;")
    e.line("{$endif}")
    e.line()
    e.line("{$POINTERMATH OFF}")
    return "\n".join(e.lines), e.names, dict(sorted(e.families.items())), len(calls) + len(closure_calls) + len(inline_const_calls) + len(modern_project_calls)


def probe_source() -> str:
    return """program omni_generated_breadth_oracle;

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch anonymousfunctions}
  {$modeswitch functionreferences}
  {$modeswitch nestedprocvars}
  {$modeswitch INLINEVARS}
  {$modeswitch advancedrecords}
  {$define HAS_ANON}
  {$define HAS_INLINEVAR}
{$else}
  {$APPTYPE CONSOLE}
  {$define HAS_ANON}
  {$define HAS_INLINEVAR}
{$endif}
{$Q-}{$R-}

uses
{$ifdef FPC}
  {$ifdef UNIX}cthreads,{$endif}
  SysUtils, Variants, Classes, TypInfo, Rtti, Generics.Defaults,
  Generics.Collections;
{$else}
  System.SysUtils, System.Variants, System.Classes, System.TypInfo,
  System.Rtti, System.Generics.Defaults, System.Generics.Collections;
{$endif}

var
  RtZero: UInt64 = 0;

procedure GeneratedCheckU(const Name: AnsiString; Actual, Expected: UInt64);
begin
  WriteLn(string(Name), '=', IntToHex(Actual, 16));
end;

{$I omni_generated_breadth.inc}

begin
  RunGeneratedBreadthCoreForms;
  RunGeneratedBreadthModernForms;
end.
"""


ORACLE_RE = re.compile(r"^([a-z0-9-]+)=([0-9A-F]{16})$")


def capture_oracle(path: Path) -> dict[str, str]:
    raw = path.read_bytes()
    text = raw.decode("utf-16") if raw.startswith((b"\xff\xfe", b"\xfe\xff")) else raw.decode("utf-8-sig")
    result: dict[str, str] = {}
    for raw_line in text.splitlines():
        match = ORACLE_RE.fullmatch(raw_line.strip())
        if not match:
            continue
        name, value = match.groups()
        if name in result:
            raise SystemExit(f"duplicate oracle name: {name}")
        result[name] = value
    if not result:
        raise SystemExit(f"no oracle rows found in {path}")
    return result


def write_if_changed(path: Path, content: str) -> None:
    data = content.encode("utf-8")
    if not path.exists() or path.read_bytes() != data:
        path.write_bytes(data)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--capture", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    oracle = json.loads(ORACLE.read_text(encoding="utf-8")) if ORACLE.exists() else {}
    if args.capture:
        # Delphi cannot parse a small number of deliberate FPC-extension forms.
        # Their previously reviewed semantic oracles stay intact while a
        # Delphi run refreshes every row it actually executed.
        oracle.update(capture_oracle(args.capture))
        write_if_changed(ORACLE, json.dumps(oracle, indent=2, sort_keys=True) + "\n")

    generated, names, families, procedure_count = generate(oracle)
    missing = sorted(set(names) - set(oracle))
    extra = sorted(set(oracle) - set(names))
    manifest = {
        "schema": 1,
        "generator": "scripts/generate_omni_breadth.py",
        "case_count": len(names),
        "unique_case_count": len(set(names)),
        "procedure_count": procedure_count,
        "family_counts": families,
        "cross_axis": cross_axis_manifest(),
        "oracle_count": len(oracle),
        "oracle_complete": not missing and not extra,
        "missing_oracle_count": len(missing),
        "extra_oracle_count": len(extra),
    }
    expected = {
        GENERATED: generated,
        PROBE: probe_source(),
        MANIFEST: json.dumps(manifest, indent=2, sort_keys=True) + "\n",
    }
    if args.check:
        stale = [str(path.relative_to(ROOT)) for path, content in expected.items()
                 if not path.exists() or path.read_bytes() != content.encode("utf-8")]
        if stale:
            raise SystemExit("generated files are stale: " + ", ".join(stale))
        if missing or extra:
            raise SystemExit(f"oracle incomplete: missing={len(missing)} extra={len(extra)}")
        return
    for path, content in expected.items():
        write_if_changed(path, content)
    print(json.dumps(manifest, sort_keys=True))


if __name__ == "__main__":
    main()
