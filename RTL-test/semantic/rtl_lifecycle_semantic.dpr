program rtl_lifecycle_semantic;

{$mode delphi}{$H+}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  {$endif UNIX}
  SysUtils,
  Classes,
  rtl_lifecycle_probe in 'RTL-test/semantic/support/rtl_lifecycle_probe.pas';

threadvar
  ThreadLocalValue: Integer;

type
  TLifecycleThread = class(TThread)
  protected
    procedure Execute; override;
  end;

procedure Check(ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    raise Exception.Create('RTL_LIFECYCLE_FAIL: ' + AMessage);
end;

procedure TLifecycleThread.Execute;
var
  LocalCritical: TRTLCriticalSection;
  LocalMonitor: TObject;
begin
  ThreadLocalValue := 73;
  InitCriticalSection(LocalCritical);
  try
    EnterCriticalSection(LocalCritical);
    LeaveCriticalSection(LocalCritical);
  finally
    DoneCriticalSection(LocalCritical);
  end;
  LocalMonitor := TObject.Create;
  try
    TMonitor.Enter(LocalMonitor);
    TMonitor.Exit(LocalMonitor);
  finally
    LocalMonitor.Free;
  end;
  if ThreadLocalValue <> 73 then
    raise Exception.Create('threadvar lifecycle');
end;

procedure Run;
var
  Thread: TLifecycleThread;
begin
  Check(InitializationPassed, 'unit initialization');
  ThreadLocalValue := 19;
  Thread := TLifecycleThread.Create(True);
  try
    Thread.FreeOnTerminate := False;
    Thread.Start;
    Thread.WaitFor;
    Check(Thread.FatalException = nil, 'thread init/final');
    Check(ThreadLocalValue = 19, 'main threadvar preserved');
  finally
    Thread.Free;
  end;
end;

begin
  try
    Run;
    WriteLn('RTL_LIFECYCLE_SEMANTIC_PASS');
  except
    on E: Exception do
    begin
      WriteLn(ErrOutput, E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
