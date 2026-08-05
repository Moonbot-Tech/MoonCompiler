program tw41808;

{$mode delphi}
{$rangechecks on}
{$overflowchecks on}

function Difference(R, G, B: Byte): Integer;
begin
  Result := R - (G + B) div 2;
end;

begin
  if Difference(0, 100, 100) <> -100 then
    Halt(1);
end.
