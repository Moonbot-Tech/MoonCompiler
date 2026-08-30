program tdelphiconstarithoverflow8;

{$mode delphi}
{$Q+}

uses
  SysUtils;

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
  try
    Value:=Seed+Add1+Add2;
    halt(1);
  except
    on EIntOverflow do
      ;
  end;
  Seed:=2;
  try
    Value:=Seed*Mul1*Mul2;
    halt(2);
  except
    on EIntOverflow do
      ;
  end;
end.
