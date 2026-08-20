program float_decimal_core_semantic;

{$ifdef FPC}
  {$mode delphi}
{$endif}

{$Q-}{$R-}

{ Where Extended aliases Double, FloatToDecimal now feeds from the Grisu digit
  core directly.  A target with a distinct 80-bit Extended keeps the typed
  Str path.  The reference renders through Str and parses the text back; both
  implementations must agree bit for bit on the digit string, the exponent
  and the sign over a deterministic stream of raw bit patterns, directed
  boundary values and a Precision x Decimals grid.

  One deliberate difference is pinned separately: fvDouble/fvReal previously
  lost the 17th digit to the width-23 Str buffer; they now produce the same
  full 17-digit sequence as fvExtended, so the reference renders them through
  the width-25 form as well. }

uses
  {$ifdef FPC}
  mormot.core.fpcx64mm,
  {$ifdef UNIX}cthreads,cwstring,{$endif UNIX}
  {$endif}
  SysUtils;

procedure RefFloatToDecimal(Out Result: TFloatRec; const Value; ValueType: TFloatValue; Precision, Decimals: integer);
var
  Buffer: String[254];
  InfNan: string[3];
  N, L, Start, C, ExpIdx, ExponentSign: Integer;
  GotNonZeroBeforeDot, BeforeDot: boolean;
