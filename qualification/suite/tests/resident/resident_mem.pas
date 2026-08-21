unit resident_mem;

{ Семейство `mem` — память, переезды и указатели.

  Здесь программа стареет по-настоящему: буферы растут до переезда, освобождают
  место, занимают его снова, чередуют размеры так, чтобы менеджеру памяти
  пришлось работать всеми своими классами блоков — от самых мелких до крупных,
  идущих мимо кэшей напрямую к системе.

  Адреса в дайджест не идут ни разу: адрес — свойство запуска, а не программы.
  Идут только факты, которые обязаны быть одинаковы всегда: тот же буфер или
  уже другой, сохранилось ли содержимое после переезда, совпало ли сравнение
  двух областей, легло ли поле по ожидаемому смещению.

  Ручные блоки заводятся и освобождаются в одной стадии в `try/finally`: слой,
  который течёт сам, не имеет права обвинять в утечке менеджер памяти. }

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
  SysUtils, Classes, Generics.Collections, resident_core;

implementation

type
  { Размеры подобраны так, чтобы задеть все классы менеджера памяти: мелкие с
    шагом по спискам, средние, и заведомо крупные, идущие мимо кэшей. }
  TResidentSizes = array[0 .. 9] of Integer;

const
  BlockSizes: TResidentSizes =
    (16, 48, 112, 256, 600, 1400, 2600, 2856, 16384, 262144);

type
  TResidentPacked = packed record
    A: Byte;
    B: Int64;
    C: Word;
    D: Byte;
  end;

  TResidentAligned = record
    A: Byte;
    B: Int64;
    C: Word;
    D: Byte;
  end;

  TResidentNested = record
    Head: UInt64;
    Inner: TResidentAligned;
    Tail: UInt64;
  end;

  TResidentParcel = record
    Text: string;
    Bytes: AnsiString;
    Numbers: System.TArray<Int64>;
    Slot: Int64;
  end;

  TResidentMemPocket = class(TResidentPocket)
  private
    FGrid: System.TArray<System.TArray<Int64>>;
    FRounds: Int64;
  end;

{ Один буфер или разные: сам адрес недетерминирован, факт совпадения — нет. }
function SameStore(const A, B: System.TArray<Int64>): Boolean;
begin
  if (Length(A) = 0) or (Length(B) = 0) then
    Exit(Length(A) = Length(B));
  Result := Pointer(A) = Pointer(B);
end;

{ Рост массива до потолка и сжатие обратно: за прогон случается и переезд, и
  усечение, и повторное занятие той же памяти. }
procedure StageArrayGrowth(Carrier: TResidentCarrier);
var
  Numbers: System.TArray<Int64>;
  Room, I: Integer;
  Tag: TResidentTag;
begin
  Tag := Carrier.Tag;
  Numbers := Carrier.Numbers;
  Room := Length(Numbers);

  { Расписание роста детерминировано: зависит от оборота, а не от времени. }
  if Room < 64 then
  begin
    SetLength(Numbers, Room + 1);
    Numbers[Room] := Tag.Wide + Room;
  end
  else
    SetLength(Numbers, 4);

  for I := 0 to High(Numbers) do
    Carrier.Feed(UInt64(Numbers[I]));
  Carrier.Numbers := Numbers;
  Carrier.Feed(UInt64(Cardinal(Length(Numbers))));
end;

{ Динамический массив тоже делит буфер: присваивание не копирует, `SetLength`
  обязан отделить, а `Copy` — сделать свой. }
procedure StageArrayShare(Carrier: TResidentCarrier);
var
  Source, Twin: System.TArray<Int64>;
  Was: Int64;
begin
  SetLength(Source, 8);
  for var I := 0 to High(Source) do
    Source[I] := Carrier.Tag.Wide + I;

  Twin := Source;
  Carrier.Feed(UInt64(Ord(SameStore(Source, Twin))));

  { Запись через второй ярлык видна первому: буфер общий, копии не было. }
  Was := Source[0];
  Twin[0] := Was + 1000;
  Carrier.Feed(UInt64(Ord(Source[0] = Twin[0])));
  Twin[0] := Was;

  { `SetLength` обязан отделить: у длины свой владелец. }
  SetLength(Twin, 9);
  Carrier.Feed(UInt64(Ord(SameStore(Source, Twin))));
  Carrier.Feed(UInt64(Cardinal(Length(Source))));
  Carrier.Feed(UInt64(Cardinal(Length(Twin))));

  { `Copy` всегда делает свой буфер, даже когда длина та же. }
  Twin := System.Copy(Source, 0, Length(Source));
  Carrier.Feed(UInt64(Ord(SameStore(Source, Twin))));
  Carrier.Feed(UInt64(Ord(Length(Twin) = Length(Source))));
  Twin[0] := Was + 7;
  Carrier.Feed(UInt64(Ord(Source[0] = Was)));
