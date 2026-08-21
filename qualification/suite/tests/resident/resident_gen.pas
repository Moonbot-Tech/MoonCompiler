unit resident_gen;

{ Семейство `gen` — обобщения.

  Обобщение живёт дважды: один раз как текст, где тип ещё буква, и второй раз
  как специализация, где буква стала конкретным типом со своей шириной, своим
  знаком, своим способом копирования и своим освобождением. Здесь проверяется
  вторая жизнь: не потерялась ли ширина при подстановке, копируется ли
  управляемый тип как управляемый, зовётся ли для специализации именно её
  реализация, а не соседняя.

  Общего состояния тут нет ни байта. Переменная класса у обобщения — своя на
  каждую специализацию, и это соблазнительная механика для проверки, но она
  разделяется между потоками; слой с гонкой в самом себе не имеет права
  обвинять компилятор. Поэтому всё состояние — локальное либо в носителе. }

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
  SysUtils, Classes, TypInfo, Generics.Defaults, Generics.Collections,
  resident_core;

implementation

type
  { Коробка: минимальное обобщение, чей единственный смысл — донести тип. }
  TResidentBox<T> = record
    Value: T;
    function Read: T;
    function Width: Integer;
    function Kind: Integer;
    function IsManaged: Boolean;
  end;

  { Пара: два параметра типа, чтобы подстановка не могла перепутать порядок. }
  TResidentPair<K, V> = record
    Key: K;
    Val: V;
    function KeyWidth: Integer;
    function ValWidth: Integer;
    function Total: Integer;
  end;

  IResidentHolder<T> = interface
    ['{4D5A0020-0000-0000-0000-0000524553FF}']
    function Get: T;
    function Width: Integer;
  end;

  TResidentHolder<T> = class(TInterfacedObject, IResidentHolder<T>)
  private
    FValue: T;
  public
    constructor Create(const AValue: T);
    function Get: T;
    function Width: Integer;
  end;

  { Наследование обобщения: потомок фиксирует параметр родителя. }
  TResidentStore<T> = class
  private
    FItems: System.TArray<T>;
  public
    procedure Put(const Value: T);
    function Count: Integer;
    function Item(Index: Integer): T;
    function Width: Integer;
    class function Name: string;
  end;

  TResidentInt64Store = class(TResidentStore<Int64>)
  public
    function Total: Int64;
  end;

  { Ограничение «класс с конструктором»: специализация обязана позвать именно
    конструктор подставленного типа. }
  TResidentSeed = class
  private
    FMark: Integer;
  public
    constructor Create; virtual;
    property Mark: Integer read FMark;
  end;

  TResidentSeedTwo = class(TResidentSeed)
  public
    constructor Create; override;
  end;

  TResidentGenPocket = class(TResidentPocket)
  private
    FStore: TResidentInt64Store;
    FRounds: Int64;
  public
    destructor Destroy; override;
  end;

{ ---------------------------------------------------------- реализации ---- }

function TResidentBox<T>.Read: T;
begin
  Result := Value;
end;

function TResidentBox<T>.Width: Integer;
begin
  Result := SizeOf(T);
end;

function TResidentBox<T>.Kind: Integer;
begin
  Result := Ord(GetTypeKind(T));
end;

function TResidentBox<T>.IsManaged: Boolean;
begin
  Result := IsManagedType(T);
end;

function TResidentPair<K, V>.KeyWidth: Integer;
begin
  Result := SizeOf(K);
end;

function TResidentPair<K, V>.ValWidth: Integer;
begin
  Result := SizeOf(V);
end;

function TResidentPair<K, V>.Total: Integer;
begin
  Result := SizeOf(K) + SizeOf(V);
end;

constructor TResidentHolder<T>.Create(const AValue: T);
begin
  inherited Create;
  FValue := AValue;
end;

function TResidentHolder<T>.Get: T;
begin
  Result := FValue;
end;

function TResidentHolder<T>.Width: Integer;
begin
  Result := SizeOf(T);
end;

