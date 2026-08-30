unit chimera_hold;

{ Орган «держатели»: кольцевой буфер с одним писателем и список с копией при
  записи и отложенной уборкой.

  Источник: `Arbitrage/Common\HelpClasses.pas` —
  `TThreadSafeBuffer<T>`, `TSlowSafeList<T>`, `TDelayedTrash`. Перенесено
  дословно по форме:

    * кольцо на обобщённом типе: позиция двигается ВПЕРЁД перед записью,
      счётчик растёт только до размера, чтение идёт назад от позиции с
      заворотом через ноль, а очистка ставит позицию в минус единицу;
    * чтение по номеру назад с обрезкой номера по размеру — тихая, без
      исключения: спросили дальше, чем помнит кольцо, — получили отказ;
    * список с копией при записи: обычное добавление правит список на месте, а
      «медленное» СОЗДАЁТ новый список из старого, добавляет в него и
      подменяет ссылку, а старый отдаёт в отложенную уборку. Читатель, который
      уже взял ссылку, продолжает ходить по старому телу;
    * отложенная уборка чистит протухшее при каждом добавлении, а не по
      таймеру.

  Почему это отдельная форма:

    * запись `FBuffer[P] := aValue` идёт ДО публикации новой позиции — тот же
      порядок двух присваиваний, что в кольце сделок, но на обобщённом типе и
      с возвратом УКАЗАТЕЛЯ на только что записанный слот;
    * подмена ссылки на список под ногами читателя законна ровно потому, что
      старое тело живо ещё какое-то время. Если уборка заберёт его раньше,
      читатель пойдёт по освобождённой памяти — а это не падение, а тихая
      порча;
    * обобщённый тип разворачивается и для простого, и для управляемого
      содержимого, и счёт ссылок обязан сойтись в обоих случаях.

  Оракулы:

    1. независимая модель кольца обычным массивом с явным индексом: она
       хранит последние N значений и не знает про заворот;
    2. снимок списка, взятый ДО подмены, обязан остаться прежним по длине и
       содержимому, а новый — отличаться ровно на добавленное;
    3. счётчик живых объектов: всё, что ушло в отложенную уборку, обязано
       умереть ровно один раз. }

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch INLINEVARS}
{$endif}
{$Q-}{$R-}

interface

uses
  SysUtils, Classes, Generics.Collections, chimera_body, chimera_crew;

type
  { Кольцо: один писатель, чтение назад от текущей позиции. }
  TChiRingBuf<T> = class
  private
    FSize:   Integer;
    FCount:  Integer;
    FPos:    Integer;
    FBuffer: TArray<T>;
  public
    constructor Create(ASize: Integer);
    function Add(const AValue: T): Pointer;
    function Read: T;
    function GetValue(var AValue: T; N: Integer): Boolean;
    procedure Clear;
    property Count: Integer read FCount;
    property Size: Integer read FSize;
  end;

  { Отложенная уборка: объекты не освобождаются сразу — читатель, взявший
    ссылку, обязан успеть уйти. }
  TChiTrash = class
  private
    FItems: TList<TObject>;
    FAges:  TList<Int64>;
    FNow:   Int64;
    FFreed: Int64;
  public
    constructor Create;
    destructor Destroy; override;
    procedure AddTrash(AObject: TObject);
    procedure Tick(Age: Int64);
    property Freed: Int64 read FFreed;
  end;

  { Список с копией при записи. }
  TChiSlowList<T> = class
  private
    FList: TList<T>;
    FTrash: TChiTrash;
    FCopies: Int64;
  public
    constructor Create(ATrash: TChiTrash);
    destructor Destroy; override;
    procedure Add(const Value: T; MainList: Boolean);
    function Snapshot: TList<T>;
    function Count: Integer;
    property Copies: Int64 read FCopies;
  end;

function ChiHoldRun: Int64;

implementation

{ ═══ Кольцо ══════════════════════════════════════════════════════════════ }

constructor TChiRingBuf<T>.Create(ASize: Integer);
begin
  inherited Create;
  FSize := ASize;
  SetLength(FBuffer, FSize);
  FPos := -1;
  FCount := 0;
end;

function TChiRingBuf<T>.Add(const AValue: T): Pointer;
var
  P: Integer;
begin
  P := FPos + 1;
  if P >= FSize then P := 0;
  { Слот заполняется ДО публикации новой позиции. }
  FBuffer[P] := AValue;
  Result := @FBuffer[P];
  FPos := P;
  if FCount < FSize then Inc(FCount);
end;

function TChiRingBuf<T>.Read: T;
begin
  if (FPos < 0) or (FCount = 0) then
    raise EInvalidOpException.Create('чтение из пустого кольца');
  Result := FBuffer[FPos];
end;

function TChiRingBuf<T>.GetValue(var AValue: T; N: Integer): Boolean;
var
  P: Integer;
