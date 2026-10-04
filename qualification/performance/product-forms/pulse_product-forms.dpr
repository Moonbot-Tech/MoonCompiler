program pulse_product_forms;

{ The hot routines of a trading server as MoonBot writes them, with their data
  where MoonBot keeps it (pulse_product_model.pas: the fields of the market
  objects, the market list, the globals of Vars.pas).  Each case walks the
  markets through a local reference and calls one routine: the per-trade
  update of the recent price, the windows over the trade history (the highest
  trade, buy against sell volume, the same under the lock with the ring), the
  hour deltas over the 5-minute candles, the rebuild of the candles from the
  trades, a market looked up by name through the list and through the
  dictionary, the batch over all markets.  Every case returns a digest of
  what the routine computed, the same for Delphi 12.2 and MoonCompiler: the
  prices are multiples of 1/64 and the quantities of 1/16. Candle opens are
  64 so the percent calculations use an exact binary divisor on both systems. }

{$ifndef FPC}
  {$APPTYPE CONSOLE}
{$endif}

{$ifdef FPC}
  {$mode delphi}{$H+}
{$endif}

{$Q-}{$R-}

uses
  {$if defined(FPC) and not defined(PULSE_DEFAULT_MM)}
  mormot.core.fpcx64mm,
  {$ifend}
  {$I ../common/pulse_placement_uses.inc}
  SysUtils,
  perf_clock in '..\common\perf_clock.pas',
  pulse_process_metrics in '..\common\pulse_process_metrics.pas',
  pulse_harness in '..\common\pulse_harness.pas',
  pulse_product_model in 'pulse_product_model.pas';

{$I ../common/pulse_program_prefix.inc}

const
  { markets with trades; the list holds as many again with a name only }
  TradedMarkets = 16;
  ListedMarkets = 64;
  HistoryCount = 4096;
  RingCount = 64;
  CandleCount = 288;
  RebuildCandles = 8;
  BlockTrades = 64;
  BaseTime = 46000.0;
  { no window of a case ends on a trade or a candle: the steps do not divide
    the windows, and a rounding of a time cannot move a trade across }
  TradeStep = 0.27 / SecondsInDay;
  FeedStep = 0.027 / SecondsInDay;
  { the trades within the windows the cases ask for }
  MaxWindowTrades = 95;
  BuySellWindowTrades = 111;
  LockedWindowTrades = 111;
  HourCandles = 12;
  WindowCount = 1024;

type
  { What a case feeds the markets: the trades of a message and the names
    messages spell. }
  TFeed = class
  public
    Orders: array of THOrder;
    IntNames: array of string;
    Names: array of string;
    WindowSeconds: array[0..WindowCount - 1] of Integer;
  end;

var
  Markets: TMarkets;
  Feed: TFeed;
  RngState: UInt64 = UInt64($9E3779B97F4A7C15);

function NextRandom: UInt64;
begin
  RngState := RngState xor (RngState shl 13);
  RngState := RngState xor (RngState shr 7);
  RngState := RngState xor (RngState shl 17);
  Result := RngState;
end;

function DoubleDigest(Value: Double): UInt64;
begin
  Move(Value, Result, SizeOf(Result));
end;

function Mix(Digest: UInt64; Value: Double): UInt64;
begin
  Result := (Digest xor DoubleDigest(Value)) * UInt64($100000001B3);
end;

procedure ResetRecent(List: TMarkets);
var
  I: Integer;
begin
  for I := 0 to TradedMarkets - 1 do
    List.Items[I].ResetRecentPrice;
end;

{ Every trade of a message goes through UpdateRecentPrice of its market. }
function CaseTradeRecentPrice(Iterations: Integer): UInt64;
var
  I, J: Integer;
  List: TMarkets;
  Source: TFeed;
  M: TMarket;
  XTime: Int64;
begin
  List := Markets;
  Source := Feed;
  ResetRecent(List);
  XTime := 0;
  Result := 0;
  for I := 1 to Iterations do begin
    M := List.Items[I and (TradedMarkets - 1)];
    for J := 0 to BlockTrades - 1 do begin
      Inc(XTime, 25);
      M.UpdateRecentPrice(Source.Orders[J], Source.Orders[J].Time, XTime);
    end;
    Result := Mix(Result, M.RecentDigest);
  end;
end;

function CaseTradeMaxWindow(Iterations: Integer): UInt64;
var
  I: Integer;
  List: TMarkets;
  M: TMarket;
begin
  List := Markets;
  Result := 0;
  for I := 1 to Iterations do begin
    M := List.Items[I and (TradedMarkets - 1)];
    Result := Mix(Result, M.GetMaxTradePrice(25.5, M.LastGotTradeTime));
  end;
