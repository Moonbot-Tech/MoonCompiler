unit resident_shape;

{ Семейство `shape` — представление: чем значение является помимо величины.

  Множество, перечисление, поддиапазон, вариантная запись, логический тип
  разной ширины — всё это способы уложить смысл в биты. Уложить можно
  по-разному, но договор один, и здесь проверяется именно он: сколько байт
  занимает множество с заданным диапазоном, где лежит его последний элемент,
  что даёт `Ord` у перечисления с дырами, как выглядит логическое значение
  шириной в четыре байта.

  Множества особенно ценны тем, что их хвост — самое тихое место в программе:
  элемент за краем занятого байта не виден никаким обычным вычислением, и
  ошибка там годами не всплывает. Поэтому диапазоны здесь взяты так, чтобы
  край байта и край множества приходились на разные места.

  Переинтерпретация через вариантную запись — законный приём Паскаля, а не
  лазейка: наложение полей объявлено, ширины совпадают, порядок байт на этой
  платформе фиксирован. }

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch anonymousfunctions}
  {$modeswitch functionreferences}
  {$modeswitch INLINEVARS}
{$endif}
{$Q-}{$R-}

interface

uses
  SysUtils, Classes, Variants, TypInfo, Generics.Collections, resident_core;

implementation

type
  { Плотное перечисление: значения идут подряд от нуля. }
  TResidentColour = (rcRed, rcGreen, rcBlue, rcAmber, rcViolet);

  { Дырявое: значения заданы вручную, и ширина типа обязана вырасти под них. }
  TResidentCode = (rkNone = 0, rkLow = 1, rkMid = 200, rkHigh = 60000);

  TResidentColours = set of TResidentColour;

  { Множество, чей край не совпадает с краем байта: последний элемент лежит в
    хвосте, куда обычные вычисления не заглядывают. }
  TResidentTail = set of 200 .. 255;
  TResidentWide = set of 0 .. 255;
  TResidentOffset = set of 3 .. 66;

  TResidentSmall = 10 .. 20;

  { Вариантная запись: наложение объявлено явно, ширины совпадают. }
  TResidentOverlay = record
    case Integer of
      0: (Whole: Int64);
      1: (Halves: array[0 .. 1] of Cardinal);
      2: (Bytes: array[0 .. 7] of Byte);
      3: (Narrow: array[0 .. 3] of Word);
  end;

  TResidentFlags = record
    case Boolean of
      False: (Plain: Boolean);
      True: (Wide: LongBool);
  end;

{ Открытый массив: длина приезжает вместе со значением, а не с типом. }
function SumOpen(const Values: array of Int64): Int64;
var
  I: Integer;
begin
  Result := 0;
  for I := Low(Values) to High(Values) do
    Result := Result + Values[I];
end;

function CountOpen(const Values: array of Int64): Integer;
begin
  Result := Length(Values);
end;

{ Массив констант: каждый элемент везёт с собой свой тип. }
function DescribeConst(const Values: array of const): Int64;
var
  I: Integer;
begin
  Result := 0;
  for I := Low(Values) to High(Values) do
    Result := Result * 10 + Values[I].VType;
end;

{ Перечисление: порядок, границы и соседи. }
procedure StageEnumOrder(Carrier: TResidentCarrier);
var
  Colour: TResidentColour;
  Seen: Integer;
