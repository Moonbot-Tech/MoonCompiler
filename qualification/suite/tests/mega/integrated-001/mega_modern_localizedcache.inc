{$ifdef BREADTH_HAS_PRODUCT_IO}
{ A normalized label retrieves its route while a distinct suffix keeps its own entry. }

procedure RunBreadthLocalizedRouteCache;
const
  Original: UnicodeString = 'Ticker-' + #$0416 + #0 + 'West';
  AliasText: UnicodeString = 'TICKER-' + #$0436 + #0 + 'WEST';
  Other: UnicodeString = 'ticker-' + #$0436 + #0 + 'east';
  Expected: UnicodeString = 'ticker-' + #$0436 + #0 + 'west';
var
  Cache: TDictionary<string, Int64>;
  Key, AliasKey: string;
  ID: Int64;
begin
  Key := TCharacter.ToLower(Original);
  AliasKey := TCharacter.ToLower(AliasText);
  Check((Key = Expected) and (AliasKey = Expected), 'breadth-localized-cache-normalizes-cyrillic-and-tail-after-nul');
  Cache := TDictionary<string, Int64>.Create;
  try
    Cache.Add(Key, OpaqueI(9007199254740993));
    Cache.Add(Other, OpaqueI(-870000000079));
    Check(Cache.TryGetValue(AliasKey, ID) and (ID = 9007199254740993),
      'breadth-localized-cache-finds-wide-id-through-alias');
    Cache.AddOrSetValue(AliasKey, OpaqueI(9007199254740995));
    Check((Cache.Count = 2) and (Cache[Key] = 9007199254740995), 'breadth-localized-cache-update-reuses-existing-key');
    Check(Cache[Other] = -870000000079, 'breadth-localized-cache-distinguishes-same-prefix-and-different-tail');
    Mix(UInt64(Cache[Key]));
  finally
    Cache.Free;
  end;
end;
{$endif}
