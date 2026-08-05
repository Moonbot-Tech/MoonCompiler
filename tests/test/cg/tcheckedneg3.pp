{ %FAIL }
{ %CPU=x86_64 }
program tcheckedneg3;

{$mode delphi}
{$Q+}

begin
  if -Int128(Low(Int128)) <> Low(Int128) then
    Halt(1);
end.
