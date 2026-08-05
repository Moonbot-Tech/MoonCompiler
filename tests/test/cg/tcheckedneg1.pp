{ %FAIL }
{ %CPU=x86_64 }
program tcheckedneg1;

{$mode delphi}
{$Q+}

begin
  if -UInt64($FFFFFFFFFFFFFFFF) <> UInt64(1) then
    Halt(1);
end.
