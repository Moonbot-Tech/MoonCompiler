program showcase_moon;

{$mode delphiunicode}
{$H+}
{$R-}
{$Q-}

uses
  cthreads, SysUtils, Classes, Generics.Collections,
  mormot.core.base, mormot.core.text, mormot.core.unicode, mormot.core.json,
  JsonReader, JsonReaderScan, JsonHelpers;

const
  ClockMonotonic = 1;
  ClockProcessCpu = 2;
  InitialEntries = 100000;
  KeySpace = 111111;

type
  TTimespec = record
    Seconds: Int64;
    Nanoseconds: Int64;
  end;

  TMarket = class
    Price: Double;
    Volume: Double;
    Count: Int64;
  end;

  TTrade = record
    Price: Double;
    Quantity: Double;
    Symbol: TJsonSlice;
  end;

  TSample = record
    Price: Double;
    Quantity: Double;
    Time: Int64;
    Side: Integer;
  end;

  TTimerItem = record
    Deadline: UInt64;
    Token: UInt64;
  end;

  TReply = record
    Price: Double;
    Volume: Double;
  end;

function clock_gettime(Id: LongInt; var Time: TTimespec): LongInt; cdecl; external 'c';

function ClockNs(Id: Integer): Int64;
var
  Time: TTimespec;
begin
  If clock_gettime(Id, Time) <> 0 then raise Exception.Create('clock_gettime failed');
  Result := Time.Seconds * 1000000000 + Time.Nanoseconds;
end;

function ResidentBytes(const Field: string): Int64;
var
  Lines: TStringList;
  Value: string;
  Space: Integer;
begin
  Lines := TStringList.Create;
  Result := -1;
  Lines.LoadFromFile('/proc/self/status');
  for var Line in Lines do begin
    If Pos(Field, Line) <> 1 then Continue;
    Value := Trim(Copy(Line, Length(Field) + 1, MaxInt));
    Space := Pos(' ', Value);
    If Space > 0 then Value := Copy(Value, 1, Space - 1);
    Result := StrToInt64(Value) * 1024;
    Break;
  end;
  Lines.Free;
  If Result < 0 then raise Exception.Create('Missing memory statistic: ' + Field);
end;

function ReadBytes(const FileName: string): RawUtf8;
var
  Stream: TFileStream;
begin
  Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  SetLength(Result, Stream.Size);
  If Length(Result) > 0 then Stream.ReadBuffer(Pointer(Result)^, Length(Result));
  Stream.Free;
end;

procedure WriteBytes(const FileName: string; const Bytes: RawUtf8);
var
  Stream: TFileStream;
begin
  Stream := TFileStream.Create(FileName, fmCreate);
  If Length(Bytes) > 0 then Stream.WriteBuffer(Pointer(Bytes)^, Length(Bytes));
  Stream.Free;
end;

function ReadLines(const FileName: string): TArray<RawUtf8>;
var
  Text: RawUtf8;
  Start, Count, LineIndex, LineLength: Integer;
