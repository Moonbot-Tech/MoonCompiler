program forin_class_lifetime;
{$ifdef FPC}{$mode delphi}{$endif}
{$apptype console}
uses SysUtils, Generics.Collections;

type
  EProbe = class(Exception);
  TWalk = class
  private
    FIndex, FLimit, FID, FThrow: Integer;
  public
    constructor Create(ALimit, AThrow: Integer);
    destructor Destroy; override;
    function MoveNext: Boolean; virtual;
    function GetCurrent: Integer; virtual;
    property Current: Integer read GetCurrent;
  end;
  TRange = record
    Limit, ThrowAt: Integer;
    function GetEnumerator: TWalk; inline;
  end;
  TInlineWalk = class
    Index, Limit: Integer;
    constructor Create(ALimit: Integer);
    destructor Destroy; override;
    function MoveNext: Boolean; inline;
    property Current: Integer read Index;
  end;
  TInlineRange = record
    Limit: Integer;
    function GetEnumerator: TInlineWalk; inline;
  end;
  TValueWalk = record
    Index, Limit: Integer;
    function MoveNext: Boolean; inline;
    property Current: Integer read Index;
  end;
  TValueRange = record
    Limit: Integer;
    function GetEnumerator: TValueWalk; inline;
  end;

var
  Created, Freed, FactoryCalls, LastIndex, NextID: Integer;
  DestroyOrder: string;
  Observed: UInt64;
  Inputs: array[0..13] of UInt64;

procedure Check(OK: Boolean; const What: string);
begin
  If not OK then
    raise Exception.Create(What);
end;

constructor TWalk.Create(ALimit, AThrow: Integer);
begin
  inherited Create;
  Inc(Created);
  Inc(NextID);
  FID := NextID;
  FIndex := 0;
  FLimit := ALimit;
  FThrow := AThrow;
end;

destructor TWalk.Destroy;
begin
  Inc(Freed);
  LastIndex := FIndex;
  DestroyOrder := DestroyOrder + IntToStr(FID);
  inherited Destroy;
end;

function TWalk.MoveNext: Boolean;
begin
  Inc(FIndex);
  If (FThrow = 5) and (FIndex = 3) then
    raise EProbe.Create('move');
  Result := FIndex <= FLimit;
end;

function TWalk.GetCurrent: Integer;
begin
  If (FThrow = 6) and (FIndex = 3) then
    raise EProbe.Create('current');
  Result := FIndex;
end;

function TRange.GetEnumerator: TWalk;
begin
  Inc(FactoryCalls);
  If ThrowAt = 7 then
    raise EProbe.Create('factory');
  If Limit < 0 then
    Result := nil
  else
    Result := TWalk.Create(Limit, ThrowAt);
end;

constructor TInlineWalk.Create(ALimit: Integer);
begin
  inherited Create;
  Inc(Created);
  Index := 0;
  Limit := ALimit;
end;

destructor TInlineWalk.Destroy;
begin
  Inc(Freed);
  LastIndex := Index;
  inherited Destroy;
end;

function TInlineWalk.MoveNext: Boolean;
begin
  Inc(Index);
  Result := Index <= Limit;
end;

function TInlineRange.GetEnumerator: TInlineWalk;
begin
  Inc(FactoryCalls);
  Result := TInlineWalk.Create(Limit);
end;

function TValueWalk.MoveNext: Boolean;
begin
  Inc(Index);
  Result := Index <= Limit;
end;

function TValueRange.GetEnumerator: TValueWalk;
begin
  Inc(FactoryCalls);
  Result.Index := 0;
  Result.Limit := Limit;
end;

{$inline off}
function Clobber(A, B, C, D, E, F, G, H: UInt64): UInt64;
begin
  Result := (A + B * 3 + C * 5 + D * 7 + E * 11 + F * 13 + G * 17 + H * 19) xor $12345;
  Observed := Result;
end;

procedure ThrowInner;
begin
  Clobber(1, 2, 3, 4, 5, 6, 7, 8);
  raise EProbe.Create('inner');
end;
{$inline on}

function WalkMode(Mode, Limit: Integer): Integer;
var
  R: TRange;
  V: Integer;
begin
  R.Limit := Limit;
  R.ThrowAt := Mode;
  Result := 0;
  for V in R do
  begin
    If (Mode = 1) and (V = 3) then
      Break;
    If (Mode = 2) and Odd(V) then
      Continue;
    If (Mode = 3) and (V = 3) then
      Exit;
    If (Mode = 4) and (V = 3) then
      raise EProbe.Create('body');
    If Mode = 8 then
      try
        ThrowInner;
      except
        on E: EProbe do
          Inc(Result, 10);
      end;
    Inc(Result, V);
  end;
end;

procedure CheckModes;
const
  Expected: array[0..3] of Integer = (15, 3, 6, 3);
  ExpectedIndex: array[0..3] of Integer = (6, 3, 6, 3);
var
  Mode, C, F, Calls: Integer;
  Caught: Boolean;
