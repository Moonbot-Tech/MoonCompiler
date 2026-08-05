{ %CPU=x86_64 }
{ %OPT=-O3 }
program tcmovliveness1;

{$mode delphi}

var
  TouchCount: Integer;

procedure Touch; noinline;
begin
  Inc(TouchCount);
end;

function CountSteps(ReverseOrder: Boolean; InitialLimit: Integer): Integer; noinline;
var
  Current, Limit, Step, Count: Integer;
begin
  Limit := InitialLimit;
  if not ReverseOrder then
    begin
      Current := Limit;
      Limit := -1;
      Step := -1;
    end
  else
    begin
      Current := 0;
      Limit := Limit + 1;
      Step := 1;
      Touch;
    end;
  Count := 0;
  while Current <> Limit do
    begin
      Inc(Count);
      Inc(Current, Step);
    end;
  Result := Count;
end;

begin
  if CountSteps(False, 11) <> 12 then
    Halt(1);
  if CountSteps(True, 11) <> 12 then
    Halt(2);
  if TouchCount <> 1 then
    Halt(3);
end.
