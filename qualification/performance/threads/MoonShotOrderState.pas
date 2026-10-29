unit MoonShotOrderState;
{$ifdef FPC}{$mode delphiunicode}{$H+}{$endif}
{$Q-}{$R-}{$B-}{$POINTERMATH ON}

interface

uses
  {$ifdef MSWINDOWS}Windows,{$endif}
  SysUtils, DateUtils, Generics.Collections, MoonShotFilters;

{ Data records and computation copied from MoonBot sources. This is a local
  quiet publication harness: a real changed state fails instead of sending a
  protocol message. No hash/broadcast is fabricated. UI/worker object offsets
  are not reproduced; complete TOrder/TOrderState/TMessageContent fields are. }
type
  EUnexpectedOrderPublication = class(Exception);
  TOrderUID = string[40];
  TOrderType = (O_SELL, O_BUY, O_BuyStop, O_BuyLimit);
  TOrderSubType = (OT_Limit, OT_Trailing, OT_Stop, OT_StopMarket, OT_ReduceOnly, OT_Market);
  TOrderWorkerStatus = (OS_None,OS_BuyFail,OS_BuySet,OS_BuyCancel,OS_BuyDone,OS_SellFail,OS_SellSet,OS_SellCancel,OS_SelLDone,OS_SelLAlmostDone);
  TBaseCurrency = (BC_BTC, BC_USDT, BC_ETH, BC_BNB, BC_AUD, BC_TUSD, BC_BRL, BC_USDH, BC_USDC, BC_FDUSD, BC_AEUR, BC_USD, BC_TRX, BC_RUB, BC_EUR, BC_HTX, BC_USDD, BC_IDR, BC_DOGE, BC_TRY, BC_USDE, BC_Next2, BC_Next3, BC_Next4, BC_Next5, BC_EMPTY, BC_Unknown);
  TOrder = record                                 // SizeOf = 224
    OrderID:                  TOrderUID;
    LastUpdTime:              int64;
    intID:                    int64;
    wsBTC:                    double;
    Quantity:                 double;
    QuantityRemaining:        double;
    TotalBTC:                 double;
    Price:                    double;
    SpentBTC:                 double;
    OpenTime:                 TDateTime;
    CloseTime:                TDateTime;
    IsOpened:                 boolean;
    IsClosed:                 boolean;
    OrderType:                TOrderType;
    IsIceberg:                boolean;
    dbID:                     integer;
    ActualPrice:              double;
    Canceled:                 boolean;
    BaseCurrency:             TBaseCurrency;
    updCount:                 byte;
    WSQ_OK:                   boolean;
    RefWorkerNum:             word;
    StopFlag:                 byte;
    TryCounter:               byte;  // Наверное не нужно
    CreateTime:               TDateTime;
    LastAPICheck:             int64;
