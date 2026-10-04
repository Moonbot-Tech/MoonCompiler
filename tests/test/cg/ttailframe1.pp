program ttailframe1;

{$mode unleashed}

type
  PInteger = ^Integer;
  TPair = record
    Value: Integer;
    Guard: Integer;
  end;

function LocalFrame(N: Integer; Previous: PInteger): Integer;
var
  OwnValue: Integer;
begin
  OwnValue:=N;
  if N=0 then
    Result:=Previous^
  else
    Result:=LocalFrame(N-1,@OwnValue);
end;

function ParameterFrame(N: Integer; Previous: PInteger): Integer;
begin
  if N=0 then
    Result:=Previous^
  else
    Result:=ParameterFrame(N-1,@N);
end;

function RecordFrame(N: Integer; Previous: PInteger): Integer;
var
  OwnValue: TPair;
begin
  OwnValue.Value:=N;
  OwnValue.Guard:=$12345678;
  if N=0 then
    Result:=Previous^
  else
    Result:=RecordFrame(N-1,@OwnValue.Value);
  if OwnValue.Guard<>$12345678 then
    Halt(4);
end;

function SumTail(N, Accumulator: Integer): Integer;
begin
  if N=0 then
    Result:=Accumulator
  else
    Result:=SumTail(N-1,Accumulator+N);
end;

var
  Start: Integer;
begin
  Start:=77;
  if LocalFrame(3,@Start)<>1 then
    Halt(1);
  if ParameterFrame(3,@Start)<>1 then
    Halt(2);
  if RecordFrame(3,@Start)<>1 then
    Halt(3);
  if SumTail(100,0)<>5050 then
    Halt(5);
end.
