program pulse_fft_codegen;

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
  FftSize = 1024;
  Butterflies = (FftSize div 2) * 10;

type
  TComplex = record
    Re, Im: Double;
  end;
  PComplex = ^TComplex;

var
  Data: array[0..FftSize - 1] of TComplex;
  TwiddleRe: array[0..FftSize * 2 - 1] of Double;
  TwiddleIm: array[0..FftSize * 2 - 1] of Double;

procedure FillData(Seed: Integer);
var
  I: Integer;
begin
  for I := 0 to High(Data) do
  begin
    Data[I].Re := ((I * 17 + Seed * 3) and 1023) * 0.0009765625;
    Data[I].Im := ((I * 29 + Seed * 5) and 1023) * 0.00048828125;
  end;
end;

procedure BitReverse;
var
  I, J, K: Integer;
  Temp: TComplex;
begin
  J := 0;
  for I := 1 to High(Data) do
  begin
    K := Length(Data) shr 1;
    while (J and K) <> 0 do
    begin
      J := J xor K;
      K := K shr 1;
    end;
    J := J xor K;
    If I < J then
    begin
      Temp := Data[I];
      Data[I] := Data[J];
      Data[J] := Temp;
    end;
  end;
end;

procedure FftIndexedTrig;
var
  I, J, K, M, Half: Integer;
  Angle, WRe, WIm, URe, UIm, TRe, TIm: Double;
begin
  BitReverse;
  M := 2;
  while M <= Length(Data) do
  begin
    Half := M shr 1;
    for K := 0 to Half - 1 do
    begin
      Angle := -2.0 * Pi * K / M;
      WRe := Cos(Angle);
      WIm := Sin(Angle);
      I := K;
      while I < Length(Data) do
      begin
        J := I + Half;
        TRe := WRe * Data[J].Re - WIm * Data[J].Im;
        TIm := WRe * Data[J].Im + WIm * Data[J].Re;
        URe := Data[I].Re;
        UIm := Data[I].Im;
        Data[I].Re := URe + TRe;
        Data[I].Im := UIm + TIm;
        Data[J].Re := URe - TRe;
        Data[J].Im := UIm - TIm;
        Inc(I, M);
      end;
    end;
    M := M shl 1;
  end;
end;

procedure FftIndexedTable;
var
  I, J, K, M, Half: Integer;
  WRe, WIm, URe, UIm, TRe, TIm: Double;
begin
  BitReverse;
  M := 2;
  while M <= Length(Data) do
  begin
    Half := M shr 1;
    for K := 0 to Half - 1 do
    begin
      WRe := TwiddleRe[M + K];
      WIm := TwiddleIm[M + K];
      I := K;
      while I < Length(Data) do
      begin
        J := I + Half;
        TRe := WRe * Data[J].Re - WIm * Data[J].Im;
        TIm := WRe * Data[J].Im + WIm * Data[J].Re;
        URe := Data[I].Re;
        UIm := Data[I].Im;
        Data[I].Re := URe + TRe;
        Data[I].Im := UIm + TIm;
        Data[J].Re := URe - TRe;
        Data[J].Im := UIm - TIm;
        Inc(I, M);
      end;
    end;
    M := M shl 1;
  end;
end;

procedure FftPointerTable;
var
  K, M, Half: Integer;
  WRe, WIm, URe, UIm, TRe, TIm: Double;
  PI, PJ, Limit: PComplex;
begin
  BitReverse;
  Limit := PComplex(PByte(@Data[0]) + SizeOf(Data));
  M := 2;
  while M <= Length(Data) do
  begin
    Half := M shr 1;
    for K := 0 to Half - 1 do
    begin
      WRe := TwiddleRe[M + K];
      WIm := TwiddleIm[M + K];
      PI := @Data[K];
      PJ := @Data[K + Half];
      while NativeUInt(PI) < NativeUInt(Limit) do
      begin
        TRe := WRe * PJ^.Re - WIm * PJ^.Im;
        TIm := WRe * PJ^.Im + WIm * PJ^.Re;
        URe := PI^.Re;
        UIm := PI^.Im;
        PI^.Re := URe + TRe;
        PI^.Im := UIm + TIm;
        PJ^.Re := URe - TRe;
        PJ^.Im := UIm - TIm;
        Inc(PI, M);
        Inc(PJ, M);
      end;
    end;
    M := M shl 1;
  end;
end;

function DigestData: UInt64;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to 15 do
    Result := Result xor (UInt64(Trunc(Abs(Data[I * 61].Re) * 1000.0)) shl
      (I and 31));
end;

function CaseFill(Iterations: Integer): UInt64;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    FillData(I);
    Result := Result xor DigestData;
  end;
