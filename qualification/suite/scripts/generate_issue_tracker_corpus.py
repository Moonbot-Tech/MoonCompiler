#!/usr/bin/env python3
"""Generate isolated Delphi-compatibility fixtures from ISSUE_TRACKER_FINDINGS."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "fixtures" / "tracker"
CASES: list[dict[str, object]] = []
STALE: list[str] = []

PARSER = argparse.ArgumentParser()
PARSER.add_argument("--check", action="store_true")
ARGS = PARSER.parse_args()


def runtime_case(case_id: str, declarations: str, run_body: str, placement: str = "corpus") -> None:
    slug = case_id.lower().replace("-", "_")
    source = f"""program tracker_{slug};

{{$ifdef FPC}}
  {{$mode delphiunicode}}{{$H+}}
  {{$modeswitch advancedrecords}}
  {{$modeswitch anonymousfunctions}}
  {{$modeswitch functionreferences}}
  {{$modeswitch nestedprocvars}}
  {{$modeswitch inlinevars}}
{{$endif}}
{{$APPTYPE CONSOLE}}
{{$Q-}}{{$R-}}

uses
  SysUtils, Classes, Math, Variants, TypInfo, Rtti,
  Generics.Defaults, Generics.Collections;

procedure Check(Condition: Boolean; const Name: string);
begin
  if not Condition then
    raise Exception.Create(Name);
end;

{declarations.strip()}

procedure Run;
begin
{run_body.strip()}
end;

