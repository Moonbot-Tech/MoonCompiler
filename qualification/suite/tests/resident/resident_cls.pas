unit resident_cls;

{ Семейство `cls` — объектная модель.

  Вызов виртуального метода — это не переход по имени, а поиск в таблице,
  которую компилятор построил для каждого класса и связал с каждым экземпляром.
  Здесь проверяется, что таблица собрана верно: что через ссылку на предка
  зовётся метод потомка, что `inherited` идёт ровно на один уровень вверх, что
  метакласс заводит именно тот класс, который в нём лежит, и что перегрузка
  выбирает вариант по типу, а не по порядку объявления.

  Наблюдение всюду одинаковое: каждый метод дописывает свою метку в след, и
  цепочка вызовов превращается в число. Ошибка в диспетчеризации меняет след,
  даже если итоговое значение случайно совпало.

  Все объекты стадии — свои и локальные, общего состояния между потоками нет ни
  байта; переменные класса не используются именно поэтому. }

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
  { Три уровня наследования: середина переопределяет одно, низ — другое, и
    видно, чей метод достался ссылке на верх. }
  TResidentBase = class
  private
    FMark: Integer;
  public
    constructor Create; virtual;
    function Level: Integer; virtual;
    function Chain: Int64; virtual;
    function Plain: Integer;
    class function Kind: Integer; virtual;
    class function Fixed: Integer;
    property Mark: Integer read FMark;
  end;

  TResidentMiddle = class(TResidentBase)
  public
    constructor Create; override;
    function Level: Integer; override;
    function Chain: Int64; override;
    function Plain: Integer;
    class function Kind: Integer; override;
  end;

  TResidentLeaf = class(TResidentMiddle)
  public
    constructor Create; override;
    function Level: Integer; override;
    function Chain: Int64; override;
    class function Kind: Integer; override;
  end;

  { Метакласс: ссылка на сам класс, по которой можно завести экземпляр. }
  TResidentClass = class of TResidentBase;

  { Абстрактный договор: тело обязан дать потомок. }
  TResidentShape = class
  public
    function Area: Integer; virtual; abstract;
    function Describe: Int64;
  end;

  TResidentSquare = class(TResidentShape)
  private
    FSide: Integer;
  public
    constructor Create(ASide: Integer);
    function Area: Integer; override;
  end;

  TResidentStripe = class(TResidentShape)
  private
    FLength: Integer;
  public
    constructor Create(ALength: Integer);
    function Area: Integer; override;
  end;

  { Свойства с индексом: один метод обслуживает несколько свойств, различая их
    по числу, которое подставил компилятор. }
  TResidentPanel = class
  private
    FSlots: array[0 .. 3] of Int64;
    function GetSlot(Index: Integer): Int64;
    procedure SetSlot(Index: Integer; Value: Int64);
    function GetCell(Row, Col: Integer): Int64;
  public
    property Top: Int64 index 0 read GetSlot write SetSlot;
    property Left: Int64 index 1 read GetSlot write SetSlot;
    property Right: Int64 index 2 read GetSlot write SetSlot;
    property Bottom: Int64 index 3 read GetSlot write SetSlot;
    property Cell[Row, Col: Integer]: Int64 read GetCell; default;
  end;

  { Делегирование интерфейса полю: методы обязан отдать внутренний объект. }
  IResidentSpeaker = interface
    ['{4D5A0030-0000-0000-0000-0000524553FF}']
    function Say: Int64;
  end;

  TResidentVoice = class(TInterfacedObject, IResidentSpeaker)
  private
    FValue: Int64;
  public
    constructor Create(AValue: Int64);
    function Say: Int64;
  end;

  TResidentSpeakerHost = class(TInterfacedObject, IResidentSpeaker)
  private
    FInner: IResidentSpeaker;
  public
    constructor Create(const AInner: IResidentSpeaker);
    property Inner: IResidentSpeaker read FInner implements IResidentSpeaker;
  end;

  { Вложенный тип: имя живёт внутри класса и не спорит с одноимённым снаружи. }
  TResidentOuter = class
  public type
    TInner = record
      Value: Int64;
      function Doubled: Int64;
    end;
  private
    FInner: TInner;
  public
    procedure Put(AValue: Int64);
    function Get: Int64;
  end;

  { Операторы записи: сложение и сравнение объявлены самим типом. }
  TResidentAmount = record
    Value: Int64;
    class operator Add(const A, B: TResidentAmount): TResidentAmount;
    class operator Subtract(const A, B: TResidentAmount): TResidentAmount;
    class operator Equal(const A, B: TResidentAmount): Boolean;
    class operator NotEqual(const A, B: TResidentAmount): Boolean;
  end;

  TResidentClsPocket = class(TResidentPocket)
  private
    FHeld: TResidentBase;
    FRounds: Int64;
  public
    destructor Destroy; override;
  end;