end;

function CaseAngleOnly(Iterations: Integer): UInt64;
var
  Iteration, K, M, Half: Integer;
  Angle, Sum: Double;
begin
  Sum := 0;
  for Iteration := 1 to Iterations do
  begin
    M := 2;
    while M <= FftSize do
    begin
      Half := M shr 1;
      for K := 0 to Half - 1 do
      begin
        Angle := -2.0 * Pi * K / M;
        Sum := Sum + Angle;
      end;
      M := M shl 1;
    end;
  end;
  Result := UInt64(Trunc(Abs(Sum) * 1000.0));
end;

function CaseTwiddleOnly(Iterations: Integer): UInt64;
var
  Iteration, K, M, Half: Integer;
  Angle, Sum: Double;
begin
  Sum := 0;
  for Iteration := 1 to Iterations do
  begin
    M := 2;
    while M <= FftSize do
    begin
      Half := M shr 1;
      for K := 0 to Half - 1 do
      begin
        Angle := -2.0 * Pi * K / M;
        Sum := Sum + Cos(Angle) + Sin(Angle);
      end;
      M := M shl 1;
    end;
  end;
  Result := UInt64(Trunc(Abs(Sum) * 1000.0));
end;

function CaseTwiddlePositive(Iterations: Integer): UInt64;
var
  Iteration, K, M, Half: Integer;
  Angle, Sum: Double;
begin
  Sum := 0;
  for Iteration := 1 to Iterations do
  begin
    M := 2;
    while M <= FftSize do
    begin
      Half := M shr 1;
      for K := 0 to Half - 1 do
      begin
        Angle := 2.0 * Pi * K / M;
        Sum := Sum + Cos(Angle) + Sin(Angle);
      end;
      M := M shl 1;
    end;
  end;
  Result := UInt64(Trunc(Abs(Sum) * 1000.0));
end;

function CaseIndexedTrig(Iterations: Integer): UInt64;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    FillData(I);
    FftIndexedTrig;
    Result := Result xor DigestData;
  end;
end;

function CaseIndexedTable(Iterations: Integer): UInt64;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    FillData(I);
    FftIndexedTable;
    Result := Result xor DigestData;
  end;
end;

function CasePointerTable(Iterations: Integer): UInt64;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    FillData(I);
    FftPointerTable;
    Result := Result xor DigestData;
  end;
end;

procedure InitializeTwiddles;
var
  K, M, Half: Integer;
  Angle: Double;
begin
  M := 2;
  while M <= FftSize do
  begin
    Half := M shr 1;
    for K := 0 to Half - 1 do
    begin
      Angle := -2.0 * Pi * K / M;
      TwiddleRe[M + K] := Cos(Angle);
      TwiddleIm[M + K] := Sin(Angle);
    end;
    M := M shl 1;
  end;
end;

procedure Run;
var
  Profile: TPulseProfile;
  SelectedCase: string;
  Found: Boolean;
begin
  InitializeTwiddles;
  PulseInitialize('pulse_fft_codegen', Profile, SelectedCase);
  Found := False;
  PulseRunCase('pulse_fft_codegen', 'fill', 'memory', '1024 complex records',
    @CaseFill, FftSize, Profile, SelectedCase, Found);
  PulseRunCase('pulse_fft_codegen', 'angle-only', 'codegen',
    'FFT twiddle angle arithmetic', @CaseAngleOnly, FftSize - 1, Profile,
    SelectedCase, Found);
  PulseRunCase('pulse_fft_codegen', 'twiddle-only', 'codegen+math',
    'negative FFT twiddle Sin/Cos pair', @CaseTwiddleOnly, FftSize - 1, Profile,
    SelectedCase, Found);
  PulseRunCase('pulse_fft_codegen', 'twiddle-positive', 'codegen+math',
    'positive FFT twiddle Sin/Cos pair', @CaseTwiddlePositive, FftSize - 1, Profile,
    SelectedCase, Found);
  PulseRunCase('pulse_fft_codegen', 'indexed-trig', 'codegen+math',
    'indexed FFT with Sin/Cos', @CaseIndexedTrig, Butterflies, Profile,
    SelectedCase, Found);
  PulseRunCase('pulse_fft_codegen', 'indexed-table', 'codegen',
    'indexed FFT with prepared twiddles', @CaseIndexedTable, Butterflies,
    Profile, SelectedCase, Found);
  PulseRunCase('pulse_fft_codegen', 'pointer-table', 'codegen',
    'pointer-carried FFT with prepared twiddles', @CasePointerTable,
    Butterflies, Profile, SelectedCase, Found);
  PulseFinish('pulse_fft_codegen', SelectedCase, Found);
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
