unit resident_siege;

{ Семейство `siege` — длинная цепочка зависимостей и барьеры поперёк неё.

  Процессор считает быстро, когда операции независимы: он берёт их вперёд
  пачкой и раскладывает по свободным исполнителям. Цепочка, где каждая операция
  ждёт предыдущую, лишает его этой свободы, а компилятор пытается свободу
  вернуть — переставляет, растаскивает, считает наперёд. Пока перестановка
  сохраняет зависимости, всё честно; ошибка в учёте зависимости даёт результат,
  посчитанный из ещё не готового значения.

  Поперёк цепочки стоят барьеры четырёх видов: вызов в соседний юнит, чтение и
  запись общей памяти, интерфейсный вызов и бросок с обработчиком. Каждый из
  них — место, где наперёд считать нельзя, и каждый обязан пропустить через
  себя ровно то значение, которое к нему пришло.

  Отдельно проверяется обратное: несколько независимых дорожек, идущих
  вперемешку. Их переставлять можно как угодно, и результат каждой обязан
  остаться своим — перепутать дорожки нельзя даже при полной свободе. }

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch INLINEVARS}
{$endif}
{$Q-}{$R-}

interface

uses
  SysUtils, resident_core, resident_across;

implementation

type
  ESiegeCut = class(Exception)
  private
    FValue: Int64;
  public
    constructor Create(AValue: Int64); reintroduce;
    property Value: Int64 read FValue;
  end;

  ISiegeGate = interface
    ['{4D5A0006-0000-0000-0000-000053494547}']
    function Cross(const Value: Int64): Int64;
  end;

  TSiegeGate = class(TInterfacedObject, ISiegeGate)
  private
    FSeen: Int64;
  public
    function Cross(const Value: Int64): Int64;
    property Seen: Int64 read FSeen;
  end;

constructor ESiegeCut.Create(AValue: Int64);
begin
  inherited Create('resident: siege cut');
  FValue := AValue;
end;

function TSiegeGate.Cross(const Value: Int64): Int64;
begin
  Inc(FSeen);
  Result := Value + 29;
end;

{ Звено цепочки: результат зависит только от предыдущего значения и от номера
  шага, поэтому порядок нарушить нельзя, а посчитать наперёд — можно только
  выполнив всё до него. }
function Link(Step: Integer; const Value: Int64): Int64;
begin
  case Step and 3 of
    0: Result := Value * 3 + Step;
    1: Result := Value xor (Value shr 9);
    2: Result := Value - Step * 2;
  else
    Result := Value + (Value and 63);
  end;
end;

{ Двести звеньев подряд и барьеры через каждые двадцать. }
procedure StageChain(Carrier: TResidentCarrier);
var
  State: UInt64;
  Gate: ISiegeGate;
  Memory: array[0 .. 15] of Int64;
  I, Steps, Crossed, Thrown: Integer;
  Live, Flat: Int64;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap);
  Steps := 200 + Integer(ResidentNext(State) and 55);
  Live := Int64(ResidentNext(State) and $FFFF);
  Flat := Live;
  Crossed := 0;
  Thrown := 0;

  for I := 0 to High(Memory) do
    Memory[I] := 0;

  Gate := TSiegeGate.Create;
  AcrossEnter;
  try
    AcrossSet32(0);
    for I := 1 to Steps do
      begin
        Live := Link(I, Live);

        if (I mod 20) = 0 then
          case (I div 20) and 3 of
            0:
              begin
                { Барьер вызовом в соседний юнит. }
                AcrossBump32(1);
                Live := Live + AcrossRead32;
              end;
            1:
              begin
                { Барьер через память: значение уезжает в ячейку и
                  возвращается оттуда же. }
                Memory[(I div 20) and 15] := Live;
                Live := Memory[(I div 20) and 15];
              end;
            2:
              begin
                { Барьер интерфейсным вызовом. }
                Live := Gate.Cross(Live);
                Inc(Crossed);
              end;
          else
            { Барьер броском: значение проходит через обработчик. }
            try
              raise ESiegeCut.Create(Live - 5);
            except
              on E: ESiegeCut do
                begin
                  Inc(Thrown);
                  Live := E.Value;
                end;
            end;
          end;
      end;
  finally
    AcrossLeave;
    Gate := nil;
  end;

  { Плоско: та же цепочка, те же барьеры, но каждый барьер записан своим
    действием прямо в строке. }
  var Counter: Integer := 0;
  for I := 1 to Steps do
    begin
      Flat := Link(I, Flat);
      if (I mod 20) = 0 then
        case (I div 20) and 3 of
          0:
            begin
              Inc(Counter);
              Flat := Flat + Counter;
            end;
          1: ;
          2: Flat := Flat + 29;
        else
          Flat := Flat - 5;
        end;
    end;

  Carrier.Feed(UInt64(Live));
  Carrier.Feed(UInt64(Cardinal(Crossed)));
  Carrier.Feed(UInt64(Cardinal(Thrown)));
  Carrier.Claim(Live = Flat, 'siege: long dependency chain with barriers gave a different result');
end;

{ Четыре независимые дорожки, идущие вперемешку. Переставлять их между собой
  можно как угодно — но перепутать нельзя. }
