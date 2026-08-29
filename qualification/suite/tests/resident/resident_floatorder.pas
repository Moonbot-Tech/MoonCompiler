unit resident_floatorder;

{ Семейство `floatorder` — чего нельзя делать с вещественной арифметикой.

  Остальные вещественные семейства (`float`, `calc`, `fluid`, `fft`) считают и
  сверяют результат с допуском. Здесь проверяется противоположное: что
  компилятор **не переписал** написанное. Вещественное сложение не
  ассоциативно, умножение не распределяется точно, деление не равно умножению
  на обратное — и всё это не мелочи представления, а разные ответы на разных
  входах. Перестановка, законная для целых, для вещественных меняет число.

  Значения подобраны так, что разница видна целиком, а не в последнем разряде:
  вокруг границы точного представления целых любое смещение порядка стоит целой
  единицы. Поэтому здесь нет ни одного допуска — все сравнения строгие, и это
  законно: каждое участвующее число представимо точно, а результат каждой
  операции задан стандартом однозначно.

  Никаких особых значений тут нет и не будет: ни бесконечностей, ни
  неопределённостей. Проверяется обычная арифметика на обычных числах — та,
  которой считают деньги и цены. }

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch INLINEVARS}
{$endif}
{$Q-}{$R-}

interface

uses
  SysUtils, resident_core;

implementation

const
  { Граница, за которой соседние целые перестают быть представимыми: у двойной
    точности пятьдесят три двоичных разряда мантиссы. Все ячейки одинаковы, а
    индекс приходит из потока — значение известно нам, но не выражению. }
  Huge: array[0 .. 3] of Double = (9007199254740992.0, 9007199254740992.0,
                                   9007199254740992.0, 9007199254740992.0);
  Ones: array[0 .. 3] of Double = (1.0, 1.0, 1.0, 1.0);
  Thirds: array[0 .. 3] of Double = (3.0, 3.0, 3.0, 3.0);
  Tenths: array[0 .. 3] of Double = (10.0, 10.0, 10.0, 10.0);

{ Сложение не ассоциативно: скобки решают, каким будет ответ. }
procedure StageAssociativity(Carrier: TResidentCarrier);
var
  State: UInt64;
  Big, One: Double;
  Left, Right: Double;
  Bad: Integer;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap);
  Big := Huge[Integer(ResidentNext(State) and 3)];
  One := Ones[Integer(ResidentNext(State) and 3)];
  Bad := 0;

  { Слева направо: сумма большого и единицы округляется обратно к большому,
    потому что нечётного соседа у него уже нет. Вычитание даёт ноль. }
  Left := (Big + One) - Big;

  { Справа налево: единица вычитается из большого точно, и остаётся. }
  Right := Big + (One - Big);

  if Left <> 0.0 then Inc(Bad);
  if Right <> 1.0 then Inc(Bad);
  if Left = Right then Inc(Bad);

  { То же самое с тройным сложением. }
  if ((Big + One) + (-Big)) <> 0.0 then Inc(Bad);
  if (Big + (One + (-Big))) <> 1.0 then Inc(Bad);

  { А на числах, где округления нет, скобки ничего не меняют. }
  if ((One + One) + One) <> (One + (One + One)) then Inc(Bad);

  Carrier.Feed(UInt64(Trunc(Left)));
  Carrier.Feed(UInt64(Trunc(Right)));
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'floatorder: addition was reassociated');
end;

{ Деление не равно умножению на обратное: обратное само по себе неточно. }
procedure StageDivisionVersusReciprocal(Carrier: TResidentCarrier);
var
  State: UInt64;
  Three, Ten, One: Double;
  I, Bad, Differ: Integer;
  Value, ByDiv, ByMul: Double;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 3 + 1);
  Three := Thirds[Integer(ResidentNext(State) and 3)];
  Ten := Tenths[Integer(ResidentNext(State) and 3)];
  One := Ones[Integer(ResidentNext(State) and 3)];
  Bad := 0;
  Differ := 0;

  for I := 1 to 64 do
    begin
      Value := I;

      ByDiv := Value / Three;
      ByMul := Value * (One / Three);
      if ByDiv <> ByMul then
        Inc(Differ);

      ByDiv := Value / Ten;
      ByMul := Value * (One / Ten);
      if ByDiv <> ByMul then
        Inc(Differ);
    end;

  { Сколько случаев разошлось — не утверждение, а наблюдение: точное их число
    зависит от того, как легли округления, и предъявлять его как известный
    ответ было бы выдумкой. Зато оно обязано совпадать между сборками, а
    обнулиться может только одним способом — если деление заменили умножением
    на обратное. }

  { Деление на степень двойки точно, и там замена законна. }
  for I := 1 to 32 do
    begin
      Value := I;
      if (Value / 2.0) <> (Value * 0.5) then Inc(Bad);
      if (Value / 4.0) <> (Value * 0.25) then Inc(Bad);
      if (Value / 8.0) <> (Value * 0.125) then Inc(Bad);
    end;

  Carrier.Feed(UInt64(Cardinal(Differ)));
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'floatorder: division was replaced by multiplication by the reciprocal');
end;

