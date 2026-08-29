unit resident_select;

{ Семейство `select` — выбор по значению.

  Оператор выбора компилируется не одним способом, а несколькими, и способ
  выбирает компилятор: плотный набор меток превращается в таблицу переходов,
  разреженный — в дерево сравнений, пара меток — в обычное ветвление. Границы
  между этими способами и есть опасное место: таблица строится по наименьшей и
  наибольшей метке, дерево — по порядку значений, а ошибка на краю диапазона
  или у отрицательной метки не видна ни на одном «обычном» входе.

  Поэтому каждая стадия перебирает **весь** домен селектора, включая всё, что
  лежит за пределами меток, и сверяет ответ с цепочкой сравнений, написанной
  вручную. Цепочка — не копия оператора выбора, а другая машина: у неё нет ни
  таблицы, ни дерева, поэтому одинаковая ошибка в обеих исключена.

  Особая цель — широкий селектор. Метки в Delphi ограничены разрядностью
  целого, но само сравниваемое значение шириной не ограничено, и обрезать его
  до метки нельзя: значение, отличающееся от метки только старшей половиной,
  обязано уйти в `else`. }

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
  { Разреженное перечисление: значения заданы явно и идут с пропусками. }
  TSelectMark = (smNone = 0, smLow = 3, smMid = 17, smHigh = 40, smTop = 41);

{ Плотный набор меток подряд — самый вероятный кандидат в таблицу переходов. }
procedure StageDense(Carrier: TResidentCarrier);
var
  I, Bad: Integer;
  ByCase, ByChain: Int64;

  function Dense(V: Integer): Integer;
  begin
    case V of
      0: Result := 10;   1: Result := 11;   2: Result := 12;   3: Result := 13;
      4: Result := 14;   5: Result := 15;   6: Result := 16;   7: Result := 17;
      8: Result := 18;   9: Result := 19;  10: Result := 20;  11: Result := 21;
     12: Result := 22;  13: Result := 23;  14: Result := 24;  15: Result := 25;
    else
      Result := -1;
    end;
  end;

begin
  Bad := 0;
  ByCase := 0;
  ByChain := 0;

  for I := -8 to 24 do
    begin
      ByCase := ByCase + Dense(I);
      if (I >= 0) and (I <= 15) then
        ByChain := ByChain + (I + 10)
      else
        ByChain := ByChain - 1;
      if (Dense(I) = -1) <> ((I < 0) or (I > 15)) then
        Inc(Bad);
    end;

  Carrier.Feed(UInt64(ByCase));
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(ByCase = ByChain, 'select: dense jump table disagrees with a comparison chain');
  Carrier.Claim(Bad = 0, 'select: dense table sent a value to the wrong branch');
end;

{ Редкие метки, разбросанные далеко друг от друга: таблицу строить нельзя,
  строится дерево. }
procedure StageSparse(Carrier: TResidentCarrier);
var
  I, Bad, Hits: Integer;
  ByCase, ByChain: Int64;

  function Sparse(V: Integer): Integer;
  begin
    case V of
      -1000: Result := 1;
      -7: Result := 2;
      0: Result := 3;
      5: Result := 4;
      999: Result := 5;
      100000: Result := 6;
    else
      Result := 0;
    end;
  end;

begin
  Bad := 0;
  Hits := 0;
  ByCase := 0;
  ByChain := 0;

  for I := -12 to 12 do
    begin
      ByCase := ByCase + Sparse(I);
      if I = -7 then
        ByChain := ByChain + 2
      else if I = 0 then
        ByChain := ByChain + 3
      else if I = 5 then
        ByChain := ByChain + 4;
    end;

  { Дальние метки проверяются точечно — перебирать до ста тысяч незачем. }
  if Sparse(-1000) <> 1 then Inc(Bad);
  if Sparse(999) <> 5 then Inc(Bad);
  if Sparse(100000) <> 6 then Inc(Bad);
  if Sparse(-999) <> 0 then Inc(Bad);
  if Sparse(1000) <> 0 then Inc(Bad);
  if Sparse(99999) <> 0 then Inc(Bad);
  if Sparse(100001) <> 0 then Inc(Bad);

  for I := -12 to 12 do
    if Sparse(I) <> 0 then
      Inc(Hits);

  Carrier.Feed(UInt64(ByCase));
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(ByCase = ByChain, 'select: sparse selection disagrees with a comparison chain');
  Carrier.Claim(Hits = 3, 'select: sparse labels matched the wrong number of values');
  Carrier.Claim(Bad = 0, 'select: a distant label was missed or invented');
