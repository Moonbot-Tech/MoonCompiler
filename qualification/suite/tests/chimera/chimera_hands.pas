unit chimera_hands;

{ Орган «руки»: замыкания и обобщённый словарь под блокировкой.

  Источники:

    * `MoonBot/AssetTransferU.pas` — безымянный поток получает
      замыкание, замыкание захватывает ЛОКАЛ внешней процедуры, а внутри себя
      создаёт ВТОРОЕ замыкание для отложенного вызова. Захват через два кадра;
    * `Arbitrage/Common\SafeDict.pas` — обобщённый словарь
      под блокировкой чтения-записи, доступ к сырому словарю через замыкание,
      освобождение блокировки в `finally`.

  Заменено оснасткой: сама блокировка (в библиотеке этой сборки её нет,
  поэтому здесь она своя, на атомарных операциях — как и оригинальная) и
  запуск потоков (берётся общая бригада химеры).

  Почему это отдельные формы:

    * захваченное значение переживает выход из процедуры, где было заведено.
      Компилятор обязан вынести его в кадр замыкания, а не оставить на стеке;
    * захват ПЕРЕМЕННОЙ ЦИКЛА и захват КОПИИ НА ИТЕРАЦИЮ дают разные ответы, и
      оба встречаются в живом коде. Разница — предмет проверки, а не спор о
      вкусах;
    * замыкание внутри замыкания захватывает через два кадра: внешний локал
      обязан дожить до вызова внутреннего;
    * управляемые значения в захвате — строка, интерфейс, динамический массив,
      объект — считаются по-разному, и счётчик ссылок обязан сойтись;
    * исключение ВНУТРИ замыкания, вызванного под блокировкой, обязано
      освободить блокировку: `finally` вокруг вызова — единственное, что
      стоит между дефектом и намертво вставшим словарём.

  Оракулы:

    1. значение, посчитанное замыканием, сверяется с посчитанным прямо на
       месте, без замыкания — те же действия, другая дорога;
    2. захват копии на итерацию обязан дать последовательность, захват общей
       переменной — последнее значение; оба ответа известны заранее;
    3. счётчик живых объектов и счётчик ссылок интерфейса обязаны вернуться
       к исходному после ухода всех замыканий;
    4. словарь под блокировкой сверяется с обычным словарём, набитым теми же
       ключами в том же порядке. }

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
  SysUtils, Classes, SyncObjs, Generics.Collections, chimera_body, chimera_crew;

type
  TChiThunk = reference to function: Int64;
  TChiAction = reference to procedure;

  { Блокировка чтения-записи на атомарных операциях. Много читателей либо один
    писатель; писатель ждёт, пока читатели уйдут. }
  TChiRWLock = record
    Readers: Integer;
    Writer:  Integer;
    procedure BeginRead;
    procedure EndRead;
    procedure BeginWrite;
    procedure EndWrite;
  end;

  TChiDictReader<TKey, TValue> = reference to procedure(
    const D: TDictionary<TKey, TValue>);
  TChiDictWriter<TKey, TValue> = reference to procedure(
    var D: TDictionary<TKey, TValue>);

  { Обобщённая обёртка: доступ к сырому словарю только через замыкание, и
    только под блокировкой. }
  TChiSafeDict<TKey, TValue> = class
  private
    FDict: TDictionary<TKey, TValue>;
    FRW: TChiRWLock;
  public
    constructor Create;
    destructor Destroy; override;
    procedure AddOrSetValue(const AKey: TKey; const AValue: TValue);
    function TryGetValue(const AKey: TKey; out AValue: TValue): Boolean;
    procedure Remove(const AKey: TKey);
    function Count: Integer;
    function Keys: TArray<TKey>;
    procedure ForRead(const AProc: TChiDictReader<TKey, TValue>);
    procedure ForWrite(const AProc: TChiDictWriter<TKey, TValue>);
  end;

function ChiHandsRun: Int64;

implementation

{ ═══ Блокировка ══════════════════════════════════════════════════════════ }

procedure TChiRWLock.BeginRead;
begin
  repeat
    while Writer <> 0 do TThread.Yield;
    AtomicIncrement(Readers);
    if Writer = 0 then Exit;
    { Писатель успел встать между проверкой и захватом — отступаем. }
    AtomicDecrement(Readers);
  until False;
end;

procedure TChiRWLock.EndRead;
begin
  AtomicDecrement(Readers);
end;

