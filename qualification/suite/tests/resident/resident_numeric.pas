unit resident_numeric;

{ Разложения матриц и теория чисел.

  Обе половины дают то, чего в слое ещё не было.

  **Разложения** — это длинные цепочки зависимых действий над плавающей точкой,
  но с оракулами, которые проверяют не число, а свойство: ортогональная матрица
  умноженная на себя транспонированную даёт единичную; произведение множителей
  даёт исходную матрицу; треугольный множитель Холецкого воспроизводит исходную.
  Такие свойства не требуют эталона и не боятся перестановки сложений.

  **Теория чисел** — целочисленная, поэтому проверяется точно, и у неё есть
  редкая роскошь: **внешние числа, известные независимо**. Сколько простых чисел
  до миллиона — вопрос с одним ответом, и он не выводится из нашего кода.

  Решето — снова та самая форма, что уже дала находку: проход по таблице внутри
  внешнего цикла. Здесь она в другом виде — вычёркивание кратных, — и это
  нарочно: одну и ту же форму надо щупать разными способами. }

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

  { Сколько простых чисел не превышает данной границы. Числа известны
    независимо и не выводятся из нашего кода — это внешний ответ. }
  PiOf10 = 4;
  PiOf100 = 25;
  PiOf1000 = 168;
  PiOf10000 = 1229;
  PiOf100000 = 9592;
  SumTo100 = 1060;
  SumTo1000 = 76127;
  Prime1000th = 7919;

type
  TMatrix = System.TArray<System.TArray<Double>>;

  TResidentNumPocket = class(TResidentPocket)
  private
    FCount: Int64;
    FRounds: Int64;
  end;

function Tolerance(Steps: Integer): Double;
begin
  Result := MachineEps * Steps * Guard;
end;

function MakeMatrix(N: Integer; var State: UInt64): TMatrix;
var
  R, C: Integer;
begin
  SetLength(Result, N);
  for R := 0 to N - 1 do
  begin
    SetLength(Result[R], N);
    for C := 0 to N - 1 do
      Result[R][C] := (Double(Int64(ResidentNext(State) and $FFFF)) - 32768.0) /
                      8192.0;
  end;
end;

function Product(const A, B: TMatrix): TMatrix;
var
  N, R, C, K: Integer;
  Acc: Double;
begin
  N := Length(A);
  SetLength(Result, N);
  for R := 0 to N - 1 do
  begin
    SetLength(Result[R], N);
    for C := 0 to N - 1 do
    begin
      Acc := 0;
      for K := 0 to N - 1 do
        Acc := Acc + A[R][K] * B[K][C];
      Result[R][C] := Acc;
    end;
  end;
end;

function Transpose(const A: TMatrix): TMatrix;
var
  N, R, C: Integer;
begin
  N := Length(A);
  SetLength(Result, N);
  for R := 0 to N - 1 do
  begin
    SetLength(Result[R], N);
    for C := 0 to N - 1 do
      Result[R][C] := A[C][R];
  end;
end;

{ ------------------------------------------------------------- стадии ----- }

{ Разложение на ортогональный и треугольный множители по Граму — Шмидту.

  Два независимых свойства: столбцы первого множителя попарно перпендикулярны и
  единичной длины, а произведение множителей воспроизводит исходную матрицу. }
procedure StageQr(Carrier: TResidentCarrier);
var
  A, Q, R, Check, Ident: TMatrix;
  N, I, J, K: Integer;
  State: UInt64;
  Dot, Norm, Worst, Limit: Double;
