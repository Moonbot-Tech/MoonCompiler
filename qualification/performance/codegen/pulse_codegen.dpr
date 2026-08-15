program pulse_codegen;

{$ifndef FPC}
  {$APPTYPE CONSOLE}
{$endif}

{$ifdef FPC}
  {$mode delphi}{$H+}
{$endif}

{$Q-}{$R-}

uses
  {$if defined(FPC) and not defined(PULSE_DEFAULT_MM)}
  mormot.core.fpcx64mm,
  {$ifend}
  SysUtils,
  Math,
  perf_clock in '..\common\perf_clock.pas',
  pulse_process_metrics in '..\common\pulse_process_metrics.pas',
  pulse_harness in '..\common\pulse_harness.pas',
  pulse_call_targets in 'pulse_call_targets.pas';

type
  TUInt64Func = function(Value: UInt64): UInt64;
  TPlainRecord = record
    A, B, C, D: UInt64;
  end;
  TPackedRecord = packed record
    Flag: Byte;
    A: UInt64;
    B: UInt32;
    C: UInt16;
  end;
  TPulseEnum = (peZero, peOne, peTwo, peThree, peFour, peFive, peSix,
    peSeven);
  TPulseSet = set of Byte;

const
  InnerCount = 64;
  L1Count = 4096;
  L2Count = 32768;
  LlcCount = 524288;
  DramCount = 4194304;

var
  Input64: array[0..255] of UInt64;
  Input32: array[0..255] of UInt32;
  L1Data, L2Data, LlcData, DramData: array of UInt64;
  RandomIndex: array of UInt32;
  NextIndex: array of UInt32;
  VirtualAdder: TPulseVirtualAdder;
  InterfaceAdder: IPulseAdder;
  DirectFunc: TUInt64Func;
  RuntimeUpper: Integer;

function RotateLeft64(Value: UInt64; Count: Integer): UInt64; inline;
begin
  Result := (Value shl Count) or (Value shr (64 - Count));
end;

function InlineAdd(Value: UInt64): UInt64; inline;
begin
  Result := (Value xor (Value shr 17)) + UInt64($9E3779B185EBCA87);
end;

function CaseDependencyAdd(Iterations: Integer): UInt64;
var
  I, J: Integer;
  X: UInt64;
begin
  X := UInt64($123456789ABCDEF0);
  for I := 1 to Iterations do
    for J := 1 to InnerCount do
      X := X * UInt64(2862933555777941757) + UInt64(3037000493);
  Result := X;
end;

function CaseIndependent4(Iterations: Integer): UInt64;
var
  I, J: Integer;
  A, B, C, D: UInt64;
begin
  A := 1;
  B := 3;
  C := 5;
  D := 7;
  for I := 1 to Iterations do
    for J := 1 to InnerCount do
    begin
      A := A * UInt64(2862933555777941757) + 11;
      B := B * UInt64(3202034522624059733) + 13;
      C := C * UInt64(3935559000370003845) + 17;
      D := D * UInt64(2691343689449507681) + 19;
    end;
  Result := A xor RotateLeft64(B, 7) xor RotateLeft64(C, 19) xor
    RotateLeft64(D, 37);
end;

function CaseInlineCall(Iterations: Integer): UInt64;
var
  I, J: Integer;
  X: UInt64;
begin
  X := 1;
  for I := 1 to Iterations do
    for J := 1 to InnerCount do
      X := InlineAdd(X);
  Result := X;
end;

function CaseDirectCall(Iterations: Integer): UInt64;
var
  I, J: Integer;
  X: UInt64;
begin
  X := 1;
  for I := 1 to Iterations do
    for J := 1 to InnerCount do
      X := PulseDirectAdd(X);
  Result := X;
end;

function CaseIndirectCall(Iterations: Integer): UInt64;
var
  I, J: Integer;
  X: UInt64;
begin
  X := 1;
  for I := 1 to Iterations do
    for J := 1 to InnerCount do
      X := DirectFunc(X);
  Result := X;
end;