begin
  { Номер обрезается по размеру молча — это не ошибка, а правило. }
  if N > FSize - 1 then N := FSize - 1;
  if (FPos < 0) or (FCount = 0) or (N >= FCount) then Exit(False);
  P := FPos - N;
  if P < 0 then P := FSize + P;
  AValue := FBuffer[P];
  Result := True;
end;

procedure TChiRingBuf<T>.Clear;
begin
  FCount := 0;
  FPos := -1;
end;

{ ═══ Отложенная уборка ═══════════════════════════════════════════════════ }

constructor TChiTrash.Create;
begin
  inherited Create;
  FItems := TList<TObject>.Create;
  FAges := TList<Int64>.Create;
end;

destructor TChiTrash.Destroy;
var
  I: Integer;
begin
  for I := 0 to FItems.Count - 1 do FItems[I].Free;
  FreeAndNil(FItems);
  FreeAndNil(FAges);
  inherited Destroy;
end;

procedure TChiTrash.AddTrash(AObject: TObject);
begin
  if AObject = nil then Exit;
  FItems.Add(AObject);
  FAges.Add(FNow);
  { Чистка протухшего идёт при каждом добавлении, а не по таймеру. }
  Tick(FNow);
end;

procedure TChiTrash.Tick(Age: Int64);
var
  I: Integer;
begin
  FNow := Age;
  for I := FItems.Count - 1 downto 0 do
    if FNow - FAges[I] >= 10 then
    begin
      FItems[I].Free;
      Inc(FFreed);
      FItems.Delete(I);
      FAges.Delete(I);
    end;
end;

{ ═══ Список с копией при записи ══════════════════════════════════════════ }

constructor TChiSlowList<T>.Create(ATrash: TChiTrash);
begin
  inherited Create;
  FTrash := ATrash;
  FList := TList<T>.Create;
end;

destructor TChiSlowList<T>.Destroy;
begin
  FreeAndNil(FList);
  inherited Destroy;
end;

procedure TChiSlowList<T>.Add(const Value: T; MainList: Boolean);
var
  NewList: TList<T>;
begin
  if MainList then
    { Прямое добавление: тело правится под ногами читателя. }
    FList.Add(Value)
  else
  begin
    { Копия при записи: старое тело остаётся жить, пока его не приберут. }
    NewList := TList<T>.Create;
    NewList.AddRange(FList);
    NewList.Add(Value);
    FTrash.AddTrash(FList);
    FList := NewList;
    Inc(FCopies);
  end;
end;

function TChiSlowList<T>.Snapshot: TList<T>;
begin
  Result := FList;
end;

function TChiSlowList<T>.Count: Integer;
begin
  Result := FList.Count;
end;

{ ═══ Проверка ════════════════════════════════════════════════════════════ }

type
  TChiHeld = class
    Value: Int64;
    constructor Create(AValue: Int64);
    destructor Destroy; override;
  end;

var
  LiveHeld: Integer;

constructor TChiHeld.Create(AValue: Int64);
begin
  inherited Create;
  Value := AValue;
  AtomicIncrement(LiveHeld);
end;

destructor TChiHeld.Destroy;
begin
  AtomicDecrement(LiveHeld);
  inherited Destroy;
end;

const
  IdBuf  = 'CHI-ARB-BUF-001';
  RingSz = 16;

function ChiHoldRun: Int64;
var
  Ring: TChiRingBuf<Int64>;
  Strings: TChiRingBuf<string>;
  Model: array [0 .. 255] of Int64;
  ModelCount, I, J: Integer;
  Value: Int64;
  Text: string;
  Acc: UInt64;
  Slot: Pointer;
  Trash: TChiTrash;
  Slow: TChiSlowList<Int64>;
  Before, After: TList<Int64>;
  BeforeLen: Integer;
  Raised: Boolean;
  StartHeld: Integer;
  Held: TChiSlowList<TChiHeld>;
