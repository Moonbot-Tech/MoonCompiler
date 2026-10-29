unit MoonShotFilters;
{$ifdef FPC}{$mode delphiunicode}{$H+}{$endif}
{$Q-}{$R-}{$B-}

interface

uses SysUtils, Math, DateUtils, Generics.Collections;

{ Frozen source extraction, not a complete MoonBot strategy/market ABI.
  The IntCheckMarketCond prefix and its original locals are copied verbatim.
  WhiteList/BlackList remain managed-array-returning methods, including the
  repeated calls and four-strategy sharing used by ordinary order workers.
  Field subsets keep source types but not full production offsets or sizes. }
const
  MaxTriggerKeys = 202;
  MinsInDay = 1440;
  SecondsInDay = 86400;

type
  EUnsupportedMoonShotPath = class(Exception);
  TStrategyKind = (sk_Unknown, sk_Telegram, sk_Drops, sk_Walls, sk_Volumes, sk_PumpDetection, sk_MoonShot,  // в конце файла BuildStrategyKindMaps
                   sk_VLite, sk_Delta, sk_Waves, sk_Combo, sk_UDP, sk_Manual, sk_MoonStrike, sk_NewListing,
                   sk_Liquidations, sk_TopMarket, sk_EMA, sk_Spread, sk_ChartWall, sk_MoonHook, sk_Activity, sk_Alerts, sk_Watcher);

  TBotPlatform = (Platform_none, Platform_WasBittrex, Platform_FBybit, Platform_Binance,
                  Platform_FBinance, Platform_Huobi, Platform_QBinance, Platform_ByBit,
                  Platform_Gate,  Platform_FGate, Platform_BitGet,  Platform_FBitGet,
                  Platform_Hyper,  Platform_FHyper,  Platform_OKX,  Platform_FOKX,
                  Platform_Next7,  Platform_Next8,  Platform_Next9,  Platform_Next10);


  TEMAFilterType = (EMA_None, EMA_MarketEMA, EMA_BTCEMA, EMA_Max, EMA_Min, EMA_MarketsAvg, EMA_Avg, EMA_Vol, EMA_Arb);
  TEMAKind = (EMA_seconds, EMA_minutes, EMA_hours);
  TEMACondition = (EMA_Higher, EMA_lower, EMA_Equal);

  TEMASource = (es_AvgSec, es_AvgMin, es_AvgHour, es_MaxMin, es_MaxHour, es_MinMin, es_MinHour,
                es_MktAvgSec, es_MktAvgMin, es_MktAvgHour, es_AvgLast, es_AvgClosest,
                es_VolConst, es_Vol5s, es_Vol15s, es_Vol30s,
                es_VolM1, es_VolM3, es_VolM5, es_VolM15, es_VolM30,
                es_VolH1, es_VolH3, es_VolH24, es_VolBad, es_ArbPrice, es_Unknown);

  TEMAFilter = record
    FType:         TEMAFilterType;
    M1Kind:        TEMAKind;
    M1:            integer; // index
    M2Kind:        TEMAKind;
    M2:            integer; // index
    Cond:          TEMACondition;
    Comp:          double; // compare with
    CompMul:       double; // pre-computed multiplier: v2 >< v1 * CompMul replaces division
    AlwaysTrue:    boolean; // |Comp| >= 887 → skip comparison, only check data exists
    Src1:          TEMASource; Idx1: integer;
    Src2:          TEMASource; Idx2: integer;
    UseBTCMarket:  boolean;
  end;

  TEMAFilterList = TList<TEMAFilter>;
  TEMAFilterSet  = TList<TEMAFilterList>;

  TEMAObject = record
    EMAFilters:            array[boolean] of TEMAFilterSet;
    CurrentEMAIndex:       boolean;
    UseCustomEMA:          boolean;
    CustomEMAWrongSet:     boolean;
    CustomEMAWrongRes:     string;
    AllAlwaysTrue:         boolean; // all filters have |Comp| >= 888 → skip CheckEMAFilter entirely
  end;

  TCheckDynListKind = (Dyn_CheckNothing, Dyn_CheckWL, Dyn_CheckBL, Dyn_CheckBoth);
  TListedOnExchange = (L_Unknown, L_Spot, L_Futures, L_Both);
  TTokenTag = (tag_none, tag_Monitoring, tag_Fan, tag_seed, tag_launch, tag_gaming, tag_New, tag_OLD, tag_BNB, tag_Alpha, tag_OICapped, tag_TradFi);
  TFlagList = array of boolean;
  TPriceBugRecord = record
    Time: TDateTime;
    val: double;
  end;

  TMarket = class
  public
    TimeAdded: TDateTime;
    Triggers: array [1 .. MaxTriggerKeys] of TDateTime;
    MarketBlackLIsted: boolean;
    MarketCurrency: string;
    pLast: double;
    LastAsk: double;
    LastBid: double;
    LastTradePrice: double;
    MarkPriceDelta: double;
    bnLeveraged: boolean;
    InternalErrorLightPenaltyTime: TDateTime;
    ListedType: TListedOnExchange;
    mIndex: integer;
    Orders_10m: integer;
    QuantitativeBL: TDateTime;
    LastMarketOfflineTime: TDateTime;
    TempBLTime: TDateTime;
    PriceZeroFlag: boolean;
    procedure InitQuietMarket(AIndex: Integer; const ACurrency: string; APrice: Double; ANow: TDateTime);
  end;

  { Only Current is read by extracted config methods; other header fields are
    not imported. This is explicitly not the serialized TBotPlatformHeader. }
  TFilterPlatformHeader = record
    Current: TBotPlatform;
  end;
  TConfig = class
  public
    Header: TFilterPlatformHeader;
    FuturesRules: boolean;
    UseAlgoMod: boolean;
    EmulatorMode: boolean;
    UseCoinsBlackList: boolean;
    function IsGateIO: boolean; inline;
    function IsByBit: boolean;
    function IsBinanceFutures: boolean;
    function IsBinanceMain: boolean;
    function SupportListedType: boolean;
    function IsFutures: boolean;
    function PriceToStr(p: double; Pres: integer = 8): string;
  end;

  TStrategy = class
  private
    FStrategyKind: TStrategyKind;
    FIntID: UInt64;
    IntListedType: TListedOnExchange;
    function IntCheckMarketCond(AMarket: TObject; var res: string; WideInt:boolean=false; DuringBuy: boolean=false; CheckForSell: boolean = false; TimeSinceStart: integer = 0; BeforeBuy: boolean = false; NowTimeSet: boolean = false; CheckKind: TCheckDynListKind = Dyn_CheckBoth; Verbose: boolean = true):boolean;
    function CheckSessionFilter(m: TObject; NowTime: TDateTime; var res: string; Verbose: boolean = true): boolean;
    function CheckEMAFilter(const AMarket: TObject; const e: TEMAObject; var res: string; GetResStr: boolean = false): boolean;
    function IsWhiteListedDyn(m: TObject): boolean;
    function IsNotBlackListedDyn(m: TObject): boolean;
  public
    IntWhiteLists: array[boolean] of TFlagList;
    IntBlackLists: array[boolean] of TFlagList;
    IntDynWhiteList: TFlagList;
    IntDynBlackList: TFlagList;
    IntWLIndex: boolean;
    IntBLIndex: boolean;
    FPreFlightTime: TDateTime;
    FPreFlightOK: boolean;
    TriggerWLIndex: array [1 .. MaxTriggerKeys] of word;
    TriggerWLIndexCount: word;
    TriggerTime: array [1 .. MaxTriggerKeys] of double;
    TriggerError: string;
    TriggerValid: boolean;
    TriggerSellError: string;
    TriggerSellValid: boolean;
    TriggerBLIndex: array [1 .. MaxTriggerKeys] of word;
    TriggerBLIndexCount: word;
    TriggerSell: array [1 .. MaxTriggerKeys] of boolean;
    TriggerBLTime: array [1 .. MaxTriggerKeys] of double;
    TriggerBLError: string;
    TriggerBLValid: boolean;
    TriggerExists: boolean;
    SellEMA: TEMAObject;
    FNowTime: TDateTime;
    FPreventWorkingUntil: TDateTime;
    FHasWhiteList: boolean;
    DynWL_Count: integer;
    DynBL_Count: integer;
    IgnoreFilters: boolean;
    IgnoreBase: boolean;
    MarkPriceMin: double;
    MarkPriceMax: double;
    DeltaSwitch: double;
    IgnoreGatePenalty: boolean;
    OnlyNewListing: integer;
    DontTradeListing: integer;
    LeveragedTokens: boolean;
    PreventWorkingUntil: int64;
    TriggerByAllKeys: boolean;
    CancelByTriggerBL: boolean;
    IgnoreSession: boolean;
    SessionPenaltyTime: integer;
    SellByFilters: integer;
    SellEMADelay: integer;
    SellEMACheckEnter: boolean;
    function WhiteList: TFlagList; inline;
    function BlackList: TFlagList; inline;
    function CheckMarketCond(AMarket: TObject; var res: string; WideInt:boolean=false; DuringBuy: boolean=false; CheckForSell: boolean = false; TimeSinceStart: integer = 0; BeforeBuy: boolean = false):boolean;
    function CheckSpecialCond(AMarket: TObject; var res: string; WideInt:boolean = false; DuringBuy: boolean = false; CheckForSell: boolean = false; TimeSinceStart: integer = 0; BeforeBuy: boolean = false; NowTime: TDateTime = 0; Verbose: boolean = true):boolean;
    function DeltaOutInterval(x, Left, Right: double; WideInt: boolean): boolean; inline;
    function CheckFiltersAfterSignal(AMarket: TObject; var res: string; FIsShort, DuringBuy, Verbose: boolean): boolean;
    function CheckMarkPriceFilter(AMarket: TObject; var res: string; IsLong: boolean; WideInt: boolean; Verbose: boolean = true): boolean;
    procedure InitQuietFilters(AMarketCount: Integer);
    property StrategyID: UInt64 read FIntID write FIntID;
    property StrategyKind: TStrategyKind read FStrategyKind write FStrategyKind;
    property FListedType: TListedOnExchange read IntListedType write IntListedType;
  end;

