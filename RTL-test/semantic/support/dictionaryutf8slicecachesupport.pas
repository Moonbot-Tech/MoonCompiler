unit DictionaryUtf8SliceCacheSupport;

{$mode delphiunicode}

interface

uses Generics.Collections;

type
  TSliceCacheValue = record Number, Witness: UInt64; end;
  TSliceCacheMap = TDictionary<UTF8String, TSliceCacheValue>;

function MakeSliceCacheMap: TSliceCacheMap;
function LookupFromSliceCacheUnit(Map: TSliceCacheMap; Text: PAnsiChar; Len: SizeInt;
  var Value: TSliceCacheValue): Boolean;

implementation

function MakeSliceCacheMap: TSliceCacheMap;
var Value: TSliceCacheValue;
begin
  Result := TSliceCacheMap.Create;
  Value.Number := 123456789;
  Value.Witness := 987654321;
  Result.Add('cache-key', Value);
end;

function LookupFromSliceCacheUnit(Map: TSliceCacheMap; Text: PAnsiChar; Len: SizeInt;
  var Value: TSliceCacheValue): Boolean;
begin
  Result := Map.TryGetValueUtf8(Text, Len, Value);
end;

end.
