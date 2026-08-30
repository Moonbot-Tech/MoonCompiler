unit chimera_task;

{ Орган «задача»: состояние ордера как проводная запись и его жизненный путь.

  Источники: `MoonBot/MoonProto\MoonProtoOrderState.pas` —
  канон состояния ордера; `TaskWorkers.pas` — выдача номера задачи атомарным
  счётчиком и порядок наполнения полей при рождении. Перенесено дословно по
  форме:

    * состояние — `packed record` из ВЛОЖЕННЫХ `packed record`, у каждой
      секции свой точный размер, и размеры эти суть часть протокола, а не
      следствие выравнивания. Тридцать три, шестьдесят три, двадцать;
    * секции меняются ПО ОТДЕЛЬНОСТИ: правка исполнения не имеет права
      задеть размещение, правка размещения — медленные поля;
    * номер задачи выдаётся атомарным счётчиком, общим на все потоки;
    * при рождении поля заполняются длинным списком присваиваний подряд —
      десятки строк, где пропуск одной не виден глазом.

  Заменено оснасткой: биржа, журнал и очередь; здесь задача проходит свой путь
  сама.

  Почему это отдельная форма:

    * упакованная вложенность означает, что поле секции лежит по смещению,
      посчитанному сложением размеров предыдущих. Одно лишнее выравнивание —
      и весь хвост записи уезжает, а на проводе это не падение, а чужие
      числа в чужих полях;
    * `packed` запрещает выравнивание, но не запрещает компилятору читать поле
      целиком: чтение восьмибайтового значения по невыровненному адресу — то,
      что здесь происходит на каждом шагу;
    * фаза меняется не произвольно: из каждого состояния законны лишь
      некоторые переходы, и таблица законных — часть задачи.

  Оракулы:

    1. **точные размеры и смещения** каждой секции и каждого поля, выписанные
       по правилам упаковки, а не измеренные;
    2. **побайтовая неприкосновенность** соседних секций после правки одной;
    3. **таблица законных переходов** — отдельная от кода, который переходы
       выполняет;
    4. **уникальность номеров** задач, выданных из многих потоков. }

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch INLINEVARS}
{$endif}
{$Q-}{$R-}

interface

uses
  SysUtils, chimera_body, chimera_crew;

type
  { Исполнение одной стороны — 33 байта. }
  TChiExecSection = packed record
    QuantityRemaining: Double;
    ActualQ:           Double;
    TotalBTC:          Double;
    MeanPrice:         Double;
    PartialDone:       Byte;
  end;

  { Физическая инкарнация биржевого ордера — 63 байта. }
  TChiPlaceSection = packed record
    IntID:        Int64;
    ActualPrice:  Double;
    OpenTime:     Int64;
    Quantity:     Double;
    QuantityBase: Double;
    CloseTime:    Int64;
    CreateTime:   Int64;
    StopFlag:     Byte;
    OrderType:    Byte;
    SubType:      Byte;
    Leverage:     Byte;
    IsOpened:     Byte;
    IsClosed:     Byte;
    Canceled:     Byte;
  end;

  { Медленные поля — 20 байт. }
  TChiSlowSection = packed record
    LastCheck:  Int64;
    Retries:    Integer;
    LastError:  Integer;
    Flags:      Integer;
  end;

  TChiOrderState = packed record
    Status:           Byte;
    EffectiveStratID: UInt64;
    SellReason:       Byte;
    Flags:            Byte;
    TargetBuyPrice:   Double;
    TargetBuySize:    Double;
    BuyReplacing:     Byte;
    TargetSell:       Double;
    SellReplacing:    Byte;
    BuyExec:          TChiExecSection;
    BuyPlace:         TChiPlaceSection;
    BuySlow:          TChiSlowSection;
    SellExec:         TChiExecSection;
    SellPlace:        TChiPlaceSection;
    SellSlow:         TChiSlowSection;
  end;

function ChiTaskRun: Int64;

implementation

