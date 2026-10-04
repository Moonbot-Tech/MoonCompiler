unit pulse_product_model;

{ The data and hot methods of a trading server as MoonBot writes them
  (MarketsU.pas, TradeTypes.pas, HelpClasses.pas, Vars.pas), in a unit of
  their own as TMarket lives in MarketsU:
  - a trade of 16 bytes with inline methods (the side is the sign of Qty),
    a packed candle of 28 bytes whose TDateTime sits at offset 20;
  - a market object whose trade history, trade ring, candles and recent
    trades are fields: UpdateRecentPrice runs for every trade, GetMaxPrice
    and CalcBv_SV read the last seconds of the history, the hour deltas read
    the last hour of candles, the candles are rebuilt from the trades;
  - the market list, an enumerable over a TList whose enumerator is the base
    TEnumerator (MoveNext and Current are virtual), with the name dictionary
    in a field; markets are looked up by name through the list with SameText
    and through the dictionary;
  - the unit globals the hot loops read (_eps, _epsM, the size of the ring,
    the configuration record).
  The product routines retain their forms. Small additional methods exercise
  managed getters and finally-protected loops over the same fields. }

{$ifdef FPC}
  {$mode delphi}{$H+}{$modeswitch inlinevars}
{$endif}

{$Q-}{$R-}

interface

uses
  SysUtils,
  Math,
  SyncObjs,
  Generics.Collections;

const
  SecondsInDay = 86400;
  msSecondsInDay = 86400000;
  MinsInDay = 1440;

type
  TOrderType = (O_BUY, O_SELL);

  { TradeTypes.THOrder: a trade as the parser hands it over }
  THOrder = record
    Time: TDateTime;
    Price: Double;
    Quantity: Double;
    OrderType: TOrderType;
    FillType: Byte;
  end;

  { TradeTypes.TTrade: a trade of the history }
  TTrade = record
    Time: TDateTime;
    Price: Single;
    Qty: Single;   { signed: > 0 a buy, < 0 a sell }
    function Quantity: Single; inline;
    function OrderType: TOrderType; inline;
  end;

  { MarketsU.TDeepPrice: a 5-minute candle }
  TDeepPrice = packed record
    OpenP, CloseP, MaxP, MinP: Single;
    Vol: Single;
    Time: TDateTime;
  end;

  TTradeForAvg = record
    P, Q: Double;
    Time: TDateTime;
  end;

  TRecentTradePrice = record
    MinP, MaxP: Double;
    MinP2, MaxP2: Double;
    T1: TDateTime;
  end;

  TConfig = record
    IsFutures: Boolean;
    DeltaPercent: Double;
    TimeOffset: Double;
  end;

  TMarket = class
  private
    RecentPrice: TRecentTradePrice;
    RecentTradesAvg: array[0..24] of TTradeForAvg;
    RecentTradesAvgK: Integer;
    RecentTradesAvgCalc: Int64;
    function GetMarketName: string; inline;
  public
    bnMarketName: string;
    OrdersH: array of TTrade;
    OrdersHCount: Integer;
    OrdersHLock: TCriticalSection;
    { the ring the exchange thread fills and JoinHOrders drains }
    tmpList: array of TTrade;
    tmpTradesWrite: Integer;
    tmpTradesRead: Integer;
    LastGotTradeTime: TDateTime;
    Deep5m: array of TDeepPrice;
    tmpDeep: array of TDeepPrice;
    WeightTradePrice: Double;
    WeightTradePricePrev: Double;
    LastTradeMaxPrice: Double;
    LastTradeMinPrice: Double;
    LastBid: Double;
    LastAsk: Double;
    PrevPrice: Double;
    MaxPrice15: Double;
    MinPrice15: Double;
    Last15mDelta: Double;
    Last1hDelta: Double;
    Last30mDelta: Double;
    Last1hDeltaCandles: Double;
    Last2hDelta: Double;
    Last3hDelta: Double;
    Last24hDelta: Double;
    HourlyMaxPrice: Double;
    HourlyMinPrice: Double;
    Max1hPrice: Double;
    Min1hPrice: Double;
    Open1HPrice: Double;
    PumpHDelta: Double;
    DumpHDelta: Double;
    PumpDelta: Double;
    LastTradePrice: Double;
    AvgPrice5m: Double;
    AvgPrice5mSet: TDateTime;
    VisAvgPrice: Double;
    FCandle: TDeepPrice;
    Moved: Boolean;
    constructor Create(const AName: string);
    destructor Destroy; override;
    procedure UpdateRecentPrice(const Order: THOrder; NTime: TDateTime; XTime: Int64);
    function GetMaxTradePrice(Period: Double; NowTime: TDateTime): Double;
    function CalcBv_SV(N: Integer; IsShort: Boolean): Double;
    function CalcBv_SV_Precise(N: Integer; IsShort: Boolean): Double;
    function TradeValueLocked: Double;
    procedure RecalcDeltasByCandles(NowTime: TDateTime);
    function RebuildDeep: Double;
    procedure CheckMove;
    procedure ResetRecentPrice;
    function RecentDigest: Double;
    property MarketName: string read GetMarketName;
  end;

  { HelpClasses.TSlowSafeList<T> }
  TSlowSafeList<T> = class(TEnumerable<T>)
  protected
    function DoGetEnumerator: TEnumerator<T>; override;
  public
    FList: TList<T>;
    constructor Create; virtual;
    destructor Destroy; override;
    function GetEnumerator: TEnumerator<T>; inline;
    function Count: NativeInt; inline;
    function GetItem(Index: NativeInt): T; inline;
    property Items[Index: NativeInt]: T read GetItem;
  end;

  { MarketsU.TMarkets }
  TMarkets = class(TSlowSafeList<TMarket>)
  public
    mDict: TDictionary<string, TMarket>;
    constructor Create; override;
    destructor Destroy; override;
    procedure Add(M: TMarket);
    function MarketByIntName(MarketName: string): TMarket;
    function MarketByNameFast(const MarketName: string): TMarket;
    function MarketByNameGetter(const MarketName: string): TMarket;
  end;

