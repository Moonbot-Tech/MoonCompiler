unit benchmark_portable;

{$ifdef FPC}
  {$mode delphi}{$H+}
  {$if FPC_FULLVERSION >= 30301}
    {$EXCESSPRECISION OFF}
  {$endif}
{$endif}
{$Q-}{$R-}

interface

uses
  {$ifdef FPC}
  SysUtils;
  {$else}
  System.SysUtils;
  {$endif}

function RunBenchmark(const Name: string; Iterations: Integer): UInt64;

implementation

const
  HashOffset = UInt64($CBF29CE484222325);
  HashPrime = UInt64($100000001B3);

type
  TByteBlock = array[0..4095] of Byte;
  TMoveBlock = array[0..255] of Byte;

procedure Mix(var Digest: UInt64; Value: UInt64);
begin
  Digest := (Digest xor Value) * HashPrime;
end;

function IntegerMix(Iterations: Integer): UInt64;
var
  A, B, Digest: UInt64;
  I: Integer;
begin
  A := UInt64($0123456789ABCDEF);
  B := UInt64($FEDCBA9876543210);
  Digest := HashOffset;
  for I := 1 to Iterations do
  begin
    A := (A xor (A shr 7)) * UInt64($9E3779B185EBCA87) + UInt64(I);
    B := (B + (B shl 3)) xor (A shr 11);
    if (I and 1023) = 0 then
      Mix(Digest, A xor B);
  end;
  Mix(Digest, A);
  Mix(Digest, B);
  Result := Digest;
end;

function SignedDivMod(Iterations: Integer): UInt64;
var
  State, Digest: UInt64;
  Bits: LongWord;
  Value, Divisor, Quotient, Remainder, I: Integer;
begin
  State := UInt64($D1B54A32D192ED03);
  Digest := HashOffset;
  for I := 1 to Iterations do
  begin
    State := State xor (State shr 12);
    State := State xor (State shl 25);
    State := State xor (State shr 27);
    State := State * UInt64($2545F4914F6CDD1D);
    Bits := LongWord(State);
    Move(Bits, Value, SizeOf(Value));
    Divisor := Integer((State shr 32) mod 2001) + 1;
    if (State and 1) <> 0 then
      Divisor := -Divisor;
    If (Value = Low(Integer)) and (Divisor = -1) then
      Divisor := 1;
    Quotient := Value div Divisor;
    Remainder := Value mod Divisor;
    Mix(Digest, UInt64(LongWord(Quotient)) or
      (UInt64(LongWord(Remainder)) shl 32));
  end;
  Result := Digest;
end;

function FloatAffine(Iterations: Integer): UInt64;
const
  InitialXBits: UInt64 = $3FD5555555555555;
  InitialYBits: UInt64 = $3FE45D1745D1745D;
  ResetFactorBits: UInt64 = $3EB0C6F7A0B5ED8D;
var
  X, Y, ResetFactor: Double;
  BitsX, BitsY: UInt64;
  I: Integer;
begin
  BitsX := InitialXBits;
  BitsY := InitialYBits;
  Move(BitsX, X, SizeOf(X));
  Move(BitsY, Y, SizeOf(Y));
  Move(ResetFactorBits, ResetFactor, SizeOf(ResetFactor));
  for I := 1 to Iterations do
  begin
    X := X * 1.00000011920928955078125 + Y;
    Y := (Y + X) * 0.999999940395355224609375 - 0.25;
    if X > 1000000.0 then
    begin
      X := X * ResetFactor;
      Y := Y * ResetFactor;
    end;
  end;
  Move(X, BitsX, SizeOf(BitsX));
  Move(Y, BitsY, SizeOf(BitsY));
  Result := HashOffset;
  Mix(Result, BitsX);
  Mix(Result, BitsY);
end;

function ByteScan(Iterations: Integer): UInt64;
var
  Data: TByteBlock;
  State, Digest: UInt64;
  I, J, Position: Integer;
begin
  State := UInt64($A0761D6478BD642F);
  for I := 0 to High(Data) do
  begin
    State := State * UInt64(6364136223846793005) + UInt64(1442695040888963407);
    Data[I] := Byte(State shr 56);
  end;
  Digest := HashOffset;
  for I := 1 to Iterations do
  begin
    Position := (I * 131) and High(Data);
    for J := 0 to 255 do
      Mix(Digest, Data[(Position + J * 17) and High(Data)]);
  end;
  Result := Digest;
