unit resident_form;

{ Семейство `form` — одна работа, записанная разными конструкциями.

  Компилятор волен приводить разные записи к одному машинному коду: цикл со
  счётчиком и цикл с условием, перебор по индексу и перебор по элементам,
  побайтовый цикл и библиотечный перенос блока. Пока приведение честное, ответ
  от формы записи не зависит — и это ровно то, что здесь предъявляется.

  Стадия строит две-три записи одного вычисления и требует совпадения. Такая
  проверка не нуждается ни во внешнем эталоне, ни в предыдущем прогоне: если
  две формы разошлись, ошибочна хотя бы одна, и это факт, а не подозрение.
  Заодно она ловит класс, который не виден покомпонентно, — когда каждая форма
  по отдельности выглядит разумной, а машинный код у них общий и неверный.

  Формы подобраны так, чтобы отличаться механикой, а не оформлением: перенос
  блока против побайтового цикла, разворот на месте против сборки в новый
  буфер, поиск с досрочным выходом против поиска с флагом. Переписывать
  «то же самое другими скобками» смысла нет — такие пары компилятор сводит к
  одному дереву ещё до оптимизаций, и проверять будет нечего. }

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
  SysUtils, Math, resident_core;

implementation

const
  Span = 24;

type
  TFormBlock = array[0 .. Span - 1] of Int64;
  TFormBytes = array[0 .. 63] of Byte;

procedure FillBlock(var Block: TFormBlock; var State: UInt64);
var
  I: Integer;
begin
  for I := 0 to High(Block) do
    Block[I] := Int64(ResidentNext(State) and $FFFF) - 32768;
end;

{ Свёртка шестью способами. Операция ассоциативна, поэтому порядок обхода не
  меняет ответ — меняется только машина обхода. }
procedure StageLoopKinds(Carrier: TResidentCarrier);
var
  State: UInt64;
  Block: TFormBlock;
  I: Integer;
  ByFor, ByDownto, ByWhile, ByRepeat, ByRecursion, ByPointer: Int64;
  Cursor: ^Int64;

  function Fold(Index: Integer): Int64;
  begin
    if Index > High(Block) then
      Result := 0
    else
      Result := Block[Index] + Fold(Index + 1);
  end;

begin
  State := Carrier.Seed xor UInt64(Carrier.Lap);
  FillBlock(Block, State);

  ByFor := 0;
  for I := 0 to High(Block) do
    ByFor := ByFor + Block[I];

  ByDownto := 0;
  for I := High(Block) downto 0 do
    ByDownto := ByDownto + Block[I];

  ByWhile := 0;
  I := 0;
  while I <= High(Block) do
    begin
      ByWhile := ByWhile + Block[I];
      Inc(I);
    end;

  ByRepeat := 0;
  I := 0;
  repeat
    ByRepeat := ByRepeat + Block[I];
    Inc(I);
  until I > High(Block);

  ByRecursion := Fold(0);

  ByPointer := 0;
  Cursor := @Block[0];
  for I := 0 to High(Block) do
    begin
      ByPointer := ByPointer + Cursor^;
      Inc(Cursor);
    end;

  Carrier.Feed(UInt64(ByFor));
  Carrier.Claim(ByFor = ByDownto, 'form: counted loop disagrees with the reversed one');
  Carrier.Claim(ByFor = ByWhile, 'form: counted loop disagrees with the conditional one');
  Carrier.Claim(ByFor = ByRepeat, 'form: counted loop disagrees with the post-conditional one');
  Carrier.Claim(ByFor = ByRecursion, 'form: counted loop disagrees with recursion');
  Carrier.Claim(ByFor = ByPointer, 'form: counted loop disagrees with pointer walking');
end;

{ Перебор по элементам против перебора по индексу. }
procedure StageForIn(Carrier: TResidentCarrier);
var
  State: UInt64;
  Data: TArray<Int64>;
  I: Integer;
  ByIndex, ByElement, ByXorIndex, ByXorElement: Int64;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 3 + 1);
  SetLength(Data, Span);
  for I := 0 to High(Data) do
    Data[I] := Int64(ResidentNext(State) and $FFFFF);

  ByIndex := 0;
  ByXorIndex := 0;
  for I := 0 to High(Data) do
    begin
      ByIndex := ByIndex + Data[I];
      ByXorIndex := ByXorIndex xor Data[I];
    end;

  ByElement := 0;
  ByXorElement := 0;
  for var Item in Data do
    begin
      ByElement := ByElement + Item;
      ByXorElement := ByXorElement xor Item;
    end;

  Carrier.Feed(UInt64(ByIndex));
  Carrier.Feed(UInt64(ByXorIndex));
  Carrier.Claim(ByIndex = ByElement, 'form: element walk disagrees with index walk');
  Carrier.Claim(ByXorIndex = ByXorElement, 'form: element walk lost a value');

  Data := nil;