procedure TResidentStore<T>.Put(const Value: T);
begin
  SetLength(FItems, Length(FItems) + 1);
  FItems[High(FItems)] := Value;
end;

function TResidentStore<T>.Count: Integer;
begin
  Result := Length(FItems);
end;

function TResidentStore<T>.Item(Index: Integer): T;
begin
  Result := FItems[Index];
end;

function TResidentStore<T>.Width: Integer;
begin
  Result := SizeOf(T);
end;

class function TResidentStore<T>.Name: string;
begin
  Result := string(PTypeInfo(TypeInfo(T))^.Name);
end;

function TResidentInt64Store.Total: Int64;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to Count - 1 do
    Result := Result xor Item(I);
end;

constructor TResidentSeed.Create;
begin
  inherited Create;
  FMark := 1;
end;

constructor TResidentSeedTwo.Create;
begin
  inherited Create;
  FMark := 2;
end;

destructor TResidentGenPocket.Destroy;
begin
  FStore.Free;
  inherited Destroy;
end;

{ Обобщённые действия собраны в класс со статическими методами, а не объявлены
  отдельными функциями. Причина переносимости: параметр типа у глобальной
  функции Delphi не принимает вовсе, а у метода — принимает; форма же проверки
  от этого не меняется, специализация остаётся специализацией. }
type
  TResidentGen = class
    class function WidthOf<T>: Integer; static;
    class function KindOf<T>: Integer; static;
    { Ограничение с конструктором: подставленный тип обязан завестись своим. }
    class function MakeSeed<T: TResidentSeed, constructor>: T; static;
    { Обобщённый обмен: работает через тип, а не через размер в байтах. }
    class procedure SwapAny<T>(var Left, Right: T); static;
  end;

class function TResidentGen.WidthOf<T>: Integer;
begin
  Result := SizeOf(T);
end;

class function TResidentGen.KindOf<T>: Integer;
begin
  Result := Ord(GetTypeKind(T));
end;

class function TResidentGen.MakeSeed<T>: T;
begin
  Result := T.Create;
end;

class procedure TResidentGen.SwapAny<T>(var Left, Right: T);
var
  Spare: T;
begin
  Spare := Left;
  Left := Right;
  Right := Spare;
end;

{ ------------------------------------------------------------- стадии ----- }

{ Ширина подставленного типа обязана дойти до специализации в целости. }
procedure StageWidths(Carrier: TResidentCarrier);
var
  Narrow: TResidentBox<SmallInt>;
  Unsigned: TResidentBox<Word>;
  Wide: TResidentBox<Int64>;
  Tiny: TResidentBox<Byte>;
  Tag: TResidentTag;
begin
  Tag := Carrier.Tag;
  Narrow.Value := Tag.Narrow;
  Unsigned.Value := Tag.Unsigned;
  Wide.Value := Tag.Wide;
  Tiny.Value := Byte(Tag.Wide and $FF);

  Carrier.Feed(UInt64(Cardinal(Narrow.Width)));
  Carrier.Feed(UInt64(Cardinal(Unsigned.Width)));
  Carrier.Feed(UInt64(Cardinal(Wide.Width)));
  Carrier.Feed(UInt64(Cardinal(Tiny.Width)));

  { Сужение обязано пережить подстановку: узкое поле остаётся узким. }
  Carrier.Feed(UInt64(Word(Narrow.Read)));
  Carrier.Feed(UInt64(Unsigned.Read));
  Carrier.Feed(UInt64(Wide.Read));
  Carrier.Feed(UInt64(Tiny.Read));

  { Та же ширина, взятая обобщённой функцией, обязана совпасть. }
  Carrier.Feed(UInt64(Cardinal(TResidentGen.WidthOf<SmallInt>)));
  Carrier.Feed(UInt64(Cardinal(TResidentGen.WidthOf<Int64>)));
  Carrier.Feed(UInt64(Ord(TResidentGen.WidthOf<Word> = Unsigned.Width)));
end;

{ Род типа: подстановка обязана донести не только ширину, но и природу. }
procedure StageKinds(Carrier: TResidentCarrier);
var
  Text: TResidentBox<string>;
  Bytes: TResidentBox<AnsiString>;
  Number: TResidentBox<Int64>;
  Flag: TResidentBox<Boolean>;
