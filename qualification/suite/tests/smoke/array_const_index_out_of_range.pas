program array_const_index_out_of_range;

{$mode delphi}
{$R-}

type
  TValues = array[2..4] of Integer;

var
  Values: TValues;
begin
  Values[5] := 42;
end.
