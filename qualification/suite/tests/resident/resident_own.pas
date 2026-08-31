unit resident_own;

{ Семейство `own` — владение и время жизни.

  Здесь проверяется не значение, а судьба: вернулся ли счётчик ссылок туда,
  откуда стартовал; пережило ли захваченное значение кадр, в котором его
  захватили; умер ли объект ровно один раз и ровно тогда, когда обязан был.

  Счётчик ссылок наблюдается напрямую: `TResidentCounted` ведёт свой учёт в
  `_AddRef`/`_Release`, поэтому ARC перестаёт быть невидимкой и становится
  величиной, которую можно предъявить. Все наблюдаемые объекты локальны для
  потока стадии, поэтому чтение счётчика гонок не создаёт.

  Два счёта, и путать их нельзя. Глобальная перепись — общая на программу, её
  показания двигают соседние носители, поэтому в дайджест они не идут никогда;
  она отвечает только за итоговый баланс всего прогона. Локальный счёт живёт
  внутри одной стадии одного потока — вот он детерминирован и предъявляем.

  Замыкания здесь строятся только фабриками. Анонимная функция захватывает
  **переменную**, а не её значение: захвати она локальную, которую потом
  обнулят, — и стадия обвиняла бы компилятор в собственной ошибке. Параметр
  фабрики принадлежит её кадру, поэтому захват однозначен.

  Ни одна стадия не опирается на неопределённое поведение: нет обращений к
  освобождённой памяти, нет циклов ссылок, нет двойного владения. }

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
  { Наблюдаемый счётчик ссылок: ARC становится величиной, а не догадкой. }
  IResidentCounted = interface
    ['{4D5A0010-0000-0000-0000-0000524553FF}']
    function Value: Int64;
    function Live: Integer;
  end;

  IResidentSide = interface
    ['{4D5A0011-0000-0000-0000-0000524553FF}']
    function Mirror: Int64;
  end;

  TResidentCounted = class(TInterfacedObject, IResidentCounted, IResidentSide)
  private
    FValue: Int64;
    FLive: Integer;
    FPeak: Integer;
    FCensus: TResidentCensus;
    FTally: PResidentTally;
  protected
    function _AddRef: Integer;
      {$ifdef MSWINDOWS}stdcall{$else}cdecl{$endif};
    function _Release: Integer;
      {$ifdef MSWINDOWS}stdcall{$else}cdecl{$endif};
  public
    constructor Create(AValue: Int64; ACensus: TResidentCensus;
      ATally: PResidentTally);
    destructor Destroy; override;
    function Value: Int64;
    function Live: Integer;
    function Mirror: Int64;
    property Peak: Integer read FPeak;
  end;

  { Вложенное владение: хозяин хоронит жильца, и никто больше. }
  TResidentHouse = class
  private
    FGuest: TResidentHouse;
    FDepth: Integer;
    FCensus: TResidentCensus;
    FTally: PResidentTally;
  public
    constructor Create(ACensus: TResidentCensus; ATally: PResidentTally;
      ADepth: Integer);
    destructor Destroy; override;
    function Total: Int64;
    property Guest: TResidentHouse read FGuest;
    property Depth: Integer read FDepth;
  end;

  { Карман семейства: живёт между оборотами и обязан пережить их все. }
  TResidentOwnPocket = class(TResidentPocket)
  private
    FKept: IResidentCounted;
    FSteps: TArray<TResidentStep>;
    FRounds: Int64;
  public
    destructor Destroy; override;
  end;

  TResidentBox = record
    Held: IResidentCounted;
    Text: string;
    Slot: Int64;
  end;

{ ------------------------------------------------------- TResidentCounted -- }

constructor TResidentCounted.Create(AValue: Int64; ACensus: TResidentCensus;
  ATally: PResidentTally);
begin
  inherited Create;
  FValue := AValue;
  FCensus := ACensus;
  FTally := ATally;
  if FCensus <> nil then
    FCensus.NoteBorn;
  if FTally <> nil then
    Inc(FTally^.Born);
end;

destructor TResidentCounted.Destroy;
begin
  if FTally <> nil then
    Inc(FTally^.Gone);
  if FCensus <> nil then
    FCensus.NoteGone;
  inherited Destroy;
