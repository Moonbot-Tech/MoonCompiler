unit resident_mesh;

{ Семейство `mesh` — машина, у которой каждый шаг выбирается по-своему.

  Проверять по отдельности, работает ли виртуальный вызов, замыкание,
  интерфейс и обработчик исключения, смысла мало: каждый из них работает.
  Ломается сочетание — когда решение о следующем шаге принимается виртуальным
  вызовом, значение для него готовит замыкание, поправку вносит обработчик, а
  владение объектом переходит по дороге. Оптимизатору тут нечего доказать
  наверняка, и он либо оставляет всё как есть, либо ошибается.

  Устройство. Есть узлы четырёх пород, у каждой свой шаг и своё правило
  перехода. Значение ходит по сети сотни шагов: узел считает, узел решает, куда
  дальше, часть переходов идёт через интерфейс, часть — через хранимое
  замыкание, часть — через процедурную переменную. Некоторые узлы на некоторых
  значениях бросают исключение, и оно — не сбой, а часть маршрута: обработчик
  правит значение и продолжает ход.

  Оракул — та же прогулка, посчитанная плоско: без объектов, без вызовов, одним
  циклом с теми же правилами. Он повторяет не код, а **правила**, поэтому
  совпасть две реализации могут только если обе верны. И он же отвечает на
  вопрос, зачем всё это: если диспетчеризация уехала на один узел, плоский счёт
  разойдётся с сетевым сразу, а не когда-нибудь. }

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
  SysUtils, resident_core;

implementation

type
  EMeshTurn = class(Exception)
  private
    FValue: Int64;
  public
    constructor Create(AValue: Int64); reintroduce;
    property Value: Int64 read FValue;
  end;

  TMeshNode = class;

  IMeshStep = interface
    ['{4D5A0003-0000-0000-0000-00004D455348}']
    function Apply(const Value: Int64): Int64;
  end;

  TMeshPick = function(const Value: Int64; Count: Integer): Integer;

  { Узел сети. Шаг и переход виртуальны, поэтому за одной ссылкой стоит
    четыре разных поведения. }
  TMeshNode = class(TInterfacedObject, IMeshStep)
  private
    FIndex: Integer;
  public
    constructor Create(AIndex: Integer);
    function Apply(const Value: Int64): Int64; virtual;
    function Next(const Value: Int64; Count: Integer): Integer; virtual;
    property Index: Integer read FIndex;
  end;

  TMeshAdder = class(TMeshNode)
  public
    function Apply(const Value: Int64): Int64; override;
    function Next(const Value: Int64; Count: Integer): Integer; override;
  end;

  TMeshScaler = class(TMeshNode)
  public
    function Apply(const Value: Int64): Int64; override;
    function Next(const Value: Int64; Count: Integer): Integer; override;
  end;

  TMeshFolder = class(TMeshNode)
  public
    function Apply(const Value: Int64): Int64; override;
    function Next(const Value: Int64; Count: Integer): Integer; override;
  end;

  { Этот узел на части значений не считает, а бросает: продолжение маршрута
    лежит через обработчик. }
  TMeshBreaker = class(TMeshNode)
  public
    function Apply(const Value: Int64): Int64; override;
    function Next(const Value: Int64; Count: Integer): Integer; override;
  end;

constructor EMeshTurn.Create(AValue: Int64);
begin
  inherited Create('resident: mesh turn');
  FValue := AValue;
end;

constructor TMeshNode.Create(AIndex: Integer);
begin
  inherited Create;
  FIndex := AIndex;
end;

function TMeshNode.Apply(const Value: Int64): Int64;
begin
  Result := Value + 1;
end;

function TMeshNode.Next(const Value: Int64; Count: Integer): Integer;
begin
  Result := (FIndex + 1) mod Count;
end;

function TMeshAdder.Apply(const Value: Int64): Int64;
begin
  Result := Value + FIndex + 3;
end;

function TMeshAdder.Next(const Value: Int64; Count: Integer): Integer;
begin
  Result := Integer((Value + 2) and 7) mod Count;
end;

function TMeshScaler.Apply(const Value: Int64): Int64;
begin
  Result := Value * 3 - FIndex;
end;

function TMeshScaler.Next(const Value: Int64; Count: Integer): Integer;
begin
  Result := (FIndex + 3) mod Count;
end;

function TMeshFolder.Apply(const Value: Int64): Int64;
begin
  Result := (Value xor (Value shr 5)) + 11;
end;

function TMeshFolder.Next(const Value: Int64; Count: Integer): Integer;
begin
  Result := Integer((Value shr 3) and 3) mod Count;
end;

function TMeshBreaker.Apply(const Value: Int64): Int64;
begin
  if (Value and 3) = 1 then
    raise EMeshTurn.Create(Value * 2 + 7);
  Result := Value - FIndex - 1;
