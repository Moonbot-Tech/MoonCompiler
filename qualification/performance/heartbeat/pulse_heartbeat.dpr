program pulse_heartbeat;

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
  SysUtils,
  Variants,
  Generics.Defaults,
  Generics.Collections,
  mormot.core.base,
  mormot.core.unicode,
  mormot.core.text,
  mormot.core.json,
  mormot.core.variants,
  perf_clock in '..\common\perf_clock.pas',
  pulse_process_metrics in '..\common\pulse_process_metrics.pas',
  pulse_harness in '..\common\pulse_harness.pas';

{ Heartbeat is one application-shaped benchmark with independent hot-path
  lines. It covers a deterministic market-data cycle plus concentrated work
  from trading and server programs: order-book deltas and sweeps, sorting,
  binary request/cache/response handling and a timer heap. It deliberately
  contains no network, storage, logging or server framework. }

const
  SmallMarkets = 100;
  LargeMarkets = 1000;
  RingSize = 1024;
  RingMask = RingSize - 1;
  SmallMessagesPerMarket = 1536;
  LargeMessagesPerMarket = 384;
  MissEvery = 16;
  CorrMarkets = 32;
  CorrWindow = 256;
  FftMarkets = 32;
  FftSize = 1024;
  TopCount = 20;
  BookLevels = 4096;
  BookDeltaCount = 8192;
  BookSweepCount = 2048;
  SortItemCount = 8192;
  SessionCount = 4096;
  RequestCount = 16384;
  TimerCount = 8192;
  TimerOperationCount = 16384;
  PriceScale = 100000000;
  InvPriceScale = 1.0 / PriceScale;
  RollWindow = 32;
  BaseTimeMs = Int64(1700000000000);
  { name-case-sensitive wire parsing: ReturnNull + ByRef + CaseSensitive }
  WireJsonModel = mNameValue;

type
  TTradeSim = packed record
    Price: Double;
    Qty: Single;
    TimeMs: UInt32;
  end;

  TMarketDescriptor = record
    Symbol, BaseAsset, QuoteAsset: RawUtf8;
    SymbolS, BaseAssetS, QuoteAssetS: string;
    TickE8, StepE8, MinNotionalE8: Int64;
    Trading: Boolean;
    StartPriceE8: Int64;
    WalkSeed: UInt64;
  end;
  TMarketDescriptorArray = array of TMarketDescriptor;

  TMarketSim = class
  public
    Symbol, BaseAsset, QuoteAsset: UnicodeString;
    TickSize, StepSize, MinNotional: Double;
    Trading: Boolean;
    Ring: array of TTradeSim;
    RingHead, RingCount: Integer;
    SumPQ, SumQ, Vwap, LastPrice, MinPrice, MaxPrice: Double;
    Signals: Integer;
    procedure EnsureRing;
  end;

  TMarketList = TObjectList<TMarketSim>;
  TSymbolIndex = TDictionary<UnicodeString, TMarketSim>;

  TComplex = record
    Re, Im: Double;
  end;

  TBookLevel = packed record
    PriceE8, QtyE8: Int64;
  end;
  TBookLevelArray = array of TBookLevel;

  TBookDelta = packed record
    PriceE8, QtyE8: Int64;
    Reinsert: Boolean;
  end;
  TBookDeltaArray = array of TBookDelta;

  TInt64Array = array of Int64;

  TSessionState = packed record
    LastSequence: UInt32;
    Accepted: UInt32;
    RollingHash: UInt64;
  end;
  TSessionStateArray = array of TSessionState;
  TSessionIndex = TDictionary<UInt64, Integer>;

  TWireHeader = packed record
    SessionId: UInt64;
    Sequence: UInt32;
    PayloadSize: Word;
    Opcode: Byte;
    Flags: Byte;
  end;

  TWireResponse = packed record
    SessionId: UInt64;
    Sequence: UInt32;
    Status: UInt32;
    PayloadHash: UInt64;
  end;
  PWireResponse = ^TWireResponse;
  TWireResponseArray = array of TWireResponse;

  TTimerEvent = packed record
    Deadline, Token: UInt64;
  end;
  TTimerEventArray = array of TTimerEvent;

  TTurnoverComparer = class(TInterfacedObject, IComparer<Integer>)
  private
    FMarkets: TMarketList;
  public
    constructor Create(Markets: TMarketList);
    function Compare(const Left, Right: Integer): Integer;
  end;

var
  SmallDescriptors, LargeDescriptors: TMarketDescriptorArray;
  InfoJsonSmall, InfoJsonLarge: RawUtf8;
  TradeBufferSmall, TradeBufferLarge: RawByteString;
  PreparedSmall, PreparedLarge: TMarketList;
  IndexSmall, IndexLarge: TSymbolIndex;
  TotalTradesLarge: UInt64;
  UnsortedOrderLarge: TArray<Integer>;
  ComparerLarge: IComparer<Integer>;
  TopSmall: array of Integer;
  JsonProofSmall, JsonProofLarge: UInt64;
  MarketsProofSmall, MarketsProofLarge: UInt64;
  BookTemplate, BidBook, AskBook: TBookLevelArray;
  BookDeltas: TBookDeltaArray;
  SweepQuantities: TInt64Array;
  SortRandom, SortAscending, SortDescending, SortDuplicates: TInt64Array;
  RequestBuffer: RawByteString;
  SessionsTemplate: TSessionStateArray;
  SessionIndex: TSessionIndex;
  Responses: TWireResponseArray;
  TimerTemplate: TTimerEventArray;

procedure TMarketSim.EnsureRing;
begin
  If Ring = nil then
    SetLength(Ring, RingSize);
end;

constructor TTurnoverComparer.Create(Markets: TMarketList);
begin
  inherited Create;
  FMarkets := Markets;
end;

function TTurnoverComparer.Compare(const Left, Right: Integer): Integer;
var
  L, R: Double;
begin
  L := FMarkets[Left].SumPQ;
  R := FMarkets[Right].SumPQ;
  If L > R then
    Result := -1
  else If L < R then
    Result := 1
  else
    Result := Left - Right;
end;

function NextRandom(var State: UInt64): UInt64;
begin
  State := State xor (State shr 12);
  State := State xor (State shl 25);
  State := State xor (State shr 27);
  Result := State * UInt64($2545F4914F6CDD1D);
end;

function DoubleBits(const Value: Double): UInt64;
begin
  Result := 0;
  Move(Value, Result, SizeOf(Result));
end;

function RotL(Value: UInt64; Bits: Integer): UInt64;
begin
  Bits := Bits and 63;
  If Bits = 0 then
    Result := Value
  else
    Result := (Value shl Bits) or (Value shr (64 - Bits));
end;

function HashBytes(Data: Pointer; Count: NativeInt): UInt64;
const
  OffsetBasis = UInt64($CBF29CE484222325);
  Prime = UInt64($00000100000001B3);
var
  P: PByte;
begin
  Result := OffsetBasis;
  P := Data;
  while Count > 0 do
  begin
    Result := (Result xor P^) * Prime;
    Inc(P);
    Dec(Count);
  end;
end;

