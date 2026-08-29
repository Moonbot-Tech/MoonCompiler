unit resident_enumord;

{ Семейство `enumord` — перечисления и их порядковые значения.

  Перечисление в Паскале — это имена для чисел, и почти всё в нём определяется
  порядковым номером: перебор, множество, индекс массива, приведение к целому,
  соседнее значение. Компилятор вправе выбрать под перечисление тип любой
  ширины, лишь бы влезли все значения, и вправе считать переход к соседу
  прибавлением единицы. Обе вольности безобидны, пока номера остаются теми,
  какие написаны.

  Отсюда две группы проверок. Первая — про номера: у обычного перечисления они
  идут подряд с нуля, у перечисления с явными значениями — ровно те, что
  указаны, и это часть исходника, а не выбор компилятора. Вторая — про то, что
  из номеров следует: перебор посещает каждое значение по разу, множество
  вмещает ровно свои элементы, индекс массива попадает в свою ячейку.

  Ширина типа под перечисление в утверждения не идёт — её выбирает компилятор,
  и требовать конкретного числа байтов значило бы придумывать договор. Зато
  предъявляется то, что от неё следует: значение переживает поездку через
  массив, множество и целое, и возвращается собой. }

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
  { Обычное перечисление: номера идут подряд с нуля. }
  TStep = (stIdle, stArm, stFire, stCool, stDone);

  { С явными значениями: номера заданы исходником, и подряд они не идут. }
  TMark = (mkNone = 0, mkLow = 5, mkMid = 100, mkHigh = 1000);

  TStepSet = set of TStep;
  TStepCounts = array[TStep] of Integer;

{ Номера обычного перечисления идут подряд, а соседи получаются переходом. }
procedure StageOrdinals(Carrier: TResidentCarrier);
var
  Step: TStep;
  Bad, Seen: Integer;
begin
  Bad := 0;
  Seen := 0;

  if Ord(stIdle) <> 0 then Inc(Bad);
  if Ord(stArm) <> 1 then Inc(Bad);
  if Ord(stFire) <> 2 then Inc(Bad);
  if Ord(stCool) <> 3 then Inc(Bad);
  if Ord(stDone) <> 4 then Inc(Bad);

  if Low(TStep) <> stIdle then Inc(Bad);
  if High(TStep) <> stDone then Inc(Bad);

  { Перебор посещает каждое значение ровно раз. }
  for Step := Low(TStep) to High(TStep) do
    begin
      Inc(Seen);
      if Ord(Step) <> Seen - 1 then
        Inc(Bad);
    end;
  if Seen <> 5 then Inc(Bad);

  { Сосед справа и слева. }
  if Succ(stIdle) <> stArm then Inc(Bad);
  if Pred(stDone) <> stCool then Inc(Bad);
  if Succ(Pred(stFire)) <> stFire then Inc(Bad);

  { Приведение к целому и обратно. }
  for Step := Low(TStep) to High(TStep) do
    if TStep(Ord(Step)) <> Step then
      Inc(Bad);

  { Порядок значений — это порядок их номеров. }
  if not (stIdle < stArm) then Inc(Bad);
  if not (stDone > stCool) then Inc(Bad);

  Carrier.Feed(UInt64(Cardinal(Seen)));
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'enumord: plain enumeration does not number its values from zero');
end;

{ Явные значения — часть исходника, и они обязаны быть ровно такими. }
procedure StageExplicitValues(Carrier: TResidentCarrier);
const
  All: array[0 .. 3] of TMark = (mkNone, mkLow, mkMid, mkHigh);
var
  I, Bad: Integer;
begin
  Bad := 0;

  if Ord(mkNone) <> 0 then Inc(Bad);
  if Ord(mkLow) <> 5 then Inc(Bad);
  if Ord(mkMid) <> 100 then Inc(Bad);
  if Ord(mkHigh) <> 1000 then Inc(Bad);

  if Low(TMark) <> mkNone then Inc(Bad);
  if High(TMark) <> mkHigh then Inc(Bad);

  { Приведение туда и обратно. }
  for I := Low(All) to High(All) do
    if TMark(Ord(All[I])) <> All[I] then
      Inc(Bad);

  { Порядок сохраняется, а расстояния — нет: между соседями пропуски. }
  if not (mkNone < mkLow) then Inc(Bad);
  if not (mkLow < mkMid) then Inc(Bad);
  if not (mkMid < mkHigh) then Inc(Bad);
  if Ord(mkLow) - Ord(mkNone) = 1 then Inc(Bad);

  Carrier.Feed(UInt64(Cardinal(Ord(mkHigh))));
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'enumord: explicit enumeration values are not what the source says');
end;

{ Перечисление как индекс массива: каждая ячейка своя. }
procedure StageAsIndex(Carrier: TResidentCarrier);
var
  State: UInt64;
  Counts: TStepCounts;
  Step: TStep;
  I, Bad, Total: Integer;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap);
  Bad := 0;

  for Step := Low(TStep) to High(TStep) do
    Counts[Step] := 0;

  { Раскладываем по ячейкам значения, полученные из номера. }
  for I := 1 to 40 do
    begin
      { Номер берётся из беззнакового куска: отрицательный остаток вывел бы
        значение за пределы перечисления. }
      Step := TStep(Integer(ResidentNext(State) and $FF) mod 5);
      Inc(Counts[Step]);
    end;

  Total := 0;
  for Step := Low(TStep) to High(TStep) do
    Total := Total + Counts[Step];
  if Total <> 40 then Inc(Bad);

  { Массив с перечислением в индексе имеет ровно столько ячеек, сколько
    значений. }
  if Length(Counts) <> 5 then Inc(Bad);
  if SizeOf(Counts) <> 5 * SizeOf(Integer) then Inc(Bad);

  { Запись в одну ячейку не трогает соседние. }
  for Step := Low(TStep) to High(TStep) do
    Counts[Step] := Ord(Step) * 10;
  Counts[stFire] := -1;
  if Counts[stArm] <> 10 then Inc(Bad);
  if Counts[stCool] <> 30 then Inc(Bad);
  if Counts[stFire] <> -1 then Inc(Bad);

  Carrier.Feed(UInt64(Cardinal(Total)));
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'enumord: enumeration index landed in the wrong cell');
end;