end;

function TMeshBreaker.Next(const Value: Int64; Count: Integer): Integer;
begin
  Result := Integer((Value + 5) and 7) mod Count;
end;

{ Плоское повторение правил: те же формулы, но ни одного вызова по таблице.
  Порода узла определяется его номером — так же, как при постройке сети. }
function FlatApply(NodeIndex: Integer; const Value: Int64; out Thrown: Boolean): Int64;
begin
  Thrown := False;
  case NodeIndex mod 4 of
    0: Result := Value + NodeIndex + 3;
    1: Result := Value * 3 - NodeIndex;
    2: Result := (Value xor (Value shr 5)) + 11;
  else
    if (Value and 3) = 1 then
      begin
        Thrown := True;
        Result := Value * 2 + 7;
      end
    else
      Result := Value - NodeIndex - 1;
  end;
end;

function FlatNext(NodeIndex: Integer; const Value: Int64; Count: Integer): Integer;
begin
  case NodeIndex mod 4 of
    0: Result := Integer((Value + 2) and 7) mod Count;
    1: Result := (NodeIndex + 3) mod Count;
    2: Result := Integer((Value shr 3) and 3) mod Count;
  else
    Result := Integer((Value + 5) and 7) mod Count;
  end;
end;

{ Переход, общий для всех узлов. Живёт на уровне юнита не для порядка:
  процедурная переменная обычного типа не умеет держать вложенную функцию —
  той нужен кадр родителя, которого у неё при вызове не будет. }
function ChoosePlain(const Value: Int64; Count: Integer): Integer;
begin
  Result := Integer((Value + 2) and 7) mod Count;
end;

function MakeNode(Index: Integer): TMeshNode;
begin
  case Index mod 4 of
    0: Result := TMeshAdder.Create(Index);
    1: Result := TMeshScaler.Create(Index);
    2: Result := TMeshFolder.Create(Index);
  else
    Result := TMeshBreaker.Create(Index);
  end;
end;

{ Прогулка по сети: шаг считает объект, переход выбирает объект, бросок ловит
  обработчик и правит значение, не сбивая маршрут. }
procedure StageWalk(Carrier: TResidentCarrier);
var
  State: UInt64;
  Nodes: array[0 .. 7] of TMeshNode;
  I, Steps, At_, Thrown: Integer;
  Live, Flat: Int64;
  FlatAt, FlatThrown: Integer;
  Broke: Boolean;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap);
  Steps := 60 + Integer(ResidentNext(State) and 63);
  Live := Int64(ResidentNext(State) and $FFFF);
  Flat := Live;
  Thrown := 0;
  FlatThrown := 0;
  At_ := 0;
  FlatAt := 0;

  for I := 0 to High(Nodes) do
    Nodes[I] := MakeNode(I);
  try
    for I := 1 to Steps do
      begin
        try
          Live := Nodes[At_].Apply(Live);
        except
          on E: EMeshTurn do
            begin
              Inc(Thrown);
              Live := E.Value;
            end;
        end;
        At_ := Nodes[At_].Next(Live, Length(Nodes));
      end;
  finally
    for I := 0 to High(Nodes) do
      FreeAndNil(Nodes[I]);
  end;

  for I := 1 to Steps do
    begin
      Flat := FlatApply(FlatAt, Flat, Broke);
      if Broke then
        Inc(FlatThrown);
      FlatAt := FlatNext(FlatAt, Flat, 8);
    end;

  Carrier.Feed(UInt64(Live));
  Carrier.Feed(UInt64(Cardinal(Thrown)));
  Carrier.Feed(UInt64(Cardinal(At_)));
  Carrier.Claim(Live = Flat, 'mesh: walking the network disagrees with the flat rules');
  Carrier.Claim(At_ = FlatAt, 'mesh: the walk ended on a different node');
  Carrier.Claim(Thrown = FlatThrown, 'mesh: a different number of turns went through the handler');
end;

{ Та же прогулка, но шаг зовётся через интерфейс, а переход — через
  процедурную переменную. Диспетчеризация меняется, ответ — нет. }
