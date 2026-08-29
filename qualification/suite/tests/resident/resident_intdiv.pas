unit resident_intdiv;

{ Семейство `intdiv` — целочисленное деление и остаток.

  Деление — самая дорогая целочисленная операция, поэтому компилятор её почти
  не выполняет: деление на константу он заменяет умножением на заранее
  подобранное число со сдвигом, деление на степень двойки — сдвигом с
  поправкой. Обе замены точны на всём домене, если подобраны верно, и врут на
  краях, если нет. Врут при этом тихо: частное отличается на единицу, остаток
  съезжает вместе с ним, а сумма и близко похожа на правду.

  Отдельная тонкость — знак. Деление в Паскале усекает к нулю, поэтому
  `-7 div 2` равно минус трём, а не минус четырём, и заменять его сдвигом без
  поправки нельзя. Сам сдвиг тут не оракул и в сравнениях для отрицательных не
  участвует: `shr` в Delphi логический, он тащит нули в старший разряд и на
  отрицательном делимом даёт не «деление вниз», а огромное положительное
  число. Усечение к нулю проверяется тем, что от него однозначно следует:
  делимые, отличающиеся только знаком, дают частные и остатки, отличающиеся
  только знаком.

  Проверяется тождеством, а не таблицей ответов: частное, умноженное на
  делитель, плюс остаток обязано дать делимое; остаток обязан быть меньше
  делителя по модулю и нести знак делимого. Эти три условия задают деление
  однозначно, поэтому им достаточно.

  Делимое ноль и делитель `-1` вместе с наименьшим значением типа сюда не
  попадают намеренно: частное там не представимо, и процессор отвечает на это
  ловушкой, а не числом. }

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

{ Деление на каждую константу от двух до семнадцати, на обоих знаках делимого.
  Именно здесь компилятор подставляет магическое умножение. }
procedure StageByConstants(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, D, Bad: Integer;
  Value, Q, R: Int64;

  procedure Check(A, B: Int64);
  var
    LocalQ, LocalR: Int64;
  begin
    LocalQ := A div B;
    LocalR := A mod B;
    if LocalQ * B + LocalR <> A then
      Inc(Bad);
    if Abs(LocalR) >= Abs(B) then
      Inc(Bad);
    if (LocalR <> 0) and ((LocalR < 0) <> (A < 0)) then
      Inc(Bad);
  end;

begin
  State := Carrier.Seed xor UInt64(Carrier.Lap);
  Bad := 0;

  for I := 1 to 8 do
    begin
      Value := Int64(ResidentNext(State) and $FFFFFFF) - $8000000;

      { Константный делитель — тот случай, ради которого всё затевалось. }
      Check(Value, 2);  Check(Value, 3);  Check(Value, 4);  Check(Value, 5);
      Check(Value, 6);  Check(Value, 7);  Check(Value, 8);  Check(Value, 9);
      Check(Value, 10); Check(Value, 11); Check(Value, 12); Check(Value, 13);
      Check(Value, 16); Check(Value, 17); Check(Value, 100); Check(Value, 1000);

      { Те же делители с обратным знаком. }
      Check(Value, -2); Check(Value, -3); Check(Value, -7); Check(Value, -8);
      Check(Value, -10); Check(Value, -100);

      Carrier.Feed(UInt64(Value));
    end;

  { Делитель из потока: заменить нечем, считается по-настоящему. }
  for I := 1 to 8 do
    begin
      Value := Int64(ResidentNext(State) and $FFFFFFF) - $8000000;
      D := 1 + Integer(ResidentNext(State) and 255);
      Check(Value, D);
      Check(Value, -D);
      Q := Value div D;
      R := Value mod D;
      Carrier.Feed(UInt64(Q));
      Carrier.Feed(UInt64(R));
    end;

  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'intdiv: division by a constant broke the div/mod contract');
end;

{ Степени двойки: деление усекает к нулю, сдвиг округляет вниз. На
  положительных они совпадают, на отрицательных — нет, и подменять одно
  другим нельзя. }
