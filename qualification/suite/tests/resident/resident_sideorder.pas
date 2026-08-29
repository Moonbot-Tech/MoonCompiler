unit resident_sideorder;

{ Семейство `sideorder` — побочные эффекты в выражениях.

  Порядок вычисления операндов язык не задаёт, и это не недосмотр: свобода
  переставлять операнды нужна компилятору, чтобы считать выражения дёшево.
  Поэтому здесь нигде не предъявляется порядок — предъявляется **полнота**:
  каждый операнд обязан быть вычислен, и вычислен ровно один раз. Это свойство
  от порядка не зависит, а значит его можно утверждать, ничего не выдумывая.

  Разница важная. Утверждать «левый операнд считается первым» — значит
  требовать от компилятора того, чего никто не обещал, и получить ложную
  тревогу на честной сборке. Утверждать «оба операнда посчитаны по разу» —
  значит проверять настоящий договор: выражение, в котором операнд посчитан
  дважды или не посчитан вовсе, сломано при любом порядке.

  Там, где итог зависит от порядка, стадия предъявляет не итог, а инвариант:
  сумму счётчиков, число посещений, множество затронутых ячеек. Единственное
  исключение — логические операции с коротким замыканием: там порядок задан
  языком, и он проверяется отдельно, в семействе `pred`. }

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

{ Все аргументы вызова вычисляются, и каждый по разу. }
procedure StageArguments(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, Steps: Integer;
  Hits: array[0 .. 5] of Integer;
  Total, Mirror: Int64;

  function Take(Slot: Integer; Value: Int64): Int64;
  begin
    Inc(Hits[Slot]);
    Result := Value;
  end;

  function Join(A, B, C, D, E, F: Int64): Int64;
  begin
    Result := A + B * 2 + C * 3 + D * 4 + E * 5 + F * 6;
  end;

begin
  State := Carrier.Seed xor UInt64(Carrier.Lap);
  Steps := 6 + Integer(ResidentNext(State) and 7);
  for I := 0 to High(Hits) do
    Hits[I] := 0;

  Total := 0;
  for I := 1 to Steps do
    Total := Total + Join(Take(0, I), Take(1, I + 1), Take(2, I + 2),
                          Take(3, I + 3), Take(4, I + 4), Take(5, I + 5));

  Mirror := 0;
  for I := 1 to Steps do
    Mirror := Mirror + Int64(I) + Int64(I + 1) * 2 + Int64(I + 2) * 3 +
              Int64(I + 3) * 4 + Int64(I + 4) * 5 + Int64(I + 5) * 6;

  Carrier.Feed(UInt64(Total));
  for I := 0 to High(Hits) do
    begin
      Carrier.Feed(UInt64(Cardinal(Hits[I])));
      Carrier.Claim(Hits[I] = Steps, 'sideorder: an argument was evaluated the wrong number of times');
    end;
  Carrier.Claim(Total = Mirror, 'sideorder: argument values got mixed up');
end;

{ Операнды бинарной операции: сумма от порядка не зависит, число вычислений —
  тоже. }
procedure StageBinary(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, Steps, Left, Right: Integer;
  Total, Mirror: Int64;

  function L(Value: Int64): Int64;
  begin
    Inc(Left);
    Result := Value;
  end;

  function R(Value: Int64): Int64;
  begin
    Inc(Right);
    Result := Value;
  end;

begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 3 + 1);
  Steps := 8 + Integer(ResidentNext(State) and 7);
  Left := 0;
  Right := 0;

  Total := 0;
  for I := 1 to Steps do
    begin
      Total := Total + (L(I) + R(I * 10));
      Total := Total + (L(I) * R(2));
      Total := Total + (L(I * 100) - R(I));
    end;

  Mirror := 0;
  for I := 1 to Steps do
    Mirror := Mirror + (Int64(I) + Int64(I) * 10) + (Int64(I) * 2) +
              (Int64(I) * 100 - I);

  Carrier.Feed(UInt64(Total));
  Carrier.Feed(UInt64(Cardinal(Left)));
  Carrier.Feed(UInt64(Cardinal(Right)));
  Carrier.Claim(Left = Steps * 3, 'sideorder: left operand evaluated the wrong number of times');
  Carrier.Claim(Right = Steps * 3, 'sideorder: right operand evaluated the wrong number of times');
  Carrier.Claim(Total = Mirror, 'sideorder: binary operands got mixed up');
end;

{ Индекс с побочным эффектом: он вычисляется один раз, и обращение идёт по
  тому индексу, который получился. }
procedure StageIndex(Carrier: TResidentCarrier);
var
  State: UInt64;
  Cells: array[0 .. 15] of Int64;
  I, Steps, Calls: Integer;
  Total, Mirror: Int64;

  function Where(Value: Integer): Integer;
  begin
    Inc(Calls);
    Result := Value and 15;
  end;

begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 5 + 2);
  Steps := 10 + Integer(ResidentNext(State) and 5);
  for I := 0 to High(Cells) do
    Cells[I] := Int64(I) * 7 + 1;
  Calls := 0;

  Total := 0;
  for I := 1 to Steps do
    Total := Total + Cells[Where(I)];

  Mirror := 0;
  for I := 1 to Steps do
    Mirror := Mirror + Cells[I and 15];

  Carrier.Feed(UInt64(Total));
  Carrier.Feed(UInt64(Cardinal(Calls)));
  Carrier.Claim(Calls = Steps, 'sideorder: index expression evaluated the wrong number of times');
  Carrier.Claim(Total = Mirror, 'sideorder: index expression picked the wrong cell');

  { Запись по вычисленному индексу: затронуты ровно те ячейки. }
  Calls := 0;
  for I := 1 to Steps do
    Cells[Where(I)] := -1;

  var Touched: Integer := 0;
  for I := 0 to High(Cells) do
    if Cells[I] = -1 then
      Inc(Touched);

  Carrier.Feed(UInt64(Cardinal(Touched)));
  Carrier.Claim(Calls = Steps, 'sideorder: index of a store evaluated the wrong number of times');
  Carrier.Claim(Touched = Steps, 'sideorder: store landed in the wrong number of cells');
