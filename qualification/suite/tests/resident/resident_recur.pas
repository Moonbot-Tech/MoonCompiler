unit resident_recur;

{ Семейство `recur` — рекурсия и кадры вызова.

  Рекурсия интересна тем, что компилятор вправе её не выполнять. Хвостовой
  вызов он может свернуть в цикл, мелкое тело — вставить в себя же на пару
  уровней вглубь, повторяющийся расчёт — заметить и сохранить. Каждое из этих
  превращений меняет форму кадра: где лежат локалы, когда они рождаются, когда
  хоронятся и что происходит с ними при выходе через исключение.

  Ответ здесь всегда известен независимо: то же число считается циклом, у
  которого никакого кадра нет вовсе. Совпадение рекурсии с циклом — не
  совпадение двух похожих записей, а проверка того, что свёртка кадров не
  потеряла ни одного слагаемого.

  Глубина везде умеренная и задана явно: цель — форма кадра, а не проверка
  размера стека, и превращать стадию в испытание на переполнение незачем. }

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch INLINEVARS}
{$endif}
{$Q-}{$R-}

interface

uses
  SysUtils, resident_core;

implementation

type
  ERecurSignal = class(Exception)
  private
    FDepth: Integer;
  public
    constructor Create(ADepth: Integer); reintroduce;
    property Depth: Integer read FDepth;
  end;

constructor ERecurSignal.Create(ADepth: Integer);
begin
  inherited Create('resident: recur');
  FDepth := ADepth;
end;

{ Хвостовой вызов: результат вложенного и есть результат внешнего, значит
  кадр можно не заводить. Ответ от этого меняться не имеет права. }
procedure StageTail(Carrier: TResidentCarrier);
var
  State: UInt64;
  Steps: Integer;
  ByRecursion, ByLoop: Int64;
  I: Integer;

  function Walk(N: Integer; Acc: Int64): Int64;
  begin
    if N = 0 then
      Result := Acc
    else
      Result := Walk(N - 1, Acc * 2 + N);
  end;

begin
  State := Carrier.Seed xor UInt64(Carrier.Lap);
  Steps := 16 + Integer(ResidentNext(State) and 15);

  ByRecursion := Walk(Steps, 1);

  ByLoop := 1;
  for I := Steps downto 1 do
    ByLoop := ByLoop * 2 + I;

  Carrier.Feed(UInt64(ByRecursion));
  Carrier.Claim(ByRecursion = ByLoop, 'recur: tail recursion disagrees with the same loop');
end;

{ Накопление в параметре против накопления в результате: одна арифметика, но
  в первом случае значение едет вниз, а во втором собирается на обратном
  ходе. }
procedure StageAccumulator(Carrier: TResidentCarrier);
var
  State: UInt64;
  Steps: Integer;
  Down, Up, ByLoop: Int64;
  I: Integer;

  function Downward(N: Integer; Acc: Int64): Int64;
  begin
    if N = 0 then
      Result := Acc
    else
      Result := Downward(N - 1, Acc + Int64(N) * N);
  end;

  function Upward(N: Integer): Int64;
  begin
    if N = 0 then
      Result := 0
    else
      Result := Int64(N) * N + Upward(N - 1);
  end;

begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 3 + 1);
  Steps := 20 + Integer(ResidentNext(State) and 15);

  Down := Downward(Steps, 0);
  Up := Upward(Steps);

  ByLoop := 0;
  for I := 1 to Steps do
    ByLoop := ByLoop + Int64(I) * I;

  Carrier.Feed(UInt64(Up));
  Carrier.Claim(Down = ByLoop, 'recur: accumulating downwards lost a term');
  Carrier.Claim(Up = ByLoop, 'recur: accumulating upwards lost a term');
  Carrier.Claim(Down = Up, 'recur: two accumulation directions disagree');
end;

{ Взаимная рекурсия: свернуть её в цикл сложнее, а разложить по кадрам легче
  ошибиться. }
