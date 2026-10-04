{ %OPT=-O3 }
program tforunrollexceptioncounter1;

{$mode delphiunicode}
{$modeswitch forstep}
{$goto on}

uses
  SysUtils;

var
  Sink,
  AbruptObserved: Integer;

type
  TPositiveStep = 1..3;

procedure RaiseAt(const Value: Integer); noinline;
begin
  if Value=2 then
    raise Exception.Create('loop counter observation');
end;

function Probe: Integer;
var
  Index: Integer;
begin
  Index:=77;
  Result:=-1;
  try
    for Index:=1 to 3 do
      RaiseAt(Index);
  except
    Result:=Index;
  end;
end;

function ProbeFinally: Integer;
var
  Index: Integer;
begin
  Index:=77;
  Result:=-1;
  try
    try
      for Index:=1 to 3 do
        RaiseAt(Index);
    finally
      Result:=Index;
    end;
  except
  end;
end;

function ProbeWriteBeforeRead: Integer;
var
  Index: Integer;
begin
  Index:=77;
  Result:=-1;
  try
    for Index:=1 to 3 do
      RaiseAt(Index);
  except
    Index:=91;
    Result:=Index;
  end;
end;

function ProbeNestedHandler: Integer;
var
  Index: Integer;
begin
  Index:=77;
  Result:=-1;
  try
    try
      for Index:=1 to 3 do
        RaiseAt(Index);
    except
      Inc(Sink);
      raise;
    end;
  except
    Result:=Index;
  end;
end;

function ProbeLoopInFinalizer: Integer;
var
  Index: Integer;
begin
  Index:=77;
  Result:=-1;
  try
    try
      Inc(Sink);
    finally
      for Index:=1 to 3 do
        RaiseAt(Index);
    end;
  except
    Result:=Index;
  end;
end;

function ProbeContinuation: Integer;
var
  Index: Integer;
  Raised: Boolean;
begin
  Index:=77;
  Raised:=False;
  try
    for Index:=1 to 3 do
      RaiseAt(Index);
  except
    Raised:=True;
  end;
  if Raised then
    Result:=Index
  else
    Result:=-1;
end;

function ProbeElseBranch(const TakeOther: Boolean): Integer;
var
  Index: Integer;
begin
  Index:=77;
  Result:=-1;
  if TakeOther then
    Result:=Index
  else
    try
      for Index:=1 to 3 do
        RaiseAt(Index);
    except
      Result:=Index;
    end;
end;

function ProbeOnHandler: Integer;
var
  Index: Integer;
begin
  Index:=77;
  Result:=-1;
  try
    RaiseAt(2);
  except
    on E: Exception do
      try
        for Index:=1 to 3 do
          RaiseAt(Index);
      except
        Result:=Index;
      end;
  end;
end;

function ProbeFinallyKillsCounter: Integer;
var
  Index: Integer;
begin
  Index:=77;
  Result:=-1;
  try
    try
      for Index:=1 to 3 do
        RaiseAt(Index);
    finally
      Index:=91;
    end;
  except
    Result:=Index;
  end;
end;

function ProbeCatchAllKillsCounter: Integer;
var
  Index: Integer;
  Caught: Boolean;
begin
  Index:=77;
  Caught:=False;
  try
    for Index:=1 to 3 do
      RaiseAt(Index);
  except
    Index:=91;
    Caught:=True;
  end;
  if Caught then
    Result:=Index
  else
    Result:=-1;
end;

function ProbeGotoKillsCounter: Integer;
label
  Cleanup;
var
  Index: Integer;
begin
  Index:=77;
  try
    for Index:=1 to 3 do
      RaiseAt(Index);
  except
    goto Cleanup;
Cleanup:
    Index:=91;
  end;
  Result:=Index;
end;

procedure ProbeExitThroughFinally;
var
  Index: Integer;
begin
  Index:=77;
  try
    try
      for Index:=1 to 3 do
        RaiseAt(Index);
    except
      Exit;
    end;
  finally
    AbruptObserved:=Index;
  end;
end;

procedure ProbeBreakThroughFinally;
var
  Index: Integer;
begin
  Index:=77;
  while True do
    try
      try
        for Index:=1 to 3 do
          RaiseAt(Index);
      except
        Break;
      end;
      Index:=91;
    finally
      AbruptObserved:=Index;
    end;
end;

procedure ProbeContinueThroughFinally;
var
  Index,
  Iteration: Integer;
begin
  Index:=77;
  Iteration:=0;
  while Iteration<1 do
    try
      Inc(Iteration);
      try
        for Index:=3 downto 1 do
          RaiseAt(Index);
      except
        Continue;
      end;
      Index:=91;
    finally
      AbruptObserved:=Index;
  end;
end;

procedure ProbeNestedExitThroughFinally(const TakeExit: Boolean);
var
  Index: Integer;