begin
  Text.Value := Carrier.Text.Wide;
  Bytes.Value := Carrier.Text.Bytes;
  Number.Value := Carrier.Tag.Wide;
  Flag.Value := Carrier.Serial and 1 = 0;

  Carrier.Feed(UInt64(Cardinal(Text.Kind)));
  Carrier.Feed(UInt64(Cardinal(Bytes.Kind)));
  Carrier.Feed(UInt64(Cardinal(Number.Kind)));
  Carrier.Feed(UInt64(Cardinal(Flag.Kind)));
  Carrier.Feed(UInt64(Cardinal(TResidentGen.KindOf<Int64>)));
  Carrier.Feed(UInt64(Ord(TResidentGen.KindOf<string> = Text.Kind)));

  { Управляемость — тоже свойство подставленного типа. }
  Carrier.Feed(UInt64(Ord(Text.IsManaged)));
  Carrier.Feed(UInt64(Ord(Bytes.IsManaged)));
  Carrier.Feed(UInt64(Ord(Number.IsManaged)));
  Carrier.Feed(UInt64(Ord(Flag.IsManaged)));
end;

{ Управляемый тип внутри обобщения обязан копироваться как управляемый: у копии
  свой буфер, у оригинала свой. }
procedure StageManagedBox(Carrier: TResidentCarrier);
var
  Source, Twin: TResidentBox<string>;
  Held: TResidentBox<System.TArray<Int64>>;
  Copy: TResidentBox<System.TArray<Int64>>;
begin
  Source.Value := Carrier.Text.Wide;
  Twin := Source;
  Twin.Value := Twin.Value + 'x';
  Carrier.Feed(UInt64(Cardinal(Length(Source.Value))));
  Carrier.Feed(UInt64(Cardinal(Length(Twin.Value))));
  Carrier.Feed(UInt64(Ord(Length(Twin.Value) = Length(Source.Value) + 1)));

  Held.Value := System.Copy(Carrier.Numbers, 0, Length(Carrier.Numbers));
  Copy := Held;
  Carrier.Feed(UInt64(Cardinal(Length(Copy.Value))));
  { Коробка скопирована по значению, но массив внутри — общий буфер, поэтому
    правка видна обеим сторонам. Это и есть договор ссылочного типа. }
  if Length(Copy.Value) > 0 then
  begin
    Copy.Value[0] := Copy.Value[0] + 1;
    Carrier.Feed(UInt64(Ord(Held.Value[0] = Copy.Value[0])));
  end;
end;

{ Вложенное обобщение: коробка в коробке обязана донести оба слоя. }
procedure StageNested(Carrier: TResidentCarrier);
var
  Inner: TResidentBox<Int64>;
  Outer: TResidentBox<TResidentBox<Int64>>;
  Deep: TResidentBox<TResidentBox<TResidentBox<Word>>>;
begin
  Inner.Value := Carrier.Tag.Wide;
  Outer.Value := Inner;
  Carrier.Feed(UInt64(Outer.Read.Read));
  Carrier.Feed(UInt64(Cardinal(Outer.Width)));
  Carrier.Feed(UInt64(Cardinal(Outer.Read.Width)));
  Carrier.Feed(UInt64(Ord(Outer.Read.Read = Inner.Value)));

  Deep.Value.Value.Value := Carrier.Tag.Unsigned;
  Carrier.Feed(UInt64(Deep.Read.Read.Read));
  Carrier.Feed(UInt64(Cardinal(Deep.Read.Read.Width)));
  Carrier.Feed(UInt64(Cardinal(SizeOf(Deep))));
end;

{ Два параметра типа: порядок подстановки обязан сохраниться. }
procedure StagePair(Carrier: TResidentCarrier);
var
  Straight: TResidentPair<Byte, Int64>;
  Flipped: TResidentPair<Int64, Byte>;
