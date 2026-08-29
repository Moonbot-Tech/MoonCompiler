unit chimera_tape;

{ Орган «лента»: свёртка ленты сделок по окнам — сердце горячего пути бота.

  Живая процедура идёт по ленте с конца к началу и за ОДИН проход набивает
  десяток окон разной длины, корзины по десятым долям секунды, кольцо минутных
  объёмов, скользящее среднее, края цены и несколько признаков — обрывая обход,
  как только время ушло за самую дальнюю границу. Форма этого прохода и есть
  предмет проверки:

    * обход `downto` с раскрытием элемента массива через `with` — компилятор
      получает право держать адрес элемента, и вопрос в том, тот ли адрес;
    * СОРОК с лишним одновременно живых значений в локальных переменных. Это не
      неряшливость оригинала, а часть формы: именно на таком давлении
      распределитель регистров начинает выталкивать значения в стек, и именно
      на выталкивании ошибаются;
    * накопители одинарной точности, в которые кладут произведения двойной:
      сужение происходит на КАЖДОМ сложении, переставить порядок нельзя;
    * индекс корзины через усечение произведения разности времён на масштаб, с
      проверкой обеих границ;
    * кольцевой индекс минуты со сбросом ячейки при смене минуты — индексная
      арифметика с заворотом через ноль;
    * скользящее среднее вида (X*99 + Q)/100 — деление в цикле, которое
      оптимизатор вправе заменить умножением на обратное;
    * досрочный выход по времени: сколько именно шагов сделано — часть ответа.

  ПЯТЬ ТЕЛ. Одна и та же работа записана пятью способами, и все обязаны дать
  один ответ. Дробить вместо целого было бы подменой: баг, который живёт
  только на большом теле — давление на регистры, длинные диапазоны жизни
  значений, пороги, за которыми оптимизатор бросает дорогие проходы, — на
  мелких кусках просто не рождается. Поэтому и целое, и дроблёное, и сверка.

    1. монолит — как в живом коде, ничего не причёсано, всё в локалах;
    2. дроблёный процедурами-накопителями: состояние ездит записью через
       `var`, кадров много. Вставить такое тело компилятор отказывается —
       он не может доказать, что запись по ссылке не пересекается с
       `const`-параметром, — так что это ещё и форма «дробление без вставки»;
    3. дроблёный ЧИСТЫМИ шагами из листового юнита — эти вставляются;
    4. тот же текст, что в третьем (подключается одним файлом), но шаги взяты
       из юнита в кольце зависимостей — оттуда вставка не работает. Один
       исходник, два машинных кода;
    5. независимо написанный оракул.

  Первые четыре тождественны по действиям и порядку, поэтому сверяются ДО
  БИТА. Пятое написано иначе — точные величины до единицы, вещественные с
  допуском. Расхождение любых двух — находка сама по себе, без второй сборки
  для сравнения. }

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
  SysUtils, chimera_body, chimera_tape_types;

{ Прогон органа: пять тел, четыре сверки, вклад в общий итог. }
function ChiTapeRun(const Tape: TChiTape): Int64;

implementation

uses
  chimera_tape_v3, chimera_tape_v4;

{ ═══ Тело 1: монолит ══════════════════════════════════════════════════════

  Всё в локальных переменных, один цикл, `with` над элементом, досрочный
  выход. Ничего не вынесено и не причёсано — это и есть предмет проверки. }

function TapeMonolith(const Tape: TChiTape; var BuyMin, SellMin: TChiMinuteRing;
  out Steps, Bucketed, Minuted: Int64): TChiSum;
