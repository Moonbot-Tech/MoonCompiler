{ %OPT=-O3 }
program tforunrollnonlocalgoto1;

{$mode objfpc}
{$goto on}
{$modeswitch nonlocalgoto}
{$modeswitch nestedprocvars}
{$modeswitch forstep}

type
  TNestedJump = procedure is nested;

var
  Got,
  Sink,
  Wide: Integer;
  Small: 0..2;
  JumpCallback: TNestedJump;
  OldErrorProc: TErrorProc;
  OldMM,
  HookMM: TMemoryManager;
  ManagedText: AnsiString;

function HookGetMem(Size: PtrUInt): Pointer;
begin
  JumpCallback;
  Result:=OldMM.GetMem(Size);
end;

function HookReallocMem(var P: Pointer; Size: PtrUInt): Pointer;
begin
  JumpCallback;
  Result:=OldMM.ReallocMem(P,Size);
end;

procedure HookRangeError(ErrNo: LongInt; Address: CodePointer; Frame: Pointer);
begin
  JumpCallback;
end;

procedure ProbeScalar;
label
  Done;
var
  Value: Integer;

  procedure JumpOut; noinline;
  begin
    goto Done;
  end;

begin
  Value:=42;
  JumpOut;
  Value:=91;
Done:
  Got:=Value;
end;

procedure ProbeLoop;
label
  Done;
var
  Index: Integer;

  procedure JumpOut(const Value: Integer); noinline;
  begin
    if Value=2 then
      goto Done;
  end;

begin
  Index:=77;
  for Index:=1 to 3 do
    JumpOut(Index);
Done:
  Got:=Index;
end;

procedure ProbeTransitiveLoop;
label
  Done;
var
  Index: Integer;

  procedure JumpOut(const Value: Integer); noinline;
  begin
    if Value=2 then
      goto Done;
  end;

  procedure Wrapper(const Value: Integer); noinline;
  begin
    JumpOut(Value);
  end;

begin
  Index:=77;
  for Index:=1 to 3 do
    Wrapper(Index);
Done:
  Got:=Index;
end;

procedure ProbeKilledTarget;
label
  Done;
var
  Index: Integer;

  procedure JumpOut(const Value: Integer); noinline;
  begin
    if Value=2 then
      goto Done;
  end;

begin
  Index:=77;
  for Index:=1 to 3 do
    JumpOut(Index);
Done:
  Index:=91;
  Got:=Index;
end;

procedure ProbeArrayLabel;
label
  Done[1..2];
var
  Index: Integer;

  procedure JumpOut(const Target: Integer); noinline;
  begin
    goto Done[Target];
  end;

begin
  Index:=77;
  for Index:=1 to 3 do
    JumpOut(Index);
Done[1]:
  Got:=Index;
  exit;
Done[2]:
  Got:=-Index;
end;

procedure ProbeCountdown;
label
  Done;
var
  Index: Integer;

  procedure JumpOut; noinline;
  begin
    goto Done;
  end;

begin
  Index:=77;
  { This exceeds the unroll threshold and reaches the for-loop reversal pass. }
  for Index:=1 to 100 do
    JumpOut;
Done:
  Got:=Index;
end;

procedure ProbeDisjointTargets;
label
  KillTarget,
  ReadTarget;
var
  Index: Integer;

  procedure JumpKill; noinline;
  begin
    goto KillTarget;
  end;

  procedure JumpRead; noinline;
  begin
    goto ReadTarget;
  end;

begin
  Index:=77;
  for Index:=1 to 3 do
    JumpKill;
  JumpRead;
KillTarget:
  Index:=9;
ReadTarget:
  Got:=Index;
end;

procedure ProbeImplicitSetLength;
label
  Done;
var
  Index: Integer;

  procedure JumpOut;
  begin
    goto Done;
  end;

begin
  GetMemoryManager(OldMM);
  HookMM:=OldMM;
  HookMM.GetMem:=@HookGetMem;
  HookMM.ReallocMem:=@HookReallocMem;
  JumpCallback:=@JumpOut;
  Index:=77;
  SetMemoryManager(HookMM);
  for Index:=1 to 3 do
    SetLength(ManagedText,1000);
Done:
  SetMemoryManager(OldMM);
  JumpCallback:=nil;
  Got:=Index;
end;

procedure ProbeDirectRangeError;
label
  Done;
var
  Index: Integer;

  procedure JumpOut;
  begin
    goto Done;
  end;

begin
  OldErrorProc:=ErrorProc;
  JumpCallback:=@JumpOut;
  Index:=77;
  ErrorProc:=@HookRangeError;
  for Index:=1 to 3 do
    begin
{$R+}
      Small:=Wide;
{$R-}
    end;
