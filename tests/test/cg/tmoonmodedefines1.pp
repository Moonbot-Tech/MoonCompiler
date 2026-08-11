{ %OPT=-Mdelphiunicode -O2 }
program tmoonmodedefines1;

{$mode delphi}

{$ifdef FPC_UNICODESTRINGS}
  {$fatal Delphi mode must clear FPC_UNICODESTRINGS}
{$endif}
{$ifdef UNICODE}
  {$fatal Delphi mode must clear UNICODE}
{$endif}

begin
  if (SizeOf(Char) <> 1) or (SizeOf(String('x')[1]) <> 1) then
    Halt(1);
end.
