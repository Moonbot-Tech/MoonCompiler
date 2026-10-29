program wait_granularity_semantic;
{ %TARGET=linux }
{$ifdef FPC}{$mode delphi}{$endif}
{$ifdef LINUX}
uses cthreads, Unix, UnixType, SysUtils, Classes, SyncObjs;

procedure Check(OK: Boolean; const Text: string);
begin
  if not OK then raise Exception.Create(Text);
end;

function Clock(Id: LongInt; var T: TTimeSpec): LongInt; cdecl; external 'c' name 'clock_gettime';
function NativeSleep(var Request, Remaining: TTimeSpec): LongInt; cdecl; external 'c' name 'nanosleep';
function Ns: QWord;
var T: TTimeSpec;
begin
  Check(Clock(1,T)=0,'clock');
  Result:=QWord(T.tv_sec)*1000000000+QWord(T.tv_nsec);
end;

type
  TSignaller = class(TThread)
    E: TEvent;
    R: PRTLEvent;
    procedure Execute; override;
  end;

procedure TSignaller.Execute;
var Request, Remaining: TTimeSpec;
begin
  Request.tv_sec:=0;
  Request.tv_nsec:=5000000;
  Check(NativeSleep(Request,Remaining)=0,'native producer delay');
  if E<>nil then E.SetEvent else RTLEventSetEvent(R);
end;

var
  E: TEvent;
  R: PRTLEvent;
  W: TSignaller;
  Start, Elapsed: QWord;
  I, J: Integer;
  Manual: Boolean;
begin
  Check(WaitDurationUS(16)=16000,'native default');
  SetWaitGranularityUS(15625);
  Check(WaitDurationUS(0)=0,'zero poll');
  Check(WaitDurationUS(1)=15625,'one');
  Check(WaitDurationUS(15)=15625,'fifteen');
  Check(WaitDurationUS(16)=31250,'sixteen');
  Check(WaitDurationUS(31)=31250,'thirty one');
  Check(WaitDurationUS(32)=46875,'thirty two');
  Check(WaitDurationUS(80)=93750,'eighty');
  Check(WaitDurationUS(125)=125000,'exact multiple');
  Check(WaitDurationUS(High(Cardinal))=QWord(High(Cardinal))*1000,'infinite sentinel');
  Check(WaitDurationUS(High(Cardinal)-1)>=QWord(High(Cardinal)-1)*1000,'large finite');
  for I:=0 to 1 do begin
    Manual:=I<>0;
    E:=TEvent.Create(nil,Manual,False,'');
    try
      Start:=Ns;
      for J:=1 to 1000 do Check(E.WaitFor(0)=wrTimeout,'empty poll');
      Check(Ns-Start<500000000,'poll did not sleep');
      E.SetEvent;
      Check(E.WaitFor(High(Cardinal))=wrSignaled,'ready infinite');
      Check((E.WaitFor(0)=wrSignaled)=Manual,'reset mode');
      E.ResetEvent;
      Start:=Ns;
      Check(E.WaitFor(16)=wrTimeout,'finite timeout');
      Elapsed:=Ns-Start;
      Check(Elapsed>=31000000,'finite duration rounded');
      Check(Elapsed<500000000,'finite bounded');
      SetWaitGranularityUS(1000000);
      W:=TSignaller.Create(True);
      W.E:=E;
      Start:=Ns;
      W.Start;
      Check(E.WaitFor(5000)=wrSignaled,'signal interrupts rounded wait');
      Check(Ns-Start<500000000,'signal was not delayed until timeout');
      W.WaitFor;
      W.Free;
      SetWaitGranularityUS(15625);
    finally
      E.Free;
    end;
  end;
  R:=RTLEventCreate;
  try
    RTLEventSetEvent(R);
    Start:=Ns;
    RTLEventWaitFor(R,1000);
    Check(Ns-Start<500000000,'internal ready');
    Start:=Ns;
    RTLEventWaitFor(R,0);
    Check(Ns-Start<500000000,'internal poll');
    Start:=Ns;
    RTLEventWaitFor(R,16);
    Check(Ns-Start>=31000000,'internal rounded wait');
    W:=TSignaller.Create(True);
    W.R:=R;
    W.Start;
    Start:=Ns;
    RTLEventWaitFor(R);
    Check(Ns-Start<500000000,'internal infinite signalled');
    W.WaitFor;
    W.Free;
  finally
    RTLEventDestroy(R);
  end;
  Start:=Ns;
  Sleep(16);
  Check(Ns-Start>=31000000,'Sleep rounded');
  Start:=Ns;
  for I:=1 to 10 do Sleep(0);
  Check(Ns-Start<100000000,'Sleep zero unchanged');
  SetWaitGranularityUS(0);
  Check(WaitDurationUS(16)=16000,'native restored');
  SetWaitGranularityUS(1);
  Check(WaitDurationUS(16)=16000,'unit quantum unchanged');
  SetWaitGranularityUS(High(Cardinal));
  Check(WaitDurationUS(High(Cardinal)-1)=4294967295000,'largest quantum and finite timeout');
  SetWaitGranularityUS(0);
  WriteLn('WAIT_GRANULARITY_PASS');
end.
{$else}
begin
  Writeln('WAIT_GRANULARITY_NOT_APPLICABLE');
end.
{$endif}