procedure StageMutual(Carrier: TResidentCarrier);
var
  State: UInt64;
  Steps, I, Bad: Integer;
  Trail: Int64;

  function IsOdd_(N: Integer): Boolean; forward;

  function IsEven_(N: Integer): Boolean;
  begin
    if N = 0 then
      Result := True
    else
      Result := IsOdd_(N - 1);
  end;

  function IsOdd_(N: Integer): Boolean;
  begin
    if N = 0 then
      Result := False
    else
      Result := IsEven_(N - 1);
  end;

begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 5 + 2);
  Steps := 24 + Integer(ResidentNext(State) and 15);
  Bad := 0;
  Trail := 0;

  for I := 0 to Steps do
    begin
      if IsEven_(I) <> ((I and 1) = 0) then
        Inc(Bad);
      if IsOdd_(I) <> ((I and 1) = 1) then
        Inc(Bad);
      if IsEven_(I) = IsOdd_(I) then
        Inc(Bad);
      if IsEven_(I) then
        Trail := Trail + I;
    end;

  Carrier.Feed(UInt64(Trail));
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'recur: mutual recursion gave the wrong parity');
end;

{ Заметная глубина: кадры ложатся один на другой, и на обратном ходе каждый
  обязан вернуть своё. }
procedure StageDeep(Carrier: TResidentCarrier);
var
  State: UInt64;
  Depth: Integer;
  ByRecursion, ByLoop: Int64;
  I: Integer;

  function Dive(N: Integer): Int64;
  var
    Here: Int64;
  begin
    Here := Int64(N) * 3 + 1;
    if N = 0 then
      Result := Here
    else
      Result := Here + Dive(N - 1);
  end;

begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 7 + 3);
  Depth := 400 + Integer(ResidentNext(State) and 255);

  ByRecursion := Dive(Depth);

  ByLoop := 0;
  for I := 0 to Depth do
    ByLoop := ByLoop + Int64(I) * 3 + 1;

  Carrier.Feed(UInt64(ByRecursion));
  Carrier.Feed(UInt64(Cardinal(Depth)));
  Carrier.Claim(ByRecursion = ByLoop, 'recur: deep recursion lost a frame on the way back');
end;

{ Двойная рекурсия: одно и то же значение считается многократно, и это
  первый кандидат на сохранение промежуточных ответов. }
procedure StageBranching(Carrier: TResidentCarrier);
var
  State: UInt64;
  N, I: Integer;
  ByTree, ByLoop, Prev, Cur, Spare: Int64;
  Calls: Integer;

  function Fib(K: Integer): Int64;
  begin
    Inc(Calls);
    if K < 2 then
      Result := K
    else
      Result := Fib(K - 1) + Fib(K - 2);
  end;

begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 11 + 5);
  N := 16 + Integer(ResidentNext(State) and 3);
  Calls := 0;

  ByTree := Fib(N);

  { Глубина не меньше двух, поэтому цикл всегда проходит хотя бы раз, и после
    него в паре лежат соседние значения ряда. }
  Prev := 0;
  Cur := 1;
  for I := 2 to N do
    begin
      Spare := Prev + Cur;
      Prev := Cur;
      Cur := Spare;
    end;
  ByLoop := Cur;

  Carrier.Feed(UInt64(ByTree));
  Carrier.Feed(UInt64(Cardinal(Calls)));
  Carrier.Claim(ByTree = ByLoop, 'recur: branching recursion disagrees with the iterative form');

  { Число вызовов дерева подчиняется тому же рекуррентному правилу, что и сам
    ряд: вызовов ровно вдвое больше следующего члена, без одного. }
  Carrier.Claim(Int64(Calls) = 2 * (Prev + Cur) - 1,
    'recur: branching recursion made the wrong number of calls');
end;

{ Управляемое значение в кадре рекурсии: каждое обязано родиться и умереть
  ровно один раз, а собранная строка — доехать целой. }
