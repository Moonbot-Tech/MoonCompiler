program currency_exact_semantic;

{ %TARGET=win64 }

{ Deep-layer audit (journal 6, middle layer): money exactness.

  Literals: a Currency literal must carry its exact decimal value - the
  compiler parses it digit-by-digit into value_currency (pexpr), and the
  conversion uses that value instead of the value_real*10000.0 double
  detour that corrupted the final digits of large literals.  DCC64's
  compile-time literals are exact too: one shared expectation.

  Division: integer-backed Currency division goes through the 128-bit
  re-scaled numerator (fpc_div_currency) with the fpc_mul_currency
  rounding rule - nearest, ties to even.  The old float detour lost
  final digits of large quotients.  DCC64 divides through the x87 unit
  and its last digits carry FPU noise; by the fpc_mul_currency precedent
  the fork keeps the mathematically exact quotient, so the diverging
  axes pin each side's measured value.

  This pin is Win64-only because the repaired representation is the
  integer-backed Currency selected by FPC_CURRENCY_IS_INT64.  Native Linux
  x86-64 keeps FPC's distinct float-backed s64currency ABI and is outside this
  repair; treating its bytes as Int64 would test a representation that target
  does not use.

  Runtime Val: ours parses Currency text exactly; DCC64's runtime Val
  detours through a float (and silently wraps at the positive edge) -
  a recorded boundary we do not reproduce, checked on our side only. }

{$APPTYPE CONSOLE}

uses
  {$ifdef FPC}
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  {$endif UNIX}
  {$endif FPC}
  SysUtils;

var
  FailCount: Integer;

procedure CheckScaled(const Name: string; const C: Currency; const Expected: Int64);
begin
  If PInt64(@C)^ <> Expected then
  begin
    WriteLn('FAIL ', Name, ': ', PInt64(@C)^, ' expected ', Expected);
    Inc(FailCount);
  end;
end;

procedure Literals;
var
  A: Currency;
begin
  A := 92233720368547.7580;
  CheckScaled('lit-big', A, 922337203685477580);
  A := -92233720368547.7580;
  CheckScaled('lit-neg', A, -922337203685477580);
  A := 922337203685477.5807;
  CheckScaled('lit-max', A, 9223372036854775807);
  A := -922337203685477.5808;
  CheckScaled('lit-min', A, -9223372036854775808);
  A := 0.0001;
  CheckScaled('lit-tiny', A, 1);
  A := 123456789012.3456;
  CheckScaled('lit-mid', A, 1234567890123456);
end;

{ keeps the operands out of each compiler's constant folder: DCC64's
  compile-time fold divides DIFFERENTLY from its own runtime (a double
  detour with truncation vs the x87 unit with round-to-even) - the
  runtime paths are what this axis pins }
function Opaque(const C: Currency): Currency;
begin
  Result := C;
end;

procedure Division;
var
  A, B: Currency;
begin
  A := Opaque(123456789012.3456);
  B := Opaque(3);
  CheckScaled('div-mid', A / B, 411522630041152);

  A := Opaque(400000000000000);
  B := Opaque(7);
  { exact: 4e18*10000/70000 = 571428571428571428.571 -> rounds to 429.
    DCC64 is not even self-consistent here: the same division yields
    ...456 through x87 on globals, ...392 through the double path on
    locals, and truncated folds on constants - the last digits of real
    money depend on register allocation.  The fork keeps the exact
    quotient (the fpc_mul_currency precedent); the DCC arm pins what
    THIS program's shape measures }
  {$ifdef FPC}
  CheckScaled('div-sevenths', A / B, 571428571428571429);
  {$else}
  CheckScaled('div-sevenths', A / B, 571428571428571392);
  {$endif}

  A := Opaque(92233720368547.7580);
  B := Opaque(10);
  { exact re-scale: ...77580 / 10 = ...7758 exactly }
  {$ifdef FPC}
  CheckScaled('div-ten', A / B, 92233720368547758);
  {$else}
  CheckScaled('div-ten', A / B, 92233720368547760);
  {$endif}

  A := Opaque(0.0003);
  B := Opaque(2);
  { 1.5 rounds to the even neighbour; DCC64's local-double path
    truncates the tie instead }
  {$ifdef FPC}
  CheckScaled('div-tie-even', A / B, 2);
  {$else}
  CheckScaled('div-tie-even', A / B, 1);
  {$endif}
  A := Opaque(0.0001);
  B := Opaque(2);
  { 0.5 rounds to zero, the even neighbour }
  CheckScaled('div-tie-zero', A / B, 0);
  A := Opaque(0.0005);
  B := Opaque(2);
  { 2.5 rounds to 2 }
  CheckScaled('div-tie-two', A / B, 2);

  A := Opaque(99999999999999.9999);
  B := Opaque(9999.9999);
  CheckScaled('div-nines', A / B, 100000001000000);

  A := Opaque(1);
  B := Opaque(3);
  CheckScaled('div-third', A / B, 3333);
  A := Opaque(-1);
  CheckScaled('div-third-neg', A / B, -3333);

  { mixed operands: an integer literal divisor joins the currency domain
    before the exact division }
  A := Opaque(92233720368547.7580);
  {$ifdef FPC}
  CheckScaled('div-int-literal', A / 10, 92233720368547758);
  {$else}
  CheckScaled('div-int-literal', A / 10, 92233720368547760);
  {$endif}
end;

procedure DivisionOverflow;
{$ifdef FPC}
var
  A, B: Currency;
  LCaught: Boolean;
{$endif}
begin
  {$ifdef FPC}
  { a quotient beyond the Currency range raises an honest overflow (the
    fpc_mul_currency contract); DCC64 silently wraps the sign here even
    though its own multiplication raises - a recorded boundary }
  A := Opaque(123456789012.3456);
  B := Opaque(0.0001);
  LCaught := False;
  try
    CheckScaled('div-overflow-value', A / B, 0);
  except
    on EIntOverflow do
      LCaught := True;
  end;
  If not LCaught then
  begin
    WriteLn('FAIL div-overflow: no exception');
    Inc(FailCount);
  end;
  {$endif}
end;

procedure RuntimeVal;
{$ifdef FPC}
var
  C: Currency;
  Code: Integer;
{$endif}
begin
  {$ifdef FPC}
  Val('92233720368547.7580', C, Code);
  If Code <> 0 then
  begin
    WriteLn('FAIL val-code: ', Code);
    Inc(FailCount);
  end;
  CheckScaled('val-big', C, 922337203685477580);
  Val('922337203685477.5807', C, Code);
  CheckScaled('val-max', C, 9223372036854775807);
  {$endif}
end;

begin
  FailCount := 0;
  Literals;
  Division;
  DivisionOverflow;
  RuntimeVal;
  If FailCount = 0 then
    WriteLn('CURRENCY_EXACT_OK')
  else
  begin
    WriteLn('CURRENCY_EXACT_FAIL count=', FailCount);
    Halt(1);
  end;
end.
