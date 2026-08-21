unit resident_flow;

{ Семейство `flow` — управление, исключения и раскрутка.

  Здесь проверяется не результат, а путь: какие блоки выполнились, в каком
  порядке, что успело умереть при раскрутке стека и добралась ли программа до
  того места, куда обязана была добраться.

  Способ наблюдения один и тот же везде: стадия ведёт локальный след — число,
  в которое каждая пройденная точка вписывает свою метку по порядку. След
  детерминирован, потому что весь путь лежит внутри одного вызова одного
  потока, и никакая чужая стадия в него не вмешивается.

  Утверждений `Assert` здесь нет ни одного, и это не случайность: сборка бывает
  и с выключенной проверкой утверждений, тогда поведение изменилось бы от ключа
  сборки, а не от кода — и стенд сравнения режимов увидел бы расхождение,
  которого никто не делал.

  Короткое замыкание логических операций включено явно, а не унаследовано от
  настроек драйвера: стадия, проверяющая, что вторая половина условия не
  вычислялась, обязана сама задать правило, по которому это верно. }

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch anonymousfunctions}
  {$modeswitch functionreferences}
  {$modeswitch INLINEVARS}
  {$goto on}
{$endif}
{$Q-}{$R-}{$B-}

interface

uses
  SysUtils, Classes, Generics.Collections, resident_core;

implementation

type
  { Своя иерархия: `on E:` обязан выбирать самый близкий подходящий обработчик,
    а не первый попавшийся. }
  EResidentBase = class(Exception)
  private
    FCode: Integer;
  public
    constructor Create(const Msg: string; ACode: Integer); reintroduce;
    property Code: Integer read FCode;
  end;

  EResidentLeft = class(EResidentBase);
  EResidentRight = class(EResidentBase);
  EResidentDeep = class(EResidentLeft);

  { Объект, чей конструктор бросает после того, как часть работы уже сделана.
    Договор языка: деструктор всё равно будет позван, и заведённое внутри
    обязано быть похоронено. }
  TResidentHalfBuilt = class
  private
    FInner: TStringList;
    FTally: PResidentTally;
  public
    constructor Create(ATally: PResidentTally; Refuse: Boolean);
    destructor Destroy; override;
  end;

  TResidentFlowPocket = class(TResidentPocket)
  private
    FTrail: Int64;
    FRounds: Int64;
  end;

constructor EResidentBase.Create(const Msg: string; ACode: Integer);
begin
  inherited Create(Msg);
  FCode := ACode;
end;

constructor TResidentHalfBuilt.Create(ATally: PResidentTally; Refuse: Boolean);
begin
  inherited Create;
  FTally := ATally;
  if FTally <> nil then
    Inc(FTally^.Born);
  FInner := TStringList.Create;
  FInner.Add('half');
  if Refuse then
    raise EResidentLeft.Create('resident: ctor gave up', 7);
end;

destructor TResidentHalfBuilt.Destroy;
begin
  FInner.Free;
  if FTally <> nil then
    Inc(FTally^.Gone);
  inherited Destroy;
end;

{ След пути: каждая пройденная точка вписывает свою метку в хвост числа. }
procedure Mark(var Trail: Int64; Step: Integer); inline;
begin
  Trail := Trail * 10 + Step;
end;

{ Вложенные `finally`: внутренний обязан отработать раньше внешнего. }
procedure StageFinallyOrder(Carrier: TResidentCarrier);
var
  Trail: Int64;
begin
  Trail := 0;
  try
    Mark(Trail, 1);
    try
      Mark(Trail, 2);
      try
        Mark(Trail, 3);
      finally
        Mark(Trail, 4);
      end;
      Mark(Trail, 5);
    finally
      Mark(Trail, 6);
    end;
    Mark(Trail, 7);
  finally
    Mark(Trail, 8);
  end;
  Carrier.Feed(UInt64(Trail));
  Carrier.Feed(UInt64(Ord(Trail = 12345678)));
end;

{ Выход из середины: `Exit` не имеет права проскочить мимо `finally`. }
procedure StageExitThroughFinally(Carrier: TResidentCarrier);
var
  Trail: Int64;

  procedure Walk(var T: Int64; Leave: Boolean);
  begin
    try
      Mark(T, 1);
      try
        Mark(T, 2);
        if Leave then
          Exit;
        Mark(T, 3);
      finally
        Mark(T, 4);
      end;
      Mark(T, 5);
    finally
      Mark(T, 6);
    end;
  end;

