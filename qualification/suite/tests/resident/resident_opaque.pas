unit resident_opaque;

{ Семейство `opaque` — то, что оптимизатор обязан НЕ доказать.

  Всякая оптимизация цикла держится на утверждении «между оборотами это не
  менялось». Утверждение верное ровно до тех пор, пока компилятор видит все
  места записи. Здесь каждая стадия устроена так, что запись существует, но
  приходит с той стороны, куда прямой взгляд не достаёт: из соседнего юнита,
  из вставленного тела, через указатель, через ссылку на тот же буфер, из
  вложенной процедуры в кадр родителя, из виртуального вызова.

  Проверяется не «то же ли число, что вчера», а равенство двух форм одного
  счёта: подозрительной, где значение читается прямо в выражении цикла, и
  зеркальной, где то же самое собрано по шагам так, что выносить наружу
  нечего. Обе формы — обычный Pascal без единого трюка, и любая честная
  оптимизация сохраняет обе.

  Общие переменные соседнего юнита живут в программе в одном экземпляре, а
  кольцо многопоточное, поэтому стадия, которая их трогает, владеет ими
  целиком на всё своё время. Владение берётся снаружи расчёта: под замком
  оказывается вся стадия, а не отдельный доступ, иначе в середину своей
  арифметики попадала бы чужая. }

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
  SysUtils, resident_core, resident_across;

implementation

type
  TOpaqueCell = class
  private
    FValue: Integer;
  public
    constructor Create(AValue: Integer);
    procedure Bump(Delta: Integer); virtual;
    property Value: Integer read FValue write FValue;
  end;

  { Наследник меняет поле иначе, поэтому вызов через базовую ссылку нельзя
    заменить на известное действие: какое тело выполнится, решает объект. }
  TOpaqueTwist = class(TOpaqueCell)
  public
    procedure Bump(Delta: Integer); override;
  end;

  IOpaqueDial = interface
    ['{4D5A0002-0000-0000-0000-00004F504151}']
    function Read: Integer;
    procedure Turn(Delta: Integer);
  end;

  TOpaqueDial = class(TInterfacedObject, IOpaqueDial)
  private
    FValue: Integer;
  public
    constructor Create(AValue: Integer);
    function Read: Integer;
    procedure Turn(Delta: Integer);
  end;

  TOpaqueBumper = procedure(Delta: Integer);

var
  { Переменная класса живёт столько же, сколько программа, и меняется методом
    класса — ещё одна запись, которую не видно в месте чтения. }
  SharedTicks: Integer;

constructor TOpaqueCell.Create(AValue: Integer);
begin
  inherited Create;
  FValue := AValue;
end;

procedure TOpaqueCell.Bump(Delta: Integer);
begin
  FValue := FValue + Delta;
end;

procedure TOpaqueTwist.Bump(Delta: Integer);
begin
  FValue := FValue + Delta * 2 + 1;
end;

constructor TOpaqueDial.Create(AValue: Integer);
begin
  inherited Create;
  FValue := AValue;
end;

function TOpaqueDial.Read: Integer;
begin
  Result := FValue;
end;

procedure TOpaqueDial.Turn(Delta: Integer);
begin
  FValue := FValue + Delta;
end;

{ Глобал соседнего юнита меняется вызовом внутри цикла. Читается он там же, в
  выражении, — и вот это чтение вынести наружу нельзя. }
procedure StageCrossUnitGlobal(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, Start, Step: Integer;
  Live, Mirror, Shadow: Int64;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap);
  Start := 3 + Integer(ResidentNext(State) and 7);
  Step := 1 + Integer(ResidentNext(State) and 3);

  AcrossEnter;
  try
    AcrossSet32(Start);
    Live := 0;
    for I := 1 to 8 do
      begin
        Live := Live + Int64(I * AcrossI32);
        AcrossBump32(Step);
      end;

    { Зеркало: то же самое, но значение переносится в локал шаг за шагом. }
    Shadow := Start;
    Mirror := 0;
    for I := 1 to 8 do
      begin
        Mirror := Mirror + Int64(I) * Shadow;
        Shadow := Shadow + Step;
      end;
  finally
    AcrossLeave;
  end;

  Carrier.Feed(UInt64(Live));
  Carrier.Feed(UInt64(Mirror));
  Carrier.Claim(Live = Mirror, 'opaque: cross-unit global treated as loop invariant');
