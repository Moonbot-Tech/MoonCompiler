unit resident_pipe;

{ Семейство `pipe` — конвейер, где каждое звено вызывается по-своему.

  Значение проходит через восемь звеньев подряд. Считают они простую
  арифметику — важно не что они считают, а **как до них добираются**: обычный
  вызов, вставленное тело, виртуальная таблица, интерфейсная таблица,
  замыкание с захваченным состоянием, процедурная переменная, метод класса,
  вложенная процедура через ссылочный параметр. Восемь механизмов подряд, и
  порядок их каждый раз новый — его выбирает перестановка от сида носителя.

  Смысл именно в стыках. Каждый механизм по отдельности проверен где угодно;
  ломается место, где результат одного способа вызова становится аргументом
  другого, а компилятор пытается срастить их в одно. Перестановка не даёт ему
  запомнить конвейер целиком: порядок известен только при счёте, значит
  свернуть цепочку заранее нельзя, а выполнить — можно только честно.

  Оракул плоский: те же восемь формул в одном `case`, тот же порядок, ни одной
  косвенности. Он повторяет правила, а не код, поэтому совпасть с конвейером
  может только если оба верны. }

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

const
  Links = 8;

type
  EPipeBreak = class(Exception)
  private
    FValue: Int64;
  public
    constructor Create(AValue: Int64); reintroduce;
    property Value: Int64 read FValue;
  end;

  IPipeLink = interface
    ['{4D5A0004-0000-0000-0000-000050495045}']
    function Pass(const Value: Int64): Int64;
  end;

  TPipeProc = function(const Value: Int64): Int64;

  TPipeWorker = class(TInterfacedObject, IPipeLink)
  public
    { Виртуальное звено. }
    function Turn(const Value: Int64): Int64; virtual;
    { Интерфейсное звено — другая таблица, то же тело искать не будем. }
    function Pass(const Value: Int64): Int64;
    { Звено, живущее у класса, а не у объекта. }
    class function Stamp(const Value: Int64): Int64;
  end;

  TPipeTwist = class(TPipeWorker)
  public
    function Turn(const Value: Int64): Int64; override;
  end;

constructor EPipeBreak.Create(AValue: Int64);
begin
  inherited Create('resident: pipe break');
  FValue := AValue;
end;

function TPipeWorker.Turn(const Value: Int64): Int64;
begin
  Result := Value + 17;
end;

function TPipeTwist.Turn(const Value: Int64): Int64;
begin
  Result := Value * 2 - 3;
end;

function TPipeWorker.Pass(const Value: Int64): Int64;
begin
  Result := (Value xor 21) + 4;
end;

class function TPipeWorker.Stamp(const Value: Int64): Int64;
begin
  Result := Value - 9;
end;

{ Обычная функция уровня юнита. }
function LinkPlain(const Value: Int64): Int64;
begin
  Result := Value * 3 + 1;
end;

{ Вставляемое тело. }
function LinkInline(const Value: Int64): Int64; inline;
begin
  Result := (Value shr 2) + Value + 5;
end;

{ Тело для процедурной переменной. }
function LinkThroughVar(const Value: Int64): Int64;
begin
  Result := (Value and $FFFF) * 7 - 2;
end;

{ Плоское повторение всех восьми правил. Ни одной косвенности. }
function FlatLink(Kind: Integer; const Value: Int64): Int64;
begin
  case Kind of
    0: Result := Value * 3 + 1;
    1: Result := (Value shr 2) + Value + 5;
    2: Result := Value * 2 - 3;
    3: Result := (Value xor 21) + 4;
    4: Result := Value + 31;
    5: Result := (Value and $FFFF) * 7 - 2;
    6: Result := Value - 9;
  else
    Result := Value xor (Value shr 7);
  end;
end;

{ Перестановка звеньев: каждое встречается ровно раз. }
procedure BuildOrder(var Order: array of Integer; var State: UInt64);
var
  I, J, Spare: Integer;
begin
  for I := 0 to High(Order) do
    Order[I] := I;
  for I := High(Order) downto 1 do
    begin
      J := Integer(ResidentNext(State) mod UInt64(I + 1));
      Spare := Order[I];
      Order[I] := Order[J];
      Order[J] := Spare;
    end;
end;

{ Один проход конвейера: порядок звеньев известен только при счёте. }
procedure StagePermuted(Carrier: TResidentCarrier);
var
  State: UInt64;
  Order: array[0 .. Links - 1] of Integer;
  Twist: TPipeWorker;
  AsLink: IPipeLink;
  Hop: TPipeProc;
  Captured: Int64;
  Closure: TFunc<Int64, Int64>;
  I, Seen: Integer;
  Live, Flat: Int64;

  { Вложенная процедура: правит значение через ссылочный параметр, добираясь
    до кадра родителя за прибавкой. }
  procedure Nested(var Value: Int64);
  begin
    Value := Value xor (Value shr 7);
    Inc(Seen);
  end;

