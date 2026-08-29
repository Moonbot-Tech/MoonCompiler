unit chimera_ring;

{ Орган «кольцо»: передача сделок от потока сокета к потоку расчёта.

  Это самое лёгкое отношение к блокировкам во всём MoonBot, и оно намеренное.
  Устройство ровно такое:

    * продюсер (поток биржевого сокета) кладёт сделку в слот и ТОЛЬКО ПОТОМ
      двигает индекс записи — публикация задним числом;
    * продюсер имеет право дописать количество в УЖЕ ЗАПИСАННЫЙ слот: если
      предыдущая сделка того же направления, по близкой цене и свежее пятой
      доли секунды, она поглощает новую. Право на это он выводит из индекса
      чтения, который двигает ЧУЖОЙ поток;
    * потребитель снимает снимок обоих индексов, разворачивает кольцо в
      сплошную память двумя `Move` (или одним, если разрыва нет), сшивает
      партию с историей — и двигает индекс чтения В САМОМ КОНЦЕ;
    * рядом, без всякой атомарности, живёт «запомнить наибольшее» из чужого
      потока — чтение, изменение и запись поверх общего поля.

  Ни одной блокировки. Всё держится на том, что писатель один и читатель один,
  и на порядке двух присваиваний.

  Стык отдельно хорош: точка сшивки ищется ДВОИЧНЫМ ПОИСКОМ по
  компаратору-замыканию, который возвращает «равно» при расхождении времён
  меньше миллисекунды. Такой компаратор НЕТРАНЗИТИВЕН: из «a равно b» и «b
  равно c» не следует «a равно c». Двоичный поиск по нетранзитивному
  компаратору вправе вернуть любой элемент плато, поэтому найденная точка —
  не утверждение, а наблюдение: она сверяется между сборками, а утверждения
  строятся только на том, что верно при любой точке.

  Отсюда две ленты вместо одной:

    * РЕДКАЯ — шаг времени заведомо больше допуска стыка, значит плато пустое,
      стык не отбрасывает ничего и история предсказуема. На ней работает
      полная побитовая сверка с независимым оракулом;
    * ПЛОТНАЯ — шаг сравним с допуском, стык работает по-настоящему. Здесь
      проверяются только утверждения, верные при любой точке сшивки, а сам
      итог сверяется между сборками.

  Третий прогон — многопоточный: продюсер и потребитель одного рынка работают
  одновременно. Там итог зависит от того, кто когда успел, поэтому проверяется
  только то, что верно при ЛЮБОМ порядке. Причём проверяется честно: продюсер
  вправе дописать количество в слот, который потребитель уже скопировал себе,
  и это количество пропадёт. Такова цена отказа от блокировок, и она заплачена
  сознательно — значит утверждение обязано её учитывать, а не делать вид, что
  гонки нет. }

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
  SysUtils, Classes, Math, Generics.Defaults, Generics.Collections,
  chimera_body, chimera_crew;

const
  { Ёмкость кольца. Заметно меньше живой — чтобы заворот был частым событием,
    а не редкой экзотикой. }
  ChiRingSize = 256;

  { Порог склейки по цене: у рынка это шаг цены на чарте. }
  ChiPriceStep = 0.0009;

  { Допуск стыка: сделки, разошедшиеся меньше чем на это, считаются одной и
    той же. Ровно то, чем живой компаратор объявляет «равно». }
  ChiJoinEps = 1.0 / (86400.0 * 1000.0);

type
  TChiMarket = record
    Ring:      array [0 .. ChiRingSize - 1] of TChiTrade;
    WritePos:  Integer;
    ReadPos:   Integer;
    Hist:      TChiTape;
    HistCount: Integer;

    { Перепись: всё, что вошло, обязано найтись в одном из исходов. }
    Fed:        Int64;   { подано продюсеру }
    Merged:     Int64;   { поглощено предыдущей сделкой }
    Dropped:    Int64;   { отброшено переполнением кольца }
    Spliced:    Int64;   { отброшено стыком как не новее истории }
    Stored:     Int64;   { занято слотов кольца }
    Drains:     Int64;   { сколько раз дренаж дал непустую партию }
    FedQty:     Double;
    MergedQty:  Double;
    DroppedQty: Double;
    SplicedQty: Double;

    { Поле, которое трогают оба потока без всякой атомарности. }
    MaxSeen:   Double;

    Done:      Boolean;  { продюсер закончил; читает потребитель }
  end;
  PChiMarket = ^TChiMarket;

  { Расписание дренажа. Вход задачи, а не деталь реализации: обе дороги —
    кольцевая и оракул — обязаны видеть одно и то же расписание, иначе
    сравнивать нечего. }
  TChiSchedule = record
    Src:   TChiSource;
    Since: Integer;
    Every: Integer;
    function Tick: Boolean;
  end;