procedure StageLanes(Carrier: TResidentCarrier);
var
  State: UInt64;
  Lanes, Mirror: array[0 .. 3] of Int64;
  I, K, Steps, Bad: Integer;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 3 + 1);
  Steps := 60 + Integer(ResidentNext(State) and 31);
  Bad := 0;

  for K := 0 to High(Lanes) do
    begin
      Lanes[K] := Int64(ResidentNext(State) and $FFFF) + K;
      Mirror[K] := Lanes[K];
    end;

  { Вперемешку: на каждом шаге двигаются все четыре. }
  for I := 1 to Steps do
    for K := 0 to High(Lanes) do
      Lanes[K] := Link(I + K, Lanes[K]);

  { По очереди: каждая дорожка целиком, одна за другой. }
  for K := 0 to High(Mirror) do
    for I := 1 to Steps do
      Mirror[K] := Link(I + K, Mirror[K]);

  for K := 0 to High(Lanes) do
    begin
      if Lanes[K] <> Mirror[K] then
        Inc(Bad);
      Carrier.Feed(UInt64(Lanes[K]));
    end;

  { Дорожки обязаны разойтись между собой: иначе проверка ничего не значит. }
  if (Lanes[0] = Lanes[1]) and (Lanes[1] = Lanes[2]) and (Lanes[2] = Lanes[3]) then
    Inc(Bad);

  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'siege: interleaved lanes disagree with the same lanes run in turn');
end;

{ Цепочка, которую рвут посередине: обработчик подхватывает значение и ход
  продолжается с того же места, а не с начала. }
procedure StageRestart(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, Steps, Cuts, FlatCuts: Integer;
  Live, Flat: Int64;

  function Risky(Step: Integer; const Value: Int64): Int64;
  begin
    if (Value and 15) = 7 then
      raise ESiegeCut.Create(Value * 2 + Step);
    Result := Link(Step, Value);
  end;

begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 5 + 2);
  Steps := 120 + Integer(ResidentNext(State) and 63);
  Live := Int64(ResidentNext(State) and $FFFF);
  Flat := Live;
  Cuts := 0;
  FlatCuts := 0;

  for I := 1 to Steps do
    try
      Live := Risky(I, Live);
    except
      on E: ESiegeCut do
        begin
          Inc(Cuts);
          Live := E.Value;
        end;
    end;

  for I := 1 to Steps do
    if (Flat and 15) = 7 then
      begin
        Inc(FlatCuts);
        Flat := Flat * 2 + I;
      end
    else
      Flat := Link(I, Flat);

  Carrier.Feed(UInt64(Live));
  Carrier.Feed(UInt64(Cardinal(Cuts)));
  Carrier.Claim(Live = Flat, 'siege: chain restarted after a cut gave a different result');
  Carrier.Claim(Cuts = FlatCuts, 'siege: a different number of cuts happened');
end;

{ Цепочка, у которой каждое звено читает общую переменную соседнего юнита, а
  каждое пятое — её меняет. Ни одно чтение нельзя поднять выше своей записи. }
procedure StageSharedFeed(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, Steps: Integer;
  Live, Flat, Shadow: Int64;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 7 + 3);
  Steps := 80 + Integer(ResidentNext(State) and 31);
  Live := Int64(ResidentNext(State) and $FFF);
  Flat := Live;

  AcrossEnter;
  try
    AcrossSet32(3);
    for I := 1 to Steps do
      begin
        Live := Live + AcrossRead32 * 2 - 1;
        if (I mod 5) = 0 then
          AcrossBump32(2);
      end;
  finally
    AcrossLeave;
  end;

  Shadow := 3;
  for I := 1 to Steps do
    begin
      Flat := Flat + Shadow * 2 - 1;
      if (I mod 5) = 0 then
        Shadow := Shadow + 2;
    end;

  Carrier.Feed(UInt64(Live));
  Carrier.Claim(Live = Flat, 'siege: reads of a shared value were hoisted above its writes');
end;

{ Дерево зависимостей: каждое значение собирается из двух предыдущих, поэтому
  порядок вычисления задан жёстко, а свободы у планировщика много. }
procedure StageTree(Carrier: TResidentCarrier);
var
  State: UInt64;
  Cells: array[0 .. 63] of Int64;
  Mirror: array[0 .. 63] of Int64;
  I, Bad: Integer;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 11 + 5);
  Bad := 0;

  Cells[0] := Int64(ResidentNext(State) and $FFFF);
  Cells[1] := Int64(ResidentNext(State) and $FFFF);
  Mirror[0] := Cells[0];
  Mirror[1] := Cells[1];

  { Прямой порядок: каждое следующее ждёт двух предыдущих. }
  for I := 2 to High(Cells) do
    Cells[I] := Link(I, Cells[I - 1]) xor Link(I + 1, Cells[I - 2]);

  { Тот же расчёт, но пара считается заранее и складывается отдельно —
    зависимости те же, а форма записи другая. }
  for I := 2 to High(Mirror) do
    begin
      var Left: Int64 := Link(I, Mirror[I - 1]);
      var Right: Int64 := Link(I + 1, Mirror[I - 2]);
      Mirror[I] := Left xor Right;
    end;

  for I := 0 to High(Cells) do
    if Cells[I] <> Mirror[I] then
      Inc(Bad);

  Carrier.Feed(UInt64(Cells[High(Cells)]));
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'siege: dependency tree computed a cell from a value that was not ready');
end;

initialization
  ResidentRegisterStage('siege-chain', @StageChain);
  ResidentRegisterStage('siege-lanes', @StageLanes);
  ResidentRegisterStage('siege-restart', @StageRestart);
  ResidentRegisterStage('siege-shared-feed', @StageSharedFeed);
  ResidentRegisterStage('siege-tree', @StageTree);

end.