end;

function TResidentCounted._AddRef: Integer;
begin
  Result := inherited _AddRef;
  { Объект локален для потока стадии, поэтому счёт ведётся без блокировки:
    наблюдение не имеет права стоить дороже наблюдаемого. }
  Inc(FLive);
  if FLive > FPeak then
    FPeak := FLive;
end;

function TResidentCounted._Release: Integer;
begin
  Dec(FLive);
  Result := inherited _Release;
end;

function TResidentCounted.Value: Int64;
begin
  Result := FValue;
end;

function TResidentCounted.Live: Integer;
begin
  Result := FLive;
end;

function TResidentCounted.Mirror: Int64;
begin
  Result := not FValue;
end;

{ --------------------------------------------------------- TResidentHouse -- }

constructor TResidentHouse.Create(ACensus: TResidentCensus;
  ATally: PResidentTally; ADepth: Integer);
begin
  inherited Create;
  FCensus := ACensus;
  FTally := ATally;
  FDepth := ADepth;
  FCensus.NoteBorn;
  if FTally <> nil then
    Inc(FTally^.Born);
  if ADepth > 0 then
    FGuest := TResidentHouse.Create(ACensus, ATally, ADepth - 1);
end;

destructor TResidentHouse.Destroy;
begin
  { Хозяин хоронит жильца до собственной смерти: обратный порядок оставил бы
    жильца без хозяина, а перепись — с недостачей. }
  FreeAndNil(FGuest);
  if FTally <> nil then
    Inc(FTally^.Gone);
  FCensus.NoteGone;
  inherited Destroy;
end;

function TResidentHouse.Total: Int64;
begin
  Result := FDepth;
  if FGuest <> nil then
    Result := Result + FGuest.Total;
end;

{ ----------------------------------------------------- TResidentOwnPocket -- }

destructor TResidentOwnPocket.Destroy;
begin
  FKept := nil;
  SetLength(FSteps, 0);
  inherited Destroy;
end;

{ --------------------------------------------------------------- фабрики -- }

{ Замыкание строится только здесь: параметр принадлежит кадру фабрики, поэтому
  захвачено ровно то, что передано, и внешние присваивания на него не влияют. }
function MakeAdder(Addend: Int64): TResidentStep;
begin
  Result :=
    function(const V: Int64): Int64
    begin
      Result := V + Addend;
    end;
end;

function MakeLink(const Inner: TResidentStep; Step: Int64): TResidentStep;
begin
  Result :=
    function(const V: Int64): Int64
    begin
      Result := Inner(V) + Step;
    end;
end;

function MakeReader(const Held: IResidentCounted): TResidentStep;
begin
  Result :=
    function(const V: Int64): Int64
    begin
      Result := V xor Held.Value;
    end;
end;

{ ------------------------------------------------------------- стадии ----- }

{ Делегирование через интерфейс: ссылка, отданная посреднику, обязана вернуться
  ровно к тому же счёту, с какого ушла. }
procedure StageRelay(Carrier: TResidentCarrier);
var
  Held: IResidentToken;
begin
  Held := Carrier.Token;
  Carrier.Feed(UInt64(Held.Payload xor Carrier.Tag.Wide));
  Carrier.Feed(UInt64(Cardinal(Held.Serial)));
  { Владелец не сменился: носитель по-прежнему держит свой жетон. }
  Carrier.Feed(UInt64(Ord(Carrier.Token = Held)));
  Held := nil;
  Carrier.Feed(UInt64(Ord(Carrier.Token <> nil)));
end;

{ Лестница ссылок: счётчик поднимается на известную высоту и обязан спуститься
  ровно туда, откуда начал. }
procedure StageRefLadder(Carrier: TResidentCarrier);
var
  Tally: TResidentTally;
  Made: TResidentCounted;
  A, B, C: IResidentCounted;
  Bottom, Top: Integer;