var
  { Vars.pas: variables the hot loops read }
  _eps: Double = 0.00000001;
  _epsM: Double = 0.0000000000001;
  IntTradesBufSize: Integer = 1200;
  cfg: TConfig;

implementation

function TTrade.Quantity: Single;
begin
  Result := Abs(Qty);
end;

function TTrade.OrderType: TOrderType;
begin
  If (PCardinal(@Qty)^ and $80000000) = 0 then
    Result := O_BUY
  else
    Result := O_SELL;
end;

constructor TMarket.Create(const AName: string);
begin
  inherited Create;
  bnMarketName := AName;
  OrdersHLock := TCriticalSection.Create;
end;

destructor TMarket.Destroy;
begin
  FreeAndNil(OrdersHLock);
  inherited Destroy;
end;

function TMarket.GetMarketName: string;
begin
  Result := bnMarketName;
end;

{ TMarket.UpdateRecentPrice: every trade of the market }
procedure TMarket.UpdateRecentPrice(const Order: THOrder; NTime: TDateTime; XTime: Int64);
const
  TimeToRecalc = 75;
  TimeWnd = (TimeToRecalc - 1) / MSecsPerDay;
var
  dt: Double;
  k: Integer;
  TotalVol: Double;
  TotalQ: Double;
  AvgP: Double;
  AvgPrev: Double;
  FLastTradeMaxPrice: Double;
  FLastTradeMinPrice: Double;
