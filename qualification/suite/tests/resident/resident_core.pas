unit resident_core;

{ Ядро слоя `resident` — взрослой программы, которая живёт долго.

  Все прочие слои Devil однопроходны: кейс родился, вычислился, проверился и
  умер за один вдох, причина и следствие стоят рядом. Здесь проверяется другое:
  выдерживает ли скомпилированный код тысячу оборотов владения, роста и
  переездов памяти, не потеряв ни байта, ни ссылки, ни одного объекта, который
  обязан был умереть вовремя.

  Правило честности, на котором держится весь слой: **программа обязана быть
  безупречной**. Один владелец в каждый момент времени, ни одной своей гонки,
  ни одного неопределённого поведения. Тогда любое расхождение однозначно
  вешается на компилятор, RTL или менеджер памяти, а не на тест.

  Оракул смещён с программы на носителя. Межпоточный интерливинг —
  недетерминирован, поэтому глобальный порядок событий свойством программы не
  является и в корневую свёртку не идёт. Зато маршрут каждого носителя по
  стадиям задан сидом, значит последовательность его собственных событий
  детерминирована: личный дайджест носителя сравним между сборками до бита, а
  корень собирается коммутативной свёрткой личных дайджестов, поэтому
  инвариантен к порядку, в котором потоки успели отработать.

  Реестр стадий. Семейств механик много, и они живут в отдельных юнитах, каждый
  из которых регистрирует свои стадии в `initialization`. Индекс стадии обязан
  не зависеть от того, в каком порядке компилятор запустил секции инициализации,
  иначе дайджест поехал бы от перестановки строк в uses: поэтому реестр перед
  стартом сортируется по имени. Сам порядок инициализации при этом не выброшен,
  а свёрнут в отдельный дайджест — он контракт языка и проверяется как
  самостоятельный факт, а не размазывается по корню. }

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
  SysUtils, Classes, SyncObjs, Generics.Collections;

const
  { Свёртка личного дайджеста: биекция накопителя, поэтому один неверный бит
    не может сократиться — он размазывается лавиной до конца жизни носителя. }
  ResidentOffset = UInt64($CBF29CE484222325);
  ResidentPrime  = UInt64($00000100000001B3);

  { Канарейки вокруг буферов носителя: порча памяти обязана назвать место
    посева, а не место выстрела. }
  CanaryHead = UInt64($C0DE1234FEEDBEEF);
  CanaryTail = UInt64($0BADCAFED00DFACE);

  { Карманы носителя: стадии хранят в них своё состояние между оборотами.
    Длины фиксированы навсегда — они часть паспорта, а не данных. }
  ResidentSlotCount   = 32;
  ResidentStringCount = 8;

  { Через столько оборотов маршрут носителя перетасовывается заново: порядок
    пересадок обязан меняться, иначе пара соседних стадий так и не встретится. }
  ResidentRouteEpoch = 8;