begin
  ChiCovered(IdBuf);
  Acc := ChiOffset;
  StartHeld := LiveHeld;

  { ── Кольцо: заворот, чтение назад, обрезка номера ── }
  Ring := TChiRingBuf<Int64>.Create(RingSz);
  try
    { Пустое кольцо: чтение обязано отказать, а не отдать мусор. }
    ChiClaim(not Ring.GetValue(Value, 0), 'кольцо: пустое отдало значение');
    Raised := False;
    try
      Ring.Read;
    except
      on E: EInvalidOpException do Raised := True;
    end;
    ChiClaim(Raised, 'кольцо: чтение пустого не бросило');
    ChiBranch(IdBuf, 'empty-refuses');

    ModelCount := 0;
    for I := 1 to 100 do
    begin
      Slot := Ring.Add(I * 7);
      ChiClaim(PInt64(Slot)^ = I * 7, 'кольцо: указатель на слот не тот');
      { Модель: просто последние N значений подряд. }
      Model[ModelCount] := I * 7;
      Inc(ModelCount);

      ChiClaim(Ring.Read = I * 7, 'кольцо: последнее не последнее');
      { Счёт растёт только до размера. }
      if I <= RingSz then
        ChiClaim(Ring.Count = I, 'кольцо: счёт до заполнения не тот')
      else
        ChiClaim(Ring.Count = RingSz, 'кольцо: счёт перевалил за размер');
    end;
    ChiBranch(IdBuf, 'wrap');

    { Чтение назад обязано совпасть с моделью на всю глубину кольца. }
    for J := 0 to RingSz - 1 do
    begin
      ChiClaim(Ring.GetValue(Value, J), 'кольцо: отказ внутри глубины');
      ChiClaim(Value = Model[ModelCount - 1 - J],
        'кольцо: значение назад на ' + IntToStr(J) + ' не то');
      Acc := ChiMix(Acc, Value);
    end;
    ChiBranch(IdBuf, 'read-back');

    { Номер сверх размера обрезается молча и отдаёт самое старое. }
    ChiClaim(Ring.GetValue(Value, 1000), 'кольцо: обрезка номера отказала');
    ChiClaim(Value = Model[ModelCount - RingSz],
      'кольцо: обрезанный номер отдал не самое старое');
    ChiBranch(IdBuf, 'clamped-index');

    Ring.Clear;
    ChiClaim(Ring.Count = 0, 'кольцо: очистка не обнулила счёт');
    ChiClaim(not Ring.GetValue(Value, 0), 'кольцо: после очистки отдало');
    ChiBranch(IdBuf, 'clear');
  finally
    FreeAndNil(Ring);
  end;

  { ── То же кольцо на управляемом содержимом ── }
  Strings := TChiRingBuf<string>.Create(8);
  try
    for I := 1 to 40 do Strings.Add('элемент ' + IntToStr(I));
    ChiClaim(Strings.Read = 'элемент 40', 'кольцо строк: последнее не то');
    ChiClaim(Strings.GetValue(Text, 7), 'кольцо строк: отказ на глубине');
    ChiClaim(Text = 'элемент 33', 'кольцо строк: значение назад не то');
    ChiBranch(IdBuf, 'managed-content');
    Acc := ChiMix(Acc, Length(Text));
  finally
    FreeAndNil(Strings);
  end;

  { ── Список с копией при записи и отложенной уборкой ── }
  Trash := TChiTrash.Create;
  Slow := TChiSlowList<Int64>.Create(Trash);
  try
    for I := 1 to 5 do Slow.Add(I, True);
    ChiClaim(Slow.Count = 5, 'список: прямое добавление не сработало');
    ChiBranch(IdBuf, 'direct-add');

    { Читатель берёт ссылку на тело ДО подмены. }
    Before := Slow.Snapshot;
    BeforeLen := Before.Count;
    Slow.Add(99, False);
    After := Slow.Snapshot;

    ChiClaim(After <> Before, 'список: тело не подменилось');
    ChiClaim(Before.Count = BeforeLen, 'список: старое тело изменилось');
    ChiClaim(After.Count = BeforeLen + 1, 'список: новое тело не выросло');
    ChiClaim(After[After.Count - 1] = 99, 'список: добавленное не то');
    ChiBranch(IdBuf, 'copy-on-write');

    { Старое тело обязано быть ещё живым: читатель по нему ходит. }
    Value := 0;
    for I := 0 to Before.Count - 1 do Value := Value + Before[I];
    ChiClaim(Value = 1 + 2 + 3 + 4 + 5,
      'список: старое тело уже испорчено');
    ChiBranch(IdBuf, 'old-body-alive');
    Acc := ChiMix(Acc, Value);

    { Уборка забирает протухшее только когда возраст перевалил порог. }
    ChiClaim(Trash.Freed = 0, 'уборка: забрала слишком рано');
    Trash.Tick(100);
    ChiClaim(Trash.Freed > 0, 'уборка: не забрала протухшее');
    ChiBranch(IdBuf, 'delayed-trash');
    Acc := ChiMix(Acc, Trash.Freed);

    { Много подмен подряд: каждое старое тело обязано уйти ровно раз. }
    for I := 1 to 30 do
    begin
      Slow.Add(I, False);
      Trash.Tick(200 + I * 20);
    end;
    ChiClaim(Slow.Copies = 31, 'список: число подмен не то');
    Acc := ChiMix(Acc, Slow.Copies);
  finally
    FreeAndNil(Slow);
    FreeAndNil(Trash);
  end;

  { ── То же с объектным содержимым: счёт живых обязан сойтись ── }
  Trash := TChiTrash.Create;
  Held := TChiSlowList<TChiHeld>.Create(Trash);
  try
    for I := 1 to 10 do Held.Add(TChiHeld.Create(I), False);
    ChiClaim(LiveHeld = StartHeld + 10, 'держатели: объекты не дожили');
    for I := 0 to Held.Snapshot.Count - 1 do Held.Snapshot[I].Free;
  finally
    FreeAndNil(Held);
    FreeAndNil(Trash);
  end;
  ChiClaim(LiveHeld = StartHeld, 'держатели: остались живые объекты');
  ChiBranch(IdBuf, 'object-content');

  Result := Int64(Acc and $7FFFFFFFFFFF);
end;

end.