end;

{ Обе стороны присваивания несут эффекты: и приёмник, и источник обязаны быть
  вычислены по разу. }
procedure StageAssignment(Carrier: TResidentCarrier);
var
  State: UInt64;
  Cells: array[0 .. 15] of Int64;
  I, Steps, LeftCalls, RightCalls: Integer;
  Sum: Int64;

  function Slot(Value: Integer): Integer;
  begin
    Inc(LeftCalls);
    Result := Value and 15;
  end;

  function Source(Value: Integer): Int64;
  begin
    Inc(RightCalls);
    Result := Int64(Value) * 3;
  end;

begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 7 + 3);
  Steps := 8 + Integer(ResidentNext(State) and 7);
  for I := 0 to High(Cells) do
    Cells[I] := 0;
  LeftCalls := 0;
  RightCalls := 0;

  for I := 1 to Steps do
    Cells[Slot(I)] := Source(I);

  Sum := 0;
  for I := 0 to High(Cells) do
    Sum := Sum + Cells[I];

  { Каждая запись легла в свою ячейку, поэтому сумма известна точно. }
  var Mirror: Int64 := 0;
  for I := 1 to Steps do
    Mirror := Mirror + Int64(I) * 3;

  Carrier.Feed(UInt64(Sum));
  Carrier.Feed(UInt64(Cardinal(LeftCalls)));
  Carrier.Feed(UInt64(Cardinal(RightCalls)));
  Carrier.Claim(LeftCalls = Steps, 'sideorder: destination expression evaluated the wrong number of times');
  Carrier.Claim(RightCalls = Steps, 'sideorder: source expression evaluated the wrong number of times');
  Carrier.Claim(Sum = Mirror, 'sideorder: assignment lost or duplicated a value');
end;

{ Вложенные вызовы: внутренний считается один раз, даже если его результат
  нужен снаружи дважды по виду выражения. }
procedure StageNested(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, Steps, Inner, Outer: Integer;
  Total, Mirror: Int64;

  function Deep(Value: Int64): Int64;
  begin
    Inc(Inner);
    Result := Value * 2 + 1;
  end;

  function Wrap(A, B: Int64): Int64;
  begin
    Inc(Outer);
    Result := A * 10 + B;
  end;

begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 11 + 5);
  Steps := 6 + Integer(ResidentNext(State) and 7);
  Inner := 0;
  Outer := 0;

  Total := 0;
  for I := 1 to Steps do
    Total := Total + Wrap(Deep(I), Deep(I + 1));

  Mirror := 0;
  for I := 1 to Steps do
    Mirror := Mirror + (Int64(I) * 2 + 1) * 10 + (Int64(I + 1) * 2 + 1);

  Carrier.Feed(UInt64(Total));
  Carrier.Feed(UInt64(Cardinal(Inner)));
  Carrier.Feed(UInt64(Cardinal(Outer)));
  Carrier.Claim(Inner = Steps * 2, 'sideorder: inner call evaluated the wrong number of times');
  Carrier.Claim(Outer = Steps, 'sideorder: outer call evaluated the wrong number of times');
  Carrier.Claim(Total = Mirror, 'sideorder: nested results got mixed up');
end;

{ Эффект внутри условия, которое решает исход: считается ровно столько раз,
  сколько условие проверялось. }
procedure StageInCondition(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, Steps, Probes, Taken: Integer;
  Total, Mirror: Int64;

  function Ask(Value: Integer): Boolean;
  begin
    Inc(Probes);
    Result := (Value mod 3) = 0;
  end;

begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 13 + 7);
  Steps := 12 + Integer(ResidentNext(State) and 7);
  Probes := 0;
  Taken := 0;

  Total := 0;
  for I := 1 to Steps do
    if Ask(I) then
      begin
        Inc(Taken);
        Total := Total + I;
      end
    else
      Total := Total - 1;

  Mirror := 0;
  for I := 1 to Steps do
    if (I mod 3) = 0 then
      Mirror := Mirror + I
    else
      Mirror := Mirror - 1;

  Carrier.Feed(UInt64(Total));
  Carrier.Feed(UInt64(Cardinal(Probes)));
  Carrier.Claim(Probes = Steps, 'sideorder: condition evaluated the wrong number of times');
  Carrier.Claim(Taken = Steps div 3, 'sideorder: condition chose the wrong branch');
  Carrier.Claim(Total = Mirror, 'sideorder: branch totals do not match');
end;

initialization
  ResidentRegisterStage('sideorder-arguments', @StageArguments);
  ResidentRegisterStage('sideorder-assignment', @StageAssignment);
  ResidentRegisterStage('sideorder-binary', @StageBinary);
  ResidentRegisterStage('sideorder-in-condition', @StageInCondition);
  ResidentRegisterStage('sideorder-index', @StageIndex);
  ResidentRegisterStage('sideorder-nested', @StageNested);

end.