end;

function CaseTradeBuySell(Iterations: Integer): UInt64;
var
  I: Integer;
  List: TMarkets;
begin
  List := Markets;
  Result := 0;
  for I := 1 to Iterations do
    Result := Mix(Result, List.Items[I and (TradedMarkets - 1)].CalcBv_SV(30, (I and 16) <> 0));
end;

{ A query is the useful operation here: the precomputed window changes how
  many recent trades it scans. The fixed-window cases remain comparable. }
function CaseTradeMaxWindowChanging(Iterations: Integer): UInt64;
var
  I: Integer;
  List: TMarkets;
  Source: TFeed;
  M: TMarket;
begin
  List := Markets;
  Source := Feed;
  Result := 0;
  for I := 1 to Iterations do begin
    M := List.Items[I and (TradedMarkets - 1)];
    Result := Mix(Result, M.GetMaxTradePrice(Source.WindowSeconds[I and (WindowCount - 1)] + 0.125,
      M.LastGotTradeTime));
  end;
end;

function CaseTradeBuySellChanging(Iterations: Integer): UInt64;
var
  I: Integer;
  List: TMarkets;
  Source: TFeed;
begin
  List := Markets;
  Source := Feed;
  Result := 0;
  for I := 1 to Iterations do
    Result := Mix(Result, List.Items[I and (TradedMarkets - 1)].CalcBv_SV(
      Source.WindowSeconds[I and (WindowCount - 1)], (I and 16) <> 0));
end;

function CaseTradeBuySellLocked(Iterations: Integer): UInt64;
var
  I: Integer;
  List: TMarkets;
begin
  List := Markets;
  Result := 0;
  for I := 1 to Iterations do
    Result := Mix(Result, List.Items[I and (TradedMarkets - 1)].CalcBv_SV_Precise(30000, (I and 16) <> 0));
end;

function CaseCandleHourDeltas(Iterations: Integer): UInt64;
var
  I: Integer;
  List: TMarkets;
  M: TMarket;
begin
  List := Markets;
  Result := 0;
  for I := 1 to Iterations do begin
    M := List.Items[I and (TradedMarkets - 1)];
    M.RecalcDeltasByCandles(M.LastGotTradeTime);
    Result := Mix(Result, M.Last15mDelta);
    Result := Mix(Result, M.Last30mDelta);
    Result := Mix(Result, M.Last1hDelta);
    Result := Mix(Result, M.PumpHDelta);
    Result := Mix(Result, M.DumpHDelta);
    Result := Mix(Result, M.PumpDelta);
    Result := Mix(Result, M.AvgPrice5m);
    Result := Mix(Result, M.VisAvgPrice);
  end;
end;

function CaseCandleRebuild(Iterations: Integer): UInt64;
var
  I: Integer;
  List: TMarkets;
begin
  List := Markets;
  Result := 0;
  for I := 1 to Iterations do
    Result := Mix(Result, List.Items[I and (TradedMarkets - 1)].RebuildDeep);
end;

function CaseTradeValueLocked(Iterations: Integer): UInt64;
var
  I: Integer;
  List: TMarkets;
begin
  List := Markets;
  Result := 0;
  for I := 1 to Iterations do
    Result := Mix(Result, List.Items[I and (TradedMarkets - 1)].TradeValueLocked);
end;

function CaseMarketByIntName(Iterations: Integer): UInt64;
var
  I: Integer;
  List: TMarkets;
  Source: TFeed;
  M: TMarket;
begin
  List := Markets;
  Source := Feed;
  Result := 0;
  for I := 1 to Iterations do begin
    M := List.MarketByIntName(Source.IntNames[I and (ListedMarkets - 1)]);
    If M <> nil then
      Result := Result * 31 + UInt64(Length(M.bnMarketName)) + UInt64(I and 7);
  end;
end;

function CaseMarketByNameDict(Iterations: Integer): UInt64;
var
  I: Integer;
  List: TMarkets;
  Source: TFeed;
  M: TMarket;
begin
  List := Markets;
  Source := Feed;
  Result := 0;
  for I := 1 to Iterations do begin
    M := List.MarketByNameFast(Source.Names[I and (ListedMarkets - 1)]);
    If M <> nil then
      Result := Result * 31 + UInt64(Length(M.bnMarketName)) + UInt64(I and 7);
  end;
end;

function CaseMarketByNameGetter(Iterations: Integer): UInt64;
var
  I: Integer;
  List: TMarkets;
  Source: TFeed;
  M: TMarket;
begin
  List := Markets;
  Source := Feed;
  Result := 0;
  for I := 1 to Iterations do begin
    M := List.MarketByNameGetter(Source.Names[I and (ListedMarkets - 1)]);
    If M <> nil then
      Result := Result * 31 + UInt64(Length(M.bnMarketName)) + UInt64(I and 7);
  end;
