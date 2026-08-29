unit resident_arraydyn;

{ Семейство `arraydyn` — динамические массивы.

  Динамический массив — не буфер, а ссылка на буфер с длиной и счётчиком
  владельцев. Отсюда всё, что здесь проверяется: присваивание массива не
  копирует данные, а заводит второе имя того же буфера; вырезка, наоборот,
  заводит новый; изменение длины сохраняет то, что уместилось, и обнуляет
  добавленное; пустой массив — это не массив нулевой длины, а отсутствие
  буфера, и наибольший индекс у него минус один.

  Каждое из этих свойств легко нарушить оптимизацией, которая приняла массив за
  обычный буфер: скопировать вместо ссылки, переиспользовать память при
  изменении длины, посчитать длину заранее. Проверяется тем, что от свойства
  следует наблюдаемо: запись через одно имя видна через другое или не видна,
  старое содержимое на месте или нет, добавленные ячейки нулевые.

  Многомерный динамический массив — массив ссылок, а не прямоугольник, поэтому
  его строки независимы, и это проверяется отдельно: подмена одной строки не
  трогает остальные. }

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

{ Изменение длины: уместившееся сохраняется, добавленное обнуляется. }
procedure StageResize(Carrier: TResidentCarrier);
var
  State: UInt64;
  Data: TArray<Int64>;
  I, Bad, Start, Grown, Cut: Integer;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap);
  Bad := 0;
  Start := 8 + Integer(ResidentNext(State) and 7);
  Grown := Start + 6;
  Cut := 4;

  SetLength(Data, Start);
  for I := 0 to High(Data) do
    Data[I] := Int64(I) * 7 + 1;

  SetLength(Data, Grown);
  if Length(Data) <> Grown then Inc(Bad);

  { Старое на месте. }
  for I := 0 to Start - 1 do
    if Data[I] <> Int64(I) * 7 + 1 then
      Inc(Bad);

  { Новое обнулено. }
  for I := Start to Grown - 1 do
    if Data[I] <> 0 then
      Inc(Bad);

  { Усечение оставляет начало нетронутым. }
  SetLength(Data, Cut);
  if Length(Data) <> Cut then Inc(Bad);
  for I := 0 to Cut - 1 do
    if Data[I] <> Int64(I) * 7 + 1 then
      Inc(Bad);

  { Наибольший индекс всегда на единицу меньше длины. }
  if High(Data) <> Cut - 1 then Inc(Bad);

  Carrier.Feed(UInt64(Cardinal(Length(Data))));
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'arraydyn: resizing lost old data or left new cells dirty');

  Data := nil;
end;

{ Присваивание заводит второе имя того же буфера. }
procedure StageReference(Carrier: TResidentCarrier);
var
  State: UInt64;
  First, Second: TArray<Int64>;
  I, Bad: Integer;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 3 + 1);
  Bad := 0;

  SetLength(First, 10);
  for I := 0 to High(First) do
    First[I] := Int64(ResidentNext(State) and $FFF);

  Second := First;
  if Length(Second) <> Length(First) then Inc(Bad);

  { Запись через одно имя видна через другое. }
  Second[0] := -111;
  if First[0] <> -111 then Inc(Bad);
  First[1] := -222;
  if Second[1] <> -222 then Inc(Bad);

  { Отпустить одно имя — буфер живёт, пока есть второе. }
  Second := nil;
  if Length(Second) <> 0 then Inc(Bad);
  if First[0] <> -111 then Inc(Bad);
  if Length(First) <> 10 then Inc(Bad);

  Carrier.Feed(UInt64(First[0]));
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'arraydyn: assignment copied the buffer instead of sharing it');

  First := nil;
end;

{ Вырезка заводит новый буфер. }
procedure StageSliceIsNew(Carrier: TResidentCarrier);
var
  State: UInt64;
  Source, Slice: TArray<Int64>;
  I, Bad: Integer;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 5 + 2);
  Bad := 0;

  SetLength(Source, 12);
  for I := 0 to High(Source) do
    Source[I] := Int64(I) + 100;

  Slice := Copy(Source, 2, 5);
  if Length(Slice) <> 5 then Inc(Bad);
  for I := 0 to High(Slice) do
    if Slice[I] <> Source[I + 2] then
      Inc(Bad);

  { Правка вырезки не видна в источнике. }
  Slice[0] := -999;
  if Source[2] = -999 then Inc(Bad);

  { Полная вырезка — тоже новый буфер. }
  Slice := Copy(Source);
  if Length(Slice) <> Length(Source) then Inc(Bad);
  Slice[3] := -777;
  if Source[3] = -777 then Inc(Bad);

  { Вырезка за концом даёт то, что осталось. }
  Slice := Copy(Source, 10, 100);
  if Length(Slice) <> 2 then Inc(Bad);
  Slice := Copy(Source, 100, 5);
  if Length(Slice) <> 0 then Inc(Bad);

  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'arraydyn: slice shares memory with its source');

  Source := nil;
  Slice := nil;
end;