//    IsPartial:                boolean;
    wsQ:                      double;
    PanicSellDown:            single;
    IsOCO:                    boolean;
    IsMultiOrder:             boolean;
    ExtraFlags:               byte;       // bitmask, см. константы HL_*
    CancelRequest:            boolean;
    MeanPrice:                double;
    QuantityBase:             double;
    ActualQ:                  double;
    tmpBTC:                   double;
    PartialDone:              byte;
    SubType:                  TOrderSubType;
    LotSize:                  byte;
    Source:                   byte;
    OrderReplace:             Boolean;
    ver:                      byte;
    IsShort:                  boolean;
    Leverage:                 byte;

  end;
  POrder = ^TOrder;

  TStopSettings = packed record
    StopLossOn:        boolean;
    SLFixed:           boolean;
    SLLevel:           double;
    SLspread:          double;
    TrailingOn:        boolean;
    TrailingFixed:     boolean;
    TrailingLevel:     double;
    TSSpread:          double;
    UseTakeProfit:     boolean;
    TakeProfit:        double;
    TakeProfitChanged: boolean;
  end;

  TSellReasonCode = (
    srcUnknown = 0,
    srcSellPrice,         // дефолт - продажа по установленной цене
    srcAutoPriceDown,     // Auto Price Down
    srcSellLevel,         // Sell Level
    srcSellSpread,        // SellSpread
    srcSellShot,          // SellShot
    srcPanicSell,         // Global/Manual PanicSell
    srcStopLoss,          // StopLoss activated
    srcTrailing,          // TrailingStop
    srcMarketStop,        // Market Stop
    srcManualSell,        // Manual Sell (price < 95%)
    srcJoinedSell,        // JoinedSell
    srcSellFromAssets,    // SellFromAssets
    srcBV_SV_Stop,        // BV/SV Stop
    srcTakeProfit         // TakeProfit
  );
  TSignalContent = record
    Filled:          boolean;
    MinP, MaxP:      double;
    Vol:             double;
    RepeatedOrder:   integer;
    IsNetOrder:      boolean;
    OrderNum:        integer;
    IsShort:         boolean;
    IsManaged:       boolean;
    ShotHigh:        double;
    ShotLo:          double;
    ShotHighN:       double;
    ShotLoN:         double;
    SellPers:        double;
    InitialModK:     double;
    BuyPers:         double;
    WasChanged:      boolean;
    WasManualStrat:  boolean;
    OrderSize:       double;
  end;

  TMessageContent = record
    Filled:          boolean;
    KeyFound:        boolean;
    BlackFound:      boolean;
    KeyDist:         integer;
    Price:           double;
    PriceFound:      boolean;
    Market:          TMarket;
    TokenCount:      integer;
    WordsCount:       integer;
    delta:           integer;
    res:             string;
    rwords:          string;
    ChanName:        string;
    SignalType:      string;
    TokensString:    string;
    ChanID:          int64;
    PredefinedBuyPrice:   double;
    StrikeVol:            double;
    PredefinedSellPrice:  double;
    tmpBidMax:            double;
    StopLoss:             double;
    TakeProfit:           array [1..4] of double;
    TakeProfitCnt:        integer;
    StopFound,TPFound:    boolean;
    reason:               integer;    // 1- manual 2- autodetect
    SignalSource:         string;
    HasStrategy:          boolean;
    LowPriceWordsFound:   boolean;
    sg:                   TStrategy;
    comment:              string;
    InitialSleep:         integer;
    IsCommand:            boolean;
    IsUDPCommand:         boolean;
    OrderK:               double;
    ManagerUID:           integer;
    wTag:                 UInt64;
    DontCheckBalance:     boolean;
    IsPremium:            boolean;
    ChannelID:            int64;
    BVSVRatio:            double;
    CanSendTrades:        boolean;
    OrderNum:             integer;
    FixedQ:               double;
    IsNetOrder:           boolean;
    IsAutoSplit:          boolean;

    OrderSize:            double;
    RemoteOrder:          boolean;

    IsShort:              boolean;
    CanShareCmd:          boolean;
    RefNetNum:            UInt64;
    sVol:                 double;
    sc:                   TSignalContent;
    UseMarketStop:        boolean;
    mList:                TList<TMarket>;
    sgJoined:             TList<TStrategy>;
    IsLiquidation:        boolean;
    IsFunding:            boolean;
  end;

const
  OSEC_PHASE          = 0;    // только-IMAGE: Status + EffectiveStratID
  OSEC_FLAGS          = 1;
  OSEC_BUY_TARGET     = 2;    // цель: живые прод-поля (пендинг — BuyCondPrice/OrderSize, нога — Price/OrderReplace)
  OSEC_SELL_TARGET    = 3;
  OSEC_BUY_EXEC       = 4;
  OSEC_BUY_PLACEMENT  = 5;
  OSEC_BUY_SLOW       = 6;    // slow: разморозка не чаще OrdersSyncPeriodMS либо на IMAGE-точке
  OSEC_SELL_EXEC      = 7;
  OSEC_SELL_PLACEMENT = 8;
  OSEC_SELL_SLOW      = 9;    // slow
  OSEC_STOPS          = 10;
  OSEC_VSTOP          = 11;
  OSEC_PLANNED        = 12;

  OrderSectionCount   = 13;
  OrderSectionAllMask = word($1FFF);           // биты 0..12; биты 13..15 обязаны быть 0

  OrderStateSize      = 342;
  OrderMarketNameMax  = 64;
  OrderDescMaxSize    = 66;                    // NameLen:1 + имя<=64 + Flags:1

  OrderStateHashSeed  = Cardinal($4F726432);          // «Ord2»

  // Одна нормативная временная константа v2: период фонового каталога и срок разморозки
  // SLOW-секций на ближайшей обычной точке минта (отдельного таймера нет — §6.3 спеки)
  OrdersSyncPeriodMS  = 9000;

  // Битфлаги FLAGS.Flags
  OFL_Immune    = 1;
  OFL_PanicOn   = 2;
  OFL_PanicAuto = 4;

  // Битфлаги TOrderDesc.Flags
  ODF_Emulator  = 1;
  ODF_IsShort   = 2;
