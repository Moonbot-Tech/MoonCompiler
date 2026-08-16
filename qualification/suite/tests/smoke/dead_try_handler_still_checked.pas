program dead_try_handler_still_checked;

{$mode delphi}

var
  Value: Integer;

begin
  try
    Value := Value + 1;
  except
    MissingInDeadHandler;
  end;
end.