begin
  Straight.Key := Byte(Carrier.Serial and $FF);
  Straight.Val := Carrier.Tag.Wide;
  Flipped.Key := Carrier.Tag.Wide;
  Flipped.Val := Byte(Carrier.Serial and $FF);

  Carrier.Feed(UInt64(Cardinal(Straight.KeyWidth)));
  Carrier.Feed(UInt64(Cardinal(Straight.ValWidth)));
  Carrier.Feed(UInt64(Cardinal(Flipped.KeyWidth)));
  Carrier.Feed(UInt64(Cardinal(Flipped.ValWidth)));
  Carrier.Feed(UInt64(Ord(Straight.KeyWidth = Flipped.ValWidth)));
  Carrier.Feed(UInt64(Ord(Straight.Total = Flipped.Total)));
  Carrier.Feed(UInt64(Straight.Val));
  Carrier.Feed(UInt64(Flipped.Key));
end;

{ Обобщённый интерфейс: у каждой специализации своя таблица методов. }
procedure StageHolder(Carrier: TResidentCarrier);
var
  Number: IResidentHolder<Int64>;
  Text: IResidentHolder<string>;
  Narrow: IResidentHolder<SmallInt>;
begin
  Number := TResidentHolder<Int64>.Create(Carrier.Tag.Wide);
  Text := TResidentHolder<string>.Create(Carrier.Text.Wide);
  Narrow := TResidentHolder<SmallInt>.Create(Carrier.Tag.Narrow);

  Carrier.Feed(UInt64(Number.Get));
  Carrier.Feed(UInt64(Cardinal(Length(Text.Get))));
  Carrier.Feed(UInt64(Word(Narrow.Get)));
  Carrier.Feed(UInt64(Cardinal(Number.Width)));
  Carrier.Feed(UInt64(Cardinal(Text.Width)));
  Carrier.Feed(UInt64(Cardinal(Narrow.Width)));
  Carrier.Feed(UInt64(Ord(Number.Width <> Narrow.Width)));

  Number := nil;
  Text := nil;
  Narrow := nil;
end;

{ Наследование обобщения: потомок с зафиксированным параметром обязан видеть
  и своё, и родительское. }
procedure StageInherit(Carrier: TResidentCarrier);
var
  Pocket: TResidentGenPocket;
begin
  Pocket := Carrier.PocketAs<TResidentGenPocket>('gen-inherit');
  if Pocket.FStore = nil then
    Pocket.FStore := TResidentInt64Store.Create;

  Pocket.FStore.Put(Carrier.Tag.Wide);
  Carrier.Feed(UInt64(Cardinal(Pocket.FStore.Count)));
  Carrier.Feed(UInt64(Pocket.FStore.Total));
  Carrier.Feed(UInt64(Cardinal(Pocket.FStore.Width)));
  Carrier.Feed(UInt64(Pocket.FStore.Item(0)));

  { Хранилище растёт от оборота к обороту и обязано помнить всё положенное. }
  Inc(Pocket.FRounds);
  Carrier.Feed(UInt64(Pocket.FRounds));
  Carrier.Feed(UInt64(Ord(Int64(Pocket.FStore.Count) = Pocket.FRounds)));

  { Дойдя до потолка, хранилище заводится заново — так за прогон случается и
    рост, и полная смена. }
  if Pocket.FStore.Count >= 32 then
  begin
    FreeAndNil(Pocket.FStore);
    Pocket.FRounds := 0;
  end;
end;

{ Имя подставленного типа: специализация обязана нести своё, а не соседнее. }
procedure StageTypeNames(Carrier: TResidentCarrier);
var
  Numbers: TResidentStore<Int64>;
  Words: TResidentStore<Word>;
begin
  Numbers := TResidentStore<Int64>.Create;
  Words := TResidentStore<Word>.Create;
  try
    { Имя берётся через экземпляры: запись вида Specialized<T>.Method прямо в
      выражении спотыкается о разбор угловых скобок рядом с оператором. }
    Carrier.FeedWide(Numbers.Name);
    Carrier.FeedWide(Words.Name);
    Carrier.Feed(UInt64(Ord(Numbers.Name <> Words.Name)));
    Carrier.Feed(UInt64(Cardinal(Numbers.Width)));
    Carrier.Feed(UInt64(Cardinal(Words.Width)));
  finally
    Numbers.Free;
    Words.Free;
  end;
