program tforsteplatchasm1;

{ the for-step steady state must carry exactly one continuation compare:
  the repair gate reads the O3 assembly of Sum and rejects a first-iteration
  flag or a second bound check in the loop body }

{$mode unleashed}

function Sum(lo,hi,st: integer): integer;
var
  i : integer;
begin
  result:=0;
  for i:=lo to hi step st do
    result:=result+i;
end;

begin
  { 1+8+...+99: 15 passes }
  if Sum(1,100,7)<>750 then
    halt(1);
  if Sum(10,1,2)<>0 then
    halt(2);
end.