begin
  If WeightTradePrice < _epsM then begin
    WeightTradePrice := Order.Price;
    WeightTradePricePrev := Order.Price;
    LastTradeMaxPrice := Order.Price;
    LastTradeMinPrice := Order.Price;
  end;
  RecentTradesAvg[RecentTradesAvgK].Time := Order.Time;
  RecentTradesAvg[RecentTradesAvgK].P := Order.Price;
  RecentTradesAvg[RecentTradesAvgK].Q := Order.Quantity;
  RecentTradesAvgK := (RecentTradesAvgK + 1) mod (High(RecentTradesAvg) + 1);
  If abs(RecentTradesAvgCalc - XTime) > TimeToRecalc then begin
    RecentTradesAvgCalc := XTime;
    TotalVol := 0;
    TotalQ := 0;
    FLastTradeMaxPrice := Order.Price;
    FLastTradeMinPrice := Order.Price;
    for k := 0 to High(RecentTradesAvg) do
      If abs(Order.Time - RecentTradesAvg[k].Time) < TimeWnd then begin
        TotalVol := TotalVol + RecentTradesAvg[k].P * RecentTradesAvg[k].Q;
        TotalQ := TotalQ + RecentTradesAvg[k].Q;
        FLastTradeMaxPrice := Max(FLastTradeMaxPrice, RecentTradesAvg[k].P);
        FLastTradeMinPrice := Min(FLastTradeMinPrice, RecentTradesAvg[k].P);
      end;
    If TotalQ > _eps then
      AvgP := TotalVol / TotalQ
    else
      AvgP := Order.Price;
    AvgPrev := WeightTradePrice;
    WeightTradePrice := AvgP;
    WeightTradePricePrev := AvgPrev;
    LastTradeMaxPrice := FLastTradeMaxPrice;
    LastTradeMinPrice := FLastTradeMinPrice;
  end;
  LastTradeMaxPrice := Max(LastTradeMaxPrice, Order.Price);
  LastTradeMinPrice := Min(LastTradeMinPrice, Order.Price);
  with RecentPrice do begin
    dt := abs(Order.Time - T1);
    If MinP < _eps then begin
      MinP := Order.Price;
      MaxP := Order.Price;
      MinP2 := Order.Price;
      MaxP2 := Order.Price;
    end;
    If dt < 7 / SecondsInDay then begin
      MinP := Min(MinP, Order.Price);
      MaxP := Max(MaxP, Order.Price);
      MinP2 := Order.Price;
      MaxP2 := Order.Price;
    end else If dt < 14 / SecondsInDay then begin
      MinP := Min(MinP, Order.Price);
      MaxP := Max(MaxP, Order.Price);
      MinP2 := Min(MinP2, Order.Price);
      MaxP2 := Max(MaxP2, Order.Price);
    end else begin
      MinP := MinP2;
      MaxP := MaxP2;
      MinP2 := Order.Price;
      MaxP2 := Order.Price;
      T1 := Order.Time;
    end;
  end;
end;

{ TMarket.GetMaxPrice, PK_Trade: the highest trade of the last Period seconds }
function TMarket.GetMaxTradePrice(Period: Double; NowTime: TDateTime): Double;
var
  k: Integer;
begin
  Result := LastBid;
  If OrdersHCount <= 2 then
    Exit;
  Period := Period + 0.1;
  NowTime := Min(NowTime - Period / SecondsInDay, OrdersH[OrdersHCount - 1].Time - Period / SecondsInDay);
  for k := OrdersHCount - 1 downto 0 do begin
    If OrdersH[k].Time < NowTime then
      Break;
    Result := Max(Result, OrdersH[k].Price);
  end;
end;

{ TMarket.CalcBv_SV: buy against sell volume of the last N seconds }
function TMarket.CalcBv_SV(N: Integer; IsShort: Boolean): Double;
var
  m: Integer;
  BQuantity: Double;
  bv, sv: Double;
  MCount: Integer;
  tm0: Double;
