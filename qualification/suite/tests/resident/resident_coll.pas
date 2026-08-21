unit resident_coll;

{ Семейство `coll` — коллекции времени выполнения.

  Коллекция — это обещание: положил столько-то, получишь ровно столько же и
  ровно то же, в порядке, который она обязалась держать. Здесь это обещание
  проверяется через рост до перестройки внутреннего устройства и обратно:
  список переезжает по мере наполнения, словарь перехэшируется, очередь
  прокручивает кольцо, и всё положенное обязано это пережить.

  Порядок обхода берётся только там, где он обещан: список и очередь его дают,
  словарь — нет. Поэтому от словаря берутся величины, не зависящие от порядка:
  число элементов, наличие ключа, значение по ключу и коммутативная свёртка по
  всем парам. Сумма не зависит от того, в каком порядке словарь решил их
  разложить, а вот потеря или задвоение пары её ломают.

  Хэш-значения наружу не идут: конкретное число — дело реализации хэш-функции,
  и оно вправе отличаться между компиляторами. Идёт только то, что обязано
  выполняться при любой честной хэш-функции. }

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
  SysUtils, Classes, Generics.Defaults, Generics.Collections, resident_core;

implementation

type
  TResidentEntry = record
    Key: Integer;
    Weight: Int64;
    Label_: string;
  end;

  TResidentNode = class
  private
    FKey: Integer;
    FTally: PResidentTally;
  public
    constructor Create(AKey: Integer; ATally: PResidentTally);
    destructor Destroy; override;
    property Key: Integer read FKey;
  end;

  TResidentCollPocket = class(TResidentPocket)
  private
    FTable: TDictionary<Integer, Int64>;
    FRing: TQueue<Int64>;
    FRounds: Int64;
  public
    destructor Destroy; override;
  end;

constructor TResidentNode.Create(AKey: Integer; ATally: PResidentTally);
begin
  inherited Create;
  FKey := AKey;
  FTally := ATally;
  if FTally <> nil then
    Inc(FTally^.Born);
end;

destructor TResidentNode.Destroy;
begin
  if FTally <> nil then
    Inc(FTally^.Gone);
  inherited Destroy;
end;

destructor TResidentCollPocket.Destroy;
begin
  FTable.Free;
  FRing.Free;
  inherited Destroy;
end;

{ Список: порядок обещан, поэтому его можно предъявлять поэлементно. }
procedure StageListOrder(Carrier: TResidentCarrier);
var
  List: TList<Int64>;
  I, Room: Integer;
begin
  List := TList<Int64>.Create;
  try
    Room := 4 + (Carrier.Lap mod 13);
    for I := 0 to Room - 1 do
      List.Add(Carrier.Tag.Wide + I);
    Carrier.Feed(UInt64(Cardinal(List.Count)));
    for I := 0 to List.Count - 1 do
      Carrier.Feed(UInt64(List[I]));

    { Вставка в начало обязана сдвинуть весь хвост ровно на одну позицию. }
    List.Insert(0, -1);
    Carrier.Feed(UInt64(List[0]));
    Carrier.Feed(UInt64(List[1]));
    Carrier.Feed(UInt64(Ord(List[1] = Carrier.Tag.Wide)));
    Carrier.Feed(UInt64(Cardinal(List.Count)));

    { Удаление из середины — тот же сдвиг в обратную сторону. }
    List.Delete(1);
    Carrier.Feed(UInt64(List[1]));
    Carrier.Feed(UInt64(Cardinal(List.Count)));

    { Обмен местами не меняет состав. }
    if List.Count >= 2 then
    begin
      List.Exchange(0, List.Count - 1);
      Carrier.Feed(UInt64(List[0]));
      Carrier.Feed(UInt64(List[List.Count - 1]));
    end;
  finally
    List.Free;
  end;
end;

{ Рост списка: ёмкость растёт скачками, но содержимое обязано пережить каждый
  переезд без потерь. }
procedure StageListGrowth(Carrier: TResidentCarrier);
var
  List: TList<Int64>;
  I, Room: Integer;
  Sum, Check: Int64;
