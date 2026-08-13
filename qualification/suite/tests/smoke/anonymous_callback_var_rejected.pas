program anonymous_callback_var_rejected;

{$mode delphi}
{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}

type
  TCallback<T> = reference to function(Arg: T): Integer;

var
  Callback: TCallback<Integer>;

begin
  Callback := TCallback<Integer>(
    function(var Arg: Integer): Integer
    begin
      Result := Arg;
    end);
end.