begin
  State := Carrier.Seed xor UInt64(Carrier.Lap);
  BuildOrder(Order, State);
  Live := Int64(ResidentNext(State) and $FFFF);
  Flat := Live;
  Seen := 0;
  Captured := 31;

  Twist := TPipeTwist.Create;
  AsLink := TPipeWorker.Create;
  Hop := @LinkThroughVar;
  Closure := function(Value: Int64): Int64
    begin
      Result := Value + Captured;
    end;
  try
    for I := 0 to High(Order) do
      case Order[I] of
        0: Live := LinkPlain(Live);
        1: Live := LinkInline(Live);
        2: Live := Twist.Turn(Live);
        3: Live := AsLink.Pass(Live);
        4: Live := Closure(Live);
        5: Live := Hop(Live);
        6: Live := TPipeWorker.Stamp(Live);
      else
        Nested(Live);
      end;
  finally
    Closure := nil;
    AsLink := nil;
    FreeAndNil(Twist);
  end;

  for I := 0 to High(Order) do
    Flat := FlatLink(Order[I], Flat);

  Carrier.Feed(UInt64(Live));
  for I := 0 to High(Order) do
    Carrier.Feed(UInt64(Cardinal(Order[I])));
  Carrier.Claim(Live = Flat, 'pipe: chain of eight call mechanisms disagrees with the flat rules');
  Carrier.Claim(Seen = 1, 'pipe: the nested link ran the wrong number of times');
end;

{ Конвейер, пройденный много раз подряд: композиция композиции. }
procedure StageRepeated(Carrier: TResidentCarrier);
var
  State: UInt64;
  Order: array[0 .. Links - 1] of Integer;
  Twist: TPipeWorker;
  AsLink: IPipeLink;
  Hop: TPipeProc;
  Closure: TFunc<Int64, Int64>;
  Captured: Int64;
  I, J, Rounds, Seen: Integer;
  Live, Flat: Int64;

  procedure Nested(var Value: Int64);
  begin
    Value := Value xor (Value shr 7);
    Inc(Seen);
  end;

begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 3 + 1);
  BuildOrder(Order, State);
  Rounds := 5 + Integer(ResidentNext(State) and 7);
  Live := Int64(ResidentNext(State) and $FFFF);
  Flat := Live;
  Seen := 0;
  Captured := 31;

  Twist := TPipeTwist.Create;
  AsLink := TPipeWorker.Create;
  Hop := @LinkThroughVar;
  Closure := function(Value: Int64): Int64
    begin
      Result := Value + Captured;
    end;
  try
    for J := 1 to Rounds do
      for I := 0 to High(Order) do
        case Order[I] of
          0: Live := LinkPlain(Live);
          1: Live := LinkInline(Live);
          2: Live := Twist.Turn(Live);
          3: Live := AsLink.Pass(Live);
          4: Live := Closure(Live);
          5: Live := Hop(Live);
          6: Live := TPipeWorker.Stamp(Live);
        else
          Nested(Live);
        end;
  finally
    Closure := nil;
    AsLink := nil;
    FreeAndNil(Twist);
  end;

  for J := 1 to Rounds do
    for I := 0 to High(Order) do
      Flat := FlatLink(Order[I], Flat);

  Carrier.Feed(UInt64(Live));
  Carrier.Feed(UInt64(Cardinal(Rounds)));
  Carrier.Claim(Live = Flat, 'pipe: repeated pipeline drifted from the flat rules');
  Carrier.Claim(Seen = Rounds, 'pipe: the nested link ran the wrong number of times');
end;

{ Часть звеньев на части значений бросает: продолжение конвейера идёт через
  обработчик, и место в цепочке при этом не теряется. }
procedure StageWithFaults(Carrier: TResidentCarrier);
var
  State: UInt64;
  Order: array[0 .. Links - 1] of Integer;
  Twist: TPipeWorker;
  AsLink: IPipeLink;
  I, J, Rounds, Thrown, FlatThrown: Integer;
  Live, Flat: Int64;

  function Risky(Kind: Integer; const Value: Int64): Int64;
  begin
    if (Kind = 2) and ((Value and 7) = 3) then
      raise EPipeBreak.Create(Value * 5 + 1);
    Result := FlatLink(Kind, Value);
  end;

begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 5 + 2);
  BuildOrder(Order, State);
  Rounds := 6 + Integer(ResidentNext(State) and 7);
  Live := Int64(ResidentNext(State) and $FFFF);
  Flat := Live;
  Thrown := 0;
  FlatThrown := 0;

  Twist := TPipeTwist.Create;
  AsLink := TPipeWorker.Create;
  try
    for J := 1 to Rounds do
      for I := 0 to High(Order) do
        try
          case Order[I] of
            2: Live := Risky(2, Live);
            3: Live := AsLink.Pass(Live);
          else
            Live := FlatLink(Order[I], Live);
          end;
        except
          on E: EPipeBreak do
            begin
              Inc(Thrown);
              Live := E.Value;
            end;
        end;
  finally
    AsLink := nil;
    FreeAndNil(Twist);
  end;

  for J := 1 to Rounds do
    for I := 0 to High(Order) do
      if (Order[I] = 2) and ((Flat and 7) = 3) then
        begin
          Inc(FlatThrown);
          Flat := Flat * 5 + 1;
        end
      else
        Flat := FlatLink(Order[I], Flat);

  Carrier.Feed(UInt64(Live));
  Carrier.Feed(UInt64(Cardinal(Thrown)));
  Carrier.Claim(Live = Flat, 'pipe: pipeline with faults drifted from the flat rules');
  Carrier.Claim(Thrown = FlatThrown, 'pipe: a different number of links went through the handler');
