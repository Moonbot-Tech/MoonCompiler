program inline_const_var_parameter_rejected;

{$ifdef FPC}
  {$mode delphi}
  {$modeswitch inlinevars}
{$endif}

procedure ReplaceValue(var Value: Integer);
begin
  Value := 42;
end;

var
  Base: Integer;
begin
  Base := 7;
  const Value = Base + 5;
  ReplaceValue(Value);
end.
