unit resident_const;

{ Семейство `const` — то, что компилятор считает сам.

  Часть выражений известна на этапе сборки, и компилятор считает их заранее.
  Считает он их не той машиной, которой считал бы процессор: своей
  арифметикой, своими правилами типов, своим порядком. Пока обе арифметики
  сходятся, разницы нет; расхождение же выглядит особенно скверно — программа
  выдаёт разные ответы на одно выражение в зависимости от того, стояли ли в нём
  константы или переменные с теми же значениями.

  Отсюда способ проверки: каждое выражение считается дважды — из констант и из
  переменных, в которые положены те же числа. Переменная непрозрачна, потому
  что приходит из потока носителя, так что свернуть её компилятор не может.
  Совпадение обязательно: одно и то же выражение над одними и теми же
  значениями не имеет права зависеть от того, когда его посчитали.

  Проверяется и то, что константы вообще на месте: типизированные константы,
  константные массивы, записи и множества живут в разделе данных, и их легко
  испортить выравниванием или неверной длиной — молча, потому что читаются они
  редко. }

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

type
  TConstPoint = record
    X, Y: Int64;
    Tag: Byte;
  end;

  { Множество строится по номерам букв, а не по самим буквам: в юникодном
    режиме символ занимает два байта, а множество умеет только однобайтовый
    домен, и `set of Char` тут просто не существует. }
  TConstLetter = 0 .. 25;
  TConstLetters = set of TConstLetter;

const
  Primes: array[0 .. 9] of Int64 = (2, 3, 5, 7, 11, 13, 17, 19, 23, 29);
  Grid: array[0 .. 2, 0 .. 3] of Integer = ((1, 2, 3, 4), (5, 6, 7, 8), (9, 10, 11, 12));
  Origin: TConstPoint = (X: 100; Y: -200; Tag: 42);
  Corners: array[0 .. 1] of TConstPoint = ((X: 1; Y: 2; Tag: 3), (X: -4; Y: -5; Tag: 6));
  { Номера гласных в латинском алфавите: a, e, i, o, u. }
  Vowels: TConstLetters = [0, 4, 8, 14, 20];
  Greeting = 'abcdefghij';
  BigStep = Int64(1) shl 40;

{ Одно выражение, посчитанное компилятором и процессором. }
procedure StageFoldVersusRuntime(Carrier: TResidentCarrier);
const
  { Все ячейки одинаковы, а индекс приходит из потока: значение известно нам,
    но не выражению, в котором оно стоит. Присвоить литерал напрямую было бы
    бессмысленно — тогда обе половины проверки свернулись бы одинаково, и
    сравнивать стало бы нечего. }
  Sevens: array[0 .. 3] of Int64 = (7, 7, 7, 7);
  MinusThrees: array[0 .. 3] of Int64 = (-3, -3, -3, -3);
  Elevens: array[0 .. 3] of Int64 = (11, 11, 11, 11);
var
  State: UInt64;
  A, B, C: Int64;
  Folded, Live: Int64;
  Bad: Integer;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap);
  Bad := 0;

  A := Sevens[Integer(ResidentNext(State) and 3)];
  B := MinusThrees[Integer(ResidentNext(State) and 3)];
  C := Elevens[Integer(ResidentNext(State) and 3)];
  if (A <> 7) or (B <> -3) or (C <> 11) then
    Inc(Bad);

  Folded := 7 * 11 - (-3) * 4 + 7 div 2 + (-3) mod 4;
  Live := A * C - B * 4 + A div 2 + B mod 4;
  if Folded <> Live then Inc(Bad);

  Folded := (7 shl 5) or (11 and 6) xor (-3 and 255);
  Live := (A shl 5) or (C and 6) xor (B and 255);
  if Folded <> Live then Inc(Bad);

  Folded := Int64(7) * 1000000000 + 11;
  Live := A * 1000000000 + C;
  if Folded <> Live then Inc(Bad);

  { Сдвиг за пределы тридцати двух бит: сворачивая, легко потерять старшую
    половину. }
  Folded := BigStep + 7;
  Live := (Int64(1) shl 40) + A;
  if Folded <> Live then Inc(Bad);
  if BigStep <> 1099511627776 then Inc(Bad);

  { Деление и остаток на отрицательных — там, где правила расходятся чаще
    всего. }
  Folded := (-3) div 2;
  Live := B div 2;
  if Folded <> Live then Inc(Bad);
  Folded := (-3) mod 2;
  Live := B mod 2;
  if Folded <> Live then Inc(Bad);

  Carrier.Feed(UInt64(Live));
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'const: folded expression disagrees with the same one at run time');
end;