var
  M, Sk, J, OldJ, CurMinute:                          Integer;
  Trades15s, Trades5s, PbCount:                       Integer;
  First, W5s, W15s, W30s, W1m, W5m, W15m, W30m, Stop: TDateTime;
  PbStart, PbEnd, PbX:                                TDateTime;
  PreVol, BuyVol, SellVol:                            Single;
  PreCoin, BuyCoin, SellCoin:                         Single;
  Buy1m, Sell1m, BuyQ1m, SellQ1m:                     Single;
  Buy15m, Sell15m, Buy30m, Sell30m:                   Single;
  BuyN, SellN, BuyQN, SellQN:                         Single;
  Vol5s, Vol15s, Vol30s, CurVol, AvgVol:              Double;
  MinD15s, LastAvgDx, NearPrice:                      Double;
  MinM, MaxM, Min5M, Max5M, MinLast, MaxLast:         Double;
  Bq, Last:                                           Double;
  PdfLow, PdfHi:                                      Boolean;
  Splits:                                             TChiSplits;
  Digest:                                             UInt64;
  St:                                                 TChiTapeState;
begin
  First := Tape[High(Tape)].Time;
  W5s  := First - 5 / ChiSecsPerDay;
  W15s := First - 15 / ChiSecsPerDay;
  W30s := First - 30 / ChiSecsPerDay;
  W1m  := First - 1 / ChiMinsPerDay;
  W5m  := First - 5 / ChiMinsPerDay;
  W15m := First - 15 / ChiMinsPerDay;
  W30m := First - 30 / ChiMinsPerDay;
  Stop := W30m;
  CurMinute := Trunc(First * ChiMinsPerDay) mod ChiMinutes;

  FillChar(Splits, SizeOf(Splits), 0);
  Last := Tape[High(Tape)].Price;
  PreVol := 0;   BuyVol := 0;   SellVol := 0;
  PreCoin := 0;  BuyCoin := 0;  SellCoin := 0;
  Buy1m := 0;    Sell1m := 0;   BuyQ1m := 0;   SellQ1m := 0;
  Buy15m := 0;   Sell15m := 0;  Buy30m := 0;   Sell30m := 0;
  BuyN := 0;     SellN := 0;    BuyQN := 0;    SellQN := 0;
  Vol5s := 0;    Vol15s := 0;   Vol30s := 0;   CurVol := 0;   AvgVol := 0;
  MinD15s := -1; LastAvgDx := 0; NearPrice := Last;
  MinM := Last;  MaxM := Last;  Min5M := Last; Max5M := Last;
  MinLast := Last; MaxLast := Last;
  PbStart := 0;  PbEnd := 0;    PbX := 0;
  Trades15s := 0; Trades5s := 0; PbCount := 0;
  PdfLow := False; PdfHi := False;
  OldJ := ChiMinutes + 1;
  Steps := 0; Bucketed := 0; Minuted := 0;
  Digest := ChiOffset;

  for M := High(Tape) downto 0 do
    with Tape[M] do
    begin
      Bq := Price * Quantity;

      if AvgVol < 1E-12 then AvgVol := Quantity;
      AvgVol := (AvgVol * 99 + Quantity) / 100;

      { Корзина по десятой доле секунды от свежайшего принта. }
      Sk := Trunc(Abs(First - Time) * ChiTenthsPerDay);
      if Sk < ChiTenthsPerMin then CurVol := CurVol + Bq;

      if (Sk <= ChiHighSplit) and (Sk >= 0) then
      begin
        if Splits[Sk].Count = 0 then
        begin
          Splits[Sk].MinP := Price;
          Splits[Sk].MaxP := Price;
        end;
        if Price > Splits[Sk].MaxP then Splits[Sk].MaxP := Price;
        if Price < Splits[Sk].MinP then Splits[Sk].MinP := Price;
        if Side = csSell then
          Splits[Sk].Sv := Splits[Sk].Sv + Bq
        else
          Splits[Sk].Bv := Splits[Sk].Bv + Bq;
        Inc(Splits[Sk].Count);
        Splits[Sk].AvgP := Splits[Sk].AvgP + Quantity;
        Inc(Bucketed);
      end;

      { Кольцо минут: индекс считается назад от текущей минуты и заворачивается
        через ноль; ячейка обнуляется лениво, при первой встрече минуты. }
      J := Round(Abs(First - Time) * ChiMinsPerDay);
      if (J < ChiMinutes) and (J >= 0) then
      begin
        J := CurMinute - J;
        if J < 0 then J := ChiMinutes + J;
        if OldJ <> J then
        begin
          BuyMin[J] := 0;
          SellMin[J] := 0;
          OldJ := J;
        end;
        if Side = csSell then
          SellMin[J] := SellMin[J] + Bq
        else
          BuyMin[J] := BuyMin[J] + Bq;
        Inc(Minuted);
      end;

      { Окно «последние N сделок» — по расстоянию от конца, не по времени. }
      if High(Tape) - M < ChiLastN then
      begin
        if Side = csSell then
        begin
          SellN := SellN + Bq;
          SellQN := SellQN + Quantity;
        end
        else
        begin
          BuyN := BuyN + Bq;
          BuyQN := BuyQN + Quantity;
        end;
      end;

      if Time > W30s then
      begin
        Vol30s := Vol30s + Bq;
        if Time > W15s then Vol15s := Vol15s + Bq;
        if Time > W5s then
        begin
          Inc(Trades5s);
          Vol5s := Vol5s + Bq;
        end;
      end;

      { Окно пятнадцати секунд: счёт принтов, минимальный шаг цены от опорной,
        признаки хода вверх и вниз, разреженный счётчик секунд. }
      if Time > W15s then
      begin
        if PbStart < 1E-12 then PbStart := Time;
        PbEnd := Time;
        if Abs(Time - PbX) > 0.99 / ChiSecsPerDay then
        begin
          Inc(PbCount);
          PbX := Time;
        end;
        Inc(Trades15s);
        if MinD15s < 0 then
          MinD15s := Abs(Price - Last)
        else if Abs(Price - Last) < MinD15s then
          MinD15s := Abs(Price - Last);
        PdfLow := PdfLow or (Price < Last);
        PdfHi := PdfHi or (Price > Last);
      end;

      { Ближайшая к опорной цена: не минимум и не максимум, а наименьшее
        отклонение — накопитель, который живёт через весь цикл. }
      if Abs(Price - Last) < LastAvgDx then
      begin
        LastAvgDx := Abs(Price - Last);
        NearPrice := Price;
      end;
      if LastAvgDx < 1E-15 then
      begin
        LastAvgDx := Abs(Price - Last);
        NearPrice := Price;
      end;

      if Time > W1m then
      begin
        if Price > MaxM then MaxM := Price;
        if Price < MinM then MinM := Price;
        if Side = csSell then
        begin
          Sell1m := Sell1m + Bq;
          SellQ1m := SellQ1m + Quantity;
        end
        else
        begin
          Buy1m := Buy1m + Bq;
          BuyQ1m := BuyQ1m + Quantity;
        end;
        if Price > MaxLast then MaxLast := Price;
        if Price < MinLast then MinLast := Price;
      end;

      if Time > W5m then
      begin
        if Price > Max5M then Max5M := Price;
        if Price < Min5M then Min5M := Price;
        { Предпамп: покупки в дальнем окне. }
        if Side = csBuy then
        begin
          PreVol := PreVol + Bq;
          PreCoin := PreCoin + Quantity;
        end;
      end;

      if Time > W15m then
      begin
        if Side = csSell then Sell15m := Sell15m + Bq else Buy15m := Buy15m + Bq;
      end;

      if Time > W30m then
      begin
        if Side = csSell then
        begin
          Sell30m := Sell30m + Bq;
          SellVol := SellVol + Bq;
          SellCoin := SellCoin + Quantity;
        end
        else
        begin
          Buy30m := Buy30m + Bq;
          BuyVol := BuyVol + Bq;
          BuyCoin := BuyCoin + Quantity;
        end;
      end;

      Inc(Steps);
      Digest := ChiMix(Digest, Sk);
      Digest := ChiMix(Digest, J);
      if Time < Stop then Break;
    end;

  { Слив локалов в общую форму ответа — уже после цикла, чтобы во время него
    ни одно значение не жило в памяти вместо регистра. }
  St := Default(TChiTapeState);
  St.PreVol := PreVol;   St.BuyVol := BuyVol;    St.SellVol := SellVol;
  St.PreCoin := PreCoin; St.BuyCoin := BuyCoin;  St.SellCoin := SellCoin;
  St.Buy1m := Buy1m;     St.Sell1m := Sell1m;
  St.BuyQ1m := BuyQ1m;   St.SellQ1m := SellQ1m;
  St.Buy15m := Buy15m;   St.Sell15m := Sell15m;
  St.Buy30m := Buy30m;   St.Sell30m := Sell30m;
  St.BuyN := BuyN;       St.SellN := SellN;
  St.BuyQN := BuyQN;     St.SellQN := SellQN;
  St.Vol5s := Vol5s;     St.Vol15s := Vol15s;    St.Vol30s := Vol30s;
  St.CurVol := CurVol;   St.AvgVol := AvgVol;
  St.MinD15s := MinD15s; St.LastAvgDx := LastAvgDx; St.NearPrice := NearPrice;
  St.MinM := MinM;       St.MaxM := MaxM;
  St.Min5M := Min5M;     St.Max5M := Max5M;
  St.MinLast := MinLast; St.MaxLast := MaxLast;
  St.PbStart := PbStart; St.PbEnd := PbEnd;      St.PbX := PbX;
  St.Trades15s := Trades15s; St.Trades5s := Trades5s; St.PbCount := PbCount;
  St.PdfLow := PdfLow;   St.PdfHi := PdfHi;      St.OldJ := OldJ;
  St.Steps := Steps;     St.Bucketed := Bucketed; St.Minuted := Minuted;
  St.Splits := Splits;
  St.BuyMin := BuyMin;   St.SellMin := SellMin;
  St.Digest := Digest;
  ChiTapeStateToSum(St, Result);
  Result.Digest := ChiTapeFoldTail(St);