end;

{ Тот же конвейер, записанный вложенными вызовами в одном выражении — и он же
  по шагам. Порядок звеньев здесь постоянный, потому что записать
  перестановку одним выражением нельзя. }
procedure StageOneExpression(Carrier: TResidentCarrier);
var
  State: UInt64;
  Twist: TPipeWorker;
  AsLink: IPipeLink;
  Hop: TPipeProc;
  Closure: TFunc<Int64, Int64>;
  Captured: Int64;
  Start, ByExpression, BySteps, Flat: Int64;
  I: Integer;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 7 + 3);
  Start := Int64(ResidentNext(State) and $FFFF);
  Captured := 31;

  Twist := TPipeTwist.Create;
  AsLink := TPipeWorker.Create;
  Hop := @LinkThroughVar;
  Closure := function(Value: Int64): Int64
    begin
      Result := Value + Captured;
    end;
  try
    { Всё одним выражением: результат каждого механизма сразу становится
      аргументом следующего. }
    ByExpression := TPipeWorker.Stamp(Hop(Closure(AsLink.Pass(Twist.Turn(
      LinkInline(LinkPlain(Start)))))));

    { То же по шагам. }
    BySteps := Start;
    BySteps := LinkPlain(BySteps);
    BySteps := LinkInline(BySteps);
    BySteps := Twist.Turn(BySteps);
    BySteps := AsLink.Pass(BySteps);
    BySteps := Closure(BySteps);
    BySteps := Hop(BySteps);
    BySteps := TPipeWorker.Stamp(BySteps);
  finally
    Closure := nil;
    AsLink := nil;
    FreeAndNil(Twist);
  end;

  Flat := Start;
  for I := 0 to 6 do
    Flat := FlatLink(I, Flat);

  Carrier.Feed(UInt64(ByExpression));
  Carrier.Claim(ByExpression = BySteps, 'pipe: one expression disagrees with the same chain by steps');
  Carrier.Claim(ByExpression = Flat, 'pipe: nested call chain disagrees with the flat rules');
end;

{ Звено, внутри которого крутится тот же конвейер: косвенность на косвенности.
  Считается это только честно, целиком. }
procedure StageNestedPipeline(Carrier: TResidentCarrier);
var
  State: UInt64;
  Order: array[0 .. Links - 1] of Integer;
  I, J, Depth: Integer;
  Live, Flat: Int64;
  Twist: TPipeWorker;

  function RunOnce(const Value: Int64): Int64;
  var
    K: Integer;
  begin
    Result := Value;
    for K := 0 to High(Order) do
      Result := FlatLink(Order[K], Result);
  end;

  function RunDeep(const Value: Int64; Level: Integer): Int64;
  begin
    if Level = 0 then
      Result := Twist.Turn(Value)
    else
      Result := RunOnce(RunDeep(Value, Level - 1));
  end;

begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 11 + 5);
  BuildOrder(Order, State);
  Depth := 3 + Integer(ResidentNext(State) and 3);
  Live := Int64(ResidentNext(State) and $FFFF);

  Twist := TPipeTwist.Create;
  try
    Live := RunDeep(Live, Depth);
  finally
    FreeAndNil(Twist);
  end;

  { Плоско: сперва самый глубокий уровень, потом столько же проходов
    конвейера. Поток чисел проигрывается заново с той же точки, поэтому
    порядок звеньев и начальное значение получаются те же. }
  var Mirror: UInt64 := Carrier.Seed xor UInt64(Carrier.Lap * 11 + 5);
  var MirrorOrder: array[0 .. Links - 1] of Integer;
  BuildOrder(MirrorOrder, Mirror);
  ResidentNext(Mirror);
  Flat := Int64(ResidentNext(Mirror) and $FFFF);
  Flat := Flat * 2 - 3;
  for J := 1 to Depth do
    for I := 0 to High(MirrorOrder) do
      Flat := FlatLink(MirrorOrder[I], Flat);

  Carrier.Feed(UInt64(Live));
  Carrier.Feed(UInt64(Cardinal(Depth)));
  Carrier.Claim(Live = Flat, 'pipe: pipeline inside a link disagrees with the flat rules');
end;

initialization
  ResidentRegisterStage('pipe-nested-pipeline', @StageNestedPipeline);
  ResidentRegisterStage('pipe-one-expression', @StageOneExpression);
  ResidentRegisterStage('pipe-permuted', @StagePermuted);
  ResidentRegisterStage('pipe-repeated', @StageRepeated);
  ResidentRegisterStage('pipe-with-faults', @StageWithFaults);

end.