var
  cfg: TConfig;
  GlobalWakeUpDetectTime: TDateTime;
  GlobalGateOrdersPenaltyTime: TDateTime;
  GlobalGateOrdersPenaltyWait: double = 10 / MinsPerDay;
  MarketsPer10m: integer = 0;
  NThreshold: double = 0;
  _eps: double = 0.00000001;
  _epsM: double = 0.000000009;

procedure InitQuietFilterEnvironment(ANow: TDateTime);
procedure DoneQuietFilterEnvironment;

implementation

var
  intFormatSettings: TFormatSettings;

function TConfig.PriceToStr(p: double; Pres: integer = 8): string;
begin
  raise EUnsupportedMoonShotPath.Create('PriceZeroFlag diagnostic is outside quiet MoonShot fixture');
end;

function TStrategy.CheckSessionFilter(m: TObject; NowTime: TDateTime; var res: string; Verbose: boolean = true): boolean;
begin
  raise EUnsupportedMoonShotPath.Create('SessionPenaltyTime is outside quiet MoonShot fixture');
end;

function TStrategy.CheckEMAFilter(const AMarket: TObject; const e: TEMAObject; var res: string; GetResStr: boolean = false): boolean;
begin
  raise EUnsupportedMoonShotPath.Create('SellEMA is outside quiet MoonShot fixture');