end;

{ ═══ Тело 2: разрезанное по швам, состояние ездит записью ═════════════════

  Текст не переписан — он разрезан. Куски получают состояние записью через
  `var`, поэтому во время цикла оно живёт не в регистрах, а в памяти. Вставить
  такие куски компилятор отказывается: он не может доказать, что запись по
  ссылке не пересекается с `const`-параметром, и от вставки отступает целиком.
  Значит это ещё и честная форма «много кадров, ни одной вставки». }

procedure StepAverage(var St: TChiTapeState; const T: TChiTrade);
begin
  if St.AvgVol < 1E-12 then St.AvgVol := T.Quantity;
  St.AvgVol := (St.AvgVol * 99 + T.Quantity) / 100;
end;

procedure StepSplit(var St: TChiTapeState; const T: TChiTrade; Sk: Integer;
  const Bq: Double);
begin
  if Sk < ChiTenthsPerMin then St.CurVol := St.CurVol + Bq;
  if (Sk <= ChiHighSplit) and (Sk >= 0) then
  begin
    if St.Splits[Sk].Count = 0 then
    begin
      St.Splits[Sk].MinP := T.Price;
      St.Splits[Sk].MaxP := T.Price;
    end;
    if T.Price > St.Splits[Sk].MaxP then St.Splits[Sk].MaxP := T.Price;
    if T.Price < St.Splits[Sk].MinP then St.Splits[Sk].MinP := T.Price;
    if T.Side = csSell then
      St.Splits[Sk].Sv := St.Splits[Sk].Sv + Bq
    else
      St.Splits[Sk].Bv := St.Splits[Sk].Bv + Bq;
    Inc(St.Splits[Sk].Count);
    St.Splits[Sk].AvgP := St.Splits[Sk].AvgP + T.Quantity;
    Inc(St.Bucketed);
  end;