end;

{ Проход указателем: адрес внутрь буфера обязан оставаться верным, пока буфер
  не переехал. }
procedure StagePointerWalk(Carrier: TResidentCarrier);
var
  Numbers: System.TArray<Int64>;
  Cursor: PInt64;
  I: Integer;
  Sum, Direct: Int64;
begin
  Numbers := Carrier.Numbers;
  Sum := 0;
  Direct := 0;
  if Length(Numbers) > 0 then
  begin
    Cursor := @Numbers[0];
    for I := 0 to High(Numbers) do
    begin
      Sum := Sum xor Cursor^;
      Inc(Cursor);
    end;
    { Тот же проход индексами обязан дать тот же результат — иначе шаг
      указателя разошёлся с размером элемента. }
    for I := 0 to High(Numbers) do
      Direct := Direct xor Numbers[I];
  end;
  Carrier.Feed(UInt64(Sum));
  Carrier.Feed(UInt64(Ord(Sum = Direct)));
  Carrier.Feed(UInt64(Cardinal(Length(Numbers))));
end;

{ Указатель назад: шаг вниз обязан вернуть ровно туда, откуда шагнули вверх. }
procedure StagePointerBack(Carrier: TResidentCarrier);
var
  Numbers: System.TArray<Int64>;
  Head, Cursor: PInt64;
  I, Steps: Integer;
begin
  Numbers := Carrier.Numbers;
  if Length(Numbers) = 0 then
    Exit;
  Head := @Numbers[0];
  Cursor := Head;
  Steps := Length(Numbers) - 1;
  for I := 1 to Steps do
    Inc(Cursor);
  Carrier.Feed(UInt64(Cursor^));
  Carrier.Feed(UInt64(Ord(Cursor^ = Numbers[Steps])));
  for I := 1 to Steps do
    Dec(Cursor);
  Carrier.Feed(UInt64(Ord(Cursor = Head)));
  Carrier.Feed(UInt64(Cursor^));

  { Разность указателей на элементы обязана считаться в элементах. }
  Carrier.Feed(UInt64(Cardinal(Steps)));
end;

{ Ручной блок: занять, записать, прочитать, отдать. Всё в одной стадии, всё в
  `try/finally` — течь здесь нечему. }
procedure StageManualBlock(Carrier: TResidentCarrier);
var
  Block: PByte;
  Size, I: Integer;
  Sum: UInt64;
begin
  Size := BlockSizes[Carrier.Lap mod Length(BlockSizes)];
  GetMem(Block, Size);
  try
    Carrier.Feed(UInt64(Ord(Block <> nil)));
    for I := 0 to Size - 1 do
      PByte(PByte(Block) + I)^ := Byte((Carrier.Tag.Wide + I) and $FF);
    Sum := 0;
    for I := 0 to Size - 1 do
      Sum := Sum + PByte(PByte(Block) + I)^;
    Carrier.Feed(Sum);
    Carrier.Feed(UInt64(Cardinal(Size)));
  finally
    FreeMem(Block);
  end;
end;

{ Смена размера блока: содержимое обязано пережить переезд целиком. }
procedure StageRealloc(Carrier: TResidentCarrier);
var
  Block: PByte;
  Small, Large, I: Integer;
  Ok: Boolean;