{ Пустой массив: длина ноль, наибольший индекс минус один, обращений нет. }
procedure StageEmpty(Carrier: TResidentCarrier);
var
  Empty, Made: TArray<Int64>;
  Bad, Visits, I: Integer;
begin
  Bad := 0;
  Visits := 0;

  if Length(Empty) <> 0 then Inc(Bad);
  if High(Empty) <> -1 then Inc(Bad);
  if Empty <> nil then Inc(Bad);

  { Цикл по пустому массиву не выполняется ни разу. }
  for I := 0 to High(Empty) do
    Inc(Visits);
  if Visits <> 0 then Inc(Bad);

  for var Item in Empty do
    Inc(Visits);
  if Visits <> 0 then Inc(Bad);

  { Явно заведённый нулевой длины — то же самое. }
  SetLength(Made, 0);
  if Length(Made) <> 0 then Inc(Bad);
  if High(Made) <> -1 then Inc(Bad);

  { Вырезка пустого пуста. }
  if Length(Copy(Empty, 0, 5)) <> 0 then Inc(Bad);

  { Заводится и опустошается без потерь. }
  SetLength(Made, 4);
  if Length(Made) <> 4 then Inc(Bad);
  SetLength(Made, 0);
  if Length(Made) <> 0 then Inc(Bad);
  if High(Made) <> -1 then Inc(Bad);

  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'arraydyn: empty array does not behave as empty');
end;

{ Многомерный массив — массив ссылок: строки независимы. }
procedure StageMultiDimensional(Carrier: TResidentCarrier);
var
  State: UInt64;
  Grid: TArray<TArray<Int64>>;
  Row: TArray<Int64>;
  I, J, Bad: Integer;
  Sum, Mirror: Int64;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 7 + 3);
  Bad := 0;

  SetLength(Grid, 5);
  for I := 0 to High(Grid) do
    begin
      SetLength(Grid[I], 4 + I);
      for J := 0 to High(Grid[I]) do
        Grid[I][J] := Int64(I) * 100 + J;
    end;

  { Строки разной длины — это законно, потому что каждая своя. }
  for I := 0 to High(Grid) do
    if Length(Grid[I]) <> 4 + I then
      Inc(Bad);

  Sum := 0;
  for I := 0 to High(Grid) do
    for J := 0 to High(Grid[I]) do
      Sum := Sum + Grid[I][J];

  Mirror := 0;
  for I := 0 to 4 do
    for J := 0 to 3 + I do
      Mirror := Mirror + Int64(I) * 100 + J;

  if Sum <> Mirror then Inc(Bad);

  { Подмена одной строки не трогает остальные. }
  Row := Grid[2];
  Row[0] := -555;
  if Grid[2][0] <> -555 then Inc(Bad);
  if Grid[1][0] <> 100 then Inc(Bad);
  if Grid[3][0] <> 300 then Inc(Bad);

  SetLength(Grid[2], 2);
  if Length(Grid[2]) <> 2 then Inc(Bad);
  if Length(Grid[1]) <> 5 then Inc(Bad);
  if Length(Grid[3]) <> 7 then Inc(Bad);

  Carrier.Feed(UInt64(Sum));
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'arraydyn: rows of a jagged array are not independent');

  Grid := nil;
  Row := nil;
end;

{ Массив управляемых значений: строки внутри живут и умирают вместе с
  ячейками. }
procedure StageManagedElements(Carrier: TResidentCarrier);
var
  State: UInt64;
  Texts: TArray<string>;
  I, Bad, Len: Integer;
  Total: Integer;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 11 + 5);
  Bad := 0;
  Len := 6 + Integer(ResidentNext(State) and 3);

  SetLength(Texts, Len);
  for I := 0 to High(Texts) do
    Texts[I] := StringOfChar('a', I + 1);

  Total := 0;
  for I := 0 to High(Texts) do
    begin
      if Length(Texts[I]) <> I + 1 then
        Inc(Bad);
      Total := Total + Length(Texts[I]);
    end;
  if Total <> Len * (Len + 1) div 2 then Inc(Bad);

  { Рост: старые строки на месте, новые пусты. }
  SetLength(Texts, Len + 3);
  for I := 0 to Len - 1 do
    if Length(Texts[I]) <> I + 1 then
      Inc(Bad);
  for I := Len to Len + 2 do
    if Texts[I] <> '' then
      Inc(Bad);

  { Усечение: оставшиеся целы. }
  SetLength(Texts, 3);
  for I := 0 to 2 do
    if Length(Texts[I]) <> I + 1 then
      Inc(Bad);

  Carrier.Feed(UInt64(Cardinal(Total)));
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'arraydyn: managed elements did not survive resizing');

  Texts := nil;
end;

initialization
  ResidentRegisterStage('arraydyn-empty', @StageEmpty);
  ResidentRegisterStage('arraydyn-managed-elements', @StageManagedElements);
  ResidentRegisterStage('arraydyn-multidimensional', @StageMultiDimensional);
  ResidentRegisterStage('arraydyn-reference', @StageReference);
  ResidentRegisterStage('arraydyn-resize', @StageResize);
  ResidentRegisterStage('arraydyn-slice-is-new', @StageSliceIsNew);

end.