end;

function StepMinute(var St: TChiTapeState; const T: TChiTrade;
  const W: TChiWindows; const Bq: Double): Integer;
begin
  Result := Round(Abs(W.First - T.Time) * ChiMinsPerDay);
  if (Result < ChiMinutes) and (Result >= 0) then
  begin
    Result := W.CurMinute - Result;
    if Result < 0 then Result := ChiMinutes + Result;
    if St.OldJ <> Result then
    begin
      St.BuyMin[Result] := 0;
      St.SellMin[Result] := 0;
      St.OldJ := Result;
    end;
    if T.Side = csSell then
      St.SellMin[Result] := St.SellMin[Result] + Bq
    else
      St.BuyMin[Result] := St.BuyMin[Result] + Bq;
    Inc(St.Minuted);
  end;
end;

procedure StepLastN(var St: TChiTapeState; const T: TChiTrade;
  Distance: Integer; const Bq: Double);
begin
  if Distance >= ChiLastN then Exit;
  if T.Side = csSell then
  begin
    St.SellN := St.SellN + Bq;
    St.SellQN := St.SellQN + T.Quantity;
  end
  else
  begin
    St.BuyN := St.BuyN + Bq;
    St.BuyQN := St.BuyQN + T.Quantity;
  end;
end;

procedure StepSeconds(var St: TChiTapeState; const T: TChiTrade;
  const W: TChiWindows; const Bq: Double);