end;

{ Ограничение «класс с конструктором»: обязан завестись конструктор именно
  подставленного потомка, а не объявленного предка. }
procedure StageConstructorConstraint(Carrier: TResidentCarrier);
var
  Base: TResidentSeed;
  Heir: TResidentSeedTwo;
begin
  Base := TResidentGen.MakeSeed<TResidentSeed>;
  try
    Carrier.Feed(UInt64(Cardinal(Base.Mark)));
  finally
    Base.Free;
  end;

  Heir := TResidentGen.MakeSeed<TResidentSeedTwo>;
  try
    Carrier.Feed(UInt64(Cardinal(Heir.Mark)));
    Carrier.Feed(UInt64(Ord(Heir.Mark = 2)));
    Carrier.Feed(UInt64(Ord(Heir is TResidentSeed)));
  finally
    Heir.Free;
  end;
end;

{ Значение по умолчанию: для каждого типа своё, и обобщение обязано его знать. }
procedure StageDefaults(Carrier: TResidentCarrier);
var
  Text: string;
  Number: Int64;
  Narrow: SmallInt;
  Flag: Boolean;
begin
  Text := Default(string);
  Number := Default(Int64);
  Narrow := Default(SmallInt);
  Flag := Default(Boolean);
  Carrier.Feed(UInt64(Cardinal(Length(Text))));
  Carrier.Feed(UInt64(Number));
  Carrier.Feed(UInt64(Word(Narrow)));
  Carrier.Feed(UInt64(Ord(Flag)));
  Carrier.Feed(UInt64(Ord(Text = '')));

  { Обобщённая коробка после обнуления обязана дать то же самое. }
  var Box := Default(TResidentBox<Int64>);
  Carrier.Feed(UInt64(Box.Read));
  var TextBox := Default(TResidentBox<string>);
  Carrier.Feed(UInt64(Cardinal(Length(TextBox.Read))));
end;

{ Обобщённый обмен: значения меняются местами, ширина не теряется. }
procedure StageSwap(Carrier: TResidentCarrier);
var
  A, B: Int64;
  X, Y: SmallInt;
  P, Q: string;
begin
  A := Carrier.Tag.Wide;
  B := not A;
  TResidentGen.SwapAny<Int64>(A, B);
  Carrier.Feed(UInt64(A));
  Carrier.Feed(UInt64(B));
  Carrier.Feed(UInt64(Ord(A = not B)));

  X := Carrier.Tag.Narrow;
  Y := SmallInt(-X);
  TResidentGen.SwapAny<SmallInt>(X, Y);
  Carrier.Feed(UInt64(Word(X)));
  Carrier.Feed(UInt64(Word(Y)));

  P := Carrier.Text.Wide;
  Q := 'other';
  TResidentGen.SwapAny<string>(P, Q);
  Carrier.Feed(UInt64(Cardinal(Length(P))));
  Carrier.Feed(UInt64(Cardinal(Length(Q))));
  Carrier.Feed(UInt64(Ord(P = 'other')));
end;

{ Сравниватель по умолчанию: у каждой специализации свой, и порядок обязан
  соответствовать природе типа, а не его битам. }
procedure StageComparer(Carrier: TResidentCarrier);
var
  Numbers: IComparer<Int64>;
  Narrow: IComparer<SmallInt>;
  Unsigned: IComparer<Word>;
  Texts: IComparer<string>;