function CaseVirtualCall(Iterations: Integer): UInt64;
var
  I, J: Integer;
  X: UInt64;
begin
  X := 1;
  for I := 1 to Iterations do
    for J := 1 to InnerCount do
      X := VirtualAdder.Add(X);
  Result := X;
end;

function CaseInterfaceCall(Iterations: Integer): UInt64;
var
  I, J: Integer;
  X: UInt64;
begin
  X := 1;
  for I := 1 to Iterations do
    for J := 1 to InnerCount do
      X := InterfaceAdder.Add(X);
  Result := X;
end;

function CaseManyArgs(Iterations: Integer): UInt64;
var
  I, J: Integer;
  X: UInt64;
begin
  X := 1;
  for I := 1 to Iterations do
    for J := 1 to InnerCount do
      X := PulseManyArgs(X, X + 1, X + 2, X + 3, X + 4, X + 5,
        X + 6, X + 7);
  Result := X;
end;

function CaseInt32Mixed(Iterations: Integer): UInt64;
var
  I, J: Integer;
  A, B, C: Int32;
begin
  A := 123456789;
  B := -98765431;
  C := 17;
  for I := 1 to Iterations do
    for J := 1 to InnerCount do
    begin
      A := (A xor (B shr 3)) + C;
      B := B + A * 3 - J;
      C := C xor (A shl (J and 7));
    end;
  Result := UInt32(A) or (UInt64(UInt32(B)) shl 32) xor UInt32(C);
end;

function CaseNarrowIntegers(Iterations: Integer): UInt64;
var
  I, J: Integer;
  B: Byte;
  W: Word;
  S: UInt64;
begin
  B := 17;
  W := 513;
  S := 0;
  for I := 1 to Iterations do
    for J := 1 to InnerCount do
    begin
      B := Byte(B * 13 + J);
      W := Word(W * 257 + B + I);
      S := S + B + W;
    end;
  Result := S xor B xor (UInt64(W) shl 32);
end;

function CaseUInt64Mixed(Iterations: Integer): UInt64;
var
  I, J: Integer;
  A, B: UInt64;
begin
  A := UInt64($FEDCBA9876543210);
  B := UInt64($0123456789ABCDEF);
  for I := 1 to Iterations do
    for J := 1 to InnerCount do
    begin
      A := RotateLeft64(A + B, 13) xor UInt64(J);
      B := RotateLeft64(B xor A, 29) + UInt64($9E3779B185EBCA87);
    end;
  Result := A xor B;
end;

function CaseDivConst(Iterations: Integer): UInt64;
var
  I, J: Integer;
  X, S: UInt64;
begin
  S := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      X := Input64[(I + J) and 255];
      S := S + X div 10 + X mod 1000 + X div 65537;
    end;
  Result := S;
end;

function CaseDivRuntime(Iterations: Integer): UInt64;
var
  I, J: Integer;
  X, D, S: UInt64;
begin
  S := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      X := Input64[(I + J) and 255];
      D := UInt64(J + 3);
      S := S + X div D + X mod D;
    end;
  Result := S;
end;

function CaseDouble(Iterations: Integer): UInt64;
var
  I, J: Integer;
  X, Y: Double;
begin
  X := 1.000001;
  Y := 0.999999;
  for I := 1 to Iterations do
    for J := 1 to InnerCount do
    begin
      X := X * 1.0000001192092896 + Y;
      Y := Y * 0.9999999403953552 + X * 0.00000001;
      If X > 1000000.0 then
        X := X * 0.000001;
    end;
  Result := PUInt64(@X)^ xor RotateLeft64(PUInt64(@Y)^, 17);
end;

function CaseSingle(Iterations: Integer): UInt64;
var
  I, J: Integer;
  X, Y: Single;
begin
  X := 1.0001;
  Y := 0.9999;
  for I := 1 to Iterations do
    for J := 1 to InnerCount do
    begin
      X := X * 1.000119 + Y;
      Y := Y * 0.999941 + X * 0.0001;
      If X > 10000.0 then
        X := X * 0.0001;
    end;
  Result := UInt64(PUInt32(@X)^) or (UInt64(PUInt32(@Y)^) shl 32);