begin
  Tally := Default(TResidentTally);
  Made := TResidentCounted.Create(Carrier.Tag.Wide, Carrier.Census, @Tally);
  A := Made;
  Bottom := Made.Live;
  B := A;
  C := B;
  Top := Made.Live;
  Carrier.Feed(UInt64(Cardinal(Bottom)));
  Carrier.Feed(UInt64(Cardinal(Top)));
  Carrier.Feed(UInt64(Cardinal(Top - Bottom)));
  C := nil;
  B := nil;
  Carrier.Feed(UInt64(Cardinal(Made.Live)));
  Carrier.Feed(UInt64(Cardinal(Made.Peak)));
  Carrier.Feed(UInt64(A.Value));
  A := nil;
  { Последняя ссылка ушла — объект обязан быть похоронен ровно один раз. }
  Carrier.Feed(UInt64(Tally.Born));
  Carrier.Feed(UInt64(Tally.Gone));
  Carrier.Feed(UInt64(Cardinal(Ord(Tally.Alive = 0))));
end;

{ Захваченное значение обязано пережить кадр, в котором его захватили. }
procedure StageClosureCapture(Carrier: TResidentCarrier);
var
  Made: TResidentStep;
  Tag: TResidentTag;
begin
  Tag := Carrier.Tag;
  Made := MakeAdder(Tag.Wide);
  Carrier.Feed(UInt64(Made(Tag.Wide)));
  { Замыкание, сделанное на прошлом обороте, обязано работать и сейчас. }
  if Assigned(Carrier.Step) then
    Carrier.Feed(UInt64(Carrier.Step(Tag.Wide)));
  Carrier.Step := Made;
end;

{ Цепочка замыканий: каждое держит предыдущее, и вся цепь обязана дожить до
  вызова, а потом целиком умереть. }
procedure StageClosureChain(Carrier: TResidentCarrier);
var
  Pocket: TResidentOwnPocket;
  Chain: TResidentStep;
  I, Depth: Integer;
  Salt: Int64;
begin
  Pocket := Carrier.PocketAs<TResidentOwnPocket>('own-closure-chain');
  Depth := 1 + (Carrier.Lap mod 6);
  Salt := Carrier.Tag.Wide;

  Chain := MakeAdder(Salt);
  for I := 1 to Depth do
    Chain := MakeLink(Chain, I);
  Carrier.Feed(UInt64(Chain(Salt)));
  Carrier.Feed(UInt64(Cardinal(Depth)));

  { Цепочка складывается в карман и живёт до следующего оборота: так проверяется
    не только вызов, но и хранение. }
  SetLength(Pocket.FSteps, Depth);
  for I := 0 to Depth - 1 do
    Pocket.FSteps[I] := Chain;
  Inc(Pocket.FRounds);
  Carrier.Feed(UInt64(Pocket.FRounds));
  Carrier.Feed(UInt64(Pocket.FSteps[0](Salt)));
end;

{ Порядок разрушения вложенных владельцев: хозяин уходит последним. }
procedure StageNestedOwner(Carrier: TResidentCarrier);
var
  Tally: TResidentTally;
  House: TResidentHouse;
  Depth: Integer;
begin
  Tally := Default(TResidentTally);
  Depth := 1 + (Carrier.Lap mod 5);
  House := TResidentHouse.Create(Carrier.Census, @Tally, Depth);
  try
    Carrier.Feed(UInt64(House.Total));
    Carrier.Feed(UInt64(Cardinal(House.Depth)));
    { Дом со всеми жильцами построен целиком внутри этого потока, поэтому его
      локальный счёт — величина программы, а не расписания. }
    Carrier.Feed(UInt64(Tally.Born));
    Carrier.Feed(UInt64(Cardinal(Ord(Tally.Born = Depth + 1))));
  finally
    House.Free;
  end;
  Carrier.Feed(UInt64(Tally.Gone));
  Carrier.Feed(UInt64(Cardinal(Ord(Tally.Alive = 0))));
end;

{ Обмен двух интерфейсных ссылок: после обмена оба счётчика обязаны остаться
  прежними, а значения — поменяться местами. }
procedure StageInterfaceSwap(Carrier: TResidentCarrier);
var
  Tally: TResidentTally;
  Left, Right, Spare: IResidentCounted;
  MadeLeft, MadeRight: TResidentCounted;