type
  TOrderExecSection = packed record
    QuantityRemaining: double;
    ActualQ:           double;
    TotalBTC:          double;
    MeanPrice:         double;
    PartialDone:       byte;
  end;

  // Физическая инкарнация биржевого ордера одной ноги — 63 Б. Меняется PATCH'ем внутри
  // фазы (cancel+set/amend: IsOpened переключает busy-подпись Cancelling…/Setting new…)
  TOrderPlacementSection = packed record
    intID:        Int64;
    ActualPrice:  double;
    OpenTime:     Int64;    // Unix UTC ms; 0 = не установлено
    Quantity:     double;
    QuantityBase: double;
    CloseTime:    Int64;    // Unix UTC ms
    CreateTime:   Int64;    // Unix UTC ms
    StopFlag:     byte;     // v1-битовая маска как есть
    OrderType:    byte;     // TOrderType 0..3
    SubType:      byte;     // TOrderSubType 0..5
    Leverage:     byte;
    IsOpened:     byte;     // 0/1
    IsClosed:     byte;     // 0/1
    Canceled:     byte;     // 0/1
  end;

  // Фоновые дребезжащие поля одной ноги — 20 Б
  TOrderSlowSection = packed record
    SpentBTC:      double;
    tmpBTC:        double;
    PanicSellDown: single;
  end;

  // Канон: 342 Б, 13 секций подряд (границы — OrderSectionOffset/Size).
  // Детерминизм каждого байта обязателен для CompareMem/пруфа/публикации (§3 спеки):
  // полная сборка обнуляет кандидата целиком (InitOrderState), частичная стартует
  // с копии уже детерминированного committed-канона
  TOrderState = packed record
    // PHASE (9) — пара режимных фактов, минтится только в IMAGE
    Status:            byte;     // TOrderWorkerStatus 0..9
    EffectiveStratID:  UInt64;   // 0 = нет стратегии; текущий MContent.sg.StrategyID
    // FLAGS (2)
    SellReason:        byte;     // TSellReasonCode 0..14
    Flags:             byte;     // OFL_*
    // BUY_TARGET (17) — абсолютная пара принятой цели buy/pending
    TargetBuyPrice:    double;
    TargetBuySize:     double;   // ровно project vOrder.OrderSize, без смены единиц
    BuyReplacing:      byte;     // 0/1
    // SELL_TARGET (9)
    TargetSell:        double;
    SellReplacing:     byte;     // 0/1
    // BUY (33+63+20)
    BuyExec:           TOrderExecSection;
    BuyPlacement:      TOrderPlacementSection;
    BuySlow:           TOrderSlowSection;
    // SELL (33+63+20)
    SellExec:          TOrderExecSection;
    SellPlacement:     TOrderPlacementSection;
    SellSlow:          TOrderSlowSection;
    // STOPS (46) — TStopSettings как есть (CompareMem-детектор)
    Stops:             TStopSettings;
    // VSTOP (18)
    VStopOn:           byte;     // 0/1
    VStopFixed:        byte;     // 0/1
    VStopLevel:        double;
    VStopVol:          double;
    // PLANNED (9)
    PredefinedSellPrice: double; // 0 = не задана (production-сентинел)
    UseMarketStop:     byte;     // 0/1
  end;
  POrderState = ^TOrderState;

const
  OrderSectionOffset: array[0..OrderSectionCount-1] of word =
    (0, 9, 11, 28, 37, 70, 133, 153, 186, 249, 269, 315, 333);
  OrderSectionSize: array[0..OrderSectionCount-1] of byte =
    (9, 2, 17, 9, 33, 63, 20, 33, 63, 20, 46, 18, 9);