begin
  N := 6 + (Carrier.Lap mod 5) * 3;
  State := ResidentMix(Carrier.Seed,
                       UInt64(Cardinal(Carrier.Serial * 37 + Carrier.Lap)));
  A := MakeMatrix(N, State);
  { Диагональное усиление: столбцы гарантированно независимы, и разложение
    существует. Иначе проверялась бы вырожденность случайной матрицы. }
  for I := 0 to N - 1 do
    A[I][I] := A[I][I] + N * 4.0;

  SetLength(Q, N);
  SetLength(R, N);
  for I := 0 to N - 1 do
  begin
    SetLength(Q[I], N);
    SetLength(R[I], N);
  end;

  { Столбцы по очереди: из очередного вычитается его проекция на уже готовые,
    остаток нормируется. }
  for J := 0 to N - 1 do
  begin
    for I := 0 to N - 1 do
      Q[I][J] := A[I][J];

    for K := 0 to J - 1 do
    begin
      Dot := 0;
      for I := 0 to N - 1 do
        Dot := Dot + Q[I][K] * A[I][J];
      R[K][J] := Dot;
      for I := 0 to N - 1 do
        Q[I][J] := Q[I][J] - Dot * Q[I][K];
    end;

    Norm := 0;
    for I := 0 to N - 1 do
      Norm := Norm + Q[I][J] * Q[I][J];
    Norm := Sqrt(Norm);
    R[J][J] := Norm;
    for I := 0 to N - 1 do
      Q[I][J] := Q[I][J] / Norm;
  end;

  { Первое свойство: столбцы перпендикулярны и единичны, то есть произведение
    транспонированного на исходный даёт единичную матрицу. }
  Ident := Product(Transpose(Q), Q);
  Worst := 0;
  for I := 0 to N - 1 do
    for J := 0 to N - 1 do
    begin
      if I = J then
        Dot := Abs(Ident[I][J] - 1.0)
      else
        Dot := Abs(Ident[I][J]);
      if Dot > Worst then
        Worst := Dot;
    end;
  Limit := Tolerance(N * N * N) * 10.0;
  Carrier.Claim(Worst < Limit + 1e-9, 'qr: columns are not orthonormal');
  Carrier.Feed(UInt64(Cardinal(N)));
  Carrier.Feed(UInt64(Round(Worst * 1e15)));

  { Второе свойство: произведение множителей воспроизводит исходную матрицу. }
  Check := Product(Q, R);
  Worst := 0;
  for I := 0 to N - 1 do
    for J := 0 to N - 1 do
      if Abs(Check[I][J] - A[I][J]) > Worst then
        Worst := Abs(Check[I][J] - A[I][J]);
  Carrier.Claim(Worst < Limit * (1.0 + N * 4.0) + 1e-9,
                'qr: factors do not reproduce the matrix');
  Carrier.Feed(UInt64(Round(Worst * 1e12)));
end;

{ Разложение положительно определённой матрицы на треугольный множитель и его
  транспонированный. Свойство одно и точное: произведение воспроизводит
  исходную. }
procedure StageCholesky(Carrier: TResidentCarrier);
var
  A, B, L, Check: TMatrix;
  N, I, J, K: Integer;
  State: UInt64;
  Acc, Worst, Limit: Double;
  Ok: Boolean;
begin
  N := 6 + (Carrier.Lap mod 4) * 3;
  State := ResidentMix(Carrier.Seed, UInt64(Cardinal(Carrier.Lap * 53 + 11)));
  B := MakeMatrix(N, State);

  { Положительно определённая матрица строится как произведение матрицы на свою
    транспонированную с усиленной диагональю: так разложение заведомо есть. }
  A := Product(B, Transpose(B));
  for I := 0 to N - 1 do
    A[I][I] := A[I][I] + N * 2.0;

  SetLength(L, N);
  for I := 0 to N - 1 do
  begin
    SetLength(L[I], N);
    for J := 0 to N - 1 do
      L[I][J] := 0;
  end;

  Ok := True;
  for I := 0 to N - 1 do
    for J := 0 to I do
    begin
      Acc := A[I][J];
      for K := 0 to J - 1 do
        Acc := Acc - L[I][K] * L[J][K];
      if I = J then
      begin
        if Acc <= 0 then
          Ok := False
        else
          L[I][J] := Sqrt(Acc);
      end
      else
        L[I][J] := Acc / L[J][J];
    end;
  Carrier.Claim(Ok, 'cholesky: matrix turned out not positive definite');

  { Верхний треугольник обязан остаться пустым. }
  for I := 0 to N - 1 do
    for J := I + 1 to N - 1 do
      Carrier.Claim(L[I][J] = 0, 'cholesky: upper triangle is not empty');

  Check := Product(L, Transpose(L));
  Worst := 0;
  for I := 0 to N - 1 do
    for J := 0 to N - 1 do
      if Abs(Check[I][J] - A[I][J]) > Worst then
        Worst := Abs(Check[I][J] - A[I][J]);
  Limit := Tolerance(N * N * N) * (1.0 + Abs(A[0][0]));
  Carrier.Claim(Worst < Limit + 1e-9, 'cholesky: factor does not reproduce the matrix');
  Carrier.Feed(UInt64(Cardinal(N)));
  Carrier.Feed(UInt64(Round(Worst * 1e12)));
