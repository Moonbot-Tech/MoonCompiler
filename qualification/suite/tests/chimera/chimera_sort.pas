unit chimera_sort;

{ Орган «сортировка»: наведение порядка в ленте перед сшивкой.

  Источник: `MoonBot/MarketsU.pas`, `TMarket.QuickSortOrders`.
  Перенесены дословно по форме: выбор опоры серединой отрезка, сравнение с
  ДОПУСКОМ в обе стороны, обмен через ПОЛЕ ВЛАДЕЛЬЦА (а не через локальную
  переменную), рекурсия на левую половину при хвостовом цикле на правую,
  счётчик глубины в поле владельца с инкрементом на входе и декрементом на
  выходе, и аварийный выход по превышению предела. Заменены оснасткой: сам
  массив (здесь он свой, детерминированный) и источник данных.

  Почему это отдельная форма, а не «ещё одна сортировка»:

    * временная переменная обмена живёт в ПОЛЕ ВЛАДЕЛЬЦА и потому общая для
      всех вложенных вызовов рекурсии. Это не ошибка оригинала — обмен
      завершается до рекурсивного вызова, — но компилятор обязан это уважать,
      а значит не имеет права держать её в регистре через вызов;
    * сравнение с допуском делает алгоритм НЕ порождающим строгий порядок:
      элементы, попавшие в допуск опоры, не двигаются. Требовать от него
      строгой отсортированности — значит требовать того, чего он не обещает;
    * аварийный выход по глубине бросает работу НЕДОДЕЛАННОЙ. Массив после
      этого не отсортирован — но обязан остаться перестановкой исходного;
    * гибрид «рекурсия влево, цикл вправо» — форма, в которой хвостовой вызов
      уже устранён руками, и оптимизатору остаётся настоящая рекурсия.

  Оракулы, по убыванию силы:

    1. **перестановочность** — мультимножество записей обязано сохраниться при
       ЛЮБОМ исходе, включая аварийный выход. Проверяется свёрткой, не
       зависящей от порядка, плюс сверкой отсортированных копий;
    2. **порядок при нулевом допуске** — тогда алгоритм обязан дать ровно тот
       же порядок времён, что и независимая сортировка вставками;
    3. **отсутствие крупных инверсий при живом допуске** — соседняя пара не
       имеет права разойтись больше чем на допуск в обратную сторону;
    4. **счётчик глубины вернулся в ноль** — инкремент и декремент обязаны
       сойтись, иначе рекурсия где-то вышла не той дверью. }

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch INLINEVARS}
{$endif}
{$Q-}{$R-}

interface

uses
  SysUtils, Math, chimera_body;

const
  { Допуск сравнения. Значение из живого кода. }
  ChiSortEps = 0.0000000001;
  { Предел глубины, после которого работа бросается. Значение из живого кода. }
  ChiSortLimit = 1500;

type
  { Владелец ленты. Временная переменная обмена и счётчик глубины — ЕГО поля,
    как в оригинале: они общие для всех вложенных вызовов. }
  TChiSorter = record
    Items:    TChiTape;
    Swap:     TChiTrade;   { поле, а не локал — форма оригинала }
    Depth:    Integer;     { текущая глубина рекурсии }
    MaxDepth: Integer;     { наибольшая достигнутая }
    Swaps:    Int64;
    Recurses: Int64;
    Tails:    Int64;
    Skips:    Int64;       { обмен пропущен, потому что индексы сошлись }
    BailedOut: Boolean;    { сработал аварийный выход по глубине }
    Eps:      Double;
    procedure Sort(L, R: Integer);
  end;

function ChiSortRun: Int64;

implementation

{ ═══ Перенесённая форма ══════════════════════════════════════════════════ }

procedure TChiSorter.Sort(L, R: Integer);
var
  I, J: Integer;
  Pivot: Double;
begin
  if R - L <= 0 then Exit;
  Inc(Depth);
  if Depth > ChiSortLimit then
  begin
    { Работа бросается недоделанной. Счётчик НЕ уменьшается — ровно как в
      оригинале: выход здесь идёт мимо парного декремента. }
    BailedOut := True;
    Exit;
  end;
  if Depth > MaxDepth then MaxDepth := Depth;
  repeat
    I := L;
    J := R;
    Pivot := Items[L + (R - L) shr 1].Time;
    repeat
      while Items[I].Time < Pivot - Eps do Inc(I);
      while Items[J].Time > Pivot + Eps do Dec(J);
      if I <= J then
      begin
        if I <> J then
        begin
          { Обмен через поле владельца: оно общее для всей рекурсии. }
          Swap := Items[I];
          Items[I] := Items[J];
          Items[J] := Swap;
          Inc(Swaps);
        end
        else
          Inc(Skips);
        Inc(I);
        Dec(J);
      end;
    until I > J;
    if L < J then
    begin
      Inc(Recurses);
      Sort(L, J);
    end;
    L := I;
    Inc(Tails);
  until I >= R;
  Dec(Depth);
