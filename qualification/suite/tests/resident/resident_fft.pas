unit resident_fft;

{ Быстрое преобразование Фурье — плотный расчёт с плавающей точкой и богатым
  набором законов, которые обязаны выполняться при любом верном ответе.

  Здесь нет ни одного эталонного массива чисел, и он не нужен: у преобразования
  есть свойства, которые проверяют его сами.

    * **обратимость**: прямое и обратное преобразование возвращают исходное;
    * **равенство Парсеваля**: энергия сигнала равна энергии спектра, делённой
      на длину. Это закон сохранения, и он ловит ошибку в любом месте бабочки;
    * **линейность**: преобразование суммы равно сумме преобразований;
    * **известный вход**: у чистой гармоники частоты k вся энергия обязана
      стоять в двух отсчётах спектра, k и N-k, а прочие обязаны быть пусты;
    * **сдвиг**: сдвиг сигнала по времени меняет фазу, но не модуль спектра;
    * **свёртка**: произведение спектров равно спектру свёртки — и его можно
      сверить с прямой свёрткой, посчитанной по определению.

  Пороги выведены из длины: на длине N преобразование делает порядка N log N
  зависимых действий, и накопление не превышает этого числа машинных эпсилонов
  с запасом. Побитового совпадения ни от чего не требуется — перестановка
  сложений законна. }

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch INLINEVARS}
{$endif}
{$Q-}{$R-}

interface

uses
  SysUtils, Math, Classes, Generics.Collections, resident_core;

implementation

const
  MachineEps = 2.220446049250313e-16;
  Guard = 1000.0;

type
  TComplexArray = record
    Re, Im: System.TArray<Double>;
    procedure Init(N: Integer);
    function Len: Integer;
  end;

  TResidentFftPocket = class(TResidentPocket)
  private
    FEnergy: Double;
    FRounds: Int64;
  end;

procedure TComplexArray.Init(N: Integer);
begin
  SetLength(Re, N);
  SetLength(Im, N);
end;

function TComplexArray.Len: Integer;
begin
  Result := Length(Re);
end;

function Tolerance(Steps: Integer): Double;
begin
  Result := MachineEps * Steps * Guard;
end;

{ Преобразование на месте, основание два. Перестановка по обратному порядку
  битов, затем бабочки удваивающейся длины. }
procedure Transform(var Data: TComplexArray; Invert: Boolean);
var
  N, I, J, K, Len, Step: Integer;
  Angle, WRe, WIm, CurRe, CurIm, URe, UIm, VRe, VIm, Tmp: Double;
begin
  N := Data.Len;

  J := 0;
  for I := 1 to N - 1 do
  begin
    K := N shr 1;
    while (J and K) <> 0 do
    begin
      J := J xor K;
      K := K shr 1;
    end;
    J := J or K;
    if I < J then
    begin
      Tmp := Data.Re[I];
      Data.Re[I] := Data.Re[J];
      Data.Re[J] := Tmp;
      Tmp := Data.Im[I];
      Data.Im[I] := Data.Im[J];
      Data.Im[J] := Tmp;
    end;
  end;

  Len := 2;
  while Len <= N do
  begin
    Angle := 2 * Pi / Len;
    if not Invert then
      Angle := -Angle;
    WRe := Cos(Angle);
    WIm := Sin(Angle);
    I := 0;
    while I < N do
    begin
      CurRe := 1;
      CurIm := 0;
      for Step := 0 to Len div 2 - 1 do
      begin
        URe := Data.Re[I + Step];
        UIm := Data.Im[I + Step];
        VRe := Data.Re[I + Step + Len div 2] * CurRe -
               Data.Im[I + Step + Len div 2] * CurIm;
        VIm := Data.Re[I + Step + Len div 2] * CurIm +
               Data.Im[I + Step + Len div 2] * CurRe;
        Data.Re[I + Step] := URe + VRe;
        Data.Im[I + Step] := UIm + VIm;
        Data.Re[I + Step + Len div 2] := URe - VRe;
        Data.Im[I + Step + Len div 2] := UIm - VIm;
        Tmp := CurRe * WRe - CurIm * WIm;
        CurIm := CurRe * WIm + CurIm * WRe;
        CurRe := Tmp;
      end;
      Inc(I, Len);
    end;
    Len := Len shl 1;
  end;

  if Invert then
    for I := 0 to N - 1 do
    begin
      Data.Re[I] := Data.Re[I] / N;
      Data.Im[I] := Data.Im[I] / N;
    end;