begin
  Result := 1;
  If OrdersHCount < 2 then
    Exit;
  bv := 0;
  sv := 0;
  MCount := OrdersHCount - 1;
  tm0 := OrdersH[MCount].Time;
  for m := MCount downto 0 do
    with OrdersH[m] do begin
      If abs(Time - tm0) * SecondsInDay > N then
        Break;
      BQuantity := Price * Quantity;
      If OrderType = O_SELL then
        sv := sv + BQuantity
      else
        bv := bv + BQuantity;
    end;
  If not IsShort then begin
    If sv > _eps then
      Result := bv / sv
    else
      Result := 100;
  end else begin
    If bv > _eps then
      Result := sv / bv
    else
      Result := 100;
  end;
end;

{ TMarket.CalcBv_SV_Precise: the same in milliseconds under the history lock,
  with the trades of the ring JoinHOrders has not taken yet }
function TMarket.CalcBv_SV_Precise(N: Integer; IsShort: Boolean): Double;
var
  m: Integer;
  BQuantity: Double;
  bv, sv: Double;
  MCount: Integer;
  tm0: Double;
begin
  Result := 0;
  If OrdersHCount < 2 then
    Exit;
  OrdersHLock.Acquire;
  try
    bv := 0;
    sv := 0;
    tm0 := LastGotTradeTime;
    MCount := OrdersHCount - 1;
    for m := MCount downto 0 do
      with OrdersH[m] do begin
        If abs(Time - tm0) * msSecondsInDay > N then
          Break;
        BQuantity := Price * Quantity;
        If OrderType = O_SELL then
          sv := sv + BQuantity
        else
          bv := bv + BQuantity;
      end;
    var localWrite := tmpTradesWrite;
    var localRead := tmpTradesRead;
    var cnt := (localWrite - localRead + IntTradesBufSize) mod IntTradesBufSize;
    If cnt > 0 then
      for var j := cnt - 1 downto 0 do begin
        var idx := (localRead + j) mod IntTradesBufSize;
        with tmpList[idx] do begin
          If abs(Time - tm0) * msSecondsInDay > N then
            Break;
          BQuantity := Price * Quantity;
          If OrderType = O_SELL then
            sv := sv + BQuantity
          else
            bv := bv + BQuantity;
        end;
      end;
    If not IsShort then begin
      If sv > _eps then
        Result := bv / sv
      else
        Result := 100;
    end else begin
      If bv > _eps then
        Result := sv / bv
      else
        Result := 100;
    end;
  except
    Result := 0;
  end;
  OrdersHLock.Release;
end;

{ Accumulate into Result under a finally-protected lock, with the history in
  the object's field. This is distinct from the precise window's except form. }
function TMarket.TradeValueLocked: Double;
begin
  Result := 0;
  OrdersHLock.Acquire;
  try
    for var I := 0 to OrdersHCount - 1 do
      Result := Result + OrdersH[I].Price * OrdersH[I].Qty;
  finally
    OrdersHLock.Release;
  end;
end;

{ MarketsU.RecalcDeltasByCandles: include the post-loop work and its Now call;
  they determine the register pressure of the candle loop. }
procedure TMarket.RecalcDeltasByCandles(NowTime: TDateTime);
var
  j: Integer;
  Max15, Min15, Max30, Min30: Double;
  Max1h, Min1h: Double;
  Open1h, Open5, Max5: Double;
  tm5m, tm15m, tm30m, tm1h: TDateTime;
  MoreThen5m: Boolean;
  tmpAvg: Double;