end;

{ Перенос блока с перекрытием. Библиотечный перенос обязан вести себя так,
  будто источник сперва скопировали целиком. }
procedure StageBufferMove(Carrier: TResidentCarrier);
var
  State: UInt64;
  Live, Mirror, Origin: TFormBytes;
  I, Shift, Bad: Integer;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 5 + 2);
  for I := 0 to High(Origin) do
    Origin[I] := Byte(ResidentNext(State) and $FF);
  Bad := 0;

  { Вперёд: приёмник правее источника, области перекрываются. }
  Live := Origin;
  Shift := 5;
  Move(Live[0], Live[Shift], Length(Live) - Shift);

  Mirror := Origin;
  for I := Length(Mirror) - Shift - 1 downto 0 do
    Mirror[I + Shift] := Mirror[I];

  for I := 0 to High(Live) do
    if Live[I] <> Mirror[I] then
      Inc(Bad);

  { Назад: приёмник левее источника. }
  Live := Origin;
  Move(Live[Shift], Live[0], Length(Live) - Shift);

  Mirror := Origin;
  for I := 0 to Length(Mirror) - Shift - 1 do
    Mirror[I] := Mirror[I + Shift];

  for I := 0 to High(Live) do
    if Live[I] <> Mirror[I] then
      Inc(Bad);

  for I := 0 to High(Live) do
    Carrier.Feed(UInt64(Live[I]));
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'form: overlapping block move disagrees with a hand copy');
end;

{ Заполнение и сравнение блоков против побайтовых циклов. }
procedure StageFillAndCompare(Carrier: TResidentCarrier);
var
  State: UInt64;
  Live, Mirror: TFormBytes;
  I, Bad, Value: Integer;
  SameByLib, SameByHand: Boolean;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 7 + 3);
  Value := Integer(ResidentNext(State) and $FF);
  Bad := 0;

  FillChar(Live, SizeOf(Live), Byte(Value));
  for I := 0 to High(Mirror) do
    Mirror[I] := Byte(Value);
  for I := 0 to High(Live) do
    if Live[I] <> Mirror[I] then
      Inc(Bad);

  SameByLib := CompareMem(@Live, @Mirror, SizeOf(Live));
  SameByHand := True;
  for I := 0 to High(Live) do
    if Live[I] <> Mirror[I] then
      SameByHand := False;
  if SameByLib <> SameByHand then
    Inc(Bad);

  { Один байт врозь — и оба способа обязаны это увидеть. }
  Mirror[High(Mirror) div 2] := Byte(Value xor $FF);
  SameByLib := CompareMem(@Live, @Mirror, SizeOf(Live));
  SameByHand := True;
  for I := 0 to High(Live) do
    if Live[I] <> Mirror[I] then
      SameByHand := False;
  if SameByLib <> SameByHand then
    Inc(Bad);
  if SameByLib then
    Inc(Bad);

  Carrier.Feed(UInt64(Cardinal(Value)));
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'form: library fill or compare disagrees with the byte loop');
end;

{ Строка, собранная присоединением и записью по месту. }
procedure StageStringBuild(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, Count: Integer;
  ByConcat, ByPlace: string;
  Ch: Char;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 11 + 5);
  Count := 12 + Integer(ResidentNext(State) and 15);

  ByConcat := '';
  for I := 1 to Count do
    begin
      Ch := Char(Ord('a') + (I mod 26));
      ByConcat := ByConcat + Ch;
    end;

  SetLength(ByPlace, Count);
  for I := 1 to Count do
    ByPlace[I] := Char(Ord('a') + (I mod 26));

  Carrier.FeedWide(ByConcat);
  Carrier.Feed(UInt64(Cardinal(Length(ByConcat))));
  Carrier.Claim(ByConcat = ByPlace, 'form: concatenation disagrees with writing in place');
  Carrier.Claim(Length(ByConcat) = Count, 'form: built string has the wrong length');
end;

