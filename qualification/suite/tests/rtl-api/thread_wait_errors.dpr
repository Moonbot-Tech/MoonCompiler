program thread_wait_errors;
{$mode delphiunicode}
uses cthreads, Classes, SysUtils, BaseUnix, Dynlibs;
type TWorker = class(TThread)
  procedure Execute; override;
end;
var Gate: PRTLEvent;
procedure TWorker.Execute;
begin
  RTLEventWaitFor(Gate);
  ReturnValue:=63;
end;
type TClockFault = function: LongInt; cdecl;
var W: TWorker; Failed: Boolean; Code: DWord; Err: LongInt;
  Helper: TLibHandle; ClockFault: TClockFault;
begin
  Gate:=RTLEventCreate;
  W:=TWorker.Create(false);
  If GetEnvironmentVariable('MOON_WAIT_FAULT')='clock-error' then begin
    Helper:=LoadLibrary(AnsiString(GetEnvironmentVariable('MOON_WAIT_FAULT_HELPER')));
    If Helper=0 then Halt(10);
    ClockFault:=TClockFault(GetProcedureAddress(Helper,'wait_deny_clock'));
    If not Assigned(ClockFault) then Halt(11);
    If ClockFault<>0 then Halt(12);
  end;
  Failed:=false;
  try
    W.WaitFor(20);
  except
    on E: EThread do Failed:=true;
  end;
  If not Failed then Halt(1);
  If WaitForThreadTerminateEx(W.Handle,20,Code,Err)<>twrError then Halt(2);
  If (Err<>ESysENOSYS) and (Err<>ESysEINVAL) and (Err<>ESysEPERM) then Halt(3);
  RTLEventSetEvent(Gate);
  If W.WaitFor<>63 then Halt(4);
  W.Free;
  RTLEventDestroy(Gate);
  WriteLn('THREAD_WAIT_ERRORS_OK');
end.