begin
  Text := ReadBytes(FileName);
  Count := 0;
  for var Index := 1 to Length(Text) do
    If Text[Index] = #10 then Inc(Count);
  If (Length(Text) > 0) and (Text[Length(Text)] <> #10) then Inc(Count);
  SetLength(Result, Count);
  Start := 1;
  LineIndex := 0;
  for var Index := 1 to Length(Text) do begin
    If Text[Index] <> #10 then Continue;
    LineLength := Index - Start;
    If (LineLength > 0) and (Text[Index - 1] = #13) then Dec(LineLength);
    Result[LineIndex] := Copy(Text, Start, LineLength);
    Inc(LineIndex);
    Start := Index + 1;
  end;
  If Start <= Length(Text) then Result[LineIndex] := Copy(Text, Start, MaxInt);
end;

procedure WriteJsonValue(Writer: TJsonWriter; const Value: TJsonValue);
var
  Text: RawUtf8;
  Number: Double;
  IntegerValue: Int64;
  BooleanValue, First: Boolean;
begin
  case Value.Kind of
    jkNull: Writer.AddShort('null');
    jkBoolean: begin
      Value.TryBool(BooleanValue);
      If BooleanValue then Writer.AddShort('true') else Writer.AddShort('false');
    end;
    jkInt64: begin
      Value.TryI64(IntegerValue);
      Writer.Add(IntegerValue);
    end;
    jkDouble: begin
      Value.TryNum(Number);
      Writer.AddDouble(Number);
    end;
    jkString: begin
      Value.TryStr(Text);
      Writer.Add('"');
      Writer.AddJsonEscape(Pointer(Text), Length(Text));
      Writer.Add('"');
    end;
    jkArray, jkObject: begin
      If Value.Kind = jkArray then Writer.Add('[') else Writer.Add('{');
      First := True;
      for var Child in Value.Items do begin
        If not First then Writer.Add(',');
        First := False;
        If Value.Kind = jkObject then begin
          Text := Child.Name;
          Writer.Add('"');
          Writer.AddJsonEscape(Pointer(Text), Length(Text));
          Writer.AddShort('":');
        end;
        WriteJsonValue(Writer, Child);
      end;
      If Value.Kind = jkArray then Writer.Add(']') else Writer.Add('}');
    end;
    else raise Exception.Create('Missing document node');
  end;
end;

procedure Report(const Mode: string; Wall, Cpu, Operations: Int64; const Extra: string);
begin
  Writeln('{"case":"', Mode, '","wall_ns":', Wall, ',"cpu_ns":', Cpu,
    ',"operations":', Operations, ',"peak_rss":', ResidentBytes('VmHWM:'), Extra, '}');
end;

procedure RunExchange(const Directory, OutputName: string);
var
  CpuStart, WallStart, Wall, Cpu: Int64;
  Baseline, InputRss, RetainedRss, InputBytes, Names, Filters, Count: Int64;
  Text, Symbol, Json: RawUtf8;
  Document: TJsonDocument;
  Writer: TJsonWriter;
begin
  Baseline := ResidentBytes('VmRSS:');
  Text := ReadBytes(Directory + '/exchangeInfo.json');
  InputBytes := Length(Text);
  InputRss := ResidentBytes('VmRSS:');
  Document := TJsonDocument.Create;
  CpuStart := ClockNs(ClockProcessCpu);
  WallStart := ClockNs(ClockMonotonic);
  If not Document.ParseOwned(Text) then raise Exception.Create('Exchange parse failed');
  Names := 0;
  Filters := 0;
  Count := 0;
  for var Item in Document.Root.Get('symbols').Objects do begin
    Item.LoadStr('symbol', Symbol);
    Inc(Names, Length(Symbol));
    Inc(Filters, Item.Get('filters').Count);
    Inc(Count);
  end;
  Wall := ClockNs(ClockMonotonic) - WallStart;
  Cpu := ClockNs(ClockProcessCpu) - CpuStart;

  // ParseOwned retains the source needed by every document view.
  RetainedRss := ResidentBytes('VmRSS:');
  Report('exchange', Wall, Cpu, Count, ',"count":' + IntToStr(Count) + ',"names":' + IntToStr(Names) +
    ',"filters":' + IntToStr(Filters) + ',"input_bytes":' + IntToStr(InputBytes) +
    ',"baseline_rss":' + IntToStr(Baseline) + ',"input_rss":' + IntToStr(InputRss) +
    ',"retained_rss":' + IntToStr(RetainedRss) + ',"index_bytes":' + IntToStr(Document.IndexBytes));
  If OutputName <> '' then begin
    Writer := TJsonWriter.CreateOwnedStream;
    WriteJsonValue(Writer, Document.Root);
    Writer.SetText(Json);
    WriteBytes(OutputName, Json);
    Writer.Free;
  end;
  Document.Free;
end;

procedure RunTrades(const Directory, OutputName: string; Passes: Integer);
var
  CpuStart, WallStart, Wall, Cpu: Int64;
  Symbols, Lines: TArray<RawUtf8>;
  Markets: TDictionary<RawUtf8, TMarket>;
  MarketObjects: TObjectList<TMarket>;
  Market: TMarket;
  Reader: TJsonReader<TTrade>;
  Trade: TTrade;
  Output: TextFile;
begin
  Symbols := ReadLines(Directory + '/symbols.txt');
  Lines := ReadLines(Directory + '/trades.jsonl');
  Reader := TJsonReader<TTrade>.Create('data');
  Reader.Num('p', 'Price');
  Reader.Num('q', 'Quantity');
  Reader.Slice('s', 'Symbol');

  CpuStart := ClockNs(ClockProcessCpu);
  WallStart := ClockNs(ClockMonotonic);
  Markets := TDictionary<RawUtf8, TMarket>.Create(Length(Symbols));
  MarketObjects := TObjectList<TMarket>.Create(True);
  MarketObjects.Capacity := Length(Symbols);
  for var SymbolIndex := 0 to High(Symbols) do begin
    Market := TMarket.Create;
    MarketObjects.Add(Market);
    Markets.Add(Symbols[SymbolIndex], Market);
  end;
  for var Pass := 1 to Passes do begin
    for var Index := 0 to High(Lines) do begin
      If not Reader.Read(Lines[Index], Trade) or (Trade.Price <= 0) or
         (Trade.Quantity <= 0) then
        raise Exception.Create('Trade parse failed');
      If not Markets.TryGetValueUtf8(Trade.Symbol.Text, Trade.Symbol.Len, Market) then
        raise Exception.Create('Unknown symbol at ' + IntToStr(Index));
      Market.Price := Trade.Price;
      Market.Volume := Market.Volume + Trade.Price * Trade.Quantity;
      Inc(Market.Count);
    end;
  end;
  Wall := ClockNs(ClockMonotonic) - WallStart;
  Cpu := ClockNs(ClockProcessCpu) - CpuStart;

  If OutputName <> '' then begin
    AssignFile(Output, OutputName);
    Rewrite(Output);
    for var SymbolIndex := 0 to High(Symbols) do begin
      Market := MarketObjects[SymbolIndex];
      Writeln(Output, Symbols[SymbolIndex], #9, Market.Count, #9, Market.Price:0:17, #9, Market.Volume:0:17);
    end;
    CloseFile(Output);
  end;
  Report('trades', Wall, Cpu, Int64(Length(Lines)) * Passes,
    ',"count":' + IntToStr(Markets.Count));
  Markets.Free;
  MarketObjects.Free;
  Reader.Free;
end;

procedure RunSerialization(const Directory, OutputName: string; Passes: Integer);
var
  CpuStart, WallStart, Wall, Cpu: Int64;
  Symbols: TArray<RawUtf8>;
  Replies: TArray<TReply>;
  Writer: TJsonWriter;
  Json: RawUtf8;
  TotalBytes: Int64;
begin
  Symbols := ReadLines(Directory + '/symbols.txt');
  SetLength(Replies, Length(Symbols));
  for var Index := 0 to High(Replies) do begin
    Replies[Index].Price := (Index + 1) / 64;
    Replies[Index].Volume := (Index + 1) / 128;
  end;
  TotalBytes := 0;

  CpuStart := ClockNs(ClockProcessCpu);
  WallStart := ClockNs(ClockMonotonic);
  for var Pass := 1 to Passes do begin
    Writer := TJsonWriter.CreateOwnedStream;
    Writer.Add('[');
    for var Index := 0 to High(Symbols) do begin
      If Index <> 0 then Writer.Add(',');
      Writer.AddShort('{"symbol":"');
      Writer.AddJsonEscape(Pointer(Symbols[Index]), Length(Symbols[Index]));
      Writer.AddShort('","status":"TRADING","price":');
      Writer.AddDouble(Replies[Index].Price);
      Writer.AddShort(',"volume":');
      Writer.AddDouble(Replies[Index].Volume);
      Writer.AddShort(',"note":"');
      Writer.AddJsonEscape(PAnsiChar('market "ready"'#10));
      Writer.Add('"');
      Writer.Add('}');
    end;
    Writer.Add(']');
    Writer.SetText(Json);
    Inc(TotalBytes, Length(Json));
    Writer.Free;
  end;
  Wall := ClockNs(ClockMonotonic) - WallStart;
  Cpu := ClockNs(ClockProcessCpu) - CpuStart;

  If OutputName <> '' then WriteBytes(OutputName, Json);
  Report('serialize', Wall, Cpu, Int64(Length(Symbols)) * Passes, ',"bytes":' + IntToStr(TotalBytes));
end;

function MakeSamples: TArray<TSample>;
begin
  SetLength(Result, 262144);
  for var Index := 0 to High(Result) do begin
    Result[Index].Price := (Index mod 10000 + 1) / 64;
    Result[Index].Quantity := (Index mod 100 + 1) / 128;
    Result[Index].Time := Index;
    Result[Index].Side := Index and 1;
  end;
end;

function AnalyzeWindows(const Samples: TArray<TSample>; Passes: Integer): Double;
var
  BuyTurnover, SellTurnover, MaximumPrice, Quantity: Double;
  Price, TradeQuantity, Turnover: Double;
  WindowEnd, WindowLength: Integer;
begin
  Result := 0;
  for var Window := 0 to Passes * 4096 - 1 do begin
    WindowEnd := 512 + ((Int64(Window) * 7919) mod (Length(Samples) - 512));
    WindowLength := 64 + (Window mod 449);
    BuyTurnover := 0;
    SellTurnover := 0;
    MaximumPrice := 0;
    Quantity := 0;
    for var Index := WindowEnd - WindowLength to WindowEnd - 1 do begin
      Price := Samples[Index].Price;
      TradeQuantity := Samples[Index].Quantity;
      Turnover := Price * TradeQuantity;
      If Samples[Index].Side = 0 then begin
        BuyTurnover := BuyTurnover + Turnover;
      end else begin
        SellTurnover := SellTurnover + Turnover;
      end;
      If Price > MaximumPrice then MaximumPrice := Price;
      Quantity := Quantity + TradeQuantity;
    end;
    Result := Result + (BuyTurnover + SellTurnover + MaximumPrice + (BuyTurnover + SellTurnover) / Quantity);
  end;
end;

procedure RunAnalytics(Passes: Integer);
var
  CpuStart, WallStart, Wall, Cpu: Int64;
  Samples: TArray<TSample>;
  Checksum: Double;
begin
  Samples := MakeSamples;
  CpuStart := ClockNs(ClockProcessCpu);
  WallStart := ClockNs(ClockMonotonic);
  Checksum := AnalyzeWindows(Samples, Passes);
  Wall := ClockNs(ClockMonotonic) - WallStart;
  Cpu := ClockNs(ClockProcessCpu) - CpuStart;
  Report('analytics', Wall, Cpu, Int64(Passes) * 4096, ',"result":' + FloatToStr(Checksum));
end;

procedure ReplaceEarliest(var Heap: TArray<TTimerItem>; const Event: TTimerItem);
var
  Root, Child: Integer;
begin
  Root := 0;
  while Root < Length(Heap) div 2 do begin
    Child := Root * 2 + 1;
    If (Child + 1 < Length(Heap)) and (Heap[Child + 1].Deadline < Heap[Child].Deadline) then Inc(Child);
    If Event.Deadline <= Heap[Child].Deadline then Break;
    Heap[Root] := Heap[Child];
    Root := Child;
  end;
  Heap[Root] := Event;
end;

procedure RunTimers(Passes: Integer);
var
  CpuStart, WallStart, Wall, Cpu: Int64;
  Heap: TArray<TTimerItem>;
  Event: TTimerItem;
  Checksum: UInt64;
begin
  SetLength(Heap, 8192);
  for var Index := 0 to High(Heap) do begin
    Heap[Index].Deadline := Index * 19;
    Heap[Index].Token := Index;
  end;
  Checksum := 0;

  CpuStart := ClockNs(ClockProcessCpu);
  WallStart := ClockNs(ClockMonotonic);
  for var Update := 1 to Passes * 100000 do begin
    Event := Heap[0];
    Checksum := Checksum + Event.Deadline + Event.Token;
    Event.Deadline := Event.Deadline + 100000 + (Event.Token and $3fff);
    ReplaceEarliest(Heap, Event);
  end;
  Wall := ClockNs(ClockMonotonic) - WallStart;
  Cpu := ClockNs(ClockProcessCpu) - CpuStart;
  Report('timers', Wall, Cpu, Int64(Passes) * 100000, ',"checksum":' + UIntToStr(Checksum));
end;

function MakeQueries: TArray<Cardinal>;
var
  State: Cardinal;
begin
  SetLength(Result, 1000000);
  State := 123456789;
  for var Index := 0 to High(Result) do begin
    State := State * 1664525 + 1013904223;
    Result[Index] := State mod KeySpace;
  end;
end;

procedure RunStringLookup(Passes: Integer);
var
  CpuStart, WallStart, Wall, Cpu: Int64;
  Markets: TDictionary<string, UInt64>;
  Keys, QueryKeys: TArray<string>;
  Queries: TArray<Cardinal>;
  Checksum, Value: UInt64;
begin
  Markets := TDictionary<string, UInt64>.Create(InitialEntries);
  SetLength(Keys, InitialEntries);
  for var Index := 0 to High(Keys) do begin
    Keys[Index] := 'MARKET_' + IntToHex(Index, 8);
    Markets.Add(Keys[Index], Index * 17 + 3);
  end;
  Queries := MakeQueries;
  SetLength(QueryKeys, Length(Queries));
  for var Index := 0 to High(Queries) do begin
    If Queries[Index] < Cardinal(Length(Keys)) then begin
      QueryKeys[Index] := Keys[Queries[Index]];
    end else begin
      QueryKeys[Index] := 'MISSING';
    end;
    // Independent storage: hits must compare equal text, not shared pointers.
    UniqueString(QueryKeys[Index]);
  end;
  Checksum := 0;

  CpuStart := ClockNs(ClockProcessCpu);
  WallStart := ClockNs(ClockMonotonic);
  for var Pass := 1 to Passes do
    for var QueryIndex := 0 to High(QueryKeys) do
      If Markets.TryGetValue(QueryKeys[QueryIndex], Value) then Checksum := Checksum + Value;
  Wall := ClockNs(ClockMonotonic) - WallStart;
  Cpu := ClockNs(ClockProcessCpu) - CpuStart;

  Report('dict-string', Wall, Cpu, Int64(Length(Queries)) * Passes,
    ',"checksum":' + UIntToStr(Checksum) + ',"final_checksum":0,"final_count":0');
  Markets.Free;
end;

procedure ValidateIntegerMap(Values: TDictionary<UInt64, UInt64>; const Expected: TArray<UInt64>;
  out Checksum, Count: UInt64);
var
  Value: UInt64;
begin
  Checksum := 0;
  Count := 0;
  for var Key := 0 to High(Expected) do begin
    If Expected[Key] = High(UInt64) then begin
      If Values.ContainsKey(Key) then raise Exception.Create('Unexpected dictionary key');
    end else begin
      If not Values.TryGetValue(Key, Value) or (Value <> Expected[Key]) then
        raise Exception.Create('Dictionary final value mismatch');
      Inc(Checksum, Value);
      Inc(Count);
    end;
  end;
  If UInt64(Values.Count) <> Count then raise Exception.Create('Dictionary final count mismatch');
end;

procedure RunIntegerUpdates(Passes: Integer; ReadAfterUpdate: Boolean);
var
  CpuStart, WallStart, Wall, Cpu: Int64;
  Values: TDictionary<UInt64, UInt64>;
  Queries: TArray<Cardinal>;
  Expected: TArray<UInt64>;
  Checksum, FinalChecksum, FinalCount: UInt64;
  Key: Cardinal;
  Mode: string;
begin
  Values := TDictionary<UInt64, UInt64>.Create(InitialEntries);
  for var KeyIndex := 0 to InitialEntries - 1 do Values.Add(KeyIndex, KeyIndex * 17 + 3);
  Queries := MakeQueries;
  SetLength(Expected, KeySpace);
  for var Index := 0 to High(Expected) do Expected[Index] := High(UInt64);
  for var Index := 0 to InitialEntries - 1 do Expected[Index] := Index * 17 + 3;
  for var Index := 0 to High(Queries) do Expected[Queries[Index]] := UInt64(Index) + UInt64(Passes);
  Checksum := 0;

  CpuStart := ClockNs(ClockProcessCpu);
  WallStart := ClockNs(ClockMonotonic);
  If ReadAfterUpdate then begin
    for var Pass := 1 to Passes do begin
      for var Index := 0 to High(Queries) do begin
        Key := Queries[Index];
        Values.AddOrSetValue(Key, UInt64(Index) + UInt64(Pass));
        Checksum := Checksum + Values[Key];
      end;
    end;
  end else begin
    for var Pass := 1 to Passes do
      for var Index := 0 to High(Queries) do Values.AddOrSetValue(Queries[Index], UInt64(Index) + UInt64(Pass));
  end;
  Wall := ClockNs(ClockMonotonic) - WallStart;
  Cpu := ClockNs(ClockProcessCpu) - CpuStart;

  ValidateIntegerMap(Values, Expected, FinalChecksum, FinalCount);
  If ReadAfterUpdate then Mode := 'dict-int-update-read' else Mode := 'dict-int-update';
  Report(Mode, Wall, Cpu, Int64(Length(Queries)) * Passes, ',"checksum":' + UIntToStr(Checksum) +
    ',"final_checksum":' + UIntToStr(FinalChecksum) + ',"final_count":' + UIntToStr(FinalCount));
  Values.Free;
end;

procedure Main;
var
  Mode, InputDirectory, OutputName: string;
  Passes: Integer;
begin
  If (ParamCount < 2) or (ParamCount > 4) then
    raise Exception.Create('Usage: showcase_moon CASE INPUT_DIRECTORY [PASSES [OUTPUT]]');
  Mode := ParamStr(1);
  InputDirectory := ParamStr(2);
  OutputName := ParamStr(4);
  Passes := 1;
  If ParamCount >= 3 then Passes := StrToInt(ParamStr(3));
  If (Passes <= 0) or (Passes > 10000) then raise Exception.Create('PASSES must be between 1 and 10000');
  FormatSettings.DecimalSeparator := '.';

  If Mode = 'exchange' then RunExchange(InputDirectory, OutputName)
  else If Mode = 'trades' then RunTrades(InputDirectory, OutputName, Passes)
  else If Mode = 'serialize' then RunSerialization(InputDirectory, OutputName, Passes)
  else If Mode = 'analytics' then RunAnalytics(Passes)
  else If Mode = 'timers' then RunTimers(Passes)
  else If Mode = 'dict-string' then RunStringLookup(Passes)
  else If Mode = 'dict-int-update' then RunIntegerUpdates(Passes, False)
  else If Mode = 'dict-int-update-read' then RunIntegerUpdates(Passes, True)
  else raise Exception.Create('Unknown case: ' + Mode);
end;

begin
  Main;
end.