end;

{ Keep the production exception scope, but fail the harness instead of turning
  an unsupported branch into a swallowed application-reporting exception. }
function TStrategy.CheckMarketCond(AMarket: TObject; var res: string; WideInt:boolean=false; DuringBuy: boolean=false; CheckForSell: boolean = false; TimeSinceStart: integer = 0; BeforeBuy: boolean = false):boolean;
begin
  try
    Result := IntCheckMarketCond(AMarket, res, WideInt, DuringBuy, CheckForSell, TimeSinceStart, BeforeBuy, false);
  except
    raise;
  end;
end;

function TConfig.IsGateIO: boolean;
begin
  Result := (Header.Current = Platform_Gate) or (Header.Current = Platform_FGate);
end;

function TConfig.IsByBit: boolean;
begin
  Result := (Header.Current = Platform_ByBit) or (Header.Current = Platform_FByBit);
end;

function TConfig.IsBinanceFutures: boolean;
begin
  Result := (Header.Current = Platform_FBinance) or (Header.Current = Platform_QBinance);
end;

function TConfig.IsBinanceMain: boolean;
begin
  Result := (Header.Current = Platform_FBinance) or (Header.Current = Platform_Binance);
end;

function TConfig.SupportListedType: boolean;
begin
  Result := IsBinanceMain or IsByBit;
end;

function TConfig.IsFutures: boolean;
begin
  Result := (Header.Current = Platform_FBinance) or (Header.Current = Platform_QBinance) or
            (Header.Current = Platform_FBybit) or (Header.Current = Platform_FGate) or
            (Header.Current = Platform_FBitGet) or (Header.Current = Platform_FHyper) or
            (Header.Current = Platform_FOKX);
end;

function FloatAsStr1(v: double): string;
begin
  Result:=FloatToStrF(v,Fffixed,7,1,intFormatSettings);
end;

