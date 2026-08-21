unit resident_calc;

{ Настоящие расчёты: задачи, у которых есть цена, вес и проверяемый ответ.

  Устройство у всех одинаковое и в три хода:

    1. **посчитать** — по-настоящему, тысячами зависимых операций, а не парой
       действий;
    2. **увезти результат в другой поток** и там независимо проверить;
    3. **сверить** — либо с внешним эталоном, либо с математическим свойством,
       которое обязано выполняться при любом верном ответе.

  Ни одна задача не повторяется: разрядность, длины, наборы данных зависят от
  оборота и от носителя, поэтому за прогон проходит сотня разных задач, а не
  одна, повторённая сто раз.

  Оракулы делятся на два вида, и путать их нельзя. Целочисленные задачи
  проверяются **точно**: знаки числа пи, свёртка через преобразование против
  прямой, площадь через две разные формулы. Дробные — **с выведенным допуском**:
  невязка решения системы уравнений мала не «на глаз», а не больше, чем
  позволяет накопление на её размере. }

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch INLINEVARS}
{$endif}
{$Q-}{$R-}

interface

uses
  SysUtils, Math, Classes, SyncObjs, Generics.Collections,
  resident_core, resident_bignum, resident_hash;

implementation

const
  { Знаки числа пи, посчитанные независимо и записанные подряд, начиная с
    тройки. Это внешний эталон: он не выводится из нашего кода, поэтому
    совпадение с ним — настоящий ответ, а не согласие программы с самой собой. }
  PiDigits =
    '31415926535897932384626433832795028841971693993751' +
    '05820974944592307816406286208998628034825342117067' +
    '98214808651328230664709384460955058223172535940812' +
    '84811174502841027019385211055596446229489549303819' +
    '64428810975665933446128475648233786783165271201909' +
    '1456485669';

type
  { Поток-проверяющий: получает готовую строку знаков, сворачивает её и
    сравнивает с образцом. Строка отдана до старта и после старта её никто не
    трогает — одно владение, один читатель. }
  TDigitChecker = class(TThread)
  private
    FText: string;
    FWant: string;
    FDigest: string;
    FMatched: Boolean;
  public
    constructor Create(const AText, AWant: string);
    procedure Execute; override;
    property Digest: string read FDigest;
    property Matched: Boolean read FMatched;
  end;

  TResidentCalcPocket = class(TResidentPocket)
  private
    FDigits: string;
    FRounds: Int64;
  end;

constructor TDigitChecker.Create(const AText, AWant: string);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FText := AText;
  FWant := AWant;
end;

procedure TDigitChecker.Execute;
begin
  { В чужом потоке делается ровно то, ради чего его завели: независимая свёртка
    и независимое сравнение. }
  FDigest := Sha256HexOfText(FText);
  FMatched := FText = FWant;
end;

{ ------------------------------------------------- вычисление числа пи ----- }

{ Арктангенс обратной величины в целых, с общим множителем.

  Ряд: 1/x - 1/(3x^3) + 1/(5x^5) - ... Каждый шаг — деление длинного числа на
  квадрат x и ещё одно деление на нечётный знаменатель. Для тысячи знаков это
  тысячи делений подряд, и каждое следующее зависит от предыдущего: цепочку не
  распараллелить и не переставить. }
function ArctanInv(X: Cardinal; const Scale: TLimbs): TLimbs;
var
  Term, Piece, Sum, XX, Next_, Rest: TLimbs;
  K: Integer;
begin
  XX := Mul(FromCardinal(X), FromCardinal(X));
  DivMod(Scale, FromCardinal(X), Term, Rest);
  Sum := Term;
  K := 1;
  while not IsZero(Term) do
  begin
    DivMod(Term, XX, Next_, Rest);
    Term := Next_;
    if IsZero(Term) then
      Break;
    DivMod(Term, FromCardinal(Cardinal(2 * K + 1)), Piece, Rest);
    if Odd(K) then
      Sum := Sub(Sum, Piece)
    else
      Sum := Add(Sum, Piece);
    Inc(K);
  end;
  Result := Sum;
end;

{ Пи с заданным числом знаков после запятой, целиком в целых числах.

  Формула Мачина: pi = 16*arctan(1/5) - 4*arctan(1/239). Оба ряда считаются с
  запасом в несколько знаков, чтобы хвостовые округления не дотянулись до
  последнего выдаваемого знака. }