begin
  if T.Time > W.W30s then
  begin
    St.Vol30s := St.Vol30s + Bq;
    if T.Time > W.W15s then St.Vol15s := St.Vol15s + Bq;
    if T.Time > W.W5s then
    begin
      Inc(St.Trades5s);
      St.Vol5s := St.Vol5s + Bq;
    end;
  end;
end;

procedure StepFifteen(var St: TChiTapeState; const T: TChiTrade;
  const W: TChiWindows; const Last: Double);
begin
  if T.Time <= W.W15s then Exit;
  if St.PbStart < 1E-12 then St.PbStart := T.Time;
  St.PbEnd := T.Time;
  if Abs(T.Time - St.PbX) > 0.99 / ChiSecsPerDay then
  begin
    Inc(St.PbCount);
    St.PbX := T.Time;
  end;
  Inc(St.Trades15s);
  if St.MinD15s < 0 then
    St.MinD15s := Abs(T.Price - Last)
  else if Abs(T.Price - Last) < St.MinD15s then
    St.MinD15s := Abs(T.Price - Last);
  St.PdfLow := St.PdfLow or (T.Price < Last);
  St.PdfHi := St.PdfHi or (T.Price > Last);
end;

procedure StepNearest(var St: TChiTapeState; const T: TChiTrade;
  const Last: Double);
begin
  if Abs(T.Price - Last) < St.LastAvgDx then
  begin
    St.LastAvgDx := Abs(T.Price - Last);
    St.NearPrice := T.Price;
  end;
  if St.LastAvgDx < 1E-15 then
  begin
    St.LastAvgDx := Abs(T.Price - Last);
    St.NearPrice := T.Price;
  end;
end;

procedure StepLong(var St: TChiTapeState; const T: TChiTrade;
  const W: TChiWindows; const Bq: Double);