type
  TVisualOrderItem = class
  public
    OrderSize: double;
    BuyCondPrice: double;
    StopLossOn: boolean;
    VStopON: boolean;
    VStopFixed: boolean;
    VStopLevel: double;
    VStopVol: double;
    TrailingOn: boolean;
    SLFixed: boolean;
    TrailingFixed, UseTakeProfit: boolean;
    SLLevel: double;
    TrailingLevel: double;
    TakeProfit: double;
    TakeProfitChanged: boolean;
    SLspread: double;
    TSSpread: double;
  end;

  TOrderPublication = class
  public
    BuyOrder, SellOrder: TOrder;
    pBuyOrder, pSellOrder: POrder;
    vOrder: TVisualOrderItem;
    MContent: TMessageContent;
    Status: TOrderWorkerStatus;
    BTCBalance: double;
    SellReason: string[180];
    IsPending: boolean;
    ImmuneForClicks: boolean;
    FPanicSell: boolean;
    PanicSellAutoActivated: boolean;
    FLastSlowSampleMS: int64;
    FPrevSellReason: string[180];
    FPrevBuyOpenTime: TDateTime;
    FPrevSellOpenTime: TDateTime;
    Canon: TOrderState;
    HotChecks, FullChecks, ChangedChecks: UInt64;
    constructor Create;
    destructor Destroy; override;
    function HotCanonDiff(const P: TOrderState): word;
    procedure BuildOrderStateCandidate(APrev: POrderState; out S: TOrderState);
    function GetCurrentStops: TStopSettings;
    procedure InitializeCanon;
    procedure CheckQuietPublication;
  end;

function HasStrategy({$ifdef MOONSHOT_BORROWED_CONTENT}const{$endif} mc: TMessageContent): boolean; inline;
function SameDoubleBits(const A, B: double): boolean; inline;
procedure InitOrderState(out S: TOrderState); inline;
function IsTerminalOrderStatus(AStatus: byte): boolean; inline;
function DiffSectionMask(const A, B: TOrderState): word;
function OrderTZShift: TDateTime;
function OrderTimeToWire(dt: TDateTime; ATZShift: TDateTime): Int64;

implementation

function TimeToUTC(x: double): TDateTime;
begin
  { Platform adapter: uses the standard Delphi/Moon time-zone API on both
    targets. Production Win64 uses TzSpecificLocalTimeToSystemTime directly. }
  Result := TTimeZone.Local.ToUniversalTime(x);
end;
function GetTimeMS: int64;
begin
  Result := GetTickCount64;
end;

function DateTimeToUnixMS(const AValue: TDateTime): Int64;
begin
  Result := MilliSecondsBetween(UnixDateDelta, AValue);
end;

function HasStrategy({$ifdef MOONSHOT_BORROWED_CONTENT}const{$endif} mc: TMessageContent): boolean;
begin
  Result := mc.HasStrategy and (mc.sg <> nil);
end;

function SellReasonToCode(const AReason: string): TSellReasonCode;
begin
  Result := srcUnknown;
  If AReason = '' then exit;

  // Точные совпадения сначала
  If AReason = 'Sell Price' then exit(srcSellPrice);
  If AReason = 'Auto Price Down' then exit(srcAutoPriceDown);
  If AReason = 'SellSpread' then exit(srcSellSpread);
  If AReason = 'SellShot' then exit(srcSellShot);
  If AReason = 'Market Stop' then exit(srcMarketStop);
  If AReason = 'MarketStop PanicSell' then exit(srcMarketStop);
  If AReason = 'Manual Sell' then exit(srcManualSell);
  If AReason = 'Manual PanicSell' then exit(srcPanicSell);
  If AReason = 'JoinedSell' then exit(srcJoinedSell);
  If AReason = 'SellFromAssets' then exit(srcSellFromAssets);

  // Частичные совпадения
  If AReason.StartsWith('Sell Level') then exit(srcSellLevel);
  If AReason.Contains('TrailingStop') then exit(srcTrailing);
  If AReason.Contains('StopLoss') then exit(srcStopLoss);
  If AReason.Contains('BV/SV Stop') then exit(srcBV_SV_Stop);
  If AReason.Contains('PanicSell') or AReason.Contains('Global PanicSell') then exit(srcPanicSell);
  If AReason.Contains('TakeProfit') then exit(srcTakeProfit);
