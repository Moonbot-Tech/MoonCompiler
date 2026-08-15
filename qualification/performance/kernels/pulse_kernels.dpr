program pulse_kernels;

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
  pulse_harness in '..\common\pulse_harness.pas';

const
  GraphSize = 64;
  SieveSize = 16384;
  MatrixSize = 32;
  FeatureCount = 32;
  SampleCount = 128;
  PixelCount = 4096;
  SparseRows = 512;
  SparsePerRow = 8;
  Base64Table: RawByteString =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

type
  TVector32 = array[0..FeatureCount - 1] of Double;
  TMatrix32 = array[0..MatrixSize - 1, 0..MatrixSize - 1] of Double;

var
  Graph: array[0..GraphSize - 1, 0..GraphSize - 1] of UInt32;
  MatrixInitial: TMatrix32;
  Samples: array[0..SampleCount - 1] of TVector32;
  Weights: array[0..FeatureCount - 1, 0..FeatureCount - 1] of Double;
  Pixels: array[0..PixelCount - 1] of UInt32;
  InputBytes: array[0..4095] of Byte;
  SparseColumns: array[0..SparseRows * SparsePerRow - 1] of UInt16;
  SparseValues: array[0..SparseRows * SparsePerRow - 1] of Double;
  SparseInput, SparseOutput: array[0..SparseRows - 1] of Double;

function CaseDijkstra(Iterations: Integer): UInt64;
var
  RunIndex, I, J, Best: Integer;
  BestDistance, Candidate: UInt32;
  Distance: array[0..GraphSize - 1] of UInt32;
  Visited: array[0..GraphSize - 1] of Boolean;
begin
  Result := 0;
  for RunIndex := 1 to Iterations do
  begin
    for I := 0 to GraphSize - 1 do
    begin
      Distance[I] := High(UInt32);
      Visited[I] := False;
    end;
    Distance[RunIndex and (GraphSize - 1)] := 0;
    for I := 0 to GraphSize - 1 do
    begin
      Best := -1;
      BestDistance := High(UInt32);
      for J := 0 to GraphSize - 1 do
        If (not Visited[J]) and (Distance[J] < BestDistance) then
        begin
          Best := J;
          BestDistance := Distance[J];
        end;
      If Best < 0 then
        Break;
      Visited[Best] := True;
      for J := 0 to GraphSize - 1 do
        If (not Visited[J]) and (Graph[Best, J] <> 0) then
        begin
          Candidate := BestDistance + Graph[Best, J];
          If Candidate < Distance[J] then
            Distance[J] := Candidate;
        end;
    end;
    for I := 0 to GraphSize - 1 do
      Result := Result + Distance[I] * UInt64(I + 1);
  end;
end;

function CasePrimeSieve(Iterations: Integer): UInt64;
var
  RunIndex, I, J: Integer;
  Composite: array[0..SieveSize - 1] of Boolean;
begin
  Result := 0;
  for RunIndex := 1 to Iterations do
  begin
    FillChar(Composite, SizeOf(Composite), 0);
    I := 2;
    while I * I < SieveSize do
    begin
      If not Composite[I] then
      begin
        J := I * I;
        while J < SieveSize do
        begin
          Composite[J] := True;
          Inc(J, I);
        end;
      end;
      Inc(I);
    end;
    for I := 2 to SieveSize - 1 do
      If not Composite[I] then
        Result := Result + UInt64(I + RunIndex);
  end;
end;

function CaseLuDecomposition(Iterations: Integer): UInt64;
var
  RunIndex, I, J, K: Integer;
  Matrix: TMatrix32;
  Factor, DigestValue: Double;
begin
  DigestValue := 0;
  for RunIndex := 1 to Iterations do
  begin
    Matrix := MatrixInitial;
    for K := 0 to MatrixSize - 2 do
      for I := K + 1 to MatrixSize - 1 do
      begin
        Factor := Matrix[I, K] / Matrix[K, K];
        Matrix[I, K] := Factor;
        for J := K + 1 to MatrixSize - 1 do
          Matrix[I, J] := Matrix[I, J] - Factor * Matrix[K, J];
      end;
    DigestValue := DigestValue + Matrix[0, 0] + Matrix[15, 15] +
      Matrix[31, 31];
  end;
  Result := UInt64(Trunc(DigestValue * 1000000.0));