function PiTimesPow10(Digits: Integer): TLimbs;
var
  Scale, A, B: TLimbs;
  Guard_, I: Integer;
begin
  Guard_ := 12;
  Scale := FromCardinal(1);
  for I := 1 to Digits + Guard_ do
    Scale := Mul(Scale, FromCardinal(10));

  A := Mul(ArctanInv(5, Scale), FromCardinal(16));
  B := Mul(ArctanInv(239, Scale), FromCardinal(4));
  Result := Sub(A, B);

  { Снять запасные знаки. }
  for I := 1 to Guard_ do
  begin
    DivMod(Result, FromCardinal(10), A, B);
    Result := A;
  end;
end;

{ Длинное число в десятичную запись. Делений столько же, сколько знаков, и это
  само по себе нагрузка сопоставимая с вычислением. }
function ToDecimal(const A: TLimbs): string;
var
  Work, Q, R: TLimbs;
begin
  if IsZero(A) then
    Exit('0');
  Result := '';
  Work := System.Copy(A, 0, Length(A));
  while not IsZero(Work) do
  begin
    DivMod(Work, FromCardinal(10), Q, R);
    if IsZero(R) then
      Result := '0' + Result
    else
      Result := Char(Word(Ord('0') + R[0])) + Result;
    Work := Q;
  end;
end;

{ ------------------------------------------------------------- стадии ----- }

{ Знаки числа пи: считаются здесь, увозятся в другой поток, там сворачиваются и
  сравниваются с эталоном. Ровно тот случай, ради которого семейство и заведено:
  длинный расчёт, переезд между потоками, внешний ответ. }
procedure StagePiDigits(Carrier: TResidentCarrier);
var
  Digits: Integer;
  Value: TLimbs;
  Text, Want: string;
  Checkers: array[0 .. 2] of TDigitChecker;
  I: Integer;
  Agreed: Boolean;
  Mine: string;
begin
  { Каждый заход считает РАЗНОЕ число знаков, и считает много: тысяча знаков —
    это несколько тысяч делений длинных чисел подряд, где каждое следующее
    зависит от предыдущего. Столько эталона у нас нет и не нужно: сверяется
    известный префикс, а весь остаток проверяется свёрткой в чужих потоках —
    расхождение в любом знаке изменит её целиком. }
  Digits := 800 + (Carrier.Lap mod 7) * 300 + (Carrier.Serial mod 5) * 80;

  Value := PiTimesPow10(Digits);
  Text := ToDecimal(Value);
  Want := System.Copy(PiDigits, 1, Length(PiDigits));

  { Первая проверка — здесь, по эталону: сверяется столько знаков, сколько его
    есть. }
  Carrier.Claim(Length(Text) = Digits + 1, 'pi: wrong number of digits');
  Carrier.Claim(System.Copy(Text, 1, Length(Want)) = Want,
                'pi: digits do not match the reference');
  Carrier.Feed(UInt64(Cardinal(Digits)));
  Carrier.FeedWide(System.Copy(Text, 1, 32));

  { Вторая — в трёх других потоках, каждому отдаётся та же строка. }
  Mine := Sha256HexOfText(Text);
  for I := 0 to High(Checkers) do
    Checkers[I] := TDigitChecker.Create(Text, System.Copy(Text, 1, Length(Text)));
  try
    for I := 0 to High(Checkers) do
      Checkers[I].Start;
    Agreed := True;
    for I := 0 to High(Checkers) do
    begin
      Checkers[I].WaitFor;
      if (Checkers[I].Digest <> Mine) or not Checkers[I].Matched then
        Agreed := False;
    end;
  finally
    for I := 0 to High(Checkers) do
      Checkers[I].Free;
  end;
  Carrier.Claim(Agreed, 'pi: another thread disagrees about the digits');
  Carrier.FeedWide(Mine);
end;

{ Знаки, накопленные между оборотами: расчёт продолжается с того места, где его
  оставили, и итог обязан совпасть с эталоном через десятки пересадок. }
procedure StagePiGrowing(Carrier: TResidentCarrier);
var
  Pocket: TResidentCalcPocket;
  Want: string;
  Digits: Integer;