end;

{ То же, но вызов стоит под условием и срабатывает один раз за цикл. Именно на
  этой форме держался найденный дефект: изменение редкое, и соблазн признать
  значение постоянным сильнее. }
procedure StageCrossUnitConditional(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, Start, Step: Integer;
  Live, Mirror, Shadow: Int64;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 5 + 2);
  Start := 4 + Integer(ResidentNext(State) and 7);
  Step := 2 + Integer(ResidentNext(State) and 3);

  AcrossEnter;
  try
    AcrossSet32(Start);
    Live := 0;
    for I := 1 to 6 do
      begin
        Live := Live + Int64((I * AcrossI32) xor ((I + 1) * AcrossI32));
        if I = 1 then
          AcrossBump32(Step);
      end;

    Shadow := Start;
    Mirror := 0;
    for I := 1 to 6 do
      begin
        Mirror := Mirror + Int64((Int64(I) * Shadow) xor (Int64(I + 1) * Shadow));
        if I = 1 then
          Shadow := Shadow + Step;
      end;
  finally
    AcrossLeave;
  end;

  Carrier.Feed(UInt64(Live));
  Carrier.Feed(UInt64(Mirror));
  Carrier.Claim(Live = Mirror, 'opaque: conditional cross-unit write lost');
end;

{ Индекс таблицы, посчитанный через чужой глобал. Подстановка по таблице —
  первый кандидат на вынос из цикла. }
procedure StageCrossUnitTable(Carrier: TResidentCarrier);
var
  State: UInt64;
  Table: array[0 .. 31] of Int64;
  I, J, Start: Integer;
  Live, Mirror, Shadow: Int64;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 3 + 7);
  Start := 5 + Integer(ResidentNext(State) and 7);
  for J := 0 to High(Table) do
    Table[J] := Int64(J) * 7 + 3;

  AcrossEnter;
  try
    AcrossSet32(Start);
    Live := 0;
    for I := 1 to 6 do
      begin
        Live := Live + Table[(I * AcrossI32) and 31];
        if I = 1 then
          AcrossBump32(2);
      end;

    Shadow := Start;
    Mirror := 0;
    for I := 1 to 6 do
      begin
        Mirror := Mirror + Table[(I * Shadow) and 31];
        if I = 1 then
          Shadow := Shadow + 2;
      end;
  finally
    AcrossLeave;
  end;

  Carrier.Feed(UInt64(Live));
  Carrier.Feed(UInt64(Mirror));
  Carrier.Claim(Live = Mirror, 'opaque: table lookup hoisted across a cross-unit write');
end;

{ Поле объекта, которое меняет его собственный метод. }
procedure StageObjectField(Carrier: TResidentCarrier);
var
  State: UInt64;
  Cell: TOpaqueCell;
  I, Start: Integer;
  Live, Mirror, Shadow: Int64;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 2 + 9);
  Start := 2 + Integer(ResidentNext(State) and 15);

  Cell := TOpaqueCell.Create(Start);
  try
    Live := 0;
    for I := 1 to 8 do
      begin
        Live := Live + Int64(I) * Cell.Value;
        if (I and 1) = 1 then
          Cell.Bump(3);
      end;
  finally
    FreeAndNil(Cell);
  end;

  Shadow := Start;
  Mirror := 0;
  for I := 1 to 8 do
    begin
      Mirror := Mirror + Int64(I) * Shadow;
      if (I and 1) = 1 then
        Shadow := Shadow + 3;
    end;

  Carrier.Feed(UInt64(Live));
  Carrier.Feed(UInt64(Mirror));
  Carrier.Claim(Live = Mirror, 'opaque: object field treated as loop invariant');
end;