end;

{ Решето: проход по таблице с вычёркиванием кратных внутри внешнего цикла.
  Сколько простых не превышает границы — известно независимо. }
procedure StageSieve(Carrier: TResidentCarrier);
var
  Mark: System.TArray<Boolean>;
  Limit, I, J, Count, Small: Integer;
  Sum: Int64;
begin
  { Граница меняется от оборота, но всегда одна из тех, для которых ответ
    известен: иначе проверять было бы не с чем. }
  case Carrier.Lap mod 4 of
    0: Limit := 100;
    1: Limit := 1000;
    2: Limit := 10000;
  else
    Limit := 100000;
  end;

  SetLength(Mark, Limit + 1);
  for I := 0 to Limit do
    Mark[I] := True;
  Mark[0] := False;
  if Limit >= 1 then
    Mark[1] := False;

  I := 2;
  while I * I <= Limit do
  begin
    if Mark[I] then
    begin
      J := I * I;
      while J <= Limit do
      begin
        Mark[J] := False;
        Inc(J, I);
      end;
    end;
    Inc(I);
  end;

  Count := 0;
  Sum := 0;
  for I := 2 to Limit do
    if Mark[I] then
    begin
      Inc(Count);
      Sum := Sum + I;
    end;

  case Limit of
    100: Carrier.Claim(Count = PiOf100, 'sieve: wrong count below 100');
    1000: Carrier.Claim(Count = PiOf1000, 'sieve: wrong count below 1000');
    10000: Carrier.Claim(Count = PiOf10000, 'sieve: wrong count below 10000');
    100000: Carrier.Claim(Count = PiOf100000, 'sieve: wrong count below 100000');
  end;
  if Limit >= 100 then
  begin
    Small := 0;
    for I := 2 to 10 do
      if Mark[I] then
        Inc(Small);
    Carrier.Claim(Small = PiOf10, 'sieve: wrong count below 10');
  end;
  if Limit = 100 then
    Carrier.Claim(Sum = SumTo100, 'sieve: wrong sum below 100');
  if Limit = 1000 then
  begin
    Carrier.Claim(Sum = SumTo1000, 'sieve: wrong sum below 1000');
    { Тысячное простое тоже известно. }
    Count := 0;
    for I := 2 to Limit do
      if Mark[I] then
      begin
        Inc(Count);
        if Count = 1000 then
        begin
          Carrier.Claim(I = Prime1000th, 'sieve: wrong 1000th prime');
          Break;
        end;
      end;
  end;

  Carrier.Feed(UInt64(Cardinal(Limit)));
  Carrier.Feed(UInt64(Sum));

  { Свойства, верные при любой границе: два и три простые, четыре и девять нет,
    и ни одно чётное больше двух не простое. }
  Carrier.Claim(Mark[2] and Mark[3], 'sieve: 2 or 3 not marked prime');
  Carrier.Claim(not Mark[4], 'sieve: 4 marked prime');
  if Limit >= 9 then
    Carrier.Claim(not Mark[9], 'sieve: 9 marked prime');
  I := 4;
  while I <= Limit do
  begin
    if Mark[I] then
      Carrier.Claim(False, 'sieve: an even number marked prime');
    Inc(I, 2);
  end;
end;

{ Проверка на простоту по свидетелям, сверенная с решетом на всём диапазоне.
  Два независимых способа обязаны сойтись на каждом числе. }
procedure StageWitness(Carrier: TResidentCarrier);
const
  Witnesses: array[0 .. 6] of UInt64 = (2, 3, 5, 7, 11, 13, 17);
