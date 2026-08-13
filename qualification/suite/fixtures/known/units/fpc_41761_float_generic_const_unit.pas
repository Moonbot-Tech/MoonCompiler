unit fpc_41761_float_generic_const_unit;

{$mode objfpc}
{$modeswitch advancedrecords}

interface

type
  generic TProduct<T; const A, B: Single> = record
    const Value = A * B;
  end;

  TStringProduct = specialize TProduct<String, 1.0, 2.0>;

implementation

end.