begin
  Small := 64 + (Carrier.Lap mod 7) * 16;
  Large := Small * 4;
  GetMem(Block, Small);
  try
    for I := 0 to Small - 1 do
      PByte(PByte(Block) + I)^ := Byte((I * 7 + Carrier.Serial) and $FF);

    ReallocMem(Block, Large);
    Ok := True;
    for I := 0 to Small - 1 do
      if PByte(PByte(Block) + I)^ <> Byte((I * 7 + Carrier.Serial) and $FF) then
        Ok := False;
    Carrier.Feed(UInt64(Ord(Ok)));
    Carrier.Feed(UInt64(Cardinal(Large)));

    { Сжатие обратно: голова обязана уцелеть, хвост — исчезнуть. }
    ReallocMem(Block, Small div 2);
    Ok := True;
    for I := 0 to Small div 2 - 1 do
      if PByte(PByte(Block) + I)^ <> Byte((I * 7 + Carrier.Serial) and $FF) then
        Ok := False;
    Carrier.Feed(UInt64(Ord(Ok)));
  finally
    FreeMem(Block);
  end;
end;

{ Перенос области с перекрытием: и вперёд, и назад. Обе стороны определены и
  обязаны дать в точности сдвинутое содержимое. }
procedure StageMoveOverlap(Carrier: TResidentCarrier);
var
  Data: array[0 .. 31] of Byte;
  Mirror: array[0 .. 31] of Byte;
  I: Integer;
  Ok: Boolean;
begin
  for I := 0 to High(Data) do
  begin
    Data[I] := Byte((I + Carrier.Serial) and $FF);
    Mirror[I] := Data[I];
  end;

  { Сдвиг вправо: хвост обязан не затереть то, что ещё не скопировано. }
  Move(Data[0], Data[4], 20);
  Ok := True;
  for I := 0 to 19 do
    if Data[4 + I] <> Mirror[I] then
      Ok := False;
  Carrier.Feed(UInt64(Ord(Ok)));
  for I := 0 to 3 do
    Carrier.Feed(UInt64(Data[I]));

  { Сдвиг влево — обратное направление той же механики. }
  Move(Data[8], Data[2], 16);
  Ok := True;
  for I := 0 to 15 do
    if Data[2 + I] <> Mirror[4 + I] then
      Ok := False;
  Carrier.Feed(UInt64(Ord(Ok)));

  { Нулевая длина обязана быть безвредной. }
  Move(Data[0], Data[1], 0);
  Carrier.Feed(UInt64(Data[1]));
end;

{ Заливка и сравнение областей: обе обязаны считать байты, а не элементы. }
procedure StageFillCompare(Carrier: TResidentCarrier);
var
  Left, Right: array[0 .. 63] of Byte;
  Filler: Byte;
begin
  Filler := Byte(Carrier.Lap and $FF);
  FillChar(Left, SizeOf(Left), Filler);
  FillChar(Right, SizeOf(Right), Filler);
  Carrier.Feed(UInt64(Ord(CompareMem(@Left, @Right, SizeOf(Left)))));
  Carrier.Feed(UInt64(Left[0]));
  Carrier.Feed(UInt64(Left[High(Left)]));

  { Один изменённый байт обязан ломать сравнение. }
  Right[SizeOf(Right) - 1] := Byte(Filler + 1);
  Carrier.Feed(UInt64(Ord(CompareMem(@Left, @Right, SizeOf(Left)))));
  { А сравнение более короткого куска — нет. }
  Carrier.Feed(UInt64(Ord(CompareMem(@Left, @Right, SizeOf(Left) - 1))));

  { Частичная заливка не имеет права выйти за свою длину. }
  FillChar(Left, 8, 0);
  Carrier.Feed(UInt64(Left[7]));
  Carrier.Feed(UInt64(Left[8]));
end;

{ Раскладка записи: смещения полей — это договор компилятора, и упакованная
  запись обязана отличаться от выровненной. }
procedure StageLayout(Carrier: TResidentCarrier);
var
  Tight: TResidentPacked;
  Loose: TResidentAligned;
  Nested: TResidentNested;