function ChiSchedule: TChiSchedule;

{ Редкая лента: шаг времени заведомо больше допуска стыка. }
function ChiMakeSparseTape(Count: Integer; ASeed: UInt64): TChiTape;
{ Плотная лента: шаг сравним с допуском, стык работает по-настоящему. }
function ChiMakeDenseTape(Count: Integer; ASeed: UInt64): TChiTape;

procedure ChiMarketInit(out M: TChiMarket);

{ Продюсер и потребитель — ровно в той форме, в какой они живут в боте. }
procedure ChiRingFeed(var M: TChiMarket; const T: TChiTrade);
function ChiRingDrain(var M: TChiMarket): Integer;

function ChiRingRun: Int64;

implementation

function TChiSchedule.Tick: Boolean;
begin
  Inc(Since);
  Result := Since >= Every;
  if Result then
  begin
    Since := 0;
    { Реже сотни сделок кольцо на двести пятьдесят шесть слотов переполнилось
      бы; чаще — заворот не успевал бы случиться. }
    Every := 40 + Src.NextBelow(60);
  end;
end;

function ChiSchedule: TChiSchedule;
begin
  Result.Src := ChiSource(777);
  Result.Since := 0;
  Result.Every := 40 + Result.Src.NextBelow(60);
end;

function MakeTape(Count: Integer; ASeed: UInt64;
  StepLo, StepHi: Double; Echoes: Boolean): TChiTape;
var
  Src: TChiSource;
  I, Echo: Integer;
  T, Price, Qty: Double;
begin
  Result := nil;
  SetLength(Result, Count);
  Src := ChiSource(ASeed);
  T := 45000.0;
  Price := 1.0;
  Echo := 0;
  for I := 0 to Count - 1 do
  begin
    { Повторные принты: биржа изредка присылает пачку сделок с одной и той же
      отметкой времени. Ради них стык и написан — без них его ветка мертва, а
      в бою именно она защищает историю от задвоения. Цены в пачке разные,
      иначе продюсер поглотил бы их ещё в кольце. }
    if Echoes and (Echo = 0) and (Src.NextBelow(25) = 0) then Echo := 4;
    if Echo > 0 then
    begin
      Dec(Echo);
      Price := Price * 1.005;
      Result[I].Time := T;
      Result[I].Price := Price;
      Qty := 1 + Src.NextBelow(64);
      if Src.NextBelow(2) = 0 then Qty := -Qty;
      Result[I].Qty := Qty;
      Continue;
    end;

    T := T + (StepLo + Src.NextUnit * (StepHi - StepLo))
             / (ChiSecsPerDay * 1000.0);
    Price := Price * (1.0 + (Src.NextUnit - 0.5) * 0.0016);
    { Количества целые: сумма целых в одинарной точности точна, пока не
      перевалила за два в двадцать четвёртой, — значит перепись объёмов можно
      сверять ТОЧНО, а не с допуском. }
    Qty := 1 + Src.NextBelow(64);
    if Src.NextBelow(2) = 0 then Qty := -Qty;
    Result[I].Time := T;
    Result[I].Price := Price;
    Result[I].Qty := Qty;
  end;
end;

function ChiMakeSparseTape(Count: Integer; ASeed: UInt64): TChiTape;
begin
  { Нижняя граница шага — полторы миллисекунды, допуск стыка — одна. }
  Result := MakeTape(Count, ASeed, 1.5, 6.0, False);
end;

function ChiMakeDenseTape(Count: Integer; ASeed: UInt64): TChiTape;
begin
  Result := MakeTape(Count, ASeed, 0.0, 4.0, True);
end;

