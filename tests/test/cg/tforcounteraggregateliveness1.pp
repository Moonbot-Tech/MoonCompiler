program tforcounteraggregateliveness1;

{$mode tp}

type
  TCounterRecord = record
    Value: Integer;
  end;

var
  Ticks: Integer;

procedure Tick; noinline;
begin
  Inc(Ticks);
end;

procedure Probe;
var
  CounterRecord: TCounterRecord;
  CounterArray: array[0..1] of Integer;
begin
  CounterRecord.Value:=77;
  for CounterRecord.Value:=1 to 3 do
    Tick;
  if CounterRecord.Value<>3 then
    Halt(1);

  CounterArray[1]:=77;
  for CounterArray[1]:=1 to 3 do
    Tick;
  if CounterArray[1]<>3 then
    Halt(2);
end;

begin
  Ticks:=0;
  Probe;
  if Ticks<>6 then
    Halt(3);
end.
