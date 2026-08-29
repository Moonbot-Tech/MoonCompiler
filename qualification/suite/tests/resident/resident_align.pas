unit resident_align;

{ Семейство `align` — раскладка записей в памяти.

  Размер записи и смещения её полей нигде в исходнике не написаны: их выбирает
  компилятор по правилам выравнивания. Правила эти — часть договора о двоичной
  совместимости, потому что по ним ходят и чужой код, и сохранённые файлы, и
  протокол на проводе. Ошибка здесь не портит вычисление: она сдвигает поле, и
  дальше всё считается правильно, но не над теми байтами.

  Проверяется тем, что от раскладки следует однозначно: поля не наезжают друг
  на друга, запись в одно поле не трогает соседнее, шаг массива записей равен
  размеру записи, упакованная запись занимает ровно сумму своих полей, а
  выравненная — не меньше упакованной. Конкретные числа смещений в утверждения
  не идут: их выбирает компилятор, и требовать от него именно наших чисел
  значило бы придумывать договор, которого нет.

  Единственное, что предъявляется числом, — размеры простых типов и
  упакованных записей: там сумма байтов задана однозначно. }

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
  { Поля идут от узкого к широкому: выравнивание обязано вставить пропуски. }
  TMixed = record
    A: Byte;
    B: Int64;
    C: Word;
    D: Integer;
    E: Byte;
  end;

  { Та же запись без пропусков. }
  TMixedPacked = packed record
    A: Byte;
    B: Int64;
    C: Word;
    D: Integer;
    E: Byte;
  end;

  TInner = record
    X, Y: Integer;
  end;

  TOuter = record
    Head: Byte;
    Nested: TInner;
    Tail: Int64;
  end;

  TRecArray = array[0 .. 7] of TMixed;

{ Размеры: у упакованной записи он задан суммой полей, у обычной — не меньше. }
procedure StageSizes(Carrier: TResidentCarrier);
var
  Bad: Integer;
begin
  Bad := 0;

  if SizeOf(TMixedPacked) <> 1 + 8 + 2 + 4 + 1 then Inc(Bad);
  if SizeOf(TMixed) < SizeOf(TMixedPacked) then Inc(Bad);
  if SizeOf(TInner) <> 8 then Inc(Bad);
  if SizeOf(TRecArray) <> 8 * SizeOf(TMixed) then Inc(Bad);
  if SizeOf(TOuter) < 1 + SizeOf(TInner) + 8 then Inc(Bad);

  Carrier.Feed(UInt64(Cardinal(SizeOf(TMixed))));
  Carrier.Feed(UInt64(Cardinal(SizeOf(TMixedPacked))));
  Carrier.Feed(UInt64(Cardinal(SizeOf(TOuter))));
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'align: record size does not match its fields');
end;

{ Поля не наезжают: запись в одно не меняет соседей. }
procedure StageFieldsDoNotOverlap(Carrier: TResidentCarrier);
var
  State: UInt64;
  Item: TMixed;
  Packed_: TMixedPacked;
  Bad: Integer;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap);
  Bad := 0;

  Item.A := 11;
  Item.B := Int64(ResidentNext(State));
  Item.C := 2222;
  Item.D := 333333;
  Item.E := 44;

  var SavedB: Int64 := Item.B;

  Item.A := 99;
  if (Item.B <> SavedB) or (Item.C <> 2222) or (Item.D <> 333333) or (Item.E <> 44) then
    Inc(Bad);

  Item.E := 88;
  if (Item.A <> 99) or (Item.B <> SavedB) or (Item.C <> 2222) or (Item.D <> 333333) then
    Inc(Bad);

  Item.C := 65535;
  if (Item.A <> 99) or (Item.B <> SavedB) or (Item.D <> 333333) or (Item.E <> 88) then
    Inc(Bad);

  { То же в упакованной записи, где пропусков между полями нет вовсе. }
  Packed_.A := 11;
  Packed_.B := SavedB;
  Packed_.C := 2222;
  Packed_.D := 333333;
  Packed_.E := 44;

  Packed_.C := 65535;
  if (Packed_.A <> 11) or (Packed_.B <> SavedB) or (Packed_.D <> 333333) or (Packed_.E <> 44) then
    Inc(Bad);

  Packed_.B := -1;
  if (Packed_.A <> 11) or (Packed_.C <> 65535) or (Packed_.D <> 333333) or (Packed_.E <> 44) then
    Inc(Bad);

  Carrier.Feed(UInt64(SavedB));
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'align: writing one field disturbed its neighbour');
end;

