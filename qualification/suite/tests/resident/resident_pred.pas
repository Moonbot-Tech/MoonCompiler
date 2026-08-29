unit resident_pred;

{ Семейство `pred` — длинные предикаты и порядок вычисления.

  Остальные семейства спрашивают «тот же ли ответ». Здесь спрашивается другое:
  не соврал ли компилятор, **упрощая условие**. Оптимизатор вправе переписать
  предикат — свернуть повтор, вынести общее, переставить сравнение, выбросить
  ветку, которую счёл недостижимой. Каждое такое право опирается на
  доказательство, и ошибка в доказательстве видна только тому, кто спросил про
  все входы сразу, а не про один.

  Отсюда способ наблюдения, которого нет в других семействах: **двойное
  вычисление одного логического выражения**. Скалярная форма гоняет предикат по
  всем комбинациям входов и собирает ответы в биты числа. Битовая форма
  вычисляет то же выражение один раз, над масками-столбцами таблицы истинности,
  где каждый бит — своя комбинация. Обе формы обязаны дать одно число. Это не
  эталон из прошлого прогона и не «как получилось» — это тождество булевой
  алгебры, поэтому расхождение доказывает дефект само по себе, без второй
  сборки для сравнения.

  Короткое замыкание задано директивой в шапке юнита, потому что здесь оно предмет
  проверки, а не унаследованная настройка: сколько раз операнд имел право
  вычислиться, выводится из тех же масок арифметикой, а не наблюдением.

  Данные берутся из детерминированного потока носителя, а не из констант:
  предикат над константами компилятор вправе свернуть целиком, и проверять
  тогда будет нечего. }

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch anonymousfunctions}
  {$modeswitch functionreferences}
  {$modeswitch INLINEVARS}
{$endif}
{$Q-}{$R-}{$B-}

interface

uses
  SysUtils, resident_core;

implementation

const
  { Столбцы таблицы истинности на пять переменных: бит номер I содержит
    значение переменной в комбинации I. Тридцать два бита — все комбинации. }
  ColA = UInt32($AAAAAAAA);
  ColB = UInt32($CCCCCCCC);
  ColC = UInt32($F0F0F0F0);
  ColD = UInt32($FF00FF00);
  ColE = UInt32($FFFF0000);
  ColAll = UInt32($FFFFFFFF);
  Combos = 32;

function Ones(Value: UInt32): Integer;
begin
  Result := 0;
  while Value <> 0 do
    begin
      Inc(Result, Integer(Value and 1));
      Value := Value shr 1;
    end;
end;

{ Скалярная половина: обычный предикат, как его пишут руками. }
function Shape1(A, B, C, D, E: Boolean): Boolean;
begin
  Result := (A and not B) or (C and (D or not E)) and not (A and C);
end;

{ Битовая половина того же выражения. Ни одной общей строки со скалярной —
  иначе обе половины сломались бы одинаково и промолчали. }
function Shape1Mask: UInt32;
begin
  Result := (ColA and not ColB) or (ColC and (ColD or not ColE)) and not (ColA and ColC);
end;

function Shape2(A, B, C, D, E: Boolean): Boolean;
begin
  Result := ((A or B) and (C or D) and not E) or
            (not (A and B) and (C xor D) and E) or
            (A and B and C and D and E);
end;

function Shape2Mask: UInt32;
begin
  Result := ((ColA or ColB) and (ColC or ColD) and not ColE) or
            (not (ColA and ColB) and (ColC xor ColD) and ColE) or
            (ColA and ColB and ColC and ColD and ColE);
end;

function Shape3(A, B, C, D, E: Boolean): Boolean;
begin
  Result := not ((A xor B) or not (C and (D xor E))) xor
            ((B or not C) and (not D or (A and E)));
end;

function Shape3Mask: UInt32;
begin
  Result := not ((ColA xor ColB) or not (ColC and (ColD xor ColE))) xor
            ((ColB or not ColC) and (not ColD or (ColA and ColE)));
end;

{ Ответы предиката на всех комбинациях, собранные в биты числа. }
function Sweep1: UInt32;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to Combos - 1 do
    if Shape1((I and 1) <> 0, (I and 2) <> 0, (I and 4) <> 0,
              (I and 8) <> 0, (I and 16) <> 0) then
      Result := Result or (UInt32(1) shl I);
end;

