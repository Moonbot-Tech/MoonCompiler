unit resident_thr;

{ Семейство `thr` — своя многопоточность внутри стадии.

  Кольцо и так гоняет носителей десятками потоков, но каждая отдельная стадия
  до сих пор была однопоточной. Здесь стадия сама разводит работу по потокам —
  и делает это ровно так, как обязана делать честная программа: у каждого
  потока своя ячейка результата, ни одного разделяемого изменяемого поля без
  синхронизации, а сведение — коммутативное.

  Отсюда и оракул: **результат не имеет права зависеть от расписания**. Одна и
  та же работа, посчитанная одним потоком и несколькими, обязана дать
  побитово одно и то же. Если разошлось — это гонка, и своих гонок здесь нет по
  построению, значит она в том, что собрал компилятор: в менеджере памяти, в
  счётчиках ссылок, в строках.

  Второй оракул — **точный счёт**: потоки складывают в общий счётчик заведомо
  известное число раз. Потерянное сложение видно сразу, а именно так выглядит
  сорванная неделимость.

  Потоки заводятся не на каждом обороте: их создание дороже всего, что они
  делают, и кольцу незачем платить эту цену постоянно. }

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
  SysUtils, Classes, SyncObjs, Generics.Collections, resident_core;

implementation

const
  { Сколько потоков разводит стадия и как часто. Числа маленькие нарочно:
    нагрузку создаёт кольцо целиком, а не одна стадия. }
  Hands = 3;
  EveryLap = 4;
  Portion = 512;

type
  { Работа, поделённая на доли: у каждой доли своя ячейка, поэтому потокам
    нечего делить и незачем синхронизироваться. }
  TResidentShare = record
    Sum: UInt64;
    Blocks: Integer;
    Text: Integer;
    Refs: Integer;
  end;
  PResidentShare = ^TResidentShare;

  IResidentSpark = interface
    ['{4D5A0040-0000-0000-0000-0000524553FF}']
    function Value: Int64;
  end;

  TResidentSpark = class(TInterfacedObject, IResidentSpark)
  private
    FValue: Int64;
  public
    constructor Create(AValue: Int64);
    function Value: Int64;
  end;

  { Поток-доля: считает свой кусок и кладёт итог в свою ячейку. }
  TResidentHand = class(TThread)
  private
    FShare: PResidentShare;
    FFrom, FTo: Integer;
    FSeed: UInt64;
    FKind: Integer;
    FCounter: PInt64;
    FLock: TCriticalSection;
    FRounds: Integer;
    FFailed: Boolean;
    procedure DoSum;
    procedure DoBlocks;
    procedure DoText;
    procedure DoRefs;
    procedure DoCountLocked;
    procedure DoCountAtomic;
  public
    constructor Create(AShare: PResidentShare; AFrom, ATo: Integer;
      ASeed: UInt64; AKind: Integer);
    procedure Execute; override;
    property Failed: Boolean read FFailed;
  end;

  { Поточно-местная переменная: у каждого потока своя, и чужая ей не указ. }
threadvar
  LocalMark: Int64;

constructor TResidentSpark.Create(AValue: Int64);
begin
  inherited Create;
  FValue := AValue;
end;

function TResidentSpark.Value: Int64;
begin
  Result := FValue;
end;

constructor TResidentHand.Create(AShare: PResidentShare; AFrom, ATo: Integer;
  ASeed: UInt64; AKind: Integer);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FShare := AShare;
  FFrom := AFrom;
  FTo := ATo;
  FSeed := ASeed;
  FKind := AKind;
end;

procedure TResidentHand.DoSum;
var
  I: Integer;
  State: UInt64;
begin
  { Значение слагаемого зависит только от его номера — не от того, сколько
    чисел поток взял до него. Иначе разбиение на доли меняло бы сами слагаемые,
    и совпадение суммы частей с суммой целого ничего бы не значило. }
  for I := FFrom to FTo do
  begin
    State := ResidentMix(FSeed, UInt64(Cardinal(I)));
    FShare^.Sum := FShare^.Sum + (ResidentNext(State) xor UInt64(Cardinal(I)));
  end;
