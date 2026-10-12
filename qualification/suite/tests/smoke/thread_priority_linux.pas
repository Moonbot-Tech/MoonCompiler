program thread_priority_linux;
{$mode delphi}{$H+}
uses cthreads, SysUtils, Classes, SyncObjs, BaseUnix;
function NativeTid: LongInt; cdecl; external 'c' name 'gettid';
function NativeNice(Which, Who: LongInt): LongInt; cdecl; external 'c' name 'getpriority';
type
  TWorker = class(TThread)
    Ready, Finish: TEvent;
    Tid, InitialNice: LongInt;
    constructor Create;
    destructor Destroy; override;
    procedure Execute; override;
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
  Tid := NativeTid;
  InitialNice := NativeNice(0, 0);
  Ready.SetEvent;
  Finish.WaitFor(5000);
end;
procedure Check(B: Boolean; const Text: string);
begin
  If not B then raise Exception.Create(Text);
end;
var
  A, B: TWorker;
  MainNice, I, LastNice: Integer;
  Started: QWord;
  Denied: Boolean;
begin
  MainNice := NativeNice(0, 0);
  Check(MainNice = 0, 'run priority contract at native nice=0');
  A := TWorker.Create;
  B := TWorker.Create;
  try
    { This runs immediately after pthread_create, before Execute starts. }
    A.Priority := tpLowest;
    Check(A.Priority = tpLowest, 'suspended priority is real');
    Check(B.Priority = tpNormal, 'other thread unchanged');
    A.Start;
    B.Start;
    Check(A.Ready.WaitFor(5000) = wrSignaled, 'A ready');
    Check(B.Ready.WaitFor(5000) = wrSignaled, 'B ready');
    Check((A.InitialNice = 10) and (B.InitialNice = 0), 'Execute starts with selected native nice');
    Check((NativeNice(0, A.Tid) = 10) and (NativeNice(0, B.Tid) = 0), 'external OS query');
    A.Priority := tpIdle;
    Check((NativeNice(0, A.Tid) = 19) and (A.Priority = tpIdle), 'running priority change');
    Denied := False;
    try
      A.Priority := tpNormal;
    except
      on E: EThread do Denied := True;
    end;
    LastNice := NativeNice(0, A.Tid);
    If Denied then begin
      Check((LastNice = 19) and (A.Priority = tpIdle), 'denial must not invent a new state');
      Writeln('PRIORITY_RAISE_DENIED');
    end else Check((LastNice = 0) and (A.Priority = tpNormal), 'privileged restoration');
    Check(NativeNice(0, 0) = MainNice, 'main native priority unchanged');
    Check(not ThreadSetPriority(B.Handle, 21), 'reject invalid raw priority');
    Check(fpGetErrno = ESysEINVAL, 'invalid priority errno');
    Check(not ThreadSetPriority(0, 0), 'reject unknown handle');
    Check(fpGetErrno = ESysESRCH, 'unknown handle errno');
  finally
    A.Free;
    B.Free;
  end;
  { Repeated creation exercises entry teardown and pthread/TID reuse. }
  for I := 1 to 200 do begin
    A := TWorker.Create;
    try
      A.Priority := tpLower;
      A.Start;
      Check(A.Ready.WaitFor(5000) = wrSignaled, 'reuse worker ready');
      Check(A.InitialNice = 5, 'reuse selects new kernel thread');
      A.Finish.SetEvent;
      Started := GetTickCount64;
      while ThreadGetPriority(A.ThreadID) <> High(Integer) do begin
        Check(GetTickCount64 - Started < 2000, 'finished thread teardown deadline');
        TThread.Yield;
      end;
      Denied := False;
      try A.Priority := tpNormal; except on E: EThread do Denied := True; end;
      Check(Denied, 'finished but not joined thread is rejected');
      A.WaitFor;
      Check(A.FatalException = nil, 'worker exception');
      Denied := False;
      try A.Priority := tpNormal; except on E: EThread do Denied := True; end;
      Check(Denied, 'joined handle is not reused');
    finally A.Free; end;
  end;
  Writeln('THREAD_PRIORITY_LINUX_OK');
end.