end;

function CaseMathFunctions(Iterations: Integer): UInt64;
var
  I, J: Integer;
  X, S: Double;
begin
  S := 0;
  for I := 1 to Iterations do
    for J := 1 to 16 do
    begin
      X := (I + J) * 0.001;
      S := S + Sin(X) * Cos(X) + Sqrt(X + 1.0) + ArcTan(X);
    end;
  Result := PUInt64(@S)^;
end;

function CaseCurrency(Iterations: Integer): UInt64;
var
  I, J: Integer;
  X, Y, Z: Currency;
begin
  X := 123.4567;
  Y := 7.8901;
  for I := 1 to Iterations do
    for J := 1 to InnerCount do
    begin
      Z := X * Y;
      X := Z / 7.0000 + J;
      If X > 1000000.0000 then
        X := X / 1000.0000;
    end;
  Result := PUInt64(@X)^;
end;

function CaseForRuntime(Iterations: Integer): UInt64;
var
  I, J, Upper: Integer;
  S: UInt64;
begin
  S := 0;
  Upper := RuntimeUpper;
  for I := 1 to Iterations do
    for J := 0 to Upper do
      S := S + UInt64((J + I) xor (J shl 3));
  Result := S;
end;

function CaseForZeroToZero(Iterations: Integer): UInt64;
var
  I, J, Upper: Integer;
  S: UInt64;
begin
  S := 0;
  Upper := Input32[0];
  for I := 1 to Iterations do
    for J := 0 to Upper do
      S := S + UInt64(I + J);
  Result := S;
end;

function CaseForByteFull(Iterations: Integer): UInt64;
var
  I: Integer;
  B: Byte;
  S: UInt64;
begin
  S := 0;
  for I := 1 to Iterations do
    for B := 0 to 255 do
      S := S + UInt64(B xor Byte(I));
  Result := S;
end;

function CaseBranchPredictable(Iterations: Integer): UInt64;
var
  I, J: Integer;
  X, S: UInt64;
begin
  S := 0;
  for I := 1 to Iterations do
    for J := 0 to 255 do
    begin
      X := Input64[J];
      If J < 240 then
        S := S + X
      else
        S := S xor X;
    end;
  Result := S;
end;

function CaseBranchRandom(Iterations: Integer): UInt64;
var
  I, J: Integer;
  X, S: UInt64;
begin
  S := 0;
  for I := 1 to Iterations do
    for J := 0 to 255 do
    begin
      X := Input64[J];
      If (X and 1) <> 0 then
        S := S + X
      else
        S := S xor X;
    end;
  Result := S;
end;

function CaseDenseCase(Iterations: Integer): UInt64;
var
  I, J: Integer;
  S: UInt64;
begin
  S := 0;
  for I := 1 to Iterations do
    for J := 0 to 255 do
      case Input32[J] and 7 of
        0: S := S + 3;
        1: S := S + 5;
        2: S := S + 7;
        3: S := S + 11;
        4: S := S + 13;
        5: S := S + 17;
        6: S := S + 19;
        7: S := S + 23;
      end;
  Result := S;
end;

function CaseSparseCase(Iterations: Integer): UInt64;
var
  I, J: Integer;
  V: UInt32;
  S: UInt64;
begin
  S := 0;
  for I := 1 to Iterations do
    for J := 0 to 255 do
    begin
      V := Input32[J] and 1023;
      case V of
        1: S := S + 3;
        17: S := S + 5;
        63: S := S + 7;
        255: S := S + 11;
        511: S := S + 13;
        777: S := S + 17;
        1001: S := S + 19;
        else S := S + V;
      end;
    end;
  Result := S;
end;

function CaseEnumSet(Iterations: Integer): UInt64;
var
  I, J: Integer;
  E: TPulseEnum;
  Values: TPulseSet;
  S: UInt64;
