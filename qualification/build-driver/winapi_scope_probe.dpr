program winapi_scope_probe;

uses
  Winapi.Windows, Winapi.Messages, Winapi.WinSvc, Winapi.PsAPI, Winapi.TlHelp32,
  System.SysUtils, winapi_plain, winapi_generic;

var
  Time: Winapi.Windows.TFileTime;
  Message: Winapi.Messages.TMessage;
  Status: Winapi.WinSvc.TServiceStatus;
  Counters: Winapi.PsAPI.TProcessMemoryCounters;
  Thread: Winapi.TlHelp32.TThreadEntry32;
  Entry: Winapi.WinSvc.TServiceTableEntry;
  Generic: TApiValue<Integer>;
begin
  ChangeTime(Time);
  ChangeMessage(Message);
  ChangeStatus(Status);
  ChangeCounters(Counters);
  ChangeThread(Thread);
  Entry.lpServiceName := PWideChar('namespace');
  If (Time.dwLowDateTime <> 37) or (Message.Msg <> WM_USER + 17) or
     (Status.dwCurrentState <> 7) or (Counters.cb <> SizeOf(Counters)) or
     (Thread.dwSize <> SizeOf(Thread)) or (Generic.CounterSize(Counters) <> SizeOf(Counters)) or
     (SizeOf(Char) <> 2) or (SizeOf(String) <> SizeOf(Pointer)) then
    Halt(1);
  {$IFDEF RELEASE}
  {$IFDEF DEBUG}Halt(2);{$ENDIF}
  {$IFOPT C+}Halt(3);{$ENDIF}
  {$ELSE}
  {$IFNDEF DEBUG}Halt(4);{$ENDIF}
  {$IFOPT C-}Halt(5);{$ENDIF}
  {$ENDIF}
  Writeln('WINAPI_SCOPE_PASS');
end.