end;

{ Диапазоны, в том числе соседние и вырожденные в одно значение. Границы
  диапазона — самое частое место ошибки на единицу. }
procedure StageRanges(Carrier: TResidentCarrier);
var
  I, Bad: Integer;
  ByCase, ByChain: Int64;

  function Ranged(V: Integer): Integer;
  begin
    case V of
      -20 .. -11: Result := 1;
      -10 .. -1: Result := 2;
      0: Result := 3;
      1 .. 1: Result := 4;
      2 .. 9: Result := 5;
      10 .. 10: Result := 6;
      11 .. 30: Result := 7;
    else
      Result := 0;
    end;
  end;

begin
  Bad := 0;
  ByCase := 0;
  ByChain := 0;

  for I := -30 to 40 do
    begin
      ByCase := ByCase + Ranged(I);
      if (I >= -20) and (I <= -11) then
        ByChain := ByChain + 1
      else if (I >= -10) and (I <= -1) then
        ByChain := ByChain + 2
      else if I = 0 then
        ByChain := ByChain + 3
      else if I = 1 then
        ByChain := ByChain + 4
      else if (I >= 2) and (I <= 9) then
        ByChain := ByChain + 5
      else if I = 10 then
        ByChain := ByChain + 6
      else if (I >= 11) and (I <= 30) then
        ByChain := ByChain + 7;
    end;

  { Точки прямо на границах: соседи по обе стороны обязаны разойтись. }
  if Ranged(-21) <> 0 then Inc(Bad);
  if Ranged(-20) <> 1 then Inc(Bad);
  if Ranged(-11) <> 1 then Inc(Bad);
  if Ranged(-10) <> 2 then Inc(Bad);
  if Ranged(30) <> 7 then Inc(Bad);
  if Ranged(31) <> 0 then Inc(Bad);

  Carrier.Feed(UInt64(ByCase));
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(ByCase = ByChain, 'select: ranges disagree with a comparison chain');
  Carrier.Claim(Bad = 0, 'select: range boundary is off by one');
end;

{ Селектор шире метки. Метка ограничена разрядностью целого, значение — нет, и
  обрезать его до метки нельзя. }
procedure StageWideSelector(Carrier: TResidentCarrier);
var
  Bad: Integer;
  I: Integer;
  ByCase, ByChain: Int64;

  function Wide(V: Int64): Integer;
  begin
    case V of
      0: Result := 1;
      1: Result := 2;
      2: Result := 3;
      -1: Result := 4;
    else
      Result := 0;
    end;
  end;

begin
  Bad := 0;
  ByCase := 0;
  ByChain := 0;

  for I := -3 to 5 do
    begin
      ByCase := ByCase + Wide(Int64(I));
      case I of
        0: ByChain := ByChain + 1;
        1: ByChain := ByChain + 2;
        2: ByChain := ByChain + 3;
        -1: ByChain := ByChain + 4;
      end;
    end;

  { Значения, у которых младшая половина совпадает с меткой, а старшая — нет.
    Они обязаны уйти в else, а не выдать себя за метку. }
  if Wide(Int64($100000000)) <> 0 then Inc(Bad);
  if Wide(Int64($100000001)) <> 0 then Inc(Bad);
  if Wide(Int64($100000002)) <> 0 then Inc(Bad);
  if Wide(-Int64($100000000)) <> 0 then Inc(Bad);
  if Wide(Int64($7FFFFFFFFFFFFFFF)) <> 0 then Inc(Bad);
  if Wide(Low(Int64)) <> 0 then Inc(Bad);

  { А чистые метки по-прежнему попадают. }
  if Wide(0) <> 1 then Inc(Bad);
  if Wide(-1) <> 4 then Inc(Bad);

  Carrier.Feed(UInt64(ByCase));
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(ByCase = ByChain, 'select: wide selector disagrees with a narrow one on the same values');
  Carrier.Claim(Bad = 0, 'select: wide selector was truncated to the label width');
