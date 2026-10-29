unit MoonShotOrderPath;
{$ifdef FPC}{$mode delphiunicode}{$H+}{$endif}
{$Q-}{$R-}{$B-}

interface

uses {$ifdef MSWINDOWS}Windows,{$endif} SysUtils, Classes, Math, Generics.Collections, MoonShotFilters, MoonShotOrderState;

type
  TPriceKind = (PK_ASK, PK_BID, PK_Trade);
  TOrderMarket = class(MoonShotFilters.TMarket)
    PrevAsk, CurentAsk, CurentBid, LastTickerPrice: Double;
    Last1hDelta, Last3hDelta, Last15mDelta, Last24hDelta, LastMinuteDelta, Last5mDelta: Double;
    PriceBugM, MinLotSize: Double;
    ArbRange1m, Last5sDelta: Single;
    HistoryPriceCount, LastPartialValue, SellOrdersCount: Integer;
    function getActualASK(IsShort: Boolean = False): Double; inline;
    function getActualBID(IsShort: Boolean = False): Double; inline;
    function GetMaxPrice(Period: Double; PriceKind: TPriceKind; FastShotAlgo: Boolean): Double;
    function GetMinPrice(Period: Double; PriceKind: TPriceKind; FastShotAlgo: Boolean): Double;
  end;
  TOrderStrategy = class(MoonShotFilters.TStrategy)
    FStategyName: array[0..120] of Char;
    Short, Active, FastShotAlgo, CheckAfterBuy, ActiveTrigger, MShotMinusSatoshi: Boolean;
    IgnoreCancelBuy, OneOrderPerMarket, TlgUseBuyDipWords: Boolean;
    MShotPriceKind: TPriceKind;
    MShotPriceMin, MShotPrice, MShotAddDistance, MShotRaiseWait, MShotReplaceDelay: Double;
    MShotAddHourlyDelta, MShotAdd3hDelta, MShotAdd15minDelta, MShotAdd24hDelta: Double;
    MShotAdd1minDelta, MShotAdd5minDelta, MShotAddMarketDelta, MShotAddBTCDelta: Double;
    MShotAddBTC5mDelta, MShotAddMarkDelta, MShotAddPriceBug, MShotAddArbRange, MShotAdd5sDelta: Double;
    MaxModifier, AutoCancelBuy, CancelBuyStep, AutoCancelLowerBuy: Double;
    HFT: Integer;
    HookRaiseWait: Double;
    function GetMShotPriceDelta(m: TObject): Double;
    function GetMShotPriceMinPers(m: TObject): Double;
    function GetMShotPricePers(m: TObject): Double;
    function GetMShotDisnatce: Double;
    function GetLogName: string;
    function LikeMoonShot: Boolean;
    function UseFastAlgo: Boolean;
    function UseFastAlgo2: Boolean;
    function NeedCheckAfterBuy: Boolean;
  end;
  TParamValue = record
    name, value: string;
    NoQuotas: Boolean;
  end;
  TLocalEngine = class
    ParamsList: TList<TParamValue>;
    Market: TOrderMarket;
    HFT_Value, ParentWorkerNum, WSOrdersErrorsCount, LastKnownWebSocketDC: Integer;
    LastAPICheck: Int64;
    ApiReplays: UInt64;
    procedure CheckOrderRenew; virtual;
    procedure WSCheckWatchOrder(var AOrder: TOrder);
    constructor Create(AMarket: TOrderMarket; AWorker: Integer);
    destructor Destroy; override;
    function GetOrder(var AOrder: TOrder): Boolean; virtual;
  end;
  TBinanceLocalEngine = class(TLocalEngine)
    function GetOrder(var AOrder: TOrder): Boolean; override;
  end;
  TQuietOrder = class
  private
    sg: TOrderStrategy;
    Engine: TLocalEngine;
    FNowTime, WorkerStartTime, CreateTime, LastMoved, LastMShotReplaceTime: TDateTime;
    FLastCorridorDown, FLastCorridorUp, TestPriceDown, TestPriceUp: Double;
    LastMShotString: string;
    LastCheck, LastCorridor, LastBeforeGetOrderTime, LastAfterGetOrderTime, LastAfterGetOrderTime2, LastCheckBuyTime: Int64;
    CheckRenewCounter: Byte;
    GetOrderCounter, PrevPartial, PartialOrder: Integer;
    FPriority: TThreadPriority;
    BuyCancelTime: Double;
    IsMoonShot, PresaveIsMoonShot, cmdBuyReplace: Boolean;
    PresaveDown, PresaveUp: Double;
    OrderWasMoved, OrderWasMovedOnce, WasPending: Boolean;
    function CheckBuyAutoCancel: Boolean;
    function CheckCancelPartiallyFilled: Boolean;
    procedure CheckBuyMoonShot;
    procedure SendCorridorIfNeeded;
    procedure UpdatePartialStatus(APartial: Integer);
  public
    Publication: TOrderPublication;
    NoFormat, SkipFilters: Boolean;
    Checks, Formats, StringBytes, FilterChecks, LocalOrderChecks, Snapshots: UInt64;
    constructor Create(AStrategy: TOrderStrategy; AMarket: TOrderMarket; AWorker: Integer);
    destructor Destroy; override;
    procedure BeginPhase;
    procedure Poll;
    procedure Publish;
    function WaitMilliseconds: Integer;
    function ReplayCount: UInt64;
  end;