{ Перечисление в множестве: принадлежность по номеру. }
procedure StageInSet(Carrier: TResidentCarrier);
var
  Live: TStepSet;
  Step: TStep;
  Bad, Count: Integer;
begin
  Bad := 0;

  Live := [stArm, stCool];
  Count := 0;
  for Step := Low(TStep) to High(TStep) do
    if Step in Live then
      Inc(Count);
  if Count <> 2 then Inc(Bad);

  if not (stArm in Live) then Inc(Bad);
  if not (stCool in Live) then Inc(Bad);
  if stIdle in Live then Inc(Bad);
  if stDone in Live then Inc(Bad);

  { Собранное по одному совпадает с записанным целиком. }
  if ([stArm] + [stCool]) <> Live then Inc(Bad);

  { Полное множество и пустое. }
  if ([Low(TStep) .. High(TStep)] - Live) + Live <> [stIdle .. stDone] then Inc(Bad);
  if Live * [] <> [] then Inc(Bad);
  if Live - Live <> [] then Inc(Bad);

  { Добавление и удаление. }
  Include(Live, stDone);
  if not (stDone in Live) then Inc(Bad);
  Exclude(Live, stArm);
  if stArm in Live then Inc(Bad);
  if not (stCool in Live) then Inc(Bad);

  Carrier.Feed(UInt64(Cardinal(Count)));
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'enumord: set of enumeration values holds the wrong members');
end;

{ Переход к соседу приращением: он же и есть прибавление единицы к номеру. }
procedure StageIncDec(Carrier: TResidentCarrier);
var
  Step: TStep;
  Bad, Walked: Integer;
begin
  Bad := 0;
  Walked := 0;

  { Проход вперёд по одному шагу. }
  Step := Low(TStep);
  while Step < High(TStep) do
    begin
      Inc(Walked);
      var Before: Integer := Ord(Step);
      Inc(Step);
      if Ord(Step) <> Before + 1 then
        Inc(Bad);
    end;
  if Walked <> 4 then Inc(Bad);
  if Step <> High(TStep) then Inc(Bad);

  { И назад. }
  while Step > Low(TStep) do
    begin
      var Before: Integer := Ord(Step);
      Dec(Step);
      if Ord(Step) <> Before - 1 then
        Inc(Bad);
    end;
  if Step <> Low(TStep) then Inc(Bad);

  Carrier.Feed(UInt64(Cardinal(Walked)));
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'enumord: stepping through an enumeration skipped a value');
end;

{ Перечисление в записи и в массиве: значение переживает хранение. }
procedure StageStorage(Carrier: TResidentCarrier);
type
  THolder = record
    Before: Int64;
    Step: TStep;
    Mark: TMark;
    After: Int64;
  end;
var
  State: UInt64;
  Holder: THolder;
  Steps: array[0 .. 15] of TStep;
  I, Bad: Integer;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 3 + 1);
  Bad := 0;

  Holder.Before := Int64(ResidentNext(State));
  Holder.Step := stFire;
  Holder.Mark := mkMid;
  Holder.After := Int64(ResidentNext(State));

  var SavedBefore: Int64 := Holder.Before;
  var SavedAfter: Int64 := Holder.After;

  if Holder.Step <> stFire then Inc(Bad);
  if Holder.Mark <> mkMid then Inc(Bad);

  { Запись перечисления не задевает соседние поля. }
  Holder.Step := stDone;
  if (Holder.Before <> SavedBefore) or (Holder.After <> SavedAfter) then Inc(Bad);
  if Holder.Mark <> mkMid then Inc(Bad);

  Holder.Mark := mkHigh;
  if Holder.Step <> stDone then Inc(Bad);
  if (Holder.Before <> SavedBefore) or (Holder.After <> SavedAfter) then Inc(Bad);

  { В массиве каждое значение своё. }
  for I := 0 to High(Steps) do
    Steps[I] := TStep(I mod 5);
  for I := 0 to High(Steps) do
    if Ord(Steps[I]) <> I mod 5 then
      Inc(Bad);

  Carrier.Feed(UInt64(Cardinal(Ord(Holder.Step))));
  Carrier.Feed(UInt64(Cardinal(Ord(Holder.Mark))));
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'enumord: stored enumeration value came back different');
end;

initialization
  ResidentRegisterStage('enumord-as-index', @StageAsIndex);
  ResidentRegisterStage('enumord-explicit-values', @StageExplicitValues);
  ResidentRegisterStage('enumord-inc-dec', @StageIncDec);
  ResidentRegisterStage('enumord-in-set', @StageInSet);
  ResidentRegisterStage('enumord-ordinals', @StageOrdinals);
  ResidentRegisterStage('enumord-storage', @StageStorage);

end.
