{ %OPT=-O3 }
{ %RECOMPILE }
program tarrayinit1;

{$mode delphi}

uses
  uarrayinit1;

begin
  If InitializeCount <> 4 then
    Halt(1);
  If (Direct[1].State <> $4145) or (Direct[2].State <> $4145) then
    Halt(2);
  If (Wrapped.Values[1].State <> $4145) or
    (Wrapped.Values[2].State <> $4145) then
    Halt(3);
end.
