unit SliceFactory;
{$mode delphiunicode}
interface
uses AstraSlice.Collections;
type TForeignMap = TDictionary<UTF8String, Integer>;
function MakeForeign: TForeignMap;
implementation
function MakeForeign: TForeignMap;
begin
  Result := TForeignMap.Create;
  Result.Add('cross-unit', 73);
end;
end.