begin
  if T.Time > W.W1m then
  begin
    if T.Price > St.MaxM then St.MaxM := T.Price;
    if T.Price < St.MinM then St.MinM := T.Price;
    if T.Side = csSell then
    begin
      St.Sell1m := St.Sell1m + Bq;
      St.SellQ1m := St.SellQ1m + T.Quantity;
    end
    else
    begin
      St.Buy1m := St.Buy1m + Bq;
      St.BuyQ1m := St.BuyQ1m + T.Quantity;
    end;
    if T.Price > St.MaxLast then St.MaxLast := T.Price;
    if T.Price < St.MinLast then St.MinLast := T.Price;
  end;

  if T.Time > W.W5m then
  begin
    if T.Price > St.Max5M then St.Max5M := T.Price;
    if T.Price < St.Min5M then St.Min5M := T.Price;
    if T.Side = csBuy then
    begin
      St.PreVol := St.PreVol + Bq;
      St.PreCoin := St.PreCoin + T.Quantity;
    end;
  end;

  if T.Time > W.W15m then
  begin
    if T.Side = csSell then
      St.Sell15m := St.Sell15m + Bq
    else
      St.Buy15m := St.Buy15m + Bq;
  end;

  if T.Time > W.W30m then
  begin
    if T.Side = csSell then
    begin
      St.Sell30m := St.Sell30m + Bq;
      St.SellVol := St.SellVol + Bq;
      St.SellCoin := St.SellCoin + T.Quantity;
    end
    else
    begin
      St.Buy30m := St.Buy30m + Bq;
      St.BuyVol := St.BuyVol + Bq;
      St.BuyCoin := St.BuyCoin + T.Quantity;
    end;
  end;
end;

function TapeSplitBody(const Tape: TChiTape): TChiSum;
var
  St: TChiTapeState;
  W: TChiWindows;
  M, Sk, J: Integer;
  Bq, Last: Double;
begin
  ChiTapeWindows(Tape, W);
  ChiTapeStateInit(St, Tape);
  Last := Tape[High(Tape)].Price;

  for M := High(Tape) downto 0 do
  begin
    Bq := Tape[M].Price * Tape[M].Quantity;
    StepAverage(St, Tape[M]);
    Sk := Trunc(Abs(W.First - Tape[M].Time) * ChiTenthsPerDay);
    StepSplit(St, Tape[M], Sk, Bq);
    J := StepMinute(St, Tape[M], W, Bq);
    StepLastN(St, Tape[M], High(Tape) - M, Bq);
    StepSeconds(St, Tape[M], W, Bq);
    StepFifteen(St, Tape[M], W, Last);
    StepNearest(St, Tape[M], Last);
    StepLong(St, Tape[M], W, Bq);
    Inc(St.Steps);
    St.Digest := ChiMix(St.Digest, Sk);
    St.Digest := ChiMix(St.Digest, J);
    if Tape[M].Time < W.Stop then Break;
  end;

  ChiTapeStateToSum(St, Result);
  Result.Digest := ChiTapeFoldTail(St);
end;

{ ═══ Тело 5: независимо написанный оракул ════════════════════════════════

  Порядок обхода тот же — он часть спецификации, а не стиля: сложение
  вещественных не переставляется. Всё остальное написано иначе: без `with`,
  без досрочного выхода (нижняя граница найдена заранее отдельным поиском),
  направление спрошено сравнением, а не битом знака, ветки разложены другими
  условиями, промежуточные значения названы по-своему. }

function StopIndex(const Tape: TChiTape; const Stop: TDateTime): Integer;
var
  I: Integer;
begin
  { Живая форма обрывается НА первом элементе, ушедшем за границу, то есть он
    обработан. Значит нижняя граница обхода — он сам. }
  Result := 0;
  for I := High(Tape) downto 0 do
    if Tape[I].Time < Stop then
    begin
      Result := I;
      Break;
    end;
end;

function TapeFlatBody(const Tape: TChiTape): TChiSum;
var
  St: TChiTapeState;
  W: TChiWindows;
  M, Sk, J, Low, Dist: Integer;
  Bq, Qty, Prc, Tm, Last, Delta: Double;
  Sell: Boolean;
