program resident;

{ Слой `resident` — взрослая программа Devil.

  Все прочие слои спрашивают компилятор «правильно ли ты вычислил?». Этот
  спрашивает другое: **правильно ли твой код стареет?** Выдерживает ли
  скомпилированная программа сотни оборотов владения, роста и переездов памяти,
  не потеряв ни байта, ни ссылки, ни одного объекта, обязанного умереть вовремя.

  Устройство: N носителей крутятся по кольцу стадий, каждая — своя языковая
  механика со своей очередью и своим пулом потоков. Маршрут носителя —
  персональная перестановка стадий, поэтому за оборот он бывает на каждой ровно
  раз, и так сотни оборотов.

  Оракулы (детерминизм при живых потоках):

    * у каждого носителя **свой** дайджест: маршрут задан сидом, поэтому
      последовательность его собственных событий детерминирована и сравнима
      между сборками до бита;
    * корень — **коммутативная** свёртка личных дайджестов, поэтому он не
      зависит от того, в каком порядке потоки успели отработать;
    * **постадийные суммы** — та же коммутативная свёртка, но с разбивкой:
      расхождение называет стадию, а не только факт;
    * **паспорт на обороте**: что носитель показал на первом обороте, обязан
      показать и на последнем;
    * **баланс**: за прогон число рождений равно числу смертей, и утечка в одну
      тысячную умножается числом оборотов;
    * **канарейки** вокруг буферов: порча называет место посева;
    * **счёт обработок**: маршрут — перестановка, поэтому обработок обязано быть
      ровно `носители * обороты * стадии`, без «примерно»;
    * **порядок initialization**: свойство компилятора, свёрнуто отдельно, чтобы
      перестановка секций не растворилась в корне;
    * глобальный порядок событий в корень не идёт — он не свойство программы.

  Программа обязана быть безупречной: один владелец в момент времени, ноль
  своего UB, никакого перемешивания сном. Тогда любое расхождение однозначно
  вешается на компилятор, RTL или менеджер памяти. }

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch anonymousfunctions}
  {$modeswitch functionreferences}
  {$modeswitch INLINEVARS}
{$endif}
{$APPTYPE CONSOLE}
{$Q-}{$R-}

uses
{$ifdef FPC}
  mormot.core.fpcx64mm,
  {$ifdef UNIX}cthreads,{$endif}
{$endif}
  SysUtils, Classes, SyncObjs, Generics.Collections,
  resident_core,
  resident_queue,
  resident_own,
  resident_text,
  resident_mem,
  resident_gen,
  resident_flow,
  resident_coll,
  resident_shape,
  resident_rtl,
  resident_cls,
  resident_codec,
  resident_thr,
  resident_bignum,
  resident_hash,
  resident_float,
  resident_calc,
  resident_fluid,
  resident_cipher,
  resident_fft,
  resident_pack,
  resident_eth,
  resident_numeric,
  resident_ode,
  resident_algo,
  resident_poly,
  resident_vm,
  resident_pred,
  resident_across,
  resident_opaque,
  resident_fault,
  resident_edge,
  resident_form,
  resident_live,
  resident_param,
  resident_select,
  resident_recur,
  resident_convert,
  resident_hoist,
  resident_matrix,
  resident_bits,
  resident_const,
  resident_intdiv,
  resident_ptr,
  resident_strops,
  resident_sideorder,
  resident_floatorder,
  resident_align,
  resident_arraydyn,
  resident_overflow,
  resident_enumord,
  resident_mesh,
  resident_pipe,
  resident_weave,
  resident_siege,
  resident_maze;

type
  { Работник стадии: берёт носителя из своей очереди, проводит через свою
    механику и передаёт владение дальше по маршруту. }
  TResidentWorker = class(TThread)
  private
    FStage: Integer;
    FQueues: TArray<TResidentQueue>;
    FLaps: Integer;
    FDone: TResidentQueue;
    FHandled: Int64;
    FSum: UInt64;
    FMisrouted: Int64;
    FFaults: Int64;
    FFaultName: string;
    FBroken: Int64;
    FBreachName: string;
    FCurrent: Integer;
  public
    constructor Create(AStage: Integer; const AQueues: TArray<TResidentQueue>;
      ALaps: Integer; ADone: TResidentQueue);
    procedure Execute; override;
    property Stage: Integer read FStage;
    property Handled: Int64 read FHandled;
    property Sum: UInt64 read FSum;
    property Misrouted: Int64 read FMisrouted;
    property Faults: Int64 read FFaults;
    property FaultName: string read FFaultName;
    property Broken: Int64 read FBroken;
    property BreachName: string read FBreachName;
    { Какую стадию поток ведёт прямо сейчас, -1 если ни одной. Читается чужим
      потоком только при разборе застоя — в дайджест не идёт. }
    property Current: Integer read FCurrent;
  end;