procedure ChiMarketInit(out M: TChiMarket);
begin
  M := Default(TChiMarket);
  SetLength(M.Hist, 0);
end;

{ ═══ Продюсер ════════════════════════════════════════════════════════════

  Слот заполняется ПЕРЕД публикацией индекса — иначе потребитель увидит
  индекс, за которым ещё нет данных. Право дописать в уже занятый слот
  выводится из числа непрочитанного, а индекс чтения двигает чужой поток. }

procedure ChiRingFeed(var M: TChiMarket; const T: TChiTrade);
var
  W, NextW, Cnt, P1, P2: Integer;
begin
  { Чтение, изменение и запись поверх общего поля — без атомарности. }
  if T.Price > M.MaxSeen then M.MaxSeen := T.Price;

  Inc(M.Fed);
  M.FedQty := M.FedQty + Abs(T.Qty);

  W := M.WritePos;
  NextW := (W + 1) mod ChiRingSize;
  if NextW = M.ReadPos then
  begin
    { Кольцо полно — сделка теряется. В бою это видно как пропавший объём. }
    Inc(M.Dropped);
    M.DroppedQty := M.DroppedQty + Abs(T.Qty);
    Exit;
  end;

  Cnt := (W - M.ReadPos + ChiRingSize) mod ChiRingSize;
  P1 := (W - 1 + ChiRingSize) mod ChiRingSize;
  P2 := (W - 2 + ChiRingSize) mod ChiRingSize;

  if (Cnt >= 1) and M.Ring[P1].SameDirection(T)
     and (Abs(M.Ring[P1].Price - T.Price) < ChiPriceStep)
     and (Abs(M.Ring[P1].Time - T.Time) < ChiSameTime) then
  begin
    M.Ring[P1].Qty := M.Ring[P1].Qty + T.Qty;
    Inc(M.Merged);
    M.MergedQty := M.MergedQty + Abs(T.Qty);
  end
  else if (Cnt >= 2) and M.Ring[P2].SameDirection(T)
          and (Abs(M.Ring[P2].Price - T.Price) < ChiPriceStep)
          and (Abs(M.Ring[P2].Time - T.Time) < ChiSameTime) then
  begin
    M.Ring[P2].Qty := M.Ring[P2].Qty + T.Qty;
    Inc(M.Merged);
    M.MergedQty := M.MergedQty + Abs(T.Qty);
  end
  else
  begin
    M.Ring[W] := T;
    Inc(M.Stored);
    { Публикация. Всё, что выше, обязано быть видно раньше этой строки. }
    M.WritePos := NextW;
  end;
end;

{ ═══ Стык ════════════════════════════════════════════════════════════════ }

function SplicePoint(const Batch: TChiTape; K: Integer;
  const Probe: TChiTrade): Integer;
var
  Comparer: IComparer<TChiTrade>;
  Found: Boolean;
begin
  { Компаратор-замыкание. Возвращает «равно» при расхождении меньше
    миллисекунды — то есть НЕТРАНЗИТИВЕН по построению. }
  Comparer := TDelegatedComparer<TChiTrade>.Create(
    function(const Left, Right: TChiTrade): Integer
    begin
      if Abs(Left.Time - Right.Time) < ChiJoinEps then
        Result := 0
      else
        Result := Sign(Left.Time - Right.Time);
    end);

  Result := -1;
  Found := TArray.BinarySearch<TChiTrade>(Batch, Probe, Result, Comparer, 0, K);
  if Found and (Result > 0) then
    while (Result < K) and (Batch[Result].Time <= Probe.Time + ChiJoinEps) do
      Inc(Result);
  if Result < 0 then Result := 0;
end;

{ ═══ Потребитель ═════════════════════════════════════════════════════════

  Снимок обоих индексов берётся один раз; всё дальнейшее опирается только на
  снимок. Индекс чтения двигается последней строкой — до тех пор продюсер
  считает партию непрочитанной и вправе дописывать в её слоты. }

function ChiRingDrain(var M: TChiMarket): Integer;
var
  LW, LR, K, First, J, Splice: Integer;
  Batch: TChiTape;
