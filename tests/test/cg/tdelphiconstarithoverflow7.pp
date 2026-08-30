program tdelphiconstarithoverflow7;

{$mode delphi}
{$Q-}

const
  Add1 = Cardinal(2654435761);
  Add2 = Cardinal(2246822519);
  Mul1 = Cardinal(3000000000);
  Mul2 = Cardinal(3);
var
  Seed,
  Value: Cardinal;
begin
  Seed:=7;
  Value:=Seed+Add1+Add2;
  if Value<>Cardinal(606290991) then
    halt(1);
  Seed:=2;
  Value:=Seed*Mul1*Mul2;
  if Value<>Cardinal(820130816) then
    halt(2);
end.