function FullRawDigest(const Value: RawByteString): UInt64;
begin
  If Value = '' then
    Result := HashBytes(nil, 0)
  else
    Result := HashBytes(pointer(Value), Length(Value));
end;

function FullUnicodeDigest(const Value: UnicodeString): UInt64;
begin
  If Value = '' then
    Result := HashBytes(nil, 0)
  else
    Result := HashBytes(pointer(Value), Length(Value) * SizeOf(WideChar));
end;

{ ---------------- deterministic market universe ---------------- }

function QuoteAssetOf(Index: Integer): RawUtf8;
begin
  case Index and 3 of
    0: Result := 'USDT';
    1: Result := 'BTC';
    2: Result := 'ETH';
  else
    Result := 'BNB';
  end;
end;

function BaseAssetOf(Index: Integer): RawUtf8;
begin
  SetLength(Result, 3);
  { first letter stays below Z: Z is reserved for miss symbols }
  PByteArray(Result)[0] := Ord('A') + (Index div 676) mod 25;
  PByteArray(Result)[1] := Ord('A') + (Index div 26) mod 26;
  PByteArray(Result)[2] := Ord('A') + Index mod 26;
end;

function MissSymbolOf(Index: Integer): RawUtf8;
begin
  SetLength(Result, 3);
  PByteArray(Result)[0] := Ord('Z');
  PByteArray(Result)[1] := Ord('A') + (Index div 26) mod 26;
  PByteArray(Result)[2] := Ord('A') + Index mod 26;
  Result := Result + QuoteAssetOf(Index);
end;

function BuildDescriptors(Count: Integer): TMarketDescriptorArray;
const
  TickTable: array[0..5] of Int64 = (1, 10, 100, 1000, 10000, 100000);
  StepTable: array[0..3] of Int64 = (1000000, 10000000, 100000000, 1000000000);
var
  I: Integer;
  Seed: UInt64;
begin
  SetLength(Result, Count);
  Seed := UInt64($C0FFEE0DDF00D001);
  for I := 0 to Count - 1 do
  begin
    Result[I].BaseAsset := BaseAssetOf(I);
    Result[I].QuoteAsset := QuoteAssetOf(I);
    Result[I].Symbol := Result[I].BaseAsset + Result[I].QuoteAsset;
    Result[I].SymbolS := Utf8ToString(Result[I].Symbol);
    Result[I].BaseAssetS := Utf8ToString(Result[I].BaseAsset);
    Result[I].QuoteAssetS := Utf8ToString(Result[I].QuoteAsset);
    Result[I].TickE8 := TickTable[NextRandom(Seed) mod 6];
    Result[I].StepE8 := StepTable[NextRandom(Seed) mod 4];
    If (NextRandom(Seed) and 1) = 0 then
      Result[I].MinNotionalE8 := 5 * PriceScale
    else
      Result[I].MinNotionalE8 := 10 * PriceScale;
    Result[I].Trading := (I mod MissEvery) <> (MissEvery - 1);
    Result[I].StartPriceE8 := Result[I].TickE8 *
      Int64(1000 + NextRandom(Seed) mod 1000000);
    Result[I].WalkSeed := NextRandom(Seed) or 1;
  end;
end;

{ ---------------- fixed-point amount text (8 decimals) ---------------- }

function AmountToText(ValueE8: Int64): string;
begin
  Result := IntToStr(ValueE8 div PriceScale) + '.' +
    Format('%.8d', [ValueE8 mod PriceScale]);
end;

function AmountToUtf8(ValueE8: Int64): RawUtf8;
var
  Frac: Int64;
  I: Integer;
begin
  Result := Int64ToUtf8(ValueE8 div PriceScale) + '.00000000';
  Frac := ValueE8 mod PriceScale;
  I := Length(Result);
  while Frac <> 0 do
  begin
    PByteArray(Result)[I - 1] := Ord('0') + Frac mod 10;
    Frac := Frac div 10;
    Dec(I);
  end;
end;

{ ---------------- exchange-info generation: two byte-identical writers ------ }

function StatusText(Trading: Boolean): string;
begin
  If Trading then
    Result := 'TRADING'
  else
    Result := 'BREAK';
end;

function BuildInfoFormat(const Markets: TMarketDescriptorArray): RawUtf8;
var
  I: Integer;
  Body: string;
begin
  Body := '{"symbols":[';
  for I := 0 to High(Markets) do
  begin
    If I > 0 then
      Body := Body + ',';
    Body := Body + Format(
      '{"symbol":"%s","status":"%s","baseAsset":"%s","quoteAsset":"%s",' +
      '"tickSize":"%s","stepSize":"%s","minNotional":"%s"}',
      [Markets[I].SymbolS, StatusText(Markets[I].Trading),
       Markets[I].BaseAssetS, Markets[I].QuoteAssetS,
       AmountToText(Markets[I].TickE8), AmountToText(Markets[I].StepE8),
       AmountToText(Markets[I].MinNotionalE8)]);
  end;
  Body := Body + ']}';
  Result := StringToUtf8(Body);
end;

function BuildInfoMormot(const Markets: TMarketDescriptorArray): RawUtf8;
var
  I: Integer;
  Root, Arr, Obj: TDocVariantData;
  Status: RawUtf8;
begin
  Arr.InitFast(Length(Markets), dvArray);
  for I := 0 to High(Markets) do
  begin
    If Markets[I].Trading then
      Status := 'TRADING'
    else
      Status := 'BREAK';
    Obj.InitObject([
      'symbol', Markets[I].Symbol,
      'status', Status,
      'baseAsset', Markets[I].BaseAsset,
      'quoteAsset', Markets[I].QuoteAsset,
      'tickSize', AmountToUtf8(Markets[I].TickE8),
      'stepSize', AmountToUtf8(Markets[I].StepE8),
      'minNotional', AmountToUtf8(Markets[I].MinNotionalE8)], JSON_FAST);
    Arr.AddItem(Variant(Obj));
    Obj.Clear;
  end;
  Root.InitObject(['symbols', Variant(Arr)], JSON_FAST);
  Result := Root.ToJson;
  Root.Clear;
  Arr.Clear;
end;

function JsonDigest(const Json: RawUtf8): UInt64;
begin
  Result := UInt64(Length(Json));
  If Length(Json) >= 16 then
  begin
    Result := Result xor PUInt64(pointer(Json))^;
    Result := Result xor RotL(PUInt64(@PByteArray(Json)[Length(Json) - 8])^, 31);
  end;
end;

{ ---------------- trade stream generation ---------------- }

function BuildTradeBuffer(const Descriptors: TMarketDescriptorArray;
  MessagesPerMarket: Integer): RawByteString;
var
  PriceE8: array of Int64;
  Seed: array of UInt64;
  Lines: array of RawUtf8;
  MessageIndex, MarketIndex, Total, I: Integer;
  TimeMs: Int64;
  Symbol, Side: RawUtf8;
  QtyE8, Step: Int64;
  Rnd: UInt64;
  Cursor: PAnsiChar;