procedure StageThroughInterface(Carrier: TResidentCarrier);
var
  State: UInt64;
  Nodes: array[0 .. 7] of TMeshNode;
  Steps: array[0 .. 7] of IMeshStep;
  I, Count, At_, Thrown: Integer;
  Live, Flat: Int64;
  FlatAt, FlatThrown: Integer;
  Broke: Boolean;
  Pick: TMeshPick;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 3 + 1);
  Count := 40 + Integer(ResidentNext(State) and 31);
  Live := Int64(ResidentNext(State) and $FFFF);
  Flat := Live;
  Thrown := 0;
  FlatThrown := 0;
  At_ := 0;
  FlatAt := 0;
  Pick := @ChoosePlain;

  for I := 0 to High(Nodes) do
    begin
      Nodes[I] := MakeNode(I);
      { Интерфейсная ссылка на тот же объект: владение теперь считается
        счётчиком, а вызов идёт по другой таблице. }
      Steps[I] := Nodes[I];
    end;
  try
    for I := 1 to Count do
      begin
        try
          Live := Steps[At_].Apply(Live);
        except
          on E: EMeshTurn do
            begin
              Inc(Thrown);
              Live := E.Value;
            end;
        end;
        { Переход общий для всех узлов и идёт через процедурную переменную. }
        At_ := Pick(Live, Length(Nodes));
      end;
  finally
    for I := 0 to High(Nodes) do
      Steps[I] := nil;
  end;

  for I := 1 to Count do
    begin
      Flat := FlatApply(FlatAt, Flat, Broke);
      if Broke then
        Inc(FlatThrown);
      FlatAt := Integer((Flat + 2) and 7) mod 8;
    end;

  Carrier.Feed(UInt64(Live));
  Carrier.Feed(UInt64(Cardinal(Thrown)));
  Carrier.Claim(Live = Flat, 'mesh: interface dispatch disagrees with the flat rules');
  Carrier.Claim(At_ = FlatAt, 'mesh: interface walk ended on a different node');
  Carrier.Claim(Thrown = FlatThrown, 'mesh: interface walk took a different number of turns');
end;

{ Шаг сети, спрятанный в замыкание: замыкание держит узел, узел держит своё
  поведение, и всё это внутри цикла с обработчиком. }
procedure StageThroughClosures(Carrier: TResidentCarrier);
var
  State: UInt64;
  Nodes: array[0 .. 7] of TMeshNode;
  Hops: array[0 .. 7] of TFunc<Int64, Int64>;
  I, Count, At_, Thrown: Integer;
  Live, Flat: Int64;
  FlatAt, FlatThrown: Integer;
  Broke: Boolean;

  { Замыкание строится фабрикой: захватывать переменную цикла нельзя, она
    к концу постройки будет одна на всех. }
  function MakeHop(Node: TMeshNode): TFunc<Int64, Int64>;
  begin
    Result := function(Value: Int64): Int64
      begin
        Result := Node.Apply(Value);
      end;
  end;

begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 5 + 2);
  Count := 40 + Integer(ResidentNext(State) and 31);
  Live := Int64(ResidentNext(State) and $FFFF);
  Flat := Live;
  Thrown := 0;
  FlatThrown := 0;
  At_ := 0;
  FlatAt := 0;

  for I := 0 to High(Nodes) do
    begin
      Nodes[I] := MakeNode(I);
      Hops[I] := MakeHop(Nodes[I]);
    end;
  try
    for I := 1 to Count do
      begin
        try
          Live := Hops[At_](Live);
        except
          on E: EMeshTurn do
            begin
              Inc(Thrown);
              Live := E.Value;
            end;
        end;
        At_ := Nodes[At_].Next(Live, Length(Nodes));
      end;
  finally
    for I := 0 to High(Nodes) do
      begin
        Hops[I] := nil;
        FreeAndNil(Nodes[I]);
      end;
  end;

  for I := 1 to Count do
    begin
      Flat := FlatApply(FlatAt, Flat, Broke);
      if Broke then
        Inc(FlatThrown);
      FlatAt := FlatNext(FlatAt, Flat, 8);
    end;

  Carrier.Feed(UInt64(Live));
  Carrier.Feed(UInt64(Cardinal(Thrown)));
  Carrier.Claim(Live = Flat, 'mesh: closure dispatch disagrees with the flat rules');
  Carrier.Claim(At_ = FlatAt, 'mesh: closure walk ended on a different node');
  Carrier.Claim(Thrown = FlatThrown, 'mesh: closure walk took a different number of turns');
end;

{ Сеть, которая перестраивается на ходу: узлы гибнут и родятся прямо во время
  прогулки, а маршрут обязан остаться тем же. }