end;

function CaseMarketsBatch(Iterations: Integer): UInt64;
var
  I: Integer;
  List: TMarkets;
  m: TMarket;
begin
  List := Markets;
  Result := 0;
  for I := 1 to Iterations do
    for m in List do begin
      m.CheckMove;
      If m.Moved then
        Inc(Result);
    end;
end;

function SymbolName(Index: Integer): string;
const
  Coins: array[0..15] of string = ('BTC', 'ETH', 'SOL', 'XRP', 'DOGE', 'ADA', 'AVAX', 'LINK',
    'DOT', 'TRX', 'LTC', 'BCH', 'NEAR', 'APT', 'ARB', 'OP');
  Quotes: array[0..3] of string = ('USDT', 'USDC', 'FDUSD', 'BTC');
begin
  Result := Coins[Index and 15] + Quotes[(Index shr 4) and 3];
end;

function IntName(Index: Integer): string;
const
  Coins: array[0..15] of string = ('btc', 'eth', 'sol', 'xrp', 'doge', 'ada', 'avax', 'link',
    'dot', 'trx', 'ltc', 'bch', 'near', 'apt', 'arb', 'op');
  Quotes: array[0..3] of string = ('usdt', 'usdc', 'fdusd', 'btc');
begin
  Result := Coins[Index and 15] + '_' + Quotes[(Index shr 4) and 3];
end;

{ A price of the market: a multiple of 1/64 around its level }
function TradePrice(Level: Integer): Single;
begin
  Result := Level + (Integer(NextRandom and 63) - 32) / 64;
end;

procedure InitializeData;
var
  I, J, Index: Integer;
  M: TMarket;
  T, NowTime: TDateTime;
  Level: Integer;
  Q: Single;
begin
  Markets := TMarkets.Create;
  for I := 0 to ListedMarkets - 1 do begin
    M := TMarket.Create(SymbolName(I));
    Markets.Add(M);
    Level := 64 + I;
    M.PrevPrice := Level;
    M.LastBid := Level + ((I * 7) mod 9 - 4) / 4;
    M.LastAsk := M.LastBid + 1 / 64;
    If I >= TradedMarkets then
      Continue;
    SetLength(M.OrdersH, HistoryCount);
    M.OrdersHCount := HistoryCount;
    for J := 0 to HistoryCount - 1 do begin
      M.OrdersH[J].Time := BaseTime + (J + 0.5) * TradeStep;
      M.OrdersH[J].Price := TradePrice(Level);
      Q := (Integer((NextRandom shr 8) and 255) + 1) / 16;
      If (NextRandom shr 20) and 1 = 0 then
        M.OrdersH[J].Qty := Q
      else
        M.OrdersH[J].Qty := -Q;
    end;
    { the newest trades wait in the ring, across its end }
    SetLength(M.tmpList, IntTradesBufSize);
    M.tmpTradesRead := IntTradesBufSize - RingCount div 2;
    M.tmpTradesWrite := (M.tmpTradesRead + RingCount) mod IntTradesBufSize;
    for J := 0 to RingCount - 1 do begin
      Index := (M.tmpTradesRead + J) mod IntTradesBufSize;
      M.tmpList[Index].Time := BaseTime + (HistoryCount + J + 0.5) * TradeStep;
      M.tmpList[Index].Price := TradePrice(Level);
      Q := (Integer((NextRandom shr 8) and 255) + 1) / 16;
      If (NextRandom shr 20) and 1 = 0 then
        M.tmpList[Index].Qty := Q
      else
        M.tmpList[Index].Qty := -Q;
    end;
    NowTime := BaseTime + (HistoryCount + RingCount - 0.5) * TradeStep;
    M.LastGotTradeTime := NowTime;
    { a day of candles up to now; the rebuild takes the candles of the history }
    SetLength(M.Deep5m, CandleCount);
    for J := 0 to CandleCount - 1 do
      with M.Deep5m[J] do begin
        Time := NowTime - ((CandleCount - 1 - J) * 5 + 2) / MinsInDay;
        OpenP := 64;
        CloseP := TradePrice(Level);
        MaxP := Level + 1 + (NextRandom and 63) / 64;
        MinP := Level - 1 - (NextRandom and 63) / 64;
        Vol := (NextRandom and 1023) / 16;
      end;
    M.FCandle.OpenP := 64;
    M.FCandle.MaxP := Level + 1;
    M.FCandle.MinP := Level - 1;
    M.LastTradePrice := Level;
    M.AvgPrice5m := Level;
    M.AvgPrice5mSet := Now;
    M.VisAvgPrice := Level;
    SetLength(M.tmpDeep, RebuildCandles);
    for J := 0 to RebuildCandles - 1 do
      M.tmpDeep[J].Time := BaseTime + (J + 1) * 5 / MinsInDay;
  end;
  cfg.IsFutures := True;
  cfg.DeltaPercent := 1.5;
  cfg.TimeOffset := 0.25;
  Feed := TFeed.Create;
  SetLength(Feed.Orders, BlockTrades);
  T := BaseTime + HistoryCount * TradeStep;
  for J := 0 to BlockTrades - 1 do begin
    Feed.Orders[J].Time := T + J * FeedStep;
    Feed.Orders[J].Price := TradePrice(80);
    Feed.Orders[J].Quantity := (Integer((NextRandom shr 8) and 255) + 1) / 16;
    If (NextRandom shr 20) and 1 = 0 then
      Feed.Orders[J].OrderType := O_BUY
    else
      Feed.Orders[J].OrderType := O_SELL;
    Feed.Orders[J].FillType := 1;
  end;
  SetLength(Feed.IntNames, ListedMarkets);
  SetLength(Feed.Names, ListedMarkets);
  for I := 0 to ListedMarkets - 1 do begin
    { the messages ask for the markets in an order of their own }
    Index := (I * 37 + 11) and (ListedMarkets - 1);
    Feed.IntNames[I] := IntName(Index);
    Feed.Names[I] := SymbolName(Index);
  end;
  for I := 0 to WindowCount - 1 do
    Feed.WindowSeconds[I] := 1 + Integer(NextRandom and 63);