begin
  List := TList<Int64>.Create;
  try
    Room := 64 + (Carrier.Lap mod 200);
    Sum := 0;
    for I := 0 to Room - 1 do
    begin
      List.Add(Carrier.Tag.Wide + I * 3);
      Sum := Sum xor (Carrier.Tag.Wide + I * 3);
    end;
    Check := 0;
    for I := 0 to List.Count - 1 do
      Check := Check xor List[I];
    Carrier.Feed(UInt64(Ord(Sum = Check)));
    Carrier.Feed(UInt64(Cardinal(List.Count)));
    Carrier.Feed(UInt64(Ord(List.Capacity >= List.Count)));

    { Усечение обязано оставить голову нетронутой. }
    List.Count := 8;
    Carrier.Feed(UInt64(List[0]));
    Carrier.Feed(UInt64(List[7]));
    Carrier.Feed(UInt64(Cardinal(List.Count)));

    List.Clear;
    Carrier.Feed(UInt64(Cardinal(List.Count)));
  finally
    List.Free;
  end;
end;

{ Сортировка: устойчивого порядка никто не обещал, поэтому проверяется то, что
  обещано — упорядоченность и сохранность состава. }
procedure StageSort(Carrier: TResidentCarrier);
var
  List: TList<Int64>;
  I: Integer;
  Ordered: Boolean;
  Before, After: Int64;
begin
  List := TList<Int64>.Create;
  try
    Before := 0;
    for I := 0 to 31 do
    begin
      List.Add(Carrier.Tag.Wide + ((I * 37) mod 64));
      Before := Before xor List[I];
    end;
    List.Sort;

    Ordered := True;
    After := 0;
    for I := 0 to List.Count - 1 do
    begin
      After := After xor List[I];
      if (I > 0) and (List[I] < List[I - 1]) then
        Ordered := False;
    end;
    Carrier.Feed(UInt64(Ord(Ordered)));
    { Состав обязан быть тем же — сортировка переставляет, а не подменяет. }
    Carrier.Feed(UInt64(Ord(Before = After)));
    Carrier.Feed(UInt64(List[0]));
    Carrier.Feed(UInt64(List[List.Count - 1]));

    { По отсортированному работает двоичный поиск. }
    var Found: Integer;
    Carrier.Feed(UInt64(Ord(List.BinarySearch(List[5], Found))));
    Carrier.Feed(UInt64(Ord(List[Found] = List[5])));
  finally
    List.Free;
  end;
end;

{ Словарь: порядок не обещан, поэтому берутся только независимые от него
  величины. }
procedure StageDictionary(Carrier: TResidentCarrier);
var
  Table: TDictionary<Integer, Int64>;
  I, Room: Integer;
  Sum, Got: Int64;
begin
  Table := TDictionary<Integer, Int64>.Create;
  try
    Room := 16 + (Carrier.Lap mod 48);
    for I := 0 to Room - 1 do
      Table.Add(I, Carrier.Tag.Wide + I);
    Carrier.Feed(UInt64(Cardinal(Table.Count)));

    { Коммутативная свёртка: не зависит от раскладки, но ломается от потери. }
    Sum := 0;
    for var Pair in Table do
      Sum := Sum + Pair.Value + Pair.Key;
    Carrier.Feed(UInt64(Sum));

    Carrier.Feed(UInt64(Ord(Table.ContainsKey(0))));
    Carrier.Feed(UInt64(Ord(Table.ContainsKey(Room))));
    Carrier.Feed(UInt64(Ord(Table.TryGetValue(Room div 2, Got))));
    Carrier.Feed(UInt64(Got));

    { Повторная запись по тому же ключу обязана заменить, а не добавить. }
    Table.AddOrSetValue(0, 12345);
    Carrier.Feed(UInt64(Cardinal(Table.Count)));
    Carrier.Feed(UInt64(Table[0]));

    Table.Remove(0);
    Carrier.Feed(UInt64(Cardinal(Table.Count)));
    Carrier.Feed(UInt64(Ord(Table.ContainsKey(0))));
  finally
    Table.Free;
  end;
end;

{ Перехэширование: словарь растёт до перестройки, и всё положенное обязано
  найтись после неё. }
procedure StageRehash(Carrier: TResidentCarrier);
var
  Pocket: TResidentCollPocket;
  Key: Integer;
  Value, Got: Int64;
  Ok: Boolean;
  I: Integer;
begin
  Pocket := Carrier.PocketAs<TResidentCollPocket>('coll-rehash');
  if Pocket.FTable = nil then
    Pocket.FTable := TDictionary<Integer, Int64>.Create;

  Key := Carrier.Lap and 63;
  Value := Carrier.Tag.Wide + Key;
  Pocket.FTable.AddOrSetValue(Key, Value);

  if Pocket.FTable.TryGetValue(Key, Got) then
    Carrier.Feed(UInt64(Got));
  Carrier.Feed(UInt64(Cardinal(Pocket.FTable.Count)));

  { Всё, что клали раньше, обязано находиться и сейчас. }
  Ok := True;
  for I := 0 to Key do
    if not Pocket.FTable.ContainsKey(I) then
      Ok := False;
  Carrier.Feed(UInt64(Ord(Ok)));

  Inc(Pocket.FRounds);
  Carrier.Feed(UInt64(Pocket.FRounds));

  { Дойдя до потолка, таблица чистится: за прогон случается и рост, и сброс. }
  if Pocket.FTable.Count >= 64 then
  begin
    Pocket.FTable.Clear;
    Carrier.Feed(UInt64(Cardinal(Pocket.FTable.Count)));
  end;
