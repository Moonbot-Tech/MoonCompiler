program inline_const_reassign_fail;

{$ifdef FPC}
  {$mode delphi}
  {$modeswitch inlinevars}
{$endif}

var
  Base: Integer;

begin
  Base:=7;
  const Value=Base+5;
  Value:=13;
end.