begin
  Carrier.Feed(UInt64(Cardinal(Ord(Low(TResidentColour)))));
  Carrier.Feed(UInt64(Cardinal(Ord(High(TResidentColour)))));
  Carrier.Feed(UInt64(Cardinal(SizeOf(TResidentColour))));

  Seen := 0;
  for Colour := Low(TResidentColour) to High(TResidentColour) do
  begin
    Carrier.Feed(UInt64(Cardinal(Ord(Colour))));
    Inc(Seen);
  end;
  Carrier.Feed(UInt64(Cardinal(Seen)));

  Carrier.Feed(UInt64(Cardinal(Ord(Succ(rcRed)))));
  Carrier.Feed(UInt64(Cardinal(Ord(Pred(rcBlue)))));
  Carrier.Feed(UInt64(Ord(rcRed < rcBlue)));
  Carrier.Feed(UInt64(Cardinal(Ord(TResidentColour(Carrier.Lap mod 5)))));

  { Имя значения — тоже часть типа, а не украшение. }
  Carrier.FeedWide(GetEnumName(TypeInfo(TResidentColour), Ord(rcAmber)));
  Carrier.Feed(UInt64(Cardinal(GetEnumValue(TypeInfo(TResidentColour),
                                            'rcViolet'))));
end;

{ Перечисление с дырами: ширина типа обязана вместить самое большое значение. }
procedure StageEnumSparse(Carrier: TResidentCarrier);
var
  Code: TResidentCode;
begin
  Carrier.Feed(UInt64(Cardinal(SizeOf(TResidentCode))));
  Carrier.Feed(UInt64(Cardinal(Ord(rkNone))));
  Carrier.Feed(UInt64(Cardinal(Ord(rkLow))));
  Carrier.Feed(UInt64(Cardinal(Ord(rkMid))));
  Carrier.Feed(UInt64(Cardinal(Ord(rkHigh))));
  Carrier.Feed(UInt64(Cardinal(Ord(Low(TResidentCode)))));
  Carrier.Feed(UInt64(Cardinal(Ord(High(TResidentCode)))));
  Carrier.Feed(UInt64(Ord(SizeOf(TResidentCode) >= 2)));

  Code := rkMid;
  Carrier.Feed(UInt64(Cardinal(Ord(Code))));
  Code := rkHigh;
  Carrier.Feed(UInt64(Cardinal(Ord(Code))));
  Carrier.Feed(UInt64(Ord(Code > rkMid)));
end;

{ Множество: объединение, пересечение, разность и принадлежность. }
procedure StageSetOps(Carrier: TResidentCarrier);
var
  Left, Right, Both: TResidentColours;
begin
  Left := [rcRed, rcGreen];
  Right := [rcGreen, rcBlue];

  Both := Left + Right;
  Carrier.Feed(UInt64(Ord(rcRed in Both)));
  Carrier.Feed(UInt64(Ord(rcBlue in Both)));
  Carrier.Feed(UInt64(Ord(rcAmber in Both)));

  Both := Left * Right;
  Carrier.Feed(UInt64(Ord(rcGreen in Both)));
  Carrier.Feed(UInt64(Ord(rcRed in Both)));

  Both := Left - Right;
  Carrier.Feed(UInt64(Ord(rcRed in Both)));
  Carrier.Feed(UInt64(Ord(rcGreen in Both)));

  Carrier.Feed(UInt64(Ord(Left <= Left + Right)));
  Carrier.Feed(UInt64(Ord(Left >= Left * Right)));
  Carrier.Feed(UInt64(Ord(Left = [rcRed, rcGreen])));
  Carrier.Feed(UInt64(Ord([] <= Left)));
  Carrier.Feed(UInt64(Cardinal(SizeOf(TResidentColours))));

  { Включение и исключение по одному. }
  Both := Left;
  Include(Both, rcViolet);
  Carrier.Feed(UInt64(Ord(rcViolet in Both)));
  Exclude(Both, rcRed);
  Carrier.Feed(UInt64(Ord(rcRed in Both)));
end;

{ Множество со сдвинутым краем: последний элемент лежит в хвосте байта, куда
  обычные вычисления не заглядывают. }
procedure StageSetTail(Carrier: TResidentCarrier);
var
  Tail: TResidentTail;
  Wide: TResidentWide;
  Offset: TResidentOffset;
  I, Seen: Integer;