begin
  try
    Run;
    WriteLn('PASS {case_id}');
  except
    on E: Exception do
    begin
      WriteLn('FAIL {case_id}: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
"""
    path = f"fixtures/tracker/{case_id.lower()}/{slug}.dpr"
    CASES.append({
        "id": case_id,
        "source": path,
        "oracle": "runtime-self-check",
        "placement": placement,
    })
    write(ROOT / path, source)


def compile_case(case_id: str, source: str, oracle: str = "compile-success", placement: str = "corpus") -> None:
    slug = case_id.lower().replace("-", "_")
    path = f"fixtures/tracker/{case_id.lower()}/{slug}.dpr"
    CASES.append({
        "id": case_id,
        "source": path,
        "oracle": oracle,
        "compile_only": True,
        "placement": placement,
    })
    write(ROOT / path, source.strip() + "\n")


def multi_case(
    case_id: str,
    sources: dict[str, str],
    main: str,
    oracle: str = "runtime-self-check",
    placement: str = "corpus",
    compile_only: bool = False,
) -> None:
    directory = ROOT / "fixtures" / "tracker" / case_id.lower()
    for name, source in sources.items():
        source = source.strip()
        if name.lower().endswith(".pas"):
            first, rest = source.split("\n", 1)
            source = (
                first + "\n"
                "{$ifdef FPC}{$mode delphiunicode}{$H+}"
                "{$modeswitch advancedrecords}"
                "{$modeswitch anonymousfunctions}"
                "{$modeswitch functionreferences}"
                "{$modeswitch nestedprocvars}"
                "{$modeswitch inlinevars}{$endif}\n" + rest
            )
        write(directory / name, source + "\n")
    CASES.append({
        "id": case_id,
        "source": f"fixtures/tracker/{case_id.lower()}/{main}",
        "oracle": oracle,
        "placement": placement,
        **({"compile_only": True} if compile_only else {}),
    })


def write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    data = content.encode("utf-8")
    if path.exists() and path.read_bytes() == data:
        return
    if ARGS.check:
        STALE.append(str(path.relative_to(ROOT)))
    else:
        path.write_bytes(data)


runtime_case("QP-01", r"""
type
  TBox<T> = class
  public type
    TCallback = procedure;
  public
    class procedure Invoke(Callback: TCallback = nil); static;
  end;

var
  CallbackCalls: Integer;

procedure MarkCalled;
begin
  Inc(CallbackCalls);
end;

class procedure TBox<T>.Invoke(Callback: TCallback);
begin
  Check(not Assigned(Callback) or (PPointer(@Callback)^ <> nil), 'partial-nil');
  if Assigned(Callback) then
    Callback;
end;
""", r"""
  CallbackCalls := 0;
  TBox<Integer>.Invoke;
  TBox<Integer>.Invoke(nil);
  TBox<Integer>.Invoke(MarkCalled);
  Check(CallbackCalls = 1, 'callback-count');
""")

runtime_case("QP-02", r"""
function RawCurrency(const Value: Currency): Int64;
begin
  Move(Value, Result, SizeOf(Result));
end;
""", r"""
  {$EXCESSPRECISION OFF}
  Check(RawCurrency(Currency(15) / Currency(12)) = 12500, '15-div-12');
  Check(RawCurrency(Currency(-15) / Currency(12)) = -12500, 'negative');
  Check(RawCurrency(Currency(16) / Currency(4)) = 40000, 'exact');
  {$EXCESSPRECISION ON}
  Check(RawCurrency(Currency(15) / Currency(12)) = 12500, 'on-control');
""")

compile_case("QP-03", r"""
program tracker_qp_03;
{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch anonymousfunctions}
  {$modeswitch functionreferences}
{$endif}
uses SysUtils;
type
  TCallback<T> = reference to procedure(const Value: T);
  IFoo = interface
    ['{0CCB8AFD-9D05-4B25-B8E1-1B5FF41CB1DB}']
    procedure Ping;
  end;
  TGate = class
    class procedure Test<T: IInterface>(const X: IInterface; const Callback: TCallback<T>); static;
  end;
class procedure TGate.Test<T>(const X: IInterface; const Callback: TCallback<T>);
begin
  Callback(X);
end;
var X: IInterface;
begin
  TGate.Test<IFoo>(X,
    procedure(const Value: IFoo)
    begin
    end);
end.
""", oracle="compile-rejection")

runtime_case("QP-04", r"""
procedure RaiseAndReplace;
begin
  try
    raise EArgumentException.Create('inner');
  except
    on E: EArgumentException do
    begin
      var MessageCopy := E.Message;
      raise Exception.Create(MessageCopy + ':replacement');
    end;
  end;
end;
""", r"""
  for var I := 1 to 128 do
  begin
    try
      RaiseAndReplace;
      Check(False, 'not-raised');
    except
      on E: Exception do
        Check(E.Message = 'inner:replacement', 'replacement-message');
    end;
    Check(ExceptObject = nil, 'exception-frame-not-cleared');
  end;
""")

runtime_case("QP-05", r"""
function EarlyFalse: Boolean;
var
  List: TList<TObject>;
  Item: TObject;
begin
  List := TList<TObject>.Create;
  try
    List.Add(TObject.Create);
    List.Add(TObject.Create);
    try
      for Item in List do
      begin
        Result := False;
        Exit;
      end;
      Result := True;
    finally
      for Item in List do
        Item.Free;
    end;
  finally
    List.Free;
  end;
end;
""", r"""
  Check(not EarlyFalse, 'early-false');
""", placement="corpus+omni")

runtime_case("QP-06", r"""
type
  TItem = class
    Id: Integer;
    constructor Create(AId: Integer);
  end;

constructor TItem.Create(AId: Integer);
begin
  inherited Create;
  Id := AId;
end;

function FindItem(const List: TObjectList<TItem>; Id: Integer): TItem; inline;
var
  Item: TItem;
begin
  for Item in List do
    if Item.Id = Id then
      Exit(Item);
  Result := nil;
end;
""", r"""
  var List := TObjectList<TItem>.Create(True);
  try
    List.Add(TItem.Create(11));
    List.Add(TItem.Create(22));
    Check(FindItem(List, 22) = List[1], 'found');
    Check(FindItem(List, 99) = nil, 'missing');
  finally
    List.Free;
  end;
""", placement="corpus+omni")

runtime_case("QP-07", r"""
type
  TIntThunk = reference to function: Integer;
  TWrapper = record
    Kind: Integer;
    Value: Integer;
    Thunk: TIntThunk;
    class operator Implicit(const Source: TIntThunk): TWrapper;
    class operator Implicit(Source: Integer): TWrapper;
    function Evaluate: Integer;
  end;

class operator TWrapper.Implicit(const Source: TIntThunk): TWrapper;
begin
  Result.Kind := 1;
  Result.Value := 0;
  Result.Thunk := Source;
end;

class operator TWrapper.Implicit(Source: Integer): TWrapper;
begin
  Result.Kind := 2;
  Result.Value := Source;
  Result.Thunk := nil;
end;

function TWrapper.Evaluate: Integer;
begin
  if Assigned(Thunk) then
    Result := Thunk()
  else
    Result := Value;
end;
""", r"""
  var Calls := 0;
  var Value: TWrapper :=
    function: Integer
    begin
      Inc(Calls);
      Result := 7;
    end;
  Check(Calls = 0, 'called-during-conversion');
  Check(Value.Kind = 1, 'wrong-overload');
  Check(Value.Evaluate = 7, 'evaluation');
  Check(Calls = 1, 'call-count');
""", placement="corpus+omni")

runtime_case("QP-08", r"""
type
  TPositive = 0..High(Int64);

procedure Take(Value: TPositive);
begin
  if Value = 123 then
    Write('');
end;
""", r"""
  var Raised := False;
  var P: TPositive := 1;
  {$R+}
  try
    Take(-P);
  except
    on ERangeError do Raised := True;
  end;
  {$R-}
  Check(Raised, 'range-error-missing');
""")

runtime_case("QP-09", r"""
type
  TOpenArrayProbe = record
    LengthSeen: NativeInt;
    HighSeen: NativeInt;
    Sum: Integer;
    class operator Implicit(const Values: array of Byte): TOpenArrayProbe;
  end;

class operator TOpenArrayProbe.Implicit(const Values: array of Byte): TOpenArrayProbe;
begin
  Result.LengthSeen := Length(Values);
  Result.HighSeen := High(Values);
  Result.Sum := 0;
  for var Value in Values do
    Inc(Result.Sum, Value);
end;
""", r"""
  var Empty: TOpenArrayProbe := [];
  var One: TOpenArrayProbe := [7];
  var Many: TOpenArrayProbe := [1, 2, 3];
  Check((Empty.LengthSeen = 0) and (Empty.HighSeen = -1), 'empty');
  Check((One.LengthSeen = 1) and (One.HighSeen = 0) and (One.Sum = 7), 'one');
  Check((Many.LengthSeen = 3) and (Many.HighSeen = 2) and (Many.Sum = 6), 'many');
""", placement="corpus+omni")

runtime_case("QP-10", r"""
var
  CmrInit, CmrFini, CmrCopy: Integer;

type
  TWreckingBall = record
    Marker: Integer;
    class operator Initialize({$ifdef FPC}var{$else}out{$endif} Dest: TWreckingBall);
    class operator Finalize(var Dest: TWreckingBall);
{$ifdef FPC}
    class operator Copy(constref Source: TWreckingBall; var Dest: TWreckingBall);
{$else}
    class operator Assign(var Dest: TWreckingBall; const [ref] Source: TWreckingBall);
{$endif}
  end;
  TResultRec = record
    Text: string;
    Marker: Integer;
  end;

class operator TWreckingBall.Initialize({$ifdef FPC}var{$else}out{$endif} Dest: TWreckingBall);
begin Dest.Marker := 7; Inc(CmrInit); end;
class operator TWreckingBall.Finalize(var Dest: TWreckingBall);
begin Inc(CmrFini); end;
{$ifdef FPC}
class operator TWreckingBall.Copy(constref Source: TWreckingBall; var Dest: TWreckingBall);
{$else}
class operator TWreckingBall.Assign(var Dest: TWreckingBall; const [ref] Source: TWreckingBall);
{$endif}
begin Dest.Marker := Source.Marker; Inc(CmrCopy); end;

procedure ApplyWreckingBall(const Value: TWreckingBall);
begin Check(Value.Marker = 7, 'cmr-parameter'); end;

function MakeResult: TResultRec;
begin Result.Text := 'managed-result'; Result.Marker := 42; end;

procedure Consume(const Value: TResultRec);
begin Check((Value.Text = 'managed-result') and (Value.Marker = 42), 'result-temp'); end;
""", r"""
  var W: TWreckingBall;
  ApplyWreckingBall(W);
  Consume(MakeResult);
  Check(CmrInit >= 1, 'init');
""")

runtime_case("QP-11", r"""
var
  DataInit, DataFini: Integer;

type
  IMarker = interface
    ['{8E03114C-2B27-4D07-B313-806939F3D641}']
  end;
  TMarker = class(TInterfacedObject, IMarker);
  TData = record
    Value: Integer;
    class operator Initialize({$ifdef FPC}var{$else}out{$endif} Dest: TData);
    class operator Finalize(var Dest: TData);
  end;
  TSourceRec = record
    Intf: IMarker;
    Value: Integer;
    constructor Create(AValue: Integer);
    class operator Implicit(const Source: TSourceRec): TData;
  end;

class operator TData.Initialize({$ifdef FPC}var{$else}out{$endif} Dest: TData);
begin Dest.Value := 0; Inc(DataInit); end;
class operator TData.Finalize(var Dest: TData);
begin Inc(DataFini); end;
constructor TSourceRec.Create(AValue: Integer);
begin
  Check(Intf = nil, 'interface-not-zeroed');
  Intf := TMarker.Create;
  Value := AValue;
end;
class operator TSourceRec.Implicit(const Source: TSourceRec): TData;
begin Result.Value := Source.Value; end;
""", r"""
  var Data: TData := TSourceRec.Create(91);
  Check(Data.Value = 91, 'converted-value');
  Check(DataInit >= 1, 'data-init');
""")

runtime_case("QP-12", r"""
var LockInit, LockFini: Integer;
type
  TLocker = record
    Marker: Integer;
    class operator Initialize({$ifdef FPC}var{$else}out{$endif} Dest: TLocker);
    class operator Finalize(var Dest: TLocker);
  end;
  TBase = class
    Lock: TLocker;
  end;
  TChild = class(TBase)
    Text: WideString;
  end;
class operator TLocker.Initialize({$ifdef FPC}var{$else}out{$endif} Dest: TLocker);
begin Dest.Marker := 77; Inc(LockInit); end;
class operator TLocker.Finalize(var Dest: TLocker);
begin Inc(LockFini); end;
""", r"""
  var I0 := LockInit;
  var F0 := LockFini;
  var Child := TChild.Create;
  Check(Child.Lock.Marker = 77, 'base-field-init');
  Child.Text := 'wide';
  Child.Free;
  Check(LockInit - I0 = 1, 'init-count');
  Check(LockFini - F0 = 1, 'fini-count');
""")

runtime_case("QP-13", r"""
type
  TManagedResult = record
    Text: string;
  end;

function MakeManagedResult(Value: Integer): TManagedResult;
begin Result.Text := 'value:' + IntToStr(Value); end;

procedure JumpOverResults(DoJump: Boolean);
label Done;
begin
  if DoJump then
    goto Done;
  MakeManagedResult(1);
  MakeManagedResult(2);
Done:
end;
""", r"""
  for var I := 0 to 255 do
    JumpOverResults((I and 1) = 0);
""")

runtime_case("QP-14", r"""
type
  TBase<T> = class
    BaseField: NativeInt;
  end;
  TLevel1<T> = class(TBase<T>)
    Level1Field: NativeInt;
  end;
  TLevel2<T> = class(TLevel1<T>)
    Level2Field: NativeInt;
  end;
""", r"""
  var Value := TLevel2<Integer>.Create;
  try
    Value.BaseField := NativeInt($11111111);
    Value.Level1Field := NativeInt($22222222);
    Value.Level2Field := NativeInt($33333333);
    Check(Value.BaseField = NativeInt($11111111), 'base-field');
    Check(Value.Level1Field = NativeInt($22222222), 'level1-field');
    Check(Value.Level2Field = NativeInt($33333333), 'level2-field');
  finally
    Value.Free;
  end;
""", placement="corpus+omni")

runtime_case("QP-15", r"""
type
  TUInt64Array = array of UInt64;
  TArrayRecord = record
    Values: TUInt64Array;
    class operator Implicit(const Source: array of UInt64): TArrayRecord;
  end;
class operator TArrayRecord.Implicit(const Source: array of UInt64): TArrayRecord;
begin
  SetLength(Result.Values, Length(Source));
  for var I := 0 to High(Source) do Result.Values[I] := Source[I];
end;
procedure Verify(const Value: TArrayRecord; A, B: UInt64);
begin
  Check(Length(Value.Values) = 2, 'length');
  Check((Value.Values[0] = A) and (Value.Values[1] = B), 'payload');
end;
""", r"""
  var StaticValues: array[0..1] of UInt64;
  StaticValues[0] := 11;
  StaticValues[1] := 22;
  var DynamicValues: TUInt64Array := TUInt64Array.Create(11, 22);
  var R: TArrayRecord := [11, 22]; Verify(R, 11, 22);
  R := StaticValues; Verify(R, 11, 22);
  R := DynamicValues; Verify(R, 11, 22);
""", placement="corpus+omni")

runtime_case("QP-16", r"""
type TIntegerArray = array of Integer;
var Calls: Integer;
function GetArray(Tag: Integer): TIntegerArray;
begin Inc(Calls); Result := TIntegerArray.Create(Tag); end;
procedure Consume(const Values: array of Integer);
begin
  Check(Length(Values) = 2, 'length');
  Check((Values[0] = 11) and (Values[1] = 22), 'payload');
end;
""", r"""
  Calls := 0;
  Consume(GetArray(11) + GetArray(22));
  Check(Calls = 2, 'call-count');
""", placement="corpus+omni")

runtime_case("QP-17", r"""
function SayHello(const Values: array of Integer): string;
begin
  Check((Length(Values) = 1) and (Values[0] = 42), 'nested-values');
  Result := 'hello';
end;
procedure CheckArrays(const A, B, C: array of string);
begin
  Check((Length(A) = 1) and (A[0] = 'aa'), 'first');
  Check((Length(B) = 1) and (B[0] = 'hello'), 'second');
  Check((Length(C) = 1) and (C[0] = 'zz'), 'third');
end;
""", r"""
  CheckArrays(['aa'], [SayHello([42])], ['zz']);
""", placement="corpus+omni")

runtime_case("QP-18", r"""
const
  Table: array['A'..'Z'] of AnsiChar =
    ('Q','W','E','R','T','Y','U','I','O','P','A','S','D',
     'F','G','H','J','K','L','Z','X','C','V','B','N','M');
function DoubleLookup(Value: AnsiChar): AnsiChar; inline;
begin Result := Table[Table[Value]]; end;
""", r"""
  for var Code := Ord('A') to Ord('Z') do
  begin
    var C := AnsiChar(Code);
    var First: AnsiChar := Table[C];
    var Expected: AnsiChar := Table[First];
    Check(DoubleLookup(C) = Expected, 'double-lookup');
  end;
  Check((Table[Table['A']] = Table[Table['B']]) = (DoubleLookup('A') = DoubleLookup('B')), 'comparison');
""", placement="corpus+omni")

multi_case("QP-19", {
"qp19_enumerable.pas": r"""
unit qp19_enumerable;
interface
type
  TCountedEnumerator = class
  private
    FCurrent: Integer;
  public
    class var Alive: Integer;
    constructor Create;
    destructor Destroy; override;
    function MoveNext: Boolean;
    property Current: Integer read FCurrent;
  end;
  TCountedEnumerable = class
    function GetEnumerator: TCountedEnumerator;
  end;
implementation
constructor TCountedEnumerator.Create;
begin inherited Create; Inc(Alive); FCurrent := 0; end;
destructor TCountedEnumerator.Destroy;
begin Dec(Alive); inherited; end;
function TCountedEnumerator.MoveNext: Boolean;
begin Inc(FCurrent); Result := FCurrent <= 3; end;
function TCountedEnumerable.GetEnumerator: TCountedEnumerator;
begin Result := TCountedEnumerator.Create; end;
end.
""",
"qp19_consumer.pas": r"""
unit qp19_consumer;
interface
procedure RunLoops;
implementation
uses SysUtils, qp19_enumerable;
procedure Check(Value: Boolean; const Name: string);
begin if not Value then raise Exception.Create(Name); end;
procedure RunLoops;
var Source: TCountedEnumerable; Sum: Integer;
begin
  Source := TCountedEnumerable.Create;
  try
    Sum := 0;
    for var Value in Source do Inc(Sum, Value);
    Check(Sum = 6, 'complete');
    Check(TCountedEnumerator.Alive = 0, 'complete-lifetime');
    for var Value in Source do begin Check(Value = 1, 'break-value'); Break; end;
    Check(TCountedEnumerator.Alive = 0, 'break-lifetime');
  finally Source.Free; end;
end;
end.
""",
"qp_19.dpr": r"""
program tracker_qp_19;
{$ifdef FPC}{$mode delphiunicode}{$modeswitch inlinevars}{$endif}
uses qp19_consumer;
begin RunLoops; WriteLn('PASS QP-19'); end.
""",
}, "qp_19.dpr")

multi_case("QP-20", {
"qp20_map.pas": r"""
unit qp20_map;
interface
uses Generics.Collections;
type
  TPairEnumerator<K,V> = class(TEnumerator<TPair<K,V>>)
  private
    FDone: Boolean;
    FCurrent: TPair<K,V>;
  protected
    function DoGetCurrent: TPair<K,V>; override;
    function DoMoveNext: Boolean; override;
  public
    constructor Create(const AKey: K; const AValue: V);
  end;
  TMap<K,V> = class(TEnumerable<TPair<K,V>>)
  public type
    TEntry = TPair<K,V>;
  private
    FKey: K;
    FValue: V;
  protected
    function DoGetEnumerator: TEnumerator<TPair<K,V>>; override;
  public
    constructor Create(const AKey: K; const AValue: V);
  end;
implementation
constructor TPairEnumerator<K,V>.Create(const AKey: K; const AValue: V);
begin inherited Create; FCurrent := TPair<K,V>.Create(AKey, AValue); end;
function TPairEnumerator<K,V>.DoGetCurrent: TPair<K,V>;
begin Result := FCurrent; end;
function TPairEnumerator<K,V>.DoMoveNext: Boolean;
begin Result := not FDone; FDone := True; end;
constructor TMap<K,V>.Create(const AKey: K; const AValue: V);
begin inherited Create; FKey := AKey; FValue := AValue; end;
function TMap<K,V>.DoGetEnumerator: TEnumerator<TPair<K,V>>;
begin Result := TPairEnumerator<K,V>.Create(FKey, FValue); end;
end.
""",
"qp20_consumer.pas": r"""
unit qp20_consumer;
interface
procedure RunMap;
implementation
uses SysUtils, qp20_map;
procedure RunMap;
var Map: TMap<Integer,string>; Entry: TMap<Integer,string>.TEntry; Seen: Integer;
begin
  Map := TMap<Integer,string>.Create(7, 'seven');
  try
    Seen := 0;
    for Entry in Map do
    begin
      if (Entry.Key <> 7) or (Entry.Value <> 'seven') then
        raise Exception.Create('payload');
      Inc(Seen);
    end;
    if Seen <> 1 then raise Exception.Create('count');
  finally Map.Free; end;
end;
end.
""",
"qp_20.dpr": r"""
program tracker_qp_20;
{$ifdef FPC}{$mode delphiunicode}{$endif}
uses qp20_consumer;
begin RunMap; WriteLn('PASS QP-20'); end.
""",
}, "qp_20.dpr")

runtime_case("QP-22", r"""
type
  TIntArray = TArray<Integer>;
  TStringArray = TArray<string>;
  TUnrelatedAlias = TIntArray;
function Pick(const Values: TIntArray): Integer; overload;
begin Result := 1; end;
function Pick(const Values: TStringArray): Integer; overload;
begin Result := 2; end;
""", r"""
  Check(Pick([2]) = 1, 'literal-overload');
  var Typed: TUnrelatedAlias := [2];
  Check(Pick(Typed) = 1, 'alias-control');
""", placement="corpus+omni")

runtime_case("QP-23", r"""
type
  TMultiSetEntry<T> = record
    Value: T;
  end;
  TMultiSet<T> = class
  public type
    TEntry = TMultiSetEntry<T>;
  private
    FEntries: TArray<TEntry>;
  public
    procedure FillAndSort(const A, B, C: T);
    function At(Index: Integer): T;
  end;
procedure TMultiSet<T>.FillAndSort(const A, B, C: T);
begin
  SetLength(FEntries, 3);
  FEntries[0].Value := A; FEntries[1].Value := B; FEntries[2].Value := C;
  TArray.Sort<TEntry>(FEntries,
    TComparer<TEntry>.Construct(
      function(const Left, Right: TEntry): Integer
      begin Result := TComparer<T>.Default.Compare(Left.Value, Right.Value); end));
end;
function TMultiSet<T>.At(Index: Integer): T;
begin Result := FEntries[Index].Value; end;
""", r"""
  var Values := TMultiSet<Integer>.Create;
  try
    Values.FillAndSort(3, 1, 2);
    Check((Values.At(0) = 1) and (Values.At(1) = 2) and (Values.At(2) = 3), 'sorted');
  finally Values.Free; end;
""", placement="corpus")

multi_case("QP-24", {
"qp24_defaults.pas": r"""
unit qp24_defaults;
interface
procedure Test(Token: string = ''; Headers: TArray<Cardinal> = []);
implementation
procedure Test(Token: string = 'x'; Headers: TArray<Cardinal> = []);
begin end;
end.
""",
"qp_24.dpr": r"""
program tracker_qp_24;
{$ifdef FPC}{$mode delphiunicode}{$endif}
uses qp24_defaults;
begin Test; end.
""",
}, "qp_24.dpr", oracle="compile-rejection", compile_only=True)

runtime_case("QP-25", r"""
type
  TManaged = record
    Value: string;
    class var InitCount, FinalCount: Integer;
    {$ifdef FPC}
    class operator Initialize(var Dest: TManaged);
    {$else}
    class operator Initialize(out Dest: TManaged);
    {$endif}
    class operator Finalize(var Dest: TManaged);
  end;
  PManaged = ^TManaged;
{$ifdef FPC}
class operator TManaged.Initialize(var Dest: TManaged);
{$else}
class operator TManaged.Initialize(out Dest: TManaged);
{$endif}
begin Inc(InitCount); end;
class operator TManaged.Finalize(var Dest: TManaged);
begin Inc(FinalCount); end;
""", r"""
  TManaged.InitCount := 0; TManaged.FinalCount := 0;
  var Typed: PManaged;
  New(Typed);
  Typed^.Value := 'payload';
  var Raw := Pointer(Typed);
  Dispose(PManaged(Raw));
  Check(TManaged.InitCount = 1, 'initialize-count');
  Check(TManaged.FinalCount = 1, 'finalize-count');
""")

runtime_case("QP-26", r"""
type
  TAnonymous = reference to procedure;
  TGenericOwner<T> = class
  private
    FCounter: PInteger;
    procedure Touch;
  public
    constructor Create(ACounter: PInteger);
    procedure Run;
  end;
procedure Invoke(const Callback: TAnonymous);
begin Callback(); end;
constructor TGenericOwner<T>.Create(ACounter: PInteger);
begin inherited Create; FCounter := ACounter; end;
procedure TGenericOwner<T>.Touch;
begin Inc(FCounter^); end;
procedure TGenericOwner<T>.Run;
begin
  Invoke(procedure begin Touch; end);
end;
""", r"""
  var Counter := 0;
  var Owner := TGenericOwner<Integer>.Create(@Counter);
  try Owner.Run; finally Owner.Free; end;
  Check(Counter = 1, 'closure-only-reachability');
""", placement="corpus+omni")

runtime_case("QP-27", r"""
type EOuter = class(Exception); EInner = class(Exception);
procedure RaiseNested;
begin
  try
    raise EOuter.Create('outer');
  except
    on E: EOuter do
    begin
      try
        raise EInner.Create(E.Message + ':inner');
      except
        on E: EInner do raise;
      end;
    end;
  end;
end;
""", r"""
  for var I := 1 to 256 do
  begin
    try
      RaiseNested;
      Check(False, 'not-raised');
    except
      on E: EInner do Check(E.Message = 'outer:inner', 'message');
    end;
    Check(ExceptObject = nil, 'exception-state');
  end;
""")

runtime_case("QP-28", r"""
type
  TShort20 = string[20];
  TSearch<T> = class
    class function Contains(const Values: array of T; const Needle: T): Boolean; static;
  end;
class function TSearch<T>.Contains(const Values: array of T; const Needle: T): Boolean;
begin
  Result := False;
  for var Value in Values do
    if Value = Needle then Exit(True);
end;
""", r"""
  var A: TShort20 := 'ABC';
  var B: TShort20 := 'DEF';
  var C: TShort20 := 'XYZ';
  Check(TSearch<TShort20>.Contains([A, B, C], B), 'found');
  var Missing: TShort20 := 'NOPE';
  Check(not TSearch<TShort20>.Contains([A, B, C], Missing), 'missing');
""")

runtime_case("QP-29", r"""
type
  TSubrangeHolder<T> = class
  private
    FValue: 0..10;
  public
    procedure SetValue(Value: Integer); inline;
    function GetValue: Integer; inline;
  end;
procedure TSubrangeHolder<T>.SetValue(Value: Integer);
begin FValue := Value; end;
function TSubrangeHolder<T>.GetValue: Integer;
begin Result := FValue; end;
""", r"""
  var Holder := TSubrangeHolder<Integer>.Create;
  try Holder.SetValue(7); Check(Holder.GetValue = 7, 'subrange-field');
  finally Holder.Free; end;
""")

runtime_case("QP-30", r"""
type
  TNumber = record
    Value: Integer;
    class function Make(AValue: Integer): TNumber; static;
  end;
class function TNumber.Make(AValue: Integer): TNumber;
begin Result.Value := AValue; end;
function Slice(const Values: array of Integer; Count, Marker: Integer): TArray<Integer>;
begin
  SetLength(Result, Count);
  for var I := 0 to Count - 1 do Result[I] := Values[I] + Marker;
end;
procedure Consume(const Records: array of TNumber; const Values: array of Integer);
begin
  Check((Length(Records) = 1) and (Records[0].Value = 800), 'record-literal');
  Check((Length(Values) = 2) and (Values[0] = 1077) and (Values[1] = 977), 'function-array');
end;
""", r"""
  Consume([TNumber.Make(800)], Slice([1000, 900, 800], 2, 77));
""", placement="corpus+omni")

runtime_case("QP-31", r"""
type
  ITracked = interface
    ['{2C1AB237-995F-44E9-B506-C7E593351B04}']
    function Marker: Integer;
  end;
  TTracked = class(TInterfacedObject, ITracked)
  private
    FMarker: Integer;
  public
    class var Alive: Integer;
    constructor Create(AMarker: Integer);
    destructor Destroy; override;
    function Marker: Integer;
  end;
  TTrackedArray = array of ITracked;
constructor TTracked.Create(AMarker: Integer);
begin inherited Create; Inc(Alive); FMarker := AMarker; end;
destructor TTracked.Destroy;
begin Dec(Alive); inherited; end;
function TTracked.Marker: Integer;
begin Result := FMarker; end;
procedure ExerciseTrackedQueue;
var
  Queue: TQueue<TTrackedArray>;
  Input, Output: TTrackedArray;
begin
  Queue := TQueue<TTrackedArray>.Create;
  try
    SetLength(Input, 2);
    Input[0] := TTracked.Create(11); Input[1] := TTracked.Create(22);
    Queue.Enqueue(Input);
    Input := nil;
    Check(TTracked.Alive = 2, 'owned-by-queue');
    Output := Queue.Dequeue;
    Check((Length(Output) = 2) and (Output[0].Marker = 11) and (Output[1].Marker = 22), 'tracked-payload');
    Output := nil;
  finally Queue.Free; end;
end;
""", r"""
  var BytesQueue := TQueue<TBytes>.Create;
  try
    BytesQueue.Enqueue(TBytes.Create(1, 2));
    BytesQueue.Enqueue(TBytes.Create(3, 4, 5));
    var Bytes := BytesQueue.Dequeue;
    Check((Length(Bytes) = 2) and (Bytes[0] = 1) and (Bytes[1] = 2), 'bytes-first');
    Bytes := BytesQueue.Dequeue;
    Check((Length(Bytes) = 3) and (Bytes[2] = 5), 'bytes-second');
  finally BytesQueue.Free; end;
  ExerciseTrackedQueue;
  Check(TTracked.Alive = 0, 'final-lifetime');
""", placement="corpus+omni")

runtime_case("QP-32", r"""
type
  TUnary<TArg,TResult> = reference to function(const Value: TArg): TResult;
  TBinary<TLeft,TRight,TResult> = reference to function(const Left: TLeft; const Right: TRight): TResult;
  TCurry<TLeft,TRight,TResult> = class
    class function Build(const Func: TBinary<TLeft,TRight,TResult>): TUnary<TLeft,TUnary<TRight,TResult>>; static;
  end;
class function TCurry<TLeft,TRight,TResult>.Build(
  const Func: TBinary<TLeft,TRight,TResult>): TUnary<TLeft,TUnary<TRight,TResult>>;
begin
  Result :=
    function(const Left: TLeft): TUnary<TRight,TResult>
    begin
      Result :=
        function(const Right: TRight): TResult
        begin Result := Func(Left, Right); end;
    end;
end;
""", r"""
  var Join: TBinary<string,Integer,string> :=
    function(const Left: string; const Right: Integer): string
    begin Result := Left + ':' + IntToStr(Right); end;
  var Curried1 := TCurry<string,Integer,string>.Build(Join);
  var Curried2 := TCurry<string,Integer,string>.Build(Join);
  var A := Curried1('A');
  var B := Curried2('B');
  Check(A(1) = 'A:1', 'a1'); Check(B(2) = 'B:2', 'b2');
  Check(A(3) = 'A:3', 'a3'); Check(B(4) = 'B:4', 'b4');
""", placement="corpus+omni")

runtime_case("QP-34", r"""
type
  IValue = interface
    ['{086EE2D6-8D6B-4EEC-AED2-69B3285C4105}']
    procedure SetValue(const Value: Double);
    function GetValue: Double;
  end;
  TDelegate = class(TInterfacedObject, IValue)
  private FValue: Double;
  public procedure SetValue(const Value: Double); function GetValue: Double; end;
  TProxy = class(TInterfacedObject, IValue)
  private
    FDelegate: TDelegate;
    function GetDelegate: TDelegate;
  public
    destructor Destroy; override;
    property Delegate: TDelegate read GetDelegate implements IValue;
  end;
procedure TDelegate.SetValue(const Value: Double); begin FValue := Value; end;
function TDelegate.GetValue: Double; begin Result := FValue; end;
function Clobber(A, B, C, D: NativeInt): NativeInt;
begin Result := A xor B xor C xor D; end;
function TProxy.GetDelegate: TDelegate;
begin
  if Clobber(11,22,33,44) = -1 then raise Exception.Create('unreachable');
  if FDelegate = nil then FDelegate := TDelegate.Create;
  Result := FDelegate;
end;
destructor TProxy.Destroy;
begin FDelegate.Free; inherited; end;
""", r"""
  var Value: IValue := TProxy.Create;
  Value.SetValue(3.1415);
  Check(Abs(Value.GetValue - 3.1415) < 1e-15, 'double-abi');
  Value := nil;
""", placement="corpus+omni")

runtime_case("QP-35", r"""
type
  TCrud<T> = class
  public type
    TResultRecord = record
      ID: T;
    end;
    TReader = reference to function(const Value: TResultRecord): T;
    function Load(const Value: T): TResultRecord;
  end;
  TIntResult = TCrud<Integer>.TResultRecord;
  TIntResultHelper = record helper for TIntResult
    function ReadID: Integer;
  end;
function TCrud<T>.Load(const Value: T): TResultRecord;
begin Result.ID := Value; end;
function TIntResultHelper.ReadID: Integer;
begin Result := Self.ID; end;
""", r"""
  var Crud := TCrud<Integer>.Create;
  try
    var Item := Crud.Load(73);
    var Reader: TCrud<Integer>.TReader :=
      function(const Value: TIntResult): Integer
      begin Result := Value.ReadID; end;
    Check(Reader(Item) = 73, 'nested-helper-callback');
  finally Crud.Free; end;
""")

multi_case("QP-36", {
"qp36_base.pas": r"""
unit qp36_base;
interface
type
  TBase<T> = class
  protected
    function Data: Integer; virtual;
  end;
implementation
function TBase<T>.Data: Integer;
begin Result := 41; end;
end.
""",
"qp36_descendant.pas": r"""
unit qp36_descendant;
interface
uses qp36_base;
type
  TUnrelated = record Value: Integer; end;
  TUnrelatedHelper = record helper for TUnrelated
    function Data: Integer;
  end;
  TDescendant<T> = class(TBase<T>)
    function ReadData: Integer;
  end;
implementation
function TUnrelatedHelper.Data: Integer; begin Result := Self.Value + 1; end;
function TDescendant<T>.ReadData: Integer; begin Result := Data; end;
end.
""",
"qp_36.dpr": r"""
program tracker_qp_36;
{$ifdef FPC}{$mode delphiunicode}{$endif}
uses qp36_descendant;
var Value: TDescendant<Integer>;
begin
  Value := TDescendant<Integer>.Create;
  try if Value.ReadData <> 41 then Halt(1); finally Value.Free; end;
  WriteLn('PASS QP-36');
end.
""",
}, "qp_36.dpr")

runtime_case("QP-37", r"""
const VariantInputs: array[0..4] of Integer = (0, 42, 200, 15658, 65535);
function NarrowMax(Left, Right: Byte): Integer; overload;
begin if Left > Right then Result := Left else Result := Right; end;
function NarrowMax(Left, Right: Integer): Integer; overload;
begin if Left > Right then Result := Left else Result := Right; end;
""", r"""
  for var N in VariantInputs do
  begin
    var V: Variant := N;
    Check(Integer(Math.Max(V, 100)) = Math.Max(N, 100), 'math-max-' + IntToStr(N));
    Check(Integer(Math.Min(V, 100)) = Math.Min(N, 100), 'math-min-' + IntToStr(N));
  end;
""", placement="corpus+omni")

runtime_case("QP-38", r"""
type
  TSmallRecord = record A, B: Integer; end;
  TCallback = procedure(const Value: TSmallRecord; Marker: Byte);
var CallbackCount: Integer;
procedure MarkCallback(const Value: TSmallRecord; Marker: Byte);
begin
  Check((Value.A = 111) and (Value.B = 222), 'record-abi');
  Check(Marker = 73, 'byte-abi');
  Inc(CallbackCount);
end;
procedure Exercise(Callback: TCallback);
var R: TSmallRecord; P: Pointer; Marker: Byte;
begin
  R.A := 111; R.B := 222; P := @R; Marker := 73;
  for var I := 0 to 15 do Inc(R.A, I and 0);
  if P <> @R then Halt(2);
  Callback(R, Marker);
end;
""", r"""
  CallbackCount := 0; Exercise(MarkCallback); Check(CallbackCount = 1, 'callback-count');
""", placement="corpus+omni")

runtime_case("QP-39", r"""
function RawCurrency(const Value: Currency): Int64;
begin Move(Value, Result, SizeOf(Result)); end;
function CurrencyFromRaw(Value: Int64): Currency;
begin Move(Value, Result, SizeOf(Result)); end;
""", r"""
  var A: Currency := CurrencyFromRaw(9223372036854770000);
  var B: Currency := CurrencyFromRaw(9223372036854769999);
  Check(RawCurrency(Math.Max(A, B)) = RawCurrency(A), 'max-order-1');
  Check(RawCurrency(Math.Max(B, A)) = RawCurrency(A), 'max-order-2');
  Check(RawCurrency(Math.Min(A, B)) = RawCurrency(B), 'min-order-1');
  Check(RawCurrency(Math.Min(B, A)) = RawCurrency(B), 'min-order-2');
""")

runtime_case("QP-40", r"""
function RawCurrency(const Value: Currency): Int64;
begin Move(Value, Result, SizeOf(Result)); end;
""", r"""
  var A: Currency := 12.3450;
  var B: Currency := -12.3450;
  Check(RawCurrency(SimpleRoundTo(A, -2)) = 123500, 'positive-half');
  Check(RawCurrency(SimpleRoundTo(B, -2)) = -123500, 'negative-half');
""")

runtime_case("QP-41", r"""
function Mod2147483647(Value: Int64): Int64; inline; begin Result := Value mod 2147483647; end;
function Mod2147483648(Value: Int64): Int64; inline; begin Result := Value mod 2147483648; end;
function Mod3600000000(Value: Int64): Int64; inline; begin Result := Value mod 3600000000; end;
function Mod4294967295(Value: Int64): Int64; inline; begin Result := Value mod 4294967295; end;
""", r"""
  var Value: Int64 := 9223372036854775000;
  Check(Mod2147483647(Value) = 2147482841, 'd2147483647');
  Check(Mod2147483648(Value) = 2147482840, 'd2147483648');
  Check(Mod3600000000(Value) = 54775000, 'd3600000000');
  Check(Mod4294967295(Value) = 2147482840, 'd4294967295');
  Check(Mod3600000000(-Value) = -54775000, 'negative');
""", placement="corpus+omni")

runtime_case("QP-42", r"""
function Div4294967295(Value: UInt64): UInt64; inline; begin Result := Value div UInt64(4294967295); end;
function Div4294967296(Value: UInt64): UInt64; inline; begin Result := Value div UInt64(4294967296); end;
function Div4294967297(Value: UInt64): UInt64; inline; begin Result := Value div UInt64(4294967297); end;
""", r"""
  var Value: UInt64 := High(UInt64);
  Check(Div4294967295(Value) = 4294967297, 'd4294967295');
  Check(Div4294967296(Value) = 4294967295, 'd4294967296');
  Check(Div4294967297(Value) = 4294967295, 'd4294967297');
  Check(Value mod UInt64(4294967295) = 0, 'r4294967295');
  Check(Value mod UInt64(4294967296) = 4294967295, 'r4294967296');
""", placement="corpus+omni")

runtime_case("QP-44", r"""
type
  ITracked = interface ['{E7316A62-50AD-4B4B-A31B-78B47B89D26A}'] end;
  TTracked = class(TInterfacedObject, ITracked)
  public class var Alive: Integer; constructor Create; destructor Destroy; override; end;
  TAction = reference to procedure;
constructor TTracked.Create; begin inherited; Inc(Alive); end;
destructor TTracked.Destroy; begin Dec(Alive); inherited; end;
procedure Execute(const Action: TAction); begin Action(); end;
""", r"""
  for var I := 1 to 100 do
  begin
    var Token: ITracked := TTracked.Create;
    Execute(procedure begin if Token = nil then Halt(2); end);
    Token := nil;
    Check(TTracked.Alive = 0, 'iteration-release-' + IntToStr(I));
  end;
""", placement="corpus+omni")

runtime_case("QP-45", r"""
type
  TPayload<T> = packed record
    Marker: Byte;
    Value: T;
    Tail: Word;
    class operator Equal(const Left, Right: TPayload<T>): Boolean;
  end;
class operator TPayload<T>.Equal(const Left, Right: TPayload<T>): Boolean;
begin Result := (Left.Marker = Right.Marker) and (Left.Value = Right.Value) and (Left.Tail = Right.Tail); end;
""", r"""
  var List := TList<TPayload<Integer>>.Create;
  try
    for var I := 1 to 8 do
    begin
      var Item: TPayload<Integer>;
      Item.Marker := I; Item.Value := I * 10; Item.Tail := 1000 + I;
      List.Add(Item);
    end;
    while List.Count > 0 do
    begin
      var Item := List[List.Count div 2];
      Check(List.Remove(Item) >= 0, 'remove');
    end;
    Check(List.Count = 0, 'empty');
  finally List.Free; end;
""", placement="corpus+omni")

runtime_case("QP-46", r"""
procedure WriteValue(out Dest: TValue; const Source: string);
begin Dest := TValue.From<string>(Source); end;
""", r"""
  var Values: array[0..3] of string;
  Values[0] := 'aa'; Values[1] := 'bb'; Values[2] := 'cc'; Values[3] := 'dd';
  for var S in Values do
  begin
    var Value: TValue;
    WriteValue(Value, S);
    Check(Value.AsString = S, 'tvalue-' + S);
  end;
""", placement="corpus+omni")

runtime_case("QP-47", r"""
type TItem = record Text: string; Marker: Integer; end;
""", r"""
  var List := TList<TItem>.Create;
  try
    for var I := 1 to 16 do
    begin var Item: TItem; Item.Text := 'item-' + IntToStr(I); Item.Marker := I; List.Add(Item); end;
    for var Pass := 1 to 4 do
    begin
      var Sum := 0;
      for var Item in List do
      begin Check(Item.Text = 'item-' + IntToStr(Item.Marker), 'payload'); Inc(Sum, Item.Marker); end;
      Check(Sum = 136, 'sum');
    end;
  finally List.Free; end;
""", placement="corpus+omni")

runtime_case("QP-48", r"""
""", r"""
  var Dictionary := TDictionary<string,TObject>.Create;
  try
    var A := TObject.Create; var B := TObject.Create;
    Dictionary.Add('a', A); Dictionary.Add('b', B);
    var Seen := 0;
    for var Pair in Dictionary do
    begin Check(((Pair.Key = 'a') and (Pair.Value = A)) or ((Pair.Key = 'b') and (Pair.Value = B)), 'pair'); Inc(Seen); end;
    Check(Seen = 2, 'count');
    A.Free; B.Free;
  finally Dictionary.Free; end;
""", placement="corpus+omni")

runtime_case("QP-49", r"""
type
  ITracked = interface ['{525437FD-9E11-4F23-93AA-54A1753960D2}'] end;
  TTracked = class(TInterfacedObject, ITracked)
  public class var Alive: Integer; constructor Create; destructor Destroy; override; end;
constructor TTracked.Create; begin inherited; Inc(Alive); end;
destructor TTracked.Destroy; begin Dec(Alive); inherited; end;
procedure ExerciseInterfaces;
var Values: TArray<ITracked>;
begin
  SetLength(Values, 3);
  for var I := 0 to High(Values) do Values[I] := TTracked.Create;
  for var Value in Values do if Value = nil then Halt(2);
  Values := nil;
end;
""", r"""
  ExerciseInterfaces;
  Check(TTracked.Alive = 0, 'post-loop-lifetime');
""", placement="corpus+omni")

runtime_case("QP-50", r"""
type
  TKey = class
  public Value: Integer; class var DestroyedA, DestroyedB: Integer; constructor Create(AValue: Integer); destructor Destroy; override; end;
  TKeyComparer = class(TInterfacedObject, IEqualityComparer<TKey>)
    function Equals(const Left, Right: TKey): Boolean;
    {$ifdef FPC}
    function GetHashCode(const Value: TKey): Cardinal;
    {$else}
    function GetHashCode(const Value: TKey): Integer;
    {$endif}
  end;
constructor TKey.Create(AValue: Integer); begin inherited Create; Value := AValue; end;
destructor TKey.Destroy; begin if Self.Value = 101 then Inc(DestroyedA) else Inc(DestroyedB); inherited; end;
function TKeyComparer.Equals(const Left, Right: TKey): Boolean; begin Result := Left.Value mod 100 = Right.Value mod 100; end;
{$ifdef FPC}
function TKeyComparer.GetHashCode(const Value: TKey): Cardinal;
{$else}
function TKeyComparer.GetHashCode(const Value: TKey): Integer;
{$endif}
begin Result := Value.Value mod 100; end;
""", r"""
  TKey.DestroyedA := 0; TKey.DestroyedB := 0;
  var Dictionary := TObjectDictionary<TKey,Integer>.Create([doOwnsKeys], TKeyComparer.Create);
  var Stored := TKey.Create(101); var Probe := TKey.Create(201);
  Dictionary.Add(Stored, 7);
  Dictionary.Remove(Probe);
  Check(not Dictionary.ContainsKey(Probe), 'remove');
  Check((TKey.DestroyedA = 1) and (TKey.DestroyedB = 0), 'stored-key-destroyed');
  Probe.Free; Dictionary.Free;
  Check((TKey.DestroyedA = 1) and (TKey.DestroyedB = 1), 'probe-caller-owned');
""", placement="corpus+omni")

runtime_case("QP-51", r"""
type
  TObjectAction = reference to procedure(Value: TObject);
  TPlainAction = reference to procedure;
  TMarkerObject = class
  public Marker: Integer; constructor Create(AMarker: Integer); end;
constructor TMarkerObject.Create(AMarker: Integer); begin inherited Create; Marker := AMarker; end;
function Pick(Value: TObject): Integer; overload; begin Result := TMarkerObject(Value).Marker; Value.Free; end;
function Pick(const Value: TPlainAction): Integer; overload; begin Value(); Result := -1; end;
""", r"""
  Check(Pick(TMarkerObject.Create(73)) = 73, 'constructor-expression');
""")

runtime_case("QP-52", r"""
type
  TOwner<T> = class
  public type
    TResult = record Value: T; end;
    TEnvelope = record Item: TResult; end;
    TFactory = reference to function: TEnvelope;
    class function SafeCall(const Factory: TFactory): TEnvelope; static;
  end;
class function TOwner<T>.SafeCall(const Factory: TFactory): TEnvelope;
begin Result := Factory(); end;
""", r"""
  var Value := TOwner<Integer>.SafeCall(
    function: TOwner<Integer>.TEnvelope
    begin Result := Default(TOwner<Integer>.TEnvelope); Result.Item.Value := 73; end);
  Check(Value.Item.Value = 73, 'nested-default-callback');
""")

runtime_case("QP-53", r"""
type
  TOuter<T> = class
  public type TInner<U> = record First: T; Second: U; end;
  end;
  TSpecial = TOuter<Integer>.TInner<string>;
  THolder = record Value: TSpecial; end;
  TObjectHolder = class Value: TSpecial; end;
""", r"""
  var Local: TSpecial; Local.First := 7; Local.Second := 'seven';
  var ArrayValue: TArray<TSpecial> := [Local];
  var RecordValue: THolder; RecordValue.Value := Local;
  var ObjectValue := TObjectHolder.Create;
  try ObjectValue.Value := Local;
    Check((ArrayValue[0].Second = 'seven') and (RecordValue.Value.First = 7) and (ObjectValue.Value.Second = 'seven'), 'aggregate-forms');
  finally ObjectValue.Free; end;
""")

runtime_case("SO-01", r"""
type
  TBase = class
    procedure Setup(const Values: array of Integer); virtual;
  end;
  TChild = class(TBase)
    procedure Setup(const Values: array of Integer); override;
  end;
procedure TBase.Setup(const Values: array of Integer);
begin
  if Length(Values) = 0 then Check(High(Values) = -1, 'empty-high')
  else begin Check(High(Values) = Length(Values) - 1, 'high'); for var I := 0 to High(Values) do Check(Values[I] = I + 10, 'payload'); end;
end;
procedure TChild.Setup(const Values: array of Integer);
begin inherited; end;
""", r"""
  var Child := TChild.Create;
  try Child.Setup([]); Child.Setup([10]); Child.Setup([10, 11, 12]); finally Child.Free; end;
""", placement="corpus+omni")

runtime_case("SO-02", r"""
function ProcessNumber(Value: Integer): Boolean; inline;
begin Result := False; if Value = 0 then Exit; Result := True; end;
procedure Sink(Value: Boolean; Expected: Boolean);
begin Check(Value = Expected, 'sink'); end;
""", r"""
  Sink(ProcessNumber(0), False); Sink(ProcessNumber(1), True);
""", placement="corpus+omni")

runtime_case("SO-03", r"""
type
  TEntityBase = class Base: NativeInt; end;
  TEntity<TKey> = class(TEntityBase) Key: TKey; end;
  TMyEntity2 = class;
  TMyEntity1 = class(TEntity<Integer>) Marker: NativeInt; end;
  TMyEntity2 = class(TEntity<Integer>) Other: NativeInt; end;
""", r"""
  var Value := TMyEntity1.Create;
  try Value.Base := 11; Value.Key := 22; Value.Marker := 33;
    Check((Value.Base = 11) and (Value.Key = 22) and (Value.Marker = 33), 'layout');
  finally Value.Free; end;
""")

runtime_case("SO-04", r"""
type
  ITracked = interface ['{84F55ED3-E50D-442E-87F7-35C9E769EAAA}'] end;
  TTracked = class(TInterfacedObject, ITracked)
  public class var Alive: Integer; constructor Create; destructor Destroy; override; end;
  TTrackedArray = array of ITracked;
constructor TTracked.Create; begin inherited; Inc(Alive); end;
destructor TTracked.Destroy; begin Dec(Alive); inherited; end;
procedure ExerciseList;
var List: TList<TTrackedArray>; OldValue, NewValue: TTrackedArray;
begin
  List := TList<TTrackedArray>.Create;
  try
    OldValue := TTrackedArray.Create(TTracked.Create); List.Add(OldValue); OldValue := nil;
    NewValue := TTrackedArray.Create(TTracked.Create); List[0] := NewValue; NewValue := nil;
    Check(TTracked.Alive = 1, 'replacement-release');
  finally List.Free; end;
end;
""", r"""
  ExerciseList; Check(TTracked.Alive = 0, 'final-release');
""", placement="corpus+omni")

runtime_case("SO-05", r"""
type
  ITracked = interface ['{F6EBBE46-90CF-4FB4-B95F-546FF4E53E9C}'] end;
  TTracked = class(TInterfacedObject, ITracked)
  public class var Alive: Integer; constructor Create; destructor Destroy; override; end;
  TAction = reference to procedure;
constructor TTracked.Create; begin inherited; Inc(Alive); end;
destructor TTracked.Destroy; begin Dec(Alive); inherited; end;
function MakeProc: TAction;
begin
  var Token: ITracked := TTracked.Create;
  Result := procedure begin if Token = nil then Halt(2); end;
end;
""", r"""
  var First := MakeProc; var Second := First;
  Check(TTracked.Alive = 1, 'alive=' + IntToStr(TTracked.Alive));
  First := nil;
  Check(TTracked.Alive = 1, 'copy-alive=' + IntToStr(TTracked.Alive));
  Second := nil;
  Check(TTracked.Alive = 0, 'released=' + IntToStr(TTracked.Alive));
""", placement="corpus+omni")

runtime_case("SO-06", r"""
type
  TManaged = record
    Value: string;
    class var InitCount, FinalCount: Integer;
    {$ifdef FPC}class operator Initialize(var Dest: TManaged); class operator Copy(constref Src: TManaged; var Dest: TManaged);
    {$else}class operator Initialize(out Dest: TManaged); class operator Assign(var Dest: TManaged; const [ref] Src: TManaged);
    {$endif}class operator Finalize(var Dest: TManaged);
  end;
{$ifdef FPC}class operator TManaged.Initialize(var Dest: TManaged); begin Inc(InitCount); end;
class operator TManaged.Copy(constref Src: TManaged; var Dest: TManaged); begin Dest.Value := Src.Value; end;
{$else}class operator TManaged.Initialize(out Dest: TManaged); begin Inc(InitCount); end;
class operator TManaged.Assign(var Dest: TManaged; const [ref] Src: TManaged); begin Dest.Value := Src.Value; end;
{$endif}class operator TManaged.Finalize(var Dest: TManaged); begin Inc(FinalCount); end;
""", r"""
  var Dictionary := TDictionary<Integer,TManaged>.Create;
  try var Value: TManaged; Value.Value := 'payload'; Dictionary.Add(7, Value);
    var ReadValue: TManaged; Check(Dictionary.TryGetValue(7, ReadValue) and (ReadValue.Value = 'payload'), 'payload');
    Dictionary.Remove(7);
  finally Dictionary.Free; end;
""")

runtime_case("SO-07", r"""
type
  ITest = interface ['{12E78E26-9AA3-4371-B670-F4355B272944}'] procedure Ping; end;
  TComponentLike = class(TInterfacedObject, ITest) procedure Ping; virtual; end;
  TGenericBase<T: TComponentLike> = class(TInterfacedObject) protected FTarget: T; end;
  TAdapter = class(TGenericBase<TComponentLike>, ITest)
  private function GetTarget: TComponentLike;
  public constructor Create; destructor Destroy; override; property Target: TComponentLike read GetTarget implements ITest; end;
var PingCount: Integer;
procedure TComponentLike.Ping; begin Inc(PingCount); end;
constructor TAdapter.Create; begin inherited; FTarget := TComponentLike.Create; FTarget._AddRef; end;
destructor TAdapter.Destroy; begin FTarget._Release; inherited; end;
function TAdapter.GetTarget: TComponentLike; begin Result := FTarget; end;
""", r"""
  PingCount := 0; var Value: ITest := TAdapter.Create; Value.Ping; Check(PingCount = 1, 'implements'); Value := nil;
""")

runtime_case("SO-08", r"""
type
  TKind = (kOne, kTwo);
  TKindHelper = record helper for TKind
    function GetIsTwo: Boolean; inline;
    property IsTwo: Boolean read GetIsTwo;
  end;
  THolder = class private FKind: TKind; function GetKind: TKind; public constructor Create(AKind: TKind); function IsTwo: Boolean; inline; end;
function TKindHelper.GetIsTwo: Boolean; begin Result := Self = kTwo; end;
constructor THolder.Create(AKind: TKind); begin inherited Create; FKind := AKind; end;
function THolder.GetKind: TKind; begin Result := FKind; end;
function THolder.IsTwo: Boolean; begin Result := GetKind.IsTwo; end;
""", r"""
  var A := THolder.Create(kOne); var B := THolder.Create(kTwo);
  try Check(not A.IsTwo, 'one'); Check(B.IsTwo, 'two'); finally A.Free; B.Free; end;
""")

multi_case("SO-09", {
"so09_init.pas": r"""
unit so09_init;
interface
type TAction = reference to procedure;
var Action: TAction;
implementation
initialization
  Action := procedure
    var Values: array of Byte;
    begin SetLength(Values, 3); Values[0] := 1; Values[1] := 2; Values[2] := 3; if Values[2] <> 3 then Halt(2); end;
finalization
  Action := nil;
end.
""",
"so_09.dpr": r"""
program tracker_so_09;
{$ifdef FPC}{$mode delphiunicode}{$modeswitch anonymousfunctions}{$modeswitch functionreferences}{$endif}
uses so09_init;
begin Action(); WriteLn('PASS SO-09'); end.
""",
}, "so_09.dpr")

runtime_case("SO-10", r"""
type TLarge = record A, B, C, D: Cardinal; end;
function MakeLarge(Tag: Cardinal): TLarge;
begin Result.A := Tag; Result.B := Tag + 1; Result.C := Tag + 2; Result.D := Tag + 3; end;
procedure Verify(const Value: TLarge; Tag: Cardinal);
begin Check((Value.A=Tag) and (Value.B=Tag+1) and (Value.C=Tag+2) and (Value.D=Tag+3), 'payload'); end;
""", r"""
  var List := TList<TLarge>.Create;
  try List.Add(MakeLarge(10)); List.Add(MakeLarge(30)); List.Insert(1, MakeLarge(20)); List.Insert(0, MakeLarge(0)); List.Insert(List.Count, MakeLarge(40));
    Check(List.Count=5,'count'); for var I:=0 to 4 do Verify(List[I], Cardinal(I*10));
  finally List.Free; end;
""", placement="corpus+omni")

runtime_case("SO-11", r"""
type
  TArrayFactory<T> = class
    class function Make(const A, B: T): TArray<T>; static;
  end;
class function TArrayFactory<T>.Make(const A, B: T): TArray<T>;
begin Result := [A, B]; end;
""", r"""
  var Values := TArrayFactory<string>.Make('a','b');
  Check((Length(Values)=2) and (Values[0]='a') and (Values[1]='b'),'inferred-array');
""")

runtime_case("SO-13", r"""
type
  TOpenArrayProc<T> = procedure(var Values: array of T);
  TSwapper<T> = class
    class procedure SwapFirstLast(var Values: array of T); static;
  end;
class procedure TSwapper<T>.SwapFirstLast(var Values: array of T);
begin if Length(Values)>1 then begin var Temp:=Values[0]; Values[0]:=Values[High(Values)]; Values[High(Values)]:=Temp; end; end;
""", r"""
  var Values: TArray<Integer> := [1,2,3]; var Proc: TOpenArrayProc<Integer> := TSwapper<Integer>.SwapFirstLast;
  Proc(Values); Check((Values[0]=3) and (Values[2]=1),'swap');
""")

runtime_case("SO-14", r"""
type TIntMatrix = TArray<TArray<Integer>>;
""", r"""
  var Values: TIntMatrix; SetLength(Values,2,3);
  for var I:=0 to 1 do for var J:=0 to 2 do Values[I,J]:=I*10+J;
  Check((Length(Values)=2) and (Length(Values[0])=3) and (Values[1,2]=12),'matrix');
""")

runtime_case("SO-15", r"""
type
  ITracked = interface ['{0DD6DAF0-5E52-402B-8763-453910D2DB57}'] end;
  TTracked = class(TInterfacedObject,ITracked) public class var Alive:Integer; constructor Create; destructor Destroy; override; end;
  TAggregate = record Text:string; Ref:ITracked; Marker:Integer; end;
constructor TTracked.Create; begin inherited; Inc(Alive); end;
destructor TTracked.Destroy; begin Dec(Alive); inherited; end;
procedure Exercise;
begin var Value: TAggregate; Value.Text:='ok'; Value.Ref:=TTracked.Create; Value.Marker:=73; Check((Value.Text='ok') and (Value.Marker=73),'payload'); end;
""", r"""
  Exercise; Check(TTracked.Alive=0,'aggregate-release');
""", placement="corpus+omni")

runtime_case("SO-16", r"""
type
  TShort255=string[255];
  TGenericEcho<T> = class class function Echo(const Value:T):T; static; inline; end;
class function TGenericEcho<T>.Echo(const Value:T):T; begin Result:=Value; end;
""", r"""
  var A:TShort255:='abc'; var B:=TGenericEcho<TShort255>.Echo(A); Check(B=A,'short-echo');
  A:=StringOfChar('x',255); B:=TGenericEcho<TShort255>.Echo(A); Check(B=A,'short-max');
""", placement="corpus+omni")

runtime_case("SO-17", r"""
type TMethod=procedure of object; TAction=reference to procedure; TDummy=class procedure Ping; end;
var Calls:Integer;
procedure TDummy.Ping; begin Inc(Calls); end;
function Wrap(Method:TMethod):TAction;
begin Result:=procedure begin if Assigned(Method) then Method(); end; end;
""", r"""
  Calls:=0; var Empty:TMethod:=nil; var Action:=Wrap(Empty); Check(not Assigned(Empty),'method-nil'); Action(); Check(Calls=0,'no-call');
  var Dummy:=TDummy.Create; try var Live:TMethod:=Dummy.Ping; Action:=Wrap(Live); Action(); Check(Calls=1,'live-call'); finally Dummy.Free; end;
""", placement="corpus+omni")

runtime_case("SO-18", r"""
type
  IBase=interface ['{D0060E42-B860-456E-9C06-77ED237E8E3A}'] procedure Base; end;
  IDerived=interface(IBase) ['{73CA1644-ACB5-488C-A506-78E8B4FAF86C}'] procedure Derived; end;
  TImpl=class(TInterfacedObject,IDerived) procedure Base; procedure Derived; end;
  TStore<T:IBase>=class Value:T; end;
var InterfaceCalls:Integer;
procedure TImpl.Base; begin Inc(InterfaceCalls); end; procedure TImpl.Derived; begin Inc(InterfaceCalls); end;
""", r"""
  InterfaceCalls:=0; var Store:=TStore<IDerived>.Create; try Store.Value:=TImpl.Create; Store.Value.Base; Store.Value.Derived; Check(InterfaceCalls=2,'calls'); finally Store.Free; end;
""")

runtime_case("SO-19", r"""
type TIntFunc=reference to function:Integer;
function Invoke(const Func:TIntFunc):Integer; inline; begin Result:=Func(); end;
""", r"""
  for var I:=1 to 64 do begin var A:=Invoke(function:Integer begin Result:=11+I; end); var B:=Invoke(function:Integer begin Result:=101+I; end); Check(A=11+I,'first'); Check(B=101+I,'second'); end;
""", placement="corpus+omni")

runtime_case("MB-01", r"""
type
  TSparseEnum = (seZero, seOne, seThree = 3, seSeven = 7);
procedure CheckRoundTrip(Value: TSparseEnum);
begin
  var Box := TValue.From<TSparseEnum>(Value);
  Check(Ord(Box.AsType<TSparseEnum>) = Ord(Value),
    'roundtrip-' + IntToStr(Ord(Value)));
end;
""", r"""
  CheckRoundTrip(seZero);
  CheckRoundTrip(seOne);
  CheckRoundTrip(seThree);
  CheckRoundTrip(seSeven);
""")

runtime_case("MB-02", r"""
function ExerciseFinallyLoop(Seed: Integer; var Trail: AnsiString): Integer;
begin
  Result := Seed;
  for var I := 0 to 9 do
    try
      if (I + Seed) mod 4 = 0 then Continue;
      if I = 8 then Break;
      Inc(Result, I * 3);
    finally
      Trail := Trail + AnsiChar(65 + I);
    end;
end;
""", r"""
  var Trail: AnsiString := '';
  Check(ExerciseFinallyLoop(107, Trail) = 173, 'value');
  Check(Trail = 'ABCDEFGHI', 'finally-trail');
""")

runtime_case("MB-03", r"""
var RuntimeZero: UInt64 = 0;
function OpaqueWord(Value: Word): Word;
{$ifdef FPC}noinline;{$endif}
begin
  Result := Word(UInt64(Value) xor RuntimeZero);
end;
""", r"""
  var A: Word := OpaqueWord(65535);
  var B: Word := OpaqueWord(65534);
  var Product: UInt64 := UInt64(A * B);
  Check(Product = UInt64(4294770690), 'word-product');
""")

runtime_case("MB-04", r"""
var RuntimeBoundZero: UInt64 = 0;
function OpaqueBound(Value: Int64): Int64;
begin
  Result := Int64(UInt64(Value) xor RuntimeBoundZero);
end;
procedure CheckAscending;
var K, LowBound, HighBound, Count, Sum: Integer;
begin
  LowBound := 0;
  HighBound := 0;
  Count := 0;
  Sum := 0;
  for K := Integer(OpaqueBound(Int64(LowBound))) to
      Integer(OpaqueBound(Int64(HighBound))) do
  begin
    Inc(Count);
    Inc(Sum, K);
  end;
  Check((Count = 1) and (Sum = 0),
    'ascending-' + IntToStr(Count) + '-' + IntToStr(Sum));
end;
procedure CheckDescending;
var K, LowBound, HighBound, Count, Sum: Integer;
begin
  LowBound := 0;
  HighBound := 0;
  Count := 0;
  Sum := 0;
  for K := Integer(OpaqueBound(Int64(LowBound))) downto
      Integer(OpaqueBound(Int64(HighBound))) do
  begin
    Inc(Count);
    Inc(Sum, K);
  end;
  Check((Count = 1) and (Sum = 0),
    'descending-' + IntToStr(Count) + '-' + IntToStr(Sum));
end;
""", r"""
  CheckAscending;
  CheckDescending;
""")

runtime_case("MB-05", r"""
var
  LeftValue: UInt64;
  RightValue: UInt64;
""", r"""
  LeftValue := 0;
  RightValue := 0;
  Check((LeftValue = 0) and (RightValue = 0), 'uint64-comparison-and');
""")


def main() -> None:
    write(OUT / "manifest.json", json.dumps({"schema": 1, "cases": CASES}, indent=2) + "\n")
    if STALE:
        raise SystemExit("generated files are stale: " + ", ".join(STALE))
    print(json.dumps({"case_count": len(CASES)}, sort_keys=True))


if __name__ == "__main__":
    main()