function FloatAsStr2(v: double): string;
begin
  Result:=FloatToStrF(v,Fffixed,7,2,intFormatSettings);
end;

function TStrategy.DeltaOutInterval(x, Left, Right: double; WideInt: boolean): boolean;
//var
//  smallEps: double;
begin
//  Result:=false;
//  If WideInt
//    then smallEps:=Max(0.01, abs(DeltaSwitch))
//    else smallEps:=0;
//
//  If (x < Left - smallEps) or (x > Right + smallEps) then Result:=true;

  If WideInt
    then Result := (x < Left - DeltaSwitch) or (x > Right + DeltaSwitch)
    else Result := (x < Left) or (x > Right);

end;

function TStrategy.CheckFiltersAfterSignal(AMarket: TObject; var res: string; FIsShort, DuringBuy, Verbose: boolean): boolean;
begin
  Result := true;
  If cfg.IsFutures and not CheckMarkPriceFilter(AMarket, res, not FIsShort, false) then begin
    Result := false;
    exit;
  end;

end;

function TStrategy.CheckMarkPriceFilter(AMarket: TObject; var res: string; IsLong: boolean; WideInt: boolean; Verbose: boolean): boolean;
var
  TestDelta:  double;
  m:          TMarket;
  tmpRes, s1, s2:     string;
begin
  Result := true;      // tmpRes = ?

  If cfg.IsFutures and (StrategyKind <> sk_TopMarket) and (StrategyKind <> sk_NewListing) and not IgnoreFilters and not IgnoreBase then begin

    m := TMarket(AMarket);

    If ((abs(MarkPriceMax) > _eps) or (abs(MarkPriceMin) > _eps)) then begin
      If not IsLong
        then TestDelta := - m.MarkPriceDelta
        else TestDelta := m.MarkPriceDelta;
      If (abs(MarkPriceMax) > _eps) and DeltaOutInterval(TestDelta, -100, MarkPriceMax, WideInt) {(TestDelta > MarkPriceMax)}  then begin
        Result := false;
        If Verbose then s1 := FloatAsStr2(m.MarkPriceDelta);
        If Verbose then s2 := FloatAsStr2(MarkPriceMax);
        If Verbose then tmpRes := Format('MarkPrice delta %s%% > strategy MarkPriceMax %s%% ! ',[s1, s2 ]);
      end;

      If (abs(MarkPriceMin) > _eps) and DeltaOutInterval(TestDelta, MarkPriceMin, 100, WideInt) {(TestDelta < MarkPriceMin)} then begin
        Result := false;
        If Verbose then s1 := FloatAsStr2(m.MarkPriceDelta);
        If Verbose then s2 := FloatAsStr2(MarkPriceMin);
        If Verbose then tmpRes := Format('MarkPrice delta %s%% < strategy MarkPriceMin %s%% ! ',[s1, s2 ]);
      end;
    end;

    If not Result and Verbose then res := tmpRes;

  end;



end;

function TStrategy.WhiteList: TFlagList;
begin
  Result := IntWhiteLists[IntWLIndex];
end;

function TStrategy.BlackList: TFlagList;
begin
  Result := IntBlackLists[IntBLIndex];
end;

function TStrategy.IsWhiteListedDyn(m: TObject): boolean;
var
  k:              integer;
begin
  Result := DynWL_Count = 0;
  If Result then exit;
  k := TMarket(m).mIndex;
  If (k >= Low(IntDynWhiteList)) and (k <= High(IntDynWhiteList)) then Result := IntDynWhiteList[k];

end;

function TStrategy.IsNotBlackListedDyn(m: TObject): boolean;
var
  k:              integer;
begin
  Result := DynBL_Count = 0;
  If Result then exit;
  k := TMarket(m).mIndex;
  If (k >= Low(IntDynBlackList)) and (k <= High(IntDynBlackList)) then Result := not IntDynBlackList[k];

end;

function TStrategy.CheckSpecialCond(AMarket: TObject; var res: string; WideInt:boolean = false; DuringBuy: boolean = false; CheckForSell: boolean = false; TimeSinceStart: integer = 0; BeforeBuy: boolean = false; NowTime: TDateTime = 0; Verbose: boolean = true):boolean;

var
  m:            TMarket;
  k, j:         integer;
  s, s1:        string;