procedure TChiRWLock.BeginWrite;
begin
  while AtomicCmpExchange(Writer, 1, 0) <> 0 do TThread.Yield;
  while Readers > 0 do TThread.Yield;
end;

procedure TChiRWLock.EndWrite;
begin
  AtomicExchange(Writer, 0);
end;

{ ═══ Словарь ═════════════════════════════════════════════════════════════ }

constructor TChiSafeDict<TKey, TValue>.Create;
begin
  inherited Create;
  FDict := TDictionary<TKey, TValue>.Create;
  FRW := Default(TChiRWLock);
end;

destructor TChiSafeDict<TKey, TValue>.Destroy;
begin
  FRW.BeginWrite;
  try
    FreeAndNil(FDict);
  finally
    FRW.EndWrite;
  end;
  inherited Destroy;
end;

procedure TChiSafeDict<TKey, TValue>.AddOrSetValue(const AKey: TKey;
  const AValue: TValue);
begin
  FRW.BeginWrite;
  try
    FDict.AddOrSetValue(AKey, AValue);
  finally
    FRW.EndWrite;
  end;
end;

function TChiSafeDict<TKey, TValue>.TryGetValue(const AKey: TKey;
  out AValue: TValue): Boolean;
begin
  FRW.BeginRead;
  try
    Result := FDict.TryGetValue(AKey, AValue);
  finally
    FRW.EndRead;
  end;
end;

procedure TChiSafeDict<TKey, TValue>.Remove(const AKey: TKey);
begin
  FRW.BeginWrite;
  try
    FDict.Remove(AKey);
  finally
    FRW.EndWrite;
  end;
end;

function TChiSafeDict<TKey, TValue>.Count: Integer;
begin
  FRW.BeginRead;
  try
    Result := FDict.Count;
  finally
    FRW.EndRead;
  end;
end;

function TChiSafeDict<TKey, TValue>.Keys: TArray<TKey>;
var
  I: Integer;
  K: TKey;
begin
  FRW.BeginRead;
  try
    SetLength(Result, FDict.Count);
    I := 0;
    for K in FDict.Keys do
    begin
      Result[I] := K;
      Inc(I);
    end;
  finally
    FRW.EndRead;
  end;
end;

procedure TChiSafeDict<TKey, TValue>.ForRead(
  const AProc: TChiDictReader<TKey, TValue>);
begin
  FRW.BeginRead;
  try
    AProc(FDict);
  finally
    FRW.EndRead;
  end;
end;

procedure TChiSafeDict<TKey, TValue>.ForWrite(
  const AProc: TChiDictWriter<TKey, TValue>);
begin
  FRW.BeginWrite;
  try
    AProc(FDict);
  finally
    FRW.EndWrite;
  end;
end;

{ ═══ Жильцы захвата ══════════════════════════════════════════════════════ }

type
  IChiToken = interface
    ['{4D5A0002-0000-0000-0000-00004348490F}']
    function Value: Int64;
  end;

  TChiToken = class(TInterfacedObject, IChiToken)
  private
    FValue: Int64;
  public
    constructor Create(AValue: Int64);
    destructor Destroy; override;
    function Value: Int64;
  end;

  TChiPayload = class
    Data: Int64;
    constructor Create(AData: Int64);
    destructor Destroy; override;
  end;

var
  LiveTokens: Integer;
  LivePayloads: Integer;

constructor TChiToken.Create(AValue: Int64);
begin
  inherited Create;
  FValue := AValue;
  AtomicIncrement(LiveTokens);
end;

destructor TChiToken.Destroy;
begin
  AtomicDecrement(LiveTokens);
  inherited Destroy;
end;

function TChiToken.Value: Int64;
begin
  Result := FValue;
end;

constructor TChiPayload.Create(AData: Int64);
begin
  inherited Create;
  Data := AData;
  AtomicIncrement(LivePayloads);
end;

destructor TChiPayload.Destroy;
begin
  AtomicDecrement(LivePayloads);
  inherited Destroy;
end;

{ ═══ Захваты ═════════════════════════════════════════════════════════════ }

const
  IdClos1 = 'CHI-MB-CLOS-001';
  IdClos2 = 'CHI-MB-CLOS-002';
  IdClos3 = 'CHI-MB-CLOS-003';
  IdClos4 = 'CHI-MB-CLOS-004';
  IdDict  = 'CHI-ARB-DICT-001';

{ Замыкание, пережившее выход из процедуры, где заведён захваченный локал. }
function MakeEscaped(Base: Int64): TChiThunk;
var
  Local: Int64;
  Text: string;
