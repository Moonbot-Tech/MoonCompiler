program Fpc41761FloatGenericConstConsumer;

{$mode objfpc}

uses
  fpc_41761_float_generic_const_unit;

begin
  if TStringProduct.Value <> 2.0 then
    Halt(1);
end.
