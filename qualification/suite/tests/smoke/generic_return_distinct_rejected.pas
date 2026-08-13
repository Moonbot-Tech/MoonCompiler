program generic_return_distinct_rejected;

{$mode delphi}

type
  TFirst = type Int64;
  TSecond = type Int64;

function DistinctResult: TFirst; forward;

function DistinctResult: TSecond;
begin
  Result:=0;
end;

begin
end.