end;

procedure InitOrderState(out S: TOrderState);
begin
  FillChar(S, SizeOf(S), 0);
end;

function DiffSectionMask(const A, B: TOrderState): word;
begin
  Result := 0;
  for var k := 0 to OrderSectionCount - 1 do
    If not CompareMem(PByte(@A) + OrderSectionOffset[k], PByte(@B) + OrderSectionOffset[k], OrderSectionSize[k]) then
      Result := Result or (1 shl k);
end;

function IsTerminalOrderStatus(AStatus: byte): boolean;
begin
  // Нормализованный терминальный набор v1 (§3 спеки); Life/Final на wire не существует
  Result := TOrderWorkerStatus(AStatus) in [OS_SelLDone, OS_BuyCancel, OS_BuyFail, OS_SellCancel, OS_SellFail];
end;

function OrderTZShift: TDateTime;
begin
  Result := round((Now - TimeToUTC(Now)) * MinsInDay) / MinsInDay;
end;

function OrderTimeToWire(dt: TDateTime; ATZShift: TDateTime): Int64;
begin
  // Всё раньше 1970 (включая незаполненный 0 и v1-полусентинелы «<1») — не факт, а пустота.
  // DateTimeToUnixMS default (AInputIsUTC=true) — чистая epoch-арифметика, как во всех движках
  If dt < UnixDateDelta
    then Result := 0
    else Result := DateTimeToUnixMS(dt - ATZShift);
end;

function SameDoubleBits(const A, B: double): boolean; inline;
type
  PI64 = ^Int64;
begin
  Result := PI64(@A)^ = PI64(@B)^;
end;

procedure FillExecSection(const o: TOrder; var E: TOrderExecSection);
begin
  E.QuantityRemaining := o.QuantityRemaining;
  E.ActualQ := o.ActualQ;
  E.TotalBTC := o.TotalBTC;
  E.MeanPrice := o.MeanPrice;
  E.PartialDone := o.PartialDone;
end;

procedure FillPlacementSection(const o: TOrder; var P: TOrderPlacementSection; const ATZ: TDateTime);
begin
  P.intID := o.intID;
  P.ActualPrice := o.ActualPrice;
  P.OpenTime := OrderTimeToWire(o.OpenTime, ATZ);
  P.Quantity := o.Quantity;
  P.QuantityBase := o.QuantityBase;
  P.CloseTime := OrderTimeToWire(o.CloseTime, ATZ);
  P.CreateTime := OrderTimeToWire(o.CreateTime, ATZ);
  P.StopFlag := o.StopFlag;
  P.OrderType := byte(o.OrderType);
  P.SubType := byte(o.SubType);
  P.Leverage := o.Leverage;
  P.IsOpened := ord(o.IsOpened);
  P.IsClosed := ord(o.IsClosed);
  P.Canceled := ord(o.Canceled);
end;

procedure FillSlowSection(const o: TOrder; var SL: TOrderSlowSection);
begin
  SL.SpentBTC := o.SpentBTC;
  SL.tmpBTC := o.tmpBTC;
  SL.PanicSellDown := o.PanicSellDown;
end;

function TOrderPublication.HotCanonDiff(const P: TOrderState): word;

  function LegDiff(const o: TOrder; const E: TOrderExecSection; const PL: TOrderPlacementSection;
                   const APrevOpenTime: TDateTime; AExecBit, APlacementBit: word): word;
  begin
    Result := 0;
    If not (SameDoubleBits(o.QuantityRemaining, E.QuantityRemaining) and
            SameDoubleBits(o.ActualQ, E.ActualQ) and
            SameDoubleBits(o.TotalBTC, E.TotalBTC) and
            SameDoubleBits(o.MeanPrice, E.MeanPrice) and
            (o.PartialDone = E.PartialDone)) then
      Result := AExecBit;
    If not ((o.intID = PL.intID) and
            SameDoubleBits(o.ActualPrice, PL.ActualPrice) and
            SameDoubleBits(o.OpenTime, APrevOpenTime) and
            SameDoubleBits(o.Quantity, PL.Quantity) and
            SameDoubleBits(o.QuantityBase, PL.QuantityBase) and
            (o.StopFlag = PL.StopFlag) and
            (byte(o.OrderType) = PL.OrderType) and
            (byte(o.SubType) = PL.SubType) and
            (o.Leverage = PL.Leverage) and
            (ord(o.IsOpened) = PL.IsOpened) and
            (ord(o.IsClosed) = PL.IsClosed) and
            (ord(o.Canceled) = PL.Canceled)) then
      Result := Result or APlacementBit;
  end;