begin
  Result := true;
  m := TMarket(AMarket);
  If NowTime = 0 then NowTime := FNowTime;

  If CancelByTriggerBL and not CheckForSell and (cfg.UseAlgoMod or cfg.EmulatorMode) then for j := 1 to TriggerBLIndexCount do begin
    k := TriggerBLIndex[j];
    If (NowTime - TriggerBLTime[k] < m.Triggers[k]) then begin
      Result := false;
      If Verbose then s := FormatDateTime('hh:nn:ss', m.Triggers[k]);
      If Verbose then s1 := FloatAsStr1(secsPerDay * (m.Triggers[k] - NowTime + TriggerBLTime[k]));
      If Verbose then res := Format(' This market is BlackListed at %s by trigger %d. Wait %s seconds ', [s, k, s1 ]);
      exit;
    end;
  end;

  If (PreventWorkingUntil > 0) then begin
    If FPreventWorkingUntil > NowTIme then begin
      Result := false;
      If Verbose then s := FormatDateTime('hh:nn:ss', FPreventWorkingUntil);
      If Verbose then s1 :=  FloatAsStr1(secsPerDay * (FPreventWorkingUntil - NowTime));
      If Verbose then res := Format(' Strategy is turned off until %s. Wait %s seconds ', [s, s1]);
      exit;

    end;
  end;


end;

function TStrategy.IntCheckMarketCond(AMarket: TObject; var res: string; WideInt:boolean=false; DuringBuy: boolean=false; CheckForSell: boolean = false; TimeSinceStart: integer = 0; BeforeBuy: boolean = false; NowTimeSet: boolean = false; CheckKind: TCheckDynListKind = Dyn_CheckBoth; Verbose: boolean = true): boolean;
var
  m:            TMarket;
  s, s1, s2:    string;
  mDelta:       double;
  NowTIme:      TDateTime;
  k, j:         integer;
  TriggerRes:   boolean;
  TriggerAllRes:   boolean;
  CheckedKey:   integer;
  br:           TPriceBugRecord;
  IntPenaltyWait: integer;
  smallEps:       double;
  PingAddK:       double;
  tt:             TTokenTag;
  TmpRes:         string;
  UsePreFlight:   boolean;


  label FinishCheck;

//  tm1:            int64;    // убрать после оптимизации скорости
//const
//  NXTime = 20;