begin
  Local := Base * 3 + 1;
  Text := IntToStr(Base);
  Result :=
    function: Int64
    begin
      Result := Local + Length(Text);
    end;
end;

{ Замыкание внутри замыкания: внутреннее видит локал ВНЕШНЕЙ процедуры через
  два кадра. Форма из живого кода, где безымянный поток ставит отложенный
  вызов.

  Отложенное замыкание кладётся в поле ОБЪЕКТА, как в живом коде: очередь
  отложенных вызовов переживает и кадр, и саму процедуру. Локальная запись
  здесь не годится — замыкание писало бы в захваченную копию, а вызыватель
  получил бы пустое поле. }
type
  TChiNest = class
    Middle: TChiThunk;
    Inner:  TChiThunk;
  end;

function MakeNested(Base: Int64): TChiNest;
var
  Outer: Int64;
  Slot: TChiNest;
begin
  Outer := Base * 10;
  Slot := TChiNest.Create;
  Slot.Middle :=
    function: Int64
    var
      Mid: Int64;
    begin
      Mid := Outer + 7;
      Slot.Inner :=
        function: Int64
        begin
          { Через два кадра: и внешний локал, и локал среднего замыкания. }
          Result := Outer + Mid;
        end;
      Result := Mid;
    end;
  Result := Slot;
end;

{ Захват управляемых жильцов: строка, интерфейс, объект, массив. }
function MakeManaged(const S: string; const T: IChiToken; P: TChiPayload;
  const A: TArray<Int64>): TChiThunk;
begin
  Result :=
    function: Int64
    var
      I: Integer;
    begin
      Result := Length(S) + T.Value + P.Data;
      for I := 0 to High(A) do Result := Result + A[I];
    end;
end;

{ Копия на итерацию: значение приходит параметром, поэтому каждое замыкание
  получает своё. }
function CaptureCopy(Value: Int64): TChiThunk;
begin
  Result :=
    function: Int64
    begin
      Result := Value;
    end;
end;

var
  SeenLow:    Integer = 0;   { сколько раз читатель застал запись в ходу }
  WriterSpin: Integer = 0;   { работа писателя между присваиваниями }
  WriterDone: Integer = 0;

type
  { Имя нужно не для красоты: безымянный тип ссылки прямо в объявлении
    переменной строгий компилятор не принимает. }
  TChiThreeArg = reference to procedure(A: Int64; const S: string;
    const T: IChiToken);

function ChiHandsRun: Int64;
var
  Acc: UInt64;
  Thunk: TChiThunk;
  Nest: TChiNest;
  NoArgs: TChiAction;
  WithArgs: TChiThreeArg;
  Thunks: array of TChiThunk;
  I, Expect, Got: Integer;
  Token: IChiToken;
  Payload: TChiPayload;
  Arr: TArray<Int64>;
  Shared: Int64;
  Dict: TChiSafeDict<AnsiString, Int64>;
  Plain: TDictionary<AnsiString, Int64>;
  Keys: TArray<AnsiString>;
  Value: Int64;
  Raised: Boolean;
  Total: Int64;
  StartTokens, StartPayloads: Integer;