end;

{ Очередь: порядок обещан строго — что вошло первым, выйдет первым. }
procedure StageQueue(Carrier: TResidentCarrier);
var
  Ring: TQueue<Int64>;
  I, Room: Integer;
  Ok: Boolean;
begin
  Ring := TQueue<Int64>.Create;
  try
    Room := 4 + (Carrier.Lap mod 12);
    for I := 0 to Room - 1 do
      Ring.Enqueue(Carrier.Tag.Wide + I);
    Carrier.Feed(UInt64(Cardinal(Ring.Count)));
    Carrier.Feed(UInt64(Ring.Peek));

    Ok := True;
    for I := 0 to Room - 1 do
      if Ring.Dequeue <> Carrier.Tag.Wide + I then
        Ok := False;
    Carrier.Feed(UInt64(Ord(Ok)));
    Carrier.Feed(UInt64(Cardinal(Ring.Count)));

    { Кольцо прокручивается: часть уходит, часть приходит, и порядок держится
      через границу внутреннего буфера. }
    for I := 0 to Room - 1 do
      Ring.Enqueue(Int64(I));
    for I := 0 to Room div 2 - 1 do
      Ring.Dequeue;
    for I := 0 to Room - 1 do
      Ring.Enqueue(Int64(100 + I));
    Carrier.Feed(UInt64(Cardinal(Ring.Count)));
    Carrier.Feed(UInt64(Ring.Peek));
  finally
    Ring.Free;
  end;
end;

{ Стек: порядок обратный, и это тоже обещание. }
procedure StageStack(Carrier: TResidentCarrier);
var
  Pile: TStack<Int64>;
  I, Room: Integer;
  Ok: Boolean;
begin
  Pile := TStack<Int64>.Create;
  try
    Room := 4 + (Carrier.Lap mod 10);
    for I := 0 to Room - 1 do
      Pile.Push(Carrier.Tag.Wide + I);
    Carrier.Feed(UInt64(Cardinal(Pile.Count)));
    Carrier.Feed(UInt64(Pile.Peek));

    Ok := True;
    for I := Room - 1 downto 0 do
      if Pile.Pop <> Carrier.Tag.Wide + I then
        Ok := False;
    Carrier.Feed(UInt64(Ord(Ok)));
    Carrier.Feed(UInt64(Cardinal(Pile.Count)));
  finally
    Pile.Free;
  end;
end;

{ Кольцо, живущее между оборотами: то, что положили на прошлом обороте, обязано
  выйти в том же порядке на следующем. }
procedure StageRingAcrossLaps(Carrier: TResidentCarrier);
var
  Pocket: TResidentCollPocket;
  Taken: Int64;
begin
  Pocket := Carrier.PocketAs<TResidentCollPocket>('coll-ring');
  if Pocket.FRing = nil then
    Pocket.FRing := TQueue<Int64>.Create;

  Pocket.FRing.Enqueue(Carrier.Tag.Wide + Carrier.Lap);
  Carrier.Feed(UInt64(Cardinal(Pocket.FRing.Count)));

  { Кольцо держится в берегах: как только набралось достаточно, старое уходит
    первым — и это ровно то, что клали раньше всех. }
  if Pocket.FRing.Count > 8 then
  begin
    Taken := Pocket.FRing.Dequeue;
    Carrier.Feed(UInt64(Taken));
    Carrier.Feed(UInt64(Ord(Taken <= Carrier.Tag.Wide + Carrier.Lap)));
  end;
  Carrier.Feed(UInt64(Pocket.FRing.Peek));
end;

{ Словарь с владением: он хоронит значения сам, и счёт обязан сойтись. }
procedure StageObjectDictionary(Carrier: TResidentCarrier);
var
  Tally: TResidentTally;
  Table: TObjectDictionary<Integer, TResidentNode>;
  I, Room: Integer;
  Found: TResidentNode;
