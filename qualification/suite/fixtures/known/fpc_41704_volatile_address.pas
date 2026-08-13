program Fpc41704VolatileAddress;

{$mode objfpc}
{$optimization on}

var
  Value: Integer;
  ValuePointer: Pointer;
begin
  ValuePointer := @Volatile(Value);
  if ValuePointer <> @Value then
    Halt(1);
end.