{ ------------------------------------------------------- реализации ------- }

constructor TResidentBase.Create;
begin
  inherited Create;
  FMark := 1;
end;

function TResidentBase.Level: Integer;
begin
  Result := 1;
end;

function TResidentBase.Chain: Int64;
begin
  Result := 1;
end;

function TResidentBase.Plain: Integer;
begin
  Result := 10;
end;

class function TResidentBase.Kind: Integer;
begin
  Result := 100;
end;

class function TResidentBase.Fixed: Integer;
begin
  Result := 7;
end;

constructor TResidentMiddle.Create;
begin
  inherited Create;
  FMark := FMark * 10 + 2;
end;

function TResidentMiddle.Level: Integer;
begin
  Result := 2;
end;

function TResidentMiddle.Chain: Int64;
begin
  { Ровно на уровень вверх, не на самый верх. }
  Result := inherited Chain * 10 + 2;
end;

function TResidentMiddle.Plain: Integer;
begin
  Result := 20;
end;

class function TResidentMiddle.Kind: Integer;
begin
  Result := 200;
end;

constructor TResidentLeaf.Create;
begin
  inherited Create;
  FMark := FMark * 10 + 3;
end;

function TResidentLeaf.Level: Integer;
begin
  Result := 3;
end;

function TResidentLeaf.Chain: Int64;
begin
  Result := inherited Chain * 10 + 3;
end;

class function TResidentLeaf.Kind: Integer;
begin
  Result := 300;
end;

function TResidentShape.Describe: Int64;
begin
  { Невиртуальный метод зовёт виртуальный: тело обязано найтись у потомка. }
  Result := Int64(Area) * 10 + 1;
end;

constructor TResidentSquare.Create(ASide: Integer);
begin
  inherited Create;
  FSide := ASide;
end;

function TResidentSquare.Area: Integer;
begin
  Result := FSide * FSide;
end;

constructor TResidentStripe.Create(ALength: Integer);
begin
  inherited Create;
  FLength := ALength;
end;

function TResidentStripe.Area: Integer;
begin
  Result := FLength;
end;

function TResidentPanel.GetSlot(Index: Integer): Int64;
begin
  Result := FSlots[Index];
end;

procedure TResidentPanel.SetSlot(Index: Integer; Value: Int64);
begin
  FSlots[Index] := Value;
end;

function TResidentPanel.GetCell(Row, Col: Integer): Int64;
begin
  Result := FSlots[(Row * 2 + Col) and 3];
end;

constructor TResidentVoice.Create(AValue: Int64);
begin
  inherited Create;
  FValue := AValue;
end;

function TResidentVoice.Say: Int64;
begin
  Result := FValue;
end;

constructor TResidentSpeakerHost.Create(const AInner: IResidentSpeaker);
begin
  inherited Create;
  FInner := AInner;
end;

function TResidentOuter.TInner.Doubled: Int64;
begin
  Result := Value * 2;
end;

procedure TResidentOuter.Put(AValue: Int64);
begin
  FInner.Value := AValue;
end;

function TResidentOuter.Get: Int64;
begin
  Result := FInner.Doubled;
end;

class operator TResidentAmount.Add(const A, B: TResidentAmount): TResidentAmount;
begin
  Result.Value := A.Value + B.Value;
