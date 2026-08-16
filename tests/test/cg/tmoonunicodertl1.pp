{ %OPT=-dUNICODERTL -Mobjfpc -O2 }
program tmoonunicodertl1;

{$mode objfpc}

{$ifndef FPC_UNICODESTRINGS}
  {$fatal UNICODERTL must survive an ObjFPC mode directive}
{$endif}
{$ifndef UNICODE}
  {$fatal UNICODE must remain defined for UNICODERTL}
{$endif}

begin
  if (SizeOf(Char) <> 2) or (SizeOf(String('x')[1]) <> 2) then
    Halt(1);
end.
