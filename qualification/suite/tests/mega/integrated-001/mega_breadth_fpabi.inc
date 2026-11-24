{ Wide scaled-integer Currency and raw floating-point classifications at call boundaries. }

type
  TBreadthCurrencyResult = record
    Delta: Currency;
    Remainder: Currency;
    Tag: Int64;
  end;

  TBreadthCurrencyMethod = function(Left: Currency; A, B: Integer; Right: Currency;
    Key: Int64; Fraction: Double): TBreadthCurrencyResult; cdecl;

function BreadthCurrencyPacket(Left: Currency; A, B: Integer; Right: Currency;
  Key: Int64; Fraction: Double): TBreadthCurrencyResult; cdecl;
begin
  Result.Delta := Left + Right;
  Result.Remainder := Left - Result.Delta;
  Result.Tag := Key + Int64(A) * 11 - Int64(B) * 13 + Trunc(Fraction * 32.0);
end;

procedure RunBreadthCurrencyABI;
var
  Call: TBreadthCurrencyMethod;
  L, R: Currency;
  LeftBits, RightBits, DeltaBits, RemainderBits: Int64;
  Answer: TBreadthCurrencyResult;
begin
  LeftBits := OpaqueI(9000000000000000017);
  RightBits := OpaqueI(-9000000000000000003);
  Move(LeftBits, L, SizeOf(L));
  Move(RightBits, R, SizeOf(R));
  Call := BreadthCurrencyPacket;
  Answer := Call(L, Integer(OpaqueI(-17)), Integer(OpaqueI(111)), R, OpaqueI(99000000071), OpaqueD(0.625));
  Move(Answer.Delta, DeltaBits, SizeOf(DeltaBits));
  Move(Answer.Remainder, RemainderBits, SizeOf(RemainderBits));
  Check(DeltaBits = 14, 'breadth-currency-abi-keeps-small-difference-of-large-values');
  Check(RemainderBits = 9000000000000000003, 'breadth-currency-abi-keeps-large-exact-remainder');
  Check(Answer.Tag = 98999998461, 'breadth-currency-abi-mixed-int-fp-tail');
  Mix(UInt64(DeltaBits) xor UInt64(RemainderBits));
end;

type
  TBreadthClassifyResult = record
    Echo: Double;
    Flags: Integer;
  end;

  TBreadthFloatClassify = function(Value: Double; Bias: Integer): TBreadthClassifyResult; cdecl;

function BreadthFloatClassify(Value: Double; Bias: Integer): TBreadthClassifyResult; cdecl;
begin
  Result.Echo := Value;
  Result.Flags := Bias;
  If IsNan(Value) then
    Inc(Result.Flags, 1)
  else If IsInfinite(Value) then
    Inc(Result.Flags, 2)
  else If Value = 0.0 then
    Inc(Result.Flags, 4);
  If (DoubleBits(Value) and UInt64($8000000000000000)) <> 0 then
    Inc(Result.Flags, 8);
end;

procedure RunBreadthClassifyABI;
const
  Inputs: array[0..6] of UInt64 = (0, UInt64($8000000000000000), $7FF0000000000000,
    UInt64($FFF0000000000000), $7FF8000000624142, UInt64($FFF800000000CE71), 7);
  Expected: array[0..6] of Integer = (37, 45, 35, 43, 34, 42, 33);
var
  Classify: TBreadthFloatClassify;
  Actual: TBreadthClassifyResult;
  Value: Double;
  Raw: UInt64;
  I: Integer;
begin
  Classify := BreadthFloatClassify;
  for I := Low(Inputs) to High(Inputs) do begin
    Raw := UInt64(OpaqueI(Int64(Inputs[I])));
    Move(Raw, Value, SizeOf(Value));
    Actual := Classify(Value, Integer(OpaqueI(33)));
    Check(Actual.Flags = Expected[I], 'breadth-float-abi-classifies-zero-inf-nan-and-subnormal');
    Check(DoubleBits(Actual.Echo) = Inputs[I], 'breadth-float-abi-preserves-returned-raw-bits');
    Mix(UInt64(Actual.Flags));
  end;
end;

type
  TBreadthExtendedBlock = packed record
    Code: Word;
    Number: Extended;
    Tail: Byte;
  end;

  TBreadthExtendedCall = function(A, B: Extended; Ticket: Int64; C, Factor: Extended): Extended; cdecl;
  TBreadthExtendedEdit = function(Value: TBreadthExtendedBlock; Scale: Extended;
    Added: Double; Mask: Word): TBreadthExtendedBlock; cdecl;

function BreadthExtendedCall(A, B: Extended; Ticket: Int64; C, Factor: Extended): Extended; cdecl;
begin
  Result := (A * B + C) * Factor + Ticket;
end;

function BreadthExtendedEdit(Value: TBreadthExtendedBlock; Scale: Extended;
  Added: Double; Mask: Word): TBreadthExtendedBlock; cdecl;
begin
  Result.Code := Value.Code xor Mask;
  Result.Number := Value.Number * Scale + Added;
  Result.Tail := Value.Tail + Byte(Mask);
end;

procedure RunBreadthExtendedABI;
var
  Call: TBreadthExtendedCall;
  Edit: TBreadthExtendedEdit;
  Original, Answer: TBreadthExtendedBlock;
  Wide: Extended;
  Echo: Double;
begin
  Call := BreadthExtendedCall;
  Wide := Call(OpaqueD(-3.125), OpaqueD(7.5), OpaqueI(90000000011), OpaqueD(4.25), OpaqueD(-2.0));
  Check(Wide = 90000000049.375, 'breadth-extended-abi-mixed-scalar-return');
  Original.Code := $D79E;
  Original.Number := OpaqueD(-9.75);
  Original.Tail := 17;
  Edit := BreadthExtendedEdit;
  Answer := Edit(Original, OpaqueD(3.25), OpaqueD(8.125), Word(OpaqueI($3F17)));
  Check((Answer.Code = $E889) and (Answer.Tail = 40), 'breadth-extended-abi-packed-record-ordinal-lanes');
  Check(Answer.Number = -23.5625, 'breadth-extended-abi-packed-record-float-lane');
  Check((Original.Code = $D79E) and (Original.Number = -9.75) and (Original.Tail = 17),
    'breadth-extended-abi-by-value-source-intact');
  Echo := Answer.Number;
  Mix(DoubleBits(Echo));
end;

procedure RunBreadthFloatingABIForms;
begin
  RunBreadthCurrencyABI;
  RunBreadthClassifyABI;
  RunBreadthExtendedABI;
end;
