program tforstep10;

{ a runtime step <= 0 is a range error, raised after the single step
  evaluation and before the bound and the counter are touched }

{$mode unleashed}

uses
  sysutils;

var
  i, boundcalls, stepcalls, count : integer;
  caught : boolean;

function zerostep : integer;
begin
  inc(stepcalls);
  result:=0;
end;

function negstep : integer;
begin
  inc(stepcalls);
  result:=-3;
end;

function bound : integer;
begin
  inc(boundcalls);
  result:=10;
end;

begin
  { runtime zero: range error before bound evaluation and counter update }
  i:=77;
  stepcalls:=0;
  boundcalls:=0;
  count:=0;
  caught:=false;
  try
    for i:=1 to bound step zerostep do
      inc(count);
  except
    on ERangeError do
      caught:=true;
  end;
  if not caught then
    halt(1);
  if count<>0 then
    halt(2);
  if stepcalls<>1 then
    halt(3);
  if boundcalls<>0 then
    halt(4);
  if i<>77 then
    halt(5);

  { runtime negative on a downto loop }
  i:=77;
  stepcalls:=0;
  count:=0;
  caught:=false;
  try
    for i:=10 downto 1 step negstep do
      inc(count);
  except
    on ERangeError do
      caught:=true;
  end;
  if not caught then
    halt(6);
  if count<>0 then
    halt(7);
  if stepcalls<>1 then
    halt(8);
  if i<>77 then
    halt(9);

  { a positive runtime step still works and is evaluated exactly once }
  stepcalls:=0;
  count:=0;
  for i:=1 to 10 step abs(negstep) do
    inc(count);
  if count<>4 then
    halt(10);
  if stepcalls<>1 then
    halt(11);
end.
