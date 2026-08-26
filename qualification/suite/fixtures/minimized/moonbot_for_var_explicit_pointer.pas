program moonbot_for_var_explicit_pointer;

{$ifdef FPC}
  {$mode delphiunicode}
  {$modeswitch inlinevars}
{$endif}

var
  First,
  Second: Variant;
  Values: array[0..1] of PVariant;
  Total: Integer;
begin
  First:=10;
  Second:=20;
  Values[0]:=@First;
  Values[1]:=@Second;

  Total:=0;
  for var Item: PVariant in Values do
    Inc(Total,Integer(Item^));
  if Total<>30 then
    Halt(1);
end.