begin
  SetLength(PriceE8, Length(Descriptors));
  SetLength(Seed, Length(Descriptors));
  for I := 0 to High(Descriptors) do
  begin
    PriceE8[I] := Descriptors[I].StartPriceE8;
    Seed[I] := Descriptors[I].WalkSeed;
  end;
  SetLength(Lines, Length(Descriptors) * MessagesPerMarket);
  TimeMs := BaseTimeMs;
  for MessageIndex := 0 to High(Lines) do
  begin
    MarketIndex := MessageIndex mod Length(Descriptors);
    Rnd := NextRandom(Seed[MarketIndex]);
    If (MessageIndex mod MissEvery) = (MissEvery - 1) then
    begin
      Symbol := MissSymbolOf(MessageIndex);
      QtyE8 := Descriptors[MarketIndex].StepE8;
    end else
    begin
      Symbol := Descriptors[MarketIndex].Symbol;
      Step := Descriptors[MarketIndex].TickE8 * Int64(Rnd mod 7) - 3 *
        Descriptors[MarketIndex].TickE8;
      PriceE8[MarketIndex] := PriceE8[MarketIndex] + Step;
      If PriceE8[MarketIndex] < 100 * Descriptors[MarketIndex].TickE8 then
        PriceE8[MarketIndex] := Descriptors[MarketIndex].StartPriceE8;
      QtyE8 := Descriptors[MarketIndex].StepE8 *
        Int64(1 + (Rnd shr 32) mod 999);
    end;
    TimeMs := TimeMs + Int64((Rnd shr 16) and 15);
    If (Rnd and 1) = 0 then
      Side := 'true'
    else
      Side := 'false';
    Lines[MessageIndex] := '{"e":"trade","s":"' + Symbol + '","p":"' +
      AmountToUtf8(PriceE8[MarketIndex]) + '","q":"' + AmountToUtf8(QtyE8) +
      '","T":' + Int64ToUtf8(TimeMs) + ',"m":' + Side + '}';
  end;
  Total := 0;
  for I := 0 to High(Lines) do
    Inc(Total, Length(Lines[I]));
  SetLength(Result, Total);
  Cursor := pointer(Result);
  for I := 0 to High(Lines) do
  begin
    Move(pointer(Lines[I])^, Cursor^, Length(Lines[I]));
    Inc(Cursor, Length(Lines[I]));
  end;
end;

{ ---------------- exchange-info parsing (mORMot DocVariant) ---------------- }

function FieldAmount(D: PDocVariantData; const Name: RawUtf8): Double;
var
  Text: RawUtf8;
  Error: Integer;
begin
  Text := D^.U[Name];
  Result := GetExtended(pointer(Text), Error);
  If Error <> 0 then
    raise EConvertError.Create('bad amount field: ' + Utf8ToString(Name));
end;

procedure ParseMarkets(const Json: RawUtf8; Markets: TMarketList;
  Index: TSymbolIndex);
var
  Doc: TDocVariantData;
  Arr, Obj: PDocVariantData;
  I: Integer;
  Market: TMarketSim;
begin
  If not Doc.InitJson(Json, WireJsonModel) then
    raise EConvertError.Create('exchange info JSON rejected');
  try
    If not Doc.GetAsDocVariant('symbols', Arr) or not Arr^.IsArray then
      raise EConvertError.Create('symbols array missing');
    for I := 0 to Arr^.Count - 1 do
    begin
      Obj := _Safe(Arr^.Values[I]);
      Market := TMarketSim.Create;
      Markets.Add(Market);
      Market.Symbol := Utf8ToString(Obj^.U['symbol']);
      Market.BaseAsset := Utf8ToString(Obj^.U['baseAsset']);
      Market.QuoteAsset := Utf8ToString(Obj^.U['quoteAsset']);
      Market.Trading := Obj^.U['status'] = 'TRADING';
      Market.TickSize := FieldAmount(Obj, 'tickSize');
      Market.StepSize := FieldAmount(Obj, 'stepSize');
      Market.MinNotional := FieldAmount(Obj, 'minNotional');
      Index.Add(Market.Symbol, Market);
    end;
  finally
    Doc.Clear;
  end;
end;

function MarketsDigest(Markets: TMarketList; Index: TSymbolIndex): UInt64;
var
  I: Integer;
  Market: TMarketSim;
begin
  Result := UInt64(Markets.Count) xor (UInt64(Index.Count) shl 32);
  for I := 0 to Markets.Count - 1 do
  begin
    Market := Markets[I];
    Result := Result xor RotL(DoubleBits(Market.TickSize) xor
      (DoubleBits(Market.StepSize) shr 5) xor
      UInt64(Length(Market.Symbol)) xor
      (UInt64(Length(Market.BaseAsset)) shl 17), I);
    If Market.Trading then
      Inc(Result);
  end;
end;

function FullMarketsDigest(Markets: TMarketList): UInt64;
var
  I: Integer;
  Market: TMarketSim;
begin
  Result := UInt64(Markets.Count);
  for I := 0 to Markets.Count - 1 do
  begin
    Market := Markets[I];
    Result := RotL(Result, 7) xor FullUnicodeDigest(Market.Symbol);
    Result := RotL(Result, 7) xor FullUnicodeDigest(Market.BaseAsset);
    Result := RotL(Result, 7) xor FullUnicodeDigest(Market.QuoteAsset);
    Result := RotL(Result, 7) xor DoubleBits(Market.TickSize);
    Result := RotL(Result, 7) xor DoubleBits(Market.StepSize);
    Result := RotL(Result, 7) xor DoubleBits(Market.MinNotional);
    Result := RotL(Result, 7) xor UInt64(Ord(Market.Trading));
  end;
end;

{ ---------------- trade stream byte scan ---------------- }

function ScanAmountE8(var P: PAnsiChar): Int64;
begin
  Result := 0;
  while (P^ >= '0') and (P^ <= '9') do
  begin
    Result := Result * 10 + (Ord(P^) - Ord('0'));
    Inc(P);
  end;
  Result := Result * PriceScale;
  If P^ = '.' then
  begin
    Inc(P);
    Result := Result + (Ord(P[0]) - Ord('0')) * 10000000 +
      (Ord(P[1]) - Ord('0')) * 1000000 + (Ord(P[2]) - Ord('0')) * 100000 +
      (Ord(P[3]) - Ord('0')) * 10000 + (Ord(P[4]) - Ord('0')) * 1000 +
      (Ord(P[5]) - Ord('0')) * 100 + (Ord(P[6]) - Ord('0')) * 10 +
      (Ord(P[7]) - Ord('0'));
    Inc(P, 8);
  end;
end;

function ScanInt64(var P: PAnsiChar): Int64;
begin
  Result := 0;
  while (P^ >= '0') and (P^ <= '9') do
  begin
    Result := Result * 10 + (Ord(P^) - Ord('0'));
    Inc(P);
  end;
end;

function ScanTrades(const Buffer: RawByteString; Index: TSymbolIndex;
  ResetRings: Boolean): UInt64;
var
  P, PEnd, SymbolStart: PAnsiChar;
  Key: AnsiChar;
  SymbolText: UnicodeString;
  SymbolLen, K, Slot: Integer;
  Market: TMarketSim;
  PriceE8, QtyE8, TimeValue: Int64;
  Buyer: Boolean;
  Hits, Misses: UInt64;