begin
  Tally := Default(TResidentTally);
  MadeLeft := TResidentCounted.Create(Carrier.Tag.Wide, Carrier.Census, @Tally);
  MadeRight := TResidentCounted.Create(not Carrier.Tag.Wide, Carrier.Census,
                                       @Tally);
  Left := MadeLeft;
  Right := MadeRight;

  Spare := Left;
  Left := Right;
  Right := Spare;
  Spare := nil;

  Carrier.Feed(UInt64(Left.Value));
  Carrier.Feed(UInt64(Right.Value));
  Carrier.Feed(UInt64(Cardinal(MadeLeft.Live)));
  Carrier.Feed(UInt64(Cardinal(MadeRight.Live)));
  Carrier.Feed(UInt64(Ord(Left.Value = MadeRight.Value)));
  Left := nil;
  Right := nil;
  Carrier.Feed(UInt64(Tally.Born));
  Carrier.Feed(UInt64(Tally.Gone));
end;

{ Приведение интерфейса к соседнему интерфейсу того же объекта: обе ссылки
  обязаны вести к одному хозяину. }
procedure StageInterfaceCast(Carrier: TResidentCarrier);
var
  Tally: TResidentTally;
  Counted: IResidentCounted;
  Side: IResidentSide;
  Ok: Boolean;
begin
  Tally := Default(TResidentTally);
  Counted := TResidentCounted.Create(Carrier.Tag.Wide, Carrier.Census, @Tally);
  Ok := Supports(Counted, IResidentSide, Side);
  Carrier.Feed(UInt64(Ord(Ok)));
  if Ok then
  begin
    Carrier.Feed(UInt64(Side.Mirror));
    Carrier.Feed(UInt64(Ord(Side.Mirror = not Counted.Value)));
    Carrier.Feed(UInt64(Ord((Counted as IResidentSide) = Side)));
  end;
  Side := nil;
  Counted := nil;
  Carrier.Feed(UInt64(Cardinal(Ord(Tally.Alive = 0))));
end;

{ Интерфейс внутри управляемой записи. Копия по значению обязана поднять
  счётчик, передача с `const` — нет. Разница этих двух чисел и есть факт. }
procedure StageInterfaceInRecord(Carrier: TResidentCarrier);
var
  Tally: TResidentTally;
  Made: TResidentCounted;
  Source: TResidentBox;
  Alone, ByValue, ByConst: Integer;

  procedure SeeByValue(Box: TResidentBox);
  begin
    ByValue := Made.Live;
    Carrier.Feed(UInt64(Box.Held.Value));
    Carrier.Feed(UInt64(Cardinal(Length(Box.Text))));
  end;

  procedure SeeByConst(const Box: TResidentBox);
  begin
    ByConst := Made.Live;
    Carrier.Feed(UInt64(Box.Held.Value));
    Carrier.Feed(UInt64(Cardinal(Length(Box.Text))));
  end;

begin
  Tally := Default(TResidentTally);
  Made := TResidentCounted.Create(Carrier.Tag.Wide, Carrier.Census, @Tally);
  Source.Held := Made;
  Source.Text := Carrier.Text.Wide;
  Source.Slot := Carrier.Tag.Wide;
  Alone := Made.Live;

  SeeByValue(Source);
  SeeByConst(Source);
  Carrier.Feed(UInt64(Cardinal(Alone)));
  Carrier.Feed(UInt64(Cardinal(ByValue)));
  Carrier.Feed(UInt64(Cardinal(ByConst)));
  Carrier.Feed(UInt64(Cardinal(Ord(ByValue > ByConst))));
  { Счётчик обязан вернуться туда, где стоял до обоих вызовов. }
  Carrier.Feed(UInt64(Cardinal(Ord(Made.Live = Alone))));

  var Twin := Source;
  Carrier.Feed(UInt64(Cardinal(Made.Live)));
  Carrier.Feed(UInt64(Ord(Twin.Held = Source.Held)));
  Twin.Held := nil;
  Carrier.Feed(UInt64(Cardinal(Made.Live)));

  Source.Held := nil;
  Carrier.Feed(UInt64(Cardinal(Ord(Tally.Alive = 0))));
end;

{ Передача владения наружу через out-параметр: принимающая сторона становится
  единственным владельцем, отдающая обязана расстаться. }