end;

function Energy(const Data: TComplexArray): Double;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to Data.Len - 1 do
    Result := Result + Data.Re[I] * Data.Re[I] + Data.Im[I] * Data.Im[I];
end;

function Magnitude(const Data: TComplexArray; K: Integer): Double;
begin
  Result := Sqrt(Data.Re[K] * Data.Re[K] + Data.Im[K] * Data.Im[K]);
end;

procedure FillNoise(var Data: TComplexArray; var State: UInt64);
var
  I: Integer;
begin
  for I := 0 to Data.Len - 1 do
  begin
    Data.Re[I] := (Double(Int64(ResidentNext(State) and $FFFF)) - 32768.0) / 32768.0;
    Data.Im[I] := 0;
  end;
end;

function LogTwo(N: Integer): Integer;
begin
  Result := 0;
  while N > 1 do
  begin
    N := N shr 1;
    Inc(Result);
  end;
end;

{ ------------------------------------------------------------- стадии ----- }

{ Обратимость и сохранение энергии: два независимых закона на одном прогоне. }
procedure StageRoundTrip(Carrier: TResidentCarrier);
var
  Data, Keep: TComplexArray;
  N, I, Steps: Integer;
  State: UInt64;
  Worst, TimeEnergy, SpecEnergy, Limit: Double;
begin
  N := 256 shl (Carrier.Lap mod 4);
  Data.Init(N);
  Keep.Init(N);
  State := ResidentMix(Carrier.Seed,
                       UInt64(Cardinal(Carrier.Serial * 19 + Carrier.Lap)));
  FillNoise(Data, State);
  for I := 0 to N - 1 do
  begin
    Keep.Re[I] := Data.Re[I];
    Keep.Im[I] := Data.Im[I];
  end;

  TimeEnergy := Energy(Data);
  Transform(Data, False);
  SpecEnergy := Energy(Data);

  { Равенство Парсеваля: энергия спектра, делённая на длину, равна энергии
    сигнала. Закон сохранения, а не сравнение с образцом. }
  Steps := N * LogTwo(N);
  Limit := Tolerance(Steps) * (TimeEnergy + 1.0);
  Carrier.Claim(Abs(SpecEnergy / N - TimeEnergy) < Limit + 1e-9,
                'fft: Parseval identity violated');
  Carrier.Feed(UInt64(Cardinal(N)));
  Carrier.Feed(UInt64(Round(TimeEnergy * 1e6)));

  { Обратное преобразование обязано вернуть исходное. }
  Transform(Data, True);
  Worst := 0;
  for I := 0 to N - 1 do
  begin
    if Abs(Data.Re[I] - Keep.Re[I]) > Worst then
      Worst := Abs(Data.Re[I] - Keep.Re[I]);
    if Abs(Data.Im[I] - Keep.Im[I]) > Worst then
      Worst := Abs(Data.Im[I] - Keep.Im[I]);
  end;
  Carrier.Claim(Worst < Tolerance(Steps) + 1e-9,
                'fft: forward then inverse did not restore the signal');
  Carrier.Feed(UInt64(Round(Worst * 1e15)));
end;

{ Известный вход: чистая гармоника обязана дать спектр из двух отсчётов. }
procedure StageTone(Carrier: TResidentCarrier);
var
  Data: TComplexArray;
  N, K, I: Integer;
  Peak, Other, Limit: Double;