var
  StratID:  UInt64;
  SizeSame: boolean;
begin
  // PHASE. Терминальное окно до финальной точки — редкие 2-4 вызова на жизнь: судит полная сборка
  If IsTerminalOrderStatus(byte(Status)) then exit(1 shl OSEC_PHASE);
  If byte(Status) <> P.Status then exit(1 shl OSEC_PHASE);
  If HasStrategy(MContent) and (MContent.sg <> nil)
    then StratID := MContent.sg.StrategyID
    else StratID := 0;
  If StratID <> P.EffectiveStratID then exit(1 shl OSEC_PHASE);

  Result := 0;

  // FLAGS
  If (SellReason <> FPrevSellReason) or
     (ImmuneForClicks <> ((P.Flags and OFL_Immune) <> 0)) or
     (FPanicSell <> ((P.Flags and OFL_PanicOn) <> 0)) or
     (PanicSellAutoActivated <> ((P.Flags and OFL_PanicAuto) <> 0)) then
    Result := 1 shl OSEC_FLAGS;

  // TARGET
  If IsPending and (vOrder <> nil) then begin
    If not (SameDoubleBits(vOrder.BuyCondPrice, P.TargetBuyPrice) and
            SameDoubleBits(vOrder.OrderSize, P.TargetBuySize)) then
      Result := Result or (1 shl OSEC_BUY_TARGET);
  end else begin
    If vOrder <> nil
      then SizeSame := SameDoubleBits(vOrder.OrderSize, P.TargetBuySize)
      else SizeSame := SameDoubleBits(BTCBalance, P.TargetBuySize);
    If not (SameDoubleBits(pBuyOrder.Price, P.TargetBuyPrice) and SizeSame) then
      Result := Result or (1 shl OSEC_BUY_TARGET);
  end;
  If ord(pBuyOrder.OrderReplace) <> P.BuyReplacing then
    Result := Result or (1 shl OSEC_BUY_TARGET);
  If not SameDoubleBits(pSellOrder.Price, P.TargetSell) or
     (ord(pSellOrder.OrderReplace) <> P.SellReplacing) then
    Result := Result or (1 shl OSEC_SELL_TARGET);

  // Активная нога (терминалы вышли выше; OS_None-пендинг живёт на buy-ноге — MeanPrice-мост цикла)
  If Status = OS_SellSet
    then Result := Result or LegDiff(pSellOrder^, P.SellExec, P.SellPlacement, FPrevSellOpenTime,
                                     1 shl OSEC_SELL_EXEC, 1 shl OSEC_SELL_PLACEMENT)
    else Result := Result or LegDiff(pBuyOrder^, P.BuyExec, P.BuyPlacement, FPrevBuyOpenTime,
                                     1 shl OSEC_BUY_EXEC, 1 shl OSEC_BUY_PLACEMENT);

  // STOPS/VSTOP: vOrder = nil -> сборка берёт из канона, расхождения нет by construction
  If vOrder <> nil then begin
    If not ((vOrder.StopLossOn = P.Stops.StopLossOn) and
            (vOrder.SLFixed = P.Stops.SLFixed) and
            SameDoubleBits(vOrder.SLLevel, P.Stops.SLLevel) and
            SameDoubleBits(vOrder.SLspread, P.Stops.SLspread) and
            (vOrder.TrailingOn = P.Stops.TrailingOn) and
            (vOrder.TrailingFixed = P.Stops.TrailingFixed) and
            SameDoubleBits(vOrder.TrailingLevel, P.Stops.TrailingLevel) and
            SameDoubleBits(vOrder.TSSpread, P.Stops.TSSpread) and
            (vOrder.UseTakeProfit = P.Stops.UseTakeProfit) and
            SameDoubleBits(vOrder.TakeProfit, P.Stops.TakeProfit) and
            (vOrder.TakeProfitChanged = P.Stops.TakeProfitChanged)) then
      Result := Result or (1 shl OSEC_STOPS);
    If not ((ord(vOrder.VStopON) = P.VStopOn) and
            (ord(vOrder.VStopFixed) = P.VStopFixed) and
            SameDoubleBits(vOrder.VStopLevel, P.VStopLevel) and
            SameDoubleBits(vOrder.VStopVol, P.VStopVol)) then
      Result := Result or (1 shl OSEC_VSTOP);
  end;

  // PLANNED
  If not SameDoubleBits(MContent.PredefinedSellPrice, P.PredefinedSellPrice) or
     (ord(MContent.UseMarketStop) <> P.UseMarketStop) then
    Result := Result or (1 shl OSEC_PLANNED);