{ Вырезка куска массива библиотекой и руками. }
procedure StageArrayCopy(Carrier: TResidentCarrier);
var
  State: UInt64;
  Source, ByLib, ByHand: TArray<Int64>;
  I, Start, Count, Bad: Integer;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 13 + 7);
  SetLength(Source, Span);
  for I := 0 to High(Source) do
    Source[I] := Int64(ResidentNext(State) and $FFFF);
  Start := 3 + Integer(ResidentNext(State) and 7);
  Count := 5 + Integer(ResidentNext(State) and 7);
  Bad := 0;

  ByLib := Copy(Source, Start, Count);

  SetLength(ByHand, Count);
  for I := 0 to Count - 1 do
    ByHand[I] := Source[Start + I];

  if Length(ByLib) <> Length(ByHand) then
    Inc(Bad)
  else
    for I := 0 to High(ByLib) do
      if ByLib[I] <> ByHand[I] then
        Inc(Bad);

  { Вырезка — это новый буфер, а не второе имя старого. }
  ByLib[0] := ByLib[0] + 1;
  if Source[Start] = ByLib[0] then
    Inc(Bad);

  Carrier.Feed(UInt64(Cardinal(Length(ByHand))));
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'form: library slice disagrees with a hand slice');

  Source := nil;
  ByLib := nil;
  ByHand := nil;
end;

{ Двойной цикл против одинарного с делением и остатком. }
procedure StageNestedVersusFlat(Carrier: TResidentCarrier);
var
  State: UInt64;
  Grid: array[0 .. 5, 0 .. 7] of Int64;
  Row, Col, I: Integer;
  ByNested, ByFlat: Int64;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 17 + 9);
  for Row := 0 to 5 do
    for Col := 0 to 7 do
      Grid[Row, Col] := Int64(ResidentNext(State) and $FFF);

  ByNested := 0;
  for Row := 0 to 5 do
    for Col := 0 to 7 do
      ByNested := ByNested + Grid[Row, Col] * (Row + 1) - Col;

  ByFlat := 0;
  for I := 0 to 6 * 8 - 1 do
    ByFlat := ByFlat + Grid[I div 8, I mod 8] * (I div 8 + 1) - (I mod 8);

  Carrier.Feed(UInt64(ByNested));
  Carrier.Claim(ByNested = ByFlat, 'form: nested walk disagrees with the flattened one');
end;

{ Поиск с досрочным выходом, с выходом из процедуры и с флагом. }
procedure StageEarlyExit(Carrier: TResidentCarrier);
var
  State: UInt64;
  Data: TArray<Int64>;
  Needle: Int64;
  I, ByBreak, ByFlag, ByFunc, Probes: Integer;

  function Search(const Values: TArray<Int64>; const Target: Int64): Integer;
  var
    J: Integer;
  begin
    Result := -1;
    for J := 0 to High(Values) do
      if Values[J] = Target then
        begin
          Result := J;
          Exit;
        end;
  end;

begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 19 + 11);
  SetLength(Data, Span);
  for I := 0 to High(Data) do
    Data[I] := Int64(I) * 3 + Int64(ResidentNext(State) and 1);
  Needle := Data[Integer(ResidentNext(State) and 15)];

  ByBreak := -1;
  Probes := 0;
  for I := 0 to High(Data) do
    begin
      Inc(Probes);
      if Data[I] = Needle then
        begin
          ByBreak := I;
          Break;
        end;
    end;

  ByFlag := -1;
  I := 0;
  while (I <= High(Data)) and (ByFlag < 0) do
    begin
      if Data[I] = Needle then
        ByFlag := I;
      Inc(I);
    end;

  ByFunc := Search(Data, Needle);

  Carrier.Feed(UInt64(Cardinal(ByBreak)));
  Carrier.Feed(UInt64(Cardinal(Probes)));
  Carrier.Claim(ByBreak = ByFlag, 'form: break search disagrees with flag search');
  Carrier.Claim(ByBreak = ByFunc, 'form: break search disagrees with exit search');
  Carrier.Claim(ByBreak >= 0, 'form: search missed a value that is present');
  Carrier.Claim(Probes = ByBreak + 1, 'form: break did not stop the walk');

  Data := nil;
end;

{ Обмен через временную и через исключающее или. }
procedure StageSwap(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, Bad: Integer;
  A, B, TempA, TempB, XorA, XorB, Spare: Int64;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 23 + 13);
  Bad := 0;

  for I := 1 to 16 do
    begin
      A := Int64(ResidentNext(State));
      B := Int64(ResidentNext(State));

      TempA := A;
      TempB := B;
      Spare := TempA;
      TempA := TempB;
      TempB := Spare;

      XorA := A;
      XorB := B;
      XorA := XorA xor XorB;
      XorB := XorA xor XorB;
      XorA := XorA xor XorB;

      if (TempA <> XorA) or (TempB <> XorB) then
        Inc(Bad);
      if (TempA <> B) or (TempB <> A) then
        Inc(Bad);

      Carrier.Feed(UInt64(TempA));
    end;

  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'form: two ways of swapping disagree');
