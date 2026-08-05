{ %FAIL }
{ %CPU=x86_64 }
program tuncheckedneg3;

{$mode delphi}
{$Q-}

begin
  if -UInt64(1) <> High(UInt64) then
    Halt(1);
end.