begin
  ChiTapeWindows(Tape, W);
  ChiTapeStateInit(St, Tape);
  Last := Tape[High(Tape)].Price;
  Low := StopIndex(Tape, W.Stop);

  for M := High(Tape) downto Low do
  begin
    Prc := Tape[M].Price;
    Qty := Abs(Tape[M].Qty);
    Tm := Tape[M].Time;
    Sell := Tape[M].Qty < 0;
    Bq := Prc * Qty;
    Dist := High(Tape) - M;
    Delta := Abs(Prc - Last);

    if St.AvgVol < 1E-12 then St.AvgVol := Qty;
    St.AvgVol := (St.AvgVol * 99 + Qty) / 100;

    Sk := Trunc(Abs(W.First - Tm) * ChiTenthsPerDay);
    if Sk < ChiTenthsPerMin then St.CurVol := St.CurVol + Bq;

    if (Sk >= 0) and (Sk <= ChiHighSplit) then
    begin
      if St.Splits[Sk].Count = 0 then
      begin
        St.Splits[Sk].MinP := Prc;
        St.Splits[Sk].MaxP := Prc;
      end
      else
      begin
        if Prc > St.Splits[Sk].MaxP then St.Splits[Sk].MaxP := Prc;
        if Prc < St.Splits[Sk].MinP then St.Splits[Sk].MinP := Prc;
      end;
      if Sell then
        St.Splits[Sk].Sv := St.Splits[Sk].Sv + Bq
      else
        St.Splits[Sk].Bv := St.Splits[Sk].Bv + Bq;
      St.Splits[Sk].Count := St.Splits[Sk].Count + 1;
      St.Splits[Sk].AvgP := St.Splits[Sk].AvgP + Qty;
      St.Bucketed := St.Bucketed + 1;
    end;

    J := Round(Abs(W.First - Tm) * ChiMinsPerDay);
    if (J >= 0) and (J < ChiMinutes) then
    begin
      J := W.CurMinute - J;
      if J < 0 then J := J + ChiMinutes;
      if St.OldJ <> J then
      begin
        St.BuyMin[J] := 0;
        St.SellMin[J] := 0;
        St.OldJ := J;
      end;
      if Sell then
        St.SellMin[J] := St.SellMin[J] + Bq
      else
        St.BuyMin[J] := St.BuyMin[J] + Bq;
      St.Minuted := St.Minuted + 1;
    end;

    if Dist < ChiLastN then
      if Sell then
      begin
        St.SellN := St.SellN + Bq;
        St.SellQN := St.SellQN + Qty;
      end
      else
      begin
        St.BuyN := St.BuyN + Bq;
        St.BuyQN := St.BuyQN + Qty;
      end;

    if Tm > W.W30s then
    begin
      St.Vol30s := St.Vol30s + Bq;
      if Tm > W.W15s then St.Vol15s := St.Vol15s + Bq;
      if Tm > W.W5s then
      begin
        St.Trades5s := St.Trades5s + 1;
        St.Vol5s := St.Vol5s + Bq;
      end;
    end;

    if Tm > W.W15s then
    begin
      if St.PbStart < 1E-12 then St.PbStart := Tm;
      St.PbEnd := Tm;
      if Abs(Tm - St.PbX) > 0.99 / ChiSecsPerDay then
      begin
        St.PbCount := St.PbCount + 1;
        St.PbX := Tm;
      end;
      St.Trades15s := St.Trades15s + 1;
      if St.MinD15s < 0 then
        St.MinD15s := Delta
      else if Delta < St.MinD15s then
        St.MinD15s := Delta;
      if Prc < Last then St.PdfLow := True;
      if Prc > Last then St.PdfHi := True;
    end;

    if Delta < St.LastAvgDx then
    begin
      St.LastAvgDx := Delta;
      St.NearPrice := Prc;
    end;
    if St.LastAvgDx < 1E-15 then
    begin
      St.LastAvgDx := Delta;
      St.NearPrice := Prc;
    end;

    if Tm > W.W1m then
    begin
      if Prc > St.MaxM then St.MaxM := Prc;
      if Prc < St.MinM then St.MinM := Prc;
      if Sell then
      begin
        St.Sell1m := St.Sell1m + Bq;
        St.SellQ1m := St.SellQ1m + Qty;
      end
      else
      begin
        St.Buy1m := St.Buy1m + Bq;
        St.BuyQ1m := St.BuyQ1m + Qty;
      end;
      if Prc > St.MaxLast then St.MaxLast := Prc;
      if Prc < St.MinLast then St.MinLast := Prc;
    end;

    if Tm > W.W5m then
    begin
      if Prc > St.Max5M then St.Max5M := Prc;
      if Prc < St.Min5M then St.Min5M := Prc;
      if not Sell then
      begin
        St.PreVol := St.PreVol + Bq;
        St.PreCoin := St.PreCoin + Qty;
      end;
    end;

    if Tm > W.W15m then
      if Sell then
        St.Sell15m := St.Sell15m + Bq
      else
        St.Buy15m := St.Buy15m + Bq;

    if Tm > W.W30m then
      if Sell then
      begin
        St.Sell30m := St.Sell30m + Bq;
        St.SellVol := St.SellVol + Bq;
        St.SellCoin := St.SellCoin + Qty;
      end
      else
      begin
        St.Buy30m := St.Buy30m + Bq;
        St.BuyVol := St.BuyVol + Bq;
        St.BuyCoin := St.BuyCoin + Qty;
      end;

    St.Steps := St.Steps + 1;
    St.Digest := ChiMix(St.Digest, Sk);
    St.Digest := ChiMix(St.Digest, J);
  end;

  ChiTapeStateToSum(St, Result);
  Result.Digest := ChiTapeFoldTail(St);