procedure InitOrderEnvironment;
function GetTimeMS: Int64;

var
  BookTickerActual, SiteWsTickerActual: Boolean;

implementation

type
  TPriceConfig = class
    BaseCurrency: TBaseCurrency;
    function IsUSD: Boolean;
    function IsSmallPriced: Boolean;
    function PriceToStr(p: Double; Pres: Integer = 8): string; inline;
  end;

var
  PriceConfig: TPriceConfig;
  intFormatSettings: TFormatSettings;
  BTC1hDelta, BTC5mDelta, Exchange1hDelta, Exchange24hDelta: Double;
  GlobalVDSMode: Boolean;
  GlobalTiming, LastWebSocketDC, GlobalOrdersCount, ApiLimitCare: Integer;

function GetTimeMS: Int64;
begin
  Result := GetTickCount64;
end;

function FloatAsStr2(V: Double): string;
begin
  Result := FloatToStrF(V, ffFixed, 7, 2, intFormatSettings);
end;

function FloatAsStr3(v: Double): string;
begin
  Result := FloatToStrF(v, ffFixed, 7, 3, intFormatSettings);
end;

function FloatAsStr5(v: Double): string;
begin
  Result := FloatToStrF(v, ffFixed, 7, 5, intFormatSettings);
end;

function FloatAsStr6(v: Double): string;
begin
  Result := FloatToStrF(v, ffFixed, 7, 6, intFormatSettings);
end;

function FloatAsStr7(v: Double): string;
begin
  Result := FloatToStrF(v, ffFixed, 7, 7, intFormatSettings);
end;

function FloatAsStr8(v: Double): string;
begin
  Result := FloatToStrF(v, ffFixed, 15, 8, intFormatSettings);
end;

function TPriceConfig.IsUSD: boolean;
begin
  Result := (BaseCurrency = BC_USDT) or ( BaseCurrency = BC_AUD) or
            (BaseCurrency = BC_TUSD) or ( BaseCurrency = BC_BRL) or
            (BaseCurrency = BC_USDH) or (BaseCurrency = BC_USD) or
            (BaseCurrency = BC_USDC) or (BaseCurrency = BC_USDE) or (BaseCurrency = BC_RUB) or
            (BaseCurrency = BC_EUR) or (BaseCurrency = BC_USDD) or
            (BaseCurrency = BC_FDUSD) or (BaseCurrency = BC_AEUR);


//  If cfg.ReverseBaseCurrency then Result := false;

end;

function TPriceConfig.IsSmallPriced: boolean;
begin
  Result := (BaseCurrency = BC_TRX) or (BaseCurrency = BC_IDR) or (BaseCurrency = BC_DOGE) or (BaseCurrency = BC_TRY);
end;

function TPriceConfig.PriceToStr(p: double; Pres: integer = 8): string;
begin
  If IsUSD or IsSmallPriced then begin
    If p>100
      then Result:=FloatAsStr2(p)
      else If p>10
        then Result:=FloatAsStr3(p)
        else If p>0.1
          then Result:=FloatAsStr5(p)
          else If p>0.01
            then Result:=FloatAsStr6(p)
            else If p > 0.001
              then Result:=FloatAsStr6(p)
              else If (p > 0.00001) and (Pres < 8)
                then Result := FloatAsStr7(p)
                else Result := FloatAsStr8(p); // Format('%s sat', [ FloatAsStrP(p * 1e8, Max(0, Pres - 8)) ]);
  end else Result:=FloatAsStr8(p);
