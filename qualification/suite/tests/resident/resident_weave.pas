unit resident_weave;

{ Семейство `weave` — значение, которое нигде не задерживается.

  Обычная переменная живёт в регистре, и оптимизатору легко: он видит все
  места, где её читают и пишут. Здесь одно и то же число на каждом шаге меняет
  место жительства — локал, поле объекта, ячейка динамического массива, ключ
  словаря, карман носителя, захваченная переменная замыкания, поле записи
  внутри массива записей, значение за интерфейсом, десятичная запись строкой —
  и на каждом переезде к нему применяется операция.

  Каждое место хранения устроено по-своему: у одних есть счётчик ссылок, у
  других — своя память, у третьих — хеш и корзины. Держать значение в регистре
  через такой маршрут нельзя, а вот потерять по дороге — можно: при переезде в
  словарь и обратно, при перестройке массива, при захвате в замыкание, при
  превращении в строку и обратно.

  Порядок мест — перестановка от сида, поэтому маршрут известен только при
  счёте. Оракул плоский: те же операции в том же порядке над обычной
  переменной, без единого переезда. }

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
  SysUtils, Generics.Collections, resident_core;

implementation

const
  Places = 8;

type
  IWeaveCell = interface
    ['{4D5A0005-0000-0000-0000-000057454156}']
    function Read: Int64;
    procedure Write(const Value: Int64);
  end;

  TWeaveCell = class(TInterfacedObject, IWeaveCell)
  private
    FValue: Int64;
  public
    function Read: Int64;
    procedure Write(const Value: Int64);
  end;

  TWeaveHolder = class
  public
    Field: Int64;
  end;

  TWeaveSlot = record
    Before: Int64;
    Payload: Int64;
    After: Int64;
  end;

  { Карман носителя: единственное место, которое переживает стадию и живёт
    между оборотами кольца. }
  TWeavePocket = class(TResidentPocket)
  public
    Kept: Int64;
    Visits: Int64;
  end;

function TWeaveCell.Read: Int64;
begin
  Result := FValue;
end;

procedure TWeaveCell.Write(const Value: Int64);
begin
  FValue := Value;
end;

{ Операция, привязанная к месту: у каждого места своя. }
function Touch(Place: Integer; const Value: Int64): Int64;
begin
  case Place of
    0: Result := Value + 13;
    1: Result := Value * 3 - 1;
    2: Result := Value xor (Value shr 11);
    3: Result := Value + (Value and 255);
    4: Result := Value - 7;
    5: Result := (Value shl 1) + 3;
    6: Result := Value + 101;
  else
    Result := Value xor $5A5A;
  end;
end;

procedure BuildRoute(var Route: array of Integer; var State: UInt64);
var
  I, J, Spare: Integer;
begin
  for I := 0 to High(Route) do
    Route[I] := I;
  for I := High(Route) downto 1 do
    begin
      J := Integer(ResidentNext(State) mod UInt64(I + 1));
      Spare := Route[I];
      Route[I] := Route[J];
      Route[J] := Spare;
    end;
end;

{ Тур по всем местам хранения: на каждом переезде значение оседает в новом
  виде памяти, там его правят и увозят дальше. }