{ Виртуальный вызов: какое тело выполнится, известно только объекту. }
procedure StageVirtualCall(Carrier: TResidentCarrier);
var
  State: UInt64;
  Cell: TOpaqueCell;
  I, Start: Integer;
  Live, Mirror, Shadow: Int64;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 13 + 1);
  Start := 1 + Integer(ResidentNext(State) and 7);

  Cell := TOpaqueTwist.Create(Start);
  try
    Live := 0;
    for I := 1 to 6 do
      begin
        Live := Live + Int64(I) * Cell.Value;
        Cell.Bump(1);
      end;
  finally
    FreeAndNil(Cell);
  end;

  { Зеркало повторяет тело наследника, а не базы: подмена была бы видна. }
  Shadow := Start;
  Mirror := 0;
  for I := 1 to 6 do
    begin
      Mirror := Mirror + Int64(I) * Shadow;
      Shadow := Shadow + 1 * 2 + 1;
    end;

  Carrier.Feed(UInt64(Live));
  Carrier.Feed(UInt64(Mirror));
  Carrier.Claim(Live = Mirror, 'opaque: virtual call resolved to the wrong body or hoisted');
end;

{ Значение за интерфейсом: вызов идёт через таблицу, тело неизвестно. }
procedure StageInterfaceCall(Carrier: TResidentCarrier);
var
  State: UInt64;
  Dial: IOpaqueDial;
  I, Start: Integer;
  Live, Mirror, Shadow: Int64;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 17 + 4);
  Start := 3 + Integer(ResidentNext(State) and 7);

  Dial := TOpaqueDial.Create(Start);
  Live := 0;
  for I := 1 to 7 do
    begin
      Live := Live + Int64(I) * Dial.Read;
      if I <= 3 then
        Dial.Turn(4);
    end;
  Dial := nil;

  Shadow := Start;
  Mirror := 0;
  for I := 1 to 7 do
    begin
      Mirror := Mirror + Int64(I) * Shadow;
      if I <= 3 then
        Shadow := Shadow + 4;
    end;

  Carrier.Feed(UInt64(Live));
  Carrier.Feed(UInt64(Mirror));
  Carrier.Claim(Live = Mirror, 'opaque: value behind an interface treated as invariant');
end;

{ Процедурная переменная: адрес известен только в рантайме. }
procedure StageProcVar(Carrier: TResidentCarrier);
var
  State: UInt64;
  Bump: TOpaqueBumper;
  I, Start: Integer;
  Live, Mirror, Shadow: Int64;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 19 + 6);
  Start := 6 + Integer(ResidentNext(State) and 7);
  Bump := @AcrossBump32;

  AcrossEnter;
  try
    AcrossSet32(Start);
    Live := 0;
    for I := 1 to 6 do
      begin
        Live := Live + Int64(I) * AcrossI32;
        if I <> 4 then
          Bump(2);
      end;
  finally
    AcrossLeave;
  end;

  Shadow := Start;
  Mirror := 0;
  for I := 1 to 6 do
    begin
      Mirror := Mirror + Int64(I) * Shadow;
      if I <> 4 then
        Shadow := Shadow + 2;
    end;

  Carrier.Feed(UInt64(Live));
  Carrier.Feed(UInt64(Mirror));
  Carrier.Claim(Live = Mirror, 'opaque: write through a procedure variable lost');
end;

{ Замыкание держит переменную, а не её значение, и меняет именно её. }
procedure StageClosure(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, Start, Held: Integer;
  Live, Mirror, Shadow: Int64;
  Turn: TProc;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 23 + 8);
  Start := 2 + Integer(ResidentNext(State) and 7);
  Held := Start;

  Turn := procedure
    begin
      Held := Held + 5;
    end;

  Live := 0;
  for I := 1 to 6 do
    begin
      Live := Live + Int64(I) * Held;
      if (I mod 2) = 1 then
        Turn();
    end;
  Turn := nil;

  Shadow := Start;
  Mirror := 0;
  for I := 1 to 6 do
    begin
      Mirror := Mirror + Int64(I) * Shadow;
      if (I mod 2) = 1 then
        Shadow := Shadow + 5;
    end;

  Carrier.Feed(UInt64(Live));
  Carrier.Feed(UInt64(Mirror));
  Carrier.Claim(Live = Mirror, 'opaque: closure changed a captured variable unseen');
end;

{ Ссылочный параметр, за которым стоит чужой глобал. По сигнатуре не отличить
  от собственного локала вызывающего. }