begin
  Carrier.Feed(UInt64(Cardinal(SizeOf(TResidentTail))));
  Carrier.Feed(UInt64(Cardinal(SizeOf(TResidentWide))));
  Carrier.Feed(UInt64(Cardinal(SizeOf(TResidentOffset))));

  { Границы множества обязаны быть достижимы обе. }
  Tail := [200, 255];
  Carrier.Feed(UInt64(Ord(200 in Tail)));
  Carrier.Feed(UInt64(Ord(255 in Tail)));
  Carrier.Feed(UInt64(Ord(201 in Tail)));
  Carrier.Feed(UInt64(Ord(254 in Tail)));

  { Весь диапазон целиком: ни один элемент не имеет права потеряться. }
  Tail := [200 .. 255];
  Seen := 0;
  for I := 200 to 255 do
    if I in Tail then
      Inc(Seen);
  Carrier.Feed(UInt64(Cardinal(Seen)));
  Carrier.Feed(UInt64(Ord(Seen = 56)));

  Exclude(Tail, 255);
  Carrier.Feed(UInt64(Ord(255 in Tail)));
  Carrier.Feed(UInt64(Ord(254 in Tail)));

  Wide := [0, 1, 127, 128, 254, 255];
  Carrier.Feed(UInt64(Ord(0 in Wide)));
  Carrier.Feed(UInt64(Ord(127 in Wide)));
  Carrier.Feed(UInt64(Ord(128 in Wide)));
  Carrier.Feed(UInt64(Ord(255 in Wide)));
  Carrier.Feed(UInt64(Ord(2 in Wide)));

  { Множество, начинающееся не с нуля и не с края байта. }
  Offset := [3, 8, 65, 66];
  Carrier.Feed(UInt64(Ord(3 in Offset)));
  Carrier.Feed(UInt64(Ord(66 in Offset)));
  Carrier.Feed(UInt64(Ord(4 in Offset)));
  Seen := 0;
  for I := 3 to 66 do
    if I in Offset then
      Inc(Seen);
  Carrier.Feed(UInt64(Cardinal(Seen)));
end;

{ Множество, собранное на ходу: содержимое зависит от оборота, а проверка —
  от содержимого. }
procedure StageSetBuilt(Carrier: TResidentCarrier);
var
  Wide: TResidentWide;
  I, Seen, Step: Integer;
begin
  Step := 3 + (Carrier.Lap mod 5);
  Wide := [];
  I := 0;
  while I <= 255 do
  begin
    Include(Wide, I);
    Inc(I, Step);
  end;

  Seen := 0;
  for I := 0 to 255 do
    if I in Wide then
      Inc(Seen);
  Carrier.Feed(UInt64(Cardinal(Seen)));
  Carrier.Feed(UInt64(Cardinal(Step)));
  Carrier.Feed(UInt64(Ord(0 in Wide)));
  Carrier.Feed(UInt64(Ord((255 in Wide) = (255 mod Step = 0))));

  { Дополнение: каждый элемент обязан быть ровно в одной половине. }
  Seen := 0;
  for I := 0 to 255 do
    if (I in Wide) = ((I mod Step) = 0) then
      Inc(Seen);
  Carrier.Feed(UInt64(Cardinal(Seen)));
  Carrier.Feed(UInt64(Ord(Seen = 256)));
end;

{ Логические типы разной ширины: у каждого свой размер и своё представление
  истины. }
procedure StageBoolWidths(Carrier: TResidentCarrier);
var
  Plain: Boolean;
  AsByte: ByteBool;
  AsWord: WordBool;
  AsLong: LongBool;
  Flags: TResidentFlags;