begin
  Carrier.Feed(UInt64(Cardinal(SizeOf(Tight))));
  Carrier.Feed(UInt64(Cardinal(SizeOf(Loose))));
  Carrier.Feed(UInt64(Ord(SizeOf(Tight) <= SizeOf(Loose))));

  Carrier.Feed(UInt64(Cardinal(NativeUInt(@Tight.B) - NativeUInt(@Tight))));
  Carrier.Feed(UInt64(Cardinal(NativeUInt(@Loose.B) - NativeUInt(@Loose))));
  Carrier.Feed(UInt64(Cardinal(NativeUInt(@Tight.C) - NativeUInt(@Tight))));
  Carrier.Feed(UInt64(Cardinal(NativeUInt(@Loose.C) - NativeUInt(@Loose))));

  Carrier.Feed(UInt64(Cardinal(SizeOf(Nested))));
  Carrier.Feed(UInt64(Cardinal(NativeUInt(@Nested.Inner) - NativeUInt(@Nested))));
  Carrier.Feed(UInt64(Cardinal(NativeUInt(@Nested.Tail) - NativeUInt(@Nested))));

  { Запись, записанная и прочитанная целиком, обязана вернуть все поля. }
  Loose.A := Byte(Carrier.Serial and $FF);
  Loose.B := Carrier.Tag.Wide;
  Loose.C := Carrier.Tag.Unsigned;
  Loose.D := $5A;
  Nested.Head := CanaryHead;
  Nested.Inner := Loose;
  Nested.Tail := CanaryTail;
  Carrier.Feed(UInt64(Nested.Inner.B));
  Carrier.Feed(UInt64(Nested.Inner.C));
  Carrier.Feed(UInt64(Ord(Nested.Head = CanaryHead)));
  Carrier.Feed(UInt64(Ord(Nested.Tail = CanaryTail)));
end;

{ Копия управляемой записи по значению: у копии обязан быть свой буфер, иначе
  правка одной стороны видна другой. }
procedure StageRecordCopy(Carrier: TResidentCarrier);
var
  Source, Copy: TResidentParcel;
  Text: TResidentText;
begin
  Text := Carrier.Text;
  Source.Text := Text.Wide;
  Source.Bytes := Text.Bytes;
  Source.Numbers := Carrier.Numbers;
  Source.Slot := Carrier.Tag.Wide;

  Copy := Source;
  Copy.Text := Copy.Text + 'x';
  Copy.Numbers := System.Copy(Source.Numbers, 0, Length(Source.Numbers));
  if Length(Copy.Numbers) > 0 then
    Copy.Numbers[0] := Copy.Numbers[0] + 1;

  { Оригинал не должен был шелохнуться. }
  Carrier.Feed(UInt64(Cardinal(Length(Source.Text))));
  Carrier.Feed(UInt64(Cardinal(Length(Copy.Text))));
  Carrier.Feed(UInt64(Ord(Length(Copy.Text) = Length(Source.Text) + 1)));
  if Length(Source.Numbers) > 0 then
  begin
    Carrier.Feed(UInt64(Source.Numbers[0]));
    Carrier.Feed(UInt64(Ord(Copy.Numbers[0] = Source.Numbers[0] + 1)));
  end;
  Carrier.Feed(UInt64(Source.Slot));

  { Обнуление копии не имеет права задеть оригинал. }
  Copy := Default(TResidentParcel);
  Carrier.Feed(UInt64(Cardinal(Length(Source.Text))));
  Carrier.Feed(UInt64(Cardinal(Length(Copy.Text))));
end;

{ Массив массивов: внешний растёт, внутренние живут своей жизнью и переезжают
  независимо. }
procedure StageGrid(Carrier: TResidentCarrier);
var
  Pocket: TResidentMemPocket;
  Rows, Cols, R, C: Integer;
  Sum: Int64;
begin
  Pocket := Carrier.PocketAs<TResidentMemPocket>('mem-grid');
  Rows := 1 + (Carrier.Lap mod 9);
  SetLength(Pocket.FGrid, Rows);
  Sum := 0;
  for R := 0 to Rows - 1 do
  begin
    Cols := 1 + ((R + Carrier.Serial) mod 6);
    SetLength(Pocket.FGrid[R], Cols);
    for C := 0 to Cols - 1 do
    begin
      Pocket.FGrid[R][C] := Carrier.Tag.Wide + R * 100 + C;
      Sum := Sum xor Pocket.FGrid[R][C];
    end;
  end;
  Carrier.Feed(UInt64(Sum));
  Carrier.Feed(UInt64(Cardinal(Length(Pocket.FGrid))));
  for R := 0 to High(Pocket.FGrid) do
    Carrier.Feed(UInt64(Cardinal(Length(Pocket.FGrid[R]))));
  Inc(Pocket.FRounds);
  Carrier.Feed(UInt64(Pocket.FRounds));
end;

{ Вставка и удаление в середину динамического массива: длины и содержимое
  обязаны сойтись, а хвост — сдвинуться ровно на один элемент. }