var
  Mark: System.TArray<Boolean>;
  Limit, I, J: Integer;
  Disagree: Integer;

  function MulMod(A, B, M: UInt64): UInt64;
  var
    Acc: UInt64;
  begin
    { Умножение по модулю через сложение: произведение может не поместиться в
      разрядность, поэтому оно набирается удвоениями. }
    Acc := 0;
    A := A mod M;
    while B > 0 do
    begin
      if (B and 1) = 1 then
        Acc := (Acc + A) mod M;
      A := (A + A) mod M;
      B := B shr 1;
    end;
    Result := Acc;
  end;

  function PowMod64(Base, Exp_, M: UInt64): UInt64;
  begin
    Result := 1;
    Base := Base mod M;
    while Exp_ > 0 do
    begin
      if (Exp_ and 1) = 1 then
        Result := MulMod(Result, Base, M);
      Base := MulMod(Base, Base, M);
      Exp_ := Exp_ shr 1;
    end;
  end;

  function LooksPrime(N: UInt64): Boolean;
  var
    D, X: UInt64;
    R, K, W: Integer;
    Composite: Boolean;
  begin
    if N < 2 then
      Exit(False);
    for W := 0 to High(Witnesses) do
      if N = Witnesses[W] then
        Exit(True);
    for W := 0 to High(Witnesses) do
      if N mod Witnesses[W] = 0 then
        Exit(False);

    D := N - 1;
    R := 0;
    while (D and 1) = 0 do
    begin
      D := D shr 1;
      Inc(R);
    end;

    for W := 0 to High(Witnesses) do
    begin
      X := PowMod64(Witnesses[W], D, N);
      if (X = 1) or (X = N - 1) then
        Continue;
      Composite := True;
      for K := 1 to R - 1 do
      begin
        X := MulMod(X, X, N);
        if X = N - 1 then
        begin
          Composite := False;
          Break;
        end;
      end;
      if Composite then
        Exit(False);
    end;
    Result := True;
  end;

begin
  Limit := 2000 + (Carrier.Lap mod 5) * 1000;
  SetLength(Mark, Limit + 1);
  for I := 0 to Limit do
    Mark[I] := True;
  Mark[0] := False;
  Mark[1] := False;
  I := 2;
  while I * I <= Limit do
  begin
    if Mark[I] then
    begin
      J := I * I;
      while J <= Limit do
      begin
        Mark[J] := False;
        Inc(J, I);
      end;
    end;
    Inc(I);
  end;

  { Два способа на всём диапазоне: несовпадение хотя бы на одном числе — провал.
    Свидетели выбраны так, что на этом диапазоне проверка точна. }
  Disagree := 0;
  for I := 2 to Limit do
    if LooksPrime(UInt64(I)) <> Mark[I] then
      Inc(Disagree);
  Carrier.Claim(Disagree = 0, 'witness test disagrees with the sieve');
  Carrier.Feed(UInt64(Cardinal(Limit)));
  Carrier.Feed(UInt64(Cardinal(Disagree)));
end;

{ Наибольший общий делитель и его свойства: произведение с наименьшим общим
  кратным равно произведению чисел, а расширенный алгоритм даёт коэффициенты,
  которые это подтверждают. }
procedure StageGcd(Carrier: TResidentCarrier);
var
  State: UInt64;
  A, B, G, L: Int64;
  X, Y: Int64;
  I: Integer;

  function Gcd(P, Q: Int64): Int64;
  var
    T: Int64;
  begin
    while Q <> 0 do
    begin
      T := P mod Q;
      P := Q;
      Q := T;
    end;
    Result := P;
  end;

  procedure ExtGcd(P, Q: Int64; out D, Sx, Sy: Int64);
  var
    D1, X1, Y1: Int64;
  begin
    if Q = 0 then
    begin
      D := P;
      Sx := 1;
      Sy := 0;
      Exit;
    end;
    ExtGcd(Q, P mod Q, D1, X1, Y1);
    D := D1;
    Sx := Y1;
    Sy := X1 - (P div Q) * Y1;
  end;

begin
  State := ResidentMix(Carrier.Seed,
                       UInt64(Cardinal(Carrier.Serial * 61 + Carrier.Lap)));
  for I := 1 to 24 do
  begin
    A := Int64(ResidentNext(State) mod 1000000) + 1;
    B := Int64(ResidentNext(State) mod 1000000) + 1;

    G := Gcd(A, B);
    Carrier.Claim(G > 0, 'gcd: not positive');
    Carrier.Claim((A mod G = 0) and (B mod G = 0), 'gcd: does not divide both');

    { Наименьшее общее кратное через наибольший общий делитель. }
    L := (A div G) * B;
    Carrier.Claim((L mod A = 0) and (L mod B = 0), 'lcm: not a common multiple');
    Carrier.Claim(G * L = A * B, 'gcd times lcm is not the product');

    { Расширенный алгоритм: коэффициенты обязаны давать сам делитель. }
    ExtGcd(A, B, G, X, Y);
    Carrier.Claim(A * X + B * Y = G, 'extended gcd: coefficients do not fit');
  end;
  Carrier.Feed(UInt64(Cardinal(24)));
