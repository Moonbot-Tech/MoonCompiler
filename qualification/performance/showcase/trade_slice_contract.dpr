program trade_slice_contract;
{$mode delphiunicode}
{$H+}
{$codepage utf8}
uses
  {$ifdef UNIX}cthreads,{$endif}
  SysUtils, Generics.Collections, mormot.core.base, JsonReader, JsonReaderScan;
type
  TTrade = record
    Price, Quantity: Double;
    Symbol: TJsonSlice;
  end;
var
  Reader: TJsonReader<TTrade>;
  Trade: TTrade;
  Input, Original, Symbol: RawUtf8;
  Lookup: TDictionary<RawUtf8, UInt64>;
  Value: UInt64;
begin
  Reader := TJsonReader<TTrade>.Create('data');
  Reader.Num('p', 'Price');
  Reader.Num('q', 'Quantity');
  Reader.Slice('s', 'Symbol');
  Symbol := RawUtf8('рынок😀');
  Lookup := TDictionary<RawUtf8, UInt64>.Create(1);
  Lookup.Add(Symbol, 42);
  // T/m and nested metadata are irrelevant to P*Q; they need not be numeric/bool.
  Input := '{"stream":"ignored","data":{"T":{"ignored":[1,"text",null]},"s":"' + Symbol +
    '","m":[true,false],"q":"2.5","p":"12.25","extra":"escaped\\text"}}';
  Original := Copy(Input, 1, MaxInt);
  for var I := 1 to 100 do begin
    If not Reader.Read(Input, Trade) then raise Exception.Create('Valid trade rejected');
    If (Trade.Price * Trade.Quantity <> 30.625) or (Trade.Symbol.Len <> Length(Symbol)) then
      raise Exception.Create('Wrong projected fields');
    If (PtrUInt(Trade.Symbol.Text) < PtrUInt(Pointer(Input))) or
       (PtrUInt(Trade.Symbol.Text) + PtrUInt(Trade.Symbol.Len) > PtrUInt(Pointer(Input)) + PtrUInt(Length(Input))) then
      raise Exception.Create('Symbol is not a view into the input');
    If not Lookup.TryGetValueUtf8(Trade.Symbol.Text, Trade.Symbol.Len, Value) or (Value <> 42) then
      raise Exception.Create('UTF8 symbol lookup failed');
    If Input <> Original then raise Exception.Create('Parser mutated input');
  end;
  // Selected strings must be direct UTF8, not JSON escape sequences. Both the
  // Moon Slice and Rust borrowed &str modes deliberately enforce this contract.
  If Reader.Read('{"data":{"s":"\u0041","p":"1","q":"2"}}', Trade) then
    raise Exception.Create('Escaped symbol unexpectedly accepted');
  If Reader.Read('{"data":{"s":"A","p":"1"}}', Trade) then
    raise Exception.Create('Missing required quantity accepted');
  If Reader.Read('{"data":{"s":"A","p":"1","q":"2"}', Trade) then
    raise Exception.Create('Truncated input accepted');
  Lookup.Free;
  Reader.Free;
  Writeln('TRADE_SLICE_CONTRACT_PASS');
end.