begin
  If (FCandle.MaxP < _epsM) or (FCandle.MinP < _epsM) then
    Exit;
  Max1h := FCandle.MaxP;
  Min1h := FCandle.MinP;
  If LastAsk > _epsM then Max1h := Max(Max1h, LastAsk);
  If LastBid > _epsM then Min1h := Min(Min1h, LastBid);
  Open1h := FCandle.OpenP;
  Max15 := Max1h;
  Min15 := Min1h;
  Max30 := Max1h;
  Min30 := Min1h;
  Max5 := Max1h;
  Open5 := FCandle.OpenP;
  MoreThen5m := False;
  tm5m := NowTime - 5 / MinsInDay;
  tm15m := NowTime - 15 / MinsInDay;
  tm30m := NowTime - 30 / MinsInDay;
  tm1h := NowTime - 1 / 24;
  for j := High(Deep5m) downto 0 do
    with Deep5m[j] do begin
      If Time <= tm1h then
        Break;
      Max1h := Max(Max1h, MaxP);
      Min1h := Min(Min1h, MinP);
      Open1h := OpenP;
      If Time > tm15m then begin
        Max15 := Max(Max15, MaxP);
        Min15 := Min(Min15, MinP);
      end;
      If Time > tm30m then begin
        Max30 := Max(Max30, MaxP);
        Min30 := Min(Min30, MinP);
      end;
      If Time > tm5m then begin
        Max5 := Max(Max5, MaxP);
        Open5 := OpenP;
      end else
        MoreThen5m := True;
    end;
  MaxPrice15 := Max15;
  MinPrice15 := Min15;
  If Min15 > _eps then
    Last15mDelta := (Max15 / Min15 - 1) * 100;
  If Min30 > _eps then
    Last30mDelta := (Max30 / Min30 - 1) * 100;
  If Min1h > _eps then begin
    Last1hDelta := Max(Last1hDeltaCandles, (Max1h / Min1h - 1) * 100);
    Last2hDelta := Max(Last2hDelta, Last1hDelta);
    Last3hDelta := Max(Last3hDelta, Last1hDelta);
    Last24hDelta := Max(Last24hDelta, Last1hDelta);
    HourlyMaxPrice := Max1h;
    HourlyMinPrice := Min1h;
  end;
  Max1hPrice := Max1h;
  Min1hPrice := Min1h;
  If LastTradePrice > _epsM then begin
    Max1hPrice := Max(Max1hPrice, LastTradePrice);
    Min1hPrice := Min(Min1hPrice, LastTradePrice);
  end;
  Open1HPrice := Open1h;
  If Open1HPrice > _eps then begin
    PumpHDelta := Max(0, (Max1hPrice / Open1HPrice - 1) * 100);
    DumpHDelta := Max(0, (1 - Min1hPrice / Open1HPrice) * 100);
  end;
  If (Open5 > _eps) and (Max5 > _eps) then
    If MoreThen5m then
      PumpDelta := Max(0, (Max5 / Open5 - 1) * 100)
    else
      PumpDelta := Max(PumpDelta, (Max5 / Open5 - 1) * 100);
  tmpAvg := (FCandle.MaxP + FCandle.MinP) * 0.5;
  If AvgPrice5m < _epsM then AvgPrice5m := tmpAvg;
  If abs(Now - AvgPrice5mSet) > 5 / MinsInDay then begin
    AvgPrice5mSet := Now;
    AvgPrice5m := tmpAvg;
  end;
  If abs(tmpAvg - VisAvgPrice) > VisAvgPrice * Last15mDelta * 0.005 then
    VisAvgPrice := tmpAvg;
end;

{ The candles rebuilt from the trade history (MarketsU, the prints'
  contribution): every trade widens the candle it falls into }
function TMarket.RebuildDeep: Double;
var
  j, ci, N: Integer;
begin
  N := Length(tmpDeep);
  for j := 0 to N - 1 do
    with tmpDeep[j] do begin
      OpenP := 0;
      CloseP := 0;
      MaxP := 0;
      MinP := 0;
      Vol := 0;
    end;
  ci := 0;
  for j := 0 to OrdersHCount - 1 do begin
    while (ci < N) and (OrdersH[j].Time > tmpDeep[ci].Time) do
      Inc(ci);
    If ci >= N then
      Break;
    If OrdersH[j].Time <= tmpDeep[ci].Time - 5 / MinsInDay then
      Continue;
    If OrdersH[j].Price < _epsM then
      Continue;
    with tmpDeep[ci] do begin
      If OpenP < _epsM then
        OpenP := OrdersH[j].Price;
      CloseP := OrdersH[j].Price;
      If MaxP < OrdersH[j].Price then
        MaxP := OrdersH[j].Price;
      If (MinP < _epsM) or (OrdersH[j].Price < MinP) then
        MinP := OrdersH[j].Price;
      Vol := Vol + OrdersH[j].Price * OrdersH[j].Quantity;
    end;
  end;
  Result := 0;
  for j := 0 to N - 1 do
    Result := Result + tmpDeep[j].MaxP - tmpDeep[j].MinP + tmpDeep[j].Vol;
