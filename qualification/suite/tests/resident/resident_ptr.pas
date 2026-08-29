unit resident_ptr;

{ Семейство `ptr` — указатели и работа через них.

  Обращение по указателю компилятор трогать боится меньше, чем следовало бы:
  адрес он умеет считать заранее, шаг — прибавлять вместо умножения, а чтение —
  переносить через код, который «наверняка» ничего не пишет. Каждое такое
  решение опирается на то, что все места записи известны, а указатель как раз и
  есть способ записать туда, куда прямой взгляд не достаёт.

  Здесь проверяется, что обход указателем и обход по индексу дают одно и то же,
  что шаг типизированного указателя равен размеру типа, что запись через один
  указатель видна через другой, смотрящий на то же место, и что байтовый взгляд
  на число собирает обратно ровно то число.

  Ни одного обращения за пределы своей памяти здесь нет: каждый указатель
  смотрит внутрь массива или переменной, живущей всю стадию, а границы обхода
  считаются от длины, а не от догадки. }

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
  PInt64Array = ^TInt64Array;
  TInt64Array = array[0 .. 31] of Int64;

  TPtrRecord = record
    Head: Int64;
    Middle: Integer;
    Tail: Int64;
  end;
  PPtrRecord = ^TPtrRecord;

{ Обход указателем против обхода по индексу. }
procedure StageWalk(Carrier: TResidentCarrier);
var
  State: UInt64;
  Data: TInt64Array;
  I: Integer;
  Cursor: ^Int64;
  ByPointer, ByIndex: Int64;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap);
  for I := 0 to High(Data) do
    Data[I] := Int64(ResidentNext(State) and $FFFF) - 32768;

  ByPointer := 0;
  Cursor := @Data[0];
  for I := 0 to High(Data) do
    begin
      ByPointer := ByPointer + Cursor^ * (I + 1);
      Inc(Cursor);
    end;

  ByIndex := 0;
  for I := 0 to High(Data) do
    ByIndex := ByIndex + Data[I] * (I + 1);

  { Обратный обход: курсор ставится на последний элемент и идёт назад. }
  var Backward: Int64 := 0;
  Cursor := @Data[High(Data)];
  for I := High(Data) downto 0 do
    begin
      Backward := Backward + Cursor^ * (I + 1);
      Dec(Cursor);
    end;

  Carrier.Feed(UInt64(ByIndex));
  Carrier.Claim(ByPointer = ByIndex, 'ptr: walking by pointer disagrees with walking by index');
  Carrier.Claim(Backward = ByIndex, 'ptr: walking backwards disagrees with walking forwards');
end;

{ Шаг типизированного указателя равен размеру типа, и разность указателей
  считается в элементах. }
procedure StageStride(Carrier: TResidentCarrier);
var
  Data: TInt64Array;
  First, Last, Moved: ^Int64;
  Bad: Integer;
  Distance: NativeInt;
begin
  Bad := 0;
  First := @Data[0];
  Last := @Data[High(Data)];

  { Разность адресов в байтах — это число элементов на размер элемента. }
  Distance := NativeInt(PByte(Last) - PByte(First));
  if Distance <> High(Data) * SizeOf(Int64) then
    Inc(Bad);

  Moved := First;
  Inc(Moved, High(Data));
  if Moved <> Last then
    Inc(Bad);

  Dec(Moved, High(Data));
  if Moved <> First then
    Inc(Bad);

  { Байтовый указатель шагает по одному байту, а не по восемь. }
  var AsBytes: PByte := PByte(First);
  Inc(AsBytes, SizeOf(Int64));
  if AsBytes <> PByte(@Data[1]) then
    Inc(Bad);

  Carrier.Feed(UInt64(Cardinal(Distance div SizeOf(Int64))));
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'ptr: pointer step does not match the size of its type');
end;

{ Два указателя на одно место: запись через один видна через другой. }
procedure StageAliasThroughPointer(Carrier: TResidentCarrier);
var
  State: UInt64;
  Data: TInt64Array;
  I, Bad: Integer;
  A, B: ^Int64;
  Sum, Mirror: Int64;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 3 + 1);
  for I := 0 to High(Data) do
    Data[I] := Int64(I);
  Bad := 0;

  A := @Data[5];
  B := @Data[5];

  A^ := 100;
  if B^ <> 100 then Inc(Bad);
  B^ := 200;
  if A^ <> 200 then Inc(Bad);
  if Data[5] <> 200 then Inc(Bad);

  { Чтение через указатель в цикле, где запись идёт через другой. }
  Sum := 0;
  for I := 1 to 8 do
    begin
      Sum := Sum + A^;
      B^ := B^ + 3;
    end;

  Mirror := 0;
  var Shadow: Int64 := 200;
  for I := 1 to 8 do
    begin
      Mirror := Mirror + Shadow;
      Shadow := Shadow + 3;
    end;

  Carrier.Feed(UInt64(Sum));
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'ptr: two pointers to one place behaved as two places');
  Carrier.Claim(Sum = Mirror, 'ptr: read through a pointer missed a write through its twin');
end;

