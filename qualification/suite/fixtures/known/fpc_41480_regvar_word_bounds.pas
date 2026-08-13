program Fpc41480RegvarWordBounds;

{$mode objfpc}

procedure Convert(I: UInt32);
var
  W: Word;
begin
  W := 0;
  if I < $10000 then
    W := Word(I)
  else if I < $20000 then
    W := Word(I - $10000)
  else if I < $30000 then
    W := Word(I - $20000);
  if W = $ffff then
    Write('');
end;

begin
  Convert($12345);
end.