end;

procedure TResidentHand.DoBlocks;
var
  I, Size: Integer;
  Block: PByte;
begin
  { Занятие и освобождение памяти из нескольких потоков сразу — то место, где
    менеджер обязан выдержать одновременность. Каждый блок свой, ничей больше. }
  for I := FFrom to FTo do
  begin
    Size := 16 + (I mod 2048);
    GetMem(Block, Size);
    try
      PByte(Block)^ := Byte(I and $FF);
      PByte(PByte(Block) + Size - 1)^ := Byte((I shr 8) and $FF);
      if (PByte(Block)^ <> Byte(I and $FF)) or
         (PByte(PByte(Block) + Size - 1)^ <> Byte((I shr 8) and $FF)) then
        FFailed := True;
      Inc(FShare^.Blocks);
    finally
      FreeMem(Block);
    end;
  end;
end;

procedure TResidentHand.DoText;
var
  I: Integer;
  Work, Twin: string;
begin
  { Строки со счётчиком ссылок из нескольких потоков: каждая своя, но менеджер
    памяти под ними общий. }
  for I := FFrom to FTo do
  begin
    Work := StringOfChar('a', 1 + (I mod 64));
    Twin := Work;
    Twin := Twin + 'x';
    if Length(Twin) <> Length(Work) + 1 then
      FFailed := True;
    Inc(FShare^.Text, Length(Work));
  end;
end;

procedure TResidentHand.DoRefs;
var
  I: Integer;
  Held, Copy: IResidentSpark;
begin
  for I := FFrom to FTo do
  begin
    Held := TResidentSpark.Create(Int64(I));
    Copy := Held;
    if Copy.Value <> Int64(I) then
      FFailed := True;
    Copy := nil;
    Held := nil;
    Inc(FShare^.Refs);
  end;
end;

procedure TResidentHand.DoCountLocked;
var
  I: Integer;
begin
  for I := FFrom to FTo do
  begin
    FLock.Enter;
    try
      Inc(FCounter^);
    finally
      FLock.Leave;
    end;
  end;
end;

procedure TResidentHand.DoCountAtomic;
var
  I: Integer;
begin
  for I := FFrom to FTo do
    TInterlocked.Increment(FCounter^);
end;

procedure TResidentHand.Execute;
begin
  { Поточно-местная переменная обязана начинаться с нуля в каждом потоке и не
    видеть того, что положили в неё соседи. }
  if LocalMark <> 0 then
    FFailed := True;
  LocalMark := Int64(FFrom) + 1;

  case FKind of
    0: DoSum;
    1: DoBlocks;
    2: DoText;
    3: DoRefs;
    4: DoCountLocked;
    5: DoCountAtomic;
  end;

  if LocalMark <> Int64(FFrom) + 1 then
    FFailed := True;
end;

{ Развести работу по потокам и дождаться всех. Доли нарезаются заранее, поэтому
  распределение не зависит от того, кто первым проснулся. }
function RunHands(Kind: Integer; Total: Integer; Seed: UInt64;
  var Shares: array of TResidentShare; Counter: PInt64;
  Lock: TCriticalSection): Boolean;
var
  Hands_: array[0 .. Hands - 1] of TResidentHand;
  Step, I, From_, To_: Integer;
begin
  Result := True;
  Step := Total div Hands;
  for I := 0 to Hands - 1 do
  begin
    From_ := I * Step;
    if I = Hands - 1 then
      To_ := Total - 1
    else
      To_ := From_ + Step - 1;
    Hands_[I] := TResidentHand.Create(@Shares[I], From_, To_, Seed, Kind);
    Hands_[I].FCounter := Counter;
    Hands_[I].FLock := Lock;
  end;
  try
    for I := 0 to Hands - 1 do
      Hands_[I].Start;
    for I := 0 to Hands - 1 do
    begin
      Hands_[I].WaitFor;
      if Hands_[I].Failed then
        Result := False;
    end;
  finally
    for I := 0 to Hands - 1 do
      Hands_[I].Free;
  end;
end;