const
  IdTask = 'CHI-MB-TASK-001';

  { Фазы задачи. Числа — те же, что на проводе. }
  stIdle      = 0;
  stPrepared  = 1;
  stBuySet    = 2;
  stBuyFilled = 3;
  stSellSet   = 4;
  stSellFill  = 5;
  stDone      = 6;
  stCanceled  = 7;
  stFailed    = 8;

  { Таблица законных переходов — отдельно от кода, который переходит. }
  Allowed: array [0 .. 8, 0 .. 8] of Boolean = (
    { из stIdle      } (False, True,  False, False, False, False, False, True,  True),
    { из stPrepared  } (False, False, True,  False, False, False, False, True,  True),
    { из stBuySet    } (False, False, False, True,  False, False, False, True,  True),
    { из stBuyFilled } (False, False, False, False, True,  False, False, True,  True),
    { из stSellSet   } (False, False, False, False, False, True,  False, True,  True),
    { из stSellFill  } (False, False, False, False, False, False, True,  False, True),
    { из stDone      } (False, False, False, False, False, False, False, False, False),
    { из stCanceled  } (False, False, False, False, False, False, False, False, False),
    { из stFailed    } (False, False, False, False, False, False, False, False, False));

var
  TaskCounter: Int64;

{ ═══ Жизненный путь ══════════════════════════════════════════════════════ }

function NextTaskNum: Int64;
begin
  Result := AtomicIncrement(TaskCounter);
end;

{ Рождение: длинный список присваиваний подряд — форма живого конструктора. }
procedure BirthTask(out S: TChiOrderState; Num: Int64; Price, Size: Double);
begin
  S := Default(TChiOrderState);
  S.Status := stIdle;
  S.EffectiveStratID := UInt64(Num) * 7919;
  S.SellReason := 0;
  S.Flags := 0;
  S.TargetBuyPrice := Price;
  S.TargetBuySize := Size;
  S.BuyReplacing := 0;
  S.TargetSell := Price * 1.01;
  S.SellReplacing := 0;
  S.BuyExec.QuantityRemaining := Size;
  S.BuyExec.ActualQ := 0;
  S.BuyExec.TotalBTC := 0;
  S.BuyExec.MeanPrice := 0;
  S.BuyExec.PartialDone := 0;
  S.BuyPlace.IntID := Num;
  S.BuyPlace.ActualPrice := Price;
  S.BuyPlace.OpenTime := 0;
  S.BuyPlace.Quantity := Size;
  S.BuyPlace.QuantityBase := Size * Price;
  S.BuyPlace.CloseTime := 0;
  S.BuyPlace.CreateTime := 1735689600000;
  S.BuyPlace.StopFlag := 0;
  S.BuyPlace.OrderType := 1;
  S.BuyPlace.SubType := 0;
  S.BuyPlace.Leverage := 10;
  S.BuyPlace.IsOpened := 0;
  S.BuyPlace.IsClosed := 0;
  S.BuyPlace.Canceled := 0;
  S.BuySlow.LastCheck := 0;
  S.BuySlow.Retries := 0;
  S.BuySlow.LastError := 0;
  S.BuySlow.Flags := 0;
end;

function TryStep(var S: TChiOrderState; NewStatus: Byte): Boolean;
begin
  Result := Allowed[S.Status, NewStatus];
  if Result then S.Status := NewStatus;
end;

{ Правка ОДНОЙ секции: соседние не должны быть задеты. }
procedure PatchExec(var S: TChiOrderState; Filled, Price: Double);
begin
  S.BuyExec.ActualQ := S.BuyExec.ActualQ + Filled;
  S.BuyExec.QuantityRemaining := S.BuyExec.QuantityRemaining - Filled;
  S.BuyExec.TotalBTC := S.BuyExec.TotalBTC + Filled * Price;
  if S.BuyExec.ActualQ > 0 then
    S.BuyExec.MeanPrice := S.BuyExec.TotalBTC / S.BuyExec.ActualQ;
  if S.BuyExec.QuantityRemaining > 1E-12 then
    S.BuyExec.PartialDone := 1
  else
    S.BuyExec.PartialDone := 0;
end;

procedure PatchPlace(var S: TChiOrderState; OpenTime: Int64);
begin
  S.BuyPlace.OpenTime := OpenTime;
  S.BuyPlace.IsOpened := 1;
end;

{ ═══ Проверка ════════════════════════════════════════════════════════════ }

var
  Inside:    Integer = 0;
  MaxInside: Integer = 0;
  Churn:     Integer = 0;

function ChiTaskRun: Int64;
var
  S, Before: TChiOrderState;
  Acc: UInt64;
  I, J, Legal, Illegal: Integer;
  Nums: array of Int64;
  Ok: Boolean;
  Base, P: PByte;
  Path: array [0 .. 6] of Byte;