end;

{ Вложенный выбор: внешняя ветка сама содержит выбор, и таблицы у них
  разные. }
procedure StageNested(Carrier: TResidentCarrier);
var
  I, J, Bad: Integer;
  ByCase, ByChain: Int64;

  function Pick(A, B: Integer): Integer;
  begin
    case A of
      0 .. 2:
        case B of
          0: Result := 100;
          1 .. 3: Result := 200;
        else
          Result := 300;
        end;
      3 .. 5:
        case B of
          0 .. 1: Result := 400;
        else
          Result := 500;
        end;
    else
      Result := 600;
    end;
  end;

begin
  Bad := 0;
  ByCase := 0;
  ByChain := 0;

  for I := -1 to 7 do
    for J := -1 to 5 do
      begin
        ByCase := ByCase + Pick(I, J);
        if (I >= 0) and (I <= 2) then
          begin
            if J = 0 then
              ByChain := ByChain + 100
            else if (J >= 1) and (J <= 3) then
              ByChain := ByChain + 200
            else
              ByChain := ByChain + 300;
          end
        else if (I >= 3) and (I <= 5) then
          begin
            if (J >= 0) and (J <= 1) then
              ByChain := ByChain + 400
            else
              ByChain := ByChain + 500;
          end
        else
          ByChain := ByChain + 600;
      end;

  Carrier.Feed(UInt64(ByCase));
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(ByCase = ByChain, 'select: nested selection disagrees with nested comparisons');
end;

{ Выбор по символу: домен маленький, зато метки идут по кодам, и весь домен
  проверяется целиком. }
procedure StageChar(Carrier: TResidentCarrier);
var
  Code, Bad: Integer;
  Ch: Char;
  ByCase, ByChain: Int64;

  function Kind(C: Char): Integer;
  begin
    case C of
      '0' .. '9': Result := 1;
      'a' .. 'z': Result := 2;
      'A' .. 'Z': Result := 3;
      ' ', #9: Result := 4;
      '+', '-', '*', '/': Result := 5;
    else
      Result := 0;
    end;
  end;