begin
  Carrier.Feed(UInt64(Cardinal(SizeOf(Boolean))));
  Carrier.Feed(UInt64(Cardinal(SizeOf(ByteBool))));
  Carrier.Feed(UInt64(Cardinal(SizeOf(WordBool))));
  Carrier.Feed(UInt64(Cardinal(SizeOf(LongBool))));

  Plain := True;
  AsByte := True;
  AsWord := True;
  AsLong := True;
  { Наружу идёт нормализованная истина, а не  широкого логического типа.
    Причина: истина в широком типе представлена не единицей, и  от такого
    значения выходит за домен Boolean — там язык ничего не обещает, и сами
    компиляторы отвечают по-разному в зависимости от того, куда результат
    расширяется. Проверять надо смысл («истинно ли»), а представление — через
    байты, где всё определено. }
  Carrier.Feed(UInt64(Cardinal(Ord(Plain))));
  Carrier.Feed(UInt64(Ord(AsByte <> False)));
  Carrier.Feed(UInt64(Ord(AsWord <> False)));
  Carrier.Feed(UInt64(Ord(AsLong <> False)));
  Carrier.Feed(UInt64(PByte(@AsByte)^));
  Carrier.Feed(UInt64(PWord(@AsWord)^));
  Carrier.Feed(UInt64(PCardinal(@AsLong)^));

  Plain := False;
  AsLong := False;
  Carrier.Feed(UInt64(Cardinal(Ord(Plain))));
  Carrier.Feed(UInt64(Ord(AsLong <> False)));
  Carrier.Feed(UInt64(PCardinal(@AsLong)^));

  { Наложение: логическое значение шириной в четыре байта поверх однобайтового.
    Наружу идут БАЙТЫ, а не Ord узкого поля: широкая истина кладёт в байт не
    единицу, и Ord от такого значения — уже вне домена Boolean, где язык ничего
    не обещает. Байт же определён точно, и именно он отвечает на вопрос, что
    легло по этому адресу. }
  Flags.Wide := True;
  Carrier.Feed(UInt64(PByte(@Flags)^));
  Carrier.Feed(UInt64(Ord(PByte(@Flags)^ <> 0)));
  Flags.Wide := False;
  Carrier.Feed(UInt64(PByte(@Flags)^));
  Carrier.Feed(UInt64(Ord(PByte(@Flags)^ <> 0)));
  Carrier.Feed(UInt64(Cardinal(SizeOf(Flags))));
end;

{ Наложение целого и байтов: порядок байт на этой платформе фиксирован, поэтому
  разложение обязано повторяться. }
procedure StageOverlay(Carrier: TResidentCarrier);
var
  Value: TResidentOverlay;
  I: Integer;
  Rebuilt: UInt64;
begin
  Value.Whole := Carrier.Tag.Wide;
  Carrier.Feed(UInt64(Cardinal(SizeOf(Value))));
  for I := 0 to 7 do
    Carrier.Feed(UInt64(Value.Bytes[I]));
  Carrier.Feed(UInt64(Value.Halves[0]));
  Carrier.Feed(UInt64(Value.Halves[1]));

  { Собранное обратно из байтов обязано совпасть с исходным. }
  Rebuilt := 0;
  for I := 7 downto 0 do
    Rebuilt := (Rebuilt shl 8) or UInt64(Value.Bytes[I]);
  Carrier.Feed(UInt64(Ord(Rebuilt = UInt64(Value.Whole))));

  { Запись через узкое поле видна широкому. }
  Value.Bytes[0] := $FF;
  Carrier.Feed(UInt64(Value.Whole and $FF));
  Value.Narrow[0] := $1234;
  Carrier.Feed(UInt64(Value.Whole and $FFFF));
  Carrier.Feed(UInt64(Value.Bytes[0]));
  Carrier.Feed(UInt64(Value.Bytes[1]));
end;

{ Поддиапазон: своя ширина и свои границы, но значения — обычные целые. }
procedure StageSubrange(Carrier: TResidentCarrier);
var
  Small: TResidentSmall;
  I, Seen: Integer;
