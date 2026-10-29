program condition_error_probe;
{$mode delphi}{$H+}
uses cthreads, SysUtils, Classes, SyncObjs;

type
  TPoller = class(TThread)
    Event: PEventState;
    Outcome: LongInt;
    procedure Execute; override;
  end;

procedure TPoller.Execute;
begin
  Outcome:=BasicEventWaitFor(0,Event);
end;

procedure Check(Value: Boolean; const Detail: string);
begin
  If not Value then raise Exception.Create(Detail);
end;

procedure Probe(Timeout: Cardinal; Manual: Boolean; Spurious: Integer);
var E: PEventState; W: TPoller; Started: QWord; Outcome: LongInt;
begin
  E:=BasicEventCreate(nil,Manual,False,'');
  EventProbeWaitError:=22; { EINVAL, before a real pthread call releases mutex. }
  EventProbeSpuriousWaits:=Spurious;
  EventProbeCondWaits:=0;
  Outcome:=BasicEventWaitFor(Timeout,E);
  Check(Outcome=Ord(wrError),'cond error must return wrError');
  Check(EventProbeCondWaits=Spurious+1,'retry only a zero return');
  EventProbeWaitError:=0;
  Check(EventProbeWaiterCount(E)=0,'waiter reference leaked');
  W:=TPoller.Create(True);
  W.Event:=E;
  W.Outcome:=-1;
  W.Start;
  Started:=GetTickCount64;
  while not W.Finished do begin
    Check(GetTickCount64-Started<2000,'mutex left locked');
    Sleep(1);
  end;
  W.WaitFor;
  Check((W.FatalException=nil) and (W.Outcome=Ord(wrTimeout)),'other-thread poll failed');
  W.Free;
  Check(EventProbeWaiterCount(E)=0,'poll waiter reference leaked');
  BasicEventSetEvent(E);
  BasicEventSetEvent(E);
  Check(BasicEventWaitFor(0,E)=Ord(wrSignaled),'event unusable after error');
  If Manual then Check(BasicEventWaitFor(0,E)=Ord(wrSignaled),'manual state lost')
  else Check(BasicEventWaitFor(0,E)=Ord(wrTimeout),'auto coalescing lost');
  BasicEventResetEvent(E);
  Check(BasicEventWaitFor(0,E)=Ord(wrTimeout),'reset after error');
  BasicEventDestroy(E);
end;

var Timeout: Cardinal; Manual: Boolean; I: Integer;
begin
  If ParamStr(1)='finite' then Timeout:=16 else Timeout:=High(Cardinal);
  for Manual:=False to True do
    for I:=0 to 1 do Probe(Timeout,Manual,I*3);
  WriteLn('COND_ERROR_CLEANUP_PASS ',ParamStr(1));
end.