function Sweep2: UInt32;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to Combos - 1 do
    if Shape2((I and 1) <> 0, (I and 2) <> 0, (I and 4) <> 0,
              (I and 8) <> 0, (I and 16) <> 0) then
      Result := Result or (UInt32(1) shl I);
end;

function Sweep3: UInt32;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to Combos - 1 do
    if Shape3((I and 1) <> 0, (I and 2) <> 0, (I and 4) <> 0,
              (I and 8) <> 0, (I and 16) <> 0) then
      Result := Result or (UInt32(1) shl I);
end;

{ Тождество проверяется не на выбранных входах, а на всех сразу. }
procedure StageTruthTable(Carrier: TResidentCarrier);
var
  S1, S2, S3: UInt32;
begin
  S1 := Sweep1;
  S2 := Sweep2;
  S3 := Sweep3;

  Carrier.Feed(UInt64(S1));
  Carrier.Feed(UInt64(S2));
  Carrier.Feed(UInt64(S3));

  Carrier.Claim(S1 = Shape1Mask, 'pred: skalar and bitwise forms disagree (1)');
  Carrier.Claim(S2 = Shape2Mask, 'pred: skalar and bitwise forms disagree (2)');
  Carrier.Claim(S3 = Shape3Mask, 'pred: skalar and bitwise forms disagree (3)');

  { Предикат, зависящий от всех пяти входов, не имеет права оказаться
    константой: и ложь, и истина обязаны встретиться. }
  Carrier.Claim((S1 <> 0) and (S1 <> ColAll), 'pred: predicate collapsed to a constant (1)');
  Carrier.Claim((S2 <> 0) and (S2 <> ColAll), 'pred: predicate collapsed to a constant (2)');
  Carrier.Claim((S3 <> 0) and (S3 <> ColAll), 'pred: predicate collapsed to a constant (3)');
end;

{ Законы, которые оптимизатор применяет сам. Если он применил их неверно,
  тождество перестанет выполняться на какой-то комбинации — а проверяются все. }
procedure StageDeMorgan(Carrier: TResidentCarrier);
var
  I, Bad: Integer;
  A, B, C: Boolean;
begin
  Bad := 0;
  for I := 0 to 7 do
    begin
      A := (I and 1) <> 0;
      B := (I and 2) <> 0;
      C := (I and 4) <> 0;

      if (not (A and B)) <> ((not A) or (not B)) then
        Inc(Bad);
      if (not (A or B)) <> ((not A) and (not B)) then
        Inc(Bad);
      if (A xor B) <> ((A or B) and not (A and B)) then
        Inc(Bad);
      if (A and (B or C)) <> ((A and B) or (A and C)) then
        Inc(Bad);
      if (A or (B and C)) <> ((A or B) and (A or C)) then
        Inc(Bad);
      if ((A xor B) xor C) <> (A xor (B xor C)) then
        Inc(Bad);
    end;

  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'pred: boolean identity broken');

  { Те же законы на масках: одна операция вместо восьми проходов. }
  Carrier.Claim((not (ColA and ColB)) = ((not ColA) or (not ColB)),
    'pred: de Morgan on masks (and)');
  Carrier.Claim((not (ColA or ColB)) = ((not ColA) and (not ColB)),
    'pred: de Morgan on masks (or)');
end;

{ Сколько раз операнд имел право вычислиться. Число не наблюдается, а
  выводится из таблицы истинности, поэтому счётчик судит исполнение, а не
  сравнивается сам с собой. }
procedure StageShortCircuitCount(Carrier: TResidentCarrier);
var
  I, TouchA, TouchB, TouchC, TouchD, Hits: Integer;

  function TakeA(Value: Boolean): Boolean;
  begin
    Inc(TouchA);
    Result := Value;
  end;

  function TakeB(Value: Boolean): Boolean;
  begin
    Inc(TouchB);
    Result := Value;
  end;

  function TakeC(Value: Boolean): Boolean;
  begin
    Inc(TouchC);
    Result := Value;
  end;

  function TakeD(Value: Boolean): Boolean;
  begin
    Inc(TouchD);
    Result := Value;
  end;