{ Одна и та же работа, посчитанная одним потоком: эталон для сравнения. }
function AloneSum(Total: Integer; Seed: UInt64): UInt64;
var
  I: Integer;
  State: UInt64;
begin
  Result := 0;
  for I := 0 to Total - 1 do
  begin
    State := ResidentMix(Seed, UInt64(Cardinal(I)));
    Result := Result + (ResidentNext(State) xor UInt64(Cardinal(I)));
  end;
end;

{ Свёртка долей: сумма по частям обязана совпасть с суммой целиком. }
procedure StageParallelFold(Carrier: TResidentCarrier);
var
  Shares: array[0 .. Hands - 1] of TResidentShare;
  Total, I: Integer;
  Seed, Together, Alone: UInt64;
begin
  Total := Portion;
  Seed := ResidentMix(Carrier.Seed, UInt64(Cardinal(Carrier.Serial)));
  Alone := AloneSum(Total, Seed);
  Carrier.Feed(Alone);

  if Carrier.Lap mod EveryLap <> 0 then
    Exit;

  FillChar(Shares, SizeOf(Shares), 0);
  Carrier.Feed(UInt64(Ord(RunHands(0, Total, Seed, Shares, nil, nil))));

  Together := 0;
  for I := 0 to Hands - 1 do
    Together := Together + Shares[I].Sum;
  Carrier.Feed(Together);
  { Главный оракул семейства: та же работа, разложенная по потокам, обязана
    дать в точности то же число, что и посчитанная одним. Разошлось — значит
    расписание протекло в результат. }
  Carrier.Feed(UInt64(Ord(Together = Alone)));
  Carrier.Feed(UInt64(Cardinal(Hands)));
end;

{ Память под одновременной нагрузкой: несколько потоков занимают и отдают блоки
  разных классов, и каждый обязан получить свой, целый. }
procedure StageAllocStorm(Carrier: TResidentCarrier);
var
  Shares: array[0 .. Hands - 1] of TResidentShare;
  Total, I, Done: Integer;
  Ok: Boolean;
begin
  if Carrier.Lap mod EveryLap <> 0 then
  begin
    Carrier.Feed(UInt64(Cardinal(Carrier.Lap mod EveryLap)));
    Exit;
  end;

  Total := Portion;
  FillChar(Shares, SizeOf(Shares), 0);
  Ok := RunHands(1, Total, Carrier.Seed, Shares, nil, nil);
  Carrier.Feed(UInt64(Ord(Ok)));

  Done := 0;
  for I := 0 to Hands - 1 do
    Inc(Done, Shares[I].Blocks);
  { Блоков обязано быть ровно столько, сколько долей заказано — ни одной
    потерянной, ни одной лишней. }
  Carrier.Feed(UInt64(Cardinal(Done)));
  Carrier.Feed(UInt64(Ord(Done = Total)));
end;

{ Строки под одновременной нагрузкой: у каждой свой буфер, менеджер под ними
  общий. }
procedure StageTextStorm(Carrier: TResidentCarrier);
var
  Shares: array[0 .. Hands - 1] of TResidentShare;
  Total, I, Done: Integer;
  Ok: Boolean;
begin
  if Carrier.Lap mod EveryLap <> 0 then
  begin
    Carrier.Feed(UInt64(Cardinal(Carrier.Serial)));
    Exit;
  end;

  Total := Portion;
  FillChar(Shares, SizeOf(Shares), 0);
  Ok := RunHands(2, Total, Carrier.Seed, Shares, nil, nil);
  Carrier.Feed(UInt64(Ord(Ok)));

  Done := 0;
  for I := 0 to Hands - 1 do
    Inc(Done, Shares[I].Text);
  { Суммарная длина известна заранее и не зависит от того, кто когда успел. }
  Carrier.Feed(UInt64(Cardinal(Done)));
  var Expect := 0;
  for I := 0 to Total - 1 do
    Inc(Expect, 1 + (I mod 64));
  Carrier.Feed(UInt64(Ord(Done = Expect)));
end;

{ Счётчики ссылок под одновременной нагрузкой: объекты свои у каждого потока,
  но заводятся и хоронятся они одновременно. }