{ Константный массив, читаемый по переменному индексу. }
procedure StageConstArray(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, Bad: Integer;
  Sum, Mirror: Int64;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 3 + 1);
  Bad := 0;

  Sum := 0;
  for I := 0 to High(Primes) do
    Sum := Sum + Primes[I] * (I + 1);

  Mirror := 2 * 1 + 3 * 2 + 5 * 3 + 7 * 4 + 11 * 5 + 13 * 6 + 17 * 7 + 19 * 8 +
            23 * 9 + 29 * 10;
  if Sum <> Mirror then Inc(Bad);

  { Чтение по индексу, который компилятору неизвестен. }
  I := Integer(ResidentNext(State) and 7);
  if Primes[I] <> Primes[I] then Inc(Bad);
  if (Primes[I] < 2) or (Primes[I] > 29) then Inc(Bad);

  { Двумерная константа: обход по строкам и по столбцам. }
  Sum := 0;
  for I := 0 to 11 do
    Sum := Sum + Grid[I div 4, I mod 4];
  if Sum <> 78 then Inc(Bad);

  if Grid[0, 0] <> 1 then Inc(Bad);
  if Grid[2, 3] <> 12 then Inc(Bad);
  if Length(Primes) <> 10 then Inc(Bad);

  Carrier.Feed(UInt64(Sum));
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'const: constant array does not hold what was written into it');
end;

{ Константная запись и массив записей: поля разной ширины лежат рядом, и
  выравнивание легко сдвигает содержимое. }
procedure StageConstRecord(Carrier: TResidentCarrier);
var
  Bad: Integer;
  Copy_: TConstPoint;
begin
  Bad := 0;

  if Origin.X <> 100 then Inc(Bad);
  if Origin.Y <> -200 then Inc(Bad);
  if Origin.Tag <> 42 then Inc(Bad);

  if Corners[0].X <> 1 then Inc(Bad);
  if Corners[0].Y <> 2 then Inc(Bad);
  if Corners[0].Tag <> 3 then Inc(Bad);
  if Corners[1].X <> -4 then Inc(Bad);
  if Corners[1].Y <> -5 then Inc(Bad);
  if Corners[1].Tag <> 6 then Inc(Bad);

  { Копия константной записи — настоящая копия. }
  Copy_ := Origin;
  Copy_.X := Copy_.X + 1;
  if Origin.X <> 100 then Inc(Bad);
  if Copy_.X <> 101 then Inc(Bad);
  if Copy_.Y <> Origin.Y then Inc(Bad);

  Carrier.Feed(UInt64(Origin.X));
  Carrier.Feed(UInt64(Cardinal(Origin.Tag)));
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'const: constant record came out shifted');
end;

{ Константное множество: принадлежность, объединение, пересечение. }
procedure StageConstSet(Carrier: TResidentCarrier);
var
  Letter: TConstLetter;
  Bad, Count: Integer;
  Live: TConstLetters;
begin
  Bad := 0;
  Count := 0;

  for Letter := 0 to 25 do
    if Letter in Vowels then
      Inc(Count);
  if Count <> 5 then Inc(Bad);

  if not (0 in Vowels) then Inc(Bad);
  if not (20 in Vowels) then Inc(Bad);
  if 1 in Vowels then Inc(Bad);
  if 25 in Vowels then Inc(Bad);

  { Собранное на ходу множество совпадает с константным. }
  Live := [];
  Live := Live + [0] + [4] + [8] + [14] + [20];
  if Live <> Vowels then Inc(Bad);

  { Дополнение и пересечение. }
  Live := [0 .. 25] - Vowels;
  if Live * Vowels <> [] then Inc(Bad);
  if Live + Vowels <> [0 .. 25] then Inc(Bad);
  if 4 in Live then Inc(Bad);
  if not (1 in Live) then Inc(Bad);

  Carrier.Feed(UInt64(Cardinal(Count)));
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'const: constant set behaves differently from the same set built at run time');
end;

