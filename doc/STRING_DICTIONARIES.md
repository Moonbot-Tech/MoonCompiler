# String dictionary lookup from a UTF-8 slice

`Generics.Collections` provides `TryGetValueUtf8` on the existing `TDictionary`
and `TObjectDictionary`. Parsers can look up a key directly in their input buffer:

```pascal
procedure ApplyTrade(Markets: TDictionary<UTF8String, TMarket>;
  SymbolStart: PAnsiChar; SymbolBytes: SizeInt; Price, Quantity: Double);
var Market: TMarket;
begin
  // Markets was populated with ordinary owning UTF8String keys.
  // SymbolStart/Bytes identify the decoded UTF-8 symbol in a live input buffer.
  If Markets.TryGetValueUtf8(SymbolStart, SymbolBytes, Market) then
    Market.Volume := Market.Volume + Price * Quantity;
end;
```

The buffer must remain readable and unchanged for the duration of the call.
No terminating zero is required; embedded zeros are part of the key. The method
does not modify or retain the buffer. `(nil, 0)` means an empty key. Negative
lengths and `(nil, nonzero)` raise `EArgumentException`. On a miss the method
returns `False` and assigns `Default(TValue)`, like ordinary `TryGetValue`.

With the standard comparer/hash factory and `UTF8String` or UTF-8-bearing
`RawByteString` keys, lookup hashes and compares the slice directly: no temporary
string, conversion, or allocation. `RawUtf8 = type UTF8String` aliases work too.
Malformed UTF-8 is treated as bytes, just as in ordinary `UTF8String` lookup;
this API is not a validator or a JSON unescaper.

Fixed non-UTF-8 `AnsiString` code pages, `UnicodeString`, `WideString`, custom comparers
and custom hash factories retain their normal lookup semantics by constructing
the appropriately typed query key. Those fallback paths may allocate and
convert. Plain `AnsiString` (declared code page 0) and `RawByteString` retain the
query's UTF-8 bytes and code-page header; the API does not infer encoding from
the caller's source-file code page. `ShortString` and non-string key types raise
`EArgumentException`. Mixing incompatible runtime code pages in a byte-string map retains the
existing dictionary hash/equality behaviour; prefer `UTF8String` for UTF-8 data.

Insertion, removal, notifications, value ownership, key lifetime, copy-on-write,
and `for Pair in Dictionary` use the existing storage and algorithms. No new
container type or change to existing `TryGetValue` calls is required.