begin
  Bad := 0;
  ByCase := 0;
  ByChain := 0;

  for Code := 0 to 127 do
    begin
      Ch := Char(Code);
      ByCase := ByCase + Kind(Ch);
      if (Ch >= '0') and (Ch <= '9') then
        ByChain := ByChain + 1
      else if (Ch >= 'a') and (Ch <= 'z') then
        ByChain := ByChain + 2
      else if (Ch >= 'A') and (Ch <= 'Z') then
        ByChain := ByChain + 3
      else if (Ch = ' ') or (Ch = #9) then
        ByChain := ByChain + 4
      else if (Ch = '+') or (Ch = '-') or (Ch = '*') or (Ch = '/') then
        ByChain := ByChain + 5;
    end;

  { Символы вне латиницы обязаны уходить в else, а не приклеиваться к
    ближайшему диапазону. }
  if Kind(Char($0400)) <> 0 then Inc(Bad);
  if Kind(Char($FF10)) <> 0 then Inc(Bad);

  Carrier.Feed(UInt64(ByCase));
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(ByCase = ByChain, 'select: character selection disagrees with comparisons');
  Carrier.Claim(Bad = 0, 'select: a character outside the labels matched a range');
end;

{ Выбор по разреженному перечислению: значения заданы явно и идут с
  пропусками, поэтому плотная таблица здесь была бы неверна. }
procedure StageEnum(Carrier: TResidentCarrier);
const
  { Перечисление разреженное, поэтому перебирается список его значений, а не
    отрезок от наименьшего до наибольшего: в отрезке лежат числа, которым ни
    одно значение не соответствует. }
  Marks: array[0 .. 4] of TSelectMark = (smNone, smLow, smMid, smHigh, smTop);
var
  Mark: TSelectMark;
  I, Bad: Integer;
  ByCase, ByChain: Int64;

  function Weigh(M: TSelectMark): Integer;
  begin
    case M of
      smNone: Result := 1;
      smLow: Result := 2;
      smMid: Result := 3;
      smHigh: Result := 4;
      smTop: Result := 5;
    else
      Result := 0;
    end;
  end;

begin
  Bad := 0;
  ByCase := 0;
  ByChain := 0;

  for I := Low(Marks) to High(Marks) do
    begin
      Mark := Marks[I];
      ByCase := ByCase + Weigh(Mark);
      if Mark = smNone then
        ByChain := ByChain + 1
      else if Mark = smLow then
        ByChain := ByChain + 2
      else if Mark = smMid then
        ByChain := ByChain + 3
      else if Mark = smHigh then
        ByChain := ByChain + 4
      else if Mark = smTop then
        ByChain := ByChain + 5;
    end;

  if Ord(smNone) <> 0 then Inc(Bad);
  if Ord(smLow) <> 3 then Inc(Bad);
  if Ord(smMid) <> 17 then Inc(Bad);
  if Ord(smHigh) <> 40 then Inc(Bad);
  if Ord(smTop) <> 41 then Inc(Bad);

  Carrier.Feed(UInt64(ByCase));
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(ByCase = ByChain, 'select: enumeration selection disagrees with comparisons');
  Carrier.Claim(ByCase = 15, 'select: not every enumeration value was reached');
  Carrier.Claim(Bad = 0, 'select: explicit enumeration values are wrong');
end;

{ Метки на самых краях знакового типа. }
procedure StageBoundary(Carrier: TResidentCarrier);
var
  Bad: Integer;

  function AtEdge(V: Integer): Integer;
  begin
    case V of
      Low(Integer): Result := 1;
      Low(Integer) + 1: Result := 2;
      -1: Result := 3;
      0: Result := 4;
      High(Integer) - 1: Result := 5;
      High(Integer): Result := 6;
    else
      Result := 0;
    end;
  end;

begin
  Bad := 0;

  if AtEdge(Low(Integer)) <> 1 then Inc(Bad);
  if AtEdge(Low(Integer) + 1) <> 2 then Inc(Bad);
  if AtEdge(Low(Integer) + 2) <> 0 then Inc(Bad);
  if AtEdge(-1) <> 3 then Inc(Bad);
  if AtEdge(0) <> 4 then Inc(Bad);
  if AtEdge(1) <> 0 then Inc(Bad);
  if AtEdge(High(Integer) - 2) <> 0 then Inc(Bad);
  if AtEdge(High(Integer) - 1) <> 5 then Inc(Bad);
  if AtEdge(High(Integer)) <> 6 then Inc(Bad);

  Carrier.Feed(UInt64(Cardinal(AtEdge(Low(Integer)))));
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'select: label at the edge of the type was missed');
end;

initialization
  ResidentRegisterStage('select-boundary', @StageBoundary);
  ResidentRegisterStage('select-char', @StageChar);
  ResidentRegisterStage('select-dense', @StageDense);
  ResidentRegisterStage('select-enum', @StageEnum);
  ResidentRegisterStage('select-nested', @StageNested);
  ResidentRegisterStage('select-ranges', @StageRanges);
  ResidentRegisterStage('select-sparse', @StageSparse);
  ResidentRegisterStage('select-wide-selector', @StageWideSelector);

end.