begin
  Trail := 0;
  Walk(Trail, False);
  Carrier.Feed(UInt64(Trail));
  Carrier.Feed(UInt64(Ord(Trail = 123456)));

  Trail := 0;
  Walk(Trail, True);
  Carrier.Feed(UInt64(Trail));
  { Уход из середины: третья и пятая точки пропущены, оба `finally` пройдены. }
  Carrier.Feed(UInt64(Ord(Trail = 1246)));
end;

{ Раскрутка исключением: `finally` обязаны отработать снизу вверх, а обработчик
  — поймать то, что бросили. }
procedure StageUnwindOrder(Carrier: TResidentCarrier);
var
  Trail: Int64;
begin
  Trail := 0;
  try
    try
      Mark(Trail, 1);
      try
        Mark(Trail, 2);
        raise EResidentLeft.Create('resident: unwind', 3);
      finally
        Mark(Trail, 4);
      end;
    finally
      Mark(Trail, 5);
    end;
  except
    on E: EResidentBase do
    begin
      Mark(Trail, 6);
      Carrier.Feed(UInt64(Cardinal(E.Code)));
    end;
  end;
  Carrier.Feed(UInt64(Trail));
  Carrier.Feed(UInt64(Ord(Trail = 12456)));
end;

{ Выбор обработчика: обязан сработать самый близкий по иерархии, а не первый
  подходящий по порядку записи. }
procedure StageHandlerChoice(Carrier: TResidentCarrier);

  function CatchOf(Which: Integer): Integer;
  begin
    Result := 0;
    try
      case Which of
        0: raise EResidentDeep.Create('deep', 10);
        1: raise EResidentLeft.Create('left', 20);
        2: raise EResidentRight.Create('right', 30);
      else
        raise EResidentBase.Create('base', 40);
      end;
    except
      on E: EResidentDeep do
        Result := 1;
      on E: EResidentLeft do
        Result := 2;
      on E: EResidentRight do
        Result := 3;
      on E: EResidentBase do
        Result := 4;
    end;
  end;

var
  I: Integer;
begin
  for I := 0 to 3 do
    Carrier.Feed(UInt64(Cardinal(CatchOf(I))));
  Carrier.Feed(UInt64(Ord(CatchOf(0) = 1)));
  Carrier.Feed(UInt64(Ord(CatchOf(3) = 4)));
end;

{ Повторный подъём: пойманное и брошенное заново обязано долететь до внешнего
  обработчика тем же самым, а не подменённым. }
procedure StageReraise(Carrier: TResidentCarrier);
var
  Trail: Int64;
  Code: Integer;
begin
  Trail := 0;
  Code := 0;
  try
    try
      Mark(Trail, 1);
      raise EResidentRight.Create('resident: bounce', 55);
    except
      on E: EResidentRight do
      begin
        Mark(Trail, 2);
        raise;
      end;
    end;
  except
    on E: EResidentBase do
    begin
      Mark(Trail, 3);
      Code := E.Code;
      Carrier.FeedWide(E.Message);
    end;
  end;
  Carrier.Feed(UInt64(Trail));
  Carrier.Feed(UInt64(Cardinal(Code)));
  Carrier.Feed(UInt64(Ord(Trail = 123)));
end;

{ Обработчик без спецификации ловит всё, но обязан пропускать своё через
  вложенный разбор. }
procedure StageBareHandler(Carrier: TResidentCarrier);
var
  Trail: Int64;
begin
  Trail := 0;
  try
    Mark(Trail, 1);
    raise EResidentBase.Create('resident: bare', 9);
  except
    Mark(Trail, 2);
  end;

  try
    Mark(Trail, 3);
    raise EResidentDeep.Create('resident: typed', 11);
  except
    on E: EResidentLeft do
      Mark(Trail, 4);
    on E: Exception do
      Mark(Trail, 5);
  end;
  Carrier.Feed(UInt64(Trail));
  Carrier.Feed(UInt64(Ord(Trail = 1234)));
end;

{ Конструктор бросил: договор языка требует позвать деструктор, и заведённое
  внутри обязано быть похоронено, а не остаться сиротой. }
procedure StageConstructorRaises(Carrier: TResidentCarrier);
var
  Tally: TResidentTally;
  Made: TResidentHalfBuilt;
  Caught: Integer;