end;


function BooleanAsYesNo(b: Boolean): string;
begin
  If b then Result := 'YES' else Result := 'NO';
end;

procedure InitOrderEnvironment;
begin
  PriceConfig := TPriceConfig.Create;
  PriceConfig.BaseCurrency := BC_USDT;
  intFormatSettings := TFormatSettings.Create('en-US');
  BTC1hDelta := 0.02;
  BTC5mDelta := 0.03;
  Exchange1hDelta := 0.04;
  Exchange24hDelta := 0.05;
  BookTickerActual := True;
  SiteWsTickerActual := False;
  GlobalVDSMode := True;
  GlobalOrdersCount := 92;
end;

constructor TLocalEngine.Create(AMarket: TOrderMarket; AWorker: Integer);
begin
  inherited Create;
  Market := AMarket;
  ParentWorkerNum := AWorker;
  ParamsList := TList<TParamValue>.Create;
end;

destructor TLocalEngine.Destroy;
begin
  ParamsList.Free;
  inherited;
end;

function TLocalEngine.GetOrder(var AOrder: TOrder): Boolean;
begin
  ParamsList.Clear;
  Result := not AOrder.IsOpened;
end;

procedure TLocalEngine.CheckOrderRenew;
begin
end;

procedure TLocalEngine.WSCheckWatchOrder(var AOrder: TOrder);
begin
  If AOrder.updCount > 4 then Exit;
  raise EUnsupportedMoonShotPath.Create('cold order watcher outside established quiet phase');
end;

function TBinanceLocalEngine.GetOrder(var AOrder: TOrder): Boolean;
var APIDelay: Integer;
begin
  Result := inherited;
  If Result then Exit;
  APIDelay := 5000;
  If WSOrdersErrorsCount >= 2 then APIDelay := 3000;
  If WSOrdersErrorsCount >= 3 then APIDelay := 2000;
  If GlobalVDSMode then APIDelay := Round(APIDelay + Max(1000, GlobalTiming / 2));
  APIDelay := Min(APIDelay + GlobalTiming, 7000);
  If (Market.SellOrdersCount > 5) and (WSOrdersErrorsCount < 3) then
    APIDelay := APIDelay + Min(5000, 200 * (Market.SellOrdersCount - 4));
  If LastKnownWebSocketDC = LastWebSocketDC then
    APIDelay := APIDelay + (10 + (ParentWorkerNum mod 100)) * (GlobalOrdersCount * 2 + 10)
  else APIDelay := APIDelay + (ParentWorkerNum mod 100) * 10;
  APIDelay := APIDelay + ApiLimitCare;
  { Transport boundary: a recorded unchanged status is supplied when the API
    interval expires. No request, JSON parsing or fake sleeping network worker.
    This is counted separately; it is not claimed to reproduce REST CPU. }
  If (AOrder.updCount < 4) or (Abs(GetTimeMS - LastAPICheck) < APIDelay) then begin
    WSCheckWatchOrder(AOrder);
    Exit(True);
  end;
  Inc(ApiReplays);
  LastAPICheck := GetTimeMS;
  Result := True;
end;

constructor TQuietOrder.Create(AStrategy: TOrderStrategy; AMarket: TOrderMarket; AWorker: Integer);
begin
  inherited Create;
  sg := AStrategy;
  Engine := TBinanceLocalEngine.Create(AMarket, AWorker);
  Publication := TOrderPublication.Create;
end;

destructor TQuietOrder.Destroy;
begin
  Publication.Free;
  Engine.Free;
  inherited;
end;

procedure TQuietOrder.BeginPhase;
begin
  WorkerStartTime := Now;
  CreateTime := WorkerStartTime;
  LastMoved := WorkerStartTime - 1;
  LastMShotReplaceTime := LastMoved;
  LastCheck := GetTimeMS;
  LastCorridor := LastCheck;
  Engine.LastAPICheck := LastCheck;
  FPriority := tpHigher;
  BuyCancelTime := sg.AutoCancelBuy + 5; { source adds random*10 once; freeze midpoint }
end;