begin
  LW := M.WritePos;
  LR := M.ReadPos;
  K := (LW - LR + ChiRingSize) mod ChiRingSize;
  if K = 0 then Exit(0);

  SetLength(Batch, K);
  if LR < LW then
    Move(M.Ring[LR], Batch[0], K * SizeOf(TChiTrade))
  else
  begin
    { Разрыв: партия лежит двумя кусками — хвост кольца и его начало. }
    First := ChiRingSize - LR;
    if K <= First then
      Move(M.Ring[LR], Batch[0], K * SizeOf(TChiTrade))
    else
    begin
      Move(M.Ring[LR], Batch[0], First * SizeOf(TChiTrade));
      Move(M.Ring[0], Batch[First], (K - First) * SizeOf(TChiTrade));
    end;
  end;

  if M.HistCount > 0 then
    Splice := SplicePoint(Batch, K, M.Hist[M.HistCount - 1])
  else
    Splice := 0;

  for J := 0 to Splice - 1 do
  begin
    Inc(M.Spliced);
    M.SplicedQty := M.SplicedQty + Abs(Batch[J].Qty);
  end;

  if M.HistCount + (K - Splice) > Length(M.Hist) then
    SetLength(M.Hist, (M.HistCount + K) * 2 + 64);
  for J := Splice to K - 1 do
  begin
    M.Hist[M.HistCount] := Batch[J];
    Inc(M.HistCount);
  end;

  Inc(M.Drains);
  { Публикация прочитанного — последним действием. }
  M.ReadPos := (LR + K) mod ChiRingSize;
  Result := K;
end;

{ ═══ Оракул: то же поглощение, но без кольца вообще ══════════════════════

  Ни индексов, ни заворота, ни разрыва, ни двоичного поиска: сделки
  складываются в конец обычного массива, поглощение смотрит на две последние.
  Единственное, что оракул обязан повторить, — ГРАНИЦЫ ДРЕНАЖА: после
  дренажа прежние записи прочитаны, и поглощать в них уже нельзя. Это не
  деталь кольца, а правило задачи, и расписание для обеих дорог одно. }

function FlatHistory(const Tape: TChiTape; out Merged, Stored: Int64): TChiTape;
var
  I, N, Fresh: Integer;
  Plan: TChiSchedule;
  T: TChiTrade;
  Hit: Boolean;
begin
  Result := nil;
  SetLength(Result, Length(Tape));
  N := 0;
  Fresh := 0;   { сколько последних записей ещё не прочитано }
  Merged := 0;
  Stored := 0;
  Plan := ChiSchedule;
  for I := 0 to High(Tape) do
  begin
    T := Tape[I];
    Hit := False;

    if (Fresh >= 1) and Result[N - 1].SameDirection(T)
       and (Abs(Result[N - 1].Price - T.Price) < ChiPriceStep)
       and (Abs(Result[N - 1].Time - T.Time) < ChiSameTime) then
    begin
      Result[N - 1].Qty := Result[N - 1].Qty + T.Qty;
      Hit := True;
    end
    else if (Fresh >= 2) and Result[N - 2].SameDirection(T)
            and (Abs(Result[N - 2].Price - T.Price) < ChiPriceStep)
            and (Abs(Result[N - 2].Time - T.Time) < ChiSameTime) then
    begin
      Result[N - 2].Qty := Result[N - 2].Qty + T.Qty;
      Hit := True;
    end;

    if Hit then
      Inc(Merged)
    else
    begin
      Result[N] := T;
      Inc(N);
      Inc(Fresh);
      Inc(Stored);
    end;

    if Plan.Tick then Fresh := 0;
  end;
  SetLength(Result, N);
end;

{ ═══ Свёртка ═════════════════════════════════════════════════════════════ }

function HistDigest(const Hist: TChiTape; Count: Integer): UInt64;
var
  I: Integer;
begin
  Result := ChiOffset;
  for I := 0 to Count - 1 do
  begin
    Result := ChiMix(Result, PInt64(@Hist[I].Time)^);
    Result := ChiMix(Result, PInteger(@Hist[I].Price)^);
    Result := ChiMix(Result, PInteger(@Hist[I].Qty)^);
  end;
end;

function HistQty(const Hist: TChiTape; Count: Integer): Double;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to Count - 1 do
    Result := Result + Abs(Hist[I].Qty);
end;

function RingQty(const M: TChiMarket): Double;
var
  K, J, Idx: Integer;