begin
  Tally := Default(TResidentTally);
  Caught := 0;

  { Сперва честная постройка: объект живёт и хоронится обычным путём. }
  Made := TResidentHalfBuilt.Create(@Tally, False);
  Made.Free;
  Carrier.Feed(UInt64(Tally.Born));
  Carrier.Feed(UInt64(Tally.Gone));

  { Теперь постройка с отказом: ссылки наружу не будет, но уборка обязана
    случиться сама. }
  Made := nil;
  try
    Made := TResidentHalfBuilt.Create(@Tally, True);
  except
    on E: EResidentLeft do
      Caught := E.Code;
  end;
  Carrier.Feed(UInt64(Cardinal(Caught)));
  Carrier.Feed(UInt64(Ord(Made = nil)));
  Carrier.Feed(UInt64(Tally.Born));
  Carrier.Feed(UInt64(Tally.Gone));
  Carrier.Feed(UInt64(Cardinal(Ord(Tally.Alive = 0))));
end;

{ Короткое замыкание: вторая половина условия не имеет права вычисляться, когда
  первая уже решила исход. }
procedure StageShortCircuit(Carrier: TResidentCarrier);
var
  Visits: Integer;

  function Touch(Value: Boolean): Boolean;
  begin
    Inc(Visits);
    Result := Value;
  end;

begin
  Visits := 0;
  if Touch(False) and Touch(True) then
    Carrier.Feed(1);
  Carrier.Feed(UInt64(Cardinal(Visits)));

  Visits := 0;
  if Touch(True) or Touch(True) then
    Carrier.Feed(2);
  Carrier.Feed(UInt64(Cardinal(Visits)));

  { Обе половины обязаны вычислиться, когда первая исхода не решает. }
  Visits := 0;
  if Touch(True) and Touch(False) then
    Carrier.Feed(3);
  Carrier.Feed(UInt64(Cardinal(Visits)));

  Visits := 0;
  if Touch(False) or Touch(False) then
    Carrier.Feed(4);
  Carrier.Feed(UInt64(Cardinal(Visits)));
end;

{ Выбор по значению: диапазоны, перечисление и `else` — каждая ветвь обязана
  сработать ровно на своём множестве. }
procedure StageCaseRanges(Carrier: TResidentCarrier);

  function Bucket(Value: Integer): Integer;
  begin
    case Value of
      Low(Integer) .. -1: Result := 1;
      0: Result := 2;
      1 .. 9: Result := 3;
      10, 20, 30: Result := 4;
      11 .. 19, 21 .. 29: Result := 5;
    else
      Result := 6;
    end;
  end;

var
  Probes: array[0 .. 8] of Integer;
  I: Integer;
begin
  Probes[0] := -32768;
  Probes[1] := -1;
  Probes[2] := 0;
  Probes[3] := 1;
  Probes[4] := 9;
  Probes[5] := 10;
  Probes[6] := 15;
  Probes[7] := 30;
  Probes[8] := 1000;
  for I := 0 to High(Probes) do
    Carrier.Feed(UInt64(Cardinal(Bucket(Probes[I]))));
  Carrier.Feed(UInt64(Cardinal(Bucket(Carrier.Serial))));
end;

{ Вложенные циклы: `Break` обязан выйти только из своего, `Continue` — только
  свой шаг пропустить. }
procedure StageBreakContinue(Carrier: TResidentCarrier);
var
  Outer, Inner, Trail: Int64;
  I, J: Integer;
begin
  Outer := 0;
  Inner := 0;
  for I := 1 to 5 do
  begin
    Outer := Outer + I;
    for J := 1 to 5 do
    begin
      if J = 3 then
        Break;
      Inner := Inner + J;
    end;
  end;
  Carrier.Feed(UInt64(Outer));
  Carrier.Feed(UInt64(Inner));
  Carrier.Feed(UInt64(Ord(Inner = 5 * 3)));

  Trail := 0;
  for I := 1 to 6 do
  begin
    if I mod 2 = 0 then
      Continue;
    Mark(Trail, I);
  end;
  Carrier.Feed(UInt64(Trail));
  Carrier.Feed(UInt64(Ord(Trail = 135)));

  { Выход из цикла внутри `try` обязан провести через `finally`. }
  Trail := 0;
  for I := 1 to 3 do
  begin
    try
      Mark(Trail, 1);
      if I = 2 then
        Break;
    finally
      Mark(Trail, 9);
    end;
  end;
  Carrier.Feed(UInt64(Trail));
  Carrier.Feed(UInt64(Ord(Trail = 1919)));
end;

{ Цикл `while` и `repeat`: у первого проверка до тела, у второго — после, и это
  видно на пустом множестве. }
procedure StageLoopKinds(Carrier: TResidentCarrier);
var
  Count, Value: Integer;