begin
  Carrier.Feed(UInt64(Cardinal(SizeOf(TResidentSmall))));
  Carrier.Feed(UInt64(Cardinal(Low(TResidentSmall))));
  Carrier.Feed(UInt64(Cardinal(High(TResidentSmall))));

  Seen := 0;
  for Small := Low(TResidentSmall) to High(TResidentSmall) do
  begin
    Inc(Seen);
    if Small = 15 then
      Carrier.Feed(UInt64(Cardinal(Small)));
  end;
  Carrier.Feed(UInt64(Cardinal(Seen)));
  Carrier.Feed(UInt64(Ord(Seen = 11)));

  Small := TResidentSmall(10 + (Carrier.Lap mod 11));
  Carrier.Feed(UInt64(Cardinal(Small)));
  I := Small;
  Carrier.Feed(UInt64(Cardinal(I)));
end;

{ Значение уезжает в вариант и возвращается: тип обязан доехать вместе с ним. }
procedure StageVariantTransit(Carrier: TResidentCarrier);
var
  Box: Variant;
  Back: Int64;
  Text: string;
begin
  Box := Carrier.Tag.Wide;
  Back := Box;
  Carrier.Feed(UInt64(Back));
  Carrier.Feed(UInt64(Ord(Back = Carrier.Tag.Wide)));
  Carrier.Feed(UInt64(Cardinal(VarType(Box))));

  Box := Carrier.Text.Wide;
  Text := Box;
  Carrier.Feed(UInt64(Cardinal(Length(Text))));
  Carrier.Feed(UInt64(Ord(Text = Carrier.Text.Wide)));
  Carrier.Feed(UInt64(Cardinal(VarType(Box))));

  Box := Carrier.Tag.Narrow;
  Carrier.Feed(UInt64(Word(SmallInt(Box))));
  Carrier.Feed(UInt64(Cardinal(VarType(Box))));

  Box := True;
  Carrier.Feed(UInt64(Ord(Boolean(Box))));
  Carrier.Feed(UInt64(Cardinal(VarType(Box))));
end;

{ Пустой и неопределённый варианты — разные состояния, и путать их нельзя. }
procedure StageVariantStates(Carrier: TResidentCarrier);
var
  Box: Variant;
begin
  Box := Unassigned;
  Carrier.Feed(UInt64(Ord(VarIsEmpty(Box))));
  Carrier.Feed(UInt64(Ord(VarIsNull(Box))));
  Carrier.Feed(UInt64(Cardinal(VarType(Box))));

  Box := Null;
  Carrier.Feed(UInt64(Ord(VarIsEmpty(Box))));
  Carrier.Feed(UInt64(Ord(VarIsNull(Box))));
  Carrier.Feed(UInt64(Cardinal(VarType(Box))));

  Box := 0;
  Carrier.Feed(UInt64(Ord(VarIsEmpty(Box))));
  Carrier.Feed(UInt64(Ord(VarIsNull(Box))));
  Carrier.Feed(UInt64(Ord(VarIsNumeric(Box))));

  Box := Carrier.Text.Wide;
  Carrier.Feed(UInt64(Ord(VarIsStr(Box))));
  Carrier.Feed(UInt64(Ord(VarIsNumeric(Box))));

  VarClear(Box);
  Carrier.Feed(UInt64(Ord(VarIsEmpty(Box))));
end;

{ Вариантный массив: границы и содержимое обязаны пережить переезд. }
procedure StageVariantArray(Carrier: TResidentCarrier);
var
  Box: Variant;
  I, Room: Integer;
  Sum: Int64;
begin
  Room := 4 + (Carrier.Lap mod 8);
  { Тип элемента взят такой, какой умеют оба компилятора: наш заводит массив и
    с varInt64, Delphi на нём отказывает. Расхождение отмечено к сведению, но
    сама стадия проверяет не его, а работу вариантного массива. }
  Box := VarArrayCreate([0, Room - 1], varInteger);
  Carrier.Feed(UInt64(Ord(VarIsArray(Box))));
  Carrier.Feed(UInt64(Cardinal(VarArrayLowBound(Box, 1))));
  Carrier.Feed(UInt64(Cardinal(VarArrayHighBound(Box, 1))));

  for I := 0 to Room - 1 do
    Box[I] := Integer((Carrier.Tag.Wide + I) and $FFFF);
  Sum := 0;
  for I := 0 to Room - 1 do
    Sum := Sum + Int64(Integer(Box[I]));
  Carrier.Feed(UInt64(Sum));

  { Пересборка массива обязана сохранить голову. }
  VarArrayRedim(Box, Room * 2 - 1);
  Carrier.Feed(UInt64(Cardinal(VarArrayHighBound(Box, 1))));
  Carrier.Feed(UInt64(Int64(Integer(Box[0]))));
  Carrier.Feed(UInt64(Int64(Integer(Box[Room - 1]))));

  Box := Unassigned;
  Carrier.Feed(UInt64(Ord(VarIsArray(Box))));
