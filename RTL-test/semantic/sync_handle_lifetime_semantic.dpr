program sync_handle_lifetime_semantic;

{$mode delphi}{$H+}
{ %TARGET=win64 }

uses
  mormot.core.fpcx64mm,
  System.SysUtils, System.SyncObjs, System.Threading, Windows;

function GetProcessHandleCount(Process: THandle; var Count: DWORD): BOOL; stdcall;
  external 'kernel32.dll' name 'GetProcessHandleCount';

procedure Check(ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    raise Exception.Create('SYNC_HANDLE_LIFETIME_FAIL: '+AMessage);
end;

function HandleCount: DWORD;
begin
  Check(GetProcessHandleCount(GetCurrentProcess,Result),'GetProcessHandleCount');
end;

procedure ExerciseHandles;
var
  Pool: TThreadPool;
  Semaphore, OpenedSemaphore: TSemaphore;
  Mutex, OpenedMutex: TMutex;
  Name: string;
  Failed: Boolean;
begin
  Pool:=TThreadPool.Create;
  Pool.Free;
  Semaphore:=TSemaphore.Create;
  Semaphore.Free;
  Mutex:=TMutex.Create;
  Mutex.Free;
  Name:='MoonCompiler-SyncLifetime-'+IntToStr(GetCurrentProcessId);
  Semaphore:=TSemaphore.Create(nil,0,1,Name+'-semaphore');
  try
    OpenedSemaphore:=TSemaphore.Create(SEMAPHORE_ALL_ACCESS,False,Name+'-semaphore');
    try
      Semaphore.Release;
      Check(OpenedSemaphore.WaitFor(0)=wrSignaled,'opened semaphore shares token');
      Check(Semaphore.WaitFor(0)=wrTimeout,'semaphore token consumed');
    finally
      OpenedSemaphore.Free;
    end;
  finally
    Semaphore.Free;
  end;
  Mutex:=TMutex.Create(nil,False,Name+'-mutex');
  try
    OpenedMutex:=TMutex.Create(MUTEX_ALL_ACCESS,False,Name+'-mutex');
    try
      Check(OpenedMutex.WaitFor(0)=wrSignaled,'opened mutex');
      OpenedMutex.Release;
    finally
      OpenedMutex.Free;
    end;
  finally
    Mutex.Free;
  end;
  Failed:=False;
  try
    Semaphore:=TSemaphore.Create(SEMAPHORE_ALL_ACCESS,False,Name+'-missing');
    Semaphore.Free;
  except
    on EOSError do Failed:=True;
  end;
  Check(Failed,'open missing semaphore raises');
  Failed:=False;
  try
    Mutex:=TMutex.Create(MUTEX_ALL_ACCESS,False,Name+'-missing');
    Mutex.Free;
  except
    on EOSError do Failed:=True;
  end;
  Check(Failed,'open missing mutex raises');
end;

var
  BeforeCount, AfterCount: DWORD;
  I: Integer;
  Pool: TThreadPool;
begin
  ExerciseHandles;
  BeforeCount:=HandleCount;
  for I:=1 to 100 do
    begin
    Pool:=TThreadPool.Create;
    Pool.Free;
    end;
  AfterCount:=HandleCount;
  WriteLn('pool handles before=',BeforeCount,' after=',AfterCount);
  Check(AfterCount<=BeforeCount+1,'100 pools leaked handles');
  BeforeCount:=HandleCount;
  for I:=1 to 100 do
    ExerciseHandles;
  AfterCount:=HandleCount;
  WriteLn('handles before=',BeforeCount,' after=',AfterCount);
  Check(AfterCount<=BeforeCount+1,'100 pools/semaphores/mutexes leaked handles');
  WriteLn('SYNC_HANDLE_LIFETIME_PASS');
end.
