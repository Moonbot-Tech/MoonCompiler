program variant_distinct_objfpc_rejected;

{$mode objfpc}

uses
  Variants;

type
  TFirstOrdinal = type Int64;
  TSecondOrdinal = type TFirstOrdinal;

var
  Source: Variant;
  Value: TSecondOrdinal;
begin
  Source := Int64(42);
  Value := Source;
  WriteLn(Int64(Value));
end.
