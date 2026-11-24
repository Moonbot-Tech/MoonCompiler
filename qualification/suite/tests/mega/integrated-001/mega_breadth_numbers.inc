{ Unsigned machine arithmetic, including cases where CF and OF disagree. }

type
  TBreadthUnsignedOperation = (buAdd, buSubtract, buMultiply);

{$Q+}
function BreadthCheckedUnsigned(A, B: UInt64; Operation: TBreadthUnsignedOperation): UInt64;
begin
  case Operation of
    buAdd: Result := A + B;
    buSubtract: Result := A - B;
  else
    Result := A * B;
  end;
end;
{$Q-}

procedure RunBreadthUnsignedFlags;
type
  TCheckedValues = record
    A, B, Value: UInt64;
    Operation: TBreadthUnsignedOperation;
    Fails: Boolean;
  end;
const
  Sentinel = UInt64($A5C398760BAB1703);
  Cases: array[0..5] of TCheckedValues = (
    (A: UInt64($7FFFFFFFFFFFFFFF); B: 1; Value: UInt64($8000000000000000); Operation: buAdd; Fails: False),
    (A: High(UInt64); B: 1; Value: Sentinel; Operation: buAdd; Fails: True),
    (A: UInt64($8000000000000000); B: 1; Value: UInt64($7FFFFFFFFFFFFFFF); Operation: buSubtract; Fails: False),
    (A: 0; B: 1; Value: Sentinel; Operation: buSubtract; Fails: True),
    (A: UInt64($4000000000000000); B: 2; Value: UInt64($8000000000000000); Operation: buMultiply; Fails: False),
    (A: UInt64($8000000000000000); B: 2; Value: Sentinel; Operation: buMultiply; Fails: True));
var
  I: Integer;
  Actual: UInt64;
  Caught: Boolean;
begin
  for I := Low(Cases) to High(Cases) do
  begin
    Actual := Sentinel;
    Caught := False;
    try
      Actual := BreadthCheckedUnsigned(UInt64(OpaqueI(Int64(Cases[I].A))),
        UInt64(OpaqueI(Int64(Cases[I].B))), Cases[I].Operation);
    except
      on EIntOverflow do Caught := True;
    end;
    Check(Caught = Cases[I].Fails, 'breadth-checked-unsigned-carry-not-signed-overflow');
    Check(Actual = Cases[I].Value, 'breadth-checked-unsigned-commits-success-only');
    Mix(Actual);
  end;
end;

procedure RunBreadthUnsignedLiteralDivisors;
const
  LargeDivisor = UInt64($800000000000007B);
  Inputs: array[0..5] of UInt64 = (0, High(UInt64), $7FFFFFFFFFFFFFFF,
    LargeDivisor, UInt64($800000000000007C), 4294967297);
  Quotients3: array[0..5] of UInt64 = (0, 6148914691236517205, 3074457345618258602,
    3074457345618258643, 3074457345618258644, 1431655765);
  Remainders3: array[0..5] of UInt64 = (0, 0, 1, 2, 0, 2);
  Quotients365: array[0..5] of UInt64 = (0, 50539024859478223, 25269512429739111,
    25269512429739112, 25269512429739112, 11767033);
  Remainders365: array[0..5] of UInt64 = (0, 220, 292, 51, 52, 252);
  QuotientsLarge: array[0..5] of UInt64 = (0, 1, 0, 1, 1, 0);
  RemaindersLarge: array[0..5] of UInt64 = (0, 9223372036854775684, 9223372036854775807, 0, 1, 4294967297);
var
  I: Integer;
  V, Q, R: UInt64;
begin
  for I := Low(Inputs) to High(Inputs) do
  begin
    V := UInt64(OpaqueI(Int64(Inputs[I])));
    Q := V div 3;
    R := V mod 3;
    Check((Q = Quotients3[I]) and (R = Remainders3[I]), 'breadth-u64-divmod-literal-3');
    Mix(Q xor R);
    Q := V div 365;
    R := V mod 365;
    Check((Q = Quotients365[I]) and (R = Remainders365[I]), 'breadth-u64-divmod-literal-365');
    Mix(Q xor R);
    Q := V div LargeDivisor;
    R := V mod LargeDivisor;
    Check((Q = QuotientsLarge[I]) and (R = RemaindersLarge[I]), 'breadth-u64-divmod-literal-high-bit');
    Mix(Q xor R);
  end;
end;

function BreadthU64Double(V: UInt64): Double;
begin
  Result := V;
end;

function BreadthU64Single(V: UInt64): Single;
begin
  Result := V;
end;

procedure RunBreadthUnsignedFloatConsumers;
const
  Inputs: array[0..7] of UInt64 = (0, 16777217, 9007199254740993, 9007199254740995,
    UInt64($8000000000000000), UInt64($8000000000000800), UInt64($8000010000000000), High(UInt64));
  DoubleExpected: array[0..7] of UInt64 = (0, $4170000010000000, $4340000000000000,
    $4340000000000002, $43E0000000000000, $43E0000000000001, $43E0000020000000, $43F0000000000000);
  SingleExpected: array[0..7] of Cardinal = (0, $4B800000, $5A000000, $5A000000,
    $5F000000, $5F000000, $5F000001, $5F800000);
var
  OldMode: TFPURoundingMode;
  I: Integer;
  V: UInt64;
  D: Double;
  S: Single;
  SB: Cardinal;
begin
  OldMode := GetRoundMode;
  SetRoundMode(rmNearest);
  try
    for I := Low(Inputs) to High(Inputs) do
    begin
      V := UInt64(OpaqueI(Int64(Inputs[I])));
      D := BreadthU64Double(V);
      S := BreadthU64Single(V);
      Move(S, SB, SizeOf(SB));
      Check(DoubleBits(D) = DoubleExpected[I], 'breadth-u64-double-abi-bits');
      Check(SB = SingleExpected[I], 'breadth-u64-single-abi-bits');
      Mix(UInt64(SB) xor DoubleBits(D));
    end;
  finally
    SetRoundMode(OldMode);
  end;
end;

procedure RunBreadthNumericForms;
begin
  RunBreadthUnsignedFlags;
  RunBreadthUnsignedLiteralDivisors;
  RunBreadthUnsignedFloatConsumers;
end;