procedure StageVarParamAlias(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, Start: Integer;
  Live, Mirror, Shadow: Int64;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 29 + 11);
  Start := 7 + Integer(ResidentNext(State) and 7);

  AcrossEnter;
  try
    AcrossSet32(Start);
    Live := 0;
    for I := 1 to 6 do
      begin
        Live := Live + Int64(I) * AcrossI32;
        AcrossBumpVia(AcrossI32, 1);
      end;
  finally
    AcrossLeave;
  end;

  Shadow := Start;
  Mirror := 0;
  for I := 1 to 6 do
    begin
      Mirror := Mirror + Int64(I) * Shadow;
      Shadow := Shadow + 1;
    end;

  Carrier.Feed(UInt64(Live));
  Carrier.Feed(UInt64(Mirror));
  Carrier.Claim(Live = Mirror, 'opaque: write through a var parameter aliasing a global lost');
end;

{ Два имени на один буфер. Динамический массив присваивается ссылкой, поэтому
  запись через одно имя обязана быть видна через другое. }
procedure StageArrayAlias(Carrier: TResidentCarrier);
var
  State: UInt64;
  First, Second: TArray<Int64>;
  I, Start: Integer;
  Live, Mirror: Int64;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 31 + 13);
  Start := Integer(ResidentNext(State) and 15);

  SetLength(First, 8);
  for I := 0 to High(First) do
    First[I] := Int64(Start + I);
  Second := First;

  Live := 0;
  for I := 0 to High(First) do
    begin
      Live := Live + First[I];
      Second[I] := Second[I] + 10;
      Live := Live + First[I];
    end;

  Mirror := 0;
  for I := 0 to 7 do
    Mirror := Mirror + Int64(Start + I) + Int64(Start + I) + 10;

  Carrier.Feed(UInt64(Live));
  Carrier.Feed(UInt64(Mirror));
  Carrier.Claim(Live = Mirror, 'opaque: two names for one buffer read as two buffers');
  Carrier.Claim(First[0] = Second[0], 'opaque: aliased arrays drifted apart');

  First := nil;
  Second := nil;
end;

{ Таблица, которую переписывает тот же цикл, что её читает. }
procedure StageTableSelfWrite(Carrier: TResidentCarrier);
var
  State: UInt64;
  Table: array[0 .. 15] of Int64;
  Shadow: array[0 .. 15] of Int64;
  I, Start: Integer;
  Live, Mirror: Int64;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 37 + 17);
  Start := Integer(ResidentNext(State) and 7);
  for I := 0 to High(Table) do
    begin
      Table[I] := Int64(Start + I * 3);
      Shadow[I] := Table[I];
    end;

  Live := 0;
  for I := 0 to 14 do
    begin
      Live := Live + Table[I and 15];
      Table[(I + 1) and 15] := Table[(I + 1) and 15] + Table[I and 15];
    end;

  Mirror := 0;
  for I := 0 to 14 do
    begin
      Mirror := Mirror + Shadow[I and 15];
      Shadow[(I + 1) and 15] := Shadow[(I + 1) and 15] + Shadow[I and 15];
    end;

  Carrier.Feed(UInt64(Live));
  Carrier.Feed(UInt64(Mirror));
  Carrier.Claim(Live = Mirror, 'opaque: self-modified table read from a stale copy');
end;

{ Запись по указателю в собственный локал: адрес взят, значит рассуждать о
  переменной как о неизменной больше нельзя. }
procedure StagePointerWrite(Carrier: TResidentCarrier);
var
  State: UInt64;
  Value, I, Start: Integer;
  Hook: PInteger;
  Live, Mirror, Shadow: Int64;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 41 + 19);
  Start := 3 + Integer(ResidentNext(State) and 7);
  Value := Start;
  Hook := @Value;

  Live := 0;
  for I := 1 to 6 do
    begin
      Live := Live + Int64(I) * Value;
      if I < 4 then
        Hook^ := Hook^ + 6;
    end;

  Shadow := Start;
  Mirror := 0;
  for I := 1 to 6 do
    begin
      Mirror := Mirror + Int64(I) * Shadow;
      if I < 4 then
        Shadow := Shadow + 6;
    end;

  Carrier.Feed(UInt64(Live));
  Carrier.Feed(UInt64(Mirror));
  Carrier.Claim(Live = Mirror, 'opaque: write through a pointer to a local lost');