begin
  N := 256 shl (Carrier.Lap mod 3);
  K := 3 + (Carrier.Serial mod 7) + (Carrier.Lap mod 5);
  if K >= N div 2 then
    K := N div 4;

  Data.Init(N);
  for I := 0 to N - 1 do
  begin
    Data.Re[I] := Cos(2 * Pi * K * I / N);
    Data.Im[I] := 0;
  end;

  Transform(Data, False);

  { Вся энергия — в отсчётах K и N-K, по половине длины в каждом. }
  Peak := Magnitude(Data, K);
  Limit := Tolerance(N * LogTwo(N)) * N + 1e-6;
  Carrier.Claim(Abs(Peak - N / 2) < Limit + N * 1e-9,
                'fft: tone did not land on its own bin');
  Carrier.Claim(Abs(Magnitude(Data, N - K) - N / 2) < Limit + N * 1e-9,
                'fft: mirror bin of the tone is wrong');

  { Все прочие отсчёты обязаны быть пусты. }
  Other := 0;
  for I := 0 to N - 1 do
    if (I <> K) and (I <> N - K) then
      if Magnitude(Data, I) > Other then
        Other := Magnitude(Data, I);
  Carrier.Claim(Other < Limit + N * 1e-9, 'fft: energy leaked into other bins');

  Carrier.Feed(UInt64(Cardinal(N)));
  Carrier.Feed(UInt64(Cardinal(K)));
  Carrier.Feed(UInt64(Round(Peak)));
end;

{ Линейность: преобразование суммы равно сумме преобразований. }
procedure StageLinearity(Carrier: TResidentCarrier);
var
  A, B, Both: TComplexArray;
  N, I: Integer;
  State: UInt64;
  Worst, Limit: Double;
begin
  N := 128 shl (Carrier.Lap mod 3);
  A.Init(N);
  B.Init(N);
  Both.Init(N);
  State := ResidentMix(Carrier.Seed, UInt64(Cardinal(Carrier.Lap * 23 + 5)));
  FillNoise(A, State);
  FillNoise(B, State);
  for I := 0 to N - 1 do
  begin
    Both.Re[I] := A.Re[I] + B.Re[I];
    Both.Im[I] := A.Im[I] + B.Im[I];
  end;

  Transform(A, False);
  Transform(B, False);
  Transform(Both, False);

  Worst := 0;
  for I := 0 to N - 1 do
  begin
    if Abs(Both.Re[I] - (A.Re[I] + B.Re[I])) > Worst then
      Worst := Abs(Both.Re[I] - (A.Re[I] + B.Re[I]));
    if Abs(Both.Im[I] - (A.Im[I] + B.Im[I])) > Worst then
      Worst := Abs(Both.Im[I] - (A.Im[I] + B.Im[I]));
  end;
  Limit := Tolerance(N * LogTwo(N)) * N;
  Carrier.Claim(Worst < Limit + 1e-9, 'fft: transform is not linear');
  Carrier.Feed(UInt64(Cardinal(N)));
  Carrier.Feed(UInt64(Round(Worst * 1e15)));
end;

{ Сдвиг по времени меняет фазу, но не модуль спектра. }
procedure StageShift(Carrier: TResidentCarrier);
var
  Data, Moved: TComplexArray;
  N, I, By: Integer;
  State: UInt64;
  Worst, Limit: Double;
begin
  N := 128 shl (Carrier.Lap mod 3);
  By := 1 + (Carrier.Serial mod 17);
  Data.Init(N);
  Moved.Init(N);
  State := ResidentMix(Carrier.Seed, UInt64(Cardinal(Carrier.Serial * 3 + 11)));
  FillNoise(Data, State);
  for I := 0 to N - 1 do
  begin
    Moved.Re[(I + By) mod N] := Data.Re[I];
    Moved.Im[(I + By) mod N] := Data.Im[I];
  end;

  Transform(Data, False);
  Transform(Moved, False);

  Worst := 0;
  for I := 0 to N - 1 do
    if Abs(Magnitude(Data, I) - Magnitude(Moved, I)) > Worst then
      Worst := Abs(Magnitude(Data, I) - Magnitude(Moved, I));
  Limit := Tolerance(N * LogTwo(N)) * N;
  Carrier.Claim(Worst < Limit + 1e-9,
                'fft: shifting the signal changed the magnitude spectrum');
  Carrier.Feed(UInt64(Cardinal(N)));
  Carrier.Feed(UInt64(Cardinal(By)));
  Carrier.Feed(UInt64(Round(Worst * 1e12)));
end;

{ Свёртка через спектр против свёртки по определению. Это самая тяжёлая
  проверка семейства: прямая свёртка стоит квадрат длины. }
