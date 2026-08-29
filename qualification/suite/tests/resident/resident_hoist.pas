unit resident_hoist;

{ Семейство `hoist` — вынос работы из цикла.

  Вычисление, не зависящее от оборота, можно посчитать один раз до цикла.
  Выгода очевидна, поэтому оптимизатор ищет такие вычисления жадно — и здесь же
  делает самые дорогие ошибки, потому что «не зависит от оборота» и «можно
  выносить» — не одно и то же.

  Выносить нельзя как минимум в трёх случаях, и каждый проверяется отдельно.
  Первый: цикл может не выполниться ни разу — тогда вынесенное посчитается там,
  где по программе не считалось ничего, и вычисление с последствиями (деление,
  чтение по указателю, вызов) случится на пустом месте. Второй: выражение
  инвариантно не всегда, а только в одной ветке — вынести его наружу значит
  посчитать и для той ветки, где оно не имело смысла. Третий: значение
  инвариантно, а действие — нет, и одна запись в память вместо десяти меняет
  наблюдаемое.

  Каждая стадия предъявляет пару: цикл, из которого выносить **можно**, и
  почти такой же, из которого **нельзя**. Ответ обоих известен точной формулой,
  поэтому неверный вынос виден как расхождение, а не как подозрение. }

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

var
  { Счётчик вычислений: он и отвечает на вопрос, сколько раз работа реально
    выполнилась. }
  HoistWork: Integer;

function Costly(Value: Int64): Int64;
begin
  Inc(HoistWork);
  Result := Value * 3 + 7;
end;

{ Вызов, не зависящий от оборота: выносить можно, и ответ от этого не
  меняется. Число вычислений при этом не предъявляется — оно и есть предмет
  свободы компилятора. }
procedure StageInvariantCall(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, Steps: Integer;
  Base, Sum, Mirror: Int64;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap);
  Steps := 8 + Integer(ResidentNext(State) and 7);
  Base := Int64(ResidentNext(State) and $FFF);

  HoistWork := 0;
  Sum := 0;
  for I := 1 to Steps do
    Sum := Sum + Costly(Base) * I;

  Mirror := 0;
  for I := 1 to Steps do
    Mirror := Mirror + (Base * 3 + 7) * I;

  Carrier.Feed(UInt64(Sum));
  Carrier.Claim(Sum = Mirror, 'hoist: invariant call gave a different sum');
  Carrier.Claim(HoistWork >= 1, 'hoist: invariant call never ran');
end;

{ Цикл, который может не выполниться ни разу. Вынести из него вычисление
  наружу — значит посчитать то, чего в программе не было. }
procedure StageZeroTrip(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, Steps: Integer;
  Base, Sum: Int64;
  Ran: Integer;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 3 + 1);
  Base := Int64(ResidentNext(State) and $FFF) + 1;

  { Границы подобраны так, что тело не выполняется никогда. }
  Steps := 0;
  HoistWork := 0;
  Sum := 0;
  for I := 1 to Steps do
    Sum := Sum + Costly(Base);
  Ran := HoistWork;

  Carrier.Feed(UInt64(Sum));
  Carrier.Feed(UInt64(Cardinal(Ran)));
  Carrier.Claim(Sum = 0, 'hoist: empty loop produced a sum');
  Carrier.Claim(Ran = 0, 'hoist: work from an empty loop was done anyway');

  { То же самое с условием вместо счётчика: цикл с условием, ложным сразу. }
  HoistWork := 0;
  Sum := 0;
  I := 10;
  while I < 5 do
    begin
      Sum := Sum + Costly(Base);
      Inc(I);
    end;

  Carrier.Feed(UInt64(Cardinal(HoistWork)));
  Carrier.Claim(HoistWork = 0, 'hoist: work from a never-entered while loop was done anyway');
end;

{ Деление, инвариантное по виду, но осмысленное только внутри ветки: делитель
  бывает нулём, и наружу его выносить нельзя. }
procedure StageGuardedDivision(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, Steps: Integer;
  Numerator, Sum, Mirror: Int64;
  Divisor: Int64;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 5 + 2);
  Steps := 10 + Integer(ResidentNext(State) and 7);
  Numerator := Int64(ResidentNext(State) and $FFFF) + 1000;

  Sum := 0;
  for I := 1 to Steps do
    begin
      { Делитель обнуляется на чётных оборотах, и деление под защитой. }
      if (I and 1) = 1 then
        Divisor := I
      else
        Divisor := 0;

      if Divisor <> 0 then
        Sum := Sum + Numerator div Divisor
      else
        Sum := Sum + 1;
    end;

  Mirror := 0;
  for I := 1 to Steps do
    if (I and 1) = 1 then
      Mirror := Mirror + Numerator div I
    else
      Mirror := Mirror + 1;

  Carrier.Feed(UInt64(Sum));
  Carrier.Claim(Sum = Mirror, 'hoist: guarded division was moved out of its guard');
end;

{ Часть выражения инвариантна, часть — нет. Выносить можно только часть, и
  результат обязан остаться прежним. }
procedure StagePartialInvariant(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, Steps: Integer;
  A, B, Sum, Mirror: Int64;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 7 + 3);
  Steps := 12 + Integer(ResidentNext(State) and 7);
  A := Int64(ResidentNext(State) and $FF) + 1;
  B := Int64(ResidentNext(State) and $FF) + 1;

  Sum := 0;
  for I := 1 to Steps do
    Sum := Sum + (A * B + 5) * I - (A + B);

  Mirror := 0;
  for I := 1 to Steps do
    Mirror := Mirror + (A * B + 5) * I;
  Mirror := Mirror - (A + B) * Steps;

  Carrier.Feed(UInt64(Sum));
  Carrier.Claim(Sum = Mirror, 'hoist: partially invariant expression came out wrong');
