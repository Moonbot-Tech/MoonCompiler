program real_folds;
{ The code shape of real operations in the forms a trading program writes
  (compiler/ncon.pas, fold_ordinary_real; compiler/nflw.pas, the min/max
  rewrite):
  - constants met after inlining are computed in the format of the
    operation when operands and result are ordinary numbers: an inline
    helper with constant parameters leaves a constant, the branch on a
    constant condition is gone;
  - min/max over an array element and over a field through a pointer is
    minsd/maxsd, the comparison of the source reads both operands as the
    instruction does;
  - an exceptional constant operation stays at run time (1/0, the root of
    -1), a multiplication by zero stays a multiplication (NaN*0 is NaN), an
    inclusive comparison stays a branch (the sign of zero, NaN).
  Run at -O2 and -O3: every value against the one computed at run time.
  run_real_folds_gate.py counts the instructions and calls of each routine
  of the -O3 object against the recorded reference: more is red.  The file
  sets no range or overflow switch: the gate builds it without checks, as
  the product profile does, and again with -Cr -Co. }
{$mode delphi}
uses
  SysUtils, Math;

type
  TRange = record
    Lo, Hi: Double;
  end;
  PRange = ^TRange;

var
  Prices: array of Double;
  Failures: Integer;

function Opaque(X: Double): Double; noinline;
begin
  Result := X;
end;

procedure Check(Code: Integer; A, B: Double);
var
  BA, BB: UInt64;
begin
  Move(A, BA, 8);
  Move(B, BB, 8);
  If BA <> BB then begin
    Inc(Failures);
    WriteLn('MISMATCH ', Code, ' ', IntToHex(BA, 16), ' ', IntToHex(BB, 16));
  end;
end;

function Lerp(A, B, T: Double): Double; inline;
begin
  Result := A + (B - A) * T;
end;

function Scale(X, K: Double): Double; inline;
begin
  Result := X * (K * 0.5);
end;

function PickBig(X, Limit: Double): Double; inline;
begin
  If Limit > 100.0 then
    Result := X * 2.0
  else
    Result := X + 1.0;
end;

function Clamp01(X: Double): Double; inline;
begin
  If X < 0.0 then
    Result := 0.0
  else If X > 1.0 then
    Result := 1.0
  else
    Result := X;
end;

function Ratio(A, B: Double): Double; inline;
begin
  Result := A / B;
end;

function Root(A: Double): Double; inline;
begin
  Result := Sqrt(A);
end;

{ constants after inlining: X*2.0 without the constant product }
function ScaleFour(X: Double): Double; noinline;
begin
  Result := Scale(X, 4.0);
end;

{ the condition 50 > 100 is known: one arm, no comparison }
function PickSmall(X: Double): Double; noinline;
begin
  Result := PickBig(X, 50.0);
end;

{ every operand a constant: the value alone }
function LerpConst: Double; noinline;
begin
  Result := Lerp(1.0, 3.0, 0.5);
end;

function ClampConst: Double; noinline;
begin
  Result := Clamp01(0.75);
end;

{ exceptional: 1/0 and the root of -1 stay at run time }
function RatioByZero: Double; noinline;
begin
  Result := Ratio(1.0, 0.0);
end;

function RootOfNegative: Double; noinline;
begin
  Result := Root(-1.0);
end;

{ a multiplication by zero stays: NaN*0, Inf*0 and -1*0 are not +0 }
function TimesZero(X: Double): Double; noinline;
begin
  Result := X * 0.0;
end;

{ min/max over an element: the best price of an array }
function MinPrice: Double; noinline;
var
  I: Integer;
  M: Double;
begin
  M := Prices[0];
  for I := 1 to High(Prices) do
    If Prices[I] < M then
      M := Prices[I];
  Result := M;
end;

{ min/max over a field through a pointer: the range of a candle }
procedure Widen(P: PRange; V: Double); noinline;
begin
  If V < P^.Lo then
    P^.Lo := V;
  If V > P^.Hi then
    P^.Hi := V;
end;

{ an inclusive comparison keeps its branch: -0 <= +0 selects -0, a NaN takes
  the else arm; one minsd keeps neither }
function MinInclusive(P: PRange; V: Double): Double; noinline;
begin
  If V <= P^.Lo then
    Result := V
  else
    Result := P^.Lo;
end;

var
  I: Integer;
  R: TRange;
  Mask: TFPUExceptionMask;
  Raised: Boolean;
begin
  Failures := 0;
  SetLength(Prices, 64);
  for I := 0 to High(Prices) do
    Prices[I] := 100.0 + ((I * 37) mod 17) * 0.25;
  Prices[40] := 97.5;
  Check(1, ScaleFour(3.0), Opaque(3.0) * (Opaque(4.0) * 0.5));
  Check(2, PickSmall(3.0), 4.0);
  Check(3, LerpConst, 2.0);
  Check(4, ClampConst, 0.75);
  Check(5, TimesZero(-1.0), Opaque(-1.0) * Opaque(0.0));
  Check(6, TimesZero(NaN), Opaque(NaN) * Opaque(0.0));
  Check(7, MinPrice, 97.5);
  R.Lo := 1.0;
  R.Hi := 2.0;
  Widen(@R, 0.5);
  Widen(@R, 3.0);
  Widen(@R, NaN);
  Check(8, R.Lo, 0.5);
  Check(9, R.Hi, 3.0);
  R.Lo := 0.0;
  Check(10, MinInclusive(@R, -0.0), -0.0);
  Check(11, MinInclusive(@R, NaN), 0.0);
  Check(12, RatioByZero, Infinity);
  If not IsNan(RootOfNegative) then begin
    Inc(Failures);
    WriteLn('MISMATCH 13 the root of -1 is not a NaN');
  end;
  { any math exception: on Win64 the class follows the status flags left in
    MXCSR by the operations above, which ClearExceptions does not clear }
  Mask := GetExceptionMask;
  SetExceptionMask([exDenormalized, exUnderflow, exPrecision]);
  Raised := False;
  try
    Check(14, RatioByZero, 0.0);
  except
    on EMathError do
      Raised := True;
  end;
  ClearExceptions(False);
  SetExceptionMask(Mask);
  If not Raised then begin
    Inc(Failures);
    WriteLn('MISMATCH 14 1/0 after inlining did not raise');
  end;
  If Failures <> 0 then
    Halt(1);
  WriteLn('REAL_FOLDS_PASS');
end.