end;

class operator TResidentAmount.Subtract(const A, B: TResidentAmount): TResidentAmount;
begin
  Result.Value := A.Value - B.Value;
end;

class operator TResidentAmount.Equal(const A, B: TResidentAmount): Boolean;
begin
  Result := A.Value = B.Value;
end;

class operator TResidentAmount.NotEqual(const A, B: TResidentAmount): Boolean;
begin
  Result := A.Value <> B.Value;
end;

destructor TResidentClsPocket.Destroy;
begin
  FHeld.Free;
  inherited Destroy;
end;

{ Перегрузка: вариант выбирается по типу довода, а не по порядку записи. }
function Pick(Value: Int64): Integer; overload;
begin
  Result := 1;
end;

function Pick(Value: SmallInt): Integer; overload;
begin
  Result := 2;
end;

function Pick(const Value: string): Integer; overload;
begin
  Result := 3;
end;

function Pick(Value: Boolean): Integer; overload;
begin
  Result := 4;
end;

{ Довод по умолчанию: пропущенный обязан подставиться, а переданный — победить. }
function WithDefaults(A: Integer; B: Integer = 20; C: Integer = 300): Int64;
begin
  Result := Int64(A) * 10000 + Int64(B) * 100 + C;
end;

{ ------------------------------------------------------------- стадии ----- }

{ Через ссылку на предка обязан зваться метод потомка — и только виртуальный. }
procedure StageVirtualDispatch(Carrier: TResidentCarrier);
var
  Base: TResidentBase;
  Trail: Int64;
begin
  Trail := 0;

  Base := TResidentBase.Create;
  try
    Trail := Trail * 10 + Base.Level;
    Carrier.Feed(UInt64(Cardinal(Base.Plain)));
  finally
    Base.Free;
  end;

  Base := TResidentMiddle.Create;
  try
    Trail := Trail * 10 + Base.Level;
    { Невиртуальный метод берётся по типу ссылки, а не по типу объекта. }
    Carrier.Feed(UInt64(Cardinal(Base.Plain)));
    Carrier.Feed(UInt64(Cardinal(TResidentMiddle(Base).Plain)));
  finally
    Base.Free;
  end;

  Base := TResidentLeaf.Create;
  try
    Trail := Trail * 10 + Base.Level;
    Carrier.Feed(UInt64(Cardinal(Base.Plain)));
  finally
    Base.Free;
  end;

  Carrier.Feed(UInt64(Trail));
  Carrier.Feed(UInt64(Ord(Trail = 123)));
end;

{ `inherited` идёт ровно на один уровень вверх, а не на самый верх. }
procedure StageInheritedChain(Carrier: TResidentCarrier);
var
  Leaf: TResidentLeaf;
  Middle: TResidentMiddle;
begin
  Leaf := TResidentLeaf.Create;
  try
    Carrier.Feed(UInt64(Leaf.Chain));
    Carrier.Feed(UInt64(Ord(Leaf.Chain = 123)));
    { Конструкторы отработали цепочкой в том же порядке. }
    Carrier.Feed(UInt64(Cardinal(Leaf.Mark)));
    Carrier.Feed(UInt64(Ord(Leaf.Mark = 123)));
  finally
    Leaf.Free;
  end;

  Middle := TResidentMiddle.Create;
  try
    Carrier.Feed(UInt64(Middle.Chain));
    Carrier.Feed(UInt64(Cardinal(Middle.Mark)));
    Carrier.Feed(UInt64(Ord(Middle.Mark = 12)));
  finally
    Middle.Free;
  end;
end;

{ Метакласс: заводится тот класс, который лежит в переменной. }
procedure StageMetaclass(Carrier: TResidentCarrier);
var
  Meta: TResidentClass;
  Made: TResidentBase;
  Trail: Int64;
  I: Integer;
