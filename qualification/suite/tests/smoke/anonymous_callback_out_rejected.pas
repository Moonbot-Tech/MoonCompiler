program anonymous_callback_out_rejected;

{$mode delphi}
{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}

type
  TCallback<T> = reference to function(Arg: T): Integer;

var
  Callback: TCallback<Integer>;

begin
  Callback := TCallback<Integer>(
    function(out Arg: Integer): Integer
    begin
      Arg := 42;
      Result := Arg;
    end);
end.
