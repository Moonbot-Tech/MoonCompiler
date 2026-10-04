program tforcounterdfaliveness1;

{$mode unleashed}

var
  GlobalCounter: Integer;
  Ticks: Integer;

procedure Tick; noinline;
begin
  Inc(Ticks);
end;

procedure ProbeGlobal;
begin
  GlobalCounter:=77;
  for GlobalCounter:=1 to 3 do
    Tick;
end;

function ProbeAddressTaken: Integer;
var
  Counter: Integer;
  Alias: ^Integer;
begin
  Counter:=77;
  Alias:=@Counter;
  for Counter:=1 to 3 do
    Tick;
  Result:=Alias^;
end;

function ProbeFixedPoint: Integer;
var
  Counter: Integer;
  Pass: Integer;
begin
  Counter:=77;
  Pass:=0;
  Result:=-1;
  repeat
    Inc(Pass);
    if Pass=2 then
      Result:=Counter;
    for Counter:=1 to 3 do
      Tick;
  until Pass=2;
end;

begin
  Ticks:=0;
  ProbeGlobal;
  if GlobalCounter<>3 then
    Halt(1);
  if ProbeAddressTaken<>3 then
    Halt(2);
  if ProbeFixedPoint<>3 then
    Halt(3);
  if Ticks<>12 then
    Halt(4);
end.