begin
  TouchA := 0;
  TouchB := 0;
  TouchC := 0;
  TouchD := 0;
  Hits := 0;

  for I := 0 to Combos - 1 do
    if (TakeA((I and 1) <> 0) and TakeB((I and 2) <> 0)) or
       (TakeC((I and 4) <> 0) and TakeD((I and 8) <> 0)) then
      Inc(Hits);

  Carrier.Feed(UInt64(Cardinal(TouchA)));
  Carrier.Feed(UInt64(Cardinal(TouchB)));
  Carrier.Feed(UInt64(Cardinal(TouchC)));
  Carrier.Feed(UInt64(Cardinal(TouchD)));
  Carrier.Feed(UInt64(Cardinal(Hits)));

  { Левый операнд первой скобки вычисляется всегда. }
  Carrier.Claim(TouchA = Combos, 'pred: left operand skipped');

  { Второй — только когда первый истинен. }
  Carrier.Claim(TouchB = Ones(ColA), 'pred: right operand of and evaluated wrong number of times');

  { Вторая скобка нужна лишь когда первая не решила исход. }
  Carrier.Claim(TouchC = Combos - Ones(ColA and ColB),
    'pred: second bracket evaluated wrong number of times');
  Carrier.Claim(TouchD = Ones((not (ColA and ColB)) and ColC),
    'pred: right operand of second bracket evaluated wrong number of times');

  Carrier.Claim(Hits = Ones((ColA and ColB) or (ColC and ColD)),
    'pred: predicate total disagrees with its truth table');
end;

{ Повтор подвыражения, между вхождениями которого меняется его вход. Свернуть
  такой повтор в одно вычисление нельзя. }
procedure StageRepeatAcrossChange(Carrier: TResidentCarrier);
var
  State: UInt64;
  X, Bound, I, Hits, Mirror: Integer;

  function Weigh(Value: Integer): Integer;
  begin
    Result := (Value * 3) xor (Value shr 1);
  end;

begin
  State := Carrier.Seed xor UInt64(Carrier.Lap);
  X := Integer(ResidentNext(State) and 63);
  Bound := Integer(ResidentNext(State) and 31);

  Hits := 0;
  for I := 1 to 12 do
    begin
      if (Weigh(X) > Bound) and ((I and 1) = 0) then
        Inc(Hits);
      if I = 3 then
        X := X + 7;
      if I = 8 then
        X := X - 5;
    end;

  { Тот же счёт заново: та же арифметика, но условие переставлено и записано
    без вызова, поэтому выносить наружу нечего. }
  State := Carrier.Seed xor UInt64(Carrier.Lap);
  X := Integer(ResidentNext(State) and 63);
  Bound := Integer(ResidentNext(State) and 31);

  Mirror := 0;
  for I := 1 to 12 do
    begin
      if ((I and 1) = 0) and (((X * 3) xor (X shr 1)) > Bound) then
        Inc(Mirror);
      if I = 3 then
        X := X + 7;
      if I = 8 then
        X := X - 5;
    end;

  Carrier.Feed(UInt64(Cardinal(Hits)));
  Carrier.Feed(UInt64(Cardinal(Mirror)));
  Carrier.Claim(Hits = Mirror, 'pred: repeated subexpression outlived the change of its input');
end;

{ Сравнения разной ширины и знаковости в одном предикате. Договор Delphi:
  разнотипная пара сравнивается в типе, который вмещает обе, а не в том, что
  короче. }
procedure StageMixedWidth(Carrier: TResidentCarrier);
var
  State: UInt64;
  Small: SmallInt;
  Card: Cardinal;
  Sign: Integer;
  Wide: Int64;
  Un: Word;
  Bad: Integer;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 2 + 1);
  Small := SmallInt(ResidentNext(State) and $FFFF);
  Un := Word(ResidentNext(State) and $FFFF);
  Card := Cardinal($FFFFFFF0);
  Sign := -16;
  Wide := Int64(Card);
  Bad := 0;

  { Беззнаковое, не влезающее в знаковое, не равно отрицательному с тем же
    набором битов: общий тип шире обоих. }
  if Wide = Int64(Sign) then
    Inc(Bad);
  if (Card = Cardinal(Sign)) <> (Int64(Card) = Int64(Cardinal(Sign))) then
    Inc(Bad);

  { Узкое знаковое против узкого беззнакового: каждое расширяется по своим
    правилам, и результат обязан совпасть с явным расширением. }
  if (Small < Un) <> (Int64(Small) < Int64(Un)) then
    Inc(Bad);
  if (Small = SmallInt(Un)) <> (Int64(Small) = Int64(SmallInt(Un))) then
    Inc(Bad);
  if (Small < 0) <> (Int64(Small) < 0) then
    Inc(Bad);

  { Длинный предикат, где все четыре ширины встречаются вперемешку. }
  if ((Small < 0) or (Un > 32767)) and not ((Card < Cardinal(32768)) and (Wide > 0)) then
    Carrier.Feed(1)
  else
    Carrier.Feed(0);

  Carrier.Feed(UInt64(Word(Small)));
  Carrier.Feed(UInt64(Un));
  Carrier.Feed(UInt64(Card));
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'pred: mixed-width comparison disagrees with explicit widening');
end;