begin
  ChiCovered(IdTask);
  Acc := ChiOffset;

  { ── Точные размеры секций: часть протокола, а не следствие раскладки ── }
  ChiClaim(SizeOf(TChiExecSection) = 33, 'задача: секция исполнения не 33 байта');
  ChiClaim(SizeOf(TChiPlaceSection) = 63, 'задача: секция размещения не 63 байта');
  ChiClaim(SizeOf(TChiSlowSection) = 20, 'задача: медленная секция не 20 байт');
  ChiClaim(SizeOf(TChiOrderState) =
    1 + 8 + 1 + 1 + 8 + 8 + 1 + 8 + 1 + (33 + 63 + 20) * 2,
    'задача: размер состояния не сходится со суммой полей');
  ChiBranch(IdTask, 'sizes');
  Acc := ChiMix(Acc, SizeOf(TChiOrderState));

  { ── Смещения: посчитаны сложением, а не измерены ── }
  S := Default(TChiOrderState);
  Base := @S;
  ChiClaim(PByte(@S.EffectiveStratID) - Base = 1,
    'задача: смещение стратегии не то');
  ChiClaim(PByte(@S.TargetBuyPrice) - Base = 1 + 8 + 1 + 1,
    'задача: смещение цели покупки не то');
  ChiClaim(PByte(@S.BuyExec) - Base = 1 + 8 + 1 + 1 + 8 + 8 + 1 + 8 + 1,
    'задача: смещение секции исполнения не то');
  ChiClaim(PByte(@S.BuyPlace) - PByte(@S.BuyExec) = 33,
    'задача: размещение не сразу за исполнением');
  ChiClaim(PByte(@S.SellExec) - PByte(@S.BuySlow) = 20,
    'задача: продажа не сразу за медленными полями покупки');
  ChiBranch(IdTask, 'offsets');

  { Восьмибайтовое поле лежит по невыровненному адресу — и обязано читаться. }
  ChiClaim(((PByte(@S.EffectiveStratID) - Base) mod 8) <> 0,
    'задача: поле выровнялось — упаковка не сработала');
  S.EffectiveStratID := UInt64($0123456789ABCDEF);
  ChiClaim(S.EffectiveStratID = UInt64($0123456789ABCDEF),
    'задача: невыровненное чтение исказило значение');
  ChiBranch(IdTask, 'unaligned-field');

  { ── Правка одной секции не имеет права задеть соседние ── }
  BirthTask(S, 42, 100.0, 5.0);
  Before := S;
  PatchExec(S, 2.0, 100.5);
  ChiClaim(CompareMem(@Before.BuyPlace, @S.BuyPlace, SizeOf(TChiPlaceSection)),
    'задача: правка исполнения задела размещение');
  ChiClaim(CompareMem(@Before.BuySlow, @S.BuySlow, SizeOf(TChiSlowSection)),
    'задача: правка исполнения задела медленные поля');
  ChiClaim(CompareMem(@Before.SellExec, @S.SellExec, SizeOf(TChiExecSection)),
    'задача: правка покупки задела продажу');
  ChiClaim(S.BuyExec.PartialDone = 1, 'задача: частичное исполнение не отмечено');
  ChiBranch(IdTask, 'patch-exec');

  Before := S;
  PatchPlace(S, 1735689700000);
  ChiClaim(CompareMem(@Before.BuyExec, @S.BuyExec, SizeOf(TChiExecSection)),
    'задача: правка размещения задела исполнение');
  ChiClaim(S.BuyPlace.IsOpened = 1, 'задача: размещение не отмечено открытым');
  ChiBranch(IdTask, 'patch-place');

  { Добор до конца: частичное снимается. }
  PatchExec(S, 3.0, 101.0);
  ChiClaim(S.BuyExec.PartialDone = 0, 'задача: полное исполнение не сняло признак');
  ChiClaim(S.BuyExec.QuantityRemaining < 1E-12, 'задача: остаток не обнулился');
  ChiClaim(S.BuyExec.MeanPrice > 100.0, 'задача: средняя цена не посчиталась');
  ChiBranch(IdTask, 'fill-complete');
  Acc := ChiMix(Acc, PInt64(@S.BuyExec.MeanPrice)^);

  { ── Переходы: законные проходят, незаконные отвергаются ── }
  Legal := 0;
  Illegal := 0;
  for I := 0 to 8 do
    for J := 0 to 8 do
    begin
      BirthTask(S, 1, 100, 1);
      S.Status := Byte(I);
      if TryStep(S, Byte(J)) then
      begin
        ChiClaim(Allowed[I, J], 'задача: незаконный переход прошёл');
        ChiClaim(S.Status = Byte(J), 'задача: статус не обновился');
        Inc(Legal);
      end
      else
      begin
        ChiClaim(not Allowed[I, J], 'задача: законный переход отвергнут');
        ChiClaim(S.Status = Byte(I), 'задача: отвергнутый переход сдвинул статус');
        Inc(Illegal);
      end;
    end;
  ChiClaim(Legal > 0, 'задача: ни один переход не прошёл');
  ChiClaim(Illegal > 0, 'задача: ни один переход не отвергнут');
  ChiBranch(IdTask, 'transitions');
  Acc := ChiMix(Acc, Legal);
  Acc := ChiMix(Acc, Illegal);

  { ── Полный путь от рождения до завершения ── }
  Path[0] := stPrepared; Path[1] := stBuySet; Path[2] := stBuyFilled;
  Path[3] := stSellSet;  Path[4] := stSellFill; Path[5] := stDone;
  BirthTask(S, NextTaskNum, 100, 5);
  for I := 0 to 5 do
    ChiClaim(TryStep(S, Path[I]),
      'задача: шаг пути ' + IntToStr(I) + ' не прошёл');
  ChiClaim(S.Status = stDone, 'задача: путь не привёл к завершению');
  { Из завершения выхода нет. }
  ChiClaim(not TryStep(S, stBuySet), 'задача: из завершения ушли назад');
  ChiBranch(IdTask, 'full-path');

  { Отмена возможна с любой рабочей фазы. }
  for I := stIdle to stSellSet do
  begin
    BirthTask(S, 1, 100, 1);
    S.Status := Byte(I);
    ChiClaim(TryStep(S, stCanceled),
      'задача: отмена не прошла из фазы ' + IntToStr(I));
  end;
  ChiBranch(IdTask, 'cancel-anywhere');

  { ── Номера задач: атомарный счётчик из многих потоков ── }
  SetLength(Nums, 512);
  Inside := 0;
  MaxInside := 0;
  ChiParallel(Length(Nums), ChiThreadCount,
    procedure(Index: Integer)
    var
      Now1: Integer;
    begin
      { Наблюдаемый след пересечения: сколько работников было внутри
        одновременно. Без него уникальность номеров прошла бы и при
        исполнении по очереди, а тогда атомарность не проверена вовсе. }
      Now1 := AtomicIncrement(Inside);
      if Now1 > MaxInside then AtomicExchange(MaxInside, Now1);
      Nums[Index] := NextTaskNum;
      { Работа внутри: без неё работник выходит раньше, чем войдёт соседний. }
      for var Spin := 1 to 200 do
        AtomicIncrement(Churn);
      AtomicDecrement(Inside);
    end);
  ChiClaim(MaxInside > 1,
    'задача: работники не пересеклись — атомарный счётчик проверен вхолостую');
  ChiClaim(Churn = Length(Nums) * 200,
    'задача: накрутка потеряла обороты — атомарное сложение считает неверно');
  { Уникальность: номера отсортированы и соседи различны. }
  for I := 0 to High(Nums) - 1 do
    for J := I + 1 to High(Nums) do
      if Nums[I] = Nums[J] then
        ChiClaim(False, 'задача: два одинаковых номера');
  Ok := True;
  for I := 0 to High(Nums) do
    if (Nums[I] <= 0) or (Nums[I] > TaskCounter) then Ok := False;
  ChiClaim(Ok, 'задача: номер вне выданного диапазона');
  ChiBranch(IdTask, 'atomic-numbers');
  ChiBranch(IdTask, 'threads-overlapped');
  Acc := ChiMix(Acc, Length(Nums));

  { ── Запись целиком переносится байтами и обязана совпасть ── }
  BirthTask(S, 7, 123.456, 78.9);
  PatchExec(S, 10, 124.0);
  Before := Default(TChiOrderState);
  Move(S, Before, SizeOf(TChiOrderState));
  ChiClaim(CompareMem(@S, @Before, SizeOf(TChiOrderState)),
    'задача: побайтовый перенос состояния исказил его');
  P := @Before;
  Acc := ChiMix(Acc, PInt64(P + SizeOf(TChiOrderState) - 8)^);
  ChiBranch(IdTask, 'byte-copy');

  Result := Int64(Acc and $7FFFFFFFFFFF);
end;

end.
