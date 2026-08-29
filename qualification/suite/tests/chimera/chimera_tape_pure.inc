{ Тело прохода по ленте, собранное из чистых шагов.

  Файл подключается ДВУМЯ юнитами. Один берёт шаги из листового юнита — там
  вставка тел работает. Второй берёт их из юнита, затянутого в кольцо
  зависимостей, — там вставка не работает. Текст при этом один и тот же до
  буквы: разница только в том, откуда пришли шаги.

  Накопители — в локальных переменных, как в монолите: смысл этого тела не в
  том, чтобы разгрузить регистры, а в том, чтобы АРИФМЕТИКА уехала за вызовы,
  которые компилятор волен вставить, а волен и не вставить. }

function TapePure(const Tape: TChiTape): TChiSum;
var
  M, Sk, J, Raw, OldJ:                        Integer;
  Trades15s, Trades5s, PbCount:               Integer;
  W:                                          TChiWindows;
  PbStart, PbEnd, PbX:                        TDateTime;
  PreVol, BuyVol, SellVol:                    Single;
  PreCoin, BuyCoin, SellCoin:                 Single;
  Buy1m, Sell1m, BuyQ1m, SellQ1m:             Single;
  Buy15m, Sell15m, Buy30m, Sell30m:           Single;
  BuyN, SellN, BuyQN, SellQN:                 Single;
  Vol5s, Vol15s, Vol30s, CurVol, AvgVol:      Double;
  MinD15s, LastAvgDx, NearPrice:              Double;
  MinM, MaxM, Min5M, Max5M, MinLast, MaxLast: Double;
  Bq, Last, Qty, Prc, Delta:                  Double;
  Sell:                                       Boolean;
  PdfLow, PdfHi:                              Boolean;
  Splits:                                     TChiSplits;
  BuyMin, SellMin:                            TChiMinuteRing;
  Digest:                                     UInt64;
  Steps, Bucketed, Minuted:                   Int64;
  St:                                         TChiTapeState;
begin
  ChiTapeWindows(Tape, W);
  FillChar(Splits, SizeOf(Splits), 0);
  FillChar(BuyMin, SizeOf(BuyMin), 0);
  FillChar(SellMin, SizeOf(SellMin), 0);
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
  begin
    Prc := Tape[M].Price;
    Qty := Tape[M].Quantity;
    Bq := XNotional(Tape[M]);
    Sell := XIsSell(Tape[M]);
    Delta := XDelta(Prc, Last);

    if AvgVol < 1E-12 then AvgVol := Qty;
    AvgVol := XEma(AvgVol, Qty);

    Sk := XBucket(W.First, Tape[M].Time);
    if Sk < ChiTenthsPerMin then CurVol := CurVol + Bq;

    if (Sk <= ChiHighSplit) and (Sk >= 0) then
    begin
      if Splits[Sk].Count = 0 then
      begin
        Splits[Sk].MinP := Prc;
        Splits[Sk].MaxP := Prc;
      end;
      if Prc > Splits[Sk].MaxP then Splits[Sk].MaxP := Prc;
      if Prc < Splits[Sk].MinP then Splits[Sk].MinP := Prc;
      if Sell then
        Splits[Sk].Sv := Splits[Sk].Sv + Bq
      else
        Splits[Sk].Bv := Splits[Sk].Bv + Bq;
      Inc(Splits[Sk].Count);
      Splits[Sk].AvgP := Splits[Sk].AvgP + Qty;
      Inc(Bucketed);
    end;

    Raw := XMinuteRaw(W.First, Tape[M].Time);
    J := Raw;
    if (Raw < ChiMinutes) and (Raw >= 0) then
    begin
      J := XMinuteSlot(Raw, W.CurMinute);
      if OldJ <> J then
      begin
        BuyMin[J] := 0;
        SellMin[J] := 0;
        OldJ := J;
      end;
      if Sell then
        SellMin[J] := SellMin[J] + Bq
      else
        BuyMin[J] := BuyMin[J] + Bq;
      Inc(Minuted);
    end;

    if High(Tape) - M < ChiLastN then
    begin
      if Sell then
      begin
        SellN := SellN + Bq;
        SellQN := SellQN + Qty;
      end
      else
      begin
        BuyN := BuyN + Bq;
        BuyQN := BuyQN + Qty;
      end;
    end;

    if XAfter(Tape[M].Time, W.W30s) then
    begin
      Vol30s := Vol30s + Bq;
      if XAfter(Tape[M].Time, W.W15s) then Vol15s := Vol15s + Bq;
      if XAfter(Tape[M].Time, W.W5s) then
      begin
        Inc(Trades5s);
        Vol5s := Vol5s + Bq;
      end;
    end;

    if XAfter(Tape[M].Time, W.W15s) then
    begin
      if PbStart < 1E-12 then PbStart := Tape[M].Time;
      PbEnd := Tape[M].Time;
      if not XSameSecond(Tape[M].Time, PbX) then
      begin
        Inc(PbCount);
        PbX := Tape[M].Time;
      end;
      Inc(Trades15s);
      if MinD15s < 0 then
        MinD15s := Delta
      else if Delta < MinD15s then
        MinD15s := Delta;
      PdfLow := PdfLow or (Prc < Last);
      PdfHi := PdfHi or (Prc > Last);
    end;

    if Delta < LastAvgDx then
    begin
      LastAvgDx := Delta;
      NearPrice := Prc;
    end;
    if LastAvgDx < 1E-15 then
    begin
      LastAvgDx := Delta;
      NearPrice := Prc;
    end;

    if XAfter(Tape[M].Time, W.W1m) then
    begin
      if Prc > MaxM then MaxM := Prc;
      if Prc < MinM then MinM := Prc;
      if Sell then
      begin
        Sell1m := Sell1m + Bq;
        SellQ1m := SellQ1m + Qty;
      end
      else
      begin
        Buy1m := Buy1m + Bq;
        BuyQ1m := BuyQ1m + Qty;
      end;
      if Prc > MaxLast then MaxLast := Prc;
      if Prc < MinLast then MinLast := Prc;
    end;

    if XAfter(Tape[M].Time, W.W5m) then
    begin
      if Prc > Max5M then Max5M := Prc;
      if Prc < Min5M then Min5M := Prc;
      if not Sell then
      begin
        PreVol := PreVol + Bq;
        PreCoin := PreCoin + Qty;
      end;
    end;

    if XAfter(Tape[M].Time, W.W15m) then
    begin
      if Sell then Sell15m := Sell15m + Bq else Buy15m := Buy15m + Bq;
    end;

    if XAfter(Tape[M].Time, W.W30m) then
    begin
      if Sell then
      begin
        Sell30m := Sell30m + Bq;
        SellVol := SellVol + Bq;
        SellCoin := SellCoin + Qty;
      end
      else
      begin
        Buy30m := Buy30m + Bq;
        BuyVol := BuyVol + Bq;
        BuyCoin := BuyCoin + Qty;
      end;
    end;

    Inc(Steps);
    Digest := ChiMix(Digest, Sk);
    Digest := ChiMix(Digest, J);
    if Tape[M].Time < W.Stop then Break;
  end;

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