procedure StagePowerOfTwo(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, K, Bad: Integer;
  Positive, Negative, Divisor: Int64;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 3 + 1);
  Bad := 0;

  for I := 1 to 8 do
    begin
      Positive := Int64(ResidentNext(State) and $FFFFFF) + 1;
      Negative := -Positive;

      for K := 1 to 10 do
        begin
          Divisor := Int64(1) shl K;

          { На положительном делимом деление и логический сдвиг совпадают. }
          if (Positive div Divisor) <> (Positive shr K) then
            Inc(Bad);

          { Усечение к нулю: смена знака делимого меняет знак частного и
            остатка, и больше ничего. Округление вниз это тождество ломает. }
          if (Negative div Divisor) <> -(Positive div Divisor) then
            Inc(Bad);
          if (Negative mod Divisor) <> -(Positive mod Divisor) then
            Inc(Bad);

          { Договор при этом держится с обеих сторон. }
          if (Negative div Divisor) * Divisor + (Negative mod Divisor) <> Negative then
            Inc(Bad);
          if (Positive div Divisor) * Divisor + (Positive mod Divisor) <> Positive then
            Inc(Bad);
        end;

      Carrier.Feed(UInt64(Positive));
    end;

  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'intdiv: division by a power of two was replaced by a bare shift');
end;

{ Беззнаковое деление: поправка на знак здесь не нужна вовсе, а домен вдвое
  шире, и старший бит легко принять за знак. }
procedure StageUnsigned(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, Bad: Integer;
  Value, Q, R: UInt64;

  procedure Check(A, B: UInt64);
  begin
    if (A div B) * B + (A mod B) <> A then
      Inc(Bad);
    if (A mod B) >= B then
      Inc(Bad);
  end;

begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 5 + 2);
  Bad := 0;

  for I := 1 to 8 do
    begin
      { Старший бит установлен: как знаковое это число отрицательно. }
      Value := ResidentNext(State) or UInt64($8000000000000000);

      Check(Value, 2); Check(Value, 3); Check(Value, 7);
      Check(Value, 10); Check(Value, 256); Check(Value, 1000);

      { Деление на степень двойки в беззнаковом домене — ровно сдвиг. }
      if (Value div 2) <> (Value shr 1) then Inc(Bad);
      if (Value div 256) <> (Value shr 8) then Inc(Bad);

      Q := Value div 10;
      R := Value mod 10;
      if Q * 10 + R <> Value then Inc(Bad);
      if R > 9 then Inc(Bad);

      Carrier.Feed(Value);
      Carrier.Feed(Q);
    end;

  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'intdiv: unsigned division treated the top bit as a sign');
end;

{ Одно и то же деление, где делитель то константа, то переменная с тем же
  значением. Замена на умножение не имеет права изменить ответ. }
procedure StageConstantVersusVariable(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, Bad: Integer;
  Value, ByConst, ByVar: Int64;
  Three, Seven, Ten: Int64;
const
  Threes: array[0 .. 3] of Int64 = (3, 3, 3, 3);
  Sevens: array[0 .. 3] of Int64 = (7, 7, 7, 7);
  Tens: array[0 .. 3] of Int64 = (10, 10, 10, 10);
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 7 + 3);
  Bad := 0;

  { Делитель непрозрачен для компилятора, но известен нам. }
  Three := Threes[Integer(ResidentNext(State) and 3)];
  Seven := Sevens[Integer(ResidentNext(State) and 3)];
  Ten := Tens[Integer(ResidentNext(State) and 3)];
  if (Three <> 3) or (Seven <> 7) or (Ten <> 10) then
    Inc(Bad);

  for I := 1 to 12 do
    begin
      Value := Int64(ResidentNext(State) and $FFFFFFF) - $8000000;

      ByConst := Value div 3;
      ByVar := Value div Three;
      if ByConst <> ByVar then Inc(Bad);
      if (Value mod 3) <> (Value mod Three) then Inc(Bad);

      ByConst := Value div 7;
      ByVar := Value div Seven;
      if ByConst <> ByVar then Inc(Bad);
      if (Value mod 7) <> (Value mod Seven) then Inc(Bad);

      ByConst := Value div 10;
      ByVar := Value div Ten;
      if ByConst <> ByVar then Inc(Bad);
      if (Value mod 10) <> (Value mod Ten) then Inc(Bad);

      Carrier.Feed(UInt64(ByConst));
    end;

  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'intdiv: dividing by a constant differs from dividing by a variable');