procedure StageTransferOut(Carrier: TResidentCarrier);
var
  Tally: TResidentTally;
  Made: TResidentCounted;
  Taken: IResidentCounted;

  procedure HandOver(out Target: IResidentCounted);
  var
    Local: IResidentCounted;
  begin
    Local := Made;
    Target := Local;
    Local := nil;
  end;

begin
  Tally := Default(TResidentTally);
  Made := TResidentCounted.Create(Carrier.Tag.Wide, Carrier.Census, @Tally);
  { Объект ещё ничей: ни одной ссылки на него не взято. }
  Carrier.Feed(UInt64(Cardinal(Made.Live)));
  HandOver(Taken);
  Carrier.Feed(UInt64(Cardinal(Made.Live)));
  Carrier.Feed(UInt64(Taken.Value));
  Taken := nil;
  Carrier.Feed(UInt64(Tally.Gone));
end;

{ Массив интерфейсов: рост, усечение и полный сброс. Каждая ссылка в выброшенном
  хвосте обязана быть отпущена, иначе перепись покажет недостачу. }
procedure StageInterfaceArray(Carrier: TResidentCarrier);
var
  Tally: TResidentTally;
  Held: TArray<IResidentCounted>;
  I, Room: Integer;
  Sum: Int64;
begin
  Tally := Default(TResidentTally);
  Room := 1 + (Carrier.Lap mod 12);
  SetLength(Held, Room);
  for I := 0 to Room - 1 do
    Held[I] := TResidentCounted.Create(Carrier.Tag.Wide + I, Carrier.Census,
                                       @Tally);

  Sum := 0;
  for I := 0 to Room - 1 do
    Sum := Sum xor Held[I].Value;
  Carrier.Feed(UInt64(Sum));
  Carrier.Feed(UInt64(Cardinal(Room)));
  Carrier.Feed(UInt64(Tally.Born));

  { Усечение обязано отпустить хвост: длина уменьшилась, значит и похороненных
    ровно столько же, сколько выброшено. }
  SetLength(Held, Room div 2);
  Sum := 0;
  for I := 0 to High(Held) do
    Sum := Sum xor Held[I].Value;
  Carrier.Feed(UInt64(Sum));
  Carrier.Feed(UInt64(Cardinal(Length(Held))));
  Carrier.Feed(UInt64(Tally.Gone));
  Carrier.Feed(UInt64(Cardinal(Ord(Tally.Gone = Room - Room div 2))));

  SetLength(Held, 0);
  Carrier.Feed(UInt64(Cardinal(Length(Held))));
  Carrier.Feed(UInt64(Cardinal(Ord(Tally.Alive = 0))));
end;

{ Владение при исключении: раскрутка стека обязана довести до `finally` и
  похоронить всё, что было заведено. }
procedure StageExceptionUnwind(Carrier: TResidentCarrier);
var
  Tally: TResidentTally;
  House: TResidentHouse;
  Reached: Integer;
begin
  Tally := Default(TResidentTally);
  Reached := 0;
  House := TResidentHouse.Create(Carrier.Census, @Tally, 2);
  try
    try
      Carrier.Feed(UInt64(Tally.Born));
      raise EAbort.Create('resident: planned unwind');
    except
      on E: EAbort do
      begin
        Reached := 1;
        Carrier.Feed(UInt64(Cardinal(Length(E.Message))));
      end;
    end;
  finally
    House.Free;
    Inc(Reached, 2);
  end;
  Carrier.Feed(UInt64(Cardinal(Reached)));
  Carrier.Feed(UInt64(Tally.Gone));
  Carrier.Feed(UInt64(Cardinal(Ord(Tally.Alive = 0))));
end;

{ Карман заводится, живёт и хоронится: баланс обязан сойтись даже при том, что
  владелец кармана — носитель, а не стадия. }
procedure StagePocketCycle(Carrier: TResidentCarrier);
const
  Name = 'own-pocket-cycle-temp';
var
  Pocket: TResidentPocket;
  Had: Boolean;
