program procvar_of_intrinsic_rejected;
{$mode objfpc}
{$modeswitch inlinevars}
{ Abs is an intrinsic of the compiler (internproc): it is expanded in place at
  every call and has no body, so it has no address.  The address used to be
  taken without an error, and a call through it read an intrinsic number off
  the procedural type (Fatal: Unknown internal procedure number, a different
  number on every run).  The compiler must refuse the address. }
var
  X: Longint;
begin
  X := -4;
  var F := @Abs;
  If F(X) = 4 then
    WriteLn('PROCVAR_OF_INTRINSIC_TAKEN');
end.