procedure StageTour(Carrier: TResidentCarrier);
var
  State: UInt64;
  Route: array[0 .. Places - 1] of Integer;
  Holder: TWeaveHolder;
  Cells: TArray<Int64>;
  Table: TDictionary<Integer, Int64>;
  Slots: array[0 .. 3] of TWeaveSlot;
  Cell: IWeaveCell;
  Captured: Int64;
  Reader: TFunc<Int64>;
  Pocket: TWeavePocket;
  I, Rounds, J: Integer;
  Live, Flat: Int64;
  Text: string;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap);
  BuildRoute(Route, State);
  Rounds := 3 + Integer(ResidentNext(State) and 3);
  Live := Int64(ResidentNext(State) and $FFFF);
  Flat := Live;

  Pocket := Carrier.PocketAs<TWeavePocket>('weave-tour');
  Holder := TWeaveHolder.Create;
  Table := TDictionary<Integer, Int64>.Create;
  Cell := TWeaveCell.Create;
  SetLength(Cells, 6);
  try
    for J := 1 to Rounds do
      for I := 0 to High(Route) do
        case Route[I] of
          0:
            begin
              { Обычный локал. }
              Live := Touch(0, Live);
            end;
          1:
            begin
              { Поле объекта. }
              Holder.Field := Live;
              Holder.Field := Touch(1, Holder.Field);
              Live := Holder.Field;
            end;
          2:
            begin
              { Ячейка динамического массива, который тут же и растёт. }
              SetLength(Cells, Length(Cells) + 1);
              Cells[High(Cells)] := Live;
              Cells[High(Cells)] := Touch(2, Cells[High(Cells)]);
              Live := Cells[High(Cells)];
              SetLength(Cells, 6);
            end;
          3:
            begin
              { Словарь: значение уезжает по ключу и возвращается. }
              Table.AddOrSetValue(I, Live);
              Table[I] := Touch(3, Table[I]);
              Live := Table[I];
              Table.Remove(I);
            end;
          4:
            begin
              { Карман носителя — он переживёт и стадию, и оборот. }
              Pocket.Kept := Live;
              Pocket.Kept := Touch(4, Pocket.Kept);
              Live := Pocket.Kept;
            end;
          5:
            begin
              { Захват замыкания: значение живёт в кадре, который пережил
                постройку функции. }
              Captured := Live;
              Reader := function: Int64
                begin
                  Result := Touch(5, Captured);
                end;
              Live := Reader();
              Reader := nil;
            end;
          6:
            begin
              { Поле записи внутри массива записей, между двумя соседями. }
              Slots[I and 3].Before := -1;
              Slots[I and 3].Payload := Live;
              Slots[I and 3].After := -2;
              Slots[I and 3].Payload := Touch(6, Slots[I and 3].Payload);
              Live := Slots[I and 3].Payload;
            end;
        else
          begin
            { За интерфейсом: чтение и запись идут через таблицу методов. }
            Cell.Write(Live);
            Cell.Write(Touch(7, Cell.Read));
            Live := Cell.Read;
          end;
        end;
  finally
    Cell := nil;
    Reader := nil;
    FreeAndNil(Table);
    FreeAndNil(Holder);
    Cells := nil;
  end;

  for J := 1 to Rounds do
    for I := 0 to High(Route) do
      Flat := Touch(Route[I], Flat);

  Inc(Pocket.Visits);

  { Строковая запись числа — ещё одно место жительства, и обратный разбор
    обязан вернуть то же самое. }
  Text := IntToStr(Live);

  Carrier.Feed(UInt64(Live));
  Carrier.Feed(UInt64(Pocket.Visits));
  Carrier.FeedWide(Text);
  Carrier.Claim(Live = Flat, 'weave: value changed while moving between places');
  Carrier.Claim(StrToInt64(Text) = Live, 'weave: value did not survive its decimal form');
end;

{ Два значения путешествуют одновременно и на каждом шаге меняются местами:
  ни одно не имеет права уехать по чужому маршруту. }
procedure StageInterleaved(Carrier: TResidentCarrier);
var
  State: UInt64;
  Route: array[0 .. Places - 1] of Integer;
  Holder: TWeaveHolder;
  Cell: IWeaveCell;
  I, J, Rounds: Integer;
  Left, Right, FlatLeft, FlatRight, Spare: Int64;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 3 + 1);
  BuildRoute(Route, State);
  Rounds := 4 + Integer(ResidentNext(State) and 3);
  Left := Int64(ResidentNext(State) and $FFFF);
  Right := Int64(ResidentNext(State) and $FFFF);
  FlatLeft := Left;
  FlatRight := Right;

  Holder := TWeaveHolder.Create;
  Cell := TWeaveCell.Create;
  try
    for J := 1 to Rounds do
      for I := 0 to High(Route) do
        begin
          { Левое оседает в поле объекта, правое — за интерфейсом. }
          Holder.Field := Left;
          Cell.Write(Right);

          Holder.Field := Touch(Route[I], Holder.Field);
          Cell.Write(Touch(Route[I], Cell.Read));

          { И меняются местами, не задев друг друга. }
          Spare := Holder.Field;
          Left := Cell.Read;
          Right := Spare;
        end;
  finally
    Cell := nil;
    FreeAndNil(Holder);
  end;

  for J := 1 to Rounds do
    for I := 0 to High(Route) do
      begin
        FlatLeft := Touch(Route[I], FlatLeft);
        FlatRight := Touch(Route[I], FlatRight);
        Spare := FlatLeft;
        FlatLeft := FlatRight;
        FlatRight := Spare;
      end;

  Carrier.Feed(UInt64(Left));
  Carrier.Feed(UInt64(Right));
  Carrier.Claim(Left = FlatLeft, 'weave: interleaved values took each other''s route');
  Carrier.Claim(Right = FlatRight, 'weave: interleaved values swapped wrongly');