begin
  for Mode := 0 to 8 do
  begin
    C := Created;
    F := Freed;
    Calls := FactoryCalls;
    Caught := False;
    try
      If Mode < 4 then
        Check(WalkMode(Mode, 5) = Expected[Mode], 'mode result')
      else If Mode = 8 then
        Check(WalkMode(Mode, 5) = 65, 'resumed virtual loop')
      else
        WalkMode(Mode, 5);
    except
      on E: EProbe do
        Caught := True;
    end;
    Check(Caught = ((Mode >= 4) and (Mode <= 7)), 'exception propagation');
    Check(FactoryCalls = Calls + 1, 'factory evaluated once');
    Check(Created - C = Ord(Mode <> 7), 'created count');
    Check(Freed - F = Ord(Mode <> 7), 'cleanup count');
    If Mode < 4 then
      Check(LastIndex = ExpectedIndex[Mode], 'cleanup identity')
    else If Mode <= 6 then
      Check(LastIndex = 3, 'exception cleanup identity');
  end;
  Check(WalkMode(0, 0) = 0, 'empty');
  {$ifdef FPC}
  C := Created;
  F := Freed;
  Check(WalkMode(0, -1) = 0, 'nil enumerator');
  Check((Created = C) and (Freed = F), 'nil cleanup');
  {$endif}
end;

procedure CheckNested;
var
  A, B: TRange;
  I, J, Sum: Integer;
begin
  A.Limit := 2;
  A.ThrowAt := 0;
  B := A;
  NextID := 0;
  DestroyOrder := '';
  Sum := 0;
  try
    for I in A do
      for J in B do
      begin
        Inc(Sum, I * 10 + J);
        If J = 2 then
          raise EProbe.Create('nested');
      end;
  except
    on E: EProbe do
      Check(Sum = 23, 'nested result');
  end;
  Check(DestroyOrder = '21', 'nested cleanup order');
end;

function Pressure: UInt64;
var
  R: TInlineRange;
  V: Integer;
  A, B, C, D, E, F, G, H, I, J, K, L, M, N: UInt64;
begin
  A := Inputs[0];
  B := Inputs[1];
  C := Inputs[2];
  D := Inputs[3];
  E := Inputs[4];
  F := Inputs[5];
  G := Inputs[6];
  H := Inputs[7];
  I := Inputs[8];
  J := Inputs[9];
  K := Inputs[10];
  L := Inputs[11];
  M := Inputs[12];
  N := Inputs[13];
  R.Limit := 40;
  Result := 0;
  for V in R do
  begin
    Inc(A, V);
    Inc(B, V * 2);
    Inc(C, V * 3);
    Inc(D, V * 4);
    Inc(E, V * 5);
    Inc(F, V * 6);
    Inc(G, V * 7);
    Inc(H, V * 8);
    Inc(I, V * 9);
    Inc(J, V * 10);
    Inc(K, V * 11);
    Inc(L, V * 12);
    Inc(M, V * 13);
    Inc(N, V * 14);
    Inc(Result, Clobber(A, C, E, G, I, K, M, N));
    try
      try
        If Odd(V) then
          ThrowInner;
      finally
        Inc(Result, Clobber(B, D, F, H, J, L, M, N));
      end;
    except
      on Err: EProbe do
        Inc(Result, V);
    end;
  end;
  Inc(Result, A + B + C + D + E + F + G + H + I + J + K + L + M + N);
end;

procedure CheckPressure;
var
  A: array[0..13] of UInt64;
  V, I: Integer;
  Expected: UInt64;
begin
  for I := 0 to 13 do
  begin
    Inputs[I] := 101 + I * 7;
    A[I] := Inputs[I];
  end;
  Expected := 0;
  for V := 1 to 40 do
  begin
    for I := 0 to 13 do
      Inc(A[I], V * (I + 1));
    Inc(Expected, Clobber(A[0], A[2], A[4], A[6], A[8], A[10], A[12], A[13]));
    Inc(Expected, Clobber(A[1], A[3], A[5], A[7], A[9], A[11], A[12], A[13]));
    If Odd(V) then
      Inc(Expected, V);
  end;
  for I := 0 to 13 do
    Inc(Expected, A[I]);
  Check(Pressure = Expected, 'inline field, pressure, calls, nested handlers');
  Check(LastIndex = 41, 'pressure cleanup identity');
end;

procedure CheckValues;
var
  R: TValueRange;
  V, Sum: Integer;
  L: TList<string>;
  S, Text: string;
begin
  R.Limit := 9;
  Sum := 0;
  for V in R do
    Inc(Sum, V);
  Check(Sum = 45, 'record mutable Self');
  L := TList<string>.Create;
  try
    L.Add('one');
    L.Add('two');
    L.Add('three');
    Text := '';
    for S in L do
      Text := Text + S;
    Check(Text = 'onetwothree', 'managed current');
  finally
    L.Free;
  end;
end;

begin
  CheckModes;
  CheckNested;
  CheckPressure;
  CheckValues;
  Check(Created = Freed, 'all enumerators destroyed');
  Writeln('FORIN_CLASS_LIFETIME_OK');
end.