end;

{ Открытый массив: длина приезжает со значением, а не с типом. }
procedure StageOpenArray(Carrier: TResidentCarrier);
var
  Data: System.TArray<Int64>;
  Fixed: array[0 .. 3] of Int64;
  I: Integer;
begin
  SetLength(Data, 5);
  for I := 0 to High(Data) do
    Data[I] := Carrier.Tag.Wide + I;
  for I := 0 to High(Fixed) do
    Fixed[I] := Int64(I) * 10;

  Carrier.Feed(UInt64(SumOpen(Data)));
  Carrier.Feed(UInt64(Cardinal(CountOpen(Data))));
  Carrier.Feed(UInt64(SumOpen(Fixed)));
  Carrier.Feed(UInt64(Cardinal(CountOpen(Fixed))));

  { Литеральный список — тоже открытый массив. }
  Carrier.Feed(UInt64(SumOpen([Int64(1), 2, 3])));
  Carrier.Feed(UInt64(Cardinal(CountOpen([Int64(1), 2, 3]))));

  { Пустой открытый массив: длина ноль, обход не выполняется ни разу. }
  Carrier.Feed(UInt64(SumOpen([])));
  Carrier.Feed(UInt64(Cardinal(CountOpen([]))));
end;

{ Массив констант: каждый элемент везёт свой тип рядом со значением. }
procedure StageConstArray(Carrier: TResidentCarrier);
begin
  Carrier.Feed(UInt64(DescribeConst([1])));
  Carrier.Feed(UInt64(DescribeConst(['a'])));
  Carrier.Feed(UInt64(DescribeConst([True])));
  Carrier.Feed(UInt64(DescribeConst([Int64(1), 'text', True])));
  Carrier.Feed(UInt64(DescribeConst([])));
end;

{ Статический массив: границы принадлежат типу, а многомерность — это массив
  массивов, уложенный подряд. }
procedure StageStaticArray(Carrier: TResidentCarrier);
var
  Flat: array[3 .. 9] of Int64;
  Grid: array[0 .. 2, 0 .. 3] of Word;
  I, J: Integer;
  Sum: Int64;
begin
  Carrier.Feed(UInt64(Cardinal(Low(Flat))));
  Carrier.Feed(UInt64(Cardinal(High(Flat))));
  Carrier.Feed(UInt64(Cardinal(Length(Flat))));
  Carrier.Feed(UInt64(Cardinal(SizeOf(Flat))));

  Sum := 0;
  for I := Low(Flat) to High(Flat) do
  begin
    Flat[I] := Carrier.Tag.Wide + I;
    Sum := Sum xor Flat[I];
  end;
  Carrier.Feed(UInt64(Sum));

  Carrier.Feed(UInt64(Cardinal(SizeOf(Grid))));
  Carrier.Feed(UInt64(Cardinal(Length(Grid))));
  Carrier.Feed(UInt64(Cardinal(Length(Grid[0]))));
  for I := 0 to 2 do
    for J := 0 to 3 do
      Grid[I][J] := Word((I * 4 + J + Carrier.Serial) and $FFFF);
  Sum := 0;
  for I := 0 to 2 do
    for J := 0 to 3 do
      Sum := Sum + Grid[I][J];
  Carrier.Feed(UInt64(Sum));

  { Строки лежат подряд: последний элемент первой строки соседствует с первым
    элементом второй. }
  Carrier.Feed(UInt64(Ord(NativeUInt(@Grid[1][0]) - NativeUInt(@Grid[0][0]) =
                          4 * SizeOf(Word))));