procedure StageManaged(Carrier: TResidentCarrier);
var
  State: UInt64;
  Depth: Integer;
  Built: string;
  Expected: string;
  I: Integer;

  function Weave(N: Integer): string;
  var
    Here: string;
  begin
    Here := Char(Ord('a') + (N mod 26));
    if N = 0 then
      Result := Here
    else
      Result := Here + Weave(N - 1);
  end;

begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 13 + 7);
  Depth := 12 + Integer(ResidentNext(State) and 15);

  Built := Weave(Depth);

  Expected := '';
  for I := Depth downto 0 do
    Expected := Expected + Char(Ord('a') + (I mod 26));

  Carrier.FeedWide(Built);
  Carrier.Feed(UInt64(Cardinal(Length(Built))));
  Carrier.Claim(Built = Expected, 'recur: string built through frames came out wrong');
  Carrier.Claim(Length(Built) = Depth + 1, 'recur: string built through frames has the wrong length');
end;

{ Исключение из глубины: раскрутка проходит через все кадры сразу, и то, что
  каждый успел записать, обязано остаться. }
procedure StageUnwind(Carrier: TResidentCarrier);
var
  State: UInt64;
  Depth, Caught, Visited: Integer;
  Ledger, Mirror: Int64;
  I: Integer;

  procedure Dive(N: Integer);
  begin
    Inc(Visited);
    Ledger := Ledger + Int64(N);
    if N = 0 then
      raise ERecurSignal.Create(Visited);
    Dive(N - 1);
    Ledger := Ledger + 1000000;
  end;

begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 17 + 9);
  Depth := 20 + Integer(ResidentNext(State) and 15);
  Visited := 0;
  Caught := 0;
  Ledger := 0;

  try
    Dive(Depth);
  except
    on E: ERecurSignal do
      Caught := E.Depth;
  end;

  Mirror := 0;
  for I := Depth downto 0 do
    Mirror := Mirror + I;

  Carrier.Feed(UInt64(Ledger));
  Carrier.Feed(UInt64(Cardinal(Caught)));
  Carrier.Claim(Visited = Depth + 1, 'recur: unwinding skipped a frame on the way down');
  Carrier.Claim(Caught = Depth + 1, 'recur: depth carried by the exception is wrong');
  Carrier.Claim(Ledger = Mirror, 'recur: work done before the raise was lost');
end;

{ Ссылочный параметр, растущий по мере погружения: правит его каждый кадр, а
  видит — самый верхний. }
procedure StageVarParam(Carrier: TResidentCarrier);
var
  State: UInt64;
  Depth, I: Integer;
  Total, Mirror: Int64;

  procedure Dive(N: Integer; var Acc: Int64);
  begin
    Acc := Acc + Int64(N) * 2;
    if N > 0 then
      Dive(N - 1, Acc);
    Acc := Acc + 1;
  end;

begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 19 + 11);
  Depth := 18 + Integer(ResidentNext(State) and 15);

  Total := 0;
  Dive(Depth, Total);

  Mirror := 0;
  for I := 0 to Depth do
    Mirror := Mirror + Int64(I) * 2 + 1;

  Carrier.Feed(UInt64(Total));
  Carrier.Claim(Total = Mirror, 'recur: var parameter shared across frames lost a change');
end;

initialization
  ResidentRegisterStage('recur-accumulator', @StageAccumulator);
  ResidentRegisterStage('recur-branching', @StageBranching);
  ResidentRegisterStage('recur-deep', @StageDeep);
  ResidentRegisterStage('recur-managed', @StageManaged);
  ResidentRegisterStage('recur-mutual', @StageMutual);
  ResidentRegisterStage('recur-tail', @StageTail);
  ResidentRegisterStage('recur-unwind', @StageUnwind);
  ResidentRegisterStage('recur-var-param', @StageVarParam);

end.