begin
  Tally := Default(TResidentTally);
  Room := 4 + (Carrier.Lap mod 10);
  Table := TObjectDictionary<Integer, TResidentNode>.Create([doOwnsValues]);
  try
    for I := 0 to Room - 1 do
      Table.Add(I, TResidentNode.Create(I, @Tally));
    Carrier.Feed(UInt64(Cardinal(Table.Count)));
    Carrier.Feed(UInt64(Tally.Born));

    if Table.TryGetValue(Room div 2, Found) then
      Carrier.Feed(UInt64(Cardinal(Found.Key)));

    { Замена значения по существующему ключу обязана похоронить прежнее. }
    Table.AddOrSetValue(0, TResidentNode.Create(100, @Tally));
    Carrier.Feed(UInt64(Cardinal(Table.Count)));
    Carrier.Feed(UInt64(Tally.Gone));
    Carrier.Feed(UInt64(Cardinal(Table[0].Key)));

    Table.Remove(1);
    Carrier.Feed(UInt64(Cardinal(Table.Count)));
    Carrier.Feed(UInt64(Tally.Gone));
  finally
    Table.Free;
  end;
  Carrier.Feed(UInt64(Cardinal(Ord(Tally.Alive = 0))));
end;

{ Обход коллекции: перечислитель обязан обойти ровно столько, сколько лежит. }
procedure StageEnumerate(Carrier: TResidentCarrier);
var
  List: TList<Int64>;
  Table: TDictionary<Integer, Int64>;
  Seen: Integer;
  Sum: Int64;
  I: Integer;
begin
  List := TList<Int64>.Create;
  Table := TDictionary<Integer, Int64>.Create;
  try
    for I := 0 to 9 do
    begin
      List.Add(Carrier.Tag.Wide + I);
      Table.Add(I, Int64(I) * 2);
    end;

    Seen := 0;
    Sum := 0;
    for var Value in List do
    begin
      Inc(Seen);
      Sum := Sum xor Value;
    end;
    Carrier.Feed(UInt64(Cardinal(Seen)));
    Carrier.Feed(UInt64(Sum));
    Carrier.Feed(UInt64(Ord(Seen = List.Count)));

    { У словаря считаются только независимые от порядка величины. }
    Seen := 0;
    Sum := 0;
    for var Key in Table.Keys do
    begin
      Inc(Seen);
      Sum := Sum + Key;
    end;
    Carrier.Feed(UInt64(Cardinal(Seen)));
    Carrier.Feed(UInt64(Sum));

    Seen := 0;
    Sum := 0;
    for var Value in Table.Values do
    begin
      Inc(Seen);
      Sum := Sum + Value;
    end;
    Carrier.Feed(UInt64(Cardinal(Seen)));
    Carrier.Feed(UInt64(Sum));
    Carrier.Feed(UInt64(Ord(Seen = Table.Count)));
  finally
    List.Free;
    Table.Free;
  end;
end;

{ Коллекция управляемых записей: копия при выдаче обязана быть настоящей. }
procedure StageEntryList(Carrier: TResidentCarrier);
var
  List: TList<TResidentEntry>;
  Entry: TResidentEntry;
  I: Integer;
begin
  List := TList<TResidentEntry>.Create;
  try
    for I := 0 to 7 do
    begin
      Entry.Key := I;
      Entry.Weight := Carrier.Tag.Wide + I;
      Entry.Label_ := 'e' + IntToStr(I);
      List.Add(Entry);
    end;
    Carrier.Feed(UInt64(Cardinal(List.Count)));

    { Взятая копия правится, а в списке обязано остаться прежнее. }
    Entry := List[3];
    Entry.Weight := Entry.Weight + 1000;
    Entry.Label_ := Entry.Label_ + '!';
    Carrier.Feed(UInt64(List[3].Weight));
    Carrier.Feed(UInt64(Ord(List[3].Weight = Carrier.Tag.Wide + 3)));
    Carrier.Feed(UInt64(Cardinal(Length(List[3].Label_))));
    Carrier.Feed(UInt64(Cardinal(Length(Entry.Label_))));

    { Запись обратно в список обязана дойти. }
    List[3] := Entry;
    Carrier.Feed(UInt64(List[3].Weight));
    Carrier.FeedWide(List[3].Label_);
  finally
    List.Free;
  end;
end;

{ Свой сравниватель ключей: словарь обязан спрашивать именно его. }
procedure StageCustomKeys(Carrier: TResidentCarrier);
var
  Table: TDictionary<Integer, Int64>;
  Asked: Integer;