{ Смещения полей: конкретные числа — дело компилятора, а вот порядок и
  непересечение — договор. }
procedure StageOffsets(Carrier: TResidentCarrier);
var
  Item: TMixed;
  Bad: Integer;
  Base: PByte;
  OffA, OffB, OffC, OffD, OffE: NativeInt;
begin
  Bad := 0;
  Base := PByte(@Item);

  OffA := NativeInt(PByte(@Item.A) - Base);
  OffB := NativeInt(PByte(@Item.B) - Base);
  OffC := NativeInt(PByte(@Item.C) - Base);
  OffD := NativeInt(PByte(@Item.D) - Base);
  OffE := NativeInt(PByte(@Item.E) - Base);

  { Первое поле лежит в начале записи. }
  if OffA <> 0 then Inc(Bad);

  { Порядок объявления сохраняется. }
  if not ((OffA < OffB) and (OffB < OffC) and (OffC < OffD) and (OffD < OffE)) then
    Inc(Bad);

  { Между началами соседних полей помещается предыдущее поле целиком. }
  if OffB - OffA < SizeOf(Byte) then Inc(Bad);
  if OffC - OffB < SizeOf(Int64) then Inc(Bad);
  if OffD - OffC < SizeOf(Word) then Inc(Bad);
  if OffE - OffD < SizeOf(Integer) then Inc(Bad);

  { Последнее поле помещается внутрь записи. }
  if OffE + SizeOf(Byte) > SizeOf(TMixed) then Inc(Bad);

  { Широкое поле выровнено по своему размеру. }
  if (OffB mod SizeOf(Int64)) <> 0 then Inc(Bad);

  Carrier.Feed(UInt64(Cardinal(OffB)));
  Carrier.Feed(UInt64(Cardinal(OffE)));
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'align: field offsets contradict the declaration');
end;

{ Массив записей: шаг между элементами равен размеру записи, и элементы не
  наезжают. }
procedure StageArrayStride(Carrier: TResidentCarrier);
var
  State: UInt64;
  Items: TRecArray;
  I, Bad: Integer;
  Step: NativeInt;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 3 + 1);
  Bad := 0;

  for I := 0 to High(Items) do
    begin
      Items[I].A := Byte(I);
      Items[I].B := Int64(I) * 1000 + 7;
      Items[I].C := Word(I * 3);
      Items[I].D := I * 111;
      Items[I].E := Byte(255 - I);
    end;

  Step := NativeInt(PByte(@Items[1]) - PByte(@Items[0]));
  if Step <> SizeOf(TMixed) then Inc(Bad);

  for I := 0 to High(Items) do
    begin
      if Items[I].A <> Byte(I) then Inc(Bad);
      if Items[I].B <> Int64(I) * 1000 + 7 then Inc(Bad);
      if Items[I].C <> Word(I * 3) then Inc(Bad);
      if Items[I].D <> I * 111 then Inc(Bad);
      if Items[I].E <> Byte(255 - I) then Inc(Bad);
    end;

  { Запись в последний элемент не задевает предыдущий. }
  Items[High(Items)].B := -12345;
  if Items[High(Items) - 1].B <> Int64(High(Items) - 1) * 1000 + 7 then Inc(Bad);

  Carrier.Feed(UInt64(Cardinal(Step)));
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'align: array of records has the wrong stride');
end;

