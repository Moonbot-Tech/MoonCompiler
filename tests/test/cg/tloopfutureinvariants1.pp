{ %OPT=-O3 }

program tloopfutureinvariants1;

{$mode delphi}
{$modeswitch forstep}
{$R-}{$Q-}

uses
  SysUtils;

type
  TParentState = record
    Value: Integer;
    Handled: Integer;
  end;

function ZeroTripMustNotTrap(Denominator: Integer): Integer; noinline;
var
  I: Integer;
  Count: Integer;
begin
  Count := 0;
  Result := 7;
  for I := 1 to Count do
    Inc(Result, 100 div Denominator);
end;

function GrowingLength: Integer; noinline;
var
  Data: array of Integer;
  I: Integer;
begin
  SetLength(Data, 4);
  Data[0] := 1;
  Data[1] := 2;
  Data[2] := 3;
  Data[3] := 4;
  Result := 0;
  I := 0;
  while I < Length(Data) do
  begin
    Inc(Result, Data[I]);
    If I = 1 then
    begin
      SetLength(Data, 6);
      Data[4] := 5;
      Data[5] := 6;
    end;
    Inc(I);
  end;
end;

function ManagedResultChangesEachIteration: Integer; noinline;
var
  I: Integer;
  Item: string;
  Parts: array of string;

  function Fetch(Index: Integer): string; noinline;
  begin
    Result := Parts[Index];
  end;

begin
  SetLength(Parts, 4);
  Parts[0] := 'a';
  Parts[1] := 'bb';
  Parts[2] := 'ccc';
  Parts[3] := 'dddd';
  Result := 0;
  for I := 0 to High(Parts) do
  begin
    Item := Fetch(I);
    Inc(Result, Length(Item) * 10);
  end;
end;

function InlineMutationIsNotInvariant(Bias: Integer): Integer; noinline;
var
  K: Integer;
begin
  K := 1;
  Result := 0;
  while K <= 5 do
  begin
    Inc(Result, K * Bias);
    Inc(K);
  end;
end;

function StepCounterIsNotInvariant(Stride: Integer): Integer; noinline;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to 10 step 2 do
    Inc(Result, I * Stride);
end;

function NestedLoopMatchesHoistedReference: Int64; noinline;
var
  Data: array of Int64;
  Row: Integer;
  Column: Integer;
  I: Integer;
  Base: Integer;
  Direct: Int64;
  Reference: Int64;
begin
  SetLength(Data, 8 * 16);
  for I := 0 to High(Data) do
    Data[I] := (I * 7 + 3) and 63;
  Direct := 0;
  for Row := 0 to 7 do
    for Column := 0 to 15 do
      Direct := Direct + Data[Row * 16 + Column] * (Column + 1);
  Reference := 0;
  for Row := 0 to 7 do
  begin
    Base := Row * 16;
    for Column := 0 to 15 do
      Reference := Reference + Data[Base + Column] * (Column + 1);
  end;
  Result := Direct - Reference;
end;

function IndexStoreInvalidatesRepeatedAddress(NewIndex: Integer): Integer; noinline;
var
  Data: array[0..7] of Integer;
  I: Integer;
  Index: Integer;
begin
  for I := 0 to High(Data) do
    Data[I] := I * 10;
  Index := 1;
  Result := Data[Index] + Data[Index];
  Index := NewIndex;
  Result := Result + Data[Index] + Data[Index];
end;

function NestedHandlerUsesParentFrame(Seed: Integer): Integer; noinline;
var
  State: TParentState;

  procedure Run;
  begin
    try
      Inc(State.Value, 2);
      raise Exception.Create('expected');
    except
      Inc(State.Handled);
      Inc(State.Value, 3);
    end;
  end;

begin
  State.Value := Seed;
  State.Handled := 0;
  Run;
  Result := State.Value * 10 + State.Handled;
end;

var
  Raised: Boolean;
begin
  Raised := False;
  try
    If ZeroTripMustNotTrap(0) <> 7 then
      Halt(1);
  except
    Raised := True;
  end;
  If Raised then
    Halt(2);
  If GrowingLength <> 21 then
    Halt(3);
  If ManagedResultChangesEachIteration <> 100 then
    Halt(4);
  If InlineMutationIsNotInvariant(7) <> 105 then
    Halt(5);
  If StepCounterIsNotInvariant(3) <> 90 then
    Halt(6);
  If NestedLoopMatchesHoistedReference <> 0 then
    Halt(7);
  If IndexStoreInvalidatesRepeatedAddress(3) <> 80 then
    Halt(8);
  If NestedHandlerUsesParentFrame(5) <> 101 then
    Halt(9);
end.