end;

function CaseCorrelation(Iterations: Integer): UInt64;
var
  RunIndex, I, J, K: Integer;
  Mean, StandardDeviation: TVector32;
  Correlation: TMatrix32;
  Sum, DigestValue: Double;
begin
  DigestValue := 0;
  FillChar(Correlation, SizeOf(Correlation), 0);
  for RunIndex := 1 to Iterations do
  begin
    for J := 0 to FeatureCount - 1 do
    begin
      Sum := 0;
      for I := 0 to SampleCount - 1 do
        Sum := Sum + Samples[I, J];
      Mean[J] := Sum / SampleCount;
      Sum := 0;
      for I := 0 to SampleCount - 1 do
        Sum := Sum + Sqr(Samples[I, J] - Mean[J]);
      StandardDeviation[J] := Sqrt(Sum / SampleCount) + 0.000001;
    end;
    for J := 0 to FeatureCount - 1 do
      for K := J to FeatureCount - 1 do
      begin
        Sum := 0;
        for I := 0 to SampleCount - 1 do
          Sum := Sum + ((Samples[I, J] - Mean[J]) / StandardDeviation[J]) *
            ((Samples[I, K] - Mean[K]) / StandardDeviation[K]);
        Correlation[J, K] := Sum / SampleCount;
        Correlation[K, J] := Correlation[J, K];
      end;
    DigestValue := DigestValue + Correlation[0, 0] + Correlation[3, 17] +
      Correlation[FeatureCount - 1, FeatureCount - 1];
  end;
  Result := UInt64(Trunc(DigestValue * 1000000.0));
end;

function CaseNeuralDense(Iterations: Integer): UInt64;
var
  RunIndex, I, J, K: Integer;
  Input, Hidden, OutputValues: TVector32;
  Sum, DigestValue: Double;
begin
  DigestValue := 0;
  for RunIndex := 1 to Iterations do
  begin
    for I := 0 to FeatureCount - 1 do
      Input[I] := Samples[(RunIndex + I) and (SampleCount - 1), I];
    for J := 0 to FeatureCount - 1 do
    begin
      Sum := 0;
      for K := 0 to FeatureCount - 1 do
        Sum := Sum + Input[K] * Weights[K, J];
      If Sum < 0 then
        Sum := 0;
      Hidden[J] := Sum;
    end;
    for J := 0 to FeatureCount - 1 do
    begin
      Sum := 0;
      for K := 0 to FeatureCount - 1 do
        Sum := Sum + Hidden[K] * Weights[J, K];
      OutputValues[J] := Sum;
    end;
    DigestValue := DigestValue + OutputValues[0] + OutputValues[17] +
      OutputValues[FeatureCount - 1];
  end;
  Result := UInt64(Trunc(DigestValue * 1000000.0));
end;

function CasePixelTransform(Iterations: Integer): UInt64;
var
  RunIndex, I: Integer;
  Pixel, R, G, B, Gray: UInt32;
begin
  Result := 0;
  for RunIndex := 1 to Iterations do
    for I := 0 to PixelCount - 1 do
    begin
      Pixel := Pixels[I];
      R := Pixel and $FF;
      G := (Pixel shr 8) and $FF;
      B := (Pixel shr 16) and $FF;
      Gray := (R * 77 + G * 150 + B * 29) shr 8;
      Result := Result + Gray + ((R + UInt32(RunIndex)) and $FF);
    end;
end;

function CaseBase64Encode(Iterations: Integer): UInt64;
var
  RunIndex, I, OutputIndex: Integer;
  Value: UInt32;
  Output: array[0..5463] of AnsiChar;