{ Вложенная запись: её поля лежат внутри внешней и сохраняются целиком. }
procedure StageNested(Carrier: TResidentCarrier);
var
  State: UInt64;
  Outer: TOuter;
  Bad: Integer;
  InnerStart, OuterStart: NativeInt;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 5 + 2);
  Bad := 0;

  Outer.Head := 7;
  Outer.Nested.X := Integer(ResidentNext(State));
  Outer.Nested.Y := Integer(ResidentNext(State));
  Outer.Tail := Int64(ResidentNext(State));

  var SavedX: Integer := Outer.Nested.X;
  var SavedY: Integer := Outer.Nested.Y;
  var SavedTail: Int64 := Outer.Tail;

  OuterStart := NativeInt(PByte(@Outer));
  InnerStart := NativeInt(PByte(@Outer.Nested));

  { Вложенная запись лежит внутри внешней. }
  if InnerStart <= OuterStart then Inc(Bad);
  if InnerStart + SizeOf(TInner) > OuterStart + SizeOf(TOuter) then Inc(Bad);

  { Копия вложенной части — настоящая копия. }
  var Copy_: TInner := Outer.Nested;
  Copy_.X := Copy_.X + 1;
  if Outer.Nested.X <> SavedX then Inc(Bad);
  if Copy_.Y <> SavedY then Inc(Bad);

  { Запись во внешнее поле не трогает вложенное. }
  Outer.Head := 200;
  if (Outer.Nested.X <> SavedX) or (Outer.Nested.Y <> SavedY) then Inc(Bad);
  Outer.Tail := -1;
  if (Outer.Nested.X <> SavedX) or (Outer.Nested.Y <> SavedY) then Inc(Bad);
  Outer.Nested.X := 0;
  if (Outer.Head <> 200) or (Outer.Tail <> -1) or (Outer.Nested.Y <> SavedY) then Inc(Bad);

  Carrier.Feed(UInt64(Cardinal(SavedX)));
  Carrier.Feed(UInt64(SavedTail));
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'align: nested record does not sit inside the outer one');
end;

{ Побайтовая копия записи: то же содержимое, независимая память. }
procedure StageByteCopy(Carrier: TResidentCarrier);
var
  State: UInt64;
  Source, Target: TMixedPacked;
  I, Bad: Integer;
  A, B: PByte;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 7 + 3);
  Bad := 0;

  Source.A := 1;
  Source.B := Int64(ResidentNext(State));
  Source.C := 2;
  Source.D := 3;
  Source.E := 4;

  Move(Source, Target, SizeOf(TMixedPacked));

  if Target.A <> Source.A then Inc(Bad);
  if Target.B <> Source.B then Inc(Bad);
  if Target.C <> Source.C then Inc(Bad);
  if Target.D <> Source.D then Inc(Bad);
  if Target.E <> Source.E then Inc(Bad);

  A := PByte(@Source);
  B := PByte(@Target);
  for I := 0 to SizeOf(TMixedPacked) - 1 do
    begin
      if A^ <> B^ then Inc(Bad);
      Inc(A);
      Inc(B);
    end;

  { Память независима: правка копии не трогает источник. }
  Target.B := -1;
  if Source.B = -1 then Inc(Bad);

  Carrier.Feed(UInt64(Source.B));
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'align: byte copy of a packed record differs from the original');
end;

initialization
  ResidentRegisterStage('align-array-stride', @StageArrayStride);
  ResidentRegisterStage('align-byte-copy', @StageByteCopy);
  ResidentRegisterStage('align-fields-do-not-overlap', @StageFieldsDoNotOverlap);
  ResidentRegisterStage('align-nested', @StageNested);
  ResidentRegisterStage('align-offsets', @StageOffsets);
  ResidentRegisterStage('align-sizes', @StageSizes);

end.