begin
  Values := [1, 3, 5, 8, 13, 21, 34, 55, 89, 144, 233];
  S := 0;
  for I := 1 to Iterations do
    for J := 0 to 255 do
    begin
      E := TPulseEnum(J and 7);
      If Byte(J) in Values then
        S := S + UInt64(Ord(E) + J)
      else
        S := S xor UInt64(Ord(E) * 17 + J);
    end;
  Result := S;
end;

function CaseTryFinally(Iterations: Integer): UInt64;
var
  I, J: Integer;
  X, Cleanup: UInt64;
begin
  X := 0;
  Cleanup := 0;
  for I := 1 to Iterations do
    for J := 1 to 16 do
      try
        X := X + Input64[(I + J) and 255];
      finally
        Cleanup := Cleanup + UInt64(J);
      end;
  Result := X xor Cleanup;
end;

function CaseCseExpressions(Iterations: Integer): UInt64;
var
  I, J: Integer;
  A, B, S: UInt64;
begin
  S := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      A := Input64[(I + J) and 255];
      B := Input64[(I + J + 1) and 255];
      S := S + (A * 17 + B * 31) xor (A * 17 + B * 31) shr 13;
    end;
  Result := S;
end;

function CaseDeadStores(Iterations: Integer): UInt64;
var
  I, J: Integer;
  R: TPlainRecord;
  S: UInt64;
begin
  S := 0;
  for I := 1 to Iterations do
    for J := 1 to InnerCount do
    begin
      R.A := Input64[(I + J) and 255];
      R.A := R.A + 1;
      R.A := Input64[(I + J + 1) and 255];
      R.B := R.A * 3;
      R.B := R.A * 5;
      R.C := R.B xor UInt64(J);
      R.D := R.C + R.A;
      S := S + R.D;
    end;
  Result := S;
end;

function RecurseTree(Depth: Integer; Value: UInt64): UInt64;
begin
  If Depth = 0 then
    Exit((Value xor (Value shr 7)) + 3);
  Result := RecurseTree(Depth - 1, Value * 3 + 1) xor
    RecurseTree(Depth - 1, Value * 5 + 7);
end;

function CaseRecursion(Iterations: Integer): UInt64;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    Result := Result + RecurseTree(8, UInt64(I));
end;