begin
  Had := Carrier.HasPocket(Name);
  Pocket := Carrier.Pocket(Name);
  Carrier.Feed(UInt64(Ord(Had)));
  Carrier.Feed(UInt64(Ord(Pocket <> nil)));
  Carrier.Feed(UInt64(Ord(Carrier.Pocket(Name) = Pocket)));

  { Каждый третий оборот карман сносится: за прогон случается и вселение, и
    выселение, и повторное занятие того же имени. }
  if Carrier.Lap mod 3 = 2 then
  begin
    Carrier.DropPocket(Name);
    Carrier.Feed(UInt64(Ord(Carrier.HasPocket(Name))));
  end;
end;

{ Ссылка, положенная в карман, обязана дожить до следующего оборота и быть той
  же самой. }
procedure StageKeptAcrossLaps(Carrier: TResidentCarrier);
var
  Pocket: TResidentOwnPocket;
  Fresh: IResidentCounted;
  Same: Boolean;
begin
  Pocket := Carrier.PocketAs<TResidentOwnPocket>('own-kept');
  if Pocket.FKept <> nil then
  begin
    Carrier.Feed(UInt64(Pocket.FKept.Value));
    Carrier.Feed(UInt64(Cardinal(Pocket.FKept.Live)));
  end;

  Fresh := TResidentCounted.Create(Carrier.Tag.Wide, Carrier.Census, nil);
  Same := Fresh = Pocket.FKept;
  Carrier.Feed(UInt64(Ord(Same)));
  { Старый жилец отпускается ровно в момент замены — не раньше и не позже. }
  Pocket.FKept := Fresh;
  Fresh := nil;
  Carrier.Feed(UInt64(Cardinal(Pocket.FKept.Live)));
end;

{ Анонимная функция как владелец: захваченная ссылка живёт столько же, сколько
  само замыкание, и ни мгновением дольше. }
procedure StageClosureOwns(Carrier: TResidentCarrier);
var
  Tally: TResidentTally;
  Made: TResidentCounted;
  Held: IResidentCounted;
  Reader: TResidentStep;
  WhileAlive, AfterDrop: Integer;
begin
  Tally := Default(TResidentTally);
  Made := TResidentCounted.Create(Carrier.Tag.Wide, Carrier.Census, @Tally);
  Held := Made;
  Reader := MakeReader(Held);
  WhileAlive := Made.Live;
  Carrier.Feed(UInt64(Reader(Carrier.Tag.Wide)));
  Carrier.Feed(UInt64(Cardinal(WhileAlive)));

  { Локальная ссылка ушла, но замыкание держит свою — объект обязан жить. }
  Held := nil;
  AfterDrop := Made.Live;
  Carrier.Feed(UInt64(Cardinal(AfterDrop)));
  Carrier.Feed(UInt64(Reader(0)));
  Carrier.Feed(UInt64(Cardinal(Ord(AfterDrop > 0))));
  Carrier.Feed(UInt64(Tally.Gone));

  { Замыкание умерло — с ним обязана уйти и последняя ссылка. }
  Reader := nil;
  Carrier.Feed(UInt64(Tally.Gone));
  Carrier.Feed(UInt64(Cardinal(Ord(Tally.Alive = 0))));
end;

{ Список объектов с владением: `TObjectList` хоронит содержимое сам. }
procedure StageObjectListOwns(Carrier: TResidentCarrier);
var
  Tally: TResidentTally;
  List: TObjectList<TResidentHouse>;
  I, Room: Integer;
  Sum: Int64;
begin
  Tally := Default(TResidentTally);
  Room := 1 + (Carrier.Lap mod 7);
  List := TObjectList<TResidentHouse>.Create(True);
  try
    for I := 0 to Room - 1 do
      List.Add(TResidentHouse.Create(Carrier.Census, @Tally, 1));
    Sum := 0;
    for I := 0 to List.Count - 1 do
      Sum := Sum + List[I].Total;
    Carrier.Feed(UInt64(Sum));
    Carrier.Feed(UInt64(Cardinal(List.Count)));
    Carrier.Feed(UInt64(Tally.Born));

    { Удаление из середины: список хоронит удалённого, остальные не шелохнулись. }
    if List.Count > 1 then
    begin
      List.Delete(List.Count div 2);
      Carrier.Feed(UInt64(Cardinal(List.Count)));
      Carrier.Feed(UInt64(Tally.Gone));
    end;
  finally
    List.Free;
  end;
  Carrier.Feed(UInt64(Tally.Gone));
  Carrier.Feed(UInt64(Cardinal(Ord(Tally.Alive = 0))));