begin
  If ResetRings then
    for Market in Index.Values do
    begin
      Market.RingHead := 0;
      Market.RingCount := 0;
    end;
  Hits := 0;
  Misses := 0;
  Result := 0;
  P := pointer(Buffer);
  PEnd := P + Length(Buffer);
  while P < PEnd do
  begin
    // one message: {"e":"trade","s":"...","p":"...","q":"...","T":...,"m":...}
    Market := nil;
    PriceE8 := 0;
    QtyE8 := 0;
    TimeValue := 0;
    Buyer := False;
    Inc(P); // '{' -> the first key quote
    repeat
      Inc(P); { key quote -> key letter }
      Key := P^;
      Inc(P, 3); { key letter, closing quote, colon -> first value char }
      case Key of
        'e':
        begin
          Inc(P);
          while P^ <> '"' do
            Inc(P);
          Inc(P);
        end;
        's':
        begin
          Inc(P);
          SymbolStart := P;
          while P^ <> '"' do
            Inc(P);
          SymbolLen := P - SymbolStart;
          Inc(P);
          If Length(SymbolText) <> SymbolLen then
            SetLength(SymbolText, SymbolLen);
          for K := 0 to SymbolLen - 1 do
            PWordArray(pointer(SymbolText))[K] := Ord(SymbolStart[K]);
          If not Index.TryGetValue(SymbolText, Market) then
            Market := nil;
        end;
        'p':
        begin
          Inc(P);
          PriceE8 := ScanAmountE8(P);
          Inc(P);
        end;
        'q':
        begin
          Inc(P);
          QtyE8 := ScanAmountE8(P);
          Inc(P);
        end;
        'T':
          TimeValue := ScanInt64(P);
        'm':
        begin
          Buyer := P^ = 't';
          If Buyer then
            Inc(P, 4)
          else
            Inc(P, 5);
        end;
      end;
      If P^ <> ',' then
        Break;
      Inc(P); // ',' -> the next key quote
    until False;
    Inc(P); { skip the closing brace }
    If Market <> nil then
    begin
      Market.EnsureRing;
      Slot := Market.RingHead;
      Market.Ring[Slot].Price := PriceE8 * InvPriceScale;
      Market.Ring[Slot].Qty := QtyE8 * InvPriceScale;
      Market.Ring[Slot].TimeMs := UInt32(TimeValue);
      Market.RingHead := (Slot + 1) and RingMask;
      If Market.RingCount < RingSize then
        Inc(Market.RingCount);
      Inc(Hits);
      Result := Result xor RotL(UInt64(PriceE8) xor (UInt64(QtyE8) shl 7) xor
        UInt64(TimeValue), Slot and 63);
      If Buyer then
        Inc(Result);
    end else
      Inc(Misses);
  end;
  Result := Result xor (Hits shl 1) xor (Misses shl 33);
end;

{ ---------------- ring aggregation ---------------- }

function AggregateMarkets(Markets: TMarketList): UInt64;
var
  MarketIndex, I, Start, Slot: Integer;
  Market: TMarketSim;
  Price, Qty, RollSum: Double;
  Signals: Integer;
begin
  Result := 0;
  for MarketIndex := 0 to Markets.Count - 1 do
  begin
    Market := Markets[MarketIndex];
    Market.SumPQ := 0;
    Market.SumQ := 0;
    Market.Signals := 0;
    If Market.RingCount = 0 then
      Continue;
    Start := (Market.RingHead - Market.RingCount) and RingMask;
    Market.MinPrice := Market.Ring[Start].Price;
    Market.MaxPrice := Market.MinPrice;
    RollSum := 0;
    Signals := 0;
    for I := 0 to Market.RingCount - 1 do
    begin
      Slot := (Start + I) and RingMask;
      Price := Market.Ring[Slot].Price;
      Qty := Market.Ring[Slot].Qty;
      Market.SumPQ := Market.SumPQ + Price * Qty;
      Market.SumQ := Market.SumQ + Qty;
      If Price < Market.MinPrice then
        Market.MinPrice := Price;
      If Price > Market.MaxPrice then
        Market.MaxPrice := Price;
      RollSum := RollSum + Price;
      If I >= RollWindow then
      begin
        RollSum := RollSum - Market.Ring[(Start + I - RollWindow) and
          RingMask].Price;
        If Price * RollWindow > RollSum then
          Inc(Signals);
      end;
      Market.LastPrice := Price;
    end;
    Market.Vwap := Market.SumPQ / Market.SumQ;
    Market.Signals := Signals;
    Result := Result xor RotL(DoubleBits(Market.SumPQ) xor
      (DoubleBits(Market.Vwap) shr 3) xor
      (DoubleBits(Market.MaxPrice - Market.MinPrice) shl 11) xor
      UInt64(Signals), MarketIndex and 63);
  end;
end;

{ ---------------- spectral analysis ---------------- }

procedure Fft(var Data: array of TComplex);
var
  I, J, K, M, Half: Integer;
  Angle, WRe, WIm, URe, UIm, TRe, TIm: Double;
  Temp: TComplex;
begin
  J := 0;
  for I := 1 to High(Data) do
  begin
    K := Length(Data) shr 1;
    while (J and K) <> 0 do
    begin
      J := J xor K;
      K := K shr 1;
    end;
    J := J xor K;
    If I < J then
    begin
      Temp := Data[I];
      Data[I] := Data[J];
      Data[J] := Temp;
    end;
  end;
  M := 2;
  while M <= Length(Data) do
  begin
    Half := M shr 1;
    for K := 0 to Half - 1 do
    begin
      Angle := -2.0 * Pi * K / M;
      WRe := Cos(Angle);
      WIm := Sin(Angle);
      I := K;
      while I < Length(Data) do
      begin
        J := I + Half;
        TRe := WRe * Data[J].Re - WIm * Data[J].Im;
        TIm := WRe * Data[J].Im + WIm * Data[J].Re;
        URe := Data[I].Re;
        UIm := Data[I].Im;
        Data[I].Re := URe + TRe;
        Data[I].Im := UIm + TIm;
        Data[J].Re := URe - TRe;
        Data[J].Im := UIm - TIm;
        Inc(I, M);
      end;
    end;
    M := M shl 1;
  end;
end;

function SpectrumDigest(Markets: TMarketList): UInt64;
const
  Normalize = 0.001;
var
  Data: array of TComplex;
  MarketIndex, I, Start: Integer;
  Market: TMarketSim;
  S: Double;
begin
  { Sin/Cos may differ in the last bit between the two RTLs, so the digest
    quantizes the spectrum instead of comparing raw double bits. }
  Result := 0;
  SetLength(Data, FftSize);
  for MarketIndex := 0 to FftMarkets - 1 do
  begin
    Market := Markets[MarketIndex];
    Start := (Market.RingHead - Market.RingCount) and RingMask;
    for I := 0 to FftSize - 1 do
    begin
      Data[I].Re := Market.Ring[(Start + I) and RingMask].Price * Normalize;
      Data[I].Im := 0;
    end;
    Fft(Data);
    S := Abs(Data[1].Re) + Abs(Data[1].Im) + Abs(Data[17].Re) +
      Abs(Data[17].Im) + Abs(Data[FftSize div 2].Re);
    Result := Result xor RotL(UInt64(Trunc(S * 1000.0)), MarketIndex);
  end;
