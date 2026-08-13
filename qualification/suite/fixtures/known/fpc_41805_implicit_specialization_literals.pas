program Fpc41805ImplicitSpecializationLiterals;

{$mode objfpc}
{$modeswitch implicitfunctionspecialization}

generic function Add<T>(A, B: T): T;
begin
  Result := A + B;
end;

begin
  if Add(100, 100) <> 200 then
    Halt(1);
  if Add(100, Byte(100)) <> 200 then
    Halt(2);
end.