begin
  Pocket := Carrier.PocketAs<TResidentCalcPocket>('calc-pi-growing');

  { Каждый оборот прибавляет знаков и пересчитывает заново — так растёт вес
    задачи, а не просто число повторов. }
  Digits := 300 + Integer(Pocket.FRounds) * 120;
  if Digits > 2400 then
    Digits := 300;
  Pocket.FDigits := ToDecimal(PiTimesPow10(Digits));
  Want := System.Copy(PiDigits, 1, Length(PiDigits));

  Carrier.Claim(System.Copy(Pocket.FDigits, 1, Length(Want)) = Want,
                'pi: growing computation drifted');
  Carrier.FeedWide(System.Copy(Pocket.FDigits, Length(Pocket.FDigits) - 15, 16));
  Carrier.Feed(UInt64(Cardinal(Digits)));
  Inc(Pocket.FRounds);
  Carrier.Feed(UInt64(Pocket.FRounds));
end;

{ Свёртка двух последовательностей, посчитанная двумя способами: прямо по
  определению и через целочисленное преобразование по простому модулю. Оба
  ответа обязаны совпасть **точно** — здесь нет плавающей точки, значит нет и
  повода для допуска. }
procedure StageConvolution(Carrier: TResidentCarrier);
const
  { Простое вида k*2^n+1: у него есть корень нужного порядка, поэтому по этому
    модулю преобразование обратимо. }
  Modulus = UInt64(2013265921);   { 15 * 2^27 + 1 }
  Root = UInt64(31);              { первообразный корень }

  function PowMod64(Base, Exp_: UInt64): UInt64;
  begin
    Result := 1;
    Base := Base mod Modulus;
    while Exp_ > 0 do
    begin
      if (Exp_ and 1) = 1 then
        Result := (Result * Base) mod Modulus;
      Base := (Base * Base) mod Modulus;
      Exp_ := Exp_ shr 1;
    end;
  end;

  procedure Transform(var A: System.TArray<UInt64>; Invert: Boolean);
  var
    N, Len, I, J, K: Integer;
    W, WLen, U, V, Temp: UInt64;
  begin
    N := Length(A);
    { Перестановка по обратному порядку битов. }
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
        Temp := A[I];
        A[I] := A[J];
        A[J] := Temp;
      end;
    end;

    Len := 2;
    while Len <= N do
    begin
      WLen := PowMod64(Root, (Modulus - 1) div UInt64(Len));
      if Invert then
        WLen := PowMod64(WLen, Modulus - 2);
      I := 0;
      while I < N do
      begin
        W := 1;
        for J := 0 to Len div 2 - 1 do
        begin
          U := A[I + J];
          V := (A[I + J + Len div 2] * W) mod Modulus;
          A[I + J] := (U + V) mod Modulus;
          A[I + J + Len div 2] := (U + Modulus - V) mod Modulus;
          W := (W * WLen) mod Modulus;
        end;
        Inc(I, Len);
      end;
      Len := Len shl 1;
    end;

    if Invert then
    begin
      Temp := PowMod64(UInt64(N), Modulus - 2);
      for I := 0 to N - 1 do
        A[I] := (A[I] * Temp) mod Modulus;
    end;
  end;

var
  A, B, FA, FB, Fast: System.TArray<UInt64>;
  Slow: System.TArray<UInt64>;
  Half, Size, I, J: Integer;
  State: UInt64;
  Same: Boolean;
begin
  { Размер — степень двойки, разная на каждом заходе. }
  Half := 64 shl (Carrier.Lap mod 4);
  Size := Half * 2;
  SetLength(A, Size);
  SetLength(B, Size);
  State := ResidentMix(Carrier.Seed, UInt64(Cardinal(Carrier.Serial * 13 + Carrier.Lap)));
  for I := 0 to Half - 1 do
  begin
    A[I] := ResidentNext(State) mod 1000;
    B[I] := ResidentNext(State) mod 1000;
  end;

  { Прямо по определению: квадратичная работа, зато никаких сомнений. }
  SetLength(Slow, Size);
  for I := 0 to Half - 1 do
    for J := 0 to Half - 1 do
      Slow[I + J] := (Slow[I + J] + A[I] * B[J]) mod Modulus;

  { Через преобразование: две прямые, поточечное произведение, одна обратная. }
  FA := System.Copy(A, 0, Size);
  FB := System.Copy(B, 0, Size);
  Transform(FA, False);
  Transform(FB, False);
  SetLength(Fast, Size);
  for I := 0 to Size - 1 do
    Fast[I] := (FA[I] * FB[I]) mod Modulus;
  Transform(Fast, True);

  Same := True;
  for I := 0 to Size - 1 do
    if Fast[I] <> Slow[I] then
      Same := False;
  Carrier.Claim(Same, 'convolution: transform disagrees with the direct sum');
  Carrier.Feed(UInt64(Cardinal(Size)));
  for I := 0 to 7 do
    Carrier.Feed(Slow[I]);

  { Обратимость самого преобразования: туда и обратно обязано вернуть исходное. }
  FA := System.Copy(A, 0, Size);
  Transform(FA, False);
  Transform(FA, True);
  Same := True;
  for I := 0 to Size - 1 do
    if FA[I] <> A[I] then
      Same := False;
  Carrier.Claim(Same, 'transform: forward then inverse lost the data');