end;

{ Вложенная процедура пишет в кадр родителя. }
procedure StageParentFrame(Carrier: TResidentCarrier);
var
  State: UInt64;
  Held, I, Start: Integer;
  Live, Mirror, Shadow: Int64;

  procedure TurnParent;
  begin
    Held := Held + 4;
  end;

begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 43 + 23);
  Start := 5 + Integer(ResidentNext(State) and 7);
  Held := Start;

  Live := 0;
  for I := 1 to 7 do
    begin
      Live := Live + Int64(I) * Held;
      if (I and 2) = 0 then
        TurnParent;
    end;

  Shadow := Start;
  Mirror := 0;
  for I := 1 to 7 do
    begin
      Mirror := Mirror + Int64(I) * Shadow;
      if (I and 2) = 0 then
        Shadow := Shadow + 4;
    end;

  Carrier.Feed(UInt64(Live));
  Carrier.Feed(UInt64(Mirror));
  Carrier.Claim(Live = Mirror, 'opaque: nested routine wrote the parent frame unseen');
end;

{ Строка, растущая в соседнем юните: длина обязана читаться заново. }
procedure StageTextLength(Carrier: TResidentCarrier);
var
  I: Integer;
  Live, Mirror: Int64;
begin
  AcrossEnter;
  try
    AcrossText := '';
    Live := 0;
    for I := 1 to 8 do
      begin
        Live := Live + Length(AcrossText);
        AcrossGrowText('ab');
      end;
    AcrossText := '';
  finally
    AcrossLeave;
  end;

  Mirror := 0;
  for I := 1 to 8 do
    Mirror := Mirror + (I - 1) * 2;

  Carrier.Feed(UInt64(Live));
  Carrier.Feed(UInt64(Mirror));
  Carrier.Claim(Live = Mirror, 'opaque: string length cached across a cross-unit append');
end;

{ Счётчик, живущий столько же, сколько программа: его меняет вызов, а читает
  выражение рядом. }
procedure StageSharedCounter(Carrier: TResidentCarrier);
var
  I, Base: Integer;
  Live, Mirror: Int64;

  procedure Tick;
  begin
    Inc(SharedTicks);
  end;

begin
  AcrossEnter;
  try
    SharedTicks := 0;
    Base := SharedTicks;
    Live := 0;
    for I := 1 to 6 do
      begin
        Live := Live + Int64(I) * (SharedTicks - Base);
        Tick;
      end;
    SharedTicks := 0;
  finally
    AcrossLeave;
  end;

  Mirror := 0;
  for I := 1 to 6 do
    Mirror := Mirror + Int64(I) * (I - 1);

  Carrier.Feed(UInt64(Live));
  Carrier.Feed(UInt64(Mirror));
  Carrier.Claim(Live = Mirror, 'opaque: unit-wide counter read as invariant');
end;

initialization
  ResidentRegisterStage('opaque-array-alias', @StageArrayAlias);
  ResidentRegisterStage('opaque-closure', @StageClosure);
  ResidentRegisterStage('opaque-cross-unit-conditional', @StageCrossUnitConditional);
  ResidentRegisterStage('opaque-cross-unit-global', @StageCrossUnitGlobal);
  ResidentRegisterStage('opaque-cross-unit-table', @StageCrossUnitTable);
  ResidentRegisterStage('opaque-interface-call', @StageInterfaceCall);
  ResidentRegisterStage('opaque-object-field', @StageObjectField);
  ResidentRegisterStage('opaque-parent-frame', @StageParentFrame);
  ResidentRegisterStage('opaque-pointer-write', @StagePointerWrite);
  ResidentRegisterStage('opaque-procvar', @StageProcVar);
  ResidentRegisterStage('opaque-shared-counter', @StageSharedCounter);
  ResidentRegisterStage('opaque-table-self-write', @StageTableSelfWrite);
  ResidentRegisterStage('opaque-text-length', @StageTextLength);
  ResidentRegisterStage('opaque-var-param-alias', @StageVarParamAlias);
  ResidentRegisterStage('opaque-virtual-call', @StageVirtualCall);

end.