{ Байтовый взгляд на число: разобрать и собрать обратно. }
procedure StageByteView(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, B, Bad: Integer;
  Value, Rebuilt: UInt64;
  Bytes: PByte;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 5 + 2);
  Bad := 0;

  for I := 1 to 12 do
    begin
      Value := ResidentNext(State);
      Bytes := PByte(@Value);

      { Порядок байтов на этой машине младшим вперёд, и это часть договора. }
      Rebuilt := 0;
      for B := 0 to 7 do
        begin
          Rebuilt := Rebuilt or (UInt64(Bytes^) shl (B * 8));
          Inc(Bytes);
        end;
      if Rebuilt <> Value then
        Inc(Bad);

      { Младший байт числа — первый байт памяти. }
      Bytes := PByte(@Value);
      if Bytes^ <> Byte(Value and $FF) then
        Inc(Bad);

      Carrier.Feed(Rebuilt);
    end;

  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'ptr: byte view of a number does not rebuild it');
end;

{ Указатель на поле записи: смещения полей известны компилятору, и через
  указатель они обязаны совпасть. }
procedure StageRecordFields(Carrier: TResidentCarrier);
var
  State: UInt64;
  Item: TPtrRecord;
  Link: PPtrRecord;
  Bad: Integer;
  HeadPtr, TailPtr: ^Int64;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 7 + 3);
  Item.Head := Int64(ResidentNext(State));
  Item.Middle := Integer(ResidentNext(State));
  Item.Tail := Int64(ResidentNext(State));
  Bad := 0;

  Link := @Item;
  if Link^.Head <> Item.Head then Inc(Bad);
  if Link^.Middle <> Item.Middle then Inc(Bad);
  if Link^.Tail <> Item.Tail then Inc(Bad);

  { Запись через указатель видна через имя. }
  Link^.Middle := 12345;
  if Item.Middle <> 12345 then Inc(Bad);

  { Указатели на отдельные поля смотрят внутрь той же записи. }
  HeadPtr := @Item.Head;
  TailPtr := @Item.Tail;
  HeadPtr^ := 777;
  TailPtr^ := 888;
  if Item.Head <> 777 then Inc(Bad);
  if Item.Tail <> 888 then Inc(Bad);
  if HeadPtr = TailPtr then Inc(Bad);

  { Поля не наезжают друг на друга. }
  if NativeInt(PByte(TailPtr) - PByte(HeadPtr)) < SizeOf(Int64) then Inc(Bad);

  Carrier.Feed(UInt64(Item.Head));
  Carrier.Feed(UInt64(Cardinal(Item.Middle)));
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'ptr: pointer to a record field misses the field');
end;

{ Сравнение указателей и пустой указатель. }
procedure StageCompare(Carrier: TResidentCarrier);
var
  Data: TInt64Array;
  Bad: Integer;
  A, B, Empty: ^Int64;
begin
  Bad := 0;
  A := @Data[0];
  B := @Data[1];
  Empty := nil;

  if A = B then Inc(Bad);
  if not (A <> B) then Inc(Bad);
  if A = nil then Inc(Bad);
  if Empty <> nil then Inc(Bad);
  if Assigned(Empty) then Inc(Bad);
  if not Assigned(A) then Inc(Bad);

  { Порядок адресов внутри одного массива задан его раскладкой. }
  if not (PByte(B) > PByte(A)) then Inc(Bad);

  B := A;
  if A <> B then Inc(Bad);

  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'ptr: pointer comparison is wrong');
end;

{ Указатель на массив целиком: обращение через него и напрямую. }
procedure StageArrayPointer(Carrier: TResidentCarrier);
var
  State: UInt64;
  Data: TInt64Array;
  Link: PInt64Array;
  I, Bad: Integer;
  Sum, Mirror: Int64;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 11 + 5);
  for I := 0 to High(Data) do
    Data[I] := Int64(ResidentNext(State) and $FFF);
  Bad := 0;
  Link := @Data;

  Sum := 0;
  for I := 0 to High(Data) do
    Sum := Sum + Link^[I] * (I + 1);

  Mirror := 0;
  for I := 0 to High(Data) do
    Mirror := Mirror + Data[I] * (I + 1);

  if Sum <> Mirror then Inc(Bad);

  { Запись через указатель на массив видна по имени. }
  Link^[3] := 999;
  if Data[3] <> 999 then Inc(Bad);
  if Link^[3] <> Data[3] then Inc(Bad);

  Carrier.Feed(UInt64(Sum));
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'ptr: access through an array pointer differs from access by name');
end;

initialization
  ResidentRegisterStage('ptr-alias', @StageAliasThroughPointer);
  ResidentRegisterStage('ptr-array-pointer', @StageArrayPointer);
  ResidentRegisterStage('ptr-byte-view', @StageByteView);
  ResidentRegisterStage('ptr-compare', @StageCompare);
  ResidentRegisterStage('ptr-record-fields', @StageRecordFields);
  ResidentRegisterStage('ptr-stride', @StageStride);
  ResidentRegisterStage('ptr-walk', @StageWalk);

end.