Done:
  ErrorProc:=OldErrorProc;
  JumpCallback:=nil;
  Got:=Index;
end;

procedure CheckedRangeAssign; noinline;
begin
{$R+}
  Small:=Wide;
{$R-}
end;

procedure ProbeCalleeRangeError;
label
  Done;
var
  Index: Integer;

  procedure JumpOut;
  begin
    goto Done;
  end;

begin
  OldErrorProc:=ErrorProc;
  JumpCallback:=@JumpOut;
  Index:=77;
  ErrorProc:=@HookRangeError;
  for Index:=1 to 3 do
    CheckedRangeAssign;
Done:
  ErrorProc:=OldErrorProc;
  JumpCallback:=nil;
  Got:=Index;
end;

procedure ProbeRecursiveActivation(Depth: Integer); noinline;
label
  Done;
var
  Index: Integer;

  procedure JumpOut;
  begin
    goto Done;
  end;

begin
  if Depth<>0 then
    begin
      JumpCallback;
      exit;
    end;
  JumpCallback:=@JumpOut;
  Index:=77;
  for Index:=1 to 3 do
    ProbeRecursiveActivation(1);
Done:
  JumpCallback:=nil;
  Got:=Index;
end;

procedure ProbeContinuationRangeError;
label
  Resume,
  ReadTarget;
var
  Index: Integer;

  procedure JumpResume; noinline;
  begin
    goto Resume;
  end;

  procedure JumpRead;
  begin
    goto ReadTarget;
  end;

begin
  OldErrorProc:=ErrorProc;
  JumpCallback:=@JumpRead;
  Index:=77;
  ErrorProc:=@HookRangeError;
  for Index:=1 to 3 do
    JumpResume;
Resume:
{$R+}
  Small:=Wide;
{$R-}
  Index:=9;
ReadTarget:
  ErrorProc:=OldErrorProc;
  JumpCallback:=nil;
  Got:=Index;
end;

procedure ProbeContinuationStepError;
label
  Resume,
  ReadTarget;
var
  Index,
  StepIndex: Integer;

  procedure JumpResume; noinline;
  begin
    goto Resume;
  end;

  procedure JumpRead;
  begin
    goto ReadTarget;
  end;

begin
  OldErrorProc:=ErrorProc;
  JumpCallback:=@JumpRead;
  Index:=77;
  ErrorProc:=@HookRangeError;
  for Index:=1 to 3 do
    JumpResume;
Resume:
  for StepIndex:=1 to 3 step Wide do
    Sink:=StepIndex;
  Index:=9;
ReadTarget:
  ErrorProc:=OldErrorProc;
  JumpCallback:=nil;
  Got:=Index;
end;

procedure Tick; noinline;
begin
  Inc(Sink);
end;

procedure ProbeOrdinaryCountdown;
var
  Index: Integer;
begin
  { Adjacent control: without an abrupt observer the countdown transform is
    still profitable and must remain enabled. }
  for Index:=1 to 100 do
    Tick;
end;

procedure ProbeNoCallInLoop(const TakeJump: Boolean);
label
  Done;
var
  Index: Integer;

  procedure JumpOut; noinline;
  begin
    goto Done;
  end;

begin
  Index:=77;
  for Index:=1 to 3 do
    Sink:=Index*2;
  if TakeJump then
    JumpOut;
Done:
  Sink:=Index;
end;

begin
  ProbeScalar;
  if Got<>42 then
    Halt(1);
  ProbeLoop;
  if Got<>2 then
    Halt(2);
  ProbeTransitiveLoop;
  if Got<>2 then
    Halt(3);
  ProbeKilledTarget;
  if Got<>91 then
    Halt(4);
  ProbeArrayLabel;
  if Got<>1 then
    Halt(5);
  ProbeCountdown;
  if Got<>1 then
    Halt(6);
  ProbeDisjointTargets;
  if Got<>9 then
    Halt(7);
  ProbeImplicitSetLength;
  if Got<>1 then
    Halt(8);
  Wide:=10;
  ProbeDirectRangeError;
  if Got<>1 then
    Halt(9);
  ProbeCalleeRangeError;
  if Got<>1 then
    Halt(10);
  ProbeRecursiveActivation(0);
  if Got<>1 then
    Halt(11);
  Wide:=10;
  ProbeContinuationRangeError;
  if Got<>1 then
    Halt(12);
  Wide:=0;
  ProbeContinuationStepError;
  if Got<>1 then
    Halt(13);
  ProbeOrdinaryCountdown;
  ProbeNoCallInLoop(False);
end.