end;

{ Список без владения: тот же тип, обратный контракт. Хоронит вызывающая
  сторона, и счёт обязан сойтись всё равно. }
procedure StageObjectListBorrows(Carrier: TResidentCarrier);
var
  Tally: TResidentTally;
  List: TObjectList<TResidentHouse>;
  Made: TArray<TResidentHouse>;
  I, Room: Integer;
  Sum: Int64;
begin
  Tally := Default(TResidentTally);
  Room := 1 + (Carrier.Lap mod 5);
  SetLength(Made, Room);
  List := TObjectList<TResidentHouse>.Create(False);
  try
    for I := 0 to Room - 1 do
    begin
      Made[I] := TResidentHouse.Create(Carrier.Census, @Tally, 0);
      List.Add(Made[I]);
    end;
    Sum := 0;
    for I := 0 to List.Count - 1 do
      Sum := Sum + Int64(List[I].Depth);
    Carrier.Feed(UInt64(Sum));
    List.Clear;
    Carrier.Feed(UInt64(Cardinal(List.Count)));
    { Список не владел: очистка не имела права никого похоронить. }
    Carrier.Feed(UInt64(Tally.Gone));
  finally
    List.Free;
  end;
  for I := 0 to Room - 1 do
    Made[I].Free;
  Carrier.Feed(UInt64(Tally.Gone));
  Carrier.Feed(UInt64(Cardinal(Ord(Tally.Alive = 0))));
end;

{ Интерфейс, отданный в поле объекта и забранный обратно: владение переезжает
  дважды и обязано вернуться в исходную точку. }
procedure StageOwnershipRoundTrip(Carrier: TResidentCarrier);
var
  Pocket: TResidentOwnPocket;
  Made: TResidentCounted;
  Local: IResidentCounted;
  AtHome, InPocket, BackHome: Integer;
begin
  Pocket := Carrier.PocketAs<TResidentOwnPocket>('own-round-trip');
  Made := TResidentCounted.Create(Carrier.Tag.Wide, Carrier.Census, nil);
  Local := Made;
  AtHome := Made.Live;

  Pocket.FKept := Local;
  InPocket := Made.Live;
  Local := nil;

  Local := Pocket.FKept;
  Pocket.FKept := nil;
  BackHome := Made.Live;

  Carrier.Feed(UInt64(Cardinal(AtHome)));
  Carrier.Feed(UInt64(Cardinal(InPocket)));
  Carrier.Feed(UInt64(Cardinal(BackHome)));
  Carrier.Feed(UInt64(Ord(AtHome = BackHome)));
  Carrier.Feed(UInt64(Local.Value));
  Local := nil;
end;

initialization
  ResidentRegisterStage('own-closure-capture', @StageClosureCapture);
  ResidentRegisterStage('own-closure-chain', @StageClosureChain);
  ResidentRegisterStage('own-closure-owns', @StageClosureOwns);
  ResidentRegisterStage('own-exception-unwind', @StageExceptionUnwind);
  ResidentRegisterStage('own-interface-array', @StageInterfaceArray);
  ResidentRegisterStage('own-interface-cast', @StageInterfaceCast);
  ResidentRegisterStage('own-interface-in-record', @StageInterfaceInRecord);
  ResidentRegisterStage('own-interface-swap', @StageInterfaceSwap);
  ResidentRegisterStage('own-kept-across-laps', @StageKeptAcrossLaps);
  ResidentRegisterStage('own-nested-owner', @StageNestedOwner);
  ResidentRegisterStage('own-objectlist-borrows', @StageObjectListBorrows);
  ResidentRegisterStage('own-objectlist-owns', @StageObjectListOwns);
  ResidentRegisterStage('own-pocket-cycle', @StagePocketCycle);
  ResidentRegisterStage('own-ref-ladder', @StageRefLadder);
  ResidentRegisterStage('own-relay', @StageRelay);
  ResidentRegisterStage('own-round-trip', @StageOwnershipRoundTrip);
  ResidentRegisterStage('own-transfer-out', @StageTransferOut);

end.