{ Прибавить и отнять одно и то же — не тождество. }
procedure StageAddSubtract(Carrier: TResidentCarrier);
var
  State: UInt64;
  Big, One: Double;
  Bad: Integer;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 5 + 2);
  Big := Huge[Integer(ResidentNext(State) and 3)];
  One := Ones[Integer(ResidentNext(State) and 3)];
  Bad := 0;

  { Единица тонет в большом числе, и обратно её не достать. }
  if ((Big + One) - Big) = One then Inc(Bad);
  if ((Big + One) - Big) <> 0.0 then Inc(Bad);

  { Единица, утонувшая при сложении, всё равно вычитается: в сумме её нет, а
    вычитание идёт из округлённого значения, и результат меньше исходного. }
  if ((Big + One) - One) <> (Big - 1.0) then Inc(Bad);

  { Вычитание самого себя даёт ноль на любом конечном числе. }
  if (Big - Big) <> 0.0 then Inc(Bad);
  if (One - One) <> 0.0 then Inc(Bad);

  { Умножение на единицу и сложение с нулём ничего не меняют. }
  if (Big * 1.0) <> Big then Inc(Bad);
  if (Big + 0.0) <> Big then Inc(Bad);
  if (Big / 1.0) <> Big then Inc(Bad);

  Carrier.Feed(UInt64(Trunc(Big)));
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'floatorder: adding and subtracting the same value was treated as identity');
end;

{ Порядок суммирования меняет ответ, и оба ответа детерминированы. }
procedure StageSummationOrder(Carrier: TResidentCarrier);
var
  State: UInt64;
  Terms: array[0 .. 63] of Double;
  I, Bad: Integer;
  Forward_, Backward, Big: Double;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 7 + 3);
  Big := Huge[Integer(ResidentNext(State) and 3)];
  Bad := 0;

  { Одно огромное слагаемое и шестьдесят три единицы: при сложении слева
    направо единицы тонут по одной, справа налево — успевают собраться. }
  Terms[0] := Big;
  for I := 1 to High(Terms) do
    Terms[I] := 1.0;

  Forward_ := 0.0;
  for I := 0 to High(Terms) do
    Forward_ := Forward_ + Terms[I];

  Backward := 0.0;
  for I := High(Terms) downto 0 do
    Backward := Backward + Terms[I];

  { Слева направо все единицы пропали. }
  if Forward_ <> Big then Inc(Bad);

  { Справа налево они собрались в шестьдесят три и уцелели: сумма больше. }
  if Backward <= Forward_ then Inc(Bad);
  if Backward <> Big + 64.0 then Inc(Bad);

  Carrier.Feed(UInt64(Trunc(Forward_ - Big)));
  Carrier.Feed(UInt64(Trunc(Backward - Big)));
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'floatorder: summation order was changed');
end;

{ Целые числа до границы представимы точно, и арифметика над ними точна. }
procedure StageExactIntegers(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, Bad: Integer;
  Whole: Int64;
  Value, Doubled: Double;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 11 + 5);
  Bad := 0;

  for I := 1 to 24 do
    begin
      { Сорок восемь разрядов — заведомо внутри мантиссы. }
      Whole := Int64(ResidentNext(State) and $FFFFFFFFFFFF) - Int64($800000000000);
      Value := Whole;

      if Trunc(Value) <> Whole then Inc(Bad);
      if Value <> Whole then Inc(Bad);
      if (Value + 1.0) <> (Whole + 1) then Inc(Bad);
      if (Value - Value) <> 0.0 then Inc(Bad);

      { Удвоение точно: порядок вырос, мантисса та же. }
      Doubled := Value * 2.0;
      if Trunc(Doubled) <> Whole * 2 then Inc(Bad);
      if (Doubled / 2.0) <> Value then Inc(Bad);

      Carrier.Feed(UInt64(Whole));
    end;

  { На самой границе соседнее нечётное уже не представимо. }
  Value := 9007199254740992.0;
  if (Value + 1.0) <> Value then Inc(Bad);
  if (Value + 2.0) = Value then Inc(Bad);

  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'floatorder: exact integer arithmetic in floating point drifted');
end;

{ Сравнения: согласованность и отсутствие лишних вольностей. }
procedure StageComparisons(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, Bad: Integer;
  A, B: Double;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 13 + 7);
  Bad := 0;

  for I := 1 to 24 do
    begin
      A := Int64(ResidentNext(State) and $FFFFF) - $80000;
      B := Int64(ResidentNext(State) and $FFFFF) - $80000;

      { Ровно одно из трёх отношений истинно. }
      var Count: Integer := 0;
      if A < B then Inc(Count);
      if A = B then Inc(Count);
      if A > B then Inc(Count);
      if Count <> 1 then Inc(Bad);

      { Отрицание сравнения — это противоположное сравнение. }
      if (not (A < B)) <> (A >= B) then Inc(Bad);
      if (not (A = B)) <> (A <> B) then Inc(Bad);

      { Согласованность с обратным порядком. }
      if (A < B) <> (B > A) then Inc(Bad);
      if (A <= B) <> (B >= A) then Inc(Bad);

      Carrier.Feed(UInt64(Cardinal(Count)));
    end;

  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'floatorder: floating comparisons are inconsistent');
end;

initialization
  ResidentRegisterStage('floatorder-add-subtract', @StageAddSubtract);
  ResidentRegisterStage('floatorder-associativity', @StageAssociativity);
  ResidentRegisterStage('floatorder-comparisons', @StageComparisons);
  ResidentRegisterStage('floatorder-division-vs-reciprocal', @StageDivisionVersusReciprocal);
  ResidentRegisterStage('floatorder-exact-integers', @StageExactIntegers);
  ResidentRegisterStage('floatorder-summation-order', @StageSummationOrder);

end.
