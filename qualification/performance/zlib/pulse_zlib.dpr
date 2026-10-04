program pulse_zlib;

{ Compression on the product's paths.  MoonBot deflates a trade packet of
  MoonStreamer (TTrade records of 16 bytes behind each market's name), the
  candle blob of all markets for MoonProto (TDeepPricePack of 20 bytes) and the
  market history of one coin (trades, candles, prices, liquidations; the
  fastest level), inflates the same forms on the receiving side, and inflates
  every permessage-deflate frame of the exchanges' websockets on one stream,
  zips a market's data into an archive in memory and reads it back.  The
  stream-* and websocket-* cases make those calls of System.ZLib as the product
  makes them, the zip-* cases those of System.Zip; the engine-* cases do one
  piece of that work twice, the same calls through System.ZLib and through
  mormot.lib.z.  Under MoonCompiler mormot.lib.z compresses through System.ZLib
  (MOONCOMPILER_SYSTEM_ZLIB), so both sides are the one zlib of the product;
  built with -uMOONCOMPILER_SYSTEM_ZLIB they compare it with the zlib mORMot
  takes by itself (Win64: its static objects, zlib 1.2.11; Linux: the system
  libz), and System.Zip goes through that one too.  Delphi: its RTL zlib
  behind all of them.

  The data is generated here, alike for every compiler (integers and IEEE
  arithmetic only).  `pulse_zlib info` prints the sizes and the zlib version.
  A digest never depends on the compressed bytes - another zlib may pick other
  matches - only on what was put in and what came out. }

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
  {$if defined(FPC) and defined(UNIX) and not defined(PULSE_DEFAULT_MM)}
  cthreads,
  {$ifend}
  SysUtils,
  Classes,
  pulse_zlib_rtl in 'pulse_zlib_rtl.pas',
  pulse_zlib_mormot in 'pulse_zlib_mormot.pas',
  pulse_zlib_zip in 'pulse_zlib_zip.pas',
  perf_clock in '..\common\perf_clock.pas',
  pulse_process_metrics in '..\common\pulse_process_metrics.pas',
  pulse_harness in '..\common\pulse_harness.pas';

{$I ../common/pulse_program_prefix.inc}

type
  { MoonBot TradeTypes.TTrade }
  TTradeRecord = packed record
    Time: Double;
    Price: Single;
    Qty: Single;
  end;
  { MoonBot MarketsU.TDeepPricePack }
  TCandleRecord = packed record
    MaxP, MinP, Vol: Single;
    Time: Double;
  end;
  { MoonBot MarketsU.TMiniCandle }
  TMiniCandleRecord = packed record
    Time: Double;
    Cnt: Integer;
    MinPrice, MaxPrice, BuyVol, SellVol: Single;
  end;
  { MoonBot MarketsU.THistoricalPrices }
  THistoryPriceRecord = packed record
    Current: Single;
    RealTime: Double;
  end;
  TMessageBounds = array[0..256] of Integer;
  TIntegerArray = array of Integer;
  TWallRecord = packed record
    Price: Double;
    Volume, Share: Single;
  end;

const
  MessageCount = 256;
  BaseTime = 45563.5;          { 2024-09-28 12:00 }
  Millisecond = 1 / 86400000;
  Tickers: array[0..23] of AnsiString = (
    'BTC', 'ETH', 'SOL', 'XRP', 'DOGE', 'ADA', 'AVAX', 'LINK', 'DOT', 'TRX', 'TON', 'SHIB',
    'LTC', 'BCH', 'NEAR', 'UNI', 'APT', 'ARB', 'OP', 'SUI', 'PEPE', 'WIF', 'FIL', 'ATOM');
  { price in units of 1/10000, and the digits after the point on the wire }
  TickerPrices: array[0..23] of Int64 = (
    654321000, 34005000, 1504200, 5812, 1085, 3521, 272000, 115600, 42310, 1560, 55120, 2,
    658200, 3412000, 51230, 72100, 83400, 5710, 16120, 16830, 1, 21500, 38200, 47100);

var
  Seed: UInt64 = $1D3779B97F4A7C15;
  TradesPlain, TradesDeflated, CandlesPlain, CandlesDeflated: TMemoryStream;
  History: TMemoryStream;
  HistoryParts: TIntegerArray;
  { the archive of the zip-read form: History as its one deflated entry }
  HistoryZip: TMemoryStream;
  Messages, Frames: TMemoryStream;
  MessageBounds, FrameBounds: TMessageBounds;
  { the targets of the buffer forms: the uncompressed size and the bound of zlib }
  Target: array of Byte;
  Receive: array of Byte;
  Output: array of Byte;

function NextRandom: UInt64;
begin
  Seed := Seed xor (Seed shr 12);
  Seed := Seed xor (Seed shl 25);
  Seed := Seed xor (Seed shr 27);
  Result := Seed * UInt64($2545F4914F6CDD1D);
end;

function RandomBelow(Limit: Cardinal): Cardinal;
begin
  Result := Cardinal(NextRandom shr 32) mod Limit;
end;

procedure PutText(Stream: TMemoryStream; const Text: AnsiString);
begin
  If Text <> '' then
    Stream.Write(Text[1], Length(Text));
end;

procedure PutWord(Stream: TMemoryStream; Value: Word);
begin
  Stream.Write(Value, SizeOf(Value));
end;

procedure PutInteger(Stream: TMemoryStream; Value: Integer);
begin
  Stream.Write(Value, SizeOf(Value));
end;

function Digits(Value: Int64): AnsiString;
var
  Negative: Boolean;
begin
  Negative := Value < 0;
  If Negative then
    Value := -Value;
  Result := '';
  repeat
    Result := AnsiChar(Ord('0') + Value mod 10) + Result;
    Value := Value div 10;
  until Value = 0;
  If Negative then
    Result := '-' + Result;
end;

{ Value/10^Places with the zeros of Places after the point }
function Decimal(Value: Int64; Places: Integer): AnsiString;
var
  Text: AnsiString;
begin
  Text := Digits(Value);
  while Length(Text) <= Places do
    Text := '0' + Text;
  If Places = 0 then
    Result := Text
  else
    Result := Copy(Text, 1, Length(Text) - Places) + '.' + Copy(Text, Length(Text) - Places + 1, Places);
end;

function MarketName(Index: Integer): AnsiString;
begin
  If Index < Length(Tickers) then
    Result := Tickers[Index]
  else
    Result := AnsiChar(Ord('A') + Index mod 26) + AnsiChar(Ord('A') + (Index div 26) mod 26) +
      AnsiChar(Ord('A') + (Index * 7) mod 26) + Digits(Index mod 10);
end;

function StartPrice(Index: Integer): Double;
begin
  If Index < Length(TickerPrices) then
    Result := TickerPrices[Index] / 10000
  else
    Result := (100 + RandomBelow(90000)) / 1000;
end;

{ one step of a price: a few ticks of 1/10000 of it up or down }
function StepPrice(Price: Double): Double;
var
  Ticks: Integer;
begin
  Ticks := Integer(RandomBelow(9)) - 4;
  Result := Price + Ticks * Price / 10000;
end;

function RandomQty(Price: Double): Single;
var
  Lots: Integer;
begin
  Lots := 1 + Integer(RandomBelow(40));
  If RandomBelow(8) = 0 then
    Lots := Lots * 25;
  Result := Lots * 20 / Price;
  If RandomBelow(2) = 0 then
    Result := -Result;
end;

{ MoonTrades TStreamServerUDP.SendData: per market the name, the futures trades
  behind their count, the spot trades behind theirs }
procedure BuildTrades;
var
  Market, Count, Side, I: Integer;
  Name: AnsiString;
  Price: Double;
  Trade: TTradeRecord;
  Time: Double;
begin
  TradesPlain := TMemoryStream.Create;
  Time := BaseTime;
  for Market := 0 to 15 do begin
    Name := MarketName(Market) + 'USDT';
    PutWord(TradesPlain, Length(Name));
    PutText(TradesPlain, Name);
    Price := StartPrice(Market);
    for Side := 0 to 1 do begin
      If Side = 0 then
        Count := 6 + Integer(RandomBelow(19))
      else
        Count := Integer(RandomBelow(7));
      PutWord(TradesPlain, Count);
      for I := 1 to Count do begin
        Time := Time + RandomBelow(30) * Millisecond;
        Price := StepPrice(Price);
        Trade.Time := Time;
        Trade.Price := Price;
        Trade.Qty := RandomQty(Price);
        TradesPlain.Write(Trade, SizeOf(Trade));
      end;
    end;
  end;
end;

{ MarketsU TMarkets.StoreCandlesToZip: the header, per market the name, the
  5-minute candles behind their count and the two walls }
procedure BuildCandles;
const
  Markets = 360;
  CandlesPerMarket = 144;
var
  Market, I, K: Integer;
  Name: AnsiString;
  WideName: array of Word;
  Price, Range: Double;
  Candle: TCandleRecord;
  Wall: TWallRecord;
  Shift: Double;
  Version: Byte;
begin
  CandlesPlain := TMemoryStream.Create;
  PutInteger(CandlesPlain, 0);
  Version := 2;
  CandlesPlain.Write(Version, 1);
  PutInteger(CandlesPlain, Markets);
  Shift := 180;
  CandlesPlain.Write(Shift, SizeOf(Shift));
  for Market := 0 to Markets - 1 do begin
    Name := MarketName(Market) + 'USDT';
    SetLength(WideName, Length(Name));
    for K := 1 to Length(Name) do
      WideName[K - 1] := Ord(Name[K]);
    PutWord(CandlesPlain, Length(Name));
    CandlesPlain.Write(WideName[0], Length(Name) * 2);
    PutInteger(CandlesPlain, CandlesPerMarket);
    Price := StartPrice(Market);
    for I := 0 to CandlesPerMarket - 1 do begin
      Price := StepPrice(StepPrice(Price));
      Range := Price * (1 + RandomBelow(60)) / 10000;
      Candle.MaxP := Price + Range;
      Candle.MinP := Price - Range;
      Candle.Vol := (1 + RandomBelow(5000)) * 37 / Price;
      Candle.Time := BaseTime - (CandlesPerMarket - 1 - I) * 5 / 1440;
      CandlesPlain.Write(Candle, SizeOf(Candle));
    end;
    for I := 0 to 7 do begin
      Wall.Price := Price * (1 + (Integer(I) - 3) / 100);
      Wall.Volume := (1 + RandomBelow(900)) * 1000 / Price;
      Wall.Share := RandomBelow(100) / 100;
      CandlesPlain.Write(Wall, SizeOf(Wall));
    end;
  end;
end;

{ MoonProtoEngineServer SendMarketHistoryChunked: the version byte, then the
  trades, candles, prices and liquidations of one coin, each behind its count }
procedure BuildHistory;
const
  TradeCount = 12000;
  CandleCount = 1440;
  PriceCount = 7200;
  LiquidationCount = 400;
var
  I, Start: Integer;
  Price, Time: Double;
  Trade: TTradeRecord;
  Candle: TMiniCandleRecord;
  Point: THistoryPriceRecord;
  Version: Byte;

  procedure Part;
  begin
    SetLength(HistoryParts, Length(HistoryParts) + 1);
    HistoryParts[High(HistoryParts)] := Integer(History.Size) - Start;
    Start := History.Size;
  end;

begin
  History := TMemoryStream.Create;
  Start := 0;
  Version := 1;
  History.Write(Version, 1);
  Part;
  PutInteger(History, TradeCount);
  Part;
  Price := StartPrice(1);
  Time := BaseTime - 1 / 24;
  for I := 1 to TradeCount do begin
    Time := Time + RandomBelow(600) * Millisecond;
    Price := StepPrice(Price);
    Trade.Time := Time;
    Trade.Price := Price;
    Trade.Qty := RandomQty(Price);
    History.Write(Trade, SizeOf(Trade));
  end;
  Part;
  PutInteger(History, CandleCount);
  Part;
  for I := 0 to CandleCount - 1 do begin
    Price := StepPrice(Price);
    Candle.Time := BaseTime - (CandleCount - 1 - I) / 1440;
    Candle.Cnt := 20 + Integer(RandomBelow(400));
    Candle.MinPrice := Price * (1 - RandomBelow(30) / 10000);
    Candle.MaxPrice := Price * (1 + RandomBelow(30) / 10000);
    Candle.BuyVol := (1 + RandomBelow(20000)) * 11 / Price;
    Candle.SellVol := (1 + RandomBelow(20000)) * 11 / Price;
    History.Write(Candle, SizeOf(Candle));
  end;
  Part;
  PutInteger(History, PriceCount);
  Part;
  for I := 0 to PriceCount - 1 do begin
    Price := StepPrice(Price);
    Point.Current := Price;
    Point.RealTime := BaseTime - (PriceCount - 1 - I) / 86400 * 12;
    History.Write(Point, SizeOf(Point));
  end;
  Part;
  PutInteger(History, LiquidationCount);
  Part;
  Time := BaseTime - 1 / 24;
  for I := 1 to LiquidationCount do begin
    Time := Time + RandomBelow(9000) * Millisecond;
    Trade.Time := Time;
    Trade.Price := StepPrice(Price);
    Trade.Qty := RandomQty(Price) * 10;
    History.Write(Trade, SizeOf(Trade));
  end;
  Part;
end;

{ the combined aggTrade stream of Binance: one JSON message a frame }
procedure BuildMessages;
const
  Places: array[0..7] of Integer = (2, 2, 3, 4, 5, 4, 2, 3);
var
  I, K, Market: Integer;
  Name, Lower: AnsiString;
  Prices: array[0..7] of Int64;
  EventTime, AggregateId, FirstId: Int64;
  Step: Int64;
begin
  Messages := TMemoryStream.Create;
  for Market := 0 to 7 do
    Prices[Market] := TickerPrices[Market];
  EventTime := 1727524800000;
  AggregateId := 3120000000;
  FirstId := 5540000000;
  for I := 0 to MessageCount - 1 do begin
    MessageBounds[I] := Messages.Size;
    Market := RandomBelow(8);
    Name := MarketName(Market) + 'USDT';
    Lower := Name;
    for K := 1 to Length(Lower) do
      If Lower[K] in ['A'..'Z'] then
        Lower[K] := AnsiChar(Ord(Lower[K]) + 32);
    Step := Prices[Market] div 20000;
    If Step = 0 then
      Step := 1;
    Prices[Market] := Prices[Market] + (Int64(RandomBelow(7)) - 3) * Step;
    Inc(EventTime, RandomBelow(40));
    Inc(AggregateId, 1 + RandomBelow(3));
    Inc(FirstId, 1 + RandomBelow(5));
    PutText(Messages, '{"stream":"' + Lower + '@aggTrade","data":{"e":"aggTrade","E":' + Digits(EventTime) +
      ',"s":"' + Name + '","a":' + Digits(AggregateId) + ',"p":"' +
      Decimal(Prices[Market] div 100, Places[Market]) + '","q":"' +
      Decimal(1 + RandomBelow(250000), 5) + '","f":' + Digits(FirstId) + ',"l":' +
      Digits(FirstId + RandomBelow(4)) + ',"T":' + Digits(EventTime - RandomBelow(3)) + ',"m":');
    If RandomBelow(2) = 0 then
      PutText(Messages, 'true')
    else
      PutText(Messages, 'false');
    PutText(Messages, ',"M":true}}');
  end;
  MessageBounds[MessageCount] := Messages.Size;
end;

function Deflated(Source: TMemoryStream; WindowBits: Integer): TMemoryStream;
var
  Buffer: array of Byte;
  Size: Integer;
begin
  SetLength(Buffer, Source.Size + Source.Size div 16 + 4096);
  Size := RtlDeflateBuffer(Source.Memory, Source.Size, @Buffer[0], Length(Buffer), -1, WindowBits);
  Result := TMemoryStream.Create;
  Result.Write(Buffer[0], Size);
end;

procedure Check(Condition: Boolean; const What: string);
begin
  If not Condition then
    raise EAbort.Create('zlib oracle failed: ' + What);
end;

function SameBytes(A, B: Pointer; Size: Integer): Boolean;
begin
  Result := CompareMem(A, B, Size);
end;

{ the archive of the zip-add form, read back through System.Zip and through the
  zlib of both engines (its one entry is raw deflate behind the local header) }
procedure ZipRoundTrip;
var
  Archive, Back: TMemoryStream;
  Data: PByte;
  Offset, Stored, Size: Integer;
begin
  Archive := TMemoryStream.Create;
  Back := TMemoryStream.Create;
  try
    ZipAddTo(History, Archive);
    ZipReadTo(Archive, Back);
    Check((Back.Size = History.Size) and SameBytes(Back.Memory, History.Memory, History.Size), 'zip');
    Back.Clear;
    ZipReadTo(HistoryZip, Back);
    Check((Back.Size = History.Size) and SameBytes(Back.Memory, History.Memory, History.Size), 'zip prepared');
    Data := Archive.Memory;
    Check((Archive.Size > 30) and (PCardinal(Data)^ = $04034B50) and (PWord(Data + 8)^ = 8), 'zip local header');
    Offset := 30 + PWord(Data + 26)^ + PWord(Data + 28)^;
    Stored := PCardinal(Data + 18)^;
    Check(Offset + Stored <= Archive.Size, 'zip entry size');
    Size := RtlInflateBuffer(Data + Offset, Stored, @Target[0], Length(Target), -15);
    Check((Size = History.Size) and SameBytes(@Target[0], History.Memory, Size), 'zip entry rtl');
    Size := MormotInflateBuffer(Data + Offset, Stored, @Target[0], Length(Target), -15);
    Check((Size = History.Size) and SameBytes(@Target[0], History.Memory, Size), 'zip entry mormot');
  finally
    FreeAndNil(Back);
    FreeAndNil(Archive);
  end;
end;

{ Every form gives back what went in, before anything is measured }
procedure Verify;
var
  Size: Integer;
  Digest: UInt64;

  procedure RoundTrip(Source: TMemoryStream; WindowBits: Integer; const What: string);
  var
    Compressed: array of Byte;
    Squeezed: Integer;
  begin
    SetLength(Compressed, Length(Target));
    Squeezed := RtlDeflateBuffer(Source.Memory, Source.Size, @Compressed[0], Length(Compressed), -1, WindowBits);
    Size := RtlInflateBuffer(@Compressed[0], Squeezed, @Target[0], Length(Target), WindowBits);
    Check((Size = Source.Size) and SameBytes(@Target[0], Source.Memory, Size), What + ' rtl');
    Size := MormotInflateBuffer(@Compressed[0], Squeezed, @Target[0], Length(Target), WindowBits);
    Check((Size = Source.Size) and SameBytes(@Target[0], Source.Memory, Size), What + ' rtl->mormot');
    Squeezed := MormotDeflateBuffer(Source.Memory, Source.Size, @Compressed[0], Length(Compressed), -1, WindowBits);
    Size := RtlInflateBuffer(@Compressed[0], Squeezed, @Target[0], Length(Target), WindowBits);
    Check((Size = Source.Size) and SameBytes(@Target[0], Source.Memory, Size), What + ' mormot->rtl');
  end;

  { the stream forms' own output inflates back to the source, and through the
    decompression stream as well }
  procedure StreamRoundTrip(Source: TMemoryStream; Fastest: Boolean; WindowBits: Integer; const What: string);
  var
    Deflated: TMemoryStream;
  begin
    Deflated := TMemoryStream.Create;
    try
      If Source = History then
        RtlStreamDeflatePartsTo(History.Memory, HistoryParts, Fastest, WindowBits, Deflated)
      else
        RtlStreamDeflateTo(Source, Fastest, WindowBits, Deflated);
      Size := RtlInflateBuffer(Deflated.Memory, Deflated.Size, @Target[0], Length(Target), WindowBits);
      Check((Size = Source.Size) and SameBytes(@Target[0], Source.Memory, Size), What + ' stream deflate');
      Check(RtlStreamInflate(Deflated, WindowBits, Digest) = Source.Size, What + ' stream inflate');
    finally
      FreeAndNil(Deflated);
    end;
  end;

begin
  RoundTrip(TradesPlain, -15, 'trades');
  RoundTrip(CandlesPlain, 15, 'candles');
  RoundTrip(History, -15, 'history');
  StreamRoundTrip(TradesPlain, False, -15, 'trades');
  StreamRoundTrip(CandlesPlain, False, 15, 'candles');
  StreamRoundTrip(History, True, -15, 'history');
  Size := RtlStreamInflate(TradesDeflated, -15, Digest);
  Check(Size = TradesPlain.Size, 'trades stream inflate');
  Size := RtlStreamInflate(CandlesDeflated, 15, Digest);
  Check(Size = CandlesPlain.Size, 'candles stream inflate');
  Size := RtlInflateMessages(Frames.Memory, FrameBounds, @Receive[0], @Output[0], Length(Output), Digest);
  Check(Size = Messages.Size, 'websocket rtl');
  Size := MormotInflateMessages(Frames.Memory, FrameBounds, @Receive[0], @Output[0], Length(Output), Digest);
  Check(Size = Messages.Size, 'websocket mormot');
  ZipRoundTrip;
end;

procedure Prepare;
var
  Largest: Integer;
begin
  BuildTrades;
  BuildCandles;
  BuildHistory;
  BuildMessages;
  TradesDeflated := Deflated(TradesPlain, -15);
  CandlesDeflated := Deflated(CandlesPlain, 15);
  Frames := TMemoryStream.Create;
  RtlDeflateMessages(Messages.Memory, MessageBounds, Frames, FrameBounds);
  HistoryZip := TMemoryStream.Create;
  ZipAddTo(History, HistoryZip);
  Largest := CandlesPlain.Size;
  If History.Size > Largest then
    Largest := History.Size;
  SetLength(Target, Largest + Largest div 16 + 4096);
  SetLength(Receive, 65536);
  SetLength(Output, 65536);
end;

procedure Info;
begin
  WriteLn('PULSE_ZLIB version=', RtlZlibVersion, ' trades=', TradesPlain.Size, '->', TradesDeflated.Size,
    ' candles=', CandlesPlain.Size, '->', CandlesDeflated.Size, ' history=', History.Size, ' parts=',
    Length(HistoryParts), ' zip=', HistoryZip.Size, ' messages=', Messages.Size, '->', Frames.Size, ' frames=',
    MessageCount);
end;

{ ---- the cases: every global read before the loop ---- }

function CaseStreamDeflateTrades(Iterations: Integer): UInt64;
var
  Source: TMemoryStream;
  Size: UInt64;
  I: Integer;
begin
  Source := TradesPlain;
  Size := Source.Size;
  Result := 0;
  for I := 1 to Iterations do
    Result := Result + Size + UInt64(Ord(RtlStreamDeflate(Source, False, -15) > 0));
end;

function CaseStreamInflateTrades(Iterations: Integer): UInt64;
var
  Source: TMemoryStream;
  Digest: UInt64;
  I: Integer;
begin
  Source := TradesDeflated;
  Result := 0;
  for I := 1 to Iterations do begin
    Result := Result + UInt64(RtlStreamInflate(Source, -15, Digest));
    Result := Result xor Digest;
  end;
end;

function CaseStreamDeflateCandles(Iterations: Integer): UInt64;
var
  Source: TMemoryStream;
  Size: UInt64;
  I: Integer;
begin
  Source := CandlesPlain;
  Size := Source.Size;
  Result := 0;
  for I := 1 to Iterations do
    Result := Result + Size + UInt64(Ord(RtlStreamDeflate(Source, False, 15) > 0));
end;

function CaseStreamInflateCandles(Iterations: Integer): UInt64;
var
  Source: TMemoryStream;
  Digest: UInt64;
  I: Integer;
begin
  Source := CandlesDeflated;
  Result := 0;
  for I := 1 to Iterations do begin
    Result := Result + UInt64(RtlStreamInflate(Source, 15, Digest));
    Result := Result xor Digest;
  end;
end;

function CaseStreamDeflateHistory(Iterations: Integer): UInt64;
var
  Data: PByte;
  Parts: TIntegerArray;
  Size: UInt64;
  I: Integer;
begin
  Data := History.Memory;
  Size := History.Size;
  Parts := Copy(HistoryParts);
  Result := 0;
  for I := 1 to Iterations do
    Result := Result + Size + UInt64(Ord(RtlStreamDeflateParts(Data, Parts, True, -15) > 0));
end;

function CaseWebsocketInflate(Iterations: Integer): UInt64;
var
  Data, ReceiveBuffer, OutputBuffer: PByte;
  Bounds: TMessageBounds;
  OutputSize, I: Integer;
  Digest: UInt64;
begin
  Data := Frames.Memory;
  Bounds := FrameBounds;
  ReceiveBuffer := @Receive[0];
  OutputBuffer := @Output[0];
  OutputSize := Length(Output);
  Result := 0;
  for I := 1 to Iterations do begin
    Result := Result + UInt64(RtlInflateMessages(Data, Bounds, ReceiveBuffer, OutputBuffer, OutputSize, Digest));
    Result := Result xor Digest;
  end;
end;

function CaseZipAddHistory(Iterations: Integer): UInt64;
var
  Source: TMemoryStream;
  Size: UInt64;
  I: Integer;
begin
  Source := History;
  Size := Source.Size;
  Result := 0;
  for I := 1 to Iterations do
    Result := Result + Size + UInt64(Ord(ZipAdd(Source) > 0));
end;

function CaseZipReadHistory(Iterations: Integer): UInt64;
var
  Archive: TMemoryStream;
  Digest: UInt64;
  I: Integer;
begin
  Archive := HistoryZip;
  Result := 0;
  for I := 1 to Iterations do begin
    Result := Result + UInt64(ZipRead(Archive, Digest));
    Result := Result xor Digest;
  end;
end;

function EngineDeflate(Mormot: Boolean; Source: TMemoryStream; WindowBits, Iterations: Integer): UInt64;
var
  Data, Buffer: Pointer;
  Size, Capacity, I: Integer;
begin
  Data := Source.Memory;
  Size := Source.Size;
  Buffer := @Target[0];
  Capacity := Length(Target);
  Result := 0;
  If Mormot then
    for I := 1 to Iterations do
      Result := Result + UInt64(Size) + UInt64(Ord(MormotDeflateBuffer(Data, Size, Buffer, Capacity, -1, WindowBits) > 0))
  else
    for I := 1 to Iterations do
      Result := Result + UInt64(Size) + UInt64(Ord(RtlDeflateBuffer(Data, Size, Buffer, Capacity, -1, WindowBits) > 0));
end;

function EngineInflate(Mormot: Boolean; Source: TMemoryStream; WindowBits, Iterations: Integer): UInt64;
var
  Data, Buffer: PByte;
  Size, Capacity, Produced, I: Integer;
begin
  Data := Source.Memory;
  Size := Source.Size;
  Buffer := @Target[0];
  Capacity := Length(Target);
  Result := 0;
  for I := 1 to Iterations do begin
    If Mormot then
      Produced := MormotInflateBuffer(Data, Size, Buffer, Capacity, WindowBits)
    else
      Produced := RtlInflateBuffer(Data, Size, Buffer, Capacity, WindowBits);
    Result := Result + UInt64(Produced) + PByte(Buffer + Produced - 1)^;
  end;
end;

function EngineMessages(Mormot: Boolean; Iterations: Integer): UInt64;
var
  Data, ReceiveBuffer, OutputBuffer: PByte;
  Bounds: TMessageBounds;
  OutputSize, I: Integer;
  Digest: UInt64;
begin
  Data := Frames.Memory;
  Bounds := FrameBounds;
  ReceiveBuffer := @Receive[0];
  OutputBuffer := @Output[0];
  OutputSize := Length(Output);
  Result := 0;
  for I := 1 to Iterations do begin
    If Mormot then
      Result := Result + UInt64(MormotInflateMessages(Data, Bounds, ReceiveBuffer, OutputBuffer, OutputSize, Digest))
    else
      Result := Result + UInt64(RtlInflateMessages(Data, Bounds, ReceiveBuffer, OutputBuffer, OutputSize, Digest));
    Result := Result xor Digest;
  end;
end;

function CaseEngineRtlDeflateTrades(I: Integer): UInt64; begin Result := EngineDeflate(False, TradesPlain, -15, I); end;
function CaseEngineMormotDeflateTrades(I: Integer): UInt64; begin Result := EngineDeflate(True, TradesPlain, -15, I); end;
function CaseEngineRtlDeflateCandles(I: Integer): UInt64; begin Result := EngineDeflate(False, CandlesPlain, 15, I); end;
function CaseEngineMormotDeflateCandles(I: Integer): UInt64; begin Result := EngineDeflate(True, CandlesPlain, 15, I); end;
function CaseEngineRtlInflateCandles(I: Integer): UInt64; begin Result := EngineInflate(False, CandlesDeflated, 15, I); end;
function CaseEngineMormotInflateCandles(I: Integer): UInt64; begin Result := EngineInflate(True, CandlesDeflated, 15, I); end;
function CaseEngineRtlMessages(I: Integer): UInt64; begin Result := EngineMessages(False, I); end;
function CaseEngineMormotMessages(I: Integer): UInt64; begin Result := EngineMessages(True, I); end;

procedure Run;
var
  Profile: TPulseProfile;
  SelectedCase: string;
  Found: Boolean;

  procedure Add(const Name, UnitName: string; Proc: TPulseCaseProc; Operations: UInt64);
  begin
    PulseRunCase('pulse_zlib', Name, 'zlib', UnitName, Proc, Operations, Profile, SelectedCase, Found);
  end;

begin
  Prepare;
  If (ParamCount = 1) and SameText(ParamStr(1), 'info') then begin
    Verify;
    Info;
    Exit;
  end;
  Verify;
  {$ifdef PULSE_PROGRAM_PREFIX}PulseProgramPrefix;{$endif}
  PulseInitialize('pulse_zlib', Profile, SelectedCase);
  Found := False;
  Add('stream-deflate-trades-4k', 'System.ZLib', @CaseStreamDeflateTrades, TradesPlain.Size);
  Add('stream-inflate-trades-4k', 'System.ZLib', @CaseStreamInflateTrades, TradesPlain.Size);
  Add('stream-deflate-candles-1m', 'System.ZLib', @CaseStreamDeflateCandles, CandlesPlain.Size);
  Add('stream-inflate-candles-1m', 'System.ZLib', @CaseStreamInflateCandles, CandlesPlain.Size);
  Add('stream-deflate-history-fastest', 'System.ZLib', @CaseStreamDeflateHistory, History.Size);
  Add('websocket-inflate-256', 'System.ZLib', @CaseWebsocketInflate, MessageCount);
  Add('zip-add-history', 'System.Zip', @CaseZipAddHistory, History.Size);
  Add('zip-read-history', 'System.Zip', @CaseZipReadHistory, History.Size);
  Add('engine-rtl-deflate-trades-4k', 'System.ZLib', @CaseEngineRtlDeflateTrades, TradesPlain.Size);
  Add('engine-mormot-deflate-trades-4k', 'mormot.lib.z', @CaseEngineMormotDeflateTrades, TradesPlain.Size);
  Add('engine-rtl-deflate-candles-1m', 'System.ZLib', @CaseEngineRtlDeflateCandles, CandlesPlain.Size);
  Add('engine-mormot-deflate-candles-1m', 'mormot.lib.z', @CaseEngineMormotDeflateCandles, CandlesPlain.Size);
  Add('engine-rtl-inflate-candles-1m', 'System.ZLib', @CaseEngineRtlInflateCandles, CandlesPlain.Size);
  Add('engine-mormot-inflate-candles-1m', 'mormot.lib.z', @CaseEngineMormotInflateCandles, CandlesPlain.Size);
  Add('engine-rtl-inflate-websocket-256', 'System.ZLib', @CaseEngineRtlMessages, MessageCount);
  Add('engine-mormot-inflate-websocket-256', 'mormot.lib.z', @CaseEngineMormotMessages, MessageCount);
  PulseFinish('pulse_zlib', SelectedCase, Found);
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