procedure StageRefStorm(Carrier: TResidentCarrier);
var
  Shares: array[0 .. Hands - 1] of TResidentShare;
  Total, I, Done: Integer;
  Ok: Boolean;
begin
  if Carrier.Lap mod EveryLap <> 0 then
  begin
    Carrier.Feed(UInt64(Cardinal(Carrier.Lap)));
    Exit;
  end;

  Total := Portion;
  FillChar(Shares, SizeOf(Shares), 0);
  Ok := RunHands(3, Total, Carrier.Seed, Shares, nil, nil);
  Carrier.Feed(UInt64(Ord(Ok)));

  Done := 0;
  for I := 0 to Hands - 1 do
    Inc(Done, Shares[I].Refs);
  Carrier.Feed(UInt64(Cardinal(Done)));
  Carrier.Feed(UInt64(Ord(Done = Total)));
end;

{ Общий счётчик: под блокировкой и неделимой операцией. Обе дороги обязаны
  досчитать до точного числа — потерянное сложение здесь видно сразу. }
procedure StageSharedCounter(Carrier: TResidentCarrier);
var
  Shares: array[0 .. Hands - 1] of TResidentShare;
  Lock: TCriticalSection;
  Counter: Int64;
  Total: Integer;
begin
  if Carrier.Lap mod EveryLap <> 0 then
  begin
    Carrier.Feed(UInt64(Cardinal(Carrier.Serial + Carrier.Lap)));
    Exit;
  end;

  Total := Portion;
  Lock := TCriticalSection.Create;
  try
    FillChar(Shares, SizeOf(Shares), 0);
    Counter := 0;
    Carrier.Feed(UInt64(Ord(RunHands(4, Total, Carrier.Seed, Shares,
                                     @Counter, Lock))));
    Carrier.Feed(UInt64(Counter));
    Carrier.Feed(UInt64(Ord(Counter = Total)));

    FillChar(Shares, SizeOf(Shares), 0);
    Counter := 0;
    Carrier.Feed(UInt64(Ord(RunHands(5, Total, Carrier.Seed, Shares,
                                     @Counter, Lock))));
    Carrier.Feed(UInt64(Counter));
    Carrier.Feed(UInt64(Ord(Counter = Total)));
  finally
    Lock.Free;
  end;
end;

{ Поточно-местная переменная главного потока: соседи её не трогают, сколько бы
  их ни было. }
procedure StageThreadLocal(Carrier: TResidentCarrier);
var
  Shares: array[0 .. Hands - 1] of TResidentShare;
  Was: Int64;
begin
  Was := LocalMark;
  LocalMark := Carrier.Tag.Wide;
  Carrier.Feed(UInt64(Ord(LocalMark = Carrier.Tag.Wide)));

  if Carrier.Lap mod EveryLap = 0 then
  begin
    FillChar(Shares, SizeOf(Shares), 0);
    { Внутри стадии поднимаются потоки, и каждый пишет в свою копию. }
    Carrier.Feed(UInt64(Ord(RunHands(0, Portion, Carrier.Seed, Shares,
                                     nil, nil))));
    { Наша копия обязана остаться нетронутой. }
    Carrier.Feed(UInt64(Ord(LocalMark = Carrier.Tag.Wide)));
  end;

  { Прошлая стадия обязана была убрать за собой: этот поток обслуживает разные
    стадии подряд, и оставленный след был бы утечкой между ними. }
  Carrier.Feed(UInt64(Ord(Was = 0)));
  LocalMark := 0;
  Carrier.Feed(UInt64(Ord(LocalMark = 0)));
end;

initialization
  ResidentRegisterStage('thr-alloc-storm', @StageAllocStorm);
  ResidentRegisterStage('thr-parallel-fold', @StageParallelFold);
  ResidentRegisterStage('thr-ref-storm', @StageRefStorm);
  ResidentRegisterStage('thr-shared-counter', @StageSharedCounter);
  ResidentRegisterStage('thr-text-storm', @StageTextStorm);
  ResidentRegisterStage('thr-thread-local', @StageThreadLocal);

end.