end;

{ Число ездит через свою десятичную запись: на каждом шаге превращается в
  строку и разбирается обратно, а строка при этом растёт и режется. }
procedure StageThroughText(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, Steps, Bad: Integer;
  Live, Flat: Int64;
  Text, Tail: string;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 5 + 2);
  Steps := 12 + Integer(ResidentNext(State) and 7);
  Live := Int64(ResidentNext(State) and $FFFF) + 1;
  Flat := Live;
  Bad := 0;

  for I := 1 to Steps do
    begin
      Text := IntToStr(Live);
      { Хвост записи — ещё одно наблюдение за тем же числом. }
      Tail := Copy(Text, Length(Text), 1);
      if StrToInt64(Text) <> Live then
        Inc(Bad);
      if Length(Tail) <> 1 then
        Inc(Bad);

      Live := StrToInt64(Text) + StrToInt(Tail) + Length(Text);
      Flat := Flat + (Abs(Flat) mod 10) + Length(IntToStr(Flat));
    end;

  Carrier.Feed(UInt64(Live));
  Carrier.FeedWide(Text);
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'weave: decimal form did not parse back to its number');
  Carrier.Claim(Live = Flat, 'weave: trip through text changed the number');
end;

{ Словарь как единственное место жительства: значение живёт только в нём, а
  ключи всё время меняются, заставляя таблицу перестраиваться. }
procedure StageDictionaryHome(Carrier: TResidentCarrier);
var
  State: UInt64;
  Table: TDictionary<Integer, Int64>;
  I, Steps, Key, Bad: Integer;
  Live, Flat: Int64;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 7 + 3);
  Steps := 24 + Integer(ResidentNext(State) and 15);
  Live := Int64(ResidentNext(State) and $FFFF);
  Flat := Live;
  Bad := 0;

  Table := TDictionary<Integer, Int64>.Create;
  try
    Table.Add(0, Live);
    for I := 1 to Steps do
      begin
        Key := I - 1;
        if not Table.TryGetValue(Key, Live) then
          Inc(Bad);

        { Новое место — новый ключ; старое сразу освобождается, поэтому
          таблица растёт и чистится одновременно. }
        Table.Add(I, Touch(I and 7, Live));
        Table.Remove(Key);
        if Table.Count <> 1 then
          Inc(Bad);

        Flat := Touch(I and 7, Flat);
      end;

    if not Table.TryGetValue(Steps, Live) then
      Inc(Bad);
  finally
    FreeAndNil(Table);
  end;

  Carrier.Feed(UInt64(Live));
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'weave: dictionary lost the value or kept the wrong number of keys');
  Carrier.Claim(Live = Flat, 'weave: value living in a dictionary drifted');
end;

{ Карман носителя как долгая память: значение, положенное на одном обороте,
  забирается на следующем, и цепочка тянется через всю жизнь носителя. }
procedure StageAcrossLaps(Carrier: TResidentCarrier);
var
  Pocket: TWeavePocket;
  Expected: Int64;
  I: Integer;
begin
  Pocket := Carrier.PocketAs<TWeavePocket>('weave-across-laps');

  { Первый заход заводит цепочку, дальше каждый продолжает её ровно на шаг. }
  if Pocket.Visits = 0 then
    Pocket.Kept := Int64(Carrier.Serial) + 1;

  Inc(Pocket.Visits);
  Pocket.Kept := Touch(Integer(Pocket.Visits and 7), Pocket.Kept);

  { Ожидаемое пересчитывается с самого начала: та же цепочка, но за один
    присест и без кармана. }
  Expected := Int64(Carrier.Serial) + 1;
  for I := 1 to Pocket.Visits do
    Expected := Touch(Integer(Int64(I) and 7), Expected);

  Carrier.Feed(UInt64(Pocket.Kept));
  Carrier.Feed(UInt64(Pocket.Visits));
  Carrier.Claim(Pocket.Kept = Expected, 'weave: value kept between laps drifted from the replayed chain');
  Carrier.Claim(Pocket.Visits > 0, 'weave: pocket did not count its visits');
end;

initialization
  ResidentRegisterStage('weave-across-laps', @StageAcrossLaps);
  ResidentRegisterStage('weave-dictionary-home', @StageDictionaryHome);
  ResidentRegisterStage('weave-interleaved', @StageInterleaved);
  ResidentRegisterStage('weave-through-text', @StageThroughText);
  ResidentRegisterStage('weave-tour', @StageTour);

end.