type
  { Что носитель везёт с собой. Это не «данные теста», а перечень жильцов,
    каждый из которых умеет портиться по-своему: управляемая запись с
    вложенностью, строки разной ширины и кодовой страницы, интерфейс со
    счётчиком ссылок, динамический массив, замыкание, узкие целые. }
  TResidentTag = record
    Head: UInt64;          { канарейка перед полезной частью }
    Narrow: SmallInt;      { узкое знаковое: край сужения }
    Unsigned: Word;        { узкое беззнаковое: тот же край с другой стороны }
    Wide: Int64;
    Tail: UInt64;          { канарейка после }
    function Intact: Boolean;
    procedure Seal;
  end;

  TResidentText = record
    Wide: string;          { UTF-16 по контракту драйвера }
    Bytes: AnsiString;     { байтовая строка: сюда едет codepage }
    Utf8: UTF8String;
    function Intact: Boolean;
  end;

  { Счётчик живых: никто его не сбрасывает, поэтому баланс за оборот кольца
    остаётся свойством всей жизни программы, а не одного прохода. }
  TResidentCensus = class
  private
    FLock: TCriticalSection;
    FBorn: Int64;
    FGone: Int64;
  public
    constructor Create;
    destructor Destroy; override;
    procedure NoteBorn;
    procedure NoteGone;
    function Alive: Int64;
    function Born: Int64;
  end;

  { Локальный счёт рождений и смертей. Глобальная перепись общая на программу,
    поэтому её показания двигают соседние носители — в дайджест такое число
    класть нельзя. Локальный счёт живёт внутри одной стадии одного потока,
    значит он детерминирован и предъявляем. }
  TResidentTally = record
    Born: Int64;
    Gone: Int64;
    function Alive: Int64;
  end;
  PResidentTally = ^TResidentTally;

  { Интерфейсный жилец: его счётчик ссылок — главный свидетель того, что
    владение передавалось честно. }
  IResidentToken = interface
    ['{4D5A0001-0000-0000-0000-0000524553FF}']
    function Payload: Int64;
    function Serial: Integer;
  end;

  TResidentToken = class(TInterfacedObject, IResidentToken)
  private
    FPayload: Int64;
    FSerial: Integer;
    FCensus: TResidentCensus;
  public
    constructor Create(APayload: Int64; ASerial: Integer;
      ACensus: TResidentCensus);
    destructor Destroy; override;
    function Payload: Int64;
    function Serial: Integer;
  end;

  TResidentStep = reference to function(const V: Int64): Int64;

  { Объектный карман стадии. Носитель владеет карманами и хоронит их сам, так
    что стадия не обязана помнить о смерти носителя. }
  TResidentPocket = class
  private
    FCensus: TResidentCensus;
  public
    constructor Create; virtual;
    destructor Destroy; override;
    { Перепись узнаёт о кармане не в конструкторе, а при вселении: так наследник
      остаётся с конструктором без параметров и заводится обобщённым кодом. }
    procedure Attach(ACensus: TResidentCensus);
    property Census: TResidentCensus read FCensus;
  end;

  { Носитель. Живёт сотни оборотов, обходит все стадии по персональной
    перестановке и на каждом обороте предъявляет паспорт. }
  TResidentCarrier = class
  private
    FSerial: Integer;
    FSeed: UInt64;
    FDigest: UInt64;
    FLap: Integer;
    FCensus: TResidentCensus;
    FTag: TResidentTag;
    FText: TResidentText;
    FNumbers: TArray<Int64>;
    FTable: TDictionary<Integer, Int64>;
    FToken: IResidentToken;
    FStep: TResidentStep;
    FSlots: array[0 .. ResidentSlotCount - 1] of Int64;
    FStrings: array[0 .. ResidentStringCount - 1] of string;
    FPockets: TObjectDictionary<string, TResidentPocket>;
    FRoute: TArray<Integer>;
    FRoutePos: Integer;
    FStageDigest: UInt64;
    FBroken: Int64;
    FBreach: string;
    FPassport: UInt64;
    FPassportSet: Boolean;
    FDrift: Boolean;
    FCorrupt: Boolean;
    FVisits: Int64;
    procedure BuildRoute;
    function GetSlot(Index: Integer): Int64;
    procedure SetSlot(Index: Integer; Value: Int64);
    function GetString(Index: Integer): string;
    procedure SetString(Index: Integer; const Value: string);
  public
    constructor Create(ASerial: Integer; ASeed: UInt64;
      ACensus: TResidentCensus);
    destructor Destroy; override;

    { Начало стадии: вклад стадии считается с чистого листа. Личный дайджест
      носителя при этом продолжает копиться — это две разные величины и путать
      их нельзя. Личный отвечает на вопрос «та же ли у носителя судьба», вклад
      стадии — на вопрос «та же ли работа у этой стадии»; вклад не зависит от
      того, что было с носителем раньше, поэтому одно раннее расхождение не
      красит все последующие стадии, и виновная называется точно. }
    procedure BeginStage;

    { Вливание в личный дайджест носителя и во вклад текущей стадии. }
    procedure Feed(Value: UInt64);

    { Утверждение, которое обязано выполняться само по себе, без сравнения с
      чем-либо. Не всякое наблюдение таково: значение свёртки — просто число,
      его судят сравнением прогонов. А вот известный ответ из спецификации,
      договор деления или обратимость преобразования верны или неверны сразу, и
      ждать эталонного прогона, чтобы это заметить, незачем.

      Нарушение попадает и в дайджест (чтобы расхождение было видно и там), и в
      отдельный счёт, по которому прогон объявляется провальным с указанием, что
      именно не сошлось. }
    procedure Claim(Condition: Boolean; const What: string);
    procedure FeedText(const Value: AnsiString);
    procedure FeedWide(const Value: string);

    { Паспорт снимается на каждом обороте: то, что носитель показал на первом
      обороте, он обязан показать и на тысячном. Поехавший с возрастом паспорт
      — сам по себе находка, даже без знания «правильного» значения. }
    procedure StampPassport;

    { Целостность буферов: канарейки называют место посева порчи. }
    function Sound: Boolean;

    { Стадия под курсором маршрута и переход к следующей. `Advance` возвращает
      True, когда закрыт полный оборот — то есть маршрут пройден целиком и
      носитель побывал на каждой стадии ровно раз. }
    function CurrentStage: Integer;
    function Advance: Boolean;

    { Объектный карман по имени стадии: заводится при первом обращении. }
    function Pocket(const Name: string): TResidentPocket;
    function PocketAs<T: TResidentPocket, constructor>(const Name: string): T;
    function HasPocket(const Name: string): Boolean;
    procedure DropPocket(const Name: string);
    function PocketCount: Integer;

    property Serial: Integer read FSerial;
    property Seed: UInt64 read FSeed;
    property Digest: UInt64 read FDigest;
    property Lap: Integer read FLap;
    property Census: TResidentCensus read FCensus;
    property Tag: TResidentTag read FTag write FTag;
    property Text: TResidentText read FText write FText;
    property Numbers: TArray<Int64> read FNumbers write FNumbers;
    property Table: TDictionary<Integer, Int64> read FTable;
    property Token: IResidentToken read FToken write FToken;
    property Step: TResidentStep read FStep write FStep;
    property Slots[Index: Integer]: Int64 read GetSlot write SetSlot;
    property Strings[Index: Integer]: string read GetString write SetString;
    property StageDigest: UInt64 read FStageDigest;
    property Broken: Int64 read FBroken;
    property Breach: string read FBreach;
    property Passport: UInt64 read FPassport;
    property PassportDrifted: Boolean read FDrift;
    property Corrupted: Boolean read FCorrupt;
    property Visits: Int64 read FVisits;
  end;

  TResidentStageProc = procedure(Carrier: TResidentCarrier);

