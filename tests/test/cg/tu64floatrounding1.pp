{ %CPU=x86_64 }
{ %OPT=-O3 }

program tu64floatrounding1;

{$mode delphiunicode}
{$INLINE OFF}{$Q-}{$R-}

uses
  Math;

const
  ExactDouble: Double = UInt64($8000000000000401);
  ExactSingle: Single = UInt64($8000008000000001);
  ExactUInt128Double: Double =
    (UInt128(1) shl 127) or (UInt128(1) shl 74) or UInt128(1);
  ExactUInt128Single: Single =
    (UInt128(1) shl 127) or (UInt128(1) shl 103) or UInt128(1);
  ExactInt128Double: Double = Low(Int128);

var
  GlobalValue: UInt64;

function DoubleBits(const Value: Double): UInt64;
begin
  Move(Value, Result, SizeOf(Result));
end;

function SingleBits(const Value: Single): Cardinal;
begin
  Move(Value, Result, SizeOf(Result));
end;

function FromValueDouble(Value: UInt64): Double; noinline;
begin
  Result := Value;
end;

function FromValueSingle(Value: UInt64): Single; noinline;
begin
  Result := Value;
end;

function FromConstRef(const Value: UInt64): Double; noinline;
begin
  Result := Value;
end;

function FromGlobal: Double; noinline;
begin
  Result := GlobalValue;
end;

procedure Fail(Code: LongInt);
begin
  Halt(Code);
end;

function ExactBits(Value: UInt64; Precision, Bias: LongInt;
  Mode: TFPURoundingMode): UInt64;
var
  Exponent, Shift: LongInt;
  Work, Quotient, Remainder, Half: UInt64;
  RoundUp: Boolean;
begin
  if Value = 0 then
    Exit(0);

  Exponent := 0;
  Work := Value;
  while Work > 1 do
    begin
      Inc(Exponent);
      Work := Work shr 1;
    end;

  Shift := Exponent - (Precision - 1);
  if Shift <= 0 then
    Quotient := Value shl (-Shift)
  else
    begin
      Quotient := Value shr Shift;
      Remainder := Value and ((UInt64(1) shl Shift) - 1);
      Half := UInt64(1) shl (Shift - 1);
      RoundUp := False;
      case Mode of
        rmNearest:
          RoundUp := (Remainder > Half) or
            ((Remainder = Half) and Odd(Quotient));
        rmUp:
          RoundUp := Remainder <> 0;
        else
          RoundUp := False;
      end;
      if RoundUp then
        Inc(Quotient);
      if Quotient = (UInt64(1) shl Precision) then
        begin
          Quotient := Quotient shr 1;
          Inc(Exponent);
        end;
    end;

  Result := (UInt64(Exponent + Bias) shl (Precision - 1)) or
    (Quotient and ((UInt64(1) shl (Precision - 1)) - 1));
end;

procedure CheckValue(Value: UInt64; Mode: TFPURoundingMode; Code: LongInt);
begin
  if DoubleBits(FromValueDouble(Value)) <> ExactBits(Value, 53, 1023, Mode) then
    Fail(Code);
  if SingleBits(FromValueSingle(Value)) <>
      Cardinal(ExactBits(Value, 24, 127, Mode)) then
    Fail(Code + 1);
end;

procedure CheckRoundingMatrix;
var
  Mode: TFPURoundingMode;
  BitIndex, Delta, Index: LongInt;
  Value: UInt64;
begin
  for Mode := Low(TFPURoundingMode) to High(TFPURoundingMode) do
    begin
      SetRoundMode(Mode);
      for BitIndex := 0 to 63 do
        for Delta := -5 to 5 do
          CheckValue((UInt64(1) shl BitIndex) + UInt64(Int64(Delta)),
            Mode, 10 + Ord(Mode) * 2);

      for Delta := -5 to 5 do
        begin
          CheckValue(UInt64($8000000000000400) + UInt64(Int64(Delta)),
            Mode, 20 + Ord(Mode) * 2);
          CheckValue(UInt64($8000008000000000) + UInt64(Int64(Delta)),
            Mode, 30 + Ord(Mode) * 2);
        end;

      Value := 142857;
      for Index := 1 to 20000 do
        begin
          Value := Value * UInt64(6364136223846793005) +
            UInt64(1442695040888963407);
          CheckValue(Value, Mode, 40 + Ord(Mode) * 2);
        end;
    end;
  SetRoundMode(rmNearest);
end;

procedure CheckSourceLocations;
begin
  GlobalValue := UInt64($8000000000000401);
  if DoubleBits(FromConstRef(GlobalValue)) <> UInt64($43e0000000000001) then
    Fail(60);
  if DoubleBits(FromGlobal) <> UInt64($43e0000000000001) then
    Fail(61);
end;

procedure CheckPrecisionFlags;
var
  SavedMXCSR: DWord;
  DoubleValue: Double;
  SingleValue: Single;
begin
  SavedMXCSR := GetMXCSR;
  try
    SetRoundMode(rmNearest);

    SetMXCSR(GetMXCSR and not DWord($3f));
    DoubleValue := FromValueDouble(UInt64($8000000000000000));
    if (GetMXCSR and $20) <> 0 then
      Fail(70);
    if DoubleBits(DoubleValue) <> UInt64($43e0000000000000) then
      Fail(71);

    SetMXCSR(GetMXCSR and not DWord($3f));
    DoubleValue := FromValueDouble(UInt64($8000000000000001));
    if (GetMXCSR and $20) = 0 then
      Fail(72);
    if DoubleBits(DoubleValue) <> UInt64($43e0000000000000) then
      Fail(73);

    SetMXCSR(GetMXCSR and not DWord($3f));
    SingleValue := FromValueSingle(UInt64($8000000000000000));
    if (GetMXCSR and $20) <> 0 then
      Fail(74);
    if SingleBits(SingleValue) <> Cardinal($5f000000) then
      Fail(75);

    SetMXCSR(GetMXCSR and not DWord($3f));
    SingleValue := FromValueSingle(UInt64($8000000000000001));
    if (GetMXCSR and $20) = 0 then
      Fail(76);
    if SingleBits(SingleValue) <> Cardinal($5f000000) then
      Fail(77);
  finally
    SetMXCSR(SavedMXCSR);
  end;
end;

procedure CheckConstants;
begin
  if DoubleBits(ExactDouble) <> UInt64($43e0000000000001) then
    Fail(80);
  if SingleBits(ExactSingle) <> Cardinal($5f000001) then
    Fail(81);
  if DoubleBits(ExactUInt128Double) <> UInt64($47e0000000000001) then
    Fail(82);
  if SingleBits(ExactUInt128Single) <> Cardinal($7f000001) then
    Fail(83);
  if DoubleBits(ExactInt128Double) <> UInt64($c7e0000000000000) then
    Fail(84);
end;

begin
  CheckConstants;
  CheckSourceLocations;
  CheckPrecisionFlags;
  CheckRoundingMatrix;
end.