{ Константная строка: длина, символы, сравнение и склейка. }
procedure StageConstString(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, Bad: Integer;
  Live: string;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 5 + 2);
  Bad := 0;

  if Length(Greeting) <> 10 then Inc(Bad);
  if Greeting[1] <> 'a' then Inc(Bad);
  if Greeting[10] <> 'j' then Inc(Bad);

  Live := '';
  for I := 1 to 10 do
    Live := Live + Char(Ord('a') + I - 1);
  if Live <> Greeting then Inc(Bad);
  if Length(Live) <> Length(Greeting) then Inc(Bad);

  { Склейка константы с непрозрачной строкой. }
  Live := Greeting + IntToStr(Integer(ResidentNext(State) and 7));
  if Length(Live) <> 11 then Inc(Bad);
  if Copy(Live, 1, 10) <> Greeting then Inc(Bad);

  { Сравнение константы с самой собой по частям. }
  if Copy(Greeting, 1, 5) + Copy(Greeting, 6, 5) <> Greeting then Inc(Bad);

  Carrier.FeedWide(Live);
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'const: constant string is not what it was written as');
end;

{ Константные выражения в метках выбора: считает их компилятор, а сравнивает
  процессор. }
procedure StageConstLabels(Carrier: TResidentCarrier);
const
  Base = 10;
  Step = 4;
var
  I: Integer;
  ByCase, ByChain: Int64;

  function Pick(V: Integer): Integer;
  begin
    case V of
      Base: Result := 1;
      Base + Step: Result := 2;
      Base + Step * 2: Result := 3;
      Base * 2 .. Base * 2 + Step: Result := 4;
      -Base: Result := 5;
    else
      Result := 0;
    end;
  end;

begin
  ByCase := 0;
  ByChain := 0;

  for I := -15 to 30 do
    begin
      ByCase := ByCase + Pick(I);
      if I = 10 then
        ByChain := ByChain + 1
      else if I = 14 then
        ByChain := ByChain + 2
      else if I = 18 then
        ByChain := ByChain + 3
      else if (I >= 20) and (I <= 24) then
        ByChain := ByChain + 4
      else if I = -10 then
        ByChain := ByChain + 5;
    end;

  Carrier.Feed(UInt64(ByCase));
  Carrier.Claim(ByCase = ByChain, 'const: computed case labels landed on the wrong values');
end;

{ Границы типов как константы: значения, которые компилятор подставляет сам. }
procedure StageTypeBounds(Carrier: TResidentCarrier);
var
  Bad: Integer;
begin
  Bad := 0;

  if Low(Byte) <> 0 then Inc(Bad);
  if High(Byte) <> 255 then Inc(Bad);
  if Low(ShortInt) <> -128 then Inc(Bad);
  if High(ShortInt) <> 127 then Inc(Bad);
  if Low(Word) <> 0 then Inc(Bad);
  if High(Word) <> 65535 then Inc(Bad);
  if Low(SmallInt) <> -32768 then Inc(Bad);
  if High(SmallInt) <> 32767 then Inc(Bad);
  if Low(Cardinal) <> 0 then Inc(Bad);
  if High(Cardinal) <> 4294967295 then Inc(Bad);
  if Low(Integer) <> -2147483648 then Inc(Bad);
  if High(Integer) <> 2147483647 then Inc(Bad);
  if High(Int64) <> 9223372036854775807 then Inc(Bad);
  if Low(Int64) + 1 <> -9223372036854775807 then Inc(Bad);

  if SizeOf(Byte) <> 1 then Inc(Bad);
  if SizeOf(Word) <> 2 then Inc(Bad);
  if SizeOf(Cardinal) <> 4 then Inc(Bad);
  if SizeOf(Int64) <> 8 then Inc(Bad);
  if SizeOf(Pointer) <> 8 then Inc(Bad);
  if SizeOf(TConstPoint) < 17 then Inc(Bad);

  Carrier.Feed(UInt64(Cardinal(SizeOf(TConstPoint))));
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'const: a type boundary or size is not what the type promises');
end;

initialization
  ResidentRegisterStage('const-array', @StageConstArray);
  ResidentRegisterStage('const-fold-vs-runtime', @StageFoldVersusRuntime);
  ResidentRegisterStage('const-labels', @StageConstLabels);
  ResidentRegisterStage('const-record', @StageConstRecord);
  ResidentRegisterStage('const-set', @StageConstSet);
  ResidentRegisterStage('const-string', @StageConstString);
  ResidentRegisterStage('const-type-bounds', @StageTypeBounds);

end.