{ Смешивание значения в накопитель — та же биекция, что и в дайджесте. }
function ResidentMix(Accumulator, Value: UInt64): UInt64;

{ Детерминированный поток чисел: маршруты и данные носителей берутся отсюда,
  и только отсюда. Ни времени, ни адресов, ни расписания потоков в слое нет. }
function ResidentNext(var State: UInt64): UInt64;

{ Реестр стадий. Юниты семейств зовут `ResidentRegisterStage` в своей
  `initialization`; драйвер один раз зовёт `ResidentSealStages` до старта. }
procedure ResidentRegisterStage(const Name: string; Proc: TResidentStageProc);

{ Оставить в реестре только стадии, чьё имя начинается с заданного куска. Нужно
  для разбора: находка сужается до одной стадии, а кольцо вокруг неё остаётся
  тем же самым, со всеми потоками и переездами. }
procedure ResidentKeepOnly(const Prefix: string);
procedure ResidentSealStages;
function ResidentStageCount: Integer;
function ResidentStageName(Index: Integer): string;
function ResidentStageIndex(const Name: string): Integer;
procedure ResidentRunStage(Index: Integer; Carrier: TResidentCarrier);

{ Дайджест реестра по именам: не зависит от порядка инициализации, поэтому
  меняется ровно тогда, когда изменился состав стадий. }