const
  { Сколько пустых проверок подряд считать застоем: только аварийный предел,
    никакого влияния на наблюдаемые величины. }
  StallLimit = 1500;

var
  Seed: UInt64 = 1;
  CarrierCount: Integer = 24;
  LapCount: Integer = 100;
  WorkersPerStage: Integer = 2;
  ListStages: Boolean = False;
  OnlyPrefix: string = '';

constructor TResidentWorker.Create(AStage: Integer;
  const AQueues: TArray<TResidentQueue>; ALaps: Integer; ADone: TResidentQueue);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FStage := AStage;
  FQueues := AQueues;
  FLaps := ALaps;
  FDone := ADone;
  FCurrent := -1;
end;

procedure TResidentWorker.Execute;
var
  Carrier: TResidentCarrier;
  Closed: Boolean;
  BrokenBefore: Int64;
begin
  while FQueues[FStage].Take(Carrier) do
  begin
    { С этого момента и до передачи дальше носитель принадлежит только этому
      потоку. Никто другой на него не смотрит. }
    if Carrier.CurrentStage <> FStage then
      Inc(FMisrouted);

    { Отказ стадии обязан стать наблюдением, а не концом программы: носитель
      остаётся в руках потока и едет дальше, а факт отказа доезжает до отчёта.
      Потеряй мы носителя здесь — кольцо ждало бы его вечно, и находка вышла бы
      висяком вместо строки в отчёте. }
    FCurrent := FStage;
    BrokenBefore := Carrier.Broken;
    Carrier.BeginStage;
    try
      try
        ResidentRunStage(FStage, Carrier);
      except
        on E: Exception do
        begin
          Inc(FFaults);
          if FFaultName = '' then
            FFaultName := ResidentStageName(FStage) + ':' + E.ClassName;
        end;
      end;
    finally
      FCurrent := -1;
    end;
    Carrier.Sound;
    Inc(FHandled);

    { Постадийная сумма складывает ВКЛАД стадии, а не накопленный дайджест
      носителя. Разница решающая: накопленный тащит за собой всю прошлую жизнь
      носителя, и одно раннее расхождение покрасило бы все последующие стадии
      подряд — локализация превратилась бы в украшение. Вклад же зависит только
      от того, что сделала сама стадия. Сложение коммутативно, поэтому сумма не
      зависит и от расписания. }
    FSum := FSum + Carrier.StageDigest;

    { Нарушенные утверждения снимаются с носителя сразу после стадии: так
      известно не только что сломалось, но и на какой стадии. Отсчёт ведётся от
      снимка, взятого ПЕРЕД этой стадией у ЭТОГО носителя: счётчик живёт на
      носителе, а носителей через поток проходит много, и общий для потока
      уровень приписал бы чужое нарушение не той стадии. }
    if Carrier.Broken > BrokenBefore then
    begin
      Inc(FBroken, Carrier.Broken - BrokenBefore);
      if FBreachName = '' then
        FBreachName := ResidentStageName(FStage) + ':' + Carrier.Breach;
    end;

    Closed := Carrier.Advance;
    if Closed then
      { Оборот кольца закрыт: паспорт снимается ровно раз за оборот. }
      Carrier.StampPassport;

    if Closed and (Carrier.Lap >= FLaps) then
      FDone.Put(Carrier)
    else
      FQueues[Carrier.CurrentStage].Put(Carrier);
    { Владение отдано. Дальше носитель не наш. }
  end;
end;

procedure ReadArguments;
var
  I: Integer;
  Name, Value: string;
begin
  I := 1;
  while I <= ParamCount do
  begin
    Name := ParamStr(I);
    if Name = '--list-stages' then
    begin
      ListStages := True;
      Inc(I);
      Continue;
    end;
    Value := ParamStr(I + 1);
    if Name = '--seed' then
      Seed := UInt64(StrToInt64(Value))
    else if Name = '--carriers' then
      CarrierCount := StrToInt(Value)
    else if Name = '--laps' then
      LapCount := StrToInt(Value)
    else if Name = '--workers' then
      WorkersPerStage := StrToInt(Value)
    else if Name = '--only' then
      OnlyPrefix := Value;
    Inc(I, 2);
  end;
  if CarrierCount < 1 then
    CarrierCount := 1;
  if LapCount < 1 then
    LapCount := 1;
  if WorkersPerStage < 1 then
    WorkersPerStage := 1;
end;