begin
  Result := 0;
  K := (M.WritePos - M.ReadPos + ChiRingSize) mod ChiRingSize;
  for J := 0 to K - 1 do
  begin
    Idx := (M.ReadPos + J) mod ChiRingSize;
    Result := Result + Abs(M.Ring[Idx].Qty);
  end;
end;

function TimeGoesForward(const Hist: TChiTape; Count: Integer): Boolean;
var
  I: Integer;
begin
  Result := True;
  for I := 1 to Count - 1 do
    if Hist[I].Time < Hist[I - 1].Time then Exit(False);
end;

{ ═══ Прогон 1: один поток, расписание задано сидом ═══════════════════════ }

function RunDeterministic(const Tape: TChiTape; out M: TChiMarket): UInt64;
var
  Plan: TChiSchedule;
  I: Integer;
begin
  ChiMarketInit(M);
  Plan := ChiSchedule;
  for I := 0 to High(Tape) do
  begin
    ChiRingFeed(M, Tape[I]);
    if Plan.Tick then ChiRingDrain(M);
  end;
  ChiRingDrain(M);
  Result := HistDigest(M.Hist, M.HistCount);
end;

procedure CheckCensus(const M: TChiMarket; Fed: Integer; const Who: string);
begin
  ChiClaim(M.Fed = Fed, Who + ': подано не столько, сколько в ленте');
  ChiClaim(M.Merged + M.Dropped + M.Stored = M.Fed,
    Who + ': перепись исходов не сошлась');
  ChiClaim(M.Dropped = 0,
    Who + ': расписание дренажа переполнило кольцо');
  ChiClaim(M.WritePos = M.ReadPos, Who + ': осталось непрочитанное');
  ChiClaim(M.Drains > 0, Who + ': дренаж ни разу не сработал');
  { Заворот обязан был случиться, иначе форма разрыва не проверена. }
  ChiClaim(M.Stored > ChiRingSize, Who + ': заворота не было');
  ChiClaim(TimeGoesForward(M.Hist, M.HistCount),
    Who + ': время в истории пошло назад');
  ChiClaim(HistQty(M.Hist, M.HistCount) + M.SplicedQty = M.FedQty,
    Who + ': объём не сошёлся');
end;

{ ═══ Прогон 2: продюсер и потребитель одного рынка одновременно ══════════ }

procedure RunThreaded(const Tape: TChiTape; Markets: Integer);
var
  Books: array of TChiMarket;
  I: Integer;
  Kept: Double;
begin
  SetLength(Books, Markets);
  for I := 0 to Markets - 1 do ChiMarketInit(Books[I]);

  { Работа раздаётся чередованием: чётный номер — продюсер рынка, нечётный —
    его же потребитель. При раздаче общим счётчиком они попадают в разные
    потоки почти одновременно, и гонка получается настоящая. }
  ChiParallel(Markets * 2, ChiThreadCount,
    procedure(Index: Integer)
    var
      Book: PChiMarket;
      K, Spins: Integer;
    begin
      Book := @Books[Index shr 1];
      if (Index and 1) = 0 then
      begin
        for K := 0 to High(Tape) do
        begin
          ChiRingFeed(Book^, Tape[K]);
          { Уступка после пачки. Без неё продюсер заливает кольцо быстрее,
            чем потребитель успевает его разобрать, — тогда почти всё уходит
            в переполнение, и совместной работы, ради которой прогон и
            заведён, просто не происходит. В бою эту паузу даёт сокет. }
          if (K and 63) = 63 then TThread.Yield;
        end;
        Book^.Done := True;
      end
      else
      begin
        Spins := 0;
        while not Book^.Done do
        begin
          ChiRingDrain(Book^);
          Inc(Spins);
          { Потолок оборотов: зависший тест хуже упавшего. }
          if Spins > 200000000 then
          begin
            ChiClaim(False, 'кольцо: потребитель не дождался продюсера');
            Break;
          end;
        end;
        { Продюсер мог опубликовать последнее уже после проверки флага. }
        ChiRingDrain(Book^);
        ChiRingDrain(Book^);
      end;
    end);

  for I := 0 to Markets - 1 do
  begin
    { Счётчики ведёт только продюсер — они обязаны сходиться точно. }
    ChiClaim(Books[I].Fed = Length(Tape),
      'кольцо в потоках: подано не столько, сколько в ленте');
    ChiClaim(Books[I].Merged + Books[I].Dropped + Books[I].Stored
             = Books[I].Fed,
      'кольцо в потоках: перепись исходов не сошлась');

    { Объём. Точного равенства здесь быть НЕ МОЖЕТ, и это не дефект:
      продюсер вправе дописать количество в слот, который потребитель уже
      скопировал себе, — тогда дописанное пропадает. Потерять больше, чем
      было поглощено, невозможно, поэтому утверждение двустороннее. }
    Kept := HistQty(Books[I].Hist, Books[I].HistCount) + RingQty(Books[I])
            + Books[I].DroppedQty + Books[I].SplicedQty;
    ChiClaim(Kept <= Books[I].FedQty,
      'кольцо в потоках: объёма стало больше, чем подано');
    ChiClaim(Kept >= Books[I].FedQty - Books[I].MergedQty,
      'кольцо в потоках: потеряно больше, чем было поглощено');

    { Кольцо после конца работы пусто: потребитель дренировал уже после того,
      как увидел флаг готовности. }
    ChiClaim(Books[I].WritePos = Books[I].ReadPos,
      'кольцо в потоках: осталось непрочитанное после конца работы');
    ChiClaim(Books[I].HistCount > 0, 'кольцо в потоках: пустая история');
    ChiClaim(TimeGoesForward(Books[I].Hist, Books[I].HistCount),
      'кольцо в потоках: время в истории пошло назад');
    ChiClaim(Books[I].MaxSeen > 0, 'кольцо в потоках: наибольшее не заметили');
  end;