end;

{ ═══ Прогон органа ═══════════════════════════════════════════════════════ }

function ChiTapeRun(const Tape: TChiTape): Int64;
var
  Mono, Split, V3, V4, Flat: TChiSum;
  BuyMin, SellMin: TChiMinuteRing;
  Steps, Bucketed, Minuted: Int64;
begin
  ChiClaim(SizeOf(TChiTrade) = 16, 'лента: запись не шестнадцать байт');
  if Length(Tape) < 2 then
  begin
    ChiClaim(False, 'лента: слишком короткая лента');
    Exit(0);
  end;

  FillChar(BuyMin, SizeOf(BuyMin), 0);
  FillChar(SellMin, SizeOf(SellMin), 0);
  Mono := TapeMonolith(Tape, BuyMin, SellMin, Steps, Bucketed, Minuted);
  Split := TapeSplitBody(Tape);
  V3 := ChiTapeV3(Tape);
  V4 := ChiTapeV4(Tape);
  Flat := TapeFlatBody(Tape);

  { Первые четыре тождественны по действиям и порядку — сверка до бита. }
  ChiSame(Mono, Split, 'лента монолит/дроблёный');
  ChiSame(Mono, V3, 'лента монолит/вставка из листового');
  ChiSame(Mono, V4, 'лента монолит/шаги из кольца');
  ChiSame(V3, V4, 'лента вставка/без вставки');
  { Пятое написано иначе — точные до единицы, вещественные с допуском. }
  ChiClose(Mono, Flat, 'лента монолит/оракул');

  { Счётчики, отданные монолитом отдельными параметрами, обязаны совпасть с
    тем, что он же положил в общую форму: вывод через `out` и вывод через
    запись — разные дороги. }
  ChiClaim(Steps = Mono.Exact[0], 'лента: счёт шагов разошёлся с формой');
  ChiClaim(Bucketed = Mono.Exact[1], 'лента: счёт корзин разошёлся с формой');
  ChiClaim(Minuted = Mono.Exact[2], 'лента: счёт минут разошёлся с формой');

  Result := ChiFold(Mono);
end;

end.