end;

{ Вынос из внутреннего цикла во внешний: значение не зависит от внутреннего
  счётчика, но зависит от внешнего. }
procedure StageFromNested(Carrier: TResidentCarrier);
var
  State: UInt64;
  Outer, Inner, Rows, Cols: Integer;
  Base, Sum, Mirror: Int64;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 11 + 5);
  Rows := 5 + Integer(ResidentNext(State) and 3);
  Cols := 6 + Integer(ResidentNext(State) and 3);
  Base := Int64(ResidentNext(State) and $FF) + 1;

  Sum := 0;
  for Outer := 1 to Rows do
    for Inner := 1 to Cols do
      Sum := Sum + (Base * Outer + 3) * Inner;

  Mirror := 0;
  for Outer := 1 to Rows do
    begin
      var RowValue: Int64 := Base * Outer + 3;
      for Inner := 1 to Cols do
        Mirror := Mirror + RowValue * Inner;
    end;

  Carrier.Feed(UInt64(Sum));
  Carrier.Claim(Sum = Mirror, 'hoist: value lifted from the inner loop changed the sum');
end;

{ Цикл с досрочным выходом: работа за точкой выхода не имеет права
  случиться. }
procedure StageEarlyExit(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, Steps, Limit: Integer;
  Base, Sum, Mirror: Int64;
  Ran: Integer;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 13 + 7);
  Steps := 16 + Integer(ResidentNext(State) and 7);
  Limit := 4 + Integer(ResidentNext(State) and 3);
  Base := Int64(ResidentNext(State) and $FF) + 1;

  HoistWork := 0;
  Sum := 0;
  for I := 1 to Steps do
    begin
      if I > Limit then
        Break;
      Sum := Sum + Costly(Base) * I;
    end;
  Ran := HoistWork;

  Mirror := 0;
  for I := 1 to Limit do
    Mirror := Mirror + (Base * 3 + 7) * I;

  Carrier.Feed(UInt64(Sum));
  Carrier.Feed(UInt64(Cardinal(Ran)));
  Carrier.Claim(Sum = Mirror, 'hoist: work past the break was counted');
  Carrier.Claim(Ran <= Limit, 'hoist: work past the break was performed');
end;

{ Значение инвариантно, а запись — нет: одна запись вместо многих меняет то,
  что видно снаружи. }
procedure StageStoreInLoop(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, Steps: Integer;
  Slot: Int64;
  Trail, Mirror: Int64;
  Cells: array[0 .. 15] of Int64;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 17 + 9);
  Steps := 8 + Integer(ResidentNext(State) and 7);
  Slot := Int64(ResidentNext(State) and $FF) + 1;

  for I := 0 to High(Cells) do
    Cells[I] := 0;

  { В ячейку кладётся одно и то же значение, но в разные ячейки, и каждая
    запись обязана состояться. }
  Trail := 0;
  for I := 1 to Steps do
    begin
      Cells[I and 15] := Slot;
      Trail := Trail + Cells[I and 15] * I;
    end;

  Mirror := 0;
  for I := 1 to Steps do
    Mirror := Mirror + Slot * I;

  Carrier.Feed(UInt64(Trail));
  Carrier.Claim(Trail = Mirror, 'hoist: repeated store of an invariant value was collapsed');

  { Сумма всех ячеек говорит, сколько записей реально случилось. }
  Trail := 0;
  for I := 0 to High(Cells) do
    Trail := Trail + Cells[I];
  Carrier.Feed(UInt64(Trail));
  Carrier.Claim(Trail = Slot * Steps, 'hoist: some stores never happened');
end;

{ Условие, инвариантное по значению, но проверяемое каждый оборот: вынести
  его наружу можно только вместе с телом, и итог обязан совпасть. }
procedure StageInvariantCondition(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, Steps: Integer;
  Flag: Boolean;
  Sum, Mirror: Int64;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 19 + 11);
  Steps := 14 + Integer(ResidentNext(State) and 7);
  Flag := (ResidentNext(State) and 1) = 1;

  Sum := 0;
  for I := 1 to Steps do
    if Flag then
      Sum := Sum + Int64(I) * 3
    else
      Sum := Sum - I;

  Mirror := 0;
  if Flag then
    for I := 1 to Steps do
      Mirror := Mirror + Int64(I) * 3
  else
    for I := 1 to Steps do
      Mirror := Mirror - I;

  Carrier.Feed(UInt64(Sum));
  Carrier.Feed(UInt64(Cardinal(Ord(Flag))));
  Carrier.Claim(Sum = Mirror, 'hoist: loop split by an invariant condition changed the sum');
end;

initialization
  ResidentRegisterStage('hoist-early-exit', @StageEarlyExit);
  ResidentRegisterStage('hoist-from-nested', @StageFromNested);
  ResidentRegisterStage('hoist-guarded-division', @StageGuardedDivision);
  ResidentRegisterStage('hoist-invariant-call', @StageInvariantCall);
  ResidentRegisterStage('hoist-invariant-condition', @StageInvariantCondition);
  ResidentRegisterStage('hoist-partial-invariant', @StagePartialInvariant);
  ResidentRegisterStage('hoist-store-in-loop', @StageStoreInLoop);
  ResidentRegisterStage('hoist-zero-trip', @StageZeroTrip);

end.
