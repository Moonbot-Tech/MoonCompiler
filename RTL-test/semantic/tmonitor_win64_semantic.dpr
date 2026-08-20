program tmonitor_win64_semantic;

{ Delphi TMonitor works out of the box on Win64.

  The red form (audit c74fb2eb, Devil dvl-0007): the Win64
  InitSystemThreads never installed any monitor manager, so the manager
  record stayed zeroed and the first TMonitor.Enter jumped through a nil
  callback - EAccessViolation at address 0 on a plain main thread.  Two
  layers repair it: the Win64 thread init installs the inert System
  manager (a clean runtime error 235 instead of the AV when no support
  unit is present), and the portable-dpr contract gains fpwinmonitor
  right after the memory manager - like cthreads on Linux - whose SRW/
  condition-variable manager provides the full Delphi TMonitor contract.
  An -Fa auto-include was measured and rejected: it initializes SysUtils
  before the pinned MM and corrupts the heap at shutdown. }

{$mode delphiunicode}{$H+}

uses
  mormot.core.fpcx64mm,
  fpwinmonitor,
  SysUtils,
  Classes;

var
  Fails: Integer = 0;
  Obj: TObject;
  Counter: Integer = 0;
  WaiterReady: Boolean = False;
  WaiterWoke: Boolean = False;

procedure Check(const Name: string; Cond: Boolean);
begin
  if not Cond then
  begin
    WriteLn('FAIL ', Name);
    Inc(Fails);
  end;
end;

type
  TCountWorker = class(TThread)
  protected
    procedure Execute; override;
  end;
  TPulseWorker = class(TThread)
  protected
    procedure Execute; override;
  end;

procedure TCountWorker.Execute;
var
  i: Integer;
begin
  for i := 1 to 1000 do
  begin
    TMonitor.Enter(Obj);
    try
      Inc(Counter);
    finally
      TMonitor.Exit(Obj);
    end;
  end;
end;

procedure TPulseWorker.Execute;
begin
  { wait until the main thread is inside TMonitor.Wait }
  while not WaiterReady do
    Sleep(1);
  Sleep(20);
  TMonitor.Enter(Obj);
  try
    TMonitor.Pulse(Obj);
  finally
    TMonitor.Exit(Obj);
  end;
end;

var
  W: array[0..3] of TCountWorker;
  P: TPulseWorker;
  i: Integer;
begin
  Obj := TObject.Create;

  { recursive enter and TryEnter on the main thread - the exact audit AV }
  TMonitor.Enter(Obj);
  TMonitor.Enter(Obj);
  Check('tryenter-owned', TMonitor.TryEnter(Obj));
  TMonitor.Exit(Obj);
  TMonitor.Exit(Obj);
  TMonitor.Exit(Obj);

  { contended counting from four threads }
  for i := 0 to 3 do
    W[i] := TCountWorker.Create(False);
  for i := 0 to 3 do
  begin
    W[i].WaitFor;
    W[i].Free;
  end;
  Check('contended-counter', Counter = 4000);

  { wait releases the lock and a pulse wakes it }
  P := TPulseWorker.Create(False);
  TMonitor.Enter(Obj);
  try
    WaiterReady := True;
    WaiterWoke := TMonitor.Wait(Obj, 5000);
  finally
    TMonitor.Exit(Obj);
  end;
  P.WaitFor;
  P.Free;
  Check('wait-pulse', WaiterWoke);

  { a wait with nobody pulsing times out honestly }
  TMonitor.Enter(Obj);
  try
    Check('wait-timeout', not TMonitor.Wait(Obj, 50));
  finally
    TMonitor.Exit(Obj);
  end;

  Obj.Free;
  if Fails <> 0 then
    Halt(1);
  WriteLn('TMONITOR_SEMANTIC_OK');
end.