function TQuietOrder.CheckBuyAutoCancel: Boolean;
var TimeToCancelBuy: Boolean; CancelTime, TimeSinceBuy: Double; s, s2: string; bOrderWasMoved: Boolean;
begin
  If HasStrategy(Publication.MContent) and sg.IgnoreCancelBuy and (Publication.MContent.RefNetNum > 0) then Exit(False);
  TimeSinceBuy := Max(Abs(FNowTime - CreateTime) * 86400, Abs(FNowTime - WorkerStartTime) * 86400);
  If OrderWasMoved and HasStrategy(Publication.MContent) then begin
    OrderWasMoved := False;
    LastMoved := FNowTime;
  end;
  If OrderWasMovedOnce then TimeSinceBuy := Abs(FNowTime - LastMoved) * 86400;
  bOrderWasMoved := OrderWasMoved;
  If not (HasStrategy(Publication.MContent)) then raise EUnsupportedMoonShotPath.Create('non-strategy order');
  CancelTime := sg.AutoCancelBuy;
  If Publication.MContent.IsNetOrder and (Publication.MContent.OrderNum > 1) and not sg.OneOrderPerMarket then
    CancelTime := CancelTime + sg.CancelBuyStep * (Publication.MContent.OrderNum - 1);
  If Publication.MContent.Filled and Publication.MContent.LowPriceWordsFound and sg.TlgUseBuyDipWords then
    TimeToCancelBuy := (TimeSinceBuy >= sg.AutoCancelLowerBuy) and (sg.AutoCancelLowerBuy > 0)
  else TimeToCancelBuy := (TimeSinceBuy >= CancelTime) and (sg.AutoCancelBuy > _eps);
  If sg.StrategyKind = sk_MoonShot then begin
    TimeToCancelBuy := (TimeSinceBuy > BuyCancelTime) and (BuyCancelTime > 0);
    bOrderWasMoved := False;
  end;
  If WasPending then TimeToCancelBuy := TimeSinceBuy >= 3;
  s2 := ' ' + sg.GetLogName;
  Inc(StringBytes, Length(s2));
  Result := TimeToCancelBuy and not bOrderWasMoved;
end;

function TQuietOrder.CheckCancelPartiallyFilled: Boolean;
var sName: string;
begin
  If HasStrategy(Publication.MContent) and (sg.StrategyKind = sk_MoonShot) then sName := 'MoonShot: ';
  If sg.StrategyKind = sk_MoonHook then sName := 'MoonHook: ';
  If sg.StrategyKind = sk_Spread then sName := 'Spread: ';
  With Publication.BuyOrder do
    Result := (ActualQ + Quantity - QuantityRemaining) * ActualPrice > Engine.Market.MinLotSize;
end;

procedure TQuietOrder.CheckBuyMoonShot;
var s, sRes, dStr, sMShot: string; HaveToReplace, HaveToReplaceUP, HaveToReplaceDown: Boolean;
  MinAsk, newAsk, TestPrice, xMShotPriceMin, xMShotPrice, dt, p, q, dPers: Double;
  k, dSat: Integer; NowTime: TDateTime;