end;

{ Разложение на множители: произведение найденных множителей обязано дать
  исходное число, и каждый множитель обязан быть простым. }
procedure StageFactor(Carrier: TResidentCarrier);
var
  State: UInt64;
  N, Rest, Back, D: Int64;
  I, Count: Integer;
  Factors: System.TArray<Int64>;

  function IsPrimeSmall(V: Int64): Boolean;
  var
    K: Int64;
  begin
    if V < 2 then
      Exit(False);
    K := 2;
    while K * K <= V do
    begin
      if V mod K = 0 then
        Exit(False);
      Inc(K);
    end;
    Result := True;
  end;

begin
  State := ResidentMix(Carrier.Seed, UInt64(Cardinal(Carrier.Lap * 7 + 19)));
  for I := 1 to 8 do
  begin
    N := Int64(ResidentNext(State) mod 4000000) + 2;
    Rest := N;
    SetLength(Factors, 0);
    D := 2;
    while D * D <= Rest do
    begin
      while Rest mod D = 0 do
      begin
        SetLength(Factors, Length(Factors) + 1);
        Factors[High(Factors)] := D;
        Rest := Rest div D;
      end;
      Inc(D);
    end;
    if Rest > 1 then
    begin
      SetLength(Factors, Length(Factors) + 1);
      Factors[High(Factors)] := Rest;
    end;

    Back := 1;
    for Count := 0 to High(Factors) do
    begin
      Back := Back * Factors[Count];
      Carrier.Claim(IsPrimeSmall(Factors[Count]), 'factor: a factor is not prime');
    end;
    Carrier.Claim(Back = N, 'factor: product of factors is not the number');
    Carrier.Claim(Length(Factors) > 0, 'factor: no factors found');
  end;
  Carrier.Feed(UInt64(Cardinal(8)));
end;

{ Счёт простых, накопленный между оборотами: границы растут, и число простых
  обязано расти вместе с ними, никогда не убывая. }
procedure StageRunningCount(Carrier: TResidentCarrier);
var
  Pocket: TResidentNumPocket;
  Mark: System.TArray<Boolean>;
  Limit, I, J, Count: Integer;
begin
  Pocket := Carrier.PocketAs<TResidentNumPocket>('numeric-running');
  Limit := 200 + Integer(Pocket.FRounds) * 200;
  if Limit > 20000 then
    Limit := 200;

  SetLength(Mark, Limit + 1);
  for I := 0 to Limit do
    Mark[I] := True;
  Mark[0] := False;
  Mark[1] := False;
  I := 2;
  while I * I <= Limit do
  begin
    if Mark[I] then
    begin
      J := I * I;
      while J <= Limit do
      begin
        Mark[J] := False;
        Inc(J, I);
      end;
    end;
    Inc(I);
  end;
  Count := 0;
  for I := 2 to Limit do
    if Mark[I] then
      Inc(Count);

  { Счёт простых не убывает с ростом границы — это свойство самой функции. }
  if (Limit > 200) and (Pocket.FCount > 0) then
    Carrier.Claim(Count >= Pocket.FCount,
                  'prime count went down as the bound grew');
  Pocket.FCount := Count;
  Carrier.Feed(UInt64(Cardinal(Limit)));
  Carrier.Feed(UInt64(Cardinal(Count)));

  Inc(Pocket.FRounds);
  if Limit = 200 then
    Pocket.FRounds := 1;
  Carrier.Feed(UInt64(Pocket.FRounds));
end;

initialization
  ResidentRegisterStage('numeric-cholesky', @StageCholesky);
  ResidentRegisterStage('numeric-factor', @StageFactor);
  ResidentRegisterStage('numeric-gcd', @StageGcd);
  ResidentRegisterStage('numeric-qr', @StageQr);
  ResidentRegisterStage('numeric-running-count', @StageRunningCount);
  ResidentRegisterStage('numeric-sieve', @StageSieve);
  ResidentRegisterStage('numeric-witness', @StageWitness);

end.
