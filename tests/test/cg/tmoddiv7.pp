{ %OPT=-O2 }
program tmoddiv7;

{$mode objfpc}

procedure DivModNeg3(Value: LongInt; out Quotient, Remainder: LongInt);
begin
  Quotient := Value div -3;
  Remainder := Value mod -3;
end;

procedure DivModNeg7(Value: LongInt; out Quotient, Remainder: LongInt);
begin
  Quotient := Value div -7;
  Remainder := Value mod -7;
end;

procedure DivModNeg19(Value: LongInt; out Quotient, Remainder: LongInt);
begin
  Quotient := Value div -19;
  Remainder := Value mod -19;
end;

procedure Check(Value, Divisor, Quotient, Remainder,
  ExpectedQuotient, ExpectedRemainder: LongInt; ErrorCode: Byte);
begin
  if (Quotient <> ExpectedQuotient) or
     (Remainder <> ExpectedRemainder) or
     (Int64(Quotient) * Divisor + Remainder <> Value) then
  begin
    WriteLn('FAIL value=', Value, ' divisor=', Divisor,
      ' actual=', Quotient, ',', Remainder,
      ' expected=', ExpectedQuotient, ',', ExpectedRemainder);
    Halt(ErrorCode);
  end;
end;

procedure DivMod64Neg19(Value: Int64; out Quotient, Remainder: Int64);
begin
  Quotient := Value div -19;
  Remainder := Value mod -19;
end;

procedure DivMod64Neg7(Value: Int64; out Quotient, Remainder: Int64);
begin
  Quotient := Value div -7;
  Remainder := Value mod -7;
end;

procedure DivMod64Neg3(Value: Int64; out Quotient, Remainder: Int64);
begin
  Quotient := Value div -3;
  Remainder := Value mod -3;
end;

procedure Check64(Value, Divisor, Quotient, Remainder,
  ExpectedQuotient, ExpectedRemainder: Int64; ErrorCode: Byte);
begin
  if (Quotient <> ExpectedQuotient) or
     (Remainder <> ExpectedRemainder) or
     (Quotient * Divisor + Remainder <> Value) then
  begin
    WriteLn('FAIL64 value=', Value, ' divisor=', Divisor,
      ' actual=', Quotient, ',', Remainder,
      ' expected=', ExpectedQuotient, ',', ExpectedRemainder);
    Halt(ErrorCode);
  end;
end;

var
  Quotient, Remainder: LongInt;
  Quotient64, Remainder64: Int64;
begin
  DivModNeg3(411623104, Quotient, Remainder);
  Check(411623104, -3, Quotient, Remainder, -137207701, 1, 1);

  DivModNeg3(-141083978, Quotient, Remainder);
  Check(-141083978, -3, Quotient, Remainder, 47027992, -2, 2);

  DivModNeg3(Low(LongInt), Quotient, Remainder);
  Check(Low(LongInt), -3, Quotient, Remainder, 715827882, -2, 3);

  DivModNeg7(High(LongInt), Quotient, Remainder);
  Check(High(LongInt), -7, Quotient, Remainder, -306783378, 1, 4);

  DivModNeg19(576742451, Quotient, Remainder);
  Check(576742451, -19, Quotient, Remainder, -30354865, 16, 5);

  DivModNeg19(-964235248, Quotient, Remainder);
  Check(-964235248, -19, Quotient, Remainder, 50749223, -11, 6);

  { the 64-bit path: the sign contribution is bit 63, the N-bit mask of
    the fix must stay a no-op here }
  DivMod64Neg19(Low(Int64), Quotient64, Remainder64);
  Check64(Low(Int64), -19, Quotient64, Remainder64, 485440633518672410, -18, 10);

  DivMod64Neg19(High(Int64), Quotient64, Remainder64);
  Check64(High(Int64), -19, Quotient64, Remainder64, -485440633518672410, 17, 11);

  DivMod64Neg19(576742451345678901, Quotient64, Remainder64);
  Check64(576742451345678901, -19, Quotient64, Remainder64, -30354865860298889, 10, 12);

  DivMod64Neg7(-964235248123456789, Quotient64, Remainder64);
  Check64(-964235248123456789, -7, Quotient64, Remainder64, 137747892589065255, -4, 13);

  DivMod64Neg3(4611686018427387904, Quotient64, Remainder64);
  Check64(4611686018427387904, -3, Quotient64, Remainder64, -1537228672809129301, 1, 14);
end.