begin
//  tm1 := GetTimeAsm;  // убрать после оптимизации скорости

  Result := true;
  m := TMarket(AMarket);

  If not NowTimeSet
    then begin NowTIme := Now; FNowTime := NowTIme; end   // 240 ns
    else NowTime := FNowTime;

  UsePreFlight := NowTimeSet and not WideInt and not DuringBuy and not CheckForSell and not BeforeBuy;
  If UsePreFlight and (NowTime = FPreFlightTime) and not FPreFlightOK and not Verbose then begin
    Result := false;
    goto FinishCheck;
  end;

  If not CheckForSell then begin

    If not IgnoreSession and (SessionPenaltyTime <> 0) and not CheckSessionFilter(m, NowTIme, TmpRes, Verbose) and (cfg.UseAlgoMod or cfg.EmulatorMode) then begin
      Result := false;
      goto FinishCheck;
    end;

   If m.PriceZeroFlag and (StrategyKind <> sk_NewListing) and (StrategyKind <> sk_Manual) and
      ((m.pLast < _epsM) or (m.LastBid < _epsM) or (m.LastAsk < _epsM) or (m.LastTradePrice < _epsM))
    then begin

      Result := false;
      If Verbose then begin
        If m.LastTradePrice < _epsM then begin
          s := cfg.PriceToStr(m.LastTradePrice);
          TmpRes := Format('Zero prices (LastTrade: %s)', [s]);
        end else begin
          s := cfg.PriceToStr(Min(m.pLast, m.LastAsk));
          TmpRes := Format('Zero prices (PLast: %s)', [s]);
        end;
      end;
      goto FinishCheck;
    end;

    If (StrategyKind <> sk_NewListing) and (StrategyKind <> sk_Manual) and (m.LastMarketOfflineTime > NowTime - 30 / SecondsInDay) then begin
      If Verbose then TmpRes := Format('Market offline penalty (%d secs passed; wait %d secs) ',[round(abs(NowTIme - m.LastMarketOfflineTime) * SecondsInDay), 30 ]);
      Result := false;
      goto FinishCheck;
    end;

    If (StrategyKind <> sk_Manual) and (abs(GlobalWakeUpDetectTime - NowTime) * SecondsInDay < 10) then begin
      If UsePreFlight then begin FPreFlightOK := false; FPreFlightTime := NowTime; end;
      If Verbose then TmpRes := Format('WakeUp penalty (%d secs passed; wait %d secs) ',[round(abs(NowTIme - GlobalWakeUpDetectTime) * SecondsInDay), 10 ]);
      Result := false;
      goto FinishCheck;
    end;

    If cfg.FuturesRules and cfg.IsBinanceFutures then begin
      If DuringBuy then k := m.Orders_10m + 1 else k := m.Orders_10m + 2;

      If (NowTime - 11 / MinsInDay < m.QuantitativeBL) then begin
        Result:=false;
        If Verbose then s := FormatDateTime('hh:nn:ss', m.QuantitativeBL);
        If Verbose then s1 := FloatAsStr1(secsPerDay * (m.QuantitativeBL - NowTime) + 660);
        If Verbose then TmpRes := Format(' This market is BlackListed at %s by new Futures Trading Quantitative Rules. Wait %s seconds ', [s, s1 ]);
        goto FinishCheck;
      end;

      If k > NThreshold then begin
        Result := false;
        If Verbose then TmpRes := Format('According to new Futures Trading Quantitative Rules you can place only %d orders per %d markets. You placed %d orders. Market %s will be blackListed for 10 minutes. ',
                      [trunc(NThreshold), MarketsPer10m, k, m.MarketCurrency ]);
        m.QuantitativeBL := NowTime;
        goto FinishCheck;

      end;
    end;

    If (PreventWorkingUntil > 0) then begin                      // Дублирует CheckSpecialCond для оптимизации!
      If FPreventWorkingUntil > NowTIme then begin
        Result := false;
        If UsePreFlight then begin FPreFlightOK := false; FPreFlightTime := NowTime; end;
        If Verbose then s := FormatDateTime('hh:nn:ss', FPreventWorkingUntil);
        If Verbose then s1 :=  FloatAsStr1(secsPerDay * (FPreventWorkingUntil - NowTime));
        If Verbose then TmpRes := Format(' Strategy is turned off until %s. Wait %s seconds ', [s, s1]);
        exit;
      end;
    end;

    If (OnlyNewListing > 0) and (NowTime > m.TimeAdded + OnlyNewListing / SecsPerDay) then begin
      Result:=false;
      If Verbose then TmpRes := Format(' This market was added more then %d seconds ago.  ', [ Min(3600, round((NowTime - m.TimeAdded) * SecsPerDay)) ]);
      goto FinishCheck;
    end;

    If (DontTradeListing > 0) and (NowTime < m.TimeAdded + DontTradeListing / SecsPerDay) then begin
      Result:=false;
      If Verbose then TmpRes := Format(' This market was added less then %d seconds ago.  ', [ Min(3600, round((NowTime - m.TimeAdded) * SecsPerDay)) ]);
      goto FinishCheck;
    end;

    If not DuringBuy and (abs(NowTime - m.InternalErrorLightPenaltyTime) * SecondsInDay < 5) then begin
      If Verbose then TmpRes:=Format('InternalError penalty on this market (%d secs passed; wait %d secs) ',[round(abs(NowTime - m.InternalErrorLightPenaltyTime) * SecondsInDay), 5 ]);
      Result := false;
      goto FinishCheck;
    end;

  end;

