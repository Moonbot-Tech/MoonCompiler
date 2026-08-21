{ %OPT=-O3 }
program tmoonconstpropglobalcalls1;

{$mode delphi}

var
  Calls: Integer;

function Step: Integer; inline;
begin
  Inc(Calls);
  Result := Calls * 10;
end;

var
  Total: Integer;
begin
  Total := Step + Step;
  if Calls <> 2 then
    Halt(1);
  if Total <> 30 then
    Halt(2);
end.