begin
  Result := 0;
  for RunIndex := 1 to Iterations do
  begin
    I := 0;
    OutputIndex := 0;
    while I + 2 < Length(InputBytes) do
    begin
      Value := UInt32(InputBytes[I]) shl 16 or
        UInt32(InputBytes[I + 1]) shl 8 or InputBytes[I + 2];
      Output[OutputIndex] := AnsiChar(Base64Table[(Value shr 18) + 1]);
      Output[OutputIndex + 1] := AnsiChar(Base64Table[((Value shr 12) and 63) + 1]);
      Output[OutputIndex + 2] := AnsiChar(Base64Table[((Value shr 6) and 63) + 1]);
      Output[OutputIndex + 3] := AnsiChar(Base64Table[(Value and 63) + 1]);
      Inc(I, 3);
      Inc(OutputIndex, 4);
    end;
    Result := Result + Ord(Output[RunIndex mod OutputIndex]) +
      UInt64(Ord(Output[OutputIndex - 1])) shl 8;
  end;
end;

function CaseSparseMatrixVector(Iterations: Integer): UInt64;
var
  RunIndex, Row, Entry, Offset: Integer;
  Sum, DigestValue: Double;
begin
  DigestValue := 0;
  for RunIndex := 1 to Iterations do
  begin
    for Row := 0 to SparseRows - 1 do
    begin
      Sum := 0;
      Offset := Row * SparsePerRow;
      for Entry := 0 to SparsePerRow - 1 do
        Sum := Sum + SparseValues[Offset + Entry] *
          SparseInput[SparseColumns[Offset + Entry]];
      SparseOutput[Row] := Sum;
    end;
    DigestValue := DigestValue + SparseOutput[0] + SparseOutput[255] +
      SparseOutput[SparseRows - 1];
  end;
  Result := UInt64(Trunc(DigestValue * 1000000.0));
end;

function CaseMonteCarlo(Iterations: Integer): UInt64;
var
  RunIndex, I: Integer;
  State, XValue, YValue: UInt32;
  X, Y: Double;
begin
  State := $12345678;
  Result := 0;
  for RunIndex := 1 to Iterations do
    for I := 1 to 4096 do
    begin
      State := State * 1664525 + 1013904223;
      XValue := State shr 8;
      State := State * 1664525 + 1013904223;
      YValue := State shr 8;
      X := XValue * (1.0 / 16777216.0);
      Y := YValue * (1.0 / 16777216.0);
      If X * X + Y * Y <= 1.0 then
        Inc(Result);
    end;
end;

function CaseHuffmanLengths(Iterations: Integer): UInt64;
var
  RunIndex, I, J, First, Second, NodeCount: Integer;
  Frequency: array[0..510] of UInt32;
  Parent: array[0..510] of Integer;
  BestFirst, BestSecond: UInt32;
begin
  Result := 0;
  for RunIndex := 1 to Iterations do
  begin
    FillChar(Parent, SizeOf(Parent), $FF);
    for I := 0 to 255 do
      Frequency[I] := UInt32((I * 73 + RunIndex * 17) mod 1009 + 1);
    NodeCount := 256;
    while NodeCount < 511 do
    begin
      First := -1;
      Second := -1;
      BestFirst := High(UInt32);
      BestSecond := High(UInt32);
      for J := 0 to NodeCount - 1 do
        If Parent[J] < 0 then
          If Frequency[J] < BestFirst then
          begin
            Second := First;
            BestSecond := BestFirst;
            First := J;
            BestFirst := Frequency[J];
          end
          else If Frequency[J] < BestSecond then
          begin
            Second := J;
            BestSecond := Frequency[J];
          end;
      Parent[First] := NodeCount;
      Parent[Second] := NodeCount;
      Frequency[NodeCount] := BestFirst + BestSecond;
      Parent[NodeCount] := -1;
      Inc(NodeCount);
    end;
    for I := 0 to 255 do
    begin
      J := I;
      while Parent[J] >= 0 do
      begin
        Inc(Result, UInt64(Frequency[I]));
        J := Parent[J];
      end;
    end;
  end;
end;

procedure InitializeData;
var
  I, J: Integer;