{ Одно и то же условие, записанное вложенными ветвлениями и одной строкой.
  Проверяется на всём домене, а не на удачном входе. }
procedure StageNestedVersusFlat(Carrier: TResidentCarrier);
var
  I, Flat, Nested, X, Y, Z: Integer;

  function FlatForm(A, B, C: Integer): Boolean;
  begin
    Result := ((A > B) and (B > C)) or ((A = B) and (C > A)) or (A + C = B);
  end;

  function NestedForm(A, B, C: Integer): Boolean;
  begin
    Result := False;
    if A > B then
      begin
        if B > C then
          Result := True;
      end
    else
      if A = B then
        begin
          if C > A then
            Result := True;
        end;
    if not Result then
      if A + C = B then
        Result := True;
  end;

begin
  Flat := 0;
  Nested := 0;
  for I := 0 to 215 do
    begin
      X := I mod 6;
      Y := (I div 6) mod 6;
      Z := (I div 36) mod 6;
      if FlatForm(X, Y, Z) then
        Inc(Flat);
      if NestedForm(X, Y, Z) then
        Inc(Nested);
      if FlatForm(X, Y, Z) <> NestedForm(X, Y, Z) then
        Carrier.Claim(False, 'pred: flat and nested forms of one condition disagree');
    end;

  Carrier.Feed(UInt64(Cardinal(Flat)));
  Carrier.Feed(UInt64(Cardinal(Nested)));
  Carrier.Claim(Flat = Nested, 'pred: identical conditions hit a different number of times');
end;

{ Выбор по диапазонам против цепочки сравнений: разные машины, один ответ. }
procedure StageCaseVersusChain(Carrier: TResidentCarrier);
var
  I, ByCase, ByChain, V: Integer;

  function Pick(Value: Integer): Integer;
  begin
    case Value of
      0 .. 9: Result := 1;
      10 .. 19: Result := 2;
      20, 22, 24, 26, 28: Result := 3;
      21, 23, 25, 27, 29: Result := 4;
      30 .. 59: Result := 5;
      100 .. 199: Result := 6;
    else
      Result := 0;
    end;
  end;

  function Chain(Value: Integer): Integer;
  begin
    if (Value >= 0) and (Value <= 9) then
      Result := 1
    else if (Value >= 10) and (Value <= 19) then
      Result := 2
    else if (Value >= 20) and (Value <= 29) and ((Value and 1) = 0) then
      Result := 3
    else if (Value >= 20) and (Value <= 29) then
      Result := 4
    else if (Value >= 30) and (Value <= 59) then
      Result := 5
    else if (Value >= 100) and (Value <= 199) then
      Result := 6
    else
      Result := 0;
  end;

begin
  ByCase := 0;
  ByChain := 0;
  for I := -20 to 220 do
    begin
      V := Pick(I);
      ByCase := ByCase + V;
      ByChain := ByChain + Chain(I);
      if V <> Chain(I) then
        Carrier.Claim(False, 'pred: range selection disagrees with comparison chain');
    end;

  Carrier.Feed(UInt64(Cardinal(ByCase)));
  Carrier.Feed(UInt64(Cardinal(ByChain)));
  Carrier.Claim(ByCase = ByChain, 'pred: branch sums do not match');
end;

{ Домен значения сужен маской, но все значения внутри домена достижимы. Ветку,
  которая кажется недостижимой, легко выбросить по ошибке. }
