unit chimera_tape_types;

{ Типы и общая оснастка органа «лента». Юнит листовой намеренно: его подключают
  все тела органа, и он не имеет права затащить их в кольцо зависимостей —
  иначе вставка тел, ради которой всё затевалось, умрёт молча. }

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch INLINEVARS}
{$endif}
{$Q-}{$R-}

interface

uses
  SysUtils, chimera_body;

const
  { Корзины по десятой доле секунды, тридцать секунд глубиной. }
  ChiHighSplit = 299;
  { Кольцо минутных объёмов: час назад. }
  ChiMinutes = 60;
  { Окно «последние N сделок» — по расстоянию от конца ленты, а не по времени:
    ещё одна ось, независимая от часов. }
  ChiLastN = 40;

type
  TChiSplit = record
    MinP, MaxP: Single;
    AvgP:       Single;
    Bv, Sv:     Single;
    Count:      Integer;
  end;

  TChiSplits = array [0 .. ChiHighSplit] of TChiSplit;
  TChiMinuteRing = array [0 .. ChiMinutes - 1] of Double;

  { Состояние прохода. Монолит его НЕ использует — он держит всё в локальных
    переменных, как оригинал; запись нужна дроблёным телам, чтобы возить
    состояние между кусками. В этом и разница нагрузки на распределитель. }
  TChiTapeState = record
    PreVol, BuyVol, SellVol:        Single;
    PreCoin, BuyCoin, SellCoin:     Single;
    Buy1m, Sell1m, BuyQ1m, SellQ1m: Single;
    Buy15m, Sell15m:                Single;
    Buy30m, Sell30m:                Single;
    BuyN, SellN, BuyQN, SellQN:     Single;
    Vol5s, Vol15s, Vol30s:          Double;
    CurVol, AvgVol:                 Double;
    MinD15s, LastAvgDx, NearPrice:  Double;
    MinM, MaxM, Min5M, Max5M:       Double;
    MaxLast, MinLast:               Double;
    PbStart, PbEnd, PbX:            TDateTime;
    Trades15s, Trades5s, PbCount:   Integer;
    PdfLow, PdfHi:                  Boolean;
    OldJ:                           Integer;
    Steps, Bucketed, Minuted:       Int64;
    Digest:                         UInt64;
    Splits:                         TChiSplits;
    BuyMin, SellMin:                TChiMinuteRing;
  end;

  { Границы окон. Считаются от последней сделки ленты — так же, как живой код
    отсчитывает их от свежайшего принта, а не от системных часов. }
  TChiWindows = record
    First, W5s, W15s, W30s, W1m, W5m, W15m, W30m, Stop: TDateTime;
    CurMinute: Integer;
  end;

procedure ChiTapeWindows(const Tape: TChiTape; out W: TChiWindows);
procedure ChiTapeStateInit(out St: TChiTapeState; const Tape: TChiTape);
procedure ChiTapeStateToSum(const St: TChiTapeState; out S: TChiSum);

{ Корзины и кольцо минут в итог целиком не попадают — они сворачиваются в
  дайджест, иначе форма ответа раздулась бы до размера самих данных. }
function ChiTapeFoldTail(const St: TChiTapeState): UInt64;

implementation

procedure ChiTapeWindows(const Tape: TChiTape; out W: TChiWindows);
begin
  W.First := Tape[High(Tape)].Time;
  W.W5s  := W.First - 5 / ChiSecsPerDay;
  W.W15s := W.First - 15 / ChiSecsPerDay;
  W.W30s := W.First - 30 / ChiSecsPerDay;
  W.W1m  := W.First - 1 / ChiMinsPerDay;
  W.W5m  := W.First - 5 / ChiMinsPerDay;
  W.W15m := W.First - 15 / ChiMinsPerDay;
  W.W30m := W.First - 30 / ChiMinsPerDay;
  { Самая дальняя граница обхода: дальше неё считать нечего. }
  W.Stop := W.W30m;
  W.CurMinute := Trunc(W.First * ChiMinsPerDay) mod ChiMinutes;
end;

procedure ChiTapeStateInit(out St: TChiTapeState; const Tape: TChiTape);
var
  Last: Double;
begin
  St := Default(TChiTapeState);
  Last := Tape[High(Tape)].Price;
  St.MinM := Last;    St.MaxM := Last;
  St.Min5M := Last;   St.Max5M := Last;
  St.MinLast := Last; St.MaxLast := Last;
  St.NearPrice := Last;
  St.MinD15s := -1;
  St.OldJ := ChiMinutes + 1;
  St.Digest := ChiOffset;
end;

procedure ChiTapeStateToSum(const St: TChiTapeState; out S: TChiSum);
begin
  S := ChiSumEmpty;
  S.Exact[0] := St.Steps;
  S.Exact[1] := St.Bucketed;
  S.Exact[2] := St.Minuted;
  S.Exact[3] := St.Trades15s;
  S.Exact[4] := St.Trades5s;
  S.Exact[5] := St.PbCount;
  S.Exact[6] := Ord(St.PdfLow);
  S.Exact[7] := Ord(St.PdfHi);
  S.Exact[8] := St.OldJ;

  S.Loose[0]  := St.PreVol;    S.Loose[1]  := St.BuyVol;
  S.Loose[2]  := St.SellVol;   S.Loose[3]  := St.PreCoin;
  S.Loose[4]  := St.BuyCoin;   S.Loose[5]  := St.SellCoin;
  S.Loose[6]  := St.Buy1m;     S.Loose[7]  := St.Sell1m;
  S.Loose[8]  := St.BuyQ1m;    S.Loose[9]  := St.SellQ1m;
  S.Loose[10] := St.Buy15m;    S.Loose[11] := St.Sell15m;
  S.Loose[12] := St.Buy30m;    S.Loose[13] := St.Sell30m;
  S.Loose[14] := St.BuyN;      S.Loose[15] := St.SellN;
  S.Loose[16] := St.Vol5s;     S.Loose[17] := St.Vol15s;
  S.Loose[18] := St.Vol30s;    S.Loose[19] := St.CurVol;
  S.Loose[20] := St.AvgVol;    S.Loose[21] := St.MinD15s;
  S.Loose[22] := St.LastAvgDx; S.Loose[23] := St.NearPrice;

  S.Digest := St.Digest;
end;

function ChiTapeFoldTail(const St: TChiTapeState): UInt64;
var
  I: Integer;
begin
  Result := St.Digest;
  for I := 0 to ChiHighSplit do
  begin
    Result := ChiMix(Result, St.Splits[I].Count);
    Result := ChiMix(Result, PInteger(@St.Splits[I].Bv)^);
    Result := ChiMix(Result, PInteger(@St.Splits[I].Sv)^);
    Result := ChiMix(Result, PInteger(@St.Splits[I].MinP)^);
    Result := ChiMix(Result, PInteger(@St.Splits[I].MaxP)^);
    Result := ChiMix(Result, PInteger(@St.Splits[I].AvgP)^);
  end;
  for I := 0 to ChiMinutes - 1 do
  begin
    Result := ChiMix(Result, PInt64(@St.BuyMin[I])^);
    Result := ChiMix(Result, PInt64(@St.SellMin[I])^);
  end;
end;

end.