end;

{ Минимум и максимум ветвлением и библиотекой. }
procedure StageMinMax(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, Bad: Integer;
  A, B, ByBranch, ByLib: Int64;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 29 + 17);
  Bad := 0;

  for I := 1 to 24 do
    begin
      A := Int64(ResidentNext(State) and $FFFF) - 32768;
      B := Int64(ResidentNext(State) and $FFFF) - 32768;

      if A < B then
        ByBranch := A
      else
        ByBranch := B;
      ByLib := Min(A, B);
      if ByBranch <> ByLib then
        Inc(Bad);

      if A > B then
        ByBranch := A
      else
        ByBranch := B;
      ByLib := Max(A, B);
      if ByBranch <> ByLib then
        Inc(Bad);

      { Сумма наименьшего и наибольшего равна сумме исходных — на любых
        знаках и при равенстве. }
      if Min(A, B) + Max(A, B) <> A + B then
        Inc(Bad);

      Carrier.Feed(UInt64(ByLib));
    end;

  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'form: branch min/max disagrees with the library one');
end;

{ Разворот на месте и сборкой в новый буфер. }
procedure StageReverse(Carrier: TResidentCarrier);
var
  State: UInt64;
  Block, InPlace, Rebuilt: TFormBlock;
  I, Bad: Integer;
  Spare: Int64;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 31 + 19);
  FillBlock(Block, State);
  Bad := 0;

  InPlace := Block;
  for I := 0 to (Length(InPlace) div 2) - 1 do
    begin
      Spare := InPlace[I];
      InPlace[I] := InPlace[High(InPlace) - I];
      InPlace[High(InPlace) - I] := Spare;
    end;

  for I := 0 to High(Block) do
    Rebuilt[High(Block) - I] := Block[I];

  for I := 0 to High(Block) do
    if InPlace[I] <> Rebuilt[I] then
      Inc(Bad);

  { Двойной разворот возвращает исходное. }
  for I := 0 to (Length(InPlace) div 2) - 1 do
    begin
      Spare := InPlace[I];
      InPlace[I] := InPlace[High(InPlace) - I];
      InPlace[High(InPlace) - I] := Spare;
    end;
  for I := 0 to High(Block) do
    if InPlace[I] <> Block[I] then
      Inc(Bad);

  Carrier.Feed(UInt64(Rebuilt[0]));
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'form: in-place reversal disagrees with rebuilding');
end;

{ Одна сумма, накопленная в разных типах. Домен подобран так, что она
  помещается в самый узкий из них, значит различий быть не может. }
procedure StageAccumulatorWidth(Carrier: TResidentCarrier);
var
  State: UInt64;
  Block: TFormBlock;
  I: Integer;
  AsInt: Integer;
  AsWide: Int64;
  AsCard: Cardinal;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 37 + 23);
  for I := 0 to High(Block) do
    Block[I] := Int64(ResidentNext(State) and $FFF);

  AsInt := 0;
  AsWide := 0;
  AsCard := 0;
  for I := 0 to High(Block) do
    begin
      AsInt := AsInt + Integer(Block[I]);
      AsWide := AsWide + Block[I];
      AsCard := AsCard + Cardinal(Block[I]);
    end;

  Carrier.Feed(UInt64(AsWide));
  Carrier.Claim(Int64(AsInt) = AsWide, 'form: narrow accumulator lost the sum');
  Carrier.Claim(Int64(AsCard) = AsWide, 'form: unsigned accumulator lost the sum');
  Carrier.Claim(AsWide < Int64(Span) * 4096, 'form: sum escaped its own domain');
end;

initialization
  ResidentRegisterStage('form-accumulator-width', @StageAccumulatorWidth);
  ResidentRegisterStage('form-array-copy', @StageArrayCopy);
  ResidentRegisterStage('form-buffer-move', @StageBufferMove);
  ResidentRegisterStage('form-early-exit', @StageEarlyExit);
  ResidentRegisterStage('form-fill-and-compare', @StageFillAndCompare);
  ResidentRegisterStage('form-for-in', @StageForIn);
  ResidentRegisterStage('form-loop-kinds', @StageLoopKinds);
  ResidentRegisterStage('form-min-max', @StageMinMax);
  ResidentRegisterStage('form-nested-vs-flat', @StageNestedVersusFlat);
  ResidentRegisterStage('form-reverse', @StageReverse);
  ResidentRegisterStage('form-string-build', @StageStringBuild);
  ResidentRegisterStage('form-swap', @StageSwap);

end.
