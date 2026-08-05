{ %FAIL }
{ %CPU=x86_64 }
program tcheckedneg4;

{$mode delphi}
{$Q+}

begin
  if -UInt128(High(UInt128)) <> 1 then
    Halt(1);
end.