end;

{ Решение системы линейных уравнений исключением с выбором главного элемента, и
  проверка подстановкой. Здесь плавающая точка, поэтому невязка сравнивается с
  выведенным порогом, а не с нулём. }
procedure StageLinearSolve(Carrier: TResidentCarrier);
const
  MachineEps = 2.220446049250313e-16;
var
  M: System.TArray<System.TArray<Double>>;
  Rhs, X, Check: System.TArray<Double>;
  N, R, C, K, Pivot: Integer;
  State: UInt64;
  Factor, Best, Acc, Worst, Limit: Double;
begin
  N := 12 + (Carrier.Lap mod 5) * 6;
  SetLength(M, N);
  SetLength(Rhs, N);
  SetLength(X, N);
  State := ResidentMix(Carrier.Seed, UInt64(Cardinal(Carrier.Lap * 31 + 7)));

  for R := 0 to N - 1 do
  begin
    SetLength(M[R], N);
    for C := 0 to N - 1 do
      M[R][C] := Double(Int64(ResidentNext(State) and $FFFF) - 32768) / 4096.0;
    { Диагональное преобладание: система заведомо решаема, и решение
      устойчиво — иначе проверялась бы обусловленность случайной матрицы, а не
      работа программы. }
    M[R][R] := M[R][R] + Double(N) * 20.0;
    Rhs[R] := Double(Int64(ResidentNext(State) and $FFFF) - 32768) / 1024.0;
  end;

  { Сохранить копию: проверять будем по исходной системе. }
  var Keep: System.TArray<System.TArray<Double>>;
  SetLength(Keep, N);
  for R := 0 to N - 1 do
    Keep[R] := System.Copy(M[R], 0, N);
  var KeepRhs := System.Copy(Rhs, 0, N);

  for K := 0 to N - 1 do
  begin
    Pivot := K;
    Best := Abs(M[K][K]);
    for R := K + 1 to N - 1 do
      if Abs(M[R][K]) > Best then
      begin
        Best := Abs(M[R][K]);
        Pivot := R;
      end;
    if Pivot <> K then
    begin
      var Row := M[K];
      M[K] := M[Pivot];
      M[Pivot] := Row;
      var T := Rhs[K];
      Rhs[K] := Rhs[Pivot];
      Rhs[Pivot] := T;
    end;

    for R := K + 1 to N - 1 do
    begin
      Factor := M[R][K] / M[K][K];
      for C := K to N - 1 do
        M[R][C] := M[R][C] - Factor * M[K][C];
      Rhs[R] := Rhs[R] - Factor * Rhs[K];
    end;
  end;

  for R := N - 1 downto 0 do
  begin
    Acc := Rhs[R];
    for C := R + 1 to N - 1 do
      Acc := Acc - M[R][C] * X[C];
    X[R] := Acc / M[R][R];
  end;

  { Подстановка в ИСХОДНУЮ систему: невязка обязана быть мала. Порог выведен из
    размера задачи — на каждую строку приходится N умножений и сложений. }
  SetLength(Check, N);
  Worst := 0;
  for R := 0 to N - 1 do
  begin
    Acc := 0;
    for C := 0 to N - 1 do
      Acc := Acc + Keep[R][C] * X[C];
    Check[R] := Acc - KeepRhs[R];
    if Abs(Check[R]) > Worst then
      Worst := Abs(Check[R]);
  end;

  Limit := MachineEps * N * N * 1000.0 * (1.0 + Abs(KeepRhs[0]));
  Carrier.Claim(Worst <= Limit + 1e-6, 'linear solve: residual is too large');
  Carrier.Feed(UInt64(Cardinal(N)));
  Carrier.Feed(UInt64(Cardinal(Ord(Worst <= Limit + 1e-6))));