begin
  If not (sg.Active) then raise EUnsupportedMoonShotPath.Create('inactive strategy');
  If (CheckCancelPartiallyFilled) then raise EUnsupportedMoonShotPath.Create('partial fill outside quiet fixture');
  With Engine.Market do begin
    xMShotPriceMin := sg.GetMShotPriceMinPers(Engine.Market);
    xMShotPrice := sg.GetMShotPricePers(Engine.Market);
    dPers := Min(xMShotPriceMin, xMShotPrice - xMShotPriceMin);
    If cfg.IsFutures then dPers := Max(dPers, 0.00001) else dPers := Max(dPers, 0.00001);
    dPers := Min(dPers, 0.99 - xMShotPrice);
    If not NoFormat then begin
      dStr := ' dBTC: ' + FloatAsStr2(BTC1hDelta) + ' dBTC5m: ' + FloatAsStr2(BTC5mDelta) +
        ' dMarket: ' + FloatAsStr2(Exchange1hDelta) + ' dMarket24: ' + FloatAsStr2(Exchange24hDelta);
      Inc(Formats, 4);
      Inc(StringBytes, Length(dStr));
    end;
    If sg.MShotPriceKind = PK_ASK then begin
      TestPrice := getActualASK(sg.Short);
      dSat := 2;
    end else If sg.MShotPriceKind = PK_BID then begin
      TestPrice := getActualBID(sg.Short);
      dSat := 1;
    end else raise EUnsupportedMoonShotPath.Create('trade-price strategy');
    If sg.Short then begin
      HaveToReplaceDown := TestPrice * (1 + xMShotPriceMin) > Publication.BuyOrder.ActualPrice;
      TestPriceDown := TestPrice * (1 + xMShotPriceMin);
    end else begin
      HaveToReplaceDown := TestPrice * (1 - xMShotPriceMin) < Publication.BuyOrder.ActualPrice;
      TestPriceDown := TestPrice * (1 - xMShotPriceMin);
    end;
    HaveToReplaceDown := HaveToReplaceDown or (sg.MShotMinusSatoshi and
      (Abs(TestPrice - Publication.BuyOrder.ActualPrice) < dSat * _eps + _epsM));
    If not NoFormat then begin
      sMShot := '  -- ' + LastMShotString + Format('  D: %d  ', [Abs(GetTimeMS - LastCheck)]);
      LastCheck := GetTimeMS;
      LastMShotString := Format('TP: %s  RD: %s  R: %s',
        [PriceConfig.PriceToStr(TestPrice), FloatAsStr2(sg.MShotReplaceDelay), BooleanAsYesNo(HaveToReplaceDown)]);
      Inc(Formats, 4);
      Inc(StringBytes, Length(sMShot) + Length(LastMShotString));
    end else begin
      dt := Abs(GetTimeMS - LastCheck);
      LastCheck := GetTimeMS;
    end;
    If HaveToReplaceDown then raise EUnsupportedMoonShotPath.Create('replacement DOWN outside quiet fixture');
    cmdBuyReplace := False;
    If sg.Short then begin
      MinAsk := GetMaxPrice(sg.MShotRaiseWait, sg.MShotPriceKind, sg.UseFastAlgo2);
      HaveToReplaceUP := MinAsk * (1 + xMShotPrice + dPers) < Publication.BuyOrder.ActualPrice;
      TestPriceUp := MinAsk * (1 + xMShotPrice + dPers);
    end else begin
      MinAsk := GetMinPrice(sg.MShotRaiseWait, sg.MShotPriceKind, sg.UseFastAlgo2);
      HaveToReplaceUP := MinAsk * (1 - xMShotPrice - dPers) > Publication.BuyOrder.ActualPrice;
      TestPriceUp := MinAsk * (1 - xMShotPrice - dPers);
    end;
    IsMoonShot := True;
    PresaveIsMoonShot := True;
    PresaveDown := TestPriceDown;
    PresaveUp := TestPriceUp;
    SendCorridorIfNeeded;
    HaveToReplaceUP := HaveToReplaceUP and (Abs(LastMShotReplaceTime - Now) > sg.MShotRaiseWait / 86400);
    If (HaveToReplaceUP) then raise EUnsupportedMoonShotPath.Create('replacement UP outside quiet fixture');
  end;
end;

procedure TQuietOrder.SendCorridorIfNeeded;
var changed: Boolean;
begin
  If (TestPriceDown < _epsM) and (TestPriceUp < _epsM) then Exit;
  If Abs(GetTimeMS - LastCorridor) < 1000 then Exit;
  changed := False;
  If FLastCorridorDown > _epsM then changed := Abs(TestPriceDown - FLastCorridorDown) / FLastCorridorDown > 0.0001
  else changed := TestPriceDown > _epsM;
  If not changed then begin
    If FLastCorridorUp > _epsM then changed := Abs(TestPriceUp - FLastCorridorUp) / FLastCorridorUp > 0.0001
    else changed := TestPriceUp > _epsM;
  end;
  If not changed then Exit;
  LastCorridor := GetTimeMS;
  FLastCorridorDown := TestPriceDown;
  FLastCorridorUp := TestPriceUp;
  Inc(Snapshots); { first corridor only; counted, no transport }
end;

procedure TQuietOrder.UpdatePartialStatus(APartial: Integer);
begin
  If (APartial > 0) and (APartial <> PrevPartial) and (APartial <> Engine.Market.LastPartialValue) then begin
    Engine.Market.LastPartialValue := APartial;
    PrevPartial := APartial;
  end;
end;