end;

procedure TOrderPublication.BuildOrderStateCandidate(APrev: POrderState; out S: TOrderState);
var
  TZ: TDateTime;   // одна конверсия зоны на сборку (канон-паттерн TZShift)
  Birth, PhaseChanges, SlowAllowed: boolean;
begin
  InitOrderState(S);
  Birth := APrev = nil;
  TZ := OrderTZShift;

  S.Status := byte(Status);
  If HasStrategy(MContent) and (MContent.sg <> nil)
    then S.EffectiveStratID := MContent.sg.StrategyID
    else S.EffectiveStratID := 0;
  PhaseChanges := Birth or (S.Status <> APrev.Status) or (S.EffectiveStratID <> APrev.EffectiveStratID);

  // FLAGS. Prev-копия — СТРОГО до конверсии кода: при конкурентной подмене строки между
  // двумя чтениями FPrev останется старой и следующий такт перепроверит (лишняя сборка, не пропуск)
  FPrevSellReason := SellReason;
  S.SellReason := byte(SellReasonToCode(SellReason));
  If ImmuneForClicks then S.Flags := S.Flags or OFL_Immune;
  If FPanicSell then S.Flags := S.Flags or OFL_PanicOn;
  If PanicSellAutoActivated then S.Flags := S.Flags or OFL_PanicAuto;

  // TARGET — живые прод-поля цели: пендинг несёт пару условия, нога — цену REST
  If IsPending and (vOrder <> nil) then begin
    S.TargetBuyPrice := vOrder.BuyCondPrice;
    S.TargetBuySize := vOrder.OrderSize;
  end else begin
    S.TargetBuyPrice := pBuyOrder.Price;
    If vOrder <> nil
      then S.TargetBuySize := vOrder.OrderSize
      else S.TargetBuySize := BTCBalance;
  end;
  S.BuyReplacing := ord(pBuyOrder.OrderReplace);
  S.TargetSell := pSellOrder.Price;
  S.SellReplacing := ord(pSellOrder.OrderReplace);

  // EXEC/PLACEMENT — dynamic (PLACEMENT меняется внутри фазы: cancel+set/amend, busy-подпись).
  // FPrev-сырьё OpenTime — СТРОГО до Fill (как FPrevSellReason): гонка WS между двумя
  // чтениями даёт лишнюю сборку следующим тактом, не пропуск
  FPrevBuyOpenTime := pBuyOrder.OpenTime;
  FPrevSellOpenTime := pSellOrder.OpenTime;
  FillExecSection(pBuyOrder^, S.BuyExec);
  FillPlacementSection(pBuyOrder^, S.BuyPlacement, TZ);
  FillExecSection(pSellOrder^, S.SellExec);
  FillPlacementSection(pSellOrder^, S.SellPlacement, TZ);

  // SLOW — заморозка: дребезг tmpBTC/SpentBTC/PanicSellDown не чаще ~раза в 9с;
  // first/PHASE/final снимают свежий срез всегда. Окно двигает сам факт свежего среза
  // (не минт): иначе холостая периодическая сверка зацикливала бы полную сборку каждый такт
  SlowAllowed := Birth or PhaseChanges or
                 (abs(GetTimeMS - FLastSlowSampleMS) >= OrdersSyncPeriodMS);
  If SlowAllowed then begin
    FillSlowSection(pBuyOrder^, S.BuySlow);
    FillSlowSection(pSellOrder^, S.SellSlow);
    FLastSlowSampleMS := GetTimeMS;
  end else begin
    S.BuySlow := APrev.BuySlow;
    S.SellSlow := APrev.SellSlow;
  end;

  // STOPS/VSTOP — владелец vOrder; в эпилоге (vOrder уже отвязан main'ом) — из committed
  // канона: нулевые стопы с новой rev авторитетно глушили бы их на живом зеркале
  If vOrder <> nil then begin
    S.Stops := GetCurrentStops;
    S.VStopOn := ord(vOrder.VStopON);
    S.VStopFixed := ord(vOrder.VStopFixed);
    S.VStopLevel := vOrder.VStopLevel;
    S.VStopVol := vOrder.VStopVol;
  end else If not Birth then begin
    S.Stops := APrev.Stops;
    S.VStopOn := APrev.VStopOn;
    S.VStopFixed := APrev.VStopFixed;
    S.VStopLevel := APrev.VStopLevel;
    S.VStopVol := APrev.VStopVol;
  end;

  // PLANNED
  S.PredefinedSellPrice := MContent.PredefinedSellPrice;
  S.UseMarketStop := ord(MContent.UseMarketStop);