begin
  Asked := 0;
  { Сравнение по остатку: ключи, дающие один остаток, для словаря один ключ. }
  Table := TDictionary<Integer, Int64>.Create(
    TEqualityComparer<Integer>.Construct(
      function(const Left, Right: Integer): Boolean
      begin
        Inc(Asked);
        Result := Left mod 10 = Right mod 10;
      end,
      function(const Value: Integer): Integer
      begin
        Result := Value mod 10;
      end));
  try
    Table.AddOrSetValue(1, 100);
    Table.AddOrSetValue(11, 200);
    Table.AddOrSetValue(21, 300);
    { Все три легли в один ключ: словарь спросил именно наше сравнение. }
    Carrier.Feed(UInt64(Cardinal(Table.Count)));
    Carrier.Feed(UInt64(Table[1]));
    Carrier.Feed(UInt64(Ord(Table.ContainsKey(31))));
    Carrier.Feed(UInt64(Ord(Asked > 0)));

    Table.AddOrSetValue(2, 400);
    Carrier.Feed(UInt64(Cardinal(Table.Count)));
  finally
    Table.Free;
  end;
end;

{ Массив как коллекция: обобщённые операции над `TArray` обязаны работать с
  теми же обещаниями, что и списки. }
procedure StageArrayHelpers(Carrier: TResidentCarrier);
var
  Data: System.TArray<Int64>;
  I: Integer;
  Found: Integer;
  Ordered: Boolean;
begin
  SetLength(Data, 16);
  for I := 0 to High(Data) do
    Data[I] := Carrier.Tag.Wide + ((I * 11) mod 16);

  TArray.Sort<Int64>(Data);
  Ordered := True;
  for I := 1 to High(Data) do
    if Data[I] < Data[I - 1] then
      Ordered := False;
  Carrier.Feed(UInt64(Ord(Ordered)));
  Carrier.Feed(UInt64(Data[0]));
  Carrier.Feed(UInt64(Data[High(Data)]));

  Carrier.Feed(UInt64(Ord(TArray.BinarySearch<Int64>(Data, Data[7], Found))));
  Carrier.Feed(UInt64(Ord(Data[Found] = Data[7])));

  { Сортировка своим сравнением обязана дать обратный порядок. }
  TArray.Sort<Int64>(Data, TComparer<Int64>.Construct(
    function(const Left, Right: Int64): Integer
    begin
      if Left > Right then
        Result := -1
      else if Left < Right then
        Result := 1
      else
        Result := 0;
    end));
  Carrier.Feed(UInt64(Ord(Data[0] > Data[High(Data)])));
  Carrier.Feed(UInt64(Data[0]));
end;

{ Хэш-множество: состав важен, порядок — нет. }
procedure StageKeySet(Carrier: TResidentCarrier);
var
  Seen: TDictionary<Int64, Boolean>;
  I, Room, Unique: Integer;
begin
  Seen := TDictionary<Int64, Boolean>.Create;
  try
    Room := 8 + (Carrier.Lap mod 24);
    for I := 0 to Room - 1 do
      Seen.AddOrSetValue(Carrier.Tag.Wide + (I mod 8), True);
    { Повторы обязаны схлопнуться: разных значений ровно восемь либо меньше. }
    Unique := Seen.Count;
    Carrier.Feed(UInt64(Cardinal(Unique)));
    Carrier.Feed(UInt64(Ord(Unique = 8)));

    for I := 0 to 7 do
      Carrier.Feed(UInt64(Ord(Seen.ContainsKey(Carrier.Tag.Wide + I))));
  finally
    Seen.Free;
  end;
end;

initialization
  ResidentRegisterStage('coll-array-helpers', @StageArrayHelpers);
  ResidentRegisterStage('coll-custom-keys', @StageCustomKeys);
  ResidentRegisterStage('coll-dictionary', @StageDictionary);
  ResidentRegisterStage('coll-entry-list', @StageEntryList);
  ResidentRegisterStage('coll-enumerate', @StageEnumerate);
  ResidentRegisterStage('coll-key-set', @StageKeySet);
  ResidentRegisterStage('coll-list-growth', @StageListGrowth);
  ResidentRegisterStage('coll-list-order', @StageListOrder);
  ResidentRegisterStage('coll-object-dictionary', @StageObjectDictionary);
  ResidentRegisterStage('coll-queue', @StageQueue);
  ResidentRegisterStage('coll-rehash', @StageRehash);
  ResidentRegisterStage('coll-ring-across-laps', @StageRingAcrossLaps);
  ResidentRegisterStage('coll-sort', @StageSort);
  ResidentRegisterStage('coll-stack', @StageStack);

end.
