{ %FAIL }
{ %CPU=x86_64 }
program tuncheckedneg4;

{$mode delphi}
{$Q-}

begin
  if -UInt64(High(UInt64)) <> 1 then
    Halt(1);
end.
