{ %OPT=-O3 }
program tinlineminmaxsnapshot1;

{$mode delphi}{$H+}{$inline on}

uses SysUtils, Math, uminmaxsnapshot;

type
  TPrices = record
    A, B: Double;
  end;
  TGuard = record
    Value: Integer;
    class operator Initialize(var R: TGuard);
    class operator Assign(var D: TGuard; const [ref] S: TGuard);
  end;

var
  Prices: TPrices;
  Calls: Integer;

class operator TGuard.Initialize(var R: TGuard);
begin
  R.Value := 0;
  Prices.A := -30;
end;

class operator TGuard.Assign(var D: TGuard; const [ref] S: TGuard);
begin
  D.Value := S.Value;
  Prices.A := -40;
end;

function PlainMin(const A, B: Double): Double; noinline;
begin
  Result := DirectMin(A, B);
end;

function InlineMin(const A, B: Double): Double; inline;
begin
  Result := DirectMin(A, B);
end;

function PlainMax(const A, B: Double): Double; noinline;
begin
  Result := DirectMax(A, B);
end;

function InlineMax(const A, B: Double): Double; inline;
begin
  Result := DirectMax(A, B);
end;

function InlineExtra(A, B: Double; Guard: TGuard): Double; inline;
begin
  Result := DirectMin(A, B);
end;

function PlainReverse(A, B: Double): Double; noinline;
begin
  Result := DirectMin(B, A);
end;

function InlineReverse(A, B: Double): Double; inline;
begin
  Result := DirectMin(B, A);
end;

function InlineDuplicate(A, B: Double): Double; inline;
begin
  Result := DirectMin(A, A);
end;

function ChangePrice: Double; noinline;
begin
  Inc(Calls);
  Prices.A := -30;
  Prices.B := 40;
  Result := 5;
end;

function PlainBody(const A: Double): Double; noinline;
begin
  Result := Min(A, ChangePrice);
end;

function InlineBody(const A: Double): Double; inline;
begin
  Result := Min(A, ChangePrice);
end;

function PlainLifecycle(const A: Double): Double; noinline;
var
  Guard: TGuard;
begin
  Result := Min(A, Guard.Value);
end;

function InlineLifecycle(const A: Double): Double; inline;
var
  Guard: TGuard;
begin
  Result := Min(A, Guard.Value);
end;

procedure Check(const Expected, Actual: Double);
var
  E, A: UInt64;
begin
  Move(Expected, E, SizeOf(E));
  Move(Actual, A, SizeOf(A));
  If E <> A then
    begin
      Writeln('FAIL ', IntToHex(E, 16), ' ', IntToHex(A, 16));
      Halt(1);
    end;
end;

procedure Reset;
begin
  Prices.A := 10;
  Prices.B := 20;
  Calls := 0;
end;

function ConditionalValue(Take: Boolean; const Value: Integer): Integer; inline;
begin
  If Take then Result := Value else Result := 7;
end;

const
  Values: array[0..7] of UInt64 = (
    $0000000000000000, $8000000000000000,
    $3FF0000000000000, $BFF0000000000000,
    $7FF0000000000000, $FFF0000000000000,
    $7FF8000000000001, $FFF8000000001234);

var
  I, J, SavedCalls: Integer;
  Expected, Actual: Double;
  P: PInteger;
  PD: PDouble;
  Guard: TGuard;
  Caught, Take: Boolean;
begin
  for I := Low(Values) to High(Values) do
    for J := Low(Values) to High(Values) do
      begin
        Move(Values[I], Prices.A, SizeOf(Double));
        Move(Values[J], Prices.B, SizeOf(Double));
        Check(PlainMin(Prices.A, Prices.B), InlineMin(Prices.A, Prices.B));
        Check(PlainMax(Prices.A, Prices.B), InlineMax(Prices.A, Prices.B));
        Check(PlainReverse(Prices.A, Prices.B), InlineReverse(Prices.A, Prices.B));
      end;

  Reset;
  Expected := PlainMin(Prices.A, ChangePrice);
  SavedCalls := Calls;
  Reset;
  Actual := InlineMin(Prices.A, ChangePrice);
  Check(Expected, Actual);
  If Calls <> SavedCalls then Halt(2);

  Reset;
  Expected := PlainMax(ChangePrice, Prices.B);
  SavedCalls := Calls;
  Reset;
  Actual := InlineMax(ChangePrice, Prices.B);
  Check(Expected, Actual);
  If Calls <> SavedCalls then Halt(3);

  Reset;
  Expected := PlainBody(Prices.A);
  Reset;
  Actual := InlineBody(Prices.A);
  Check(Expected, Actual);
  If Calls <> 1 then Halt(4);
  Reset;
  Expected := PlainLifecycle(Prices.A);
  Reset;
  Actual := InlineLifecycle(Prices.A);
  Check(Expected, Actual);
  Reset;
  Actual := InlineExtra(Prices.A, Prices.B, Guard);
  { Compatibility with the original inline path, not a language rule for the
    order of ordinary calls and managed argument copies. }
  Check(10, Actual);
  Check(-40, Prices.A);
  PD := nil;
  Caught := False;
  try
    Writeln(InlineDuplicate(Prices.A, PD^));
  except
    on E: EAccessViolation do Caught := True;
  end;
  If not Caught then Halt(6);
  P := nil;
  Take := ParamCount > 0;
  Caught := False;
  try
    Writeln(ConditionalValue(Take, P^));
  except
    on E: EAccessViolation do Caught := True;
  end;
  If not Caught then Halt(5);
  Writeln('INLINE_MINMAX_SNAPSHOT_OK');
end.
