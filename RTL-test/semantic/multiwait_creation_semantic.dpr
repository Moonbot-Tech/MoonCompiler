program multiwait_creation_semantic;
{$mode delphi}{$H+}
uses {$ifdef UNIX}cthreads,{$endif} SysUtils, Classes, Types;

var
  Original, Probe: TThreadManager;
  TargetThread: TThreadID;
  CreateEntered, CreateReleased, SetterCompleted: LongInt;
  Mode: Integer;
  First, Other: TMultiWaitEvent;

function ControlledCreate(Attributes: Pointer; Manual, Initial: Boolean; const Name: AnsiString): PEventState;
begin
  If GetCurrentThreadID=TargetThread then begin
    InterlockedExchange(CreateEntered,1);
    while InterlockedCompareExchange(CreateReleased,0,0)=0 do Sleep(1);
    If Mode=1 then raise EAbort.Create('injected event creation failure');
    If Mode=2 then Exit(nil);
  end;
  Result:=Original.BasicEventCreate(Attributes,Manual,Initial,Name);
end;

type
  TWaiter = class(TThread)
    Outcome: TWaitResult;
    Raised: Boolean;
    procedure Execute; override;
  end;
  TSetter = class(TThread)
    procedure Execute; override;
  end;

procedure TWaiter.Execute;
begin
  TargetThread:=GetCurrentThreadID;
  try
    Outcome:=First.WaitFor(16);
  except
    on E: EAbort do Raised:=True;
  end;
end;

procedure TSetter.Execute;
begin
  If Mode=3 then First.SetEvent else Other.SetEvent;
  InterlockedExchange(SetterCompleted,1);
end;

procedure Check(Value: Boolean; const Detail: string);
begin
  If not Value then begin
    WriteLn('MULTIWAIT_CREATION_FAIL: ',Detail);
    Halt(1);
  end;
end;

procedure AwaitValue(var Value: LongInt);
var Started: UInt64;
begin
  Started:=TThread.GetTickCount64;
  while InterlockedCompareExchange(Value,0,0)=0 do begin
    Check(TThread.GetTickCount64-Started<2000,'creation or concurrent Set stuck');
    Sleep(1);
  end;
end;

var Waiter: TWaiter; Setter: TSetter;
begin
  GetThreadManager(Original);
  Probe:=Original;
  Probe.InitManager:=nil;
  Probe.BasicEventCreate:=@ControlledCreate;
  SetThreadManager(Probe);
  for Mode:=0 to 4 do begin
    First:=TMultiWaitEvent.Create;
    Other:=TMultiWaitEvent.Create;
    CreateEntered:=0;
    CreateReleased:=0;
    SetterCompleted:=0;
    Waiter:=TWaiter.Create(False);
    AwaitValue(CreateEntered);
    Setter:=nil;
    If Mode<>0 then begin
      Setter:=TSetter.Create(False);
      AwaitValue(SetterCompleted);
    end;
    { Let the finite deadline expire while creation is suspended. The signal
      case must still see the signal; failures must leave no registered waiter. }
    Sleep(25);
    InterlockedExchange(CreateReleased,1);
    Check(Waiter.WaitFor(2000),'wait completion');
    Check(Waiter.FatalException=nil,'unexpected wait exception');
    case Mode of
      0,4: Check(Waiter.Outcome=wrTimeout,'timeout after creation');
      1: Check(Waiter.Raised,'creation exception lost');
      2: Check(Waiter.Outcome=wrError,'nil creation result');
      3: Check(Waiter.Outcome=wrSignaled,'signal during creation lost');
    end;
    If Setter<>nil then begin
      Setter.WaitFor;
      Check(Setter.FatalException=nil,'setter exception');
      Setter.Free;
    end;
    Waiter.Free;
    TargetThread:=0;
    First.SetEvent;
    Check(First.WaitFor(0)=wrSignaled,'lock or waiter registration leaked');
    First.ResetEvent;
    Check(First.WaitFor(0)=wrTimeout,'reset after creation failure');
    First.Free;
    Other.Free;
  end;
  Original.InitManager:=nil;
  SetThreadManager(Original);
  WriteLn('MULTIWAIT_CREATION_PASS');
end.