procedure TQuietOrder.Poll;
var sRes: string; OldUseFastAlgo: Boolean;
begin
  Inc(CheckRenewCounter);
  If CheckRenewCounter = 0 then Engine.CheckOrderRenew;
  If FPriority <> tpHigher then FPriority := tpHigher;
  If Publication.MContent.HasStrategy and (Publication.MContent.sg <> nil) then Engine.HFT_Value := sg.HFT;
  FNowTime := Now;
  OldUseFastAlgo := HasStrategy(Publication.MContent) and sg.LikeMoonShot and not sg.UseFastAlgo;
  If not (OldUseFastAlgo or (Publication.BuyOrder.QuantityRemaining * Publication.BuyOrder.ActualPrice >= _eps)) then raise EUnsupportedMoonShotPath.Create('filled order');
  If (CheckBuyAutoCancel) then raise EUnsupportedMoonShotPath.Create('automatic cancellation');
  If HasStrategy(Publication.MContent) and not SkipFilters then begin
    If sg.NeedCheckAfterBuy and not sg.CheckMarketCond(Engine.Market, sRes, True, True) then
      raise EUnsupportedMoonShotPath.Create('market filter: ' + sRes);
    If not (sg.CheckSpecialCond(Engine.Market, sRes, True, True, False, 0, False, FNowTime)) then raise EUnsupportedMoonShotPath.Create('special filter');
    If sg.NeedCheckAfterBuy then If not (sg.CheckFiltersAfterSignal(Engine.Market, sRes, sg.Short, True, True)) then raise EUnsupportedMoonShotPath.Create('signal filter');
    Inc(FilterChecks);
  end;
  If sg.StrategyKind = sk_MoonShot then CheckBuyMoonShot;
  LastBeforeGetOrderTime := GetTimeMS;
  GetOrderCounter := (GetOrderCounter + 1) mod 4;
  If GetOrderCounter = 1 then begin
    If not (Engine.GetOrder(Publication.BuyOrder)) then raise EUnsupportedMoonShotPath.Create('local order status');
    LastAfterGetOrderTime := GetTimeMS;
    Inc(LocalOrderChecks);
  end;
  With Publication.BuyOrder do begin
    PartialOrder := Round((Quantity - QuantityRemaining) / Quantity * 100);
    UpdatePartialStatus(PartialOrder);
    PartialDone := Min(100, Round((Quantity - QuantityRemaining) / Quantity * 100));
    If not (QuantityRemaining * ActualPrice >= _eps) then raise EUnsupportedMoonShotPath.Create('completed order');
  end;
  LastAfterGetOrderTime2 := GetTimeMS;
  LastCheckBuyTime := GetTimeMS;
  Inc(Checks);
end;

procedure TQuietOrder.Publish;
begin
  Publication.CheckQuietPublication;
end;

function TQuietOrder.WaitMilliseconds: Integer;
begin
  If HasStrategy(Publication.MContent) and sg.UseFastAlgo then Result := 16 else Result := 80;
end;

function TQuietOrder.ReplayCount: UInt64;
begin
  Result := Engine.ApiReplays;
end;

{ Source-derived arithmetic and quote helpers follow. Runtime zero coefficients
  stay in fields; the compiler sees the same expression, not a hand-folded one. }

function TOrderStrategy.GetMShotPriceDelta(m: TObject): double;
var
 mDelta:  double;
begin
  With m as TOrderMarket do begin
    mDelta := 0;
    If cfg.IsFutures then begin
      If Short
        then mDelta := - MarkPriceDelta
        else mDelta := MarkPriceDelta;

      If mDelta < 0 then mDelta := 0;
    end;

    Result := Last1hDelta*MShotAddHourlyDelta + Last3hDelta*MShotAdd3hDelta + Last15mDelta*MShotAdd15minDelta +
              Last24hDelta * MShotAdd24hDelta +
              LastMinuteDelta * MShotAdd1minDelta + Last5mDelta * MShotAdd5minDelta +
              abs(Exchange1hDelta) * MShotAddMarketDelta +
              abs(BTC1hDelta) * MShotAddBTCDelta + abs(BTC5mDelta) * MShotAddBTC5mDelta +
              MShotAddMarkDelta * mDelta + Min(30, MShotAddPriceBug * PriceBugM) +
              ArbRange1m * MShotAddArbRange + Last5sDelta * MShotAdd5sDelta;

    If MaxModifier > _eps
      then Result := Min(MaxModifier, Result);

  end;

end;