//  If IntTime1 = 0
//    then IntTime1 := GetTimeAsm - tm1
//    else IntTime1 := round((IntTime1 * NXTime + (GetTimeAsm - tm1)) / (NXTime + 1));


  // =====================>>> Триггеры   TriggerExists

  If not TriggerValid and not CheckForSell  then begin
    Result := false;
    If UsePreFlight then begin FPreFlightOK := false; FPreFlightTime := NowTime; end;
    If Verbose then TmpRes := TriggerError;
    goto FinishCheck;
  end;

  If TriggerExists and not CheckForSell and (cfg.UseAlgoMod or cfg.EmulatorMode) then begin
    TriggerRes := false;
    TriggerAllRes := true;
    CheckedKey := 0;

    for j := 1 to TriggerWLIndexCount do begin
      k := TriggerWLIndex[j];
      If (NowTime - TriggerTime[k] < m.Triggers[k]) then begin      // TriggerByAllKeys
        TriggerRes := true;
      end else begin
        CheckedKey := k;
        TriggerAllRes := false;
      end;
    end;

    If TriggerByAllKeys then TriggerRes := TriggerRes and TriggerAllRes;

    If not TriggerRes and Verbose then begin
      If (CheckedKey = 0) or (m.Triggers[CheckedKey] < _eps)
        then s := 'none'
        else s := FormatDateTime('yyyy-mm-dd hh:nn:ss', m.Triggers[CheckedKey]);
      TmpRes := Format(' This market is not triggered (By key %d. Last valid time: %s) ', [ CheckedKey, s]);

    end;

    Result := TriggerRes;
    If not Result then goto FinishCheck;
  end;

  If not (TriggerBLValid and TriggerSellValid) and not CheckForSell then begin
    Result:=false;
    If UsePreFlight then begin FPreFlightOK := false; FPreFlightTime := NowTime; end;
    If Verbose then TmpRes := TriggerBLError + ' ' + TriggerSellError;
    goto FinishCheck;
  end;

  If not CheckForSell then begin

    If (cfg.UseAlgoMod or cfg.EmulatorMode) then for j := 1 to TriggerBLIndexCount do begin
      k := TriggerBLIndex[j];
      If (NowTime - TriggerBLTime[k] < m.Triggers[k]) then begin
        Result := false;
        If Verbose then s := FormatDateTime('hh:nn:ss', m.Triggers[k]);
        If Verbose then s1 := FloatAsStr1(secsPerDay * (m.Triggers[k] - NowTime + TriggerBLTime[k]));
        If Verbose then TmpRes := Format(' This market is BlackListed at %s by trigger %d. Wait %s seconds ', [s, k, s1 ]);
        goto FinishCheck;
      end;
    end;

  end;

  If CheckForSell and TriggerSellValid and (cfg.UseAlgoMod or cfg.EmulatorMode) then for j := 1 to TriggerBLIndexCount do begin
    k := TriggerBLIndex[j];
    If TriggerSell[k] and (NowTime - TriggerBLTime[k] < m.Triggers[k]) then begin
      Result:=false;
      If Verbose then s := FormatDateTime('hh:nn:ss', m.Triggers[k]);
      If Verbose then TmpRes := Format(' This market is BlackListed at %s by trigger %d. Sell by key %d. ', [s, k, k ]);
      goto FinishCheck;
    end;
  end;

  // <<<===================== Триггеры

  If not SellEMA.CustomEMAWrongSet and SellEMA.UseCustomEMA and (cfg.UseAlgoMod or cfg.EmulatorMode) then begin

    If CheckForSell then begin

      If ((SellEMADelay = 0) or (TimeSinceStart > SellEMADelay))  then begin
        Result := not CheckEMAFilter(m, SellEMA, TmpRes, Verbose);
        If not Result then goto FinishCheck;
      end;

    end else If SellEMACheckEnter and (DuringBuy or BeforeBuy) then begin

      Result := not CheckEMAFilter(m, SellEMA, TmpRes, Verbose);
      If not Result then goto FinishCheck;

    end;

  end;

  If CheckForSell and ((SellByFilters = 0) or (TimeSinceStart < SellByFilters)) then goto FinishCheck;

  If not CheckForSell then begin

    If FHasWhiteList then begin
      k := m.mIndex;
      If (k >= Low(WhiteList)) and (k <= High(WhiteList)) then Result := WhiteList[k];
      If not Result then begin
        If Verbose then TmpRes := Format('Market %s doesnt match strategy white list' , [ m.MarketCurrency ] );
        goto FinishCheck;
      end;
    end;

    k := m.mIndex;
    If (k >= Low(BlackList)) and (k <= High(BlackList)) then Result := not BlackList[k];

    If not Result then begin
      If Verbose then TmpRes := Format('Market %s match strategy black list' , [ m.MarketCurrency ] );
      goto FinishCheck;
    end;

    If cfg.UseCoinsBlackList then begin
      Result := not m.MarketBlackLIsted;
      If not Result then begin
        If Verbose then TmpRes := Format('Market %s match global black list' , [ m.MarketCurrency ] );
        goto FinishCheck;
      end;
    end;

    If NowTIme < m.TempBLTime then begin
      Result := false;
      If Verbose then TmpRes := Format('Market %s BlackListed until %s' , [ m.MarketCurrency, FormatDateTime('dd.mm hh:nn:ss', m.TempBLTime) ] );
      goto FinishCheck;
    end;

    If (DynWL_Count > 0) and ((CheckKind = Dyn_CheckBoth) or (CheckKind = Dyn_CheckWL)) then Result := IsWhiteListedDyn(m);
    If not Result then begin
      If Verbose then TmpRes := Format('Market %s doesnt match strategy Dynamic white list' , [ m.MarketCurrency ] );
      goto FinishCheck;
    end;

    If (DynBL_Count > 0) and ((CheckKind = Dyn_CheckBoth) or (CheckKind = Dyn_CheckBL)) then Result := IsNotBlackListedDyn(m);

    If not Result then begin
      If Verbose then TmpRes := Format('Market %s match strategy Dynamic black list' , [ m.MarketCurrency ] );
      goto FinishCheck;
    end;

  end;

  If not LeveragedTokens and (cfg.Header.Current = Platform_Binance) and m.bnLeveraged then begin
    Result := false;
    If Verbose then TmpRes := 'Leveraged token trading is disabled by strategy filters';
  end;
  If not Result then goto FinishCheck;

  If (FListedType <> L_Unknown) and cfg.SupportListedType and (m.ListedType <> FListedType) then begin
    If Verbose then begin
      If m.ListedType = L_Spot then TmpRes := 'This market is listed on Spot only, check the ListedType filter';
      If m.ListedType = L_Futures then TmpRes := 'This market is listed on Futures only, check the ListedType filter';
      If m.ListedType = L_Both then TmpRes := 'This market is listed on both Spot and Futures, check the ListedType filter';
      If m.ListedType = L_Unknown then TmpRes := 'This market has unknown listing type, check the ListedType filter';
    end;
    Result := false;
  end;
  If not Result then goto FinishCheck;


  If cfg.IsGateIO and not IgnoreGatePenalty and not CheckForSell and not DuringBuy then begin

    If abs(NowTime - GlobalGateOrdersPenaltyTime) < GlobalGateOrdersPenaltyWait then begin
      Result := false;
      If UsePreFlight then begin FPreFlightOK := false; FPreFlightTime := NowTime; end;
      If Verbose then TmpRes := Format('Gate OrdersLimit Penalty (%d \ %d seconds wait) ',
          [ round(abs(NowTime - GlobalGateOrdersPenaltyTime) * SecsPerDay), round(GlobalGateOrdersPenaltyWait * SecsPerDay) ]);

      goto FinishCheck;
    end;

  end;



  // IgnoreFilters ================>>>>>>>>>>>>>>>

  If (StrategyKind = sk_NewListing) or IgnoreFilters
    then goto FinishCheck;

  raise EUnsupportedMoonShotPath.Create('Filter body after IgnoreFilters is outside quiet MoonShot fixture');

  FinishCheck: If not Result and Verbose then res := TmpRes;