end;

function Move256(Iterations: Integer): UInt64;
var
  Source, Dest: TMoveBlock;
  Digest: UInt64;
  I, J, Position: Integer;
begin
  for I := 0 to High(Source) do
    Source[I] := Byte(I * 29 + 17);
  FillChar(Dest, SizeOf(Dest), 0);
  Digest := HashOffset;
  for I := 1 to Iterations do
  begin
    Move(Source, Dest, SizeOf(Source));
    Position := I and High(Source);
    Source[Position] := Dest[(Position + 97) and High(Dest)] xor Byte(I);
    if (I and 1023) = 0 then
      for J := 0 to High(Dest) do
        Mix(Digest, Dest[J]);
  end;
  for J := 0 to High(Source) do
  begin
    Mix(Digest, Source[J]);
    Mix(Digest, Dest[J]);
  end;
  Result := Digest;
end;

function Utf8Scan(Iterations: Integer): UInt64;
const
  Pattern: array[0..31] of Byte =
    (66, 84, 67, 45, 85, 83, 68, 84, 58, 49, 50, 51, 52, 53, 46, 54,
     55, 56, 57, 124, 206, 187, 45, 67, 65, 84, 45, 240, 159, 152, 128, 59);
var
  Text: RawByteString;
  Digest: UInt64;
  I, J, AsciiCount, LeadCount, SeparatorCount: Integer;
  B: Byte;
begin
  SetLength(Text, Length(Pattern) * 8);
  for I := 0 to 7 do
    Move(Pattern[0], Text[I * Length(Pattern) + 1], Length(Pattern));
  Digest := HashOffset;
  for I := 1 to Iterations do
  begin
    AsciiCount := 0;
    LeadCount := 0;
    SeparatorCount := 0;
    for J := 1 to Length(Text) do
    begin
      B := Byte(Text[J]);
      if B < $80 then
        Inc(AsciiCount)
      else if (B and $C0) = $C0 then
        Inc(LeadCount);
      if (B = Ord(':')) or (B = Ord('-')) or (B = Ord('|')) or
         (B = Ord(';')) then
        Inc(SeparatorCount);
      Digest := (Digest xor B) * HashPrime;
    end;
    Mix(Digest, UInt64(AsciiCount) or (UInt64(LeadCount) shl 20) or
      (UInt64(SeparatorCount) shl 40));
  end;
  Result := Digest;
end;

function SmallAlloc(Iterations: Integer): UInt64;
const
  Sizes: array[0..13] of Integer =
    (0, 1, 2, 7, 8, 15, 16, 31, 32, 63, 64, 127, 128, 255);
var
  Data: TBytes;
  Digest: UInt64;
  I, Size: Integer;
begin
  Digest := HashOffset;
  for I := 1 to Iterations do
  begin
    Size := Sizes[I mod Length(Sizes)];
    SetLength(Data, Size);
    if Size > 0 then
    begin
      Data[0] := Byte(I);
      Data[Size - 1] := Byte(I shr 8);
      Mix(Digest, UInt64(Data[0]) or (UInt64(Data[Size - 1]) shl 8) or
        (UInt64(Size) shl 16));
    end
    else
      Mix(Digest, 0);
    Data := nil;
  end;
  Result := Digest;
end;

function RunBenchmark(const Name: string; Iterations: Integer): UInt64;
begin
  if SameText(Name, 'int64-mix') then
    Result := IntegerMix(Iterations)
  else if SameText(Name, 'int32-divmod') then
    Result := SignedDivMod(Iterations)
  else if SameText(Name, 'float64-affine') then
    Result := FloatAffine(Iterations)
  else if SameText(Name, 'byte-scan') then
    Result := ByteScan(Iterations)
  else if SameText(Name, 'move-256') then
    Result := Move256(Iterations)
  else if SameText(Name, 'utf8-scan') then
    Result := Utf8Scan(Iterations)
  else if SameText(Name, 'small-alloc') then
    Result := SmallAlloc(Iterations)
  else
    raise EArgumentException.Create('unknown benchmark: ' + Name);
end;

end.
