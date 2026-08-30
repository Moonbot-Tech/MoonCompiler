{ %FAIL }
program tdelphiconstarithoverflow9;

{$mode delphi}
{$Q-}

const
  Add1 = Cardinal(2654435761);
  Add2 = Cardinal(2246822519);
var
  Seed,
  Value: Cardinal;
begin
  Seed:=7;
  Value:=Seed+(Add1+Add2);
  if Value=0 then
    halt(1);
end.