begin
  Trail := 0;
  for I := 0 to 2 do
  begin
    case I of
      0: Meta := TResidentBase;
      1: Meta := TResidentMiddle;
    else
      Meta := TResidentLeaf;
    end;

    { Виртуальный метод класса зовётся через метакласс, без экземпляра. }
    Carrier.Feed(UInt64(Cardinal(Meta.Kind)));
    Carrier.Feed(UInt64(Cardinal(Meta.Fixed)));

    Made := Meta.Create;
    try
      Trail := Trail * 10 + Made.Level;
      Carrier.FeedWide(Made.ClassName);
      Carrier.Feed(UInt64(Cardinal(Made.Mark)));
    finally
      Made.Free;
    end;
  end;
  Carrier.Feed(UInt64(Trail));
  Carrier.Feed(UInt64(Ord(Trail = 123)));

  { Метакласс потомка годится там, где ждут метакласс предка. }
  Meta := TResidentLeaf;
  Carrier.Feed(UInt64(Ord(Meta.InheritsFrom(TResidentBase))));
  Carrier.Feed(UInt64(Ord(Meta = TResidentLeaf)));
  Carrier.Feed(UInt64(Ord(Meta <> TResidentMiddle)));
end;

{ Родство: `is`, `as` и разбор по классу обязаны сходиться между собой. }
procedure StageKinship(Carrier: TResidentCarrier);
var
  Base: TResidentBase;
begin
  Base := TResidentLeaf.Create;
  try
    Carrier.Feed(UInt64(Ord(Base is TResidentLeaf)));
    Carrier.Feed(UInt64(Ord(Base is TResidentMiddle)));
    Carrier.Feed(UInt64(Ord(Base is TResidentBase)));
    Carrier.Feed(UInt64(Ord(Base.InheritsFrom(TResidentMiddle))));
    Carrier.Feed(UInt64(Ord(Base.ClassType = TResidentLeaf)));
    Carrier.Feed(UInt64(Ord(Base.ClassType = TResidentMiddle)));
    Carrier.FeedWide(Base.ClassName);
    Carrier.FeedWide(Base.ClassParent.ClassName);
    Carrier.FeedWide(Base.ClassParent.ClassParent.ClassName);
    Carrier.Feed(UInt64(Cardinal((Base as TResidentMiddle).Level)));
  finally
    Base.Free;
  end;

  Base := TResidentMiddle.Create;
  try
    Carrier.Feed(UInt64(Ord(Base is TResidentLeaf)));
    Carrier.Feed(UInt64(Ord(Base is TResidentMiddle)));
    { Неверное приведение обязано отказать исключением, а не молча пройти. }
    try
      Carrier.Feed(UInt64(Cardinal((Base as TResidentLeaf).Level)));
      Carrier.Feed(0);
    except
      on E: Exception do
        Carrier.Feed(UInt64(Ord(E is EInvalidCast)));
    end;
  finally
    Base.Free;
  end;
end;

{ Абстрактный метод: тело берётся у потомка, и невиртуальный вызывающий этого
  не замечает. }
procedure StageAbstract(Carrier: TResidentCarrier);
var
  Shapes: TObjectList<TResidentShape>;
  Side: Integer;
  Sum: Int64;
begin
  Side := 2 + (Carrier.Lap mod 5);
  Shapes := TObjectList<TResidentShape>.Create(True);
  try
    Shapes.Add(TResidentSquare.Create(Side));
    Shapes.Add(TResidentStripe.Create(Side));
    Sum := 0;
    for var Shape in Shapes do
    begin
      Carrier.Feed(UInt64(Cardinal(Shape.Area)));
      Carrier.Feed(UInt64(Shape.Describe));
      Sum := Sum + Shape.Area;
    end;
    Carrier.Feed(UInt64(Sum));
    Carrier.Feed(UInt64(Ord(Sum = Int64(Side) * Side + Side)));
    Carrier.Feed(UInt64(Ord(Shapes[0].ClassType <> Shapes[1].ClassType)));
  finally
    Shapes.Free;
  end;
end;

{ Свойство с индексом: один метод, много свойств, различаемых числом. }
procedure StagePropertyIndex(Carrier: TResidentCarrier);
var
  Panel: TResidentPanel;
