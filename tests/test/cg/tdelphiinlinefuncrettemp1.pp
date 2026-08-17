{ %OPT=-O3 }
program tdelphiinlinefuncrettemp1;

{$ifdef FPC}
  {$mode delphi}
{$endif}

uses
{$ifdef FPC}
  SysUtils;
{$else}
  System.SysUtils;
{$endif}

type
  TIntArray = array of Integer;

  TStrStore = class
  public
    FCount: NativeInt;
    FItems: array of UnicodeString;
    procedure Add(const AValue: UnicodeString);
    function GetItem(AIndex: NativeInt): UnicodeString; inline;
    function GetDoubled(AIndex: NativeInt): UnicodeString; inline;
    property Items[AIndex: NativeInt]: UnicodeString read GetItem; default;
    property Doubled[AIndex: NativeInt]: UnicodeString read GetDoubled;
  end;

  TArrStore = class
  public
    FCount: NativeInt;
    FItems: array of TIntArray;
    procedure Add(const AValue: TIntArray);
    function GetItem(AIndex: NativeInt): TIntArray; inline;
    property Items[AIndex: NativeInt]: TIntArray read GetItem; default;
  end;

procedure TStrStore.Add(const AValue: UnicodeString);
begin
  If FCount = Length(FItems) then
    SetLength(FItems, FCount * 2 + 4);
  FItems[FCount] := AValue;
  Inc(FCount);
end;

function TStrStore.GetItem(AIndex: NativeInt): UnicodeString;
begin
  { the range check is a leading statement in front of the result assignment }
  If NativeUInt(AIndex) >= NativeUInt(FCount) then
    raise ERangeError.Create('index');
  Result := FItems[AIndex];
end;

function TStrStore.GetDoubled(AIndex: NativeInt): UnicodeString;
begin
  If NativeUInt(AIndex) >= NativeUInt(FCount) then
    raise ERangeError.Create('index');
  Result := FItems[AIndex];
  { the second result assignment reads the first one: the call site must
    keep the temp-based form }
  Result := Result + Result;
end;

procedure TArrStore.Add(const AValue: TIntArray);
begin
  If FCount = Length(FItems) then
    SetLength(FItems, FCount * 2 + 4);
  FItems[FCount] := AValue;
  Inc(FCount);
end;

function TArrStore.GetItem(AIndex: NativeInt): TIntArray;
begin
  If NativeUInt(AIndex) >= NativeUInt(FCount) then
    raise ERangeError.Create('index');
  Result := FItems[AIndex];
end;

function SumLengths(Store: TStrStore; Iterations: Integer): UInt64;
var
  I: Integer;
  J: NativeInt;
begin
  { the getter result only feeds Length: after inlining no managed
    temp assignment may remain in this function }
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to Store.FCount - 1 do
      Result := Result + UInt64(Length(Store[J]));
end;

function CopyOutlivesStore(Store: TStrStore): UnicodeString;
begin
  { the assignment itself must still take a real reference }
  Result := Store[1];
end;

function DoubledAt(Store: TStrStore; AIndex: NativeInt): UnicodeString;
begin
  Result := Store.Doubled[AIndex];
end;

function SumArrayLengths(Store: TArrStore): UInt64;
var
  J: NativeInt;
begin
  Result := 0;
  for J := 0 to Store.FCount - 1 do
    Result := Result + UInt64(Length(Store[J]));
end;

function MakeArr(const AValues: array of Integer): TIntArray;
var
  I: Integer;
begin
  SetLength(Result, Length(AValues));
  for I := 0 to High(AValues) do
    Result[I] := AValues[I];
end;

var
  Store: TStrStore;
  ArrStore: TArrStore;
  Kept: UnicodeString;
  Arr: TIntArray;
  RangeSeen: Boolean;
begin
  Store := TStrStore.Create;
  Store.Add('alpha');
  Store.Add('beta');
  Store.Add('');
  Store.Add('gamma-delta');

  { 5 + 4 + 0 + 11 = 20 per pass; the empty entry keeps the nil-pointer
    Length path in the borrowed form }
  If SumLengths(Store, 1000) <> 20000 then
    Halt(1);

  If Store[0] + Store[1] <> 'alphabeta' then
    Halt(2);
  If Store[1][1] <> 'b' then
    Halt(3);
  If Store[3] <> 'gamma-delta' then
    Halt(4);
  If DoubledAt(Store, 1) <> 'betabeta' then
    Halt(5);

  RangeSeen := False;
  try
    If Length(Store[Store.FCount]) <> 0 then
      Halt(6);
  except
    on ERangeError do
      RangeSeen := True;
  end;
  If not RangeSeen then
    Halt(7);

  Kept := CopyOutlivesStore(Store);
  FreeAndNil(Store);
  If Kept <> 'beta' then
    Halt(8);

  ArrStore := TArrStore.Create;
  ArrStore.Add(MakeArr([1, 2, 3]));
  ArrStore.Add(MakeArr([4, 5]));
  If SumArrayLengths(ArrStore) <> 5 then
    Halt(9);
  If ArrStore[1][1] <> 5 then
    Halt(10);
  Arr := ArrStore[0];
  FreeAndNil(ArrStore);
  If (Length(Arr) <> 3) or (Arr[2] <> 3) then
    Halt(11);
end.