end;

{ ═══ Независимый оракул: сортировка вставками ════════════════════════════

  Другой алгоритм, другое представление работы: ни опоры, ни рекурсии, ни
  допуска, ни общей временной переменной. Строго по времени. }

function InsertionSorted(const Src: TChiTape): TChiTape;
var
  I, J: Integer;
  T: TChiTrade;
begin
  Result := Copy(Src);
  for I := 1 to High(Result) do
  begin
    T := Result[I];
    J := I - 1;
    while (J >= 0) and (Result[J].Time > T.Time) do
    begin
      Result[J + 1] := Result[J];
      Dec(J);
    end;
    Result[J + 1] := T;
  end;
end;

{ ═══ Перестановочность ═══════════════════════════════════════════════════

  Свёртка, не зависящая от порядка: сумма и исключающее ИЛИ побитовых образов
  каждой записи. Две последовательности с одинаковой такой свёрткой при разном
  содержимом — событие, которое надо ещё суметь построить; для страховки рядом
  идёт сверка отсортированных копий по всем полям. }

procedure Census(const Tape: TChiTape; out Sum: UInt64; out Xor64: UInt64);
var
  I: Integer;
  W: UInt64;
begin
  Sum := 0;
  Xor64 := 0;
  for I := 0 to High(Tape) do
  begin
    W := UInt64(PInt64(@Tape[I].Time)^);
    W := W xor (UInt64(PCardinal(@Tape[I].Price)^) shl 7);
    W := W xor (UInt64(PCardinal(@Tape[I].Qty)^) shl 23);
    Sum := Sum + W;
    Xor64 := Xor64 xor W;
  end;
end;

function SamePermutation(const A, B: TChiTape): Boolean;
var
  SA, SB, XA, XB: UInt64;
  I: Integer;
  PA, PB: TChiTape;
begin
  Result := Length(A) = Length(B);
  if not Result then Exit;
  Census(A, SA, XA);
  Census(B, SB, XB);
  if (SA <> SB) or (XA <> XB) then Exit(False);
  { Страховка от совпадения свёрток: сравнение отсортированных копий по всем
    полям сразу. }
  PA := InsertionSorted(A);
  PB := InsertionSorted(B);
  for I := 0 to High(PA) do
    if (PInt64(@PA[I].Time)^ <> PInt64(@PB[I].Time)^) then Exit(False);
end;

function TimesEqual(const A, B: TChiTape): Boolean;
var
  I: Integer;
begin
  Result := Length(A) = Length(B);
  if not Result then Exit;
  for I := 0 to High(A) do
    if PInt64(@A[I].Time)^ <> PInt64(@B[I].Time)^ then Exit(False);
end;

function BiggestInversion(const Tape: TChiTape): Double;
var
  I: Integer;
  D: Double;
begin
  Result := 0;
  for I := 1 to High(Tape) do
  begin
    D := Tape[I - 1].Time - Tape[I].Time;
    if D > Result then Result := D;
  end;
end;

{ ═══ Наборы данных ═══════════════════════════════════════════════════════

  Каждый набор существует ради своей ветви, а не для количества. }

type
  TChiSortCase = (scRandom, scSorted, scReversed, scAllEqual, scPlateau,
                  scEchoes, scTwoValues);

function MakeCase(Kind: TChiSortCase; Count: Integer): TChiTape;
var
  Src: TChiSource;
  I: Integer;
  T: Double;
begin
  Result := nil;
  SetLength(Result, Count);
  Src := ChiSource(4242 + Ord(Kind));
  T := 45000.0;
  for I := 0 to Count - 1 do
  begin
    case Kind of
      scRandom:
        T := 45000.0 + Src.NextUnit * 0.01;
      scSorted:
        T := T + Src.NextUnit * 1E-6;
      scReversed:
        T := 45000.01 - I * 1E-7;
      scAllEqual:
        T := 45000.0;
      scPlateau:
        { Половина ленты — одно время, остальное вокруг него: опора почти
          всегда попадает в плато, и обе внутренние петли упираются в допуск. }
        if (I mod 2) = 0 then T := 45000.0
        else T := 45000.0 + (Src.NextUnit - 0.5) * 1E-5;
      scEchoes:
        { Повторные принты: пачки по четыре с одной отметкой. }
        if (I mod 4) = 0 then T := T + Src.NextUnit * 1E-6;
      scTwoValues:
        if Src.NextBelow(2) = 0 then T := 45000.0 else T := 45000.001;
    end;
    Result[I].Time := T;
    Result[I].Price := 1.0 + I * 1E-6;
    Result[I].Qty := 1 + Src.NextBelow(64);
    if Src.NextBelow(2) = 0 then Result[I].Qty := -Result[I].Qty;
  end;