end;

{ One market of the batch that walks all markets: the move since the
  previous price against the configured percent }
procedure TMarket.CheckMove;
var
  Delta: Double;
begin
  Moved := False;
  If PrevPrice < _epsM then
    Exit;
  Delta := (LastBid / PrevPrice - 1) * 100;
  If cfg.IsFutures then
    Delta := Delta - cfg.TimeOffset;
  Moved := abs(Delta) > cfg.DeltaPercent;
end;

procedure TMarket.ResetRecentPrice;
begin
  FillChar(RecentPrice, SizeOf(RecentPrice), 0);
  FillChar(RecentTradesAvg, SizeOf(RecentTradesAvg), 0);
  RecentTradesAvgK := 0;
  RecentTradesAvgCalc := 0;
  WeightTradePrice := 0;
  WeightTradePricePrev := 0;
  LastTradeMaxPrice := 0;
  LastTradeMinPrice := 0;
end;

function TMarket.RecentDigest: Double;
begin
  Result := WeightTradePrice + LastTradeMaxPrice - LastTradeMinPrice + RecentPrice.MaxP - RecentPrice.MinP2;
end;

constructor TSlowSafeList<T>.Create;
begin
  inherited Create;
  FList := TList<T>.Create;
end;

destructor TSlowSafeList<T>.Destroy;
begin
  FreeAndNil(FList);
  inherited Destroy;
end;

function TSlowSafeList<T>.DoGetEnumerator: TEnumerator<T>;
begin
  Result := FList.GetEnumerator;
end;

function TSlowSafeList<T>.GetEnumerator: TEnumerator<T>;
begin
  Result := FList.GetEnumerator;
end;

function TSlowSafeList<T>.Count: NativeInt;
begin
  Result := FList.Count;
end;

function TSlowSafeList<T>.GetItem(Index: NativeInt): T;
begin
  Result := FList[Index];
end;

constructor TMarkets.Create;
begin
  inherited Create;
  mDict := TDictionary<string, TMarket>.Create;
end;

destructor TMarkets.Destroy;
var
  i: Integer;
begin
  for i := 0 to Count - 1 do
    Items[i].Free;
  FreeAndNil(mDict);
  inherited Destroy;
end;

procedure TMarkets.Add(M: TMarket);
begin
  FList.Add(M);
  mDict.Add(M.bnMarketName, M);
end;

{ TMarkets.MarketByIntName: the exchange's name of a market in a message }
function TMarkets.MarketByIntName(MarketName: string): TMarket;
var
  i: Integer;
begin
  Result := nil;
  MarketName := StringReplace(MarketName, '_', '', []);
  for i := 0 to Count - 1 do begin
    If SameText(MarketName, TMarket(Items[i]).bnMarketName) then begin
      Result := TMarket(Items[i]);
      Break;
    end;
  end;
end;

{ A string getter consumed by comparison while traversing a list field. }
function TMarkets.MarketByNameGetter(const MarketName: string): TMarket;
begin
  Result := nil;
  for var I := 0 to FList.Count - 1 do
    If FList[I].MarketName = MarketName then begin
      Result := FList[I];
      Break;
    end;
end;

function TMarkets.MarketByNameFast(const MarketName: string): TMarket;
begin
  If (MarketName = '') or not mDict.TryGetValue(MarketName, Result) then
    Result := nil;
end;

end.
