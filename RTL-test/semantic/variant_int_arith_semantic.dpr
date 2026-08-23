program variant_int_arith_semantic;

{$APPTYPE CONSOLE}

{$ifdef FPC}
  {$mode delphi}
{$endif}

{ Semantic pin for Delphi-compatible integer Variant arithmetic, all
  expectations DCC64-measured:

  - the 32-bit signed domain keeps varInteger while the value fits and
    goes to varDouble on overflow, losing precision by contract
    (MaxInt*MaxInt = 4.61...E18);
  - the Int64 domain wraps silently on overflow, it never falls back to
    float ($4000000000000000 * 4 = 0);
  - a QWord operand keeps the arithmetic in the unsigned 64-bit domain
    (varUInt64, silent wrap: High(QWord)+2 = 1), and mixing a negative
    operand into it raises EVariantOverflowError;
  - unsigned 32-bit operands (varLongWord) run in the Int64 domain and
    stay varInt64 even when the value would fit varInteger;
  - Integer conversion raises EVariantOverflowError for every numeric carrier
    outside its range and EVariantTypeCastError for malformed strings;
  - UInt64 rejects negative carriers with EVariantOverflowError;
  - Byte/Word/Cardinal preserve Delphi truncation for values which first fit
    the Integer conversion domain;
  - QWord->Int64 preserves Delphi's bit-pattern reinterpretation;
  - div/mod stay on the Int64 path.

  The ** power operator is an FPC extension without a Delphi contract
  and keeps its checked path with the float fallback. }

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
  U64: UInt64;
  RefI64: Int64;
  Raised: Boolean;
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

  { 32-bit signed domain overflow goes to varDouble }
  A := Integer(2147483647);
  B := Integer(2147483647);
  R := A * B;
  CheckType('mul overflow', R, varDouble);
  If Abs(Double(R) - 4.6116860141324206e18) > 1e5 then
    Fail('mul overflow value');
  R := A + A;
  CheckType('add overflow', R, varDouble);
  If Double(R) <> 4294967294.0 then
    Fail('add overflow value');
  A := Integer(-2147483648);
  R := A - 1;
  CheckType('sub underflow', R, varDouble);
  If Double(R) <> -2147483649.0 then
    Fail('sub underflow value');

  { unsigned 32-bit operands run in the Int64 domain without shrinking }
  A := High(LongInt) - 1;   { a folded non-negative expression: varLongWord }
  R := A + 1;
  CheckType('fit high', R, varInt64);
  If R <> High(LongInt) then
    Fail('fit high value');
  A := Word(60000);
  B := 100000;              { literal carrier: varLongWord }
  R := A + B;
  CheckType('word+longword', R, varInt64);
  If R <> 160000 then
    Fail('word+longword value');
  A := Cardinal(4000000000);
  B := Cardinal(1000000000);
  R := A + B;
  CheckType('longword add', R, varInt64);
  If R <> 5000000000 then
    Fail('longword add value');
  { and wraps like the Int64 domain }
  A := Cardinal(4000000000);
  B := Cardinal(4000000000);
  R := A * B;
  CheckType('longword mul wrap', R, varInt64);
  If R <> Int64(-2446744073709551616) then
    Fail('longword mul wrap value');

  { mixed small ordinal source types stay in the signed 32-bit domain }
  A := Byte(200);
  B := SmallInt(-300);
  R := A * B;
  CheckType('byte*smallint', R, varInteger);
  If R <> -60000 then
    Fail('byte*smallint value');

  { chains as in real expressions }
  A := 47;
  R := A * 3 + 7;
  CheckType('mul-add chain', R, varInteger);
  If R <> 148 then
    Fail('chain value');

  { the Int64 domain wraps silently }
  A := Int64($4000000000000000);
  B := 4;
  R := A * B;
  CheckType('int64 wrap', R, varInt64);
  If R <> 0 then
    Fail('int64 wrap value');
  A := Int64(100);
  B := Int64(23);
  R := A + B;
  If R <> 123 then
    Fail('int64 plain add');

  { the unsigned 64-bit domain stays unsigned and wraps }
  A := UInt64($8000000000000000);
  B := 2;
  R := A + B;
  CheckType('uint64 add', R, varUInt64);
  If R <> UInt64($8000000000000002) then
    Fail('uint64 add value');
  A := UInt64($FFFFFFFFFFFFFFFF);
  B := UInt64(2);
  R := A + B;
  CheckType('uint64 wrap', R, varUInt64);
  If R <> 1 then
    Fail('uint64 wrap value');

  { mixing a negative operand into the unsigned 64-bit domain raises }
  A := UInt64($8000000000000000);
  B := Integer(-1);
  Raised := False;
  try
    R := A + B;
  except
    on EVariantOverflowError do
      Raised := True;
  end;
  If not Raised then
    Fail('uint64 + negative must raise');

  { power stays on its own checked path }
  {$ifdef FPC}
  A := 2;
  R := A ** 10;
  If R <> 1024 then
    Fail('power value');
  {$endif FPC}

  { division domains }
  A := 7;
  B := 2;
  R := A / B;
  CheckType('divide', R, varDouble);
  If Abs(Double(R) - 3.5) > 1e-12 then
    Fail('divide value');
  R := A div B;
  If R <> 3 then
    Fail('intdiv value');
  A := Int64(10);
  B := Int64(4);
  R := A div B;
  CheckType('int64 intdiv', R, varInt64);
  If R <> 2 then
    Fail('int64 intdiv value');
  R := A mod B;
  If R <> 2 then
    Fail('int64 mod value');

  { conversions: exact payloads, Delphi narrowing contract }
  A := 123;
  I64 := A;
  If I64 <> 123 then
    Fail('toint64 small');
  A := Int64($123456789A);
  I64 := A;
  If I64 <> $123456789A then
    Fail('toint64 varInt64');
  Raised := False;
  try
    If Integer(A) = 0 then ;
  except
    on EVariantOverflowError do
      Raised := True;
  end;
  If not Raised then
    Fail('narrowing Int64->Integer must raise');
  A := Cardinal(High(Cardinal));
  Raised := False;
  try
    If Integer(A) = 0 then ;
  except
    on EVariantOverflowError do
      Raised := True;
  end;
  If not Raised then
    Fail('narrowing Cardinal->Integer must raise');
  A := 2147483647.5;
  Raised := False;
  try
    If Integer(A) = 0 then ;
  except
    on EVariantOverflowError do
      Raised := True;
  end;
  If not Raised then
    Fail('rounded Double->Integer overflow must raise');
  A := '2147483648';
  Raised := False;
  try
    If Integer(A) = 0 then ;
  except
    on EVariantOverflowError do
      Raised := True;
  end;
  If not Raised then
    Fail('numeric string->Integer overflow must raise');
  A := 'not-a-number';
  Raised := False;
  try
    If Integer(A) = 0 then ;
  except
    on EVariantTypeCastError do
      Raised := True;
  end;
  If not Raised then
    Fail('malformed string->Integer must be a type cast error');

  A := UInt64($8000000000000000);
  I64 := A;
  If I64 <> Low(Int64) then
    Fail('QWord->Int64 keeps the Delphi bit pattern');
  A := Int64(-1);
  Raised := False;
  try
    U64 := A;
  except
    on EVariantOverflowError do
      Raised := True;
  end;
  If not Raised then
    Fail('negative Int64->UInt64 must raise');
  A := '-1';
  Raised := False;
  try
    U64 := A;
  except
    on EVariantOverflowError do
      Raised := True;
  end;
  If not Raised then
    Fail('negative numeric string->UInt64 must raise');
  A := '18446744073709551616';
  Raised := False;
  try
    U64 := A;
  except
    on EVariantOverflowError do
      Raised := True;
  end;
  If not Raised then
    Fail('oversized numeric string->UInt64 must raise');
  A := '18446744073709551615';
  U64 := A;
  If U64 <> High(UInt64) then
    Fail('maximum numeric string->UInt64');

  VarClear(A);
  RefI64 := -1;
  TVarData(A).VType := varInt64 or varByRef;
  TVarData(A).VPointer := @RefI64;
  Raised := False;
  try
    U64 := A;
  except
    on EVariantOverflowError do
      Raised := True;
  end;
  TVarData(A).VType := varEmpty;
  If not Raised then
    Fail('negative byref Int64->UInt64 must raise');

  A := Integer(-5);
  If Cardinal(A) <> 4294967291 then
    Fail('narrowing to Cardinal truncates');
  A := Int64(70000);
  If Word(A) <> 4464 then
    Fail('narrowing to Word truncates');
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
