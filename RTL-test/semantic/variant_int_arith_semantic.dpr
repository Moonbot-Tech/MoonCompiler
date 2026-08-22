program variant_int_arith_semantic;

{$ifdef FPC}
  {$mode delphi}
{$endif}

{ Semantic pin for the unchecked 32-bit variant arithmetic fast path:
  result variant types (varInteger when the value fits, varInt64 when the
  32-bit intermediate overflows), exact values at the signed boundaries,
  mixed small ordinal types, and the untouched slow paths (Int64 operands
  with their float overflow fallback, power, division).

  Known divergence from DCC64 36.0, kept pending a dedicated repair (see
  PENDING_COMPILER_CLUSTERS "Вариантная арифметика"): on overflow DCC sends
  the varInteger domain to varDouble (losing precision) while we escalate
  to exact varInt64; DCC wraps the varInt64 domain silently while we fall
  back to varDouble; DCC raises EVariantOverflowError on a narrowing
  Int64->Integer variant conversion while we truncate.  The checks below
  pin OUR contract to guard the fast path against regressions. }

uses
  {$ifdef FPC}
  mormot.core.fpcx64mm,
  {$ifdef UNIX}cthreads,cwstring,{$endif UNIX}
  {$endif}
  SysUtils, Variants;

procedure Fail(const Msg: string);
begin
  WriteLn('FAIL ', Msg);
  Halt(1);
end;

procedure CheckType(const NameText: string; const V: Variant; Expected: TVarType);
begin
  If VarType(V) <> Expected then
    Fail(Format('%s: vartype %d <> %d', [NameText, VarType(V), Expected]));
end;

var
  A, B, R: Variant;
  I64: Int64;
begin
  { plain integer arithmetic keeps varInteger }
  A := 100;
  B := 200;
  R := A + B;
  CheckType('add small', R, varInteger);
  If R <> 300 then
    Fail('add value');
  R := A * B;
  CheckType('mul small', R, varInteger);
  If R <> 20000 then
    Fail('mul value');
  R := A - B;
  CheckType('sub small', R, varInteger);
  If R <> -100 then
    Fail('sub value');

  { 32-bit overflow promotes to varInt64 with the exact value }
  A := High(LongInt);
  B := High(LongInt);
  R := A * B;
  CheckType('mul overflow', R, varInt64);
  I64 := R;
  If I64 <> Int64(High(LongInt)) * High(LongInt) then
    Fail('mul overflow value');
  R := A + 1;
  CheckType('add overflow', R, varInt64);
  If R <> Int64(High(LongInt)) + 1 then
    Fail('add overflow value');
  A := Low(LongInt);
  R := A - 1;
  CheckType('sub underflow', R, varInt64);
  If R <> Int64(Low(LongInt)) - 1 then
    Fail('sub underflow value');
  R := A * (-1);
  CheckType('neg low', R, varInt64);
  If R <> -Int64(Low(LongInt)) then
    Fail('neg low value');

  { a folded non-negative constant expression carries the unsigned Delphi
    Variant type (dvl-0015): High(LongInt)-1 arrives as varLongWord, and
    the LongWord domain runs in Int64 - DCC64 measured, both match }
  A := High(LongInt) - 1;
  CheckType('fit high carrier', A, varLongWord);
  R := A + 1;
  CheckType('fit high', R, varInt64);
  If R <> High(LongInt) then
    Fail('fit high value');

  { mixed small ordinal source types }
  A := Byte(200);
  B := SmallInt(-300);
  R := A * B;
  CheckType('byte*smallint', R, varInteger);
  If R <> -60000 then
    Fail('byte*smallint value');
  { the literal 100000 arrives as varLongWord (dvl-0015) and the unsigned
    32-bit domain runs in Int64 - DCC64 measured, both match }
  A := Word(60000);
  B := 100000;
  R := A + B;
  CheckType('word+int', R, varInt64);
  If R <> 160000 then
    Fail('word+int value');

  { chains as in real expressions }
  A := 47;
  R := A * 3 + 7;
  CheckType('mul-add chain', R, varInteger);
  If R <> 148 then
    Fail('chain value');

  { Int64 operands keep the checked slow path with float fallback }
  A := Int64($4000000000000000);
  B := 4;
  R := A * B;
  If VarType(R) <> varDouble then
    Fail('int64 overflow fallback type');
  If Abs(Double(R) - 4.0 * $4000000000000000) > 1e4 then
    Fail('int64 overflow fallback value');
  A := Int64(100);
  B := Int64(23);
  R := A + B;
  If R <> 123 then
    Fail('int64 plain add');

  { power and division stay on their own paths }
  A := 2;
  R := A ** 10;
  If R <> 1024 then
    Fail('power value');
  A := 7;
  B := 2;
  R := A / B;
  CheckType('divide', R, varDouble);
  If Abs(Double(R) - 3.5) > 1e-12 then
    Fail('divide value');
  R := A div B;
  If R <> 3 then
    Fail('intdiv value');

  { conversion fast paths: exact values for direct integer payloads,
    truncation contract for Int64->LongInt, slow paths kept for floats,
    strings and null }
  A := 123;
  I64 := A;
  If I64 <> 123 then
    Fail('toint64 varInteger');
  A := Int64($123456789A);
  I64 := A;
  If I64 <> $123456789A then
    Fail('toint64 varInt64');
  If Integer(A) <> Integer($3456789A) then
    Fail('toint truncation');
  A := Byte(200);
  If Integer(A) <> 200 then
    Fail('toint varByte');
  A := 3.75;
  I64 := A;
  If I64 <> 4 then
    Fail('toint64 rounds double');
  A := '4321';
  I64 := A;
  If I64 <> 4321 then
    Fail('toint64 string');

  WriteLn('VARIANT_INT_ARITH_OK');
end.