begin
  for I := 0 to GraphSize - 1 do
    for J := 0 to GraphSize - 1 do
      If I = J then
        Graph[I, J] := 0
      else If ((I * 17 + J * 31) and 7) < 3 then
        Graph[I, J] := UInt32(((I + 1) * (J + 3)) mod 97 + 1)
      else
        Graph[I, J] := 0;
  for I := 0 to MatrixSize - 1 do
    for J := 0 to MatrixSize - 1 do
      If I = J then
        MatrixInitial[I, J] := MatrixSize + 1 + I * 0.125
      else
        MatrixInitial[I, J] := ((I * 17 + J * 13) and 31) * 0.00390625;
  for I := 0 to SampleCount - 1 do
    for J := 0 to FeatureCount - 1 do
      Samples[I, J] := ((I * 17 + J * 29 + 3) and 1023) * 0.0009765625;
  for I := 0 to FeatureCount - 1 do
    for J := 0 to FeatureCount - 1 do
      Weights[I, J] := (((I + 1) * (J + 3)) and 255) * 0.0001220703125;
  for I := 0 to PixelCount - 1 do
    Pixels[I] := UInt32(I) * UInt32(747796405) + UInt32(2891336453);
  for I := 0 to High(InputBytes) do
    InputBytes[I] := Byte(I * 37 + 11);
  for I := 0 to SparseRows - 1 do
  begin
    SparseInput[I] := (I and 255) * 0.00390625;
    for J := 0 to SparsePerRow - 1 do
    begin
      SparseColumns[I * SparsePerRow + J] := UInt16((I * 17 + J * 53) and
        (SparseRows - 1));
      SparseValues[I * SparsePerRow + J] := (J + 1) * 0.03125;
    end;
  end;
end;

var
  Profile: TPulseProfile;
  SelectedCase: string;
  Found: Boolean;
begin
  InitializeData;
  PulseInitialize('pulse_kernels', Profile, SelectedCase);
  Found := False;
  PulseRunCase('pulse_kernels', 'dijkstra-64', 'application', 'Pascal',
    @CaseDijkstra, GraphSize * GraphSize, Profile, SelectedCase, Found);
  PulseRunCase('pulse_kernels', 'prime-sieve-16384', 'application', 'Pascal',
    @CasePrimeSieve, SieveSize, Profile, SelectedCase, Found);
  PulseRunCase('pulse_kernels', 'lu-decomposition-32', 'application', 'Pascal',
    @CaseLuDecomposition, MatrixSize * MatrixSize * MatrixSize div 3,
    Profile, SelectedCase, Found);
  PulseRunCase('pulse_kernels', 'correlation-128x32', 'application', 'Pascal',
    @CaseCorrelation, SampleCount * FeatureCount * FeatureCount div 2,
    Profile, SelectedCase, Found);
  PulseRunCase('pulse_kernels', 'neural-dense-32x32', 'application', 'Pascal',
    @CaseNeuralDense, FeatureCount * FeatureCount * 2, Profile,
    SelectedCase, Found);
  PulseRunCase('pulse_kernels', 'pixel-transform-4096', 'application', 'Pascal',
    @CasePixelTransform, PixelCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_kernels', 'base64-encode-4096', 'application+text',
    'Pascal', @CaseBase64Encode, 4096, Profile, SelectedCase, Found);
  PulseRunCase('pulse_kernels', 'sparse-matvec-512x8', 'application', 'Pascal',
    @CaseSparseMatrixVector, SparseRows * SparsePerRow, Profile,
    SelectedCase, Found);
  PulseRunCase('pulse_kernels', 'monte-carlo-4096', 'application', 'Pascal',
    @CaseMonteCarlo, 4096, Profile, SelectedCase, Found);
  PulseRunCase('pulse_kernels', 'huffman-lengths-256', 'application', 'Pascal',
    @CaseHuffmanLengths, 256 * 256, Profile, SelectedCase, Found);
  PulseFinish('pulse_kernels', SelectedCase, Found);
end.