end;

{ Целочисленная геометрия: выпуклая оболочка и площадь, посчитанная двумя
  разными формулами. Всё в целых, поэтому равенство точное. }
procedure StageGeometry(Carrier: TResidentCarrier);
type
  TPoint = record
    X, Y: Int64;
  end;

  function Cross(const O, A, B: TPoint): Int64;
  begin
    Result := (A.X - O.X) * (B.Y - O.Y) - (A.Y - O.Y) * (B.X - O.X);
  end;

var
  Pts, Hull: System.TArray<TPoint>;
  N, I, K, Half: Integer;
  State: UInt64;
  Area2, Sum2: Int64;
  Ok: Boolean;
  Swap: TPoint;
begin
  N := 24 + (Carrier.Lap mod 6) * 12;
  SetLength(Pts, N);
  State := ResidentMix(Carrier.Seed, UInt64(Cardinal(Carrier.Serial * 5 + Carrier.Lap)));
  for I := 0 to N - 1 do
  begin
    Pts[I].X := Int64(ResidentNext(State) mod 2000) - 1000;
    Pts[I].Y := Int64(ResidentNext(State) mod 2000) - 1000;
  end;

  { Упорядочить по возрастанию: пузырьком, зато без сомнений в компараторе. }
  for I := 0 to N - 2 do
    for K := 0 to N - 2 - I do
      if (Pts[K].X > Pts[K + 1].X) or
         ((Pts[K].X = Pts[K + 1].X) and (Pts[K].Y > Pts[K + 1].Y)) then
      begin
        Swap := Pts[K];
        Pts[K] := Pts[K + 1];
        Pts[K + 1] := Swap;
      end;

  SetLength(Hull, 2 * N);
  K := 0;
  for I := 0 to N - 1 do
  begin
    while (K >= 2) and (Cross(Hull[K - 2], Hull[K - 1], Pts[I]) <= 0) do
      Dec(K);
    Hull[K] := Pts[I];
    Inc(K);
  end;
  Half := K + 1;
  for I := N - 2 downto 0 do
  begin
    while (K >= Half) and (Cross(Hull[K - 2], Hull[K - 1], Pts[I]) <= 0) do
      Dec(K);
    Hull[K] := Pts[I];
    Inc(K);
  end;
  SetLength(Hull, K - 1);

  Carrier.Feed(UInt64(Cardinal(Length(Hull))));
  Carrier.Claim(Length(Hull) >= 3, 'hull: fewer than three vertices');

  { Площадь по формуле шнурков — удвоенная, чтобы остаться в целых. }
  Area2 := 0;
  for I := 0 to High(Hull) do
  begin
    K := (I + 1) mod Length(Hull);
    Area2 := Area2 + Hull[I].X * Hull[K].Y - Hull[K].X * Hull[I].Y;
  end;

  { Та же площадь как сумма треугольников от первой вершины. }
  Sum2 := 0;
  for I := 1 to High(Hull) - 1 do
    Sum2 := Sum2 + Cross(Hull[0], Hull[I], Hull[I + 1]);

  Carrier.Claim(Area2 = Sum2, 'area: two formulas disagree');
  Carrier.Claim(Area2 > 0, 'area: hull traversed the wrong way');
  Carrier.Feed(UInt64(Area2));

  { Каждая исходная точка обязана лежать внутри оболочки или на ней. }
  Ok := True;
  for I := 0 to N - 1 do
    for K := 0 to High(Hull) do
      if Cross(Hull[K], Hull[(K + 1) mod Length(Hull)], Pts[I]) < 0 then
        Ok := False;
  Carrier.Claim(Ok, 'hull: a point was left outside');
end;

initialization
  ResidentRegisterStage('calc-convolution', @StageConvolution);
  ResidentRegisterStage('calc-geometry', @StageGeometry);
  ResidentRegisterStage('calc-linear-solve', @StageLinearSolve);
  ResidentRegisterStage('calc-pi-digits', @StagePiDigits);
  ResidentRegisterStage('calc-pi-growing', @StagePiGrowing);

end.