begin
  Numbers := TComparer<Int64>.Default;
  Narrow := TComparer<SmallInt>.Default;
  Unsigned := TComparer<Word>.Default;
  Texts := TComparer<string>.Default;

  Carrier.Feed(UInt64(Cardinal(Ord(Numbers.Compare(1, 2) < 0))));
  Carrier.Feed(UInt64(Cardinal(Ord(Numbers.Compare(2, 1) > 0))));
  Carrier.Feed(UInt64(Cardinal(Ord(Numbers.Compare(7, 7) = 0))));

  { Знаковый тип обязан ставить отрицательное ниже нуля, беззнаковый — нет. }
  Carrier.Feed(UInt64(Cardinal(Ord(Narrow.Compare(-1, 1) < 0))));
  Carrier.Feed(UInt64(Cardinal(Ord(Unsigned.Compare($FFFF, 1) > 0))));
  Carrier.Feed(UInt64(Cardinal(Ord(Texts.Compare('a', 'b') < 0))));
  Carrier.Feed(UInt64(Cardinal(Ord(Texts.Compare('abc', 'abc') = 0))));
end;

{ Свой сравниватель: обобщение обязано звать переданное сравнение, а не своё. }
procedure StageCustomComparer(Carrier: TResidentCarrier);
var
  List: TList<Int64>;
  I: Integer;
begin
  { Порядок задан наоборот: если бы звалось сравнение по умолчанию, список
    вышел бы возрастающим. }
  List := TList<Int64>.Create(TComparer<Int64>.Construct(
    function(const Left, Right: Int64): Integer
    begin
      if Left > Right then
        Result := -1
      else if Left < Right then
        Result := 1
      else
        Result := 0;
    end));
  try
    for I := 0 to 7 do
      List.Add(Carrier.Tag.Wide + ((I * 5) mod 8));
    List.Sort;
    for I := 0 to List.Count - 1 do
      Carrier.Feed(UInt64(List[I]));
    Carrier.Feed(UInt64(Ord(List[0] > List[List.Count - 1])));
    Carrier.Feed(UInt64(Cardinal(List.Count)));
  finally
    List.Free;
  end;
end;

{ Обобщённый список узких типов: сужение обязано пережить и хранение, и выдачу. }
procedure StageNarrowList(Carrier: TResidentCarrier);
var
  Narrow: TList<SmallInt>;
  Unsigned: TList<Word>;
  I: Integer;
begin
  Narrow := TList<SmallInt>.Create;
  Unsigned := TList<Word>.Create;
  try
    for I := 0 to 5 do
    begin
      Narrow.Add(SmallInt(-32767 + I));
      Unsigned.Add(Word($FFFF - I));
    end;
    for I := 0 to Narrow.Count - 1 do
    begin
      Carrier.Feed(UInt64(Word(Narrow[I])));
      Carrier.Feed(UInt64(Unsigned[I]));
    end;
    Carrier.Feed(UInt64(Cardinal(Narrow.Count)));
    Carrier.Feed(UInt64(Cardinal(SizeOf(Narrow.List[0]))));
    Carrier.Feed(UInt64(Cardinal(SizeOf(Unsigned.List[0]))));
    Carrier.Feed(UInt64(Ord(Narrow.IndexOf(SmallInt(-32767)) = 0)));
    Carrier.Feed(UInt64(Ord(Unsigned.Contains($FFFF))));
  finally
    Narrow.Free;
    Unsigned.Free;
  end;
end;

initialization
  ResidentRegisterStage('gen-comparer', @StageComparer);
  ResidentRegisterStage('gen-constructor-constraint', @StageConstructorConstraint);
  ResidentRegisterStage('gen-custom-comparer', @StageCustomComparer);
  ResidentRegisterStage('gen-defaults', @StageDefaults);
  ResidentRegisterStage('gen-holder', @StageHolder);
  ResidentRegisterStage('gen-inherit', @StageInherit);
  ResidentRegisterStage('gen-kinds', @StageKinds);
  ResidentRegisterStage('gen-managed-box', @StageManagedBox);
  ResidentRegisterStage('gen-narrow-list', @StageNarrowList);
  ResidentRegisterStage('gen-nested', @StageNested);
  ResidentRegisterStage('gen-pair', @StagePair);
  ResidentRegisterStage('gen-swap', @StageSwap);
  ResidentRegisterStage('gen-type-names', @StageTypeNames);
  ResidentRegisterStage('gen-widths', @StageWidths);

end.