function CaseEarlyExit(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Needle, S: UInt64;
begin
  S := 0;
  for I := 1 to Iterations do
  begin
    Needle := Input64[(I * 37) and 255];
    for J := 0 to 255 do
      If Input64[J] = Needle then
      begin
        S := S + UInt64(J);
        Break;
      end;
  end;
  Result := S;
end;

function ScanData(const Data: array of UInt64; Iterations: Integer): UInt64;
var
  I, J: Integer;
  S: UInt64;
begin
  S := 0;
  for I := 1 to Iterations do
    for J := 0 to High(Data) do
      S := S + Data[J];
  Result := S;
end;

function CaseScanL1(Iterations: Integer): UInt64;
begin
  Result := ScanData(L1Data, Iterations);
end;

function CaseScanL2(Iterations: Integer): UInt64;
begin
  Result := ScanData(L2Data, Iterations);
end;

function CaseScanLlc(Iterations: Integer): UInt64;
begin
  Result := ScanData(LlcData, Iterations);
end;

function CaseScanDram(Iterations: Integer): UInt64;
begin
  Result := ScanData(DramData, Iterations);
end;

function CaseStrided(Iterations: Integer): UInt64;
var
  I, J: Integer;
  S: UInt64;
begin
  S := 0;
  for I := 1 to Iterations do
    for J := 0 to (Length(LlcData) div 8) - 1 do
      S := S + LlcData[J * 8];
  Result := S;
end;

function CaseRandomRead(Iterations: Integer): UInt64;
var
  I, J: Integer;
  S: UInt64;
begin
  S := 0;
  for I := 1 to Iterations do
    for J := 0 to High(RandomIndex) do
      S := S + LlcData[RandomIndex[J]];
  Result := S;
end;

function CasePointerChase(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Index: UInt32;
begin
  Index := 0;
  for I := 1 to Iterations do
    for J := 1 to 4096 do
      Index := NextIndex[Index];
  Result := Index;
end;

function CaseAliasedUpdate(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Values: array[0..255] of UInt64;
  P, Q: PUInt64;
begin
  Move(Input64, Values, SizeOf(Values));
  for I := 1 to Iterations do
    for J := 0 to 254 do
    begin
      P := @Values[J];
      Q := @Values[J + 1];
      P^ := P^ + Q^;
    end;
  Result := Values[0] xor Values[127] xor Values[255];
end;

function CaseMatrix16(Iterations: Integer): UInt64;
var
  I, J, K, N: Integer;
  A, B, C: array[0..15, 0..15] of Double;
  S: Double;
begin
  for J := 0 to 15 do
    for K := 0 to 15 do
    begin
      A[J, K] := (J + 1) * 0.25 + K;
      B[J, K] := (K + 1) * 0.125 - J;
    end;
  for N := 1 to Iterations do
    for I := 0 to 15 do
      for J := 0 to 15 do
      begin
        S := 0;
        for K := 0 to 15 do
          S := S + A[I, K] * B[K, J];
        C[I, J] := S;
      end;
  S := C[0, 0] + C[7, 9] + C[15, 15];
  Result := PUInt64(@S)^;
end;

function CaseMove(Iterations: Integer): UInt64;
var
  I: Integer;
  Source, Target: array[0..4095] of Byte;
begin
  FillChar(Source, SizeOf(Source), $5A);
  FillChar(Target, SizeOf(Target), 0);
  for I := 1 to Iterations do
    Move(Source[0], Target[0], SizeOf(Source));
  Result := UInt64(Target[0]) + UInt64(Target[High(Target)]) shl 8;
end;

function CaseFillChar(Iterations: Integer): UInt64;
var
  I: Integer;
  Target: array[0..4095] of Byte;
begin
  for I := 1 to Iterations do
    FillChar(Target, SizeOf(Target), I);
  Result := UInt64(Target[0]) + UInt64(Target[High(Target)]) shl 8;
end;

function CaseRecordLayout(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Values: array[0..63] of TPlainRecord;
  S: UInt64;
begin
  S := 0;
  for I := 1 to Iterations do
    for J := 0 to High(Values) do
    begin
      Values[J].A := UInt64(I + J);
      Values[J].B := Values[J].A * 3;
      Values[J].C := Values[J].B xor UInt64($A5A5A5A5);
      Values[J].D := Values[J].C + Values[J].A;
      S := S + Values[J].D;
    end;
  Result := S;
end;

function CasePackedLayout(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Values: array[0..63] of TPackedRecord;
  S: UInt64;
begin
  S := 0;
  for I := 1 to Iterations do
    for J := 0 to High(Values) do
    begin
      Values[J].Flag := Byte(I + J);
      Values[J].A := UInt64(I + J) * 3;
      Values[J].B := UInt32(Values[J].A);
      Values[J].C := UInt16(Values[J].B);
      S := S + Values[J].A + Values[J].B + Values[J].C + Values[J].Flag;
    end;
  Result := S;
end;

procedure InitializeData;
var
  I: Integer;
  X: UInt64;
begin
  X := UInt64($D1B54A32D192ED03);
  for I := 0 to High(Input64) do
  begin
    X := X xor (X shr 12);
    X := X xor (X shl 25);
    X := X xor (X shr 27);
    Input64[I] := X * UInt64(2685821657736338717);
    Input32[I] := UInt32(Input64[I]);
  end;
  Input32[0] := 0;
  SetLength(L1Data, L1Count);
  SetLength(L2Data, L2Count);
  SetLength(LlcData, LlcCount);
  SetLength(DramData, DramCount);
  for I := 0 to High(DramData) do
  begin
    X := X * UInt64(6364136223846793005) + 1;
    DramData[I] := X;
    If I < Length(LlcData) then
      LlcData[I] := X;
    If I < Length(L2Data) then
      L2Data[I] := X;
    If I < Length(L1Data) then
      L1Data[I] := X;
  end;
  SetLength(RandomIndex, 4096);
  SetLength(NextIndex, 65536);
  for I := 0 to High(RandomIndex) do
  begin
    X := X * UInt64(2862933555777941757) + UInt64(3037000493);
    RandomIndex[I] := UInt32(X mod UInt64(LlcCount));
  end;
  for I := 0 to High(NextIndex) do
    NextIndex[I] := UInt32((UInt64(I) * 40503 + 17) and High(NextIndex));
  RuntimeUpper := 255;
end;

procedure Run;
var
  Profile: TPulseProfile;
  SelectedCase: string;
  Found: Boolean;
begin
  PulseInitialize('pulse_codegen', Profile, SelectedCase);
  InitializeData;
  VirtualAdder := TPulseVirtualAdder.Create;
  InterfaceAdder := TPulseAdder.Create;
  DirectFunc := PulseDirectAdd;
  Found := False;
  try
    PulseRunCase('pulse_codegen', 'dep-add', 'codegen', 'compiler',
      @CaseDependencyAdd, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_codegen', 'ilp-four-lanes', 'codegen', 'compiler',
      @CaseIndependent4, InnerCount * 4, Profile, SelectedCase, Found);
    PulseRunCase('pulse_codegen', 'call-inline', 'codegen', 'compiler',
      @CaseInlineCall, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_codegen', 'call-unit-direct', 'codegen', 'compiler',
      @CaseDirectCall, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_codegen', 'call-indirect', 'codegen', 'compiler',
      @CaseIndirectCall, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_codegen', 'call-virtual', 'codegen', 'compiler',
      @CaseVirtualCall, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_codegen', 'call-interface', 'codegen+rtl', 'compiler',
      @CaseInterfaceCall, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_codegen', 'call-eight-args', 'codegen', 'compiler',
      @CaseManyArgs, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_codegen', 'int32-mixed', 'codegen', 'compiler',
      @CaseInt32Mixed, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_codegen', 'int8-int16-promotion', 'codegen', 'compiler',
      @CaseNarrowIntegers, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_codegen', 'uint64-mixed', 'codegen', 'compiler',
      @CaseUInt64Mixed, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_codegen', 'uint64-div-constant', 'codegen', 'compiler',
      @CaseDivConst, InnerCount * 3, Profile, SelectedCase, Found);
    PulseRunCase('pulse_codegen', 'uint64-div-runtime', 'codegen', 'compiler',
      @CaseDivRuntime, InnerCount * 2, Profile, SelectedCase, Found);
    PulseRunCase('pulse_codegen', 'double-mixed', 'codegen', 'compiler',
      @CaseDouble, InnerCount * 5, Profile, SelectedCase, Found);
    PulseRunCase('pulse_codegen', 'single-mixed', 'codegen', 'compiler',
      @CaseSingle, InnerCount * 5, Profile, SelectedCase, Found);
    PulseRunCase('pulse_codegen', 'math-transcendentals', 'rtl', 'Math',
      @CaseMathFunctions, 16 * 7, Profile, SelectedCase, Found);
    PulseRunCase('pulse_codegen', 'currency-mul-div', 'codegen+rtl', 'compiler',
      @CaseCurrency, InnerCount * 3, Profile, SelectedCase, Found);
    PulseRunCase('pulse_codegen', 'for-runtime-0-255', 'codegen', 'compiler',
      @CaseForRuntime, 256, Profile, SelectedCase, Found);
    PulseRunCase('pulse_codegen', 'for-runtime-0-0', 'codegen', 'compiler',
      @CaseForZeroToZero, 1, Profile, SelectedCase, Found);
    PulseRunCase('pulse_codegen', 'for-byte-0-255', 'codegen', 'compiler',
      @CaseForByteFull, 256, Profile, SelectedCase, Found);
    PulseRunCase('pulse_codegen', 'branch-predictable', 'codegen', 'compiler',
      @CaseBranchPredictable, 256, Profile, SelectedCase, Found);
    PulseRunCase('pulse_codegen', 'branch-random', 'codegen', 'compiler',
      @CaseBranchRandom, 256, Profile, SelectedCase, Found);
    PulseRunCase('pulse_codegen', 'case-dense', 'codegen', 'compiler',
      @CaseDenseCase, 256, Profile, SelectedCase, Found);
    PulseRunCase('pulse_codegen', 'case-sparse', 'codegen', 'compiler',
      @CaseSparseCase, 256, Profile, SelectedCase, Found);
    PulseRunCase('pulse_codegen', 'enum-set-membership', 'codegen', 'compiler',
      @CaseEnumSet, 256, Profile, SelectedCase, Found);
    PulseRunCase('pulse_codegen', 'try-finally-normal', 'compiler+rtl',
      'compiler', @CaseTryFinally, 16, Profile, SelectedCase, Found);
    PulseRunCase('pulse_codegen', 'cse-expression', 'codegen', 'compiler',
      @CaseCseExpressions, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_codegen', 'dead-store-chain', 'codegen', 'compiler',
      @CaseDeadStores, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_codegen', 'recursion-tree-8', 'codegen', 'compiler',
      @CaseRecursion, 511, Profile, SelectedCase, Found);
    PulseRunCase('pulse_codegen', 'loop-early-exit', 'codegen', 'compiler',
      @CaseEarlyExit, 128, Profile, SelectedCase, Found);
    PulseRunCase('pulse_codegen', 'scan-l1', 'codegen+memory', 'compiler',
      @CaseScanL1, L1Count, Profile, SelectedCase, Found);
    PulseRunCase('pulse_codegen', 'scan-l2', 'codegen+memory', 'compiler',
      @CaseScanL2, L2Count, Profile, SelectedCase, Found);
    PulseRunCase('pulse_codegen', 'scan-llc', 'codegen+memory', 'compiler',
      @CaseScanLlc, LlcCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_codegen', 'scan-dram', 'codegen+memory', 'compiler',
      @CaseScanDram, DramCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_codegen', 'scan-strided', 'codegen+memory', 'compiler',
      @CaseStrided, LlcCount div 8, Profile, SelectedCase, Found);
    PulseRunCase('pulse_codegen', 'scan-random', 'codegen+memory', 'compiler',
      @CaseRandomRead, 4096, Profile, SelectedCase, Found);
    PulseRunCase('pulse_codegen', 'pointer-chase', 'codegen+memory', 'compiler',
      @CasePointerChase, 4096, Profile, SelectedCase, Found);
    PulseRunCase('pulse_codegen', 'pointer-alias-update', 'codegen+memory',
      'compiler', @CaseAliasedUpdate, 255, Profile, SelectedCase, Found);
    PulseRunCase('pulse_codegen', 'move-4k', 'rtl', 'System.Move',
      @CaseMove, 4096, Profile, SelectedCase, Found);
    PulseRunCase('pulse_codegen', 'fillchar-4k', 'rtl', 'System.FillChar',
      @CaseFillChar, 4096, Profile, SelectedCase, Found);
    PulseRunCase('pulse_codegen', 'record-aligned', 'codegen', 'compiler',
      @CaseRecordLayout, 64, Profile, SelectedCase, Found);
    PulseRunCase('pulse_codegen', 'record-packed', 'codegen', 'compiler',
      @CasePackedLayout, 64, Profile, SelectedCase, Found);
    PulseRunCase('pulse_codegen', 'matrix-double-16', 'codegen', 'compiler',
      @CaseMatrix16, 4096, Profile, SelectedCase, Found);
  finally
    InterfaceAdder := nil;
    VirtualAdder.Free;
  end;
  PulseFinish('pulse_codegen', SelectedCase, Found);
end;

begin
  try
    Run;
  except
    on E: Exception do
    begin
      WriteLn(ErrOutput, E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
