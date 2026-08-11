{ %OPT=-O2 }
program tmoonanoncallbackabi1;

{$mode delphi}
{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}

type
  TLarge = record
    A, B, C: Int64;
  end;
  TCallback<T, TResult> = reference to function(Arg: T): TResult;

var
  Callback: TCallback<TLarge, Int64>;
  Value: TLarge;
begin
  Callback := TCallback<TLarge, Int64>(
    function(const Arg: TLarge): Int64
    begin
      Result := Arg.A + Arg.B + Arg.C;
    end);
  Value.A := 10;
  Value.B := 12;
  Value.C := 20;
  if Callback(Value) <> 42 then
    Halt(1);
end.