end;

{ ---------------- pairwise correlation ---------------- }

function CorrelationDigest(Markets: TMarketList): UInt64;
var
  Series: array of Double;
  Mean, Norm: array of Double;
  A, B, I, Start: Integer;
  Market: TMarketSim;
  Sum, Dot, Total: Double;
begin
  SetLength(Series, CorrMarkets * CorrWindow);
  SetLength(Mean, CorrMarkets);
  SetLength(Norm, CorrMarkets);
  for A := 0 to CorrMarkets - 1 do
  begin
    Market := Markets[A];
    Start := (Market.RingHead - CorrWindow) and RingMask;
    Sum := 0;
    for I := 0 to CorrWindow - 1 do
    begin
      Series[A * CorrWindow + I] :=
        Market.Ring[(Start + I) and RingMask].Price;
      Sum := Sum + Series[A * CorrWindow + I];
    end;
    Mean[A] := Sum * (1.0 / CorrWindow);
    Sum := 0;
    for I := 0 to CorrWindow - 1 do
    begin
      Series[A * CorrWindow + I] := Series[A * CorrWindow + I] - Mean[A];
      Sum := Sum + Series[A * CorrWindow + I] * Series[A * CorrWindow + I];
    end;
    Norm[A] := Sqrt(Sum);
  end;
  Total := 0;
  for A := 0 to CorrMarkets - 2 do
    for B := A + 1 to CorrMarkets - 1 do
    begin
      Dot := 0;
      for I := 0 to CorrWindow - 1 do
        Dot := Dot + Series[A * CorrWindow + I] * Series[B * CorrWindow + I];
      If (Norm[A] > 0) and (Norm[B] > 0) then
        Total := Total + Dot / (Norm[A] * Norm[B]);
    end;
  Result := DoubleBits(Total);
end;

{ ---------------- ranking and report ---------------- }

function RankDigest(const Source: TArray<Integer>;
  const Comparer: IComparer<Integer>): UInt64;
var
  Order: TArray<Integer>;
  I: Integer;
begin
  SetLength(Order, Length(Source));
  Move(Source[0], Order[0], Length(Source) * SizeOf(Integer));
  TArray.Sort<Integer>(Order, Comparer);
  Result := 0;
  I := 0;
  while I < Length(Order) do
  begin
    Result := Result xor RotL(UInt64(UInt32(Order[I])), I and 63);
    If I < 16 then
      Inc(I)
    else
      Inc(I, 61);
  end;
end;

function ReportDigest(Markets: TMarketList; const Top: array of Integer): UInt64;
var
  I: Integer;
  Market: TMarketSim;
  Line, Report: string;
begin
  Result := 0;
  Report := '';
  for I := 0 to High(Top) do
  begin
    Market := Markets[Top[I]];
    Line := Format('%2d %s-%s last=%.8f vwap=%.8f turnover=%.2f signals=%d',
      [I + 1, Market.BaseAsset, Market.QuoteAsset, Market.LastPrice,
       Market.Vwap, Market.SumPQ, Market.Signals]);
    Report := Report + Line + #13#10;
    Result := Result xor RotL(UInt64(Length(Line)), I);
  end;
  Result := Result xor (UInt64(Length(Report)) shl 32);
end;

{ ---------------- concentrated trading hot paths ---------------- }

function LowerBoundBook(const Book: TBookLevelArray; Count: Integer;
  PriceE8: Int64): Integer;
var
  L, H, M: Integer;
begin
  L := 0;
  H := Count;
  while L < H do
  begin
    M := L + (H - L) shr 1;
    If Book[M].PriceE8 < PriceE8 then
      L := M + 1
    else
      H := M;
  end;
  Result := L;
end;

function RunBookDeltas(Iterations: Integer): UInt64;
var
  Book: TBookLevelArray;
  I, J, Position, Active: Integer;
  Delta: TBookDelta;
begin
  Result := 0;
  SetLength(Book, Length(BookTemplate));
  for I := 1 to Iterations do
  begin
    Move(BookTemplate[0], Book[0], Length(Book) * SizeOf(TBookLevel));
    Active := Length(Book);
    for J := 0 to High(BookDeltas) do
    begin
      Delta := BookDeltas[J];
      Position := LowerBoundBook(Book, Active, Delta.PriceE8);
      If (Position >= Active) or (Book[Position].PriceE8 <> Delta.PriceE8) then
        raise EAbort.Create('book delta price is absent');
      If Delta.Reinsert then
      begin
        If Position < Active - 1 then
          Move(Book[Position + 1], Book[Position],
            (Active - Position - 1) * SizeOf(TBookLevel));
        Dec(Active);
        Position := LowerBoundBook(Book, Active, Delta.PriceE8);
        If Position < Active then
          Move(Book[Position], Book[Position + 1],
            (Active - Position) * SizeOf(TBookLevel));
        Book[Position].PriceE8 := Delta.PriceE8;
        Inc(Active);
      end;
      Book[Position].QtyE8 := Delta.QtyE8;
      Result := RotL(Result, 9) xor UInt64(Book[Position].PriceE8) xor
        RotL(UInt64(Book[Position].QtyE8), Position and 63);
    end;
    If Active <> Length(Book) then
      raise EAbort.Create('book delta changed active size');
    Result := Result xor HashBytes(@Book[0],
      Length(Book) * SizeOf(TBookLevel));
  end;
end;

function SweepBook(const Book: TBookLevelArray; TargetQty: Int64;
  Descending: Boolean): UInt64;
var
  I, Step: Integer;
  Take, Left, Cost: Int64;
begin
  If Descending then
  begin
    I := High(Book);
    Step := -1;
  end else
  begin
    I := 0;
    Step := 1;
  end;
  Left := TargetQty;
  Cost := 0;
  while (Left > 0) and (I >= 0) and (I < Length(Book)) do
  begin
    Take := Book[I].QtyE8;
    If Take > Left then
      Take := Left;
    Cost := Cost + (Book[I].PriceE8 div 10000) * (Take div 10000);
    Dec(Left, Take);
    Inc(I, Step);
  end;
  Result := UInt64(Cost) xor RotL(UInt64(TargetQty - Left), 29) xor
    UInt64(UInt32(I));
end;

