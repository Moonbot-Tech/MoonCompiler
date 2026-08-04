{ %OPT=-O2 }
program taddreal4;

{ Reference bits measured on Delphi 12.2 Win64.  One rule explains the
  cases below: an intrinsic always computes in the target computation type
  (that is its signature), while operators widen to it only while excess
  precision is on.  On this target that type is double - never the 80-bit
  x87 type, which Delphi has no equivalent of.

  This file compiles with both Delphi 12.2 Win64 and FPC and must pass on
  both.  Local switches are set per routine on purpose: FPC does not
  restore them at the end of a routine, so every block states its own. }

{$ifdef FPC}
  {$mode delphi}
{$endif}

var
  Failed: Integer = 0;

procedure Check(Ok: Boolean; const Name: string);
begin
  if not Ok then
    begin
      WriteLn('FAIL ', Name);
      Inc(Failed);
    end;
end;

{ the only way to observe the static type of an expression from inside
  the program: overload resolution }
function Kind(const X: Single): Integer; overload;
begin
  Result := 1;
end;

function Kind(const X: Double): Integer; overload;
begin
  Result := 2;
end;

function Bits(const D: Double): UInt64;
begin
  Move(D, Result, SizeOf(Result));
end;

{ excess precision is the default of mode Delphi }
procedure ExcessOn;
{$excessprecision on}
var
  S1, S2: Single;
  X, Y, D: Double;
  Value: Int64;
begin
  { operators widen a single pair: 2^24+1 is not representable in single,
    so a single-wide sum would collapse back and leave 0 }
  S1 := 16777216.0;
  S2 := 1.0;
  D := (S1 + S2) - S1;
  Check(D = 1.0, 'pair-widens-under-excess');

  { the unary minus follows the same rule.  Checked by type, not by value:
    a value check would be satisfied by the pair rule above, which has
    already widened the operand }
  Check(Kind(-S1) = 2, 'unaryminus-type-widens');

  { double pairs must compute in double, not in the 80-bit type: the exact
    product 1-2^-58 rounds to exactly 1.0 in a 53-bit mantissa and stays
    distinct in a 64-bit one }
  X := 1.0;
  for Value := 1 to 29 do
    X := X * 0.5;
  X := 1.0 + X;
  Y := 2.0 - X;
  Check(X * Y - 1.0 = 0.0, 'double-pair-not-x87');
  Check((-X) * Y + 1.0 = 0.0, 'double-unaryminus-not-x87');
  Check(Abs(X) * Y - 1.0 = 0.0, 'double-abs-not-x87');

  { Sqr must not compute wider than the pair it stands for: with
    X = 1+2^-29 the exact square carries a 2^-58 tail that a 53-bit
    mantissa drops and a 64-bit one keeps }
  Check(Sqr(X) - X * X = 0.0, 'double-sqr-matches-pair');

  { an integer mixed with a single-typed literal computes in double
    (in single this overflows) }
  Value := 1000;
  D := Value * 3e38;
  Check((D > 2.9e41) and (D < 3.1e41), 'int64-single-literal-widens');

  { an untyped literal carries at least double precision.  The all-double
    reference is built through variables: a hard cast between float types
    of different size is not portable }
  S1 := 1.1;
  X := S1;
  Y := 0.3;
  Check(S1 * 0.3 = X * Y, 'literal-double-width');

  { the reference expression of the original report }
  Value := 1356062706000;
  D := (Value / 86400000.0) + 25569.0;
  Check(Bits(D) = UInt64($40E426057258BF26), 'int64-div-literal-bits');

  { intrinsic bits under excess precision }
  S1 := 2.0;
  D := Sqrt(S1);
  Check(Bits(D) = UInt64($3FF6A09E667F3BCD), 'sqrt-bits-excess-on');
  S1 := 16777215.0;
  D := Sqr(S1);
  Check(Bits(D) = UInt64($42EFFFFFC0000020), 'sqr-bits-excess-on');
end;

procedure ExcessOff;
{$excessprecision off}
var
  S1, S2: Single;
  D: Double;
begin
  { without excess precision operators keep the operand type }
  S1 := 16777216.0;
  S2 := 1.0;
  D := (S1 + S2) - S1;
  Check(D = 0.0, 'pair-stays-single-without-excess');

  { intrinsics do not depend on the switch: their declared type wins.
    Sqr is named explicitly - it is the case an earlier review disputed }
  D := Abs(S1) + S2 - S1;
  Check(D = 1.0, 'abs-computes-in-double-always');

  D := Sqrt(S1 * S1) + S2 - S1;
  Check(D = 1.0, 'sqrt-computes-in-double-always');

  { without excess precision the unary minus keeps the operand type }
  Check(Kind(-S1) = 1, 'unaryminus-type-stays');

  S1 := 16777215.0;
  D := Sqr(S1);
  Check(Bits(D) = UInt64($42EFFFFFC0000020), 'sqr-bits-excess-off');

  S1 := 2.0;
  D := Sqrt(S1);
  Check(Bits(D) = UInt64($3FF6A09E667F3BCD), 'sqrt-bits-excess-off');
end;

begin
  ExcessOn;
  ExcessOff;
  if Failed <> 0 then
    Halt(1);
end.