end;

{ Деление в узких типах: результат обязан считаться в типе выражения, а не в
  чём-то шире или уже. }
procedure StageNarrowTypes(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, Bad: Integer;
  AsByte: Byte;
  AsShort: ShortInt;
  AsWord: Word;
  AsSmall: SmallInt;
  AsInt: Integer;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 11 + 5);
  Bad := 0;

  for I := 1 to 12 do
    begin
      AsByte := Byte(ResidentNext(State));
      AsShort := ShortInt(ResidentNext(State));
      AsWord := Word(ResidentNext(State));
      AsSmall := SmallInt(ResidentNext(State));
      AsInt := Integer(ResidentNext(State));

      if (AsByte div 3) * 3 + (AsByte mod 3) <> AsByte then Inc(Bad);
      if (AsWord div 7) * 7 + (AsWord mod 7) <> AsWord then Inc(Bad);
      if Int64(AsShort div 3) * 3 + (AsShort mod 3) <> AsShort then Inc(Bad);
      if Int64(AsSmall div 7) * 7 + (AsSmall mod 7) <> AsSmall then Inc(Bad);
      if Int64(AsInt div 11) * 11 + (AsInt mod 11) <> AsInt then Inc(Bad);

      { Узкое знаковое усекается к нулю так же, как широкое. Унарный минус
        расширяет операнд до целого, поэтому наименьшее значение типа здесь
        не переполняется и оговорок не требует. }
      if (AsSmall div 4) <> -((-AsSmall) div 4) then
        Inc(Bad);
      if (AsSmall mod 4) <> -((-AsSmall) mod 4) then
        Inc(Bad);

      Carrier.Feed(UInt64(Word(AsSmall)));
    end;

  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'intdiv: division in a narrow type left its type');
end;

{ Остаток как признак делимости: он же чаще всего и заменяется на проверку
  битов. }
procedure StageDivisibility(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, Bad, ByMod, ByBits: Integer;
  Value: Int64;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 13 + 7);
  Bad := 0;
  ByMod := 0;
  ByBits := 0;

  for I := 1 to 64 do
    begin
      Value := Int64(ResidentNext(State) and $FFFFF) - $80000;

      { Кратность степени двойки — это нули в младших битах, на любом знаке. }
      if (Value mod 8 = 0) <> ((Value and 7) = 0) then
        Inc(Bad);
      if (Value mod 2 = 0) <> ((Value and 1) = 0) then
        Inc(Bad);

      if (Value mod 8) = 0 then
        Inc(ByMod);
      if (Value and 7) = 0 then
        Inc(ByBits);

      { Кратность трём битами не проверяется — только остатком. }
      if (Value mod 3 = 0) and ((Value div 3) * 3 <> Value) then
        Inc(Bad);
    end;

  Carrier.Feed(UInt64(Cardinal(ByMod)));
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(ByMod = ByBits, 'intdiv: remainder and bit test disagree about divisibility');
  Carrier.Claim(Bad = 0, 'intdiv: divisibility check is wrong');
end;

initialization
  ResidentRegisterStage('intdiv-by-constants', @StageByConstants);
  ResidentRegisterStage('intdiv-const-vs-variable', @StageConstantVersusVariable);
  ResidentRegisterStage('intdiv-divisibility', @StageDivisibility);
  ResidentRegisterStage('intdiv-narrow-types', @StageNarrowTypes);
  ResidentRegisterStage('intdiv-power-of-two', @StagePowerOfTwo);
  ResidentRegisterStage('intdiv-unsigned', @StageUnsigned);

end.