end;

procedure TMarket.InitQuietMarket(AIndex: Integer; const ACurrency: string; APrice: Double; ANow: TDateTime);
begin
  mIndex := AIndex;
  MarketCurrency := ACurrency;
  pLast := APrice;
  LastAsk := APrice;
  LastBid := APrice;
  LastTradePrice := APrice;
  TimeAdded := ANow - 10;
  QuantitativeBL := ANow - 10;
  ListedType := L_Both;
  PriceZeroFlag := false;
end;

procedure TStrategy.InitQuietFilters(AMarketCount: Integer);
begin
  { Called on a newly allocated object, once before worker startup. Market
    indexes are 1..AMarketCount, as in TMarkets.Add/Session.TryGetValue. The
    selected markets all matched the captured list, so fixture preparation
    supplies its prebuilt flags instead of rerunning UI/config rebuilds. }
  StrategyKind := sk_MoonShot;
  IgnoreFilters := true;
  IgnoreSession := true;
  MarkPriceMax := 1;
  DeltaSwitch := 0.1;
  TriggerValid := true;
  TriggerBLValid := true;
  TriggerSellValid := true;
  SellEMACheckEnter := true;
  FHasWhiteList := true;
  IntWLIndex := true;
  IntBLIndex := true;
  SetLength(IntWhiteLists[IntWLIndex], AMarketCount + 1);
  SetLength(IntBlackLists[IntBLIndex], AMarketCount + 1);
  for var I := 1 to AMarketCount do IntWhiteLists[IntWLIndex][I] := true;
end;

procedure InitQuietFilterEnvironment(ANow: TDateTime);
begin
  If cfg <> nil then raise EUnsupportedMoonShotPath.Create('filter environment initialized twice');
  cfg := TConfig.Create;
  cfg.Header.Current := Platform_FBinance;
  cfg.UseAlgoMod := true;
  cfg.FuturesRules := true;
  GlobalWakeUpDetectTime := ANow - 1;
  { Default threshold before the live aggregation producer runs. Both live
    operands are frozen fixture inputs, not claimed captured snapshot values. }
  NThreshold := 10000;
  intFormatSettings := TFormatSettings.Create('en-US');
  intFormatSettings.DecimalSeparator := '.';
end;

procedure DoneQuietFilterEnvironment;
begin
  FreeAndNil(cfg);
end;

end.