end;

{ ═══ Орган ═══════════════════════════════════════════════════════════════ }

function ChiRingRun: Int64;
var
  Sparse, Dense, Flat: TChiTape;
  Ms, Md: TChiMarket;
  DigSparse, DigDense: UInt64;
  FlatMerged, FlatStored: Int64;
  I: Integer;
  Bad: Boolean;
begin
  Sparse := ChiMakeSparseTape(9000, 20260831);
  Dense := ChiMakeDenseTape(9000, 20260901);

  { ── Редкая лента: стык не отбрасывает ничего, история предсказуема ── }
  DigSparse := RunDeterministic(Sparse, Ms);
  CheckCensus(Ms, Length(Sparse), 'кольцо редкое');
  ChiClaim(Ms.Spliced = 0,
    'кольцо редкое: стык что-то отбросил — лента недостаточно редкая');

  Flat := FlatHistory(Sparse, FlatMerged, FlatStored);
  ChiClaim(FlatMerged = Ms.Merged, 'кольцо: поглощений разное число');
  ChiClaim(FlatStored = Ms.Stored, 'кольцо: занятых слотов разное число');
  ChiClaim(Length(Flat) = Ms.HistCount, 'кольцо: история и оракул разной длины');

  Bad := False;
  if Length(Flat) = Ms.HistCount then
    for I := 0 to Ms.HistCount - 1 do
      if (PInt64(@Ms.Hist[I].Time)^ <> PInt64(@Flat[I].Time)^)
         or (PInteger(@Ms.Hist[I].Qty)^ <> PInteger(@Flat[I].Qty)^)
         or (PInteger(@Ms.Hist[I].Price)^ <> PInteger(@Flat[I].Price)^) then
        Bad := True;
  ChiClaim(not Bad, 'кольцо: история разошлась с оракулом');

  { ── Плотная лента: стык работает, проверяем то, что от него не зависит ── }
  DigDense := RunDeterministic(Dense, Md);
  CheckCensus(Md, Length(Dense), 'кольцо плотное');
  ChiClaim(Md.Spliced > 0,
    'кольцо плотное: стык ни разу не сработал — ветка не проверена');
  ChiClaim(Md.Spliced < Md.Stored,
    'кольцо плотное: стык отбросил всё, что было');

  { ── Многопоточно: только то, что верно при любом порядке ── }
  RunThreaded(Dense, 12);

  Result := Int64(DigSparse and $7FFFFFFF) * 1000003
            + Int64(DigDense and $7FFFFFFF)
            + Ms.HistCount + Md.Merged;
end;

end.