function ResidentRegistryDigest: UInt64;

{ Дайджест порядка регистрации: это уже свойство самого компилятора — в каком
  порядке он выполнил секции initialization. Сравнивается отдельно, чтобы
  перестановка не растворилась в корне. }
function ResidentInitOrderDigest: UInt64;

implementation

function ResidentMix(Accumulator, Value: UInt64): UInt64;
begin
  Result := (Accumulator xor Value) * ResidentPrime;
end;

function ResidentNext(var State: UInt64): UInt64;
var
  Z: UInt64;
begin
  { splitmix64: короткий, полностью определённый и без зависимости от RTL. }
  State := State + UInt64($9E3779B97F4A7C15);
  Z := State;
  Z := (Z xor (Z shr 30)) * UInt64($BF58476D1CE4E5B9);
  Z := (Z xor (Z shr 27)) * UInt64($94D049BB133111EB);
  Result := Z xor (Z shr 31);
end;

{ ---------------------------------------------------------------- реестр -- }

type
  TResidentStageEntry = record
    Name: string;
    Proc: TResidentStageProc;
    Born: Integer;         { номер по порядку регистрации }
  end;

  { Имя типу нужно не для красоты: два безымянных динамических массива одного
    и того же элемента — по Delphi РАЗНЫЕ типы, и присваивание между ними там
    не проходит. Именованный тип делает реестр переносимым. }
  TResidentStageList = array of TResidentStageEntry;

var
  Registry: TResidentStageList;
  RegistrySealed: Boolean = False;
  RegistryNames: UInt64 = ResidentOffset;
  RegistryOrder: UInt64 = ResidentOffset;

function ResidentNameLess(const A, B: string): Boolean;
var
  I, Limit: Integer;
begin
  { Побайтовое сравнение по кодам символов: сравнение через RTL зависело бы от
    локали, а индекс стадии обязан быть одинаков на любой машине. }
  Limit := Length(A);
  if Length(B) < Limit then
    Limit := Length(B);
  for I := 1 to Limit do
    if A[I] <> B[I] then
      Exit(Word(A[I]) < Word(B[I]));
  Result := Length(A) < Length(B);
end;

procedure ResidentRegisterStage(const Name: string; Proc: TResidentStageProc);
var
  Index: Integer;
begin
  if RegistrySealed then
    raise Exception.Create('resident: stage registered after seal: ' + Name);
  if not Assigned(Proc) then
    raise Exception.Create('resident: stage without body: ' + Name);
  Index := Length(Registry);
  SetLength(Registry, Index + 1);
  Registry[Index].Name := Name;
  Registry[Index].Proc := Proc;
  Registry[Index].Born := Index;
end;

procedure ResidentKeepOnly(const Prefix: string);
var
  Kept: TResidentStageList;
  I: Integer;
begin
  if RegistrySealed then
    raise Exception.Create('resident: registry already sealed');
  if Prefix = '' then
    Exit;
  SetLength(Kept, 0);
  for I := 0 to High(Registry) do
    if Copy(Registry[I].Name, 1, Length(Prefix)) = Prefix then
    begin
      SetLength(Kept, Length(Kept) + 1);
      Kept[High(Kept)] := Registry[I];
    end;
  if Length(Kept) = 0 then
    raise Exception.Create('resident: no stage matches ' + Prefix);
  Registry := Kept;
end;