procedure StageArraySplice(Carrier: TResidentCarrier);
var
  Data: System.TArray<Int64>;
  I, Where: Integer;
  Was: Int64;
begin
  SetLength(Data, 8);
  for I := 0 to High(Data) do
    Data[I] := Carrier.Tag.Wide + I;
  Where := 1 + (Carrier.Lap mod 6);
  Was := Data[Where];

  Insert([Int64(-1)], Data, Where);
  Carrier.Feed(UInt64(Cardinal(Length(Data))));
  Carrier.Feed(UInt64(Data[Where]));
  Carrier.Feed(UInt64(Ord(Data[Where + 1] = Was)));

  Delete(Data, Where, 1);
  Carrier.Feed(UInt64(Cardinal(Length(Data))));
  Carrier.Feed(UInt64(Ord(Data[Where] = Was)));

  for I := 0 to High(Data) do
    Carrier.Feed(UInt64(Data[I]));
end;

{ Перемежающееся занятие и освобождение: половина блоков уходит, оставшиеся
  дырки заполняются другими размерами. Это старость памяти в чистом виде. }
procedure StageFragment(Carrier: TResidentCarrier);
const
  Slots = 24;
var
  Blocks: array[0 .. Slots - 1] of PByte;
  Sizes: array[0 .. Slots - 1] of Integer;
  I: Integer;
  Sum: UInt64;
begin
  { Сначала все ярлыки пусты: тогда финальная уборка знает, что именно занято,
    даже если занятие оборвалось на середине. }
  FillChar(Blocks, SizeOf(Blocks), 0);
  try
    for I := 0 to Slots - 1 do
    begin
      Sizes[I] := BlockSizes[(I + Carrier.Lap) mod Length(BlockSizes)];
      GetMem(Blocks[I], Sizes[I]);
      PByte(Blocks[I])^ := Byte(I);
    end;

    { Каждый второй уходит: между занятыми остаются дырки разного размера. }
    for I := 0 to Slots - 1 do
      if I mod 2 = 1 then
      begin
        FreeMem(Blocks[I]);
        Blocks[I] := nil;
      end;

    { Дырки занимаются блоками других размеров — менеджеру приходится либо
      резать, либо искать новое место. }
    for I := 0 to Slots - 1 do
      if Blocks[I] = nil then
      begin
        Sizes[I] := BlockSizes[(I * 3 + Carrier.Serial) mod Length(BlockSizes)];
        GetMem(Blocks[I], Sizes[I]);
        PByte(Blocks[I])^ := Byte(I + 128);
      end;

    Sum := 0;
    for I := 0 to Slots - 1 do
      Sum := Sum + PByte(Blocks[I])^ + UInt64(Cardinal(Sizes[I]));
    Carrier.Feed(Sum);
  finally
    for I := 0 to Slots - 1 do
      if Blocks[I] <> nil then
        FreeMem(Blocks[I]);
  end;
end;

{ Крупный блок: он идёт мимо кэшей мелких классов, прямо к системе, и обязан
  быть отдан обратно так же честно. }
procedure StageLargeBlock(Carrier: TResidentCarrier);
var
  Data: System.TArray<Byte>;
  Size, I, Step: Integer;
  Sum: UInt64;
begin
  Size := 262144 + (Carrier.Lap mod 5) * 65536;
  SetLength(Data, Size);
  Step := Size div 64;
  for I := 0 to 63 do
    Data[I * Step] := Byte((I + Carrier.Serial) and $FF);
  Sum := 0;
  for I := 0 to 63 do
    Sum := Sum + Data[I * Step];
  Carrier.Feed(Sum);
  Carrier.Feed(UInt64(Cardinal(Length(Data))));

  { Усечение крупного блока обязано сохранить голову. }
  SetLength(Data, 1024);
  Carrier.Feed(UInt64(Data[0]));
  Carrier.Feed(UInt64(Cardinal(Length(Data))));
  SetLength(Data, 0);
  Carrier.Feed(UInt64(Cardinal(Length(Data))));
end;

{ Локальный массив на стеке против динамического в куче: содержимое обязано
  совпасть до байта, как бы по-разному они ни лежали. }
procedure StageStackHeap(Carrier: TResidentCarrier);
var
  OnStack: array[0 .. 255] of Int64;
  OnHeap: System.TArray<Int64>;
  I: Integer;
  Ok: Boolean;