begin
  Count := 0;
  Value := 0;
  while Value > 0 do
  begin
    Inc(Count);
    Dec(Value);
  end;
  Carrier.Feed(UInt64(Cardinal(Count)));

  Count := 0;
  Value := 0;
  repeat
    Inc(Count);
    Dec(Value);
  until Value <= 0;
  { Тело `repeat` обязано пройти хотя бы раз даже на пустом множестве. }
  Carrier.Feed(UInt64(Cardinal(Count)));

  Count := 0;
  Value := 5 + (Carrier.Lap mod 4);
  while Value > 0 do
  begin
    Inc(Count);
    Dec(Value);
  end;
  Carrier.Feed(UInt64(Cardinal(Count)));

  { Убывающий цикл: границы включительны с обеих сторон. }
  Count := 0;
  for var I := 5 downto 1 do
    Inc(Count);
  Carrier.Feed(UInt64(Cardinal(Count)));

  { Пустой диапазон обязан не выполниться ни разу. }
  Count := 0;
  for var I := 5 to 1 do
    Inc(Count);
  Carrier.Feed(UInt64(Cardinal(Count)));
end;

{ Вложенная процедура видит переменные объемлющей — и видит их текущие
  значения, а не снимок на момент объявления. }
procedure StageNestedScope(Carrier: TResidentCarrier);
var
  Shared: Int64;
  Depth: Integer;

  procedure Bump(By: Int64);

    procedure Deeper;
    begin
      Inc(Depth);
      Shared := Shared * 2;
    end;

  begin
    Shared := Shared + By;
    Deeper;
  end;

begin
  Shared := Carrier.Tag.Wide;
  Depth := 0;
  Bump(1);
  Carrier.Feed(UInt64(Shared));
  Bump(10);
  Carrier.Feed(UInt64(Shared));
  Carrier.Feed(UInt64(Cardinal(Depth)));
  Carrier.Feed(UInt64(Ord(Shared = ((Carrier.Tag.Wide + 1) * 2 + 10) * 2)));
end;

{ Рекурсия: глубина и порядок возврата. Каждый уровень обязан вернуться в свой
  кадр со своими локальными значениями. }
procedure StageRecursion(Carrier: TResidentCarrier);

  function Walk(Depth: Integer; var Trail: Int64): Int64;
  var
    Local: Int64;
  begin
    Local := Depth;
    if Depth <= 0 then
      Exit(0);
    Result := Local + Walk(Depth - 1, Trail);
    { Локальная переменная обязана уцелеть через вложенный вызов. }
    Mark(Trail, Ord(Local = Depth));
  end;

var
  Trail, Sum: Int64;
  Depth: Integer;
begin
  Depth := 4 + (Carrier.Lap mod 5);
  Trail := 0;
  Sum := Walk(Depth, Trail);
  Carrier.Feed(UInt64(Sum));
  Carrier.Feed(UInt64(Trail));
  Carrier.Feed(UInt64(Cardinal(Depth)));
  Carrier.Feed(UInt64(Ord(Sum = Int64(Depth) * (Depth + 1) div 2)));
end;

{ Переход по метке: законный внутри одной процедуры, и он обязан вести ровно
  туда, куда указано. }
procedure StageGoto(Carrier: TResidentCarrier);
label
  Again, Done;
var
  Trail: Int64;
  Count: Integer;
begin
  Trail := 0;
  Count := 0;
Again:
  Mark(Trail, 1);
  Inc(Count);
  if Count < 3 then
    goto Again;
  Mark(Trail, 2);
  goto Done;
  Mark(Trail, 9);
Done:
  Mark(Trail, 3);
  Carrier.Feed(UInt64(Trail));
  Carrier.Feed(UInt64(Cardinal(Count)));
  Carrier.Feed(UInt64(Ord(Trail = 11123)));
end;

{ Исключение внутри цикла: обработчик внутри тела обязан оставить цикл живым,
  обработчик снаружи — прервать его. }
procedure StageExceptionInLoop(Carrier: TResidentCarrier);
var
  Trail: Int64;
  I, Caught: Integer;
