{ %OPT=-O3 }
program tforunrolllocalabrupt1;

{$mode objfpc}
{$goto on}
{$modeswitch nonlocalgoto}

var
  Got,
  Sink: Integer;

procedure Tick; noinline;
begin
  Inc(Sink);
end;

procedure ProbeGotoRead;
label
  ReadTarget;
var
  Index: Integer;
begin
  Index:=77;
  for Index:=1 to 100 do
    goto ReadTarget;
ReadTarget:
  Got:=Index;
end;

procedure ProbeGotoBypassKill;
label
  ReadTarget;
var
  Index: Integer;
begin
  Index:=77;
  for Index:=1 to 100 do
    goto ReadTarget;
  Index:=9;
ReadTarget:
  Got:=Index;
end;

procedure ProbeBreakRead;
var
  Index: Integer;
begin
  Index:=77;
  for Index:=1 to 100 do
    Break;
  Got:=Index;
end;

procedure ProbeGotoKilled;
label
  KillTarget;
var
  Index: Integer;
begin
  Index:=77;
  for Index:=1 to 100 do
    goto KillTarget;
KillTarget:
  Index:=9;
  Got:=Index;
end;

procedure ProbeBreakKilled;
var
  Index: Integer;
begin
  Index:=77;
  for Index:=1 to 100 do
    Break;
  Index:=9;
  Got:=Index;
end;

procedure ProbeNestedBreak;
var
  Index,
  Inner: Integer;
begin
  for Index:=1 to 100 do
    begin
      for Inner:=1 to 3 do
        Break;
      Tick;
    end;
end;

procedure ProbeInternalGoto;
label
  ContinueBody;
var
  Index: Integer;
begin
  for Index:=1 to 100 do
    begin
      goto ContinueBody;
ContinueBody:
      Tick;
    end;
end;

procedure ProbeNestedWhileBreakDeadNonlocal(Flag, JumpAfter: Boolean);
label
  Done;
var
  Index: Integer;

  procedure JumpDone; noinline;
  begin
    goto Done;
  end;

begin
  for Index:=1 to 100 do
    begin
      while Flag do
        begin
          Tick;
          Break;
        end;
      Tick;
    end;
  if JumpAfter then
    JumpDone;
Done:
  Got:=9;
end;

procedure ProbeNestedRepeatBreakDeadNonlocal(Flag, JumpAfter: Boolean);
label
  Done;
var
  Index: Integer;

  procedure JumpDone; noinline;
  begin
    goto Done;
  end;

begin
  for Index:=1 to 100 do
    begin
      repeat
        Tick;
        Break;
      until not Flag;
      Tick;
    end;
  if JumpAfter then
    JumpDone;
Done:
  Got:=9;
end;

procedure ProbeExitFinally;
var
  Index: Integer;
begin
  Index:=77;
  try
    for Index:=1 to 100 do
      Exit;
  finally
    Got:=Index;
  end;
end;

procedure ProbeExitFinallyKill;
var
  Index: Integer;
begin
  Index:=77;
  try
    for Index:=1 to 100 do
      Exit;
  finally
    Index:=9;
    Got:=Index;
  end;
end;

begin
  ProbeGotoRead;
  if Got<>1 then
    Halt(1);
  ProbeGotoBypassKill;
  if Got<>1 then
    Halt(2);
  ProbeBreakRead;
  if Got<>1 then
    Halt(3);
  ProbeGotoKilled;
  if Got<>9 then
    Halt(4);
  ProbeBreakKilled;
  if Got<>9 then
    Halt(5);
  Sink:=0;
  ProbeNestedBreak;
  if Sink<>100 then
    Halt(6);
  Sink:=0;
  ProbeInternalGoto;
  if Sink<>100 then
    Halt(7);
  Sink:=0;
  ProbeNestedWhileBreakDeadNonlocal(True,False);
  if (Sink<>200) or (Got<>9) then
    Halt(8);
  Sink:=0;
  ProbeNestedRepeatBreakDeadNonlocal(True,False);
  if (Sink<>200) or (Got<>9) then
    Halt(9);
  ProbeExitFinally;
  if Got<>1 then
    Halt(10);
  ProbeExitFinallyKill;
  if Got<>9 then
    Halt(11);
end.