var
  Queues: TArray<TResidentQueue>;
  Workers: TArray<TResidentWorker>;
  StageSum: TArray<UInt64>;
  StageFault: TArray<Int64>;
  Done: TResidentQueue;
  Census: TResidentCensus;
  Carrier: TResidentCarrier;
  Finished: TList<TResidentCarrier>;
  Root: UInt64;
  I, Stage, StageTotal: Integer;
  Drifted, Corrupted, ShortLaps: Integer;
  Handled, Visits, Misrouted, Expected: Int64;
  Faults, Broken, Progress, Seen: Int64;
  FaultName, BreachName: string;
  Idle, Failures: Integer;
  Stalled: Boolean;
begin
  ReadArguments;
  if OnlyPrefix <> '' then
    ResidentKeepOnly(OnlyPrefix);
  ResidentSealStages;
  StageTotal := ResidentStageCount;

  WriteLn('RESIDENT_STAGES ', StageTotal);
  WriteLn('RESIDENT_REGISTRY ', IntToHex(ResidentRegistryDigest, 16));
  WriteLn('RESIDENT_INITORDER ', IntToHex(ResidentInitOrderDigest, 16));
  if ListStages then
  begin
    for Stage := 0 to StageTotal - 1 do
      WriteLn('RESIDENT_STAGE ', Stage, ' ', ResidentStageName(Stage));
    Halt(0);
  end;

  Census := TResidentCensus.Create;
  Finished := TList<TResidentCarrier>.Create;
  Done := TResidentQueue.Create;
  SetLength(Queues, StageTotal);
  for Stage := 0 to StageTotal - 1 do
    Queues[Stage] := TResidentQueue.Create;

  SetLength(Workers, StageTotal * WorkersPerStage);
  for I := 0 to High(Workers) do
    Workers[I] := TResidentWorker.Create(I mod StageTotal, Queues, LapCount,
                                         Done);

  { Носители рождаются до старта работников: так ни один не начнёт крутиться
    раньше, чем кольцо готово принять его. }
  for I := 0 to CarrierCount - 1 do
  begin
    Carrier := TResidentCarrier.Create(I, Seed, Census);
    Carrier.StampPassport;
    Queues[Carrier.CurrentStage].Put(Carrier);
  end;

  for I := 0 to High(Workers) do
    Workers[I].Start;

  { Главный поток собирает отработавших. Ждать вечно нельзя: зависшая стадия
    иначе превратила бы находку в молчаливый висяк. Признак жизни — рост общего
    числа обработок; пока оно растёт, кольцо работает, сколько бы оборотов ни
    было заказано. Время сюда входит только как аварийный предел и в дайджест
    не попадает ни в каком виде. }
  Stalled := False;
  Idle := 0;
  Seen := -1;
  while Finished.Count < CarrierCount do
  begin
    if Done.TryTake(Carrier) then
    begin
      Finished.Add(Carrier);
      Continue;
    end;
    Progress := 0;
    for I := 0 to High(Workers) do
      Inc(Progress, Workers[I].Handled);
    if Progress <> Seen then
    begin
      Seen := Progress;
      Idle := 0;
    end
    else
    begin
      Inc(Idle);
      if Idle > StallLimit then
      begin
        Stalled := True;
        Break;
      end;
    end;
  end;

  if Stalled then
  begin
    WriteLn('RESIDENT_FAILURE stalled handled=', Seen, ' collected=',
            Finished.Count, ' of=', CarrierCount);
    for I := 0 to High(Workers) do
      if Workers[I].Current >= 0 then
        WriteLn('RESIDENT_STUCK ', ResidentStageName(Workers[I].Current));
    Halt(2);
  end;

  for Stage := 0 to StageTotal - 1 do
    Queues[Stage].Close;

  SetLength(StageSum, StageTotal);
  SetLength(StageFault, StageTotal);
  Handled := 0;
  Misrouted := 0;
  for I := 0 to High(Workers) do
  begin
    Workers[I].WaitFor;
    Inc(Handled, Workers[I].Handled);
    Inc(Misrouted, Workers[I].Misrouted);
    Inc(Faults, Workers[I].Faults);
    if (Workers[I].FaultName <> '') and (FaultName = '') then
      FaultName := Workers[I].FaultName;
    Inc(Broken, Workers[I].Broken);
    if (Workers[I].BreachName <> '') and (BreachName = '') then
      BreachName := Workers[I].BreachName;
    StageSum[Workers[I].Stage] := StageSum[Workers[I].Stage] + Workers[I].Sum;
    Inc(StageFault[Workers[I].Stage], Workers[I].Faults);
    Workers[I].Free;
  end;

  { Корень — коммутативная свёртка личных дайджестов: сложение не зависит от
    того, в каком порядке потоки успели отработать, поэтому корень остаётся
    свойством программы, а не расписания. }
  Root := 0;
  Drifted := 0;
  Corrupted := 0;
  ShortLaps := 0;
  Visits := 0;
  for I := 0 to Finished.Count - 1 do
  begin
    Carrier := Finished[I];
    Root := Root + Carrier.Digest;
    Inc(Visits, Carrier.Visits);
    if Carrier.PassportDrifted then
      Inc(Drifted);
    if Carrier.Corrupted then
      Inc(Corrupted);
    if Carrier.Lap < LapCount then
      Inc(ShortLaps);
    WriteLn('RESIDENT_CARRIER ', Carrier.Serial, ' digest=',
            IntToHex(Carrier.Digest, 16), ' passport=',
            IntToHex(Carrier.Passport, 16), ' laps=', Carrier.Lap,
            ' visits=', Carrier.Visits, ' pockets=', Carrier.PocketCount);
    Carrier.Free;
  end;

  Done.Close;
  Done.Free;
  for Stage := 0 to StageTotal - 1 do
    Queues[Stage].Free;
  Finished.Free;

  for Stage := 0 to StageTotal - 1 do
    WriteLn('RESIDENT_STAGESUM ', ResidentStageName(Stage), ' ',
            IntToHex(StageSum[Stage], 16));
  { Отказы называются поимённо: одна упавшая стадия не имеет права прятаться за
    соседями, а первая по алфавиту — заслонять остальные. }
  for Stage := 0 to StageTotal - 1 do
    if StageFault[Stage] <> 0 then
      WriteLn('RESIDENT_STAGEFAULT ', ResidentStageName(Stage), ' ',
              StageFault[Stage]);

  WriteLn('RESIDENT_ROOT ', IntToHex(Root, 16));
  WriteLn('RESIDENT_CARRIERS ', CarrierCount);
  WriteLn('RESIDENT_LAPS ', LapCount);
  WriteLn('RESIDENT_HANDLED ', Handled);
  WriteLn('RESIDENT_VISITS ', Visits);
  WriteLn('RESIDENT_BORN ', Census.Born);
  WriteLn('RESIDENT_ALIVE ', Census.Alive);
  WriteLn('RESIDENT_DRIFTED ', Drifted);
  WriteLn('RESIDENT_CORRUPTED ', Corrupted);
  WriteLn('RESIDENT_SHORT ', ShortLaps);
  WriteLn('RESIDENT_MISROUTED ', Misrouted);
  WriteLn('RESIDENT_FAULTS ', Faults);
  WriteLn('RESIDENT_BROKEN ', Broken);

  Failures := 0;
  if Census.Alive <> 0 then
  begin
    WriteLn('RESIDENT_FAILURE balance alive=', Census.Alive);
    Failures := 1;
  end;
  if Drifted <> 0 then
  begin
    WriteLn('RESIDENT_FAILURE passport drifted=', Drifted);
    Failures := 1;
  end;
  if Corrupted <> 0 then
  begin
    WriteLn('RESIDENT_FAILURE canary corrupted=', Corrupted);
    Failures := 1;
  end;
  if ShortLaps <> 0 then
  begin
    WriteLn('RESIDENT_FAILURE laps short=', ShortLaps);
    Failures := 1;
  end;
  if Misrouted <> 0 then
  begin
    WriteLn('RESIDENT_FAILURE route mismatch=', Misrouted);
    Failures := 1;
  end;

  if Broken <> 0 then
  begin
    { Это не расхождение с эталоном, а нарушенное утверждение: известный ответ
      из спецификации, договор деления, обратимость. Такое неверно само по себе. }
    WriteLn('RESIDENT_FAILURE claim broken=', Broken, ' first=', BreachName);
    Failures := 1;
  end;

  if Faults <> 0 then
  begin
    WriteLn('RESIDENT_FAILURE stage raised=', Faults, ' first=', FaultName);
    Failures := 1;
  end;

  { Маршрут — перестановка, поэтому число обработок известно точно, без «около».
    Расхождение означает потерянного или задвоенного носителя. }
  Expected := Int64(CarrierCount) * Int64(LapCount) * Int64(StageTotal);
  if Handled <> Expected then
  begin
    WriteLn('RESIDENT_FAILURE handled=', Handled, ' expected=', Expected);
    Failures := 1;
  end;
  if Visits <> Expected then
  begin
    WriteLn('RESIDENT_FAILURE visits=', Visits, ' expected=', Expected);
    Failures := 1;
  end;

  Census.Free;
  Halt(Failures);
end.