end;

procedure FinalizeData;
begin
  FreeAndNil(Feed);
  FreeAndNil(Markets);
end;

var
  Profile: TPulseProfile;
  SelectedCase: string;
  Found: Boolean;
begin
  InitializeData;
  {$ifdef PULSE_PROGRAM_PREFIX}PulseProgramPrefix;{$endif}
  PulseInitialize('pulse_product_forms', Profile, SelectedCase);
  Found := False;
  PulseRunCase('pulse_product_forms', 'trade-recent-price', 'compiler+rtl', 'MarketsU', @CaseTradeRecentPrice,
    BlockTrades, Profile, SelectedCase, Found);
  PulseRunCase('pulse_product_forms', 'trade-max-window', 'compiler+rtl', 'MarketsU', @CaseTradeMaxWindow,
    MaxWindowTrades, Profile, SelectedCase, Found);
  PulseRunCase('pulse_product_forms', 'trade-buy-sell', 'compiler', 'MarketsU', @CaseTradeBuySell,
    BuySellWindowTrades, Profile, SelectedCase, Found);
  PulseRunCase('pulse_product_forms', 'trade-max-window-changing', 'compiler+rtl', 'MarketsU',
    @CaseTradeMaxWindowChanging, 1, Profile, SelectedCase, Found);
  PulseRunCase('pulse_product_forms', 'trade-buy-sell-changing', 'compiler', 'MarketsU',
    @CaseTradeBuySellChanging, 1, Profile, SelectedCase, Found);
  PulseRunCase('pulse_product_forms', 'trade-buy-sell-locked', 'compiler+rtl', 'MarketsU',
    @CaseTradeBuySellLocked, LockedWindowTrades, Profile, SelectedCase, Found);
  PulseRunCase('pulse_product_forms', 'candle-hour-deltas', 'compiler+rtl', 'MarketsU', @CaseCandleHourDeltas,
    HourCandles, Profile, SelectedCase, Found);
  PulseRunCase('pulse_product_forms', 'trade-value-locked', 'compiler+rtl', 'product-model',
    @CaseTradeValueLocked, HistoryCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_product_forms', 'market-by-name-getter', 'compiler+rtl', 'product-model',
    @CaseMarketByNameGetter, 1, Profile, SelectedCase, Found);
  PulseRunCase('pulse_product_forms', 'candle-rebuild', 'compiler', 'MarketsU', @CaseCandleRebuild,
    HistoryCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_product_forms', 'market-by-int-name', 'compiler+rtl', 'MarketsU', @CaseMarketByIntName,
    1, Profile, SelectedCase, Found);
  PulseRunCase('pulse_product_forms', 'market-by-name-dict', 'compiler+rtl', 'Generics.Collections',
    @CaseMarketByNameDict, 1, Profile, SelectedCase, Found);
  PulseRunCase('pulse_product_forms', 'markets-batch-for-in', 'compiler+rtl', 'Generics.Collections',
    @CaseMarketsBatch, ListedMarkets, Profile, SelectedCase, Found);
  PulseFinish('pulse_product_forms', SelectedCase, Found);
  FinalizeData;
end.