end;

{ Символьные типы: код и символ — взаимно обратные, каждый в своей ширине. }
procedure StageCharTypes(Carrier: TResidentCarrier);
var
  Wide: Char;
  Narrow: AnsiChar;
  I: Integer;
begin
  Carrier.Feed(UInt64(Cardinal(SizeOf(Char))));
  Carrier.Feed(UInt64(Cardinal(SizeOf(AnsiChar))));
  Carrier.Feed(UInt64(Cardinal(SizeOf(WideChar))));

  Wide := 'A';
  Narrow := 'A';
  Carrier.Feed(UInt64(Word(Wide)));
  Carrier.Feed(UInt64(Ord(Narrow)));
  Carrier.Feed(UInt64(Ord(Word(Wide) = Ord(Narrow))));

  for I := 0 to 7 do
  begin
    Wide := Char(Word(Ord('a') + I));
    Carrier.Feed(UInt64(Word(Wide)));
    Carrier.Feed(UInt64(Ord(Ord(Wide) = Ord('a') + I)));
  end;

  { Границы символьного типа принадлежат типу, а не содержимому. }
  Carrier.Feed(UInt64(Word(Low(Char))));
  Carrier.Feed(UInt64(Word(High(Char))));
  Carrier.Feed(UInt64(Ord(Low(AnsiChar))));
  Carrier.Feed(UInt64(Ord(High(AnsiChar))));
end;

{ Указатель: сравнение, ноль и приведение к целому — без единого разыменования
  чужой памяти. }
procedure StagePointerShape(Carrier: TResidentCarrier);
var
  Data: System.TArray<Int64>;
  First, Second, Empty: Pointer;
begin
  SetLength(Data, 4);
  First := @Data[0];
  Second := @Data[1];
  Empty := nil;

  Carrier.Feed(UInt64(Ord(First <> Second)));
  Carrier.Feed(UInt64(Ord(First <> nil)));
  Carrier.Feed(UInt64(Ord(Empty = nil)));
  Carrier.Feed(UInt64(Ord(Assigned(First))));
  Carrier.Feed(UInt64(Ord(Assigned(Empty))));
  Carrier.Feed(UInt64(Cardinal(SizeOf(Pointer))));

  { Расстояние между соседними элементами обязано равняться размеру элемента. }
  Carrier.Feed(UInt64(NativeUInt(Second) - NativeUInt(First)));
  Carrier.Feed(UInt64(Ord(NativeUInt(Second) - NativeUInt(First) =
                          SizeOf(Int64))));
end;

initialization
  ResidentRegisterStage('shape-bool-widths', @StageBoolWidths);
  ResidentRegisterStage('shape-char-types', @StageCharTypes);
  ResidentRegisterStage('shape-const-array', @StageConstArray);
  ResidentRegisterStage('shape-enum-order', @StageEnumOrder);
  ResidentRegisterStage('shape-enum-sparse', @StageEnumSparse);
  ResidentRegisterStage('shape-open-array', @StageOpenArray);
  ResidentRegisterStage('shape-overlay', @StageOverlay);
  ResidentRegisterStage('shape-pointer', @StagePointerShape);
  ResidentRegisterStage('shape-set-built', @StageSetBuilt);
  ResidentRegisterStage('shape-set-ops', @StageSetOps);
  ResidentRegisterStage('shape-set-tail', @StageSetTail);
  ResidentRegisterStage('shape-static-array', @StageStaticArray);
  ResidentRegisterStage('shape-subrange', @StageSubrange);
  ResidentRegisterStage('shape-variant-array', @StageVariantArray);
  ResidentRegisterStage('shape-variant-states', @StageVariantStates);
  ResidentRegisterStage('shape-variant-transit', @StageVariantTransit);

end.
