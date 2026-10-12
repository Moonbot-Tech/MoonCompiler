program thread_priority_lifecycle;
{$mode delphi}{$H+}
uses cthreads, SysUtils, Classes, BaseUnix;

function NativeTid: LongInt; cdecl; external 'c' name 'gettid';
function NativeNice(Which, Who: LongInt): LongInt; cdecl; external 'c' name 'getpriority';
function NativeSetNice(Which, Who, Value: LongInt): LongInt; cdecl; external 'c' name 'setpriority';
function NativeFork: LongInt; cdecl; external 'c' name 'fork';
procedure NativeExit(Code: LongInt); cdecl; external 'c' name '_exit';
function NativeCreate(out Id: TThreadID; Attr, Func, Arg: Pointer): LongInt; cdecl; external 'pthread' name 'pthread_create';
function NativeJoin(Id: TThreadID; Value: Pointer): LongInt; cdecl; external 'pthread' name 'pthread_join';
function NativeCancel(Id: TThreadID): LongInt; cdecl; external 'pthread' name 'pthread_cancel';
procedure NativeSleep(Usec: LongInt); cdecl; external 'c' name 'usleep';

procedure Check(Value: Boolean; const Text: string);
begin
  If not Value then raise Exception.Create(Text);
end;

type
  TForkWorker = class(TThread)
    SeenNice: Integer;
    procedure Execute; override;
  end;

procedure TForkWorker.Execute;
begin
  SeenNice := NativeNice(0, 0);
end;

function ForeignEntry(Arg: Pointer): Pointer; cdecl;
var
  Missing, Code: Integer;
begin
  { The first operation must exercise lazy RTL attachment before errno access. }
  Missing := ThreadGetPriority(0);
  Code := fpGetErrno;
  Result := Pointer(1);
  try
    Check((Missing = High(Integer)) and (Code = ESysESRCH), 'foreign first invalid lookup');
    Check(TThread.CurrentThread.ThreadID = GetCurrentThreadID, 'foreign wrapper identity');
    TThread.CurrentThread.Priority := tpLowest;
    Check((NativeNice(0, 0) = 10) and (TThread.CurrentThread.Priority = tpLowest), 'foreign native nice');
    Check(NativeSetNice(0, 0, 12) = 0, 'external renice');
    Check(TThread.CurrentThread.Priority = tpLowest, 'nearest enum for native nice 12');
    Result := nil;
  except
    on E: Exception do Writeln('FOREIGN_FAILURE ', E.Message);
  end;
end;

procedure ForeignBatch;
var
  Ids: array[0..15] of TThreadID;
  Id: TThreadID;
  Value: Pointer;
  I: Integer;
begin
  for I := 0 to High(Ids) do Check(NativeCreate(Ids[I], nil, @ForeignEntry, nil) = 0, 'native create');
  for Id in Ids do begin
    Value := Pointer(2);
    Check(NativeJoin(Id, @Value) = 0, 'native join');
    Check(Value = nil, 'foreign contract');
    Check(ThreadGetPriority(Id) = High(Integer), 'finished native thread removed');
    Check(fpGetErrno = ESysESRCH, 'finished native errno');
  end;
end;

procedure ForkCase(UseLibc, ForeignFirst: Boolean);
var
  Pid, Status, ParentNice: LongInt;
  Worker: TForkWorker;
begin
  ParentNice := NativeNice(0, 0);
  If UseLibc then Pid := NativeFork else Pid := fpFork;
  Check(Pid >= 0, 'fork');
  If Pid = 0 then begin
    try
      { Creates competing first callers before the fork survivor touches RTL. }
      If ForeignFirst then ForeignBatch;
      Check(TThread.CurrentThread.Priority = tpNormal, 'fork inherited normal');
      TThread.CurrentThread.Priority := tpLowest;
      Check((NativeNice(0, 0) = 10) and (TThread.CurrentThread.Priority = tpLowest), 'fork changes child only');
      Worker := TForkWorker.Create(True);
      try
        Worker.Priority := tpIdle;
        Worker.Start;
        Worker.WaitFor;
        Check((Worker.FatalException = nil) and (Worker.SeenNice = 19), 'RTL worker after fork');
      finally
        Worker.Free;
      end;
      NativeExit(0);
    except
      on E: Exception do begin
        Writeln('FORK_FAILURE ', E.Message);
        Flush(Output);
        NativeExit(1);
      end;
    end;
  end;
  Check(fpWaitPid(Pid, @Status, 0) = Pid, 'wait child');
  Check(Status = 0, 'child priority contract');
  Check(NativeNice(0, 0) = ParentNice, 'fork must not renice parent');
end;

var CancelReady: LongInt;
function CancelEntry(Arg: Pointer): Pointer; cdecl;
begin
  { No Pascal exception handler may swallow pthread's forced unwind. }
  If ThreadGetPriority(GetCurrentThreadID) = High(Integer) then Halt(20);
  InterlockedExchange(CancelReady, 1);
  repeat NativeSleep(10000); until False;
  Result := nil;
end;

var
  OriginalMM: TMemoryManager;
  FreeCalls: Integer;
function CheckedFree(P: Pointer): PtrUInt;
begin
  If ThreadGetPriority(GetCurrentThreadID) = High(Integer) then Halt(21);
  Inc(FreeCalls);
  Result := OriginalMM.FreeMem(P);
end;
function CheckedFreeSize(P: Pointer; Size: PtrUInt): PtrUInt;
begin
  If ThreadGetPriority(GetCurrentThreadID) = High(Integer) then Halt(22);
  Inc(FreeCalls);
  Result := OriginalMM.FreeMemSize(P, Size);
end;
function UnusedWorker(P: Pointer): PtrInt;
begin
  Halt(23);
  Result := 0;
end;
procedure FailedCreation;
var
  Hooked: TMemoryManager;
  Id, Handle: TThreadID;
begin
  GetMemoryManager(OriginalMM);
  Hooked := OriginalMM;
  Hooked.FreeMem := CheckedFree;
  Hooked.FreeMemSize := CheckedFreeSize;
  SetMemoryManager(Hooked);
  try
    { Invalid native stack size forces cleanup before pthread_create. }
    Handle := BeginThread(nil, 1, @UnusedWorker, nil, 0, Id);
  finally
    SetMemoryManager(OriginalMM);
  end;
  Check((Handle = 0) and (Id = 0) and (FreeCalls > 0), 'failed creation releases storage without locking out heap callbacks');
end;

var
  Id: TThreadID;
  Started: QWord;
begin
  Check(NativeNice(0, 0) = 0, 'run at native nice zero');
  Check(TThread.CurrentThread.Priority = tpNormal, 'main wrapper getter');
  TThread.CurrentThread.Priority := tpNormal;
  ForkCase(False, False);
  ForkCase(True, False);
  ForkCase(False, True);
  ForkCase(True, True);
  ForeignBatch;
  Check(NativeCreate(Id, nil, @CancelEntry, nil) = 0, 'cancel create');
  Started := GetTickCount64;
  while InterlockedCompareExchange(CancelReady, 0, 0) = 0 do begin
    Check(GetTickCount64 - Started < 2000, 'cancel ready deadline');
    TThread.Yield;
  end;
  Check(NativeCancel(Id) = 0, 'cancel request');
  Check(NativeJoin(Id, nil) = 0, 'cancel join');
  Check(ThreadGetPriority(Id) = High(Integer), 'cancelled entry removed');
  Check(TThread.CurrentThread.Priority = tpNormal, 'registry remains usable');
  FailedCreation;
  Writeln('THREAD_PRIORITY_LIFECYCLE_OK');
end.