begin
  ChiCovered(IdClos1);
  ChiCovered(IdClos2);
  ChiCovered(IdClos3);
  ChiCovered(IdClos4);
  ChiCovered(IdDict);
  Acc := ChiOffset;
  StartTokens := LiveTokens;
  StartPayloads := LivePayloads;

  { ── Захват локала, пережившего выход ── }
  Thunk := MakeEscaped(5);
  ChiClaim(Thunk() = 5 * 3 + 1 + Length(IntToStr(5)),
    'руки: захваченный локал не пережил выход');
  ChiBranch(IdClos4, 'escaped');
  Acc := ChiMix(Acc, Thunk());

  { ── Замыкание внутри замыкания ── }
  Nest := MakeNested(4);
  try
    ChiClaim(Nest.Middle() = 4 * 10 + 7, 'руки: среднее замыкание дало не то');
    ChiClaim(Assigned(Nest.Inner), 'руки: внутреннее замыкание не создано');
    if Assigned(Nest.Inner) then
    begin
      ChiClaim(Nest.Inner() = 4 * 10 + (4 * 10 + 7),
        'руки: захват через два кадра дал не то');
      ChiBranch(IdClos1, 'nested-capture');
      Acc := ChiMix(Acc, Nest.Inner());
    end;
  finally
    Nest.Middle := nil;
    Nest.Inner := nil;
    FreeAndNil(Nest);
  end;

  { ── Захват переменной цикла против копии на итерацию ── }
  SetLength(Thunks, 8);
  Shared := 0;
  for I := 0 to 7 do
  begin
    Shared := I;
    { Общая переменная: все замыкания увидят ПОСЛЕДНЕЕ значение. }
    Thunks[I] :=
      function: Int64
      begin
        Result := Shared;
      end;
  end;
  Got := 0;
  for I := 0 to 7 do Got := Got + Integer(Thunks[I]());
  ChiClaim(Got = 8 * 7, 'руки: общая переменная захвачена не как общая');
  ChiBranch(IdClos3, 'shared-variable');
  Acc := ChiMix(Acc, Got);

  for I := 0 to 7 do
  begin
    { Копия на итерацию: каждое замыкание видит своё значение. }
    Thunks[I] := CaptureCopy(I);
  end;
  Got := 0;
  Expect := 0;
  for I := 0 to 7 do
  begin
    Got := Got + Integer(Thunks[I]());
    Expect := Expect + I;
  end;
  ChiClaim(Got = Expect, 'руки: копия на итерацию захвачена не как копия');
  ChiBranch(IdClos3, 'per-iteration-copy');
  Acc := ChiMix(Acc, Got);

  { ── Захват управляемых жильцов ── }
  Token := TChiToken.Create(100);
  Payload := TChiPayload.Create(200);
  try
    SetLength(Arr, 4);
    for I := 0 to 3 do Arr[I] := I + 1;
    Thunk := MakeManaged('abcde', Token, Payload, Arr);
    ChiClaim(Thunk() = 5 + 100 + 200 + (1 + 2 + 3 + 4),
      'руки: захват управляемых дал не то');
    ChiBranch(IdClos2, 'managed-capture');
    Acc := ChiMix(Acc, Thunk());

    { Пока замыкание живо, жильцы обязаны быть живы. }
    ChiClaim(LiveTokens > StartTokens, 'руки: интерфейс умер под замыканием');
    Thunk := nil;
  finally
    FreeAndNil(Payload);
  end;
  Token := nil;
  ChiClaim(LiveTokens = StartTokens, 'руки: интерфейс не умер после замыкания');
  ChiClaim(LivePayloads = StartPayloads, 'руки: объект не убран');
  ChiBranch(IdClos2, 'lifetime-balanced');

  { ── Замыкание без параметров и с параметрами разных родов ── }
  Total := 0;
  NoArgs :=
    procedure
    begin
      Inc(Total);
    end;
  NoArgs();
  WithArgs :=
    procedure(A: Int64; const S: string; const T: IChiToken)
    begin
      Total := Total + A + Length(S);
      if Assigned(T) then Total := Total + T.Value;
    end;
  WithArgs(10, 'xyz', nil);
  ChiClaim(Total = 1 + 10 + 3, 'руки: замыкания с параметрами дали не то');
  ChiBranch(IdClos2, 'params');
  Acc := ChiMix(Acc, Total);

  { ── Словарь под блокировкой ── }
  Dict := TChiSafeDict<AnsiString, Int64>.Create;
  Plain := TDictionary<AnsiString, Int64>.Create;
  try
    for I := 0 to 63 do
    begin
      Dict.AddOrSetValue(AnsiString('k' + IntToStr(I)), I * I);
      Plain.AddOrSetValue(AnsiString('k' + IntToStr(I)), I * I);
    end;
    ChiClaim(Dict.Count = Plain.Count, 'словарь: счёт разошёлся с обычным');
    for I := 0 to 63 do
    begin
      ChiClaim(Dict.TryGetValue(AnsiString('k' + IntToStr(I)), Value),
        'словарь: ключ не найден');
      ChiClaim(Value = I * I, 'словарь: значение не то');
    end;
    ChiBranch(IdDict, 'add-get');

    Dict.Remove('k7');
    ChiClaim(not Dict.TryGetValue('k7', Value), 'словарь: удалённый ключ найден');
    ChiClaim(Dict.Count = 63, 'словарь: счёт после удаления не тот');
    ChiBranch(IdDict, 'remove');

    Keys := Dict.Keys;
    ChiClaim(Length(Keys) = 63, 'словарь: список ключей не той длины');
    ChiBranch(IdDict, 'keys');

    { Доступ к сырому словарю через замыкание — под блокировкой. }
    Total := 0;
    Dict.ForRead(
      procedure(const D: TDictionary<AnsiString, Int64>)
      var
        P: TPair<AnsiString, Int64>;
      begin
        for P in D do Total := Total + P.Value;
      end);
    Value := 0;
    for I := 0 to 63 do
      if I <> 7 then Value := Value + I * I;
    ChiClaim(Total = Value, 'словарь: обход под чтением дал не ту сумму');
    ChiBranch(IdDict, 'for-read');
    Acc := ChiMix(Acc, Total);

    Dict.ForWrite(
      procedure(var D: TDictionary<AnsiString, Int64>)
      begin
        D.AddOrSetValue('added', 12345);
      end);
    ChiClaim(Dict.TryGetValue('added', Value) and (Value = 12345),
      'словарь: запись под замыканием не прошла');
    ChiBranch(IdDict, 'for-write');

    { Исключение ВНУТРИ замыкания обязано освободить блокировку: иначе
      следующий же вызов встанет намертво. }
    Raised := False;
    try
      Dict.ForWrite(
        procedure(var D: TDictionary<AnsiString, Int64>)
        begin
          D.AddOrSetValue('before-throw', 1);
          raise EAbort.Create('внутри замыкания');
        end);
    except
      on E: EAbort do Raised := True;
    end;
    ChiClaim(Raised, 'словарь: исключение из замыкания не вышло наружу');
    ChiClaim(Dict.TryGetValue('before-throw', Value),
      'словарь: сделанное до броска пропало');
    { Если блокировка не освободилась, этот вызов не вернётся. }
    ChiClaim(Dict.Count > 0, 'словарь: блокировка не освобождена после броска');
    ChiBranch(IdDict, 'exception-releases-lock');

    { Многопоточно: читатели и один писатель. Утверждение только то, что верно
      при любом расписании — прочитанное значение обязано быть одним из
      записанных, а не мусором. }
    Dict.AddOrSetValue('shared', 0);
    SeenLow := 0;
    WriterSpin := 0;
    WriterDone := 0;
    { Читатели крутятся, ПОКА пишет писатель, а не заданное число раз: иначе
      писатель успевает закончить до их старта, и все видят последнее
      значение — проверка читателей тогда ничего не проверяет. Оборотов не
      больше предела, чтобы поздний читатель не крутился впустую. }
    ChiParallel(16, ChiThreadCount,
      procedure(Index: Integer)
      var
        K: Integer;
        V: Int64;
        Spins: Integer;
      begin
        if Index = 0 then
        begin
          for K := 1 to 200 do
          begin
            Dict.AddOrSetValue('shared', K);
            for var Pause := 1 to 400 do AtomicIncrement(WriterSpin);
          end;
          AtomicExchange(WriterDone, 1);
        end
        else
        begin
          Spins := 0;
          while (WriterDone = 0) and (Spins < 200000) do
          begin
            Inc(Spins);
            if Dict.TryGetValue('shared', V) then
            begin
              ChiClaim((V >= 0) and (V <= 200),
                'словарь: читатель увидел значение вне записанного');
              if V < 200 then AtomicIncrement(SeenLow);
            end;
          end;
        end;
      end);
    ChiClaim(SeenLow > 0,
      'словарь: читатели ни разу не застали запись в ходу — пересечения не было');
    ChiBranch(IdDict, 'threaded-readers');
    ChiBranch(IdDict, 'readers-saw-progress');
  finally
    FreeAndNil(Plain);
    FreeAndNil(Dict);
  end;

  { ── Замыкание уезжает в поток бригады ── }
  Shared := 0;
  ChiParallel(32, ChiThreadCount,
    procedure(Index: Integer)
    var
      Local: Int64;
      Deferred: TChiThunk;
    begin
      Local := Index * 2;
      { Внутри работника рождается ещё одно замыкание — форма отложенного
        вызова из живого кода. }
      Deferred :=
        function: Int64
        begin
          Result := Local + 1;
        end;
      AtomicIncrement(Shared, Deferred());
    end);
  Value := 0;
  for I := 0 to 31 do Value := Value + I * 2 + 1;
  ChiClaim(Shared = Value, 'руки: сумма из потоков не сошлась');
  ChiBranch(IdClos1, 'thread-capture');
  Acc := ChiMix(Acc, Shared);

  ChiClaim(LiveTokens = StartTokens, 'руки: остались живые интерфейсы');
  ChiClaim(LivePayloads = StartPayloads, 'руки: остались живые объекты');

  Result := Int64(Acc and $7FFFFFFFFFFF);
end;

end.