procedure ResidentSealStages;
var
  I, J: Integer;
  Swap: TResidentStageEntry;
begin
  if RegistrySealed then
    Exit;
  if Length(Registry) = 0 then
    raise Exception.Create('resident: no stages registered');

  { Порядок регистрации сворачивается ДО сортировки: это отдельный факт о
    компиляторе, и он не должен потеряться. }
  RegistryOrder := ResidentOffset;
  for I := 0 to High(Registry) do
  begin
    RegistryOrder := ResidentMix(RegistryOrder, UInt64(Cardinal(I)));
    for J := 1 to Length(Registry[I].Name) do
      RegistryOrder := ResidentMix(RegistryOrder, UInt64(Word(Registry[I].Name[J])));
  end;

  { Вставками: список короткий, зато сортировка устойчива и целиком наша. }
  for I := 1 to High(Registry) do
  begin
    Swap := Registry[I];
    J := I - 1;
    while (J >= 0) and ResidentNameLess(Swap.Name, Registry[J].Name) do
    begin
      Registry[J + 1] := Registry[J];
      Dec(J);
    end;
    Registry[J + 1] := Swap;
  end;

  for I := 1 to High(Registry) do
    if Registry[I].Name = Registry[I - 1].Name then
      raise Exception.Create('resident: duplicate stage name: ' + Registry[I].Name);

  RegistryNames := ResidentOffset;
  for I := 0 to High(Registry) do
  begin
    RegistryNames := ResidentMix(RegistryNames, UInt64(Cardinal(I)));
    for J := 1 to Length(Registry[I].Name) do
      RegistryNames := ResidentMix(RegistryNames, UInt64(Word(Registry[I].Name[J])));
  end;

  RegistrySealed := True;
end;

function ResidentStageCount: Integer;
begin
  Result := Length(Registry);
end;

function ResidentStageName(Index: Integer): string;
begin
  if (Index < 0) or (Index > High(Registry)) then
    Exit('out-of-range');
  Result := Registry[Index].Name;
end;

function ResidentStageIndex(const Name: string): Integer;
var
  I: Integer;
begin
  for I := 0 to High(Registry) do
    if Registry[I].Name = Name then
      Exit(I);
  Result := -1;
end;

procedure ResidentRunStage(Index: Integer; Carrier: TResidentCarrier);
begin
  Registry[Index].Proc(Carrier);
end;

function ResidentRegistryDigest: UInt64;
begin
  Result := RegistryNames;
end;

function ResidentInitOrderDigest: UInt64;
begin
  Result := RegistryOrder;
end;

{ ---------------------------------------------------------- TResidentTally - }

function TResidentTally.Alive: Int64;
begin
  Result := Born - Gone;
end;

{ ------------------------------------------------------------ TResidentTag - }

function TResidentTag.Intact: Boolean;
begin
  Result := (Head = CanaryHead) and (Tail = CanaryTail);
end;

procedure TResidentTag.Seal;
begin
  Head := CanaryHead;
  Tail := CanaryTail;
end;

{ ----------------------------------------------------------- TResidentText - }

function TResidentText.Intact: Boolean;
begin
  { Длины связаны по построению: байтовая строка — ASCII-проекция широкой,
    UTF-8 не короче её. Нарушение связи означает, что кто-то переехал. }
  Result := (Length(Bytes) = Length(Wide)) and (Length(Utf8) >= Length(Bytes));
end;

{ --------------------------------------------------------- TResidentCensus - }

constructor TResidentCensus.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
end;

destructor TResidentCensus.Destroy;
begin
  FLock.Free;
  inherited Destroy;
end;

procedure TResidentCensus.NoteBorn;
begin
  FLock.Enter;
  try
    Inc(FBorn);
  finally
    FLock.Leave;
  end;
end;

procedure TResidentCensus.NoteGone;
begin
  FLock.Enter;
  try
    Inc(FGone);
  finally
    FLock.Leave;
  end;
