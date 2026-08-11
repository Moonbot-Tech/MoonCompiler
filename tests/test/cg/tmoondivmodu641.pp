{ %OPT=-O2 }
program tmoondivmodu641;

{$mode delphi}

uses
  Math;

var
  Quotient, Remainder: UInt64;
begin
  DivMod(High(UInt64), UInt64(10), Quotient, Remainder);
  if Quotient <> UInt64(1844674407370955161) then
    Halt(1);
  if Remainder <> 5 then
    Halt(2);
end.