begin
  Panel := TResidentPanel.Create;
  try
    Panel.Top := Carrier.Tag.Wide;
    Panel.Left := Carrier.Tag.Wide + 1;
    Panel.Right := Carrier.Tag.Wide + 2;
    Panel.Bottom := Carrier.Tag.Wide + 3;

    Carrier.Feed(UInt64(Panel.Top));
    Carrier.Feed(UInt64(Panel.Left));
    Carrier.Feed(UInt64(Panel.Right));
    Carrier.Feed(UInt64(Panel.Bottom));
    Carrier.Feed(UInt64(Ord(Panel.Bottom - Panel.Top = 3)));

    { Свойство-массив по умолчанию: обращение без имени. }
    Carrier.Feed(UInt64(Panel[0, 0]));
    Carrier.Feed(UInt64(Panel[1, 1]));
    Carrier.Feed(UInt64(Ord(Panel[0, 0] = Panel.Top)));
    Carrier.Feed(UInt64(Ord(Panel.Cell[0, 1] = Panel.Left)));
  finally
    Panel.Free;
  end;
end;

{ Перегрузка: выбор по типу довода. }
procedure StageOverload(Carrier: TResidentCarrier);
var
  Wide: Int64;
  Narrow: SmallInt;
  Text: string;
  Flag: Boolean;
begin
  Wide := Carrier.Tag.Wide;
  Narrow := Carrier.Tag.Narrow;
  Text := Carrier.Text.Wide;
  Flag := True;

  Carrier.Feed(UInt64(Cardinal(Pick(Wide))));
  Carrier.Feed(UInt64(Cardinal(Pick(Narrow))));
  Carrier.Feed(UInt64(Cardinal(Pick(Text))));
  Carrier.Feed(UInt64(Cardinal(Pick(Flag))));
  Carrier.Feed(UInt64(Ord(Pick(Wide) <> Pick(Narrow))));

  { Доводы по умолчанию подставляются справа налево. }
  Carrier.Feed(UInt64(WithDefaults(1)));
  Carrier.Feed(UInt64(WithDefaults(1, 2)));
  Carrier.Feed(UInt64(WithDefaults(1, 2, 3)));
  Carrier.Feed(UInt64(Ord(WithDefaults(1) = 12300)));
end;

{ Делегирование интерфейса полю: методы обязан отдать внутренний объект. }
procedure StageDelegation(Carrier: TResidentCarrier);
var
  Inner: IResidentSpeaker;
  Host: IResidentSpeaker;
begin
  Inner := TResidentVoice.Create(Carrier.Tag.Wide);
  Host := TResidentSpeakerHost.Create(Inner);

  Carrier.Feed(UInt64(Host.Say));
  Carrier.Feed(UInt64(Ord(Host.Say = Inner.Say)));
  Carrier.Feed(UInt64(Ord(Host = Inner)));

  Inner := nil;
  { Хозяин держит свою ссылку — внутренний обязан быть жив. }
  Carrier.Feed(UInt64(Host.Say));
  Host := nil;
end;

{ Вложенный тип: имя живёт внутри класса и работает как обычный. }
procedure StageNestedType(Carrier: TResidentCarrier);
var
  Outer: TResidentOuter;
  Inner: TResidentOuter.TInner;
begin
  Outer := TResidentOuter.Create;
  try
    Outer.Put(Carrier.Tag.Wide);
    Carrier.Feed(UInt64(Outer.Get));
    Carrier.Feed(UInt64(Ord(Outer.Get = Carrier.Tag.Wide * 2)));
  finally
    Outer.Free;
  end;

  Inner.Value := Carrier.Tag.Wide + 5;
  Carrier.Feed(UInt64(Inner.Doubled));
  Carrier.Feed(UInt64(Cardinal(SizeOf(Inner))));
end;

{ Операторы записи: сложение и сравнение объявлены самим типом. }
procedure StageOperators(Carrier: TResidentCarrier);
var
  A, B, C: TResidentAmount;