begin
  SetLength(OnHeap, Length(OnStack));
  for I := 0 to High(OnStack) do
  begin
    OnStack[I] := Carrier.Tag.Wide + I * 3;
    OnHeap[I] := Carrier.Tag.Wide + I * 3;
  end;
  Ok := CompareMem(@OnStack[0], @OnHeap[0], Length(OnHeap) * SizeOf(Int64));
  Carrier.Feed(UInt64(Ord(Ok)));
  Carrier.Feed(UInt64(Cardinal(SizeOf(OnStack))));
  Carrier.Feed(UInt64(Cardinal(Length(OnHeap) * SizeOf(Int64))));
  Carrier.Feed(UInt64(OnStack[High(OnStack)]));
  Carrier.Feed(UInt64(OnHeap[High(OnHeap)]));
end;

{ Обнуление управляемых полей: `Default` обязан отпустить строки и массивы, а
  не просто затереть указатели. }
procedure StageDefaultClear(Carrier: TResidentCarrier);
var
  Parcel: TResidentParcel;
  Held: string;
begin
  Parcel.Text := Carrier.Text.Wide + 'tail';
  Parcel.Bytes := Carrier.Text.Bytes;
  Parcel.Numbers := System.Copy(Carrier.Numbers, 0, Length(Carrier.Numbers));
  Parcel.Slot := Carrier.Tag.Wide;

  { Держим свою ссылку: после обнуления записи строка обязана остаться живой. }
  Held := Parcel.Text;
  Carrier.Feed(UInt64(Cardinal(Length(Held))));

  Parcel := Default(TResidentParcel);
  Carrier.Feed(UInt64(Cardinal(Length(Parcel.Text))));
  Carrier.Feed(UInt64(Cardinal(Length(Parcel.Bytes))));
  Carrier.Feed(UInt64(Cardinal(Length(Parcel.Numbers))));
  Carrier.Feed(UInt64(Parcel.Slot));
  { Наша ссылка не пострадала. }
  Carrier.Feed(UInt64(Cardinal(Length(Held))));
  Carrier.FeedWide(Held);
end;

{ Типизированный указатель на запись: поле по указателю и поле напрямую — одно
  и то же место. }
procedure StageTypedPointer(Carrier: TResidentCarrier);
type
  PAligned = ^TResidentAligned;
var
  Value: TResidentAligned;
  Ptr: PAligned;
begin
  Value.A := 1;
  Value.B := Carrier.Tag.Wide;
  Value.C := Carrier.Tag.Unsigned;
  Value.D := 2;
  Ptr := @Value;

  Carrier.Feed(UInt64(Ptr^.B));
  Carrier.Feed(UInt64(Ord(Ptr^.B = Value.B)));
  Ptr^.B := Ptr^.B + 5;
  Carrier.Feed(UInt64(Value.B));
  Carrier.Feed(UInt64(Ord(Value.B = Ptr^.B)));
  Carrier.Feed(UInt64(Ptr^.C));
  Carrier.Feed(UInt64(Cardinal(SizeOf(Ptr^))));
end;

initialization
  ResidentRegisterStage('mem-array-growth', @StageArrayGrowth);
  ResidentRegisterStage('mem-array-share', @StageArrayShare);
  ResidentRegisterStage('mem-array-splice', @StageArraySplice);
  ResidentRegisterStage('mem-default-clear', @StageDefaultClear);
  ResidentRegisterStage('mem-fill-compare', @StageFillCompare);
  ResidentRegisterStage('mem-fragment', @StageFragment);
  ResidentRegisterStage('mem-grid', @StageGrid);
  ResidentRegisterStage('mem-large-block', @StageLargeBlock);
  ResidentRegisterStage('mem-layout', @StageLayout);
  ResidentRegisterStage('mem-manual-block', @StageManualBlock);
  ResidentRegisterStage('mem-move-overlap', @StageMoveOverlap);
  ResidentRegisterStage('mem-pointer-back', @StagePointerBack);
  ResidentRegisterStage('mem-pointer-walk', @StagePointerWalk);
  ResidentRegisterStage('mem-realloc', @StageRealloc);
  ResidentRegisterStage('mem-record-copy', @StageRecordCopy);
  ResidentRegisterStage('mem-stack-heap', @StageStackHeap);
  ResidentRegisterStage('mem-typed-pointer', @StageTypedPointer);

end.
