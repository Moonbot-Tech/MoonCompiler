unit resident_float;

{ Плавающая точка — с двумя разными мерками, и путать их нельзя.

  **Строго.** Есть места, где результат точен по построению и никакого допуска
  не заслуживает: числа, представимые точно (степени двойки, небольшие целые),
  знак, классификация особых значений, раскладка на знак-порядок-мантиссу,
  сравнения. Тут `2.5 * 2` обязано быть ровно `5`, и «почти пять» — это провал.

  **С допуском.** Есть места, где накопление неизбежно: длинная сумма, скалярное
  произведение, перемножение матриц. Там порядок действий влияет на последние
  биты, и это законно — компилятор вправе переставлять и совмещать умножение со
  сложением. Требовать побитового совпадения значило бы ловить не ошибку, а
  разрешённую свободу.

  Допуск при этом не подбирается под ответ, а **выводится**: относительная
  ошибка одного действия не превышает половины машинного эпсилона, на N
  зависимых действий она копится не быстрее чем линейно, берётся запас в тысячу
  раз. Порог, полученный так, пропускает последний бит и ловит любую потерю
  смысла: «пять с точностью до тысячной» пройдёт, «семь вместо пяти» — нет.

  В свёртку носителя сырые дробные значения не идут никогда — только вердикты и
  точные величины. Иначе законное различие в последнем бите развалило бы
  сравнение уровней оптимизации, и слой ловил бы разрешённое вместо неверного. }

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch INLINEVARS}
{$endif}
{$Q-}{$R-}

interface

uses
  SysUtils, Math, Classes, Generics.Collections, resident_core;

implementation

const
  { Половина расстояния между соседними числами вблизи единицы. }
  MachineEps = 2.220446049250313e-16;
  { Запас поверх линейного накопления: тысячекратный. Он не подгонялся под
    результат — он взят так, чтобы никакая честная перестановка действий в
    порог не упёрлась, а любая потеря смысла в него не поместилась. }
  Guard = 1000.0;

type
  TResidentFloatPocket = class(TResidentPocket)
  private
    FSum: Double;
    FTerms: Int64;
    FRounds: Int64;
  end;

{ Порог для расчёта из N зависимых действий. }
function Tolerance(Steps: Integer): Double;
begin
  Result := MachineEps * Steps * Guard;
end;

{ Согласуются ли два значения в пределах выведенного порога. }
function Close(A, B: Double; Steps: Integer): Boolean;
var
  Scale: Double;
begin
  Scale := Abs(A);
  if Abs(B) > Scale then
    Scale := Abs(B);
  if Scale < 1.0 then
    Scale := 1.0;
  Result := Abs(A - B) <= Tolerance(Steps) * Scale;
end;

{ Огрублённое представление для свёртки: значение делится на порог и
  округляется, поэтому дрожание последнего бита в свёртку не попадает, а
  расхождение по существу — попадает. }
function Coarse(Value: Double; Steps: Integer): Int64;
var
  Step: Double;
begin
  Step := Tolerance(Steps);
  if Step <= 0 then
    Step := MachineEps;
  Result := Round(Value / Step);
end;



{ Здесь остались только СЧИТАЮЩИЕ стадии.

  Проверки представления, классификации особых значений и семантики сравнений
  отсюда убраны сознательно: это отдельные короткие вопросы, а не расчёт, и
  место им не в программе, которая должна считать по-настоящему. То, что среди
  них нашлось (маска сопроцессора и отрицание сравнения при NaN), вынесено в
  находки со своими пробниками — там ему и место.

  Оставшееся считает: ряды до сходимости, скалярные произведения на тысячах
  элементов, перемножение матриц, накопление между оборотами. Оракулы —
  независимость от порядка суммирования в пределах выведенного допуска,
  ассоциативность произведения матриц и известные пределы рядов. }

{ ------------------------------------------------------------- стадии ----- }




{ Длинная сумма: то же слагаемое, сложенное вперёд и назад, обязано сойтись в
  пределах выведенного порога. Побитово оно сходиться НЕ обязано. }
procedure StageSeries(Carrier: TResidentCarrier);
var
  N, I: Integer;
  Up, Down, Term: Double;