begin
  Trail := 0;
  Caught := 0;
  for I := 1 to 5 do
  begin
    try
      if I mod 2 = 0 then
        raise EResidentRight.Create('resident: even', I);
      Mark(Trail, 1);
    except
      on E: EResidentRight do
      begin
        Inc(Caught);
        Mark(Trail, 2);
      end;
    end;
  end;
  Carrier.Feed(UInt64(Trail));
  Carrier.Feed(UInt64(Cardinal(Caught)));

  Trail := 0;
  try
    for I := 1 to 5 do
    begin
      Mark(Trail, 1);
      if I = 3 then
        raise EResidentLeft.Create('resident: stop', I);
    end;
  except
    on E: EResidentLeft do
      Mark(Trail, 7);
  end;
  Carrier.Feed(UInt64(Trail));
  Carrier.Feed(UInt64(Ord(Trail = 1117)));
end;

{ Владение при раскрутке: всё, что заведено до броска, обязано быть похоронено
  ровно один раз, сколько бы уровней ни пришлось раскрутить. }
procedure StageUnwindOwnership(Carrier: TResidentCarrier);
var
  Tally: TResidentTally;
  Depth, Caught: Integer;

  procedure Descend(Level: Integer);
  var
    Held: TResidentHalfBuilt;
  begin
    Held := TResidentHalfBuilt.Create(@Tally, False);
    try
      if Level > 0 then
        Descend(Level - 1)
      else
        raise EResidentDeep.Create('resident: bottom', Level);
    finally
      Held.Free;
    end;
  end;

begin
  Tally := Default(TResidentTally);
  Depth := 3 + (Carrier.Lap mod 4);
  Caught := 0;
  try
    Descend(Depth);
  except
    on E: EResidentDeep do
      Caught := 1;
  end;
  Carrier.Feed(UInt64(Cardinal(Caught)));
  Carrier.Feed(UInt64(Tally.Born));
  Carrier.Feed(UInt64(Tally.Gone));
  Carrier.Feed(UInt64(Ord(Tally.Born = Depth + 1)));
  Carrier.Feed(UInt64(Cardinal(Ord(Tally.Alive = 0))));
end;

{ След, накопленный за оборот: путь обязан повторяться от оборота к обороту,
  пока повторяются входные данные. }
procedure StageTrailAcrossLaps(Carrier: TResidentCarrier);
var
  Pocket: TResidentFlowPocket;
  Trail: Int64;
  Branch: Integer;
begin
  Pocket := Carrier.PocketAs<TResidentFlowPocket>('flow-trail');
  Trail := 0;
  Branch := Carrier.Lap mod 4;
  case Branch of
    0:
      try
        Mark(Trail, 1);
      finally
        Mark(Trail, 2);
      end;
    1:
      try
        raise EResidentLeft.Create('resident: branch', 1);
      except
        on E: EResidentBase do
          Mark(Trail, 3);
      end;
    2:
      for var I := 1 to 3 do
        Mark(Trail, I);
  else
    Mark(Trail, 9);
  end;

  Carrier.Feed(UInt64(Trail));
  Carrier.Feed(UInt64(Cardinal(Branch)));
  { Прошлый след обязан быть тем же самым при том же ответвлении. }
  if (Pocket.FRounds >= 4) and (Branch = 0) then
    Carrier.Feed(UInt64(Ord(Pocket.FTrail = Trail)));
  if Branch = 0 then
    Pocket.FTrail := Trail;
  Inc(Pocket.FRounds);
  Carrier.Feed(UInt64(Pocket.FRounds));
end;

initialization
  ResidentRegisterStage('flow-bare-handler', @StageBareHandler);
  ResidentRegisterStage('flow-break-continue', @StageBreakContinue);
  ResidentRegisterStage('flow-case-ranges', @StageCaseRanges);
  ResidentRegisterStage('flow-constructor-raises', @StageConstructorRaises);
  ResidentRegisterStage('flow-exception-in-loop', @StageExceptionInLoop);
  ResidentRegisterStage('flow-exit-through-finally', @StageExitThroughFinally);
  ResidentRegisterStage('flow-finally-order', @StageFinallyOrder);
  ResidentRegisterStage('flow-goto', @StageGoto);
  ResidentRegisterStage('flow-handler-choice', @StageHandlerChoice);
  ResidentRegisterStage('flow-loop-kinds', @StageLoopKinds);
  ResidentRegisterStage('flow-nested-scope', @StageNestedScope);
  ResidentRegisterStage('flow-recursion', @StageRecursion);
  ResidentRegisterStage('flow-reraise', @StageReraise);
  ResidentRegisterStage('flow-short-circuit', @StageShortCircuit);
  ResidentRegisterStage('flow-trail-across-laps', @StageTrailAcrossLaps);
  ResidentRegisterStage('flow-unwind-order', @StageUnwindOrder);
  ResidentRegisterStage('flow-unwind-ownership', @StageUnwindOwnership);

end.
