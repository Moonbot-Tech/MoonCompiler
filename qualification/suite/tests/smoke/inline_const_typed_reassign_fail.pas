program inline_const_typed_reassign_fail;

{$ifdef FPC}
  {$mode delphi}
  {$modeswitch inlinevars}
{$endif}
{$J+}

var
  Base: Integer;

begin
  Base:=7;
  const Value: Integer=Base+5;
  Value:=13;
end.