begin
  N := 5000 + (Carrier.Lap mod 7) * 2500;

  { Сумма обратных квадратов: сходится к пи-квадрат на шесть. }
  Up := 0;
  for I := 1 to N do
    Up := Up + 1.0 / (Double(I) * Double(I));
  Down := 0;
  for I := N downto 1 do
    Down := Down + 1.0 / (Double(I) * Double(I));

  { Два порядка суммирования — разные последние биты и один и тот же смысл. }
  Carrier.Claim(Close(Up, Down, N), 'float: summation order changed the sum');
  { И оба обязаны быть близки к известному пределу: хвост ряда меньше 1/N. }
  Carrier.Claim(Abs(Up - Pi * Pi / 6.0) < 2.0 / N,
                'float: series does not approach its limit');
  Carrier.Feed(UInt64(Coarse(Up, N)));
  Carrier.Feed(UInt64(Cardinal(N)));

  { Знакопеременный ряд для арктангенса единицы: сходится к четверти пи. }
  Up := 0;
  Term := 1.0;
  for I := 0 to N - 1 do
  begin
    Up := Up + Term / (2 * I + 1);
    Term := -Term;
  end;
  Carrier.Claim(Abs(Up * 4.0 - Pi) < 8.0 / N,
                'float: alternating series does not approach pi');
  Carrier.Feed(UInt64(Coarse(Up * 4.0, N)));
end;

{ Скалярное произведение: считается тремя способами — подряд, попарно и в
  обратном порядке. Все три обязаны сойтись в пределах порога. }
procedure StageDot(Carrier: TResidentCarrier);
var
  A, B: System.TArray<Double>;
  N, I: Integer;
  State: UInt64;
  Straight, Reverse, Paired: Double;
  Halves: System.TArray<Double>;
begin
  N := 1024 + (Carrier.Lap mod 5) * 512;
  SetLength(A, N);
  SetLength(B, N);
  State := ResidentMix(Carrier.Seed, UInt64(Cardinal(Carrier.Serial)));
  for I := 0 to N - 1 do
  begin
    { Значения из узкого диапазона: так сумма не теряет разряды целиком и
      проверяется накопление, а не переполнение. }
    A[I] := 1.0 + Double(ResidentNext(State) and $FFFF) / 65536.0;
    B[I] := 1.0 + Double(ResidentNext(State) and $FFFF) / 65536.0;
  end;

  Straight := 0;
  for I := 0 to N - 1 do
    Straight := Straight + A[I] * B[I];

  Reverse := 0;
  for I := N - 1 downto 0 do
    Reverse := Reverse + A[I] * B[I];

  { Попарное суммирование: другая скобочная расстановка, тот же смысл. }
  SetLength(Halves, N);
  for I := 0 to N - 1 do
    Halves[I] := A[I] * B[I];
  I := N;
  while I > 1 do
  begin
    var J := 0;
    while J + 1 < I do
    begin
      Halves[J div 2] := Halves[J] + Halves[J + 1];
      Inc(J, 2);
    end;
    if I mod 2 = 1 then
    begin
      Halves[I div 2] := Halves[I - 1];
      I := I div 2 + 1;
    end
    else
      I := I div 2;
  end;
  Paired := Halves[0];

  Carrier.Claim(Close(Straight, Reverse, N), 'float: dot product depends on direction');
  Carrier.Claim(Close(Straight, Paired, N), 'float: dot product depends on grouping');
  Carrier.Feed(UInt64(Coarse(Straight, N)));
  Carrier.Feed(UInt64(Cardinal(N)));

  { Само произведение обязано быть положительным: все сомножители больше нуля. }
  Carrier.Claim(Straight > 0, 'float: dot product of positives is not positive');
  Carrier.Claim(Straight >= N, 'float: dot product below its lower bound');
end;