function TOrderStrategy.GetMShotPricePers(m: TObject): double;
begin
  Result := (MShotPrice + GetMShotPriceDelta(m) * GetMShotDisnatce) / 100;   // (1 + MShotAddDistance)
end;

function TOrderStrategy.GetMShotDisnatce: double;
begin
  Result := 1 + MShotAddDistance / 100;
end;

function TOrderStrategy.GetMShotPriceMinPers(m: TObject): double;
begin
  Result := (MShotPriceMin + GetMShotPriceDelta(m)) / 100;
end;



function TOrderStrategy.GetLogName: string;
begin
  try
    Result := '(strategy <' + string(FStategyName) + '>)';
  except
    Result:='(strategy <unknown>)';
  end;
end;

function TOrderStrategy.UseFastAlgo: boolean;
begin
  Result := LikeMoonShot and FastShotAlgo;
end;

function TOrderStrategy.LikeMoonShot: boolean;
begin
  Result := (StrategyKind = sk_MoonShot) or (StrategyKind = sk_MoonHook);
end;


function TOrderStrategy.NeedCheckAfterBuy: boolean;
begin
  Result := CheckAfterBuy or (StrategyKind = sk_MoonShot);
end;



function TOrderStrategy.UseFastAlgo2: boolean;
begin
  Result := FastShotAlgo and
    (
      ((StrategyKind = sk_MoonShot) and (MShotRaiseWait > _eps))
      or
      ((StrategyKind = sk_MoonHook) and (HookRaiseWait > _eps))
    );
end;

function TOrderMarket.getActualASK(IsShort: boolean = false): double;
begin
  Result := LastAsk;

  If BookTickerActual then begin
    If IsShort
      then Result := Max(Result, CurentAsk)
      else Result := Min(Result, CurentAsk);
  end;

  If SiteWsTickerActual and (LastTickerPrice > _epsM) then begin
    If IsShort
      then Result := Max(Result, LastTickerPrice)
      else Result := Min(Result, LastTickerPrice);
  end;

end;

function TOrderMarket.getActualBID(IsShort: boolean = false): double;
begin
  Result := LastBID;

  If BookTickerActual then begin
    If IsShort
      then Result := Max(Result, CurentBID)
      else Result := Min(Result, CurentBID);
  end;

  If SiteWsTickerActual and (LastTickerPrice > _epsM) then begin
    If IsShort
      then Result := Max(Result, LastTickerPrice)
      else Result := Min(Result, LastTickerPrice);
  end;

end;

function TOrderMarket.GetMaxPrice(Period: Double; PriceKind: TPriceKind; FastShotAlgo: Boolean): Double;
var k: Integer; dt: Double; NowTime, xTime: TDateTime;
begin
  case PriceKind of
    PK_ASK: Result := getActualASK(True);
    PK_BID: Result := getActualBID(True);
    else raise EUnsupportedMoonShotPath.Create('trade-history quote path');
  end;
  If PriceKind <> PK_Trade then begin
    If (HistoryPriceCount > 2) and (Period > 2.5) then
      raise EUnsupportedMoonShotPath.Create('base-currency history path')
    else If Period > 1.5 then begin
      If PriceKind = PK_ASK then Result := Max(LastAsk, PrevAsk) else Result := Max(LastBID, PrevAsk);
    end;
  end;
  If not (Period <= 3600) then raise EUnsupportedMoonShotPath.Create('deep-history path');
end;

function TOrderMarket.GetMinPrice(Period: Double; PriceKind: TPriceKind; FastShotAlgo: Boolean): Double;
var k: Integer; dt: Double; NowTime, xTime: TDateTime;
begin
  case PriceKind of
    PK_ASK: Result := getActualASK(False);
    PK_BID: Result := getActualBID(False);
    else raise EUnsupportedMoonShotPath.Create('trade-history quote path');
  end;
  If PriceKind <> PK_Trade then begin
    If (HistoryPriceCount > 2) and (Period > 2.5) then
      raise EUnsupportedMoonShotPath.Create('base-currency history path')
    else If Period > 1.5 then begin
      If PriceKind = PK_ASK then Result := Min(LastAsk, PrevAsk) else Result := Min(LastBID, PrevAsk);
    end;
  end;
  If not (Period <= 3600) then raise EUnsupportedMoonShotPath.Create('deep-history path');
end;

initialization
finalization
  PriceConfig.Free;
end.