procedure StageRebuildWhileWalking(Carrier: TResidentCarrier);
var
  State: UInt64;
  Nodes: array[0 .. 7] of TMeshNode;
  I, Count, At_, Thrown, Born, Gone: Integer;
  Live, Flat: Int64;
  FlatAt, FlatThrown: Integer;
  Broke: Boolean;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 7 + 3);
  Count := 48 + Integer(ResidentNext(State) and 31);
  Live := Int64(ResidentNext(State) and $FFFF);
  Flat := Live;
  Thrown := 0;
  FlatThrown := 0;
  At_ := 0;
  FlatAt := 0;
  Born := 0;
  Gone := 0;

  for I := 0 to High(Nodes) do
    begin
      Nodes[I] := MakeNode(I);
      Inc(Born);
    end;
  try
    for I := 1 to Count do
      begin
        try
          Live := Nodes[At_].Apply(Live);
        except
          on E: EMeshTurn do
            begin
              Inc(Thrown);
              Live := E.Value;
            end;
        end;
        var Was: Integer := At_;
        At_ := Nodes[At_].Next(Live, Length(Nodes));

        { Пройденный узел заменяется новым той же породы: поведение то же,
          объект другой. }
        if (I mod 5) = 0 then
          begin
            FreeAndNil(Nodes[Was]);
            Inc(Gone);
            Nodes[Was] := MakeNode(Was);
            Inc(Born);
          end;
      end;
  finally
    for I := 0 to High(Nodes) do
      begin
        FreeAndNil(Nodes[I]);
        Inc(Gone);
      end;
  end;

  for I := 1 to Count do
    begin
      Flat := FlatApply(FlatAt, Flat, Broke);
      if Broke then
        Inc(FlatThrown);
      FlatAt := FlatNext(FlatAt, Flat, 8);
    end;

  Carrier.Feed(UInt64(Live));
  Carrier.Feed(UInt64(Cardinal(Born)));
  Carrier.Claim(Live = Flat, 'mesh: rebuilding nodes mid-walk changed the answer');
  Carrier.Claim(At_ = FlatAt, 'mesh: rebuilt walk ended on a different node');
  Carrier.Claim(Thrown = FlatThrown, 'mesh: rebuilt walk took a different number of turns');
  Carrier.Claim(Born = Gone, 'mesh: a node was born without being buried');
end;

{ Две сети идут навстречу друг другу и обмениваются значениями: маршрут одной
  зависит от того, что насчитала другая. }
procedure StageCrossedWalks(Carrier: TResidentCarrier);
var
  State: UInt64;
  Left, Right: array[0 .. 7] of TMeshNode;
  I, Count, AtL, AtR: Integer;
  LiveL, LiveR, FlatL, FlatR: Int64;
  FlatAtL, FlatAtR: Integer;
  Broke: Boolean;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 11 + 5);
  Count := 32 + Integer(ResidentNext(State) and 31);
  LiveL := Int64(ResidentNext(State) and $FFFF);
  LiveR := Int64(ResidentNext(State) and $FFFF);
  FlatL := LiveL;
  FlatR := LiveR;
  AtL := 0;
  AtR := 3;
  FlatAtL := 0;
  FlatAtR := 3;

  for I := 0 to High(Left) do
    begin
      Left[I] := MakeNode(I);
      Right[I] := MakeNode(7 - I);
    end;
  try
    for I := 1 to Count do
      begin
        try
          LiveL := Left[AtL].Apply(LiveL);
        except
          on E: EMeshTurn do
            LiveL := E.Value;
        end;
        try
          LiveR := Right[AtR].Apply(LiveR);
        except
          on E: EMeshTurn do
            LiveR := E.Value;
        end;

        { Переход каждой сети выбирается по значению соседней. }
        AtL := Left[AtL].Next(LiveR, Length(Left));
        AtR := Right[AtR].Next(LiveL, Length(Right));
      end;
  finally
    for I := 0 to High(Left) do
      begin
        FreeAndNil(Left[I]);
        FreeAndNil(Right[I]);
      end;
  end;

  for I := 1 to Count do
    begin
      FlatL := FlatApply(FlatAtL, FlatL, Broke);
      FlatR := FlatApply(7 - FlatAtR, FlatR, Broke);
      var NextL: Integer := FlatNext(FlatAtL, FlatR, 8);
      var NextR: Integer := FlatNext(7 - FlatAtR, FlatL, 8);
      FlatAtL := NextL;
      FlatAtR := NextR;
    end;

  Carrier.Feed(UInt64(LiveL));
  Carrier.Feed(UInt64(LiveR));
  Carrier.Claim(LiveL = FlatL, 'mesh: left walk disagrees with the flat rules');
  Carrier.Claim(LiveR = FlatR, 'mesh: right walk disagrees with the flat rules');
  Carrier.Claim(AtL = FlatAtL, 'mesh: crossed walks ended on different nodes');
end;

initialization
  ResidentRegisterStage('mesh-crossed-walks', @StageCrossedWalks);
  ResidentRegisterStage('mesh-rebuild-while-walking', @StageRebuildWhileWalking);
  ResidentRegisterStage('mesh-through-closures', @StageThroughClosures);
  ResidentRegisterStage('mesh-through-interface', @StageThroughInterface);
  ResidentRegisterStage('mesh-walk', @StageWalk);

end.