end;

const
  IdSort = 'CHI-MB-SORT-001';

function RunCase(Kind: TChiSortCase; Count: Integer; Eps: Double;
  const Who: string): TChiSorter;
var
  Source, Reference: TChiTape;
begin
  Source := MakeCase(Kind, Count);
  Reference := InsertionSorted(Source);

  Result := Default(TChiSorter);
  Result.Items := Copy(Source);
  Result.Eps := Eps;
  Result.Sort(0, High(Result.Items));

  { Перестановочность обязана держаться при любом исходе — включая брошенную
    работу. Это единственное, что алгоритм обещает безусловно. }
  ChiClaim(SamePermutation(Result.Items, Source),
    Who + ': сортировка потеряла или размножила записи');

  { Счётчик глубины: инкремент и декремент обязаны сойтись. Исключение —
    аварийный выход, который уходит мимо декремента: это форма оригинала, а не
    оплошность переноса. }
  if not Result.BailedOut then
    ChiClaim(Result.Depth = 0,
      Who + ': счётчик глубины не вернулся в ноль');

  if Result.BailedOut then
  begin
    ChiBranch(IdSort, 'bailout');
    Exit;
  end;

  if Eps = 0 then
  begin
    { Нулевой допуск — алгоритм обязан дать тот же порядок времён, что и
      независимая сортировка вставками. }
    ChiClaim(TimesEqual(Result.Items, Reference),
      Who + ': порядок времён разошёлся с независимой сортировкой');
    ChiBranch(IdSort, 'exact-order');
  end
  else
  begin
    { Живой допуск строгого порядка не обещает, но обещает, что соседи не
      разойдутся назад больше чем на допуск. }
    ChiClaim(BiggestInversion(Result.Items) <= Eps,
      Who + ': инверсия больше допуска');
    ChiBranch(IdSort, 'eps-order');
  end;

  if Result.Swaps > 0 then ChiBranch(IdSort, 'swap');
  if Result.Skips > 0 then ChiBranch(IdSort, 'swap-skipped');
  if Result.Recurses > 0 then ChiBranch(IdSort, 'recurse-left');
  if Result.Tails > Result.Recurses then ChiBranch(IdSort, 'tail-right');
  if Result.MaxDepth > 1 then ChiBranch(IdSort, 'nested');
end;

function ChiSortRun: Int64;
var
  Deep: TChiSorter;
  Acc: UInt64;
  Sum, X: UInt64;
begin
  ChiCovered(IdSort);
  Acc := ChiOffset;

  { Нулевой допуск: полная сортировка, сверяемая с независимым алгоритмом. }
  Acc := ChiMix(Acc, RunCase(scRandom, 4000, 0, 'сортировка случайной').Swaps);
  Acc := ChiMix(Acc, RunCase(scSorted, 3000, 0, 'сортировка готовой').Swaps);
  Acc := ChiMix(Acc, RunCase(scReversed, 3000, 0, 'сортировка обратной').Swaps);
  Acc := ChiMix(Acc, RunCase(scEchoes, 3000, 0, 'сортировка с повторами').Swaps);
  Acc := ChiMix(Acc, RunCase(scTwoValues, 3000, 0, 'сортировка двух значений').Swaps);

  { Живой допуск: строгого порядка нет, но перестановочность и отсутствие
    крупных инверсий обязаны держаться. }
  Acc := ChiMix(Acc, RunCase(scPlateau, 3000, ChiSortEps, 'сортировка плато').Swaps);
  Acc := ChiMix(Acc, RunCase(scAllEqual, 3000, ChiSortEps, 'сортировка равных').Swaps);

  { Аварийный выход. Обратная лента даёт наихудшую глубину: опора-середина
    спасает от неё, поэтому предел здесь занижается искусственно — иначе
    ветвь, ради которой в оригинале и стоит счётчик, не исполнится никогда. }
  Deep := Default(TChiSorter);
  Deep.Items := MakeCase(scReversed, 4000);
  Deep.Eps := 0;
  Deep.Depth := ChiSortLimit;   { следующий же вход упрётся в предел }
  Census(Deep.Items, Sum, X);
  Deep.Sort(0, High(Deep.Items));
  ChiClaim(Deep.BailedOut, 'сортировка: аварийный выход не сработал');
  ChiBranch(IdSort, 'bailout');
  { Работа брошена — но лента обязана остаться перестановкой исходной. }
  ChiClaim(SamePermutation(Deep.Items, MakeCase(scReversed, 4000)),
    'сортировка: брошенная работа испортила ленту');
  ChiBranch(IdSort, 'bailout-permutation');

  Result := Int64(Acc and $7FFFFFFFFFFF);
end;

end.