end;

function TResidentCensus.Alive: Int64;
begin
  FLock.Enter;
  try
    Result := FBorn - FGone;
  finally
    FLock.Leave;
  end;
end;

function TResidentCensus.Born: Int64;
begin
  FLock.Enter;
  try
    Result := FBorn;
  finally
    FLock.Leave;
  end;
end;

{ ---------------------------------------------------------- TResidentToken - }

constructor TResidentToken.Create(APayload: Int64; ASerial: Integer;
  ACensus: TResidentCensus);
begin
  inherited Create;
  FPayload := APayload;
  FSerial := ASerial;
  FCensus := ACensus;
  FCensus.NoteBorn;
end;

destructor TResidentToken.Destroy;
begin
  FCensus.NoteGone;
  inherited Destroy;
end;

function TResidentToken.Payload: Int64;
begin
  Result := FPayload;
end;

function TResidentToken.Serial: Integer;
begin
  Result := FSerial;
end;

{ --------------------------------------------------------- TResidentPocket - }

constructor TResidentPocket.Create;
begin
  inherited Create;
end;

procedure TResidentPocket.Attach(ACensus: TResidentCensus);
begin
  FCensus := ACensus;
  if FCensus <> nil then
    FCensus.NoteBorn;
end;

destructor TResidentPocket.Destroy;
begin
  if FCensus <> nil then
    FCensus.NoteGone;
  inherited Destroy;
end;

{ -------------------------------------------------------- TResidentCarrier - }

constructor TResidentCarrier.Create(ASerial: Integer; ASeed: UInt64;
  ACensus: TResidentCensus);
var
  Base: Int64;
  State: UInt64;
  I: Integer;
begin
  inherited Create;
  FSerial := ASerial;
  FSeed := ASeed;
  FCensus := ACensus;
  FDigest := ResidentOffset;
  FLap := 0;

  State := ResidentMix(ASeed, UInt64(Cardinal(ASerial)));
  Base := Int64(ResidentNext(State) and $FFFF);

  FTag.Seal;
  { Узкие поля ставятся у самого края домена: значение из середины пережило бы
    потерянное сужение незаметно. }
  FTag.Narrow := SmallInt(-32767 + (Base and 1));
  FTag.Unsigned := Word($FFFF - (Base and 1));
  FTag.Wide := Base;

  FText.Wide := StringOfChar('a', 8 + (Base and 7));
  FText.Bytes := AnsiString(FText.Wide);
  FText.Utf8 := UTF8Encode(FText.Wide);

  SetLength(FNumbers, 4);
  FNumbers[0] := Base;
  FNumbers[1] := -Base;
  FNumbers[2] := Int64(FTag.Narrow);
  FNumbers[3] := Int64(FTag.Unsigned);

  FTable := TDictionary<Integer, Int64>.Create;
  FTable.Add(0, Base);

  FToken := TResidentToken.Create(Base, ASerial, ACensus);

  FStep :=
    function(const V: Int64): Int64
    begin
      Result := V xor Base;
    end;

  for I := 0 to ResidentSlotCount - 1 do
    FSlots[I] := Base + I;
  for I := 0 to ResidentStringCount - 1 do
    FStrings[I] := StringOfChar('s', 1 + I);

  { Карманы владеют своим содержимым: носитель хоронит их сам, поэтому стадии
    не обязаны помнить о его смерти. }
  FPockets := TObjectDictionary<string, TResidentPocket>.Create([doOwnsValues]);

  BuildRoute;
end;

destructor TResidentCarrier.Destroy;
begin
  FStep := nil;
  FToken := nil;
  FPockets.Free;
  FTable.Free;
  inherited Destroy;
end;

procedure TResidentCarrier.BuildRoute;
var
  State: UInt64;
  I, J, Swap, Count: Integer;