begin
  A.Value := Carrier.Tag.Wide;
  B.Value := 100;

  C := A + B;
  Carrier.Feed(UInt64(C.Value));
  Carrier.Feed(UInt64(Ord(C.Value = A.Value + B.Value)));

  C := C - B;
  Carrier.Feed(UInt64(C.Value));
  Carrier.Feed(UInt64(Ord(C = A)));
  Carrier.Feed(UInt64(Ord(C <> B)));

  { Сложение по цепочке обязано остаться сложением. }
  C := A + B + B;
  Carrier.Feed(UInt64(C.Value));
  Carrier.Feed(UInt64(Ord(C.Value = A.Value + 200)));
end;

{ Объект, живущий в кармане между оборотами: класс и содержимое обязаны
  оставаться теми же, сколько бы оборотов ни прошло. }
procedure StageHeldAcrossLaps(Carrier: TResidentCarrier);
var
  Pocket: TResidentClsPocket;
begin
  Pocket := Carrier.PocketAs<TResidentClsPocket>('cls-held');
  if Pocket.FHeld = nil then
    Pocket.FHeld := TResidentLeaf.Create;

  Carrier.Feed(UInt64(Cardinal(Pocket.FHeld.Level)));
  Carrier.Feed(UInt64(Pocket.FHeld.Chain));
  Carrier.Feed(UInt64(Cardinal(Pocket.FHeld.Mark)));
  Carrier.FeedWide(Pocket.FHeld.ClassName);
  Carrier.Feed(UInt64(Ord(Pocket.FHeld is TResidentLeaf)));

  Inc(Pocket.FRounds);
  Carrier.Feed(UInt64(Pocket.FRounds));

  { Раз в несколько оборотов жилец меняется на другого — и класс обязан
    смениться вместе с ним. }
  if Pocket.FRounds mod 5 = 0 then
  begin
    FreeAndNil(Pocket.FHeld);
    Pocket.FHeld := TResidentMiddle.Create;
    Carrier.Feed(UInt64(Cardinal(Pocket.FHeld.Level)));
    Carrier.Feed(UInt64(Ord(Pocket.FHeld is TResidentLeaf)));
  end;
end;

{ Массив объектов разных классов: таблица методов у каждого своя, и обход
  обязан звать у каждого его собственный метод. }
procedure StageMixedArray(Carrier: TResidentCarrier);
var
  Items: TObjectList<TResidentBase>;
  Trail: Int64;
  I, Room: Integer;
begin
  Room := 3 + (Carrier.Lap mod 6);
  Items := TObjectList<TResidentBase>.Create(True);
  try
    for I := 0 to Room - 1 do
      case I mod 3 of
        0: Items.Add(TResidentBase.Create);
        1: Items.Add(TResidentMiddle.Create);
      else
        Items.Add(TResidentLeaf.Create);
      end;

    Trail := 0;
    for I := 0 to Items.Count - 1 do
    begin
      Trail := Trail * 10 + Items[I].Level;
      Carrier.Feed(UInt64(Items[I].Chain));
      Carrier.Feed(UInt64(Ord(Items[I].ClassType.InstanceSize > 0)));
    end;
    Carrier.Feed(UInt64(Trail));
    Carrier.Feed(UInt64(Cardinal(Items.Count)));
  finally
    Items.Free;
  end;
end;

initialization
  ResidentRegisterStage('cls-abstract', @StageAbstract);
  ResidentRegisterStage('cls-delegation', @StageDelegation);
  ResidentRegisterStage('cls-held-across-laps', @StageHeldAcrossLaps);
  ResidentRegisterStage('cls-inherited-chain', @StageInheritedChain);
  ResidentRegisterStage('cls-kinship', @StageKinship);
  ResidentRegisterStage('cls-metaclass', @StageMetaclass);
  ResidentRegisterStage('cls-mixed-array', @StageMixedArray);
  ResidentRegisterStage('cls-nested-type', @StageNestedType);
  ResidentRegisterStage('cls-operators', @StageOperators);
  ResidentRegisterStage('cls-overload', @StageOverload);
  ResidentRegisterStage('cls-property-index', @StagePropertyIndex);
  ResidentRegisterStage('cls-virtual-dispatch', @StageVirtualDispatch);

end.
