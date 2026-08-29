program seh_regvar_semantic;

{$mode unleashed}
{$Q-}{$R-}

uses
  SysUtils;

var
  Finalized: Integer;

function LiveThroughAV(P: PInteger): Integer; noinline;
var
  X, Y, Z: Integer;
begin
  X := 42;
  Y := 1000;
  Z := 7;
  try
    P^ := 1;
  except
    on EAccessViolation do
      ;
  end;
  Result := X + Y * 2 + Z * 3;
end;

function AssignedInsideReadAfter(P: PInteger; Bias: Integer): Integer; noinline;
var
  Acc, I: Integer;
begin
  Acc := 0;
  try
    for I := 1 to 10 do
      Acc := Acc + I * Bias;
    P^ := Acc;
  except
    on EAccessViolation do
      ;
  end;
  Result := Acc;
end;

function FirstAssignedInsideReadAfter(P: PInteger; Bias: Integer): Integer; noinline;
var
  Acc: Integer;
begin
  try
    Acc := Bias * 11;
    P^ := Acc;
  except
    on EAccessViolation do
      ;
  end;
  Result := Acc;
end;

function FinallySeesLatest(Limit: Integer): Integer; noinline;
var
  I, Steps, Seen: Integer;
begin
  Seen := -1;
  Steps := 0;
  try
    try
      for I := 1 to Limit do begin
        Inc(Steps);
        If I = 7 then
          raise EAbort.Create('stop');
      end;
    finally
      Seen := Steps;
    end;
  except
    on EAbort do
      ;
  end;
  Result := Seen;
end;

function ExitThroughFinally(Limit: Integer): Integer; noinline;
var
  I, Acc: Integer;
begin
  Acc := 5;
  for I := 1 to Limit do begin
    try
      Inc(Acc, I);
      If I = 4 then
        Exit(Acc);
    finally
      Inc(Finalized);
    end;
  end;
  Result := -1;
end;

function NestedRecordFallback(Seed: Integer): Integer; noinline;
type
  TPair = record
    A, B: Integer;
  end;
var
  Pair: TPair;

  procedure Touch;
  begin
    Inc(Pair.A);
  end;

begin
  Pair.A := Seed;
  Pair.B := Seed * 3;
  try
    Touch;
  except
    Pair.B := -1;
  end;
  Result := Pair.A + Pair.B;
end;

procedure Check(const Name: string; Got, Want: Integer);
begin
  If Got <> Want then begin
    WriteLn('FAIL ', Name, ': ', Got, ' <> ', Want);
    Halt(1);
  end;
end;

var
  Sink: Integer;
begin
  Check('live/av', LiveThroughAV(nil), 2063);
  Check('live/ok', LiveThroughAV(@Sink), 2063);
  Check('assigned/av', AssignedInsideReadAfter(nil, 2), 110);
  Check('assigned/ok', AssignedInsideReadAfter(@Sink, 2), 110);
  Check('first-assigned/av', FirstAssignedInsideReadAfter(nil, 3), 33);
  Check('first-assigned/ok', FirstAssignedInsideReadAfter(@Sink, 3), 33);
  Check('finally/latest', FinallySeesLatest(100), 7);
  Finalized := 0;
  Check('exit/finally', ExitThroughFinally(100), 15);
  Check('exit/count', Finalized, 4);
  Check('nested-record-fallback', NestedRecordFallback(11), 45);
  WriteLn('SEHREGVAR:PASS');
end.