end;

function TOrderPublication.GetCurrentStops: TStopSettings;
begin
  FillChar(Result, SizeOf(Result), 0);
  if vOrder <> nil then begin
    Result.StopLossOn := vOrder.StopLossOn;
    Result.SLFixed := vOrder.SLFixed;
    Result.SLLevel := vOrder.SLLevel;
    Result.SLspread := vOrder.SLspread;
    Result.TrailingOn := vOrder.TrailingOn;
    Result.TrailingFixed := vOrder.TrailingFixed;
    Result.TrailingLevel := vOrder.TrailingLevel;
    Result.TSSpread := vOrder.TSSpread;
    Result.UseTakeProfit := vOrder.UseTakeProfit;
    Result.TakeProfit := vOrder.TakeProfit;
    Result.TakeProfitChanged := vOrder.TakeProfitChanged;
  end;
end;

constructor TOrderPublication.Create;
begin
  inherited Create;
  pBuyOrder := @BuyOrder;
  pSellOrder := @SellOrder;
  vOrder := TVisualOrderItem.Create;
  Status := OS_BuySet;
  SellReason := 'Sell Price';
end;

destructor TOrderPublication.Destroy;
begin
  FreeAndNil(vOrder);
  inherited Destroy;
end;

procedure TOrderPublication.InitializeCanon;
begin
  If (SizeOf(TOrderState) <> OrderStateSize) or (SizeOf(TStopSettings) <> 46) then
    raise EUnexpectedOrderPublication.Create('canonical record layout mismatch');
  If (Status <> OS_BuySet) or IsPending then
    raise EUnexpectedOrderPublication.Create('expected quiet BuySet initialization');
  BuildOrderStateCandidate(nil, Canon);
end;

procedure TOrderPublication.CheckQuietPublication;
var
  Cand: TOrderState;
  Mask: word;
begin
  { Source SendMServer's established-node, no-change path. At the periodic
    boundary the real full candidate and all 13 section comparisons run. }
  var NeedFull := abs(GetTimeMS - FLastSlowSampleMS) >= OrdersSyncPeriodMS;
  If not NeedFull then begin
    Inc(HotChecks);
    Mask := HotCanonDiff(Canon);
    If Mask = 0 then exit;
    Inc(ChangedChecks);
    raise EUnexpectedOrderPublication.CreateFmt('quiet hot state changed: mask=%d', [Mask]);
  end;

  Inc(FullChecks);
  BuildOrderStateCandidate(@Canon, Cand);
  Mask := DiffSectionMask(Cand, Canon);
  If Mask = 0 then exit;
  Inc(ChangedChecks);
  raise EUnexpectedOrderPublication.CreateFmt('quiet periodic state changed: mask=%d', [Mask]);
end;

end.