procedure StageRangeNarrowing(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, V, Seen, Beyond: Integer;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 3 + 1);
  Seen := 0;
  Beyond := 0;

  for I := 1 to 256 do
    begin
      V := Integer(ResidentNext(State) and 7);
      case V of
        0: Seen := Seen or 1;
        1: Seen := Seen or 2;
        2: Seen := Seen or 4;
        3: Seen := Seen or 8;
        4: Seen := Seen or 16;
        5: Seen := Seen or 32;
        6: Seen := Seen or 64;
        7: Seen := Seen or 128;
      else
        Inc(Beyond);
      end;
      if (V > 7) or (V < 0) then
        Inc(Beyond);
    end;

  Carrier.Feed(UInt64(Cardinal(Seen)));
  Carrier.Feed(UInt64(Cardinal(Beyond)));
  Carrier.Claim(Seen = 255, 'pred: not every value of the narrowed domain was reached');
  Carrier.Claim(Beyond = 0, 'pred: value escaped its mask');
end;

{ Всегда истинное и всегда ложное над значением, которое компилятору
  неизвестно. Свернуть их он вправе; ответ обязан остаться прежним. }
procedure StageTautology(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, X, TrueHits, FalseHits: Integer;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 7 + 5);
  TrueHits := 0;
  FalseHits := 0;

  for I := 1 to 64 do
    begin
      X := Integer(ResidentNext(State) and $FFFF) - 32768;

      if (X > 3) or (X <= 3) then
        Inc(TrueHits);
      if (X > 3) and (X <= 3) then
        Inc(FalseHits);
      if ((X and 1) = 0) or ((X and 1) = 1) then
        Inc(TrueHits);
      if (X < X) or (X <> X) then
        Inc(FalseHits);
      if not ((X * 0) <> 0) then
        Inc(TrueHits);
    end;

  Carrier.Feed(UInt64(Cardinal(TrueHits)));
  Carrier.Feed(UInt64(Cardinal(FalseHits)));
  Carrier.Claim(TrueHits = 64 * 3, 'pred: tautology did not hold');
  Carrier.Claim(FalseHits = 0, 'pred: contradiction turned out true');
end;

{ Предикат в заголовке цикла, части которого меняются внутри тела. Число
  оборотов известно точно, потому что вся арифметика целая. }
procedure StageLoopGuard(Carrier: TResidentCarrier);
var
  State: UInt64;
  Left, Right, Laps, Mirror: Integer;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 11 + 3);
  Left := 4 + Integer(ResidentNext(State) and 15);
  Right := 40 + Integer(ResidentNext(State) and 15);

  Laps := 0;
  while ((Left < Right) and ((Left and 1) = 0)) or (Left + Laps < 6) do
    begin
      Inc(Laps);
      Left := Left + 2;
      if (Laps and 3) = 0 then
        Right := Right - 3;
      if Laps > 64 then
        Break;
    end;

  { Тот же цикл без составного заголовка: выход считается отдельным условием
    в теле, поэтому переписать его как заголовок нельзя. }
  State := Carrier.Seed xor UInt64(Carrier.Lap * 11 + 3);
  Left := 4 + Integer(ResidentNext(State) and 15);
  Right := 40 + Integer(ResidentNext(State) and 15);

  Mirror := 0;
  while True do
    begin
      if not (((Left < Right) and ((Left and 1) = 0)) or (Left + Mirror < 6)) then
        Break;
      Inc(Mirror);
      Left := Left + 2;
      if (Mirror and 3) = 0 then
        Right := Right - 3;
      if Mirror > 64 then
        Break;
    end;

  Carrier.Feed(UInt64(Cardinal(Laps)));
  Carrier.Feed(UInt64(Cardinal(Mirror)));
  Carrier.Claim(Laps = Mirror, 'pred: compound loop guard produced a different lap count');
end;

initialization
  ResidentRegisterStage('pred-case-vs-chain', @StageCaseVersusChain);
  ResidentRegisterStage('pred-de-morgan', @StageDeMorgan);
  ResidentRegisterStage('pred-loop-guard', @StageLoopGuard);
  ResidentRegisterStage('pred-mixed-width', @StageMixedWidth);
  ResidentRegisterStage('pred-nested-vs-flat', @StageNestedVersusFlat);
  ResidentRegisterStage('pred-range-narrowing', @StageRangeNarrowing);
  ResidentRegisterStage('pred-repeat-across-change', @StageRepeatAcrossChange);
  ResidentRegisterStage('pred-short-circuit-count', @StageShortCircuitCount);
  ResidentRegisterStage('pred-tautology', @StageTautology);
  ResidentRegisterStage('pred-truth-table', @StageTruthTable);

end.
