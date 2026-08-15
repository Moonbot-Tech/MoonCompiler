program pulse_loops;

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
  perf_clock in '..\common\perf_clock.pas',
  pulse_process_metrics in '..\common\pulse_process_metrics.pas',
  pulse_harness in '..\common\pulse_harness.pas';

const
  VectorCount = 8192;
  MatrixSide = 64;
  InnerCount = 256;

var
  IntA, IntB, IntC: array[0..VectorCount - 1] of Int32;
  DoubleA, DoubleB, DoubleC: array[0..VectorCount - 1] of Double;
  RuntimeCount: Integer;

function Mix(Value: UInt64): UInt64; inline;
begin
  Result := (Value xor (Value shr 27)) * UInt64($3C79AC492BA7B653);
end;

function LoopCall(Value: UInt64): UInt64;
begin
  Result := Mix(Value + UInt64($9E3779B185EBCA87));
end;

function CaseForUp(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      Result := Result + UInt32(IntA[(I + J) and (VectorCount - 1)]);
end;

function CaseForDown(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := InnerCount - 1 downto 0 do
      Result := Result + UInt32(IntA[(I + J) and (VectorCount - 1)]);
end;

function CaseWhileLoop(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    J := 0;
    while J < RuntimeCount do
    begin
      Result := Result + UInt32(IntA[(I + J) and (VectorCount - 1)]);
      Inc(J);
    end;
  end;
end;

function CaseRepeatLoop(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    J := 0;
    repeat
      Result := Result + UInt32(IntA[(I + J) and (VectorCount - 1)]);
      Inc(J);
    until J >= RuntimeCount;
  end;
end;

function CaseNestedRowMajor(Iterations: Integer): UInt64;
var
  I, Row, Col: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for Row := 0 to MatrixSide - 1 do
      for Col := 0 to MatrixSide - 1 do
        Result := Result + UInt32(IntA[Row * MatrixSide + Col]);
end;

function CaseNestedColumnMajor(Iterations: Integer): UInt64;
var
  I, Row, Col: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for Col := 0 to MatrixSide - 1 do
      for Row := 0 to MatrixSide - 1 do
        Result := Result + UInt32(IntA[Row * MatrixSide + Col]);
end;

function CaseInvariantExpression(Iterations: Integer): UInt64;
var
  I, J, Scale, Offset: Integer;
begin
  Result := 0;
  Scale := RuntimeCount * 17 + 3;
  Offset := RuntimeCount * RuntimeCount + 11;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      Result := Result + UInt32(IntA[(I + J) and (VectorCount - 1)] * Scale +
        Offset);
end;

function CaseStrengthMultiplyIndex(Iterations: Integer): UInt64;
var
  I, J, Index: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      Index := (J * 13 + I) and (VectorCount - 1);
      Result := Result + UInt32(IntA[Index]);
    end;
end;

function CaseReductionSum(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Sum: Double;
begin
  Sum := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      Sum := Sum + DoubleA[(I + J) and (VectorCount - 1)];
  Result := UInt64(Trunc(Sum * 1024.0));
end;

function CaseReductionFourLanes(Iterations: Integer): UInt64;
var
  I, J: Integer;
  A, B, C, D: Double;
begin
  A := 0;
  B := 0;
  C := 0;
  D := 0;
  for I := 1 to Iterations do
  begin
    J := 0;
    while J < InnerCount do
    begin
      A := A + DoubleA[(I + J) and (VectorCount - 1)];
      B := B + DoubleA[(I + J + 1) and (VectorCount - 1)];
      C := C + DoubleA[(I + J + 2) and (VectorCount - 1)];
      D := D + DoubleA[(I + J + 3) and (VectorCount - 1)];
      Inc(J, 4);
    end;
  end;
  Result := UInt64(Trunc((A + B + C + D) * 1024.0));
end;

function CaseVectorAdd(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  for I := 1 to Iterations do
    for J := 0 to VectorCount - 1 do
      DoubleC[J] := DoubleA[J] + DoubleB[J];
  Result := UInt64(Trunc(DoubleC[(Iterations * 17) and
    (VectorCount - 1)] * 1000000.0));
end;

function CaseVectorDot(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Sum: Double;
begin
  Sum := 0;
  for I := 1 to Iterations do
    for J := 0 to VectorCount - 1 do
      Sum := Sum + DoubleA[J] * DoubleB[J];
  Result := UInt64(Trunc(Sum * 4096.0));
end;

procedure AliasUpdate(var Destination: Int32; const Source: Int32); inline;
begin
  Destination := Destination + Source * 3 + 1;
end;

function CaseAliasedUpdate(Iterations: Integer): UInt64;
var
  I, J, Index: Integer;
begin
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      Index := (I + J) and (VectorCount - 1);
      IntC[Index] := IntA[Index];
      AliasUpdate(IntC[Index], IntC[Index]);
    end;
  Result := UInt32(IntC[(Iterations + 7) and (VectorCount - 1)]);
end;

function CaseNonAliasedUpdate(Iterations: Integer): UInt64;
var
  I, J, Index: Integer;
begin
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      Index := (I + J) and (VectorCount - 1);
      IntC[Index] := 0;
      AliasUpdate(IntC[Index], IntB[Index]);
    end;
  Result := UInt32(IntC[(Iterations + 7) and (VectorCount - 1)]);
end;

function CaseBreakContinue(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      If (J and 7) = 0 then
        Continue;
      If J = RuntimeCount - 1 then
        Break;
      Result := Result + UInt32(IntA[(I + J) and (VectorCount - 1)]);
    end;
end;

function CaseLoopWithCall(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 1;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      Result := LoopCall(Result + UInt64(J));
end;

function CaseLoopTryFinally(Iterations: Integer): UInt64;
var
  I, J: Integer;
  X: UInt64;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      X := UInt64(I + J);
      try
        Result := Result + Mix(X);
      finally
        Result := Result xor (X and 1);
      end;
    end;
end;

function CasePrefixDependency(Iterations: Integer): UInt64;
var
  I, J: Integer;
  X: Int32;
begin
  X := 1;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      X := X + IntA[(I + J) and (VectorCount - 1)];
      IntC[J] := X;
    end;
  Result := UInt32(X) xor UInt32(IntC[InnerCount - 1]);
end;

function CaseHistogramRandom(Iterations: Integer): UInt64;
var
  I, J, Index: Integer;
  Buckets: array[0..255] of UInt32;
begin
  FillChar(Buckets, SizeOf(Buckets), 0);
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      Index := IntA[(I * 17 + J) and (VectorCount - 1)] and 255;
      Inc(Buckets[Index]);
    end;
  Result := 0;
  for J := 0 to High(Buckets) do
    Result := Result + UInt64(Buckets[J]) * UInt64(J + 1);
end;

function CaseManualCopy(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  for I := 1 to Iterations do
    for J := 0 to VectorCount - 1 do
      IntC[J] := IntA[J];
  Result := UInt32(IntC[(Iterations * 31) and (VectorCount - 1)]);
end;

procedure InitializeData;
var
  I: Integer;
begin
  for I := 0 to VectorCount - 1 do
  begin
    IntA[I] := Int32(UInt32(I * 747796405 + 2891336453));
    IntB[I] := Int32(UInt32(I * 277803737 + 1013904223));
    IntC[I] := I xor $55AA;
    DoubleA[I] := ((I * 17) and 1023) * 0.0009765625;
    DoubleB[I] := ((I * 29 + 7) and 1023) * 0.00048828125;
    DoubleC[I] := 0;
  end;
  RuntimeCount := InnerCount;
end;

var
  Profile: TPulseProfile;
  SelectedCase: string;
  Found: Boolean;
begin
  InitializeData;
  PulseInitialize('pulse_loops', Profile, SelectedCase);
  Found := False;
  PulseRunCase('pulse_loops', 'for-up', 'codegen', 'compiler', @CaseForUp,
    InnerCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_loops', 'for-down', 'codegen', 'compiler', @CaseForDown,
    InnerCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_loops', 'while-runtime', 'codegen', 'compiler',
    @CaseWhileLoop, InnerCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_loops', 'repeat-runtime', 'codegen', 'compiler',
    @CaseRepeatLoop, InnerCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_loops', 'nested-row-major', 'codegen+memory', 'compiler',
    @CaseNestedRowMajor, MatrixSide * MatrixSide, Profile, SelectedCase, Found);
  PulseRunCase('pulse_loops', 'nested-column-major', 'codegen+memory', 'compiler',
    @CaseNestedColumnMajor, MatrixSide * MatrixSide, Profile, SelectedCase, Found);
  PulseRunCase('pulse_loops', 'invariant-expression', 'codegen', 'compiler',
    @CaseInvariantExpression, InnerCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_loops', 'strength-multiply-index', 'codegen', 'compiler',
    @CaseStrengthMultiplyIndex, InnerCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_loops', 'reduction-sum', 'codegen', 'compiler',
    @CaseReductionSum, InnerCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_loops', 'reduction-four-lanes', 'codegen', 'compiler',
    @CaseReductionFourLanes, InnerCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_loops', 'vector-add-8192', 'codegen+memory', 'compiler',
    @CaseVectorAdd, VectorCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_loops', 'vector-dot-8192', 'codegen+memory', 'compiler',
    @CaseVectorDot, VectorCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_loops', 'aliased-update', 'codegen', 'compiler',
    @CaseAliasedUpdate, InnerCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_loops', 'nonaliased-update', 'codegen', 'compiler',
    @CaseNonAliasedUpdate, InnerCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_loops', 'break-continue', 'codegen', 'compiler',
    @CaseBreakContinue, InnerCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_loops', 'loop-with-call', 'codegen', 'compiler',
    @CaseLoopWithCall, InnerCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_loops', 'loop-try-finally', 'compiler+rtl', 'compiler',
    @CaseLoopTryFinally, InnerCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_loops', 'prefix-dependency', 'codegen+memory', 'compiler',
    @CasePrefixDependency, InnerCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_loops', 'histogram-random', 'codegen+memory', 'compiler',
    @CaseHistogramRandom, InnerCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_loops', 'manual-copy-8192', 'codegen+memory', 'compiler',
    @CaseManualCopy, VectorCount, Profile, SelectedCase, Found);
  PulseFinish('pulse_loops', SelectedCase, Found);
end.
