program internal_event_probe;
{$mode delphi}{$H+}
uses cthreads, SysUtils;
procedure Check(Value: Boolean; const Reason: string);
begin If not Value then raise Exception.Create(Reason);end;
var E: PRTLEvent; I: Integer; Started: QWord;
begin
  E:=RTLEventCreate;
  EventProbeClockReads:=0;
  for I:=1 to 100 do begin
    RTLEventSetEvent(E);
    RTLEventWaitFor(E,16);
    RTLEventWaitFor(E,0);
    RTLEventSetEvent(E);
    RTLEventWaitFor(E);
  end;
  Check(EventProbeClockReads=0,'ready/zero/infinite read clock');
  RTLEventSetEvent(E);
  RTLEventSetEvent(E);
  RTLEventWaitFor(E,0);
  Started:=GetTickCount64;
  RTLEventWaitFor(E,16);
  Check(GetTickCount64-Started>=15,'coalescing or early timeout');
  Check(EventProbeClockReads=1,'finite must read one deadline');
  EventProbeFailClock:=True;
  RTLEventWaitFor(E,16);
  Check(EventProbeClockReads=2,'clock failure not reached');
  RTLEventSetEvent(E);
  RTLEventWaitFor(E,16);
  Check(EventProbeClockReads=2,'ready must bypass failed clock');
  EventProbeFailClock:=False;
  RTLEventSetEvent(E);
  RTLEventResetEvent(E);
  Started:=GetTickCount64;
  RTLEventWaitFor(E,16);
  Check(GetTickCount64-Started>=15,'reset did not clear');
  RTLEventDestroy(E);
  WriteLn('INTERNAL_EVENT_PASS');
end.