{ Матрицы: умножение ассоциативно с точностью до накопления. }
procedure StageMatrix(Carrier: TResidentCarrier);
type
  TMatrix = System.TArray<System.TArray<Double>>;

  function Make(N: Integer; var State: UInt64): TMatrix;
  var
    R, C: Integer;
  begin
    SetLength(Result, N);
    for R := 0 to N - 1 do
    begin
      SetLength(Result[R], N);
      for C := 0 to N - 1 do
        Result[R][C] := Double(Int64(ResidentNext(State) and $FFFF) - 32768) /
                        1024.0;
    end;
  end;

  function Product(const X, Y: TMatrix): TMatrix;
  var
    N, R, C, K_: Integer;
    Acc: Double;
  begin
    N := Length(X);
    SetLength(Result, N);
    for R := 0 to N - 1 do
    begin
      SetLength(Result[R], N);
      for C := 0 to N - 1 do
      begin
        Acc := 0;
        for K_ := 0 to N - 1 do
          Acc := Acc + X[R][K_] * Y[K_][C];
        Result[R][C] := Acc;
      end;
    end;
  end;

var
  A, B, C, Left, Right, Ident: TMatrix;
  N, R, Col: Integer;
  State: UInt64;
  Agree: Boolean;
begin
  N := 8 + (Carrier.Lap mod 5) * 4;
  State := ResidentMix(Carrier.Seed, UInt64(Cardinal(Carrier.Lap * 7 + 1)));
  A := Make(N, State);
  B := Make(N, State);
  C := Make(N, State);

  Left := Product(Product(A, B), C);
  Right := Product(A, Product(B, C));

  Agree := True;
  for R := 0 to N - 1 do
    for Col := 0 to N - 1 do
      if not Close(Left[R][Col], Right[R][Col], N * N) then
        Agree := False;
  Carrier.Claim(Agree, 'float: matrix product is not associative within tolerance');
  Carrier.Feed(UInt64(Cardinal(N)));
  Carrier.Feed(UInt64(Coarse(Left[0][0], N * N)));

  { Единичная матрица ничего не меняет — и это уже строгая проверка: умножение
    на единицу и сложение с нулём точны. }
  SetLength(Ident, N);
  for R := 0 to N - 1 do
  begin
    SetLength(Ident[R], N);
    for Col := 0 to N - 1 do
      if R = Col then
        Ident[R][Col] := 1.0
      else
        Ident[R][Col] := 0.0;
  end;
  Left := Product(A, Ident);
  Agree := True;
  for R := 0 to N - 1 do
    for Col := 0 to N - 1 do
      if Left[R][Col] <> A[R][Col] then
        Agree := False;
  Carrier.Claim(Agree, 'float: multiplying by identity changed the matrix');
end;


{ Сумма, растущая между оборотами: слагаемые копятся сотни оборотов и переезжают
  между потоками вместе с носителем. Итог сверяется с известной формулой. }
procedure StageRunningSum(Carrier: TResidentCarrier);
var
  Pocket: TResidentFloatPocket;
  I: Integer;
  Expected: Double;
begin
  Pocket := Carrier.PocketAs<TResidentFloatPocket>('float-running');

  { Гармонические слагаемые: сумма первых N обязана лежать между известными
    границами — она заключена между логарифмом и логарифмом плюс единица. }
  for I := 1 to 64 do
  begin
    Inc(Pocket.FTerms);
    Pocket.FSum := Pocket.FSum + 1.0 / Double(Pocket.FTerms);
  end;

  Carrier.Feed(UInt64(Pocket.FTerms));
  Carrier.Feed(UInt64(Coarse(Pocket.FSum, Integer(Pocket.FTerms))));

  Expected := Ln(Double(Pocket.FTerms));
  Carrier.Claim(Pocket.FSum > Expected,
                'float: harmonic sum fell below its lower bound');
  Carrier.Claim(Pocket.FSum < Expected + 1.0,
                'float: harmonic sum rose above its upper bound');

  Inc(Pocket.FRounds);
  Carrier.Feed(UInt64(Pocket.FRounds));

  if Pocket.FTerms > 20000 then
  begin
    Pocket.FSum := 0;
    Pocket.FTerms := 0;
  end;
end;

initialization
  ResidentRegisterStage('float-dot', @StageDot);
  ResidentRegisterStage('float-matrix', @StageMatrix);
  ResidentRegisterStage('float-running-sum', @StageRunningSum);
  ResidentRegisterStage('float-series', @StageSeries);

end.