begin
  Index:=77;
  try
    try
      for Index:=1 to 3 do
        RaiseAt(Index);
    except
      while TakeExit do
        Exit;
      Index:=91;
    end;
  finally
    AbruptObserved:=Index;
  end;
end;

procedure ProbeGotoOutOfLoop(const TakeGoto: Boolean);
label
  ReadCounter;
var
  Index: Integer;
begin
  Index:=77;
  try
    for Index:=1 to 3 do
      RaiseAt(Index);
  except
    while TakeGoto do
      goto ReadCounter;
    Index:=91;
ReadCounter:
    AbruptObserved:=Index;
  end;
end;

function ProbeGotoLoopKillsCounter: Integer;
label
  Again;
var
  Index,
  Remaining: Integer;
begin
  Index:=77;
  try
    for Index:=1 to 3 do
      RaiseAt(Index);
  except
    Remaining:=2;
    while Remaining>0 do
      begin
Again:
        Dec(Remaining);
        if Remaining>0 then
          goto Again;
      end;
    Index:=91;
  end;
  Result:=Index;
end;

function ProbeBodyStepCheckHandler(const Step: Integer): Integer;
var
  Index,
  Inner: Integer;
begin
  Index:=77;
  Result:=-1;
  try
    for Index:=1 to 3 do
      for Inner:=1 to 3 step Step do
        Sink:=Inner;
  except
    Result:=Index;
  end;
end;

function ProbeBodySubrangeStepCheckHandler(const Step: TPositiveStep): Integer;
var
  Index,
  Inner: Integer;
begin
  Index:=77;
  Result:=-1;
  try
    for Index:=1 to 3 do
      for Inner:=1 to 3 step Step do
        Sink:=Inner;
  except
    Result:=Index;
  end;
end;

function ProbeBodyConstantStepHandler: Integer;
var
  Index,
  Inner: Integer;
begin
  Index:=77;
  Result:=-1;
  try
    for Index:=1 to 3 do
      for Inner:=1 to 3 step 2 do
        Sink:=Inner;
  except
    Result:=Index;
  end;
end;

procedure ProbeFinalizerGotoContextKill;
label
  Done;
var
  Index: Integer;
begin
  Index:=77;
  try
    try
      try
        for Index:=1 to 3 do
          RaiseAt(Index);
      except
      end;
    finally
      goto Done;
Done:
      Sink:=0;
    end;
    Index:=91;
  finally
    AbruptObserved:=Index;
  end;
end;

begin
  if Probe<>2 then
    Halt(1);
  if ProbeFinally<>2 then
    Halt(2);
  if ProbeWriteBeforeRead<>91 then
    Halt(3);
  if ProbeNestedHandler<>2 then
    Halt(4);
  if ProbeLoopInFinalizer<>2 then
    Halt(5);
  if ProbeContinuation<>2 then
    Halt(6);
  if ProbeElseBranch(False)<>2 then
    Halt(7);
  if ProbeElseBranch(True)<>77 then
    Halt(8);
  if ProbeOnHandler<>2 then
    Halt(9);
  if ProbeFinallyKillsCounter<>91 then
    Halt(10);
  if ProbeCatchAllKillsCounter<>91 then
    Halt(11);
  if ProbeGotoKillsCounter<>91 then
    Halt(12);
  AbruptObserved:=-1;
  ProbeExitThroughFinally;
  if AbruptObserved<>2 then
    Halt(13);
  AbruptObserved:=-1;
  ProbeBreakThroughFinally;
  if AbruptObserved<>2 then
    Halt(14);
  AbruptObserved:=-1;
  ProbeContinueThroughFinally;
  if AbruptObserved<>2 then
    Halt(15);
  AbruptObserved:=-1;
  ProbeNestedExitThroughFinally(True);
  if AbruptObserved<>2 then
    Halt(16);
  AbruptObserved:=-1;
  ProbeNestedExitThroughFinally(False);
  if AbruptObserved<>91 then
    Halt(17);
  AbruptObserved:=-1;
  ProbeGotoOutOfLoop(True);
  if AbruptObserved<>2 then
    Halt(18);
  AbruptObserved:=-1;
  ProbeGotoOutOfLoop(False);
  if AbruptObserved<>91 then
    Halt(19);
  if ProbeGotoLoopKillsCounter<>91 then
    Halt(20);
  if ProbeBodyStepCheckHandler(0)<>1 then
    Halt(21);
  if ProbeBodyStepCheckHandler(1)<>-1 then
    Halt(22);
  if ProbeBodySubrangeStepCheckHandler(TPositiveStep(0))<>1 then
    Halt(23);
  if ProbeBodySubrangeStepCheckHandler(1)<>-1 then
    Halt(24);
  if ProbeBodyConstantStepHandler<>-1 then
    Halt(25);
  AbruptObserved:=-1;
  ProbeFinalizerGotoContextKill;
  if AbruptObserved<>91 then
    Halt(26);
end.