begin
  { Персональная перестановка стадий: за оборот носитель обязан побывать на
    каждой ровно раз, иначе покрытие зависело бы от везения, а число обработок
    перестало бы быть проверяемой величиной. Через ResidentRouteEpoch оборотов
    перестановка строится заново — соседство стадий тоже обязано меняться. }
  Count := ResidentStageCount;
  SetLength(FRoute, Count);
  for I := 0 to Count - 1 do
    FRoute[I] := I;

  State := ResidentMix(FSeed, UInt64(Cardinal(FSerial)));
  State := ResidentMix(State, UInt64(Cardinal(FLap div ResidentRouteEpoch)));
  for I := Count - 1 downto 1 do
  begin
    J := Integer(ResidentNext(State) mod UInt64(I + 1));
    Swap := FRoute[I];
    FRoute[I] := FRoute[J];
    FRoute[J] := Swap;
  end;
  FRoutePos := 0;
end;

function TResidentCarrier.CurrentStage: Integer;
begin
  Result := FRoute[FRoutePos];
end;

function TResidentCarrier.Advance: Boolean;
begin
  Inc(FVisits);
  Inc(FRoutePos);
  Result := FRoutePos >= Length(FRoute);
  if Result then
  begin
    Inc(FLap);
    if FLap mod ResidentRouteEpoch = 0 then
      BuildRoute
    else
      FRoutePos := 0;
  end;
end;

function TResidentCarrier.GetSlot(Index: Integer): Int64;
begin
  Result := FSlots[Index];
end;

procedure TResidentCarrier.SetSlot(Index: Integer; Value: Int64);
begin
  FSlots[Index] := Value;
end;

function TResidentCarrier.GetString(Index: Integer): string;
begin
  Result := FStrings[Index];
end;

procedure TResidentCarrier.SetString(Index: Integer; const Value: string);
begin
  FStrings[Index] := Value;
end;

function TResidentCarrier.Pocket(const Name: string): TResidentPocket;
begin
  if not FPockets.TryGetValue(Name, Result) then
  begin
    Result := TResidentPocket.Create;
    Result.Attach(FCensus);
    FPockets.Add(Name, Result);
  end;
end;

function TResidentCarrier.PocketAs<T>(const Name: string): T;
var
  Found: TResidentPocket;
begin
  if FPockets.TryGetValue(Name, Found) then
    Exit(T(Found));
  Result := T.Create;
  Result.Attach(FCensus);
  FPockets.Add(Name, Result);
end;

function TResidentCarrier.HasPocket(const Name: string): Boolean;
begin
  Result := FPockets.ContainsKey(Name);
end;

procedure TResidentCarrier.DropPocket(const Name: string);
begin
  { Словарь владеет значениями, поэтому Remove — это и есть похороны. }
  FPockets.Remove(Name);
end;

function TResidentCarrier.PocketCount: Integer;
begin
  Result := FPockets.Count;
end;

procedure TResidentCarrier.BeginStage;
begin
  FStageDigest := ResidentOffset;
  { Имя нарушения сбрасывается вместе со вкладом стадии: иначе в отчёт попадало
    бы первое за всю жизнь носителя, приписанное той стадии, где его заметили. }
  FBreach := '';
end;

procedure TResidentCarrier.Feed(Value: UInt64);
begin
  FDigest := ResidentMix(FDigest, Value);
  FStageDigest := ResidentMix(FStageDigest, Value);
end;

procedure TResidentCarrier.Claim(Condition: Boolean; const What: string);
begin
  Feed(UInt64(Ord(Condition)));
  if not Condition then
  begin
    Inc(FBroken);
    if FBreach = '' then
      FBreach := What;
  end;
end;

procedure TResidentCarrier.FeedText(const Value: AnsiString);
var
  I: Integer;
begin
  Feed(UInt64(Cardinal(Length(Value))));
  for I := 1 to Length(Value) do
    Feed(UInt64(Ord(Value[I])));
end;

