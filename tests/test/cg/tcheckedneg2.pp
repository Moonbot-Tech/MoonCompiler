{ %FAIL }
{ %CPU=x86_64 }
program tcheckedneg2;

{$mode delphi}
{$Q+}

begin
  if -Int64(Low(Int64)) <> Low(Int64) then
    Halt(1);
end.