function CaseBookSweep(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to High(SweepQuantities) do
      Result := RotL(Result, 5) xor SweepBook(BidBook, SweepQuantities[J],
        True) xor RotL(SweepBook(AskBook, SweepQuantities[J], False), 17);
end;

function SortAndDigest(const Source: TInt64Array): UInt64;
var
  Values: TArray<Int64>;
begin
  SetLength(Values, Length(Source));
  Move(Source[0], Values[0], Length(Source) * SizeOf(Int64));
  TArray.Sort<Int64>(Values);
  Result := HashBytes(@Values[0], Length(Values) * SizeOf(Int64));
end;

function CaseSortMixed(Iterations: Integer): UInt64;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    Result := Result xor SortAndDigest(SortRandom);
    Result := RotL(Result, 11) xor SortAndDigest(SortAscending);
    Result := RotL(Result, 11) xor SortAndDigest(SortDescending);
    Result := RotL(Result, 11) xor SortAndDigest(SortDuplicates);
  end;
end;

{ ---------------- concentrated server hot paths ---------------- }

function ProcessRequests(Iterations: Integer): UInt64;
const
  OffsetBasis = UInt64($CBF29CE484222325);
  Prime = UInt64($00000100000001B3);
var
  States: TSessionStateArray;
  Header: TWireHeader;
  P: PAnsiChar;
  Payload: PByte;
  PayloadHash: UInt64;
  I, J, StateIndex: Integer;
  Response: PWireResponse;
begin
  Result := 0;
  SetLength(States, Length(SessionsTemplate));
  for I := 1 to Iterations do
  begin
    Move(SessionsTemplate[0], States[0],
      Length(States) * SizeOf(TSessionState));
    P := pointer(RequestBuffer);
    for J := 0 to RequestCount - 1 do
    begin
      Move(P^, Header, SizeOf(Header));
      Inc(P, SizeOf(Header));
      Payload := pointer(P);
      PayloadHash := OffsetBasis;
      while Payload < PByte(P + Header.PayloadSize) do
      begin
        PayloadHash := (PayloadHash xor Payload^) * Prime;
        Inc(Payload);
      end;
      Inc(P, Header.PayloadSize);
      If not SessionIndex.TryGetValue(Header.SessionId, StateIndex) then
        raise EAbort.Create('request session is absent');
      Response := @Responses[J];
      Response^.SessionId := Header.SessionId;
      Response^.Sequence := Header.Sequence;
      Response^.PayloadHash := PayloadHash;
      If Header.Sequence > States[StateIndex].LastSequence then
      begin
        States[StateIndex].LastSequence := Header.Sequence;
        Inc(States[StateIndex].Accepted);
        States[StateIndex].RollingHash :=
          RotL(States[StateIndex].RollingHash, 7) xor PayloadHash;
        Response^.Status := 1;
      end else
        Response^.Status := 0;
    end;
    Result := Result xor HashBytes(@Responses[0],
      Length(Responses) * SizeOf(TWireResponse));
    Result := Result xor HashBytes(@States[0],
      Length(States) * SizeOf(TSessionState));
  end;
end;

procedure SiftDownTimer(var Heap: TTimerEventArray; Root, Count: Integer);
var
  Child: Integer;
  Value: TTimerEvent;
begin
  Value := Heap[Root];
  while Root < Count shr 1 do
  begin
    Child := Root * 2 + 1;
    If (Child + 1 < Count) and
       (Heap[Child + 1].Deadline < Heap[Child].Deadline) then
      Inc(Child);
    If Value.Deadline <= Heap[Child].Deadline then
      Break;
    Heap[Root] := Heap[Child];
    Root := Child;
  end;
  Heap[Root] := Value;
end;

function ProcessTimers(Iterations: Integer): UInt64;
var
  Heap: TTimerEventArray;
  Event: TTimerEvent;
  I, J: Integer;
begin
  Result := 0;
  SetLength(Heap, Length(TimerTemplate));
  for I := 1 to Iterations do
  begin
    Move(TimerTemplate[0], Heap[0], Length(Heap) * SizeOf(TTimerEvent));
    for J := 0 to TimerOperationCount - 1 do
    begin
      Event := Heap[0];
      Result := RotL(Result, 7) xor Event.Deadline xor
        RotL(Event.Token, 23);
      Event.Deadline := Event.Deadline + 100000 + (Event.Token and $3fff);
      Heap[0] := Event;
      SiftDownTimer(Heap, 0, Length(Heap));
    end;
    Result := Result xor HashBytes(@Heap[0],
      Length(Heap) * SizeOf(TTimerEvent));
  end;
end;

{ ---------------- cases ---------------- }

function CaseGenerateFormatSmall(Iterations: Integer): UInt64;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    Result := Result + JsonDigest(BuildInfoFormat(SmallDescriptors));
  Result := Result xor JsonProofSmall;
end;

function CaseGenerateFormatLarge(Iterations: Integer): UInt64;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    Result := Result + JsonDigest(BuildInfoFormat(LargeDescriptors));
  Result := Result xor JsonProofLarge;
end;

function CaseGenerateMormotSmall(Iterations: Integer): UInt64;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    Result := Result + JsonDigest(BuildInfoMormot(SmallDescriptors));
  Result := Result xor JsonProofSmall;
end;

function CaseGenerateMormotLarge(Iterations: Integer): UInt64;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    Result := Result + JsonDigest(BuildInfoMormot(LargeDescriptors));
  Result := Result xor JsonProofLarge;
end;

function ParseCase(const Json: RawUtf8; Iterations: Integer): UInt64;
var
  I: Integer;
  Markets: TMarketList;
  Index: TSymbolIndex;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    Markets := TMarketList.Create(True);
    Index := TSymbolIndex.Create;
    try
      ParseMarkets(Json, Markets, Index);
      Result := Result + MarketsDigest(Markets, Index);
    finally
      Index.Free;
      Markets.Free;
    end;
  end;
end;

function CaseParseSmall(Iterations: Integer): UInt64;
begin
  Result := ParseCase(InfoJsonSmall, Iterations) xor MarketsProofSmall;
end;

function CaseParseLarge(Iterations: Integer): UInt64;
begin
  Result := ParseCase(InfoJsonLarge, Iterations) xor MarketsProofLarge;
end;

function CaseScanSmall(Iterations: Integer): UInt64;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    Result := Result + ScanTrades(TradeBufferSmall, IndexSmall, True);
end;

function CaseScanLarge(Iterations: Integer): UInt64;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    Result := Result + ScanTrades(TradeBufferLarge, IndexLarge, True);
end;

function CaseAggregateSmall(Iterations: Integer): UInt64;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    Result := Result + AggregateMarkets(PreparedSmall);
end;

function CaseAggregateLarge(Iterations: Integer): UInt64;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    Result := Result + AggregateMarkets(PreparedLarge);
end;

function CaseSpectrum(Iterations: Integer): UInt64;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    Result := Result + SpectrumDigest(PreparedSmall);
end;

function CaseCorrelation(Iterations: Integer): UInt64;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    Result := Result + CorrelationDigest(PreparedSmall);
end;

function CaseRankLarge(Iterations: Integer): UInt64;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    Result := Result + RankDigest(UnsortedOrderLarge, ComparerLarge);
end;

function CaseReport(Iterations: Integer): UInt64;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    Result := Result + ReportDigest(PreparedSmall, TopSmall);
end;

function CaseEndToEnd(Iterations: Integer): UInt64;
var
  I, K: Integer;
  Markets: TMarketList;
  Index: TSymbolIndex;
  Comparer: IComparer<Integer>;
  Order: TArray<Integer>;
  Top: array of Integer;
  IterationDigest: UInt64;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    Markets := TMarketList.Create(True);
    Index := TSymbolIndex.Create;
    try
      ParseMarkets(InfoJsonSmall, Markets, Index);
      IterationDigest := MarketsDigest(Markets, Index);
      IterationDigest := IterationDigest xor
        ScanTrades(TradeBufferSmall, Index, False);
      IterationDigest := IterationDigest xor AggregateMarkets(Markets);
      SetLength(Order, Markets.Count);
      for K := 0 to Markets.Count - 1 do
        Order[K] := K;
      Comparer := TTurnoverComparer.Create(Markets);
      TArray.Sort<Integer>(Order, Comparer);
      SetLength(Top, TopCount);
      Move(Order[0], Top[0], TopCount * SizeOf(Integer));
      IterationDigest := IterationDigest xor ReportDigest(Markets, Top);
      Result := Result + IterationDigest;
    finally
      Index.Free;
      Markets.Free;
    end;
  end;
end;

{ ---------------- data preparation ---------------- }

procedure InitializeHotPathData;
const
  FirstSessionId = UInt64($4D4F4F4E00000000);
var
  Header: TWireHeader;
  Seed, SessionId: UInt64;
  P: PAnsiChar;
  I, J, PayloadSize, TotalSize, BookIndex: Integer;
  BeforeDigest, AfterDigest: UInt64;
begin
  SetLength(BookTemplate, BookLevels);
  SetLength(BidBook, BookLevels);
  SetLength(AskBook, BookLevels);
  for I := 0 to BookLevels - 1 do
  begin
    BookTemplate[I].PriceE8 := 1000000000000 + Int64(I) * 100000;
    BookTemplate[I].QtyE8 := 1000000 + Int64(I mod 97) * 10000;
    BidBook[I].PriceE8 := 999000000000 + Int64(I) * 100000;
    BidBook[I].QtyE8 := 500000 + Int64(I mod 113) * 10000;
    AskBook[I].PriceE8 := 1001000000000 + Int64(I) * 100000;
    AskBook[I].QtyE8 := 500000 + Int64(I mod 127) * 10000;
  end;

  SetLength(BookDeltas, BookDeltaCount);
  Seed := UInt64($B00CDA7A12345679);
  for I := 0 to High(BookDeltas) do
  begin
    BookIndex := Integer(NextRandom(Seed) mod BookLevels);
    BookDeltas[I].PriceE8 := BookTemplate[BookIndex].PriceE8;
    BookDeltas[I].QtyE8 := 250000 +
      Int64(NextRandom(Seed) mod 10000000);
    BookDeltas[I].Reinsert := (I and 63) = 63;
  end;

  SetLength(SweepQuantities, BookSweepCount);
  for I := 0 to High(SweepQuantities) do
    SweepQuantities[I] := 500000 + Int64(I mod 47) * 150000;

  SetLength(SortRandom, SortItemCount);
  SetLength(SortAscending, SortItemCount);
  SetLength(SortDescending, SortItemCount);
  SetLength(SortDuplicates, SortItemCount);
  Seed := UInt64($507771A5D15EA5E5);
  for I := 0 to SortItemCount - 1 do
  begin
    SortRandom[I] := Int64(NextRandom(Seed));
    SortAscending[I] := I;
    SortDescending[I] := SortItemCount - I;
    SortDuplicates[I] := Int64(NextRandom(Seed) and 31);
  end;

  SetLength(SessionsTemplate, SessionCount);
  SessionIndex := TSessionIndex.Create(SessionCount);
  for I := 0 to SessionCount - 1 do
    SessionIndex.Add(FirstSessionId + UInt64(I), I);
  SetLength(Responses, RequestCount);
  TotalSize := 0;
  for I := 0 to RequestCount - 1 do
    Inc(TotalSize, SizeOf(TWireHeader) + 8 + (I mod 57));
  SetLength(RequestBuffer, TotalSize);
  P := pointer(RequestBuffer);
  Seed := UInt64($5E5510C0CAC4E001);
  for I := 0 to RequestCount - 1 do
  begin
    SessionId := FirstSessionId + UInt64(I mod SessionCount);
    Header.SessionId := SessionId;
    Header.Sequence := UInt32(I div SessionCount + 1);
    Header.PayloadSize := 8 + I mod 57;
    Header.Opcode := Byte(1 + I mod 7);
    Header.Flags := Byte((I shr 3) and 3);
    Move(Header, P^, SizeOf(Header));
    Inc(P, SizeOf(Header));
    PayloadSize := Header.PayloadSize;
    for J := 0 to PayloadSize - 1 do
      P[J] := AnsiChar(Byte(NextRandom(Seed)));
    Inc(P, PayloadSize);
  end;
  If P <> PAnsiChar(pointer(RequestBuffer)) + Length(RequestBuffer) then
    raise EAbort.Create('request buffer size mismatch');

  SetLength(TimerTemplate, TimerCount);
  for I := 0 to TimerCount - 1 do
  begin
    TimerTemplate[I].Deadline := UInt64(1000000 + I * 100);
    TimerTemplate[I].Token := UInt64(I + 1) * UInt64($9E3779B97F4A7C15);
  end;

  BeforeDigest := RunBookDeltas(1);
  AfterDigest := RunBookDeltas(1);
  If BeforeDigest <> AfterDigest then
    raise EAbort.Create('book delta path is not deterministic');
  If (CaseBookSweep(1) = 0) or (CaseSortMixed(1) = 0) then
    raise EAbort.Create('trading hot path proof is empty');
  BeforeDigest := ProcessRequests(1);
  AfterDigest := ProcessRequests(1);
  If BeforeDigest <> AfterDigest then
    raise EAbort.Create('request path is not deterministic');
  BeforeDigest := ProcessTimers(1);
  AfterDigest := ProcessTimers(1);
  If BeforeDigest <> AfterDigest then
    raise EAbort.Create('timer path is not deterministic');
end;

procedure BuildPrepared(const Json: RawUtf8; const Buffer: RawByteString;
  out Markets: TMarketList; out Index: TSymbolIndex);
begin
  Markets := TMarketList.Create(True);
  Index := TSymbolIndex.Create;
  ParseMarkets(Json, Markets, Index);
  ScanTrades(Buffer, Index, False);
  AggregateMarkets(Markets);
end;

procedure InitializeData;
var
  MormotJson: RawUtf8;
  I, Swap, K: Integer;
  Seed: UInt64;
  Order: TArray<Integer>;
  ComparerSmall: IComparer<Integer>;
begin
  If SizeOf(TTradeSim) <> 16 then
    raise EAbort.Create('TTradeSim must stay 16 bytes');
  SmallDescriptors := BuildDescriptors(SmallMarkets);
  LargeDescriptors := BuildDescriptors(LargeMarkets);

  InfoJsonSmall := BuildInfoFormat(SmallDescriptors);
  MormotJson := BuildInfoMormot(SmallDescriptors);
  If InfoJsonSmall <> MormotJson then
    raise EAbort.Create('format and mORMot writers disagree (small)');
  InfoJsonLarge := BuildInfoFormat(LargeDescriptors);
  MormotJson := BuildInfoMormot(LargeDescriptors);
  If InfoJsonLarge <> MormotJson then
    raise EAbort.Create('format and mORMot writers disagree (large)');

  TradeBufferSmall := BuildTradeBuffer(SmallDescriptors,
    SmallMessagesPerMarket);
  TradeBufferLarge := BuildTradeBuffer(LargeDescriptors,
    LargeMessagesPerMarket);

  BuildPrepared(InfoJsonSmall, TradeBufferSmall, PreparedSmall, IndexSmall);
  BuildPrepared(InfoJsonLarge, TradeBufferLarge, PreparedLarge, IndexLarge);
  JsonProofSmall := FullRawDigest(InfoJsonSmall);
  JsonProofLarge := FullRawDigest(InfoJsonLarge);
  MarketsProofSmall := FullMarketsDigest(PreparedSmall);
  MarketsProofLarge := FullMarketsDigest(PreparedLarge);
  for I := 0 to FftMarkets - 1 do
    If PreparedSmall[I].RingCount <> RingSize then
      raise EAbort.Create('spectrum ring is not full');
  TotalTradesLarge := 0;
  for I := 0 to PreparedLarge.Count - 1 do
    Inc(TotalTradesLarge, UInt64(PreparedLarge[I].RingCount));

  SetLength(UnsortedOrderLarge, LargeMarkets);
  for I := 0 to LargeMarkets - 1 do
    UnsortedOrderLarge[I] := I;
  Seed := UInt64($BADC0DE5EEDF00D3);
  for I := LargeMarkets - 1 downto 1 do
  begin
    Swap := Integer(NextRandom(Seed) mod UInt64(I + 1));
    K := UnsortedOrderLarge[I];
    UnsortedOrderLarge[I] := UnsortedOrderLarge[Swap];
    UnsortedOrderLarge[Swap] := K;
  end;
  ComparerLarge := TTurnoverComparer.Create(PreparedLarge);

  ComparerSmall := TTurnoverComparer.Create(PreparedSmall);
  SetLength(Order, SmallMarkets);
  for I := 0 to SmallMarkets - 1 do
    Order[I] := I;
  TArray.Sort<Integer>(Order, ComparerSmall);
  SetLength(TopSmall, TopCount);
  Move(Order[0], TopSmall[0], TopCount * SizeOf(Integer));
  InitializeHotPathData;
end;

procedure FinalizeData;
begin
  ComparerLarge := nil;
  SessionIndex.Free;
  IndexLarge.Free;
  IndexSmall.Free;
  PreparedLarge.Free;
  PreparedSmall.Free;
end;

procedure Run;
var
  Profile: TPulseProfile;
  SelectedCase: string;
  Found: Boolean;

  procedure Add(const Name, Layer, Description: string; Proc: TPulseCaseProc;
    Operations: UInt64);
  begin
    PulseRunCase('pulse_heartbeat', Name, Layer, Description, Proc,
      Operations, Profile, SelectedCase, Found);
  end;

begin
  PulseInitialize('pulse_heartbeat', Profile, SelectedCase);
  InitializeData;
  try
    Found := False;
    Add('generate-info-format-100', 'rtl+mm',
      'exchange info JSON, string + Format writer, 100 markets',
      @CaseGenerateFormatSmall, Length(InfoJsonSmall));
    Add('generate-info-format-1000', 'rtl+mm',
      'exchange info JSON, string + Format writer, 1000 markets',
      @CaseGenerateFormatLarge, Length(InfoJsonLarge));
    Add('generate-info-mormot-100', 'mormot-json+mm',
      'exchange info JSON, mORMot DocVariant writer, 100 markets',
      @CaseGenerateMormotSmall, Length(InfoJsonSmall));
    Add('generate-info-mormot-1000', 'mormot-json+mm',
      'exchange info JSON, mORMot DocVariant writer, 1000 markets',
      @CaseGenerateMormotLarge, Length(InfoJsonLarge));
    Add('parse-markets-100', 'mormot-json+rtl+mm',
      'DocVariant parse into market objects + symbol dictionary, 100 markets',
      @CaseParseSmall, Length(InfoJsonSmall));
    Add('parse-markets-1000', 'mormot-json+rtl+mm',
      'DocVariant parse into market objects + symbol dictionary, 1000 markets',
      @CaseParseLarge, Length(InfoJsonLarge));
    Add('trade-scan-100', 'codegen+rtl',
      'byte scan of trade stream + dictionary lookup into rings, 100 markets',
      @CaseScanSmall, UInt64(SmallMarkets) * SmallMessagesPerMarket);
    Add('trade-scan-1000', 'codegen+rtl',
      'byte scan of trade stream + dictionary lookup into rings, 1000 markets',
      @CaseScanLarge, UInt64(LargeMarkets) * LargeMessagesPerMarket);
    Add('aggregate-100', 'codegen+memory',
      'Sum(P*Q)/VWAP/minmax/rolling window over full rings, 100 markets',
      @CaseAggregateSmall, UInt64(SmallMarkets) * RingSize);
    Add('aggregate-1000', 'codegen+memory',
      'Sum(P*Q)/VWAP/minmax/rolling window over rings, 1000 markets',
      @CaseAggregateLarge, TotalTradesLarge);
    Add('spectrum-fft-32x1024', 'codegen+math',
      'radix-2 FFT over ring price series of 32 markets',
      @CaseSpectrum, UInt64(FftMarkets) * FftSize * 10);
    Add('correlation-32x256', 'codegen+math+memory',
      'pairwise Pearson correlation of 32 markets over a 256 price window',
      @CaseCorrelation,
      UInt64(CorrMarkets) * (CorrMarkets - 1) div 2 * CorrWindow);
    Add('rank-1000', 'rtl+mm',
      'TArray.Sort of 1000 market indexes by turnover comparer',
      @CaseRankLarge, LargeMarkets);
    Add('report-top20', 'rtl+mm',
      'Format of a top-20 market text report',
      @CaseReport, TopCount);
    Add('orderbook-delta-4096', 'codegen+rtl+memory',
      'binary-search update with periodic delete/reinsert in a 4096-level book',
      @RunBookDeltas, BookDeltaCount);
    Add('orderbook-sweep-4096', 'codegen+memory',
      'market-order depth walk and fixed-point VWAP cost over both book sides',
      @CaseBookSweep, UInt64(BookSweepCount) * 2);
    Add('sort-int64-4x8192', 'rtl+codegen+mm',
      'TArray.Sort over random, sorted, reverse and duplicate-heavy Int64 data',
      @CaseSortMixed, UInt64(SortItemCount) * 4);
    Add('binary-session-pipeline', 'codegen+rtl+memory',
      'decode frames, session dictionary lookup, state update and response write',
      @ProcessRequests, RequestCount);
    Add('timer-heap-8192', 'codegen+memory',
      'pop, reschedule and sift-down on a preallocated server timer min-heap',
      @ProcessTimers, TimerOperationCount);
    Add('end-to-end-100', 'app',
      'parse + scan + aggregate + rank + report pipeline, 100 markets',
      @CaseEndToEnd, UInt64(SmallMarkets) * SmallMessagesPerMarket);
    PulseFinish('pulse_heartbeat', SelectedCase, Found);
  finally
    FinalizeData;
  end;
end;

begin
  try
    Run;
  except
    on E: Exception do
    begin
      WriteLn(ErrOutput, E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