procedure TResidentCarrier.FeedWide(const Value: string);
var
  I: Integer;
begin
  Feed(UInt64(Cardinal(Length(Value))));
  for I := 1 to Length(Value) do
    Feed(UInt64(Word(Value[I])));
end;

procedure TResidentCarrier.StampPassport;
var
  Current: UInt64;
begin
  { Паспорт — это то, что носитель везёт помимо величины: ширина и знак узких
    полей, ширина элемента строки, связность длин, наличие жильцов. Величины,
    которые двигает расписание роста, сюда не входят — иначе паспорт ехал бы
    по замыслу теста, а не по вине компилятора. }
  Current := ResidentOffset;
  { ширина и знак типов: возраст на них влиять не имеет права }
  Current := ResidentMix(Current, UInt64(Cardinal(SizeOf(FTag.Narrow))));
  Current := ResidentMix(Current, UInt64(Cardinal(SizeOf(FTag.Unsigned))));
  Current := ResidentMix(Current, UInt64(Cardinal(SizeOf(FTag.Wide))));
  Current := ResidentMix(Current, UInt64(Ord(FTag.Narrow < 0) xor
                                        Ord(Word(FTag.Narrow) >= $8000)));
  { ширина символа: программа по контракту вся UTF-16 }
  Current := ResidentMix(Current, UInt64(Cardinal(SizeOf(FText.Wide[1]))));
  { связность длин, а не сами длины: длины растут по расписанию, а связь — нет }
  Current := ResidentMix(Current,
    UInt64(Ord(Length(FText.Bytes) = Length(FText.Wide))));
  Current := ResidentMix(Current,
    UInt64(Ord(Length(FText.Utf8) >= Length(FText.Bytes))));
  { карманы фиксированной длины: их размер — паспортная величина }
  Current := ResidentMix(Current,
    UInt64(Cardinal(SizeOf(FSlots) div SizeOf(Int64))));
  Current := ResidentMix(Current, UInt64(Cardinal(Length(FStrings))));
  { маршрут обязан оставаться перестановкой всех стадий }
  Current := ResidentMix(Current, UInt64(Cardinal(Length(FRoute))));
  { жильцы на месте }
  Current := ResidentMix(Current, UInt64(Ord(FToken <> nil)));
  Current := ResidentMix(Current, UInt64(Ord(Assigned(FStep))));
  Current := ResidentMix(Current, UInt64(Ord(FTable <> nil)));
  Current := ResidentMix(Current, UInt64(Ord(FPockets <> nil)));
  Current := ResidentMix(Current, UInt64(Ord(FTag.Intact)));

  if FPassportSet and (Current <> FPassport) then
    FDrift := True;
  FPassport := Current;
  FPassportSet := True;
  Feed(Current);
end;

function TResidentCarrier.Sound: Boolean;
var
  I, Seen: Integer;
  Mask: UInt64;
begin
  Result := FTag.Intact and FText.Intact and (FTable <> nil) and
            (FToken <> nil) and (FPockets <> nil);

  { Маршрут обязан оставаться перестановкой: каждая стадия ровно раз. Проверка
    маской ловит и потерю элемента при переезде массива, и задвоение. }
  if Result and (Length(FRoute) = ResidentStageCount) and
     (ResidentStageCount <= 64) then
  begin
    Mask := 0;
    Seen := 0;
    for I := 0 to High(FRoute) do
      if (FRoute[I] >= 0) and (FRoute[I] < ResidentStageCount) then
      begin
        Mask := Mask or (UInt64(1) shl FRoute[I]);
        Inc(Seen);
      end;
    if (Seen <> Length(FRoute)) or
       (Mask <> not UInt64(0) shr (64 - ResidentStageCount)) then
      Result := False;
  end
  else if Length(FRoute) <> ResidentStageCount then
    Result := False;

  if not Result then
    FCorrupt := True;
end;

end.
