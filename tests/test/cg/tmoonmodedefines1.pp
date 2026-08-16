{ %OPT=-dMOONCOMPILER_UNICODE_DEFAULT -Mdelphi -O2 }
program tmoonmodedefines1;

{$mode delphi}

{$ifndef FPC_UNICODESTRINGS}
  {$fatal Moon Delphi mode must keep FPC_UNICODESTRINGS}
{$endif}
{$ifndef UNICODE}
  {$fatal Moon Delphi mode must keep UNICODE}
{$endif}

begin
  if (SizeOf(Char) <> 2) or (SizeOf(String('x')[1]) <> 2) or
     (SizeOf(AnsiChar) <> 1) or (SizeOf(AnsiString('x')[1]) <> 1) then
    Halt(1);
end.