begin
  case ValueType of
    fvExtended:
      Str(Extended(Value):25, Buffer);
    fvDouble,
    fvReal:
      Str(Double(Value):25, Buffer);
    fvSingle:
      Str(Single(Value):16, Buffer);
    fvCurrency:
      Str(Currency(Value):25, Buffer);
    fvComp:
      Str(Currency(Value):23, Buffer);
  end;
  N := 1;
  L := Byte(Buffer[0]);
  while Buffer[N] = ' ' do
    Inc(N);
  Result.Negative := (Buffer[N] = '-');
  If Result.Negative then
    Inc(N)
  else if (Buffer[N] = '+') then
    inc(N);
  If (L >= N + 2) then
    begin
      InfNan := copy(Buffer, N, 3);
      If (InfNan = 'Inf') then
        begin
          Result.Digits[0] := #0;
          Result.Exponent := 32767;
          exit
        end;
      If (InfNan = 'Nan') then
        begin
          Result.Digits[0] := #0;
          Result.Exponent := -32768;
          exit
        end;
    end;
  Start := N;
  Result.Exponent := 0;
  BeforeDot := true;
  GotNonZeroBeforeDot := false;
  while (L >= N) and (Buffer[N] <> 'E') do
    begin
      If Buffer[N] = '.' then
        BeforeDot := false
      else
        begin
          If BeforeDot then
            begin
              Inc(Result.Exponent);
              Result.Digits[N - Start] := AnsiChar(Buffer[N]);
              If Buffer[N] <> '0' then
                GotNonZeroBeforeDot := true;
            end
          else
            Result.Digits[N - Start - 1] := AnsiChar(Buffer[N])
        end;
      Inc(N);
    end;
  Inc(N);
  If N <= L then
    begin
      ExpIdx := N;
      ExponentSign := 1;
      If Buffer[ExpIdx] = '-' then
        begin
          ExponentSign := -1;
          Inc(ExpIdx);
        end
      else if Buffer[ExpIdx] = '+' then
        Inc(ExpIdx);
      C := 0;
      while (ExpIdx <= L) and (Buffer[ExpIdx] in ['0'..'9']) do
        begin
          C := C * 10 + Ord(Buffer[ExpIdx]) - Ord('0');
          Inc(ExpIdx);
        end;
      Inc(Result.Exponent, ExponentSign * C);
    end;
  If BeforeDot then
    N := N - Start - 1
  else
    N := N - Start - 2;
  L := SizeOf(Result.Digits);
  If N < L then
    FillChar(Result.Digits[N], L - N, '0');
  If Decimals + Result.Exponent < Precision Then
    N := Decimals + Result.Exponent
  Else
    N := Precision;
  If N >= L Then
    N := L - 1;
  If N = 0 Then
    begin
      If Result.Digits[0] >= '5' Then
        begin
          Result.Digits[0] := '1';
          Result.Digits[1] := #0;
          Inc(Result.Exponent);
        end
      Else
        Result.Digits[0] := #0;
    end
  Else if N > 0 Then
    begin
      If Result.Digits[N] >= '5' Then
        begin
          Repeat
            Result.Digits[N] := #0;
            Dec(N);
            Inc(Result.Digits[N]);
          Until (N = 0) Or (Result.Digits[N] < ':');
          If Result.Digits[0] = ':' Then
            begin
              Result.Digits[0] := '1';
              Inc(Result.Exponent);
            end;
        end
      Else
        begin
          Result.Digits[N] := '0';
          While (N > -1) And (Result.Digits[N] = '0') Do
            begin
              Result.Digits[N] := #0;
              Dec(N);
            end;
        end;
      end
  Else
    Result.Digits[0] := #0;
  If (Result.Digits[0] = #0) and
     not GotNonZeroBeforeDot then
    begin
      Result.Exponent := 0;
      Result.Negative := False;
    end;
end;

var
  Failures: Integer = 0;

function DigitsOf(const R: TFloatRec): string;
var
  I: Integer;
begin
  Result := '';
  I := Low(R.Digits);
  while (I <= High(R.Digits)) and (Ord(R.Digits[I]) <> 0) do
    begin
      Result := Result + Char(Chr(Ord(R.Digits[I])));
      Inc(I);
    end;
end;

procedure CompareOne(const NameText: string; const Value; ValueType: TFloatValue; Precision, Decimals: Integer);
var
  Actual, Expected: TFloatRec;
begin
  FillChar(Actual, SizeOf(Actual), Ord('9'));
  FillChar(Expected, SizeOf(Expected), Ord('9'));
  FloatToDecimal(Actual, Value, ValueType, Precision, Decimals);
  RefFloatToDecimal(Expected, Value, ValueType, Precision, Decimals);
  If (DigitsOf(Actual) <> DigitsOf(Expected)) or
     (Actual.Exponent <> Expected.Exponent) or
     (Actual.Negative <> Expected.Negative) then
    begin
      WriteLn('FAIL ', NameText, ' P=', Precision, ' D=', Decimals,
        ': digits "', DigitsOf(Actual), '"/"', DigitsOf(Expected),
        '" exp ', Actual.Exponent, '/', Expected.Exponent,
        ' neg ', Actual.Negative, '/', Expected.Negative);
      Inc(Failures);
      If Failures > 20 then
        Halt(1);
    end;
end;

procedure CompareDouble(Bits: UInt64; Precision, Decimals: Integer);
var
  D: Double absolute Bits;
  E: Extended;
begin
  { Converting a Double denormal or signalling NaN to the native 80-bit
    Extended can raise before FloatToDecimal is entered.  The Double path
    must still cover those raw encodings; exercise the distinct Extended
    path on all ordinary finite Double values converted exactly to Extended. }
  If ((Bits shr 52) and $7FF <> 0) and
     ((Bits shr 52) and $7FF <> $7FF) then
    begin
      E := D;
      CompareOne('extended ' + IntToHex(Bits, 16), E, fvExtended,
        Precision, Decimals);
    end;
{$ifdef FPC_HAS_TYPE_EXTENDED}
  { The historical Linux x86-64 Str(Double) path can raise before producing
    a record for denormals (EUnderflow) and NaN payloads (EInvalidOp).  The
    direct Double core is not used on this ABI, so keep those existing
    boundaries out of the equivalence matrix. }
  If ((((Bits shr 52) and $7FF) = 0) or
      (((Bits shr 52) and $7FF) = $7FF)) and
     ((Bits and $000FFFFFFFFFFFFF) <> 0) then
    exit;
{$endif FPC_HAS_TYPE_EXTENDED}
  CompareOne('fvdouble ' + IntToHex(Bits, 16), D, fvDouble, Precision, Decimals);
end;

procedure CompareSingle(Bits: Cardinal; Precision, Decimals: Integer);
var
  S: Single absolute Bits;
begin
  { fvSingle stays on the text path; the comparison is a regression anchor.
    Single NaN payloads are skipped: passing them through the double
    parameter raises InvalidOp in both implementations alike. }
  If ((Bits shr 23) and $FF = $FF) and (Bits and $7FFFFF <> 0) then
    exit;
  CompareOne('single ' + IntToHex(Bits, 8), S, fvSingle, Precision, Decimals);
end;

const
  DirectedBits: array[0..15] of UInt64 = (
    $0000000000000000,  // +0
    $8000000000000000,  // -0
    $0000000000000001,  // smallest denormal
    $000FFFFFFFFFFFFF,  // largest denormal
    $0010000000000000,  // smallest normal
    $7FEFFFFFFFFFFFFF,  // largest normal
    $7FF0000000000000,  // +Inf
    $FFF0000000000000,  // -Inf
    $7FF8000000000000,  // QNaN
    $7FF0000000000001,  // SNaN
    $3FB999999999999A,  // 0.1
    $3FC999999999999A,  // 0.2
    $3FE0000000000000,  // 0.5
    $4004000000000000,  // 2.5
    $54B249AD2594C37D,  // 1e100
    $01A56E1FC2F8F359   // 1e-300
  );

var
  I, P, D: Integer;
  Seed: UInt64;
  Bits: UInt64;
begin
  { directed values over the full Precision/Decimals grid }
  for I := Low(DirectedBits) to High(DirectedBits) do
    for P := 1 to 18 do
      begin
        CompareDouble(DirectedBits[I], P, 9999);
        CompareDouble(DirectedBits[I], P, 0);
        CompareDouble(DirectedBits[I], P, -3);
        CompareDouble(DirectedBits[I], P, 3);
      end;

  { deterministic bit-pattern stream; splitmix64 covers every exponent band }
  Seed := $9E3779B97F4A7C15;
  for I := 1 to 400000 do
    begin
      Seed := Seed + $9E3779B97F4A7C15;
      Bits := Seed;
      Bits := (Bits xor (Bits shr 30)) * UInt64($BF58476D1CE4E5B9);
      Bits := (Bits xor (Bits shr 27)) * UInt64($94D049BB133111EB);
      Bits := Bits xor (Bits shr 31);
      CompareDouble(Bits, 17, 9999);
      CompareDouble(Bits, 15, 9999);
      CompareSingle(Cardinal(Bits), 9, 9999);
      If I mod 37 = 0 then
        CompareDouble(Bits, 1 + Integer(Bits mod 18), Integer(Bits mod 7) - 3);
    end;

  If Failures > 0 then
    Halt(1);
  WriteLn('FLOAT_DECIMAL_CORE_SEMANTIC_OK');
end.
