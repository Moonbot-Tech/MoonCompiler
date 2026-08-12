program inline_const_compiletime_rejected;

{$mode delphi}
{$modeswitch inlinevars}

begin
  const Count=3;
  var Values: array[0..Count-1] of Integer;
  Values[0]:=1;
end.
