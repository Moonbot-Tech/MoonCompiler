unit mormot_ikeyvalue_rtti_link_unit;

{$mode delphi}

interface

function RunIKeyValueRttiLink: Int64;

implementation

uses
  mormot.core.collections;

function RunIKeyValueRttiLink: Int64;
var
  IntegerInt64: IKeyValue<Integer, Int64>;
  IntegerInt64Pair: mormot.core.collections.TPair<Integer, Int64>;
begin
  Result:=0;
  IntegerInt64:=Collections.NewKeyValue<Integer, Int64>;
  IntegerInt64.Add(1,2);
  for IntegerInt64Pair in IntegerInt64 do
    Inc(Result,IntegerInt64Pair.Key+IntegerInt64Pair.Value);
end;

end.
