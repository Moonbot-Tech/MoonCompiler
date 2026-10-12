program thread_priority_best_effort;
{$APPTYPE CONSOLE}
{$IFDEF FPC}{$mode delphi}{$H+}{$ENDIF}
uses
{$IFDEF UNIX}cthreads, BaseUnix,{$ELSE}Windows,{$ENDIF}
  SysUtils, Classes, SyncObjs;

{$IFDEF UNIX}
function NativeTid: LongInt; cdecl; external 'c' name 'gettid';
function NativeNice(Which, Who: LongInt): LongInt; cdecl; external 'c' name 'getpriority';
{$ENDIF}

type
  TWorker = class(TThread)
    Ready, Finish: TEvent;
    Tid, ActualPriority, Payload, Cleanup, Response: Integer;
    constructor Create;
    destructor Destroy; override;
    procedure Execute; override;
  end;

procedure Check(Value: Boolean; const Text: string);
begin
  If not Value then raise Exception.Create(Text);
end;

constructor TWorker.Create;
begin
  Ready := TEvent.Create(nil, True, False, '');
  Finish := TEvent.Create(nil, True, False, '');
  inherited Create(True);
end;

destructor TWorker.Destroy;
begin
  Finish.SetEvent;
  inherited;
  Ready.Free;
  Finish.Free;
end;

procedure TWorker.Execute;
begin
{$IFDEF UNIX}
  Tid := NativeTid;
{$ENDIF}
  try
    try
      Payload := 6 * 7;
    finally
      { A refused restoration must not skip application cleanup in finally. }
      Priority := tpNormal;
      Cleanup := Payload + 1;
    end;
    Response := Cleanup * 2;
  finally
{$IFDEF UNIX}
    ActualPriority := NativeNice(0, 0);
{$ELSE}
    ActualPriority := GetThreadPriority(GetCurrentThread);
{$ENDIF}
    Ready.SetEvent;
    Finish.WaitFor(5000);
  end;
end;

var
  Worker: TWorker;
  MainPriority: Integer;
{$IFDEF UNIX}
  Denied: Boolean;
  Code: Integer;
{$ENDIF}
begin
{$IFDEF UNIX}
  MainPriority := NativeNice(0, 0);
{$ELSE}
  MainPriority := GetThreadPriority(GetCurrentThread);
{$ENDIF}
  Worker := TWorker.Create;
  try
    Worker.Priority := tpIdle;
    Worker.Start;
    Check(Worker.Ready.WaitFor(5000) = wrSignaled, 'worker ready');
{$IFDEF STAND_REPORT}
    Writeln('RESTORE payload=', Worker.Payload, ' cleanup=', Worker.Cleanup,
      ' response=', Worker.Response, ' actual=', Worker.ActualPriority);
{$ENDIF}
{$IFDEF UNIX}
    Check(NativeNice(0, Worker.Tid) = Worker.ActualPriority, 'independent native getter');
    Denied := not ThreadSetPriority(Worker.ThreadID, 0);
    Code := fpGetErrno;
    If Denied then begin
      Check((Code = ESysEACCES) or (Code = ESysEPERM), 'native refusal errno');
      Check((Worker.ActualPriority = 19) and (Worker.Priority = tpIdle), 'refused restore keeps actual nice 19');
    end else Check((Worker.ActualPriority = 0) and (Worker.Priority = tpNormal), 'privileged restore reaches nice zero');
    If ParamStr(1) = '--deny' then Check(Denied, 'expected unprivileged refusal');
    If ParamStr(1) = '--allow' then Check(not Denied, 'expected privileged restoration');
    Check(NativeNice(0, 0) = MainPriority, 'main nice unchanged');
{$ELSE}
    Check((Worker.ActualPriority = THREAD_PRIORITY_NORMAL) and (Worker.Priority = tpNormal), 'Windows restoration');
    Check(GetThreadPriority(GetCurrentThread) = MainPriority, 'main priority unchanged');
{$ENDIF}
    Worker.Finish.SetEvent;
    Worker.WaitFor;
    Check(Worker.FatalException = nil, 'restoration must not raise in Execute');
    Check((Worker.Payload = 42) and (Worker.Cleanup = 43) and (Worker.Response = 86), 'cleanup and response must execute');
    Worker.Priority := tpNormal;
  finally
    Worker.Free;
  end;
  Writeln('THREAD_PRIORITY_BEST_EFFORT_OK');
end.