procedure StageConvolution(Carrier: TResidentCarrier);
var
  A, B, Fa, Fb: TComplexArray;
  Slow: System.TArray<Double>;
  Half, N, I, J: Integer;
  State: UInt64;
  Worst, Limit, Tmp: Double;
begin
  Half := 64 shl (Carrier.Lap mod 3);
  N := Half * 2;
  A.Init(N);
  B.Init(N);
  Fa.Init(N);
  Fb.Init(N);
  State := ResidentMix(Carrier.Seed, UInt64(Cardinal(Carrier.Lap * 29 + 3)));
  for I := 0 to Half - 1 do
  begin
    A.Re[I] := Double(ResidentNext(State) and $FF) / 255.0;
    B.Re[I] := Double(ResidentNext(State) and $FF) / 255.0;
  end;

  { По определению. }
  SetLength(Slow, N);
  for I := 0 to Half - 1 do
    for J := 0 to Half - 1 do
      Slow[I + J] := Slow[I + J] + A.Re[I] * B.Re[J];

  { Через спектр: перемножение спектров и обратное преобразование. }
  for I := 0 to N - 1 do
  begin
    Fa.Re[I] := A.Re[I];
    Fa.Im[I] := 0;
    Fb.Re[I] := B.Re[I];
    Fb.Im[I] := 0;
  end;
  Transform(Fa, False);
  Transform(Fb, False);
  for I := 0 to N - 1 do
  begin
    Tmp := Fa.Re[I] * Fb.Re[I] - Fa.Im[I] * Fb.Im[I];
    Fa.Im[I] := Fa.Re[I] * Fb.Im[I] + Fa.Im[I] * Fb.Re[I];
    Fa.Re[I] := Tmp;
  end;
  Transform(Fa, True);

  Worst := 0;
  for I := 0 to N - 1 do
    if Abs(Fa.Re[I] - Slow[I]) > Worst then
      Worst := Abs(Fa.Re[I] - Slow[I]);
  Limit := Tolerance(N * LogTwo(N)) * Half;
  Carrier.Claim(Worst < Limit + 1e-6,
                'fft: spectrum convolution disagrees with the direct sum');
  Carrier.Feed(UInt64(Cardinal(N)));
  Carrier.Feed(UInt64(Round(Slow[0] * 1e6)));
  Carrier.Feed(UInt64(Round(Worst * 1e12)));
end;

{ Энергия, накопленная между оборотами: спектр считается заново каждый оборот,
  а сумма энергий обязана расти монотонно и оставаться конечной. }
procedure StageRunningSpectrum(Carrier: TResidentCarrier);
var
  Pocket: TResidentFftPocket;
  Data: TComplexArray;
  N, I: Integer;
  State: UInt64;
  Before, After: Double;
begin
  Pocket := Carrier.PocketAs<TResidentFftPocket>('fft-running');
  N := 256;
  Data.Init(N);
  State := ResidentMix(Carrier.Seed,
                       UInt64(Cardinal(Carrier.Serial * 7 + Carrier.Lap)));
  FillNoise(Data, State);

  Before := Energy(Data);
  Transform(Data, False);
  After := Energy(Data) / N;

  Carrier.Claim(Abs(After - Before) < Tolerance(N * LogTwo(N)) * (Before + 1.0) + 1e-9,
                'fft: energy changed across the transform');
  Pocket.FEnergy := Pocket.FEnergy + Before;
  Carrier.Claim(Pocket.FEnergy >= Before, 'fft: accumulated energy went backwards');

  Inc(Pocket.FRounds);
  Carrier.Feed(UInt64(Pocket.FRounds));
  Carrier.Feed(UInt64(Round(Pocket.FEnergy * 1e3)));

  if Pocket.FRounds > 40 then
  begin
    Pocket.FEnergy := 0;
    Pocket.FRounds := 0;
  end;
end;

initialization
  ResidentRegisterStage('fft-convolution', @StageConvolution);
  ResidentRegisterStage('fft-linearity', @StageLinearity);
  ResidentRegisterStage('fft-round-trip', @StageRoundTrip);
  ResidentRegisterStage('fft-running-spectrum', @StageRunningSpectrum);
  ResidentRegisterStage('fft-shift', @StageShift);
  ResidentRegisterStage('fft-tone', @StageTone);

end.
