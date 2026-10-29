program pulse_thread_wakeups;

{$ifdef FPC}{$mode delphi}{$H+}{$else}{$APPTYPE CONSOLE}{$endif}
{$Q-}{$R-}

uses
  {$ifdef FPC}mormot.core.fpcx64mm,{$endif}
  SysUtils, Classes, SyncObjs,
  {$ifdef MSWINDOWS}Windows{$else}UnixType{$endif};

{ Paced workload: compare CPU spent doing identical rounds, not throughput of
  sleeping. Run with tools/pulse_wakeups.py; deliberately no adaptive batching.
  The main loop models WakeMainThread -> event -> CheckSynchronize(0).
  No application code, trading, network or disk logging is involved. }

type
  TCpu = record UserNs, KernelNs: UInt64; end;
  TWorker = class(TThread)
  private
    FId: Integer;
    FLock: TCriticalSection;
    FLog: TStringList;
    procedure Deliver;
  protected
    procedure Execute; override;
  public
    Event: TEvent;
    IssuedRound: LongInt;
    Wakes, Signals, Timeouts, Sent, Delivered, SentBytes, DeliveredBytes: UInt64;
    Digest, SequenceSum: UInt64;
    constructor Create(Id: Integer);
    destructor Destroy; override;
  end;
  TMainWake = class
    Event: TEvent;
    procedure Wake(Sender: TObject);
  end;
  TSignaler = class(TThread)
    procedure Execute; override;
  end;

{$ifdef LINUX}
type
  TRUsage = record
    UserTime, SystemTime: TTimeVal;
    Other: array[0..13] of Int64;
  end;
function GetUsage(Who: Integer; out Usage: TRUsage): Integer; cdecl; external 'c' name 'getrusage';
function LibcClock(ClockId: Integer; out Stamp: TTimeSpec): Integer; cdecl; external 'c' name 'clock_gettime';
{$endif}
{$ifdef MSWINDOWS}
function ReadProcessCycles(Process: THandle; out Cycles: UInt64): BOOL; stdcall;
  external 'kernel32.dll' name 'QueryProcessCycleTime';
function TimeBeginPeriod(Period: Cardinal): Cardinal; stdcall; external 'winmm.dll' name 'timeBeginPeriod';
function TimeEndPeriod(Period: Cardinal): Cardinal; stdcall; external 'winmm.dll' name 'timeEndPeriod';
{$endif}

var
  Workers: array of TWorker;
  Gate, RoundAck: TEvent;
  MainWake: TMainWake;
  Ready, Completed, RoundDone: LongInt;
  Mode: string;
  WorkerCount, Rounds, PeriodMs, ClockReads, LogEvery: Integer;
  UseSleep, UseSync, UseSignal, UseIdle, UseLibcClock: Boolean;
  UsePaced: Boolean;
  TimerResolution: Cardinal;
  MaxDispatchLateNs, LastDispatchNs, MinDispatchGapNs, ShortDispatchGaps: UInt64;

function ReadCpu: TCpu;
{$ifdef MSWINDOWS}
var Created, Exited, Kernel, User: TFileTime;
begin
  If not GetProcessTimes(GetCurrentProcess, Created, Exited, Kernel, User) then RaiseLastOSError;
  Result.UserNs := (UInt64(User.dwHighDateTime) shl 32 or User.dwLowDateTime) * 100;
  Result.KernelNs := (UInt64(Kernel.dwHighDateTime) shl 32 or Kernel.dwLowDateTime) * 100;
{$else}
var Usage: TRUsage;
begin
  If GetUsage(0, Usage) <> 0 then RaiseLastOSError;
  Result.UserNs := UInt64(Usage.UserTime.tv_sec) * 1000000000 + UInt64(Usage.UserTime.tv_usec) * 1000;
  Result.KernelNs := UInt64(Usage.SystemTime.tv_sec) * 1000000000 + UInt64(Usage.SystemTime.tv_usec) * 1000;
{$endif}
end;

function WallNs: UInt64;
{$ifdef MSWINDOWS}
var Counter, Frequency: Int64;
begin
  QueryPerformanceCounter(Counter);
  QueryPerformanceFrequency(Frequency);
  Result := UInt64(Counter div Frequency) * 1000000000 + UInt64(Counter mod Frequency) * 1000000000 div UInt64(Frequency);
{$else}
var Stamp: TTimeSpec;
begin
  If LibcClock(1, Stamp) <> 0 then RaiseLastOSError;
  Result := UInt64(Stamp.tv_sec) * 1000000000 + UInt64(Stamp.tv_nsec);
{$endif}
end;

function ReadTick: UInt64;
begin
  If UseLibcClock then Result := WallNs div 1000000 else Result := GetTickCount64;
end;

procedure TMainWake.Wake(Sender: TObject);
begin
  Event.SetEvent;
end;

constructor TWorker.Create(Id: Integer);
begin
  inherited Create(True);
  FId := Id;
  Event := TEvent.Create(nil, False, False, '');
  FLock := TCriticalSection.Create;
  FLog := TStringList.Create;
end;

destructor TWorker.Destroy;
begin
  inherited Destroy;
  FLog.Free;
  FLock.Free;
  Event.Free;
end;

procedure TWorker.Deliver;
var I: Integer;
begin
  FLock.Acquire;
  try
    Inc(Delivered, FLog.Count);
    for I := 0 to FLog.Count - 1 do Inc(DeliveredBytes, Length(FLog[I]));
    FLog.Clear;
  finally
    FLock.Release;
  end;
end;

procedure TWorker.Execute;
var I, J: Integer; Waited: TWaitResult; Text: string; Tick: UInt64;
begin
  try
    InterlockedIncrement(Ready);
    Gate.WaitFor(INFINITE);
    If UseIdle then begin
      Event.WaitFor(Cardinal(Rounds * PeriodMs));
      Exit;
    end;
    for I := 1 to Rounds do begin
      If UseSleep then Sleep(PeriodMs) else begin
        If UsePaced then Waited := Event.WaitFor(INFINITE) else Waited := Event.WaitFor(PeriodMs);
        case Waited of
          wrSignaled: Inc(Signals);
          wrTimeout: Inc(Timeouts);
        else raise Exception.Create('unexpected event wait result');
        end;
      end;
      Inc(Wakes);
      If UsePaced then begin
        If InterlockedCompareExchange(IssuedRound, 0, 0) <> I then
          raise Exception.Create('input round lost or repeated');
        Inc(SequenceSum, I);
      end;
      for J := 1 to ClockReads do begin
        Tick := ReadTick;
        Digest := Digest xor Tick;
      end;
      If ClockReads <> 0 then Digest := Digest xor UInt64(Trunc(Now * 86400000));
      If (LogEvery <> 0) and (I mod LogEvery = 0) then begin
        Text := 'order=' + IntToStr(FId) + ' step=' + IntToStr(I);
        Inc(Sent);
        Inc(SentBytes, Length(Text));
        FLock.Acquire;
        try
          FLog.Add(Text);
        finally
          FLock.Release;
        end;
        If UseSync then TThread.Synchronize(Self, Deliver) else TThread.Queue(nil, Deliver);
      end;
      If UsePaced then
        If InterlockedIncrement(RoundDone) = I * WorkerCount then RoundAck.SetEvent;
    end;
  finally
    InterlockedIncrement(Completed);
    MainWake.Event.SetEvent;
  end;
end;

procedure TSignaler.Execute;
var I, Step: Integer; Deadline, Current: UInt64;
begin
  Gate.WaitFor(INFINITE);
  If UsePaced then begin
    Deadline := WallNs;
    for Step := 1 to Rounds do begin
      { Do not overwrite a notification before every worker consumed it. }
      while InterlockedCompareExchange(RoundDone, 0, 0) < (Step - 1) * WorkerCount do
        If RoundAck.WaitFor(5000) = wrTimeout then raise Exception.Create('input consumer stalled');
      Inc(Deadline, UInt64(PeriodMs) * 1000000);
      Current := WallNs;
      while Current < Deadline do begin
        Sleep((Deadline - Current + 999999) div 1000000);
        Current := WallNs;
      end;
      If Current - Deadline > MaxDispatchLateNs then MaxDispatchLateNs := Current - Deadline;
      If Step > 1 then begin
        If Current - LastDispatchNs < MinDispatchGapNs then MinDispatchGapNs := Current - LastDispatchNs;
        If Current - LastDispatchNs < UInt64(PeriodMs) * 500000 then Inc(ShortDispatchGaps);
      end;
      LastDispatchNs := Current;
      for I := 0 to High(Workers) do begin
        InterlockedExchange(Workers[I].IssuedRound, Step);
        Workers[I].Event.SetEvent;
      end;
    end;
    Exit;
  end;
  while InterlockedCompareExchange(Completed, 0, 0) < WorkerCount do begin
    Sleep(PeriodMs);
    for I := 0 to High(Workers) do Workers[I].Event.SetEvent;
  end;
end;

procedure Run;
var
  I: Integer;
  FirstCpu, LastCpu: TCpu;
  Started, Elapsed, Wakes, Signals, Timeouts, Logs, CyclesBefore, CyclesAfter: UInt64;
  Signaler: TSignaler;
begin
  If ParamCount <> 4 then raise Exception.Create('usage: MODE WORKERS ROUNDS PERIOD_MS');
  {$ifdef MSWINDOWS}
  If GetEnvironmentVariable('PULSE_WAKE_CPU') <> '' then
    If not SetProcessAffinityMask(GetCurrentProcess, NativeUInt(1) shl StrToInt(GetEnvironmentVariable('PULSE_WAKE_CPU'))) then
      RaiseLastOSError;
  TimerResolution := StrToIntDef(GetEnvironmentVariable('PULSE_WAKE_TIMER_MS'), 0);
  If (TimerResolution <> 0) and (TimeBeginPeriod(TimerResolution) <> 0) then
    raise Exception.Create('timer resolution request failed');
  {$endif}
  Mode := ParamStr(1);
  WorkerCount := StrToInt(ParamStr(2));
  Rounds := StrToInt(ParamStr(3));
  PeriodMs := StrToInt(ParamStr(4));
  If (WorkerCount < 1) or (WorkerCount > 256) or (Rounds < 1) or (Rounds > 10000) or
     (PeriodMs < 1) or (PeriodMs > 1000) then raise Exception.Create('invalid workload size');
  UseIdle := Mode = 'idle';
  UseSleep := Mode = 'sleep';
  UseSync := Mode = 'synchronize';
  UseSignal := Mode = 'signal';
  UsePaced := (Mode = 'paced-event') or (Mode = 'paced-clock') or (Mode = 'paced-queue');
  If UsePaced and (Rounds > 1) then MinDispatchGapNs := High(UInt64);
  UseLibcClock := Mode = 'clock-libc';
  If (Mode = 'clock') or UseLibcClock then ClockReads := 16;
  If (Mode = 'queue') or (Mode = 'queue-heavy') or UseSync then begin
    ClockReads := 2;
    LogEvery := 8;
    If Mode = 'queue-heavy' then LogEvery := 1;
  end;
  If (Mode = 'paced-clock') or (Mode = 'paced-queue') then ClockReads := 2;
  If Mode = 'paced-queue' then LogEvery := 8;
  If not (UseIdle or UseSleep or UseSync or UseSignal or UsePaced or UseLibcClock or (Mode = 'event') or
          (Mode = 'clock') or (Mode = 'queue') or (Mode = 'queue-heavy')) then
    raise Exception.Create('unknown workload');
  Gate := TEvent.Create(nil, True, False, '');
  RoundAck := TEvent.Create(nil, False, False, '');
  MainWake := TMainWake.Create;
  MainWake.Event := TEvent.Create(nil, False, False, '');
  WakeMainThread := MainWake.Wake;
  SetLength(Workers, WorkerCount);
  for I := 0 to High(Workers) do begin
    Workers[I] := TWorker.Create(I);
    Workers[I].Start;
  end;
  Signaler := nil;
  If UseSignal or UsePaced then Signaler := TSignaler.Create(False);
  { Thread creation is a different Pulse family. Let startup settle before
    opening the gate; measure the same finite number of rounds everywhere. }
  Started := WallNs;
  while InterlockedCompareExchange(Ready, 0, 0) < WorkerCount do begin
    Sleep(1);
    If WallNs - Started > 10000000000 then raise Exception.Create('worker startup timed out');
  end;
  Sleep(20);
  CyclesBefore := 0;
  CyclesAfter := 0;
  {$ifdef MSWINDOWS}
  If not ReadProcessCycles(GetCurrentProcess, CyclesBefore) then RaiseLastOSError;
  {$endif}
  FirstCpu := ReadCpu;
  Started := WallNs;
  Gate.SetEvent;
  while InterlockedCompareExchange(Completed, 0, 0) < WorkerCount do begin
    CheckSynchronize(0);
    If InterlockedCompareExchange(Completed, 0, 0) < WorkerCount then MainWake.Event.WaitFor(250);
    If WallNs - Started > UInt64(Rounds * PeriodMs) * 1000000 * 4 + 10000000000 then
      raise Exception.Create('workload did not complete');
  end;
  CheckSynchronize(0);
  Elapsed := WallNs - Started;
  LastCpu := ReadCpu;
  {$ifdef MSWINDOWS}
  If not ReadProcessCycles(GetCurrentProcess, CyclesAfter) then RaiseLastOSError;
  {$endif}
  Wakes := 0;
  Signals := 0;
  Timeouts := 0;
  Logs := 0;
  If Assigned(Signaler) then begin
    Signaler.WaitFor;
    If Assigned(Signaler.FatalException) then raise Exception.Create('signaler failed');
    Signaler.Free;
  end;
  for I := 0 to High(Workers) do begin
    Workers[I].WaitFor;
    If Assigned(Workers[I].FatalException) then raise Exception.Create('worker failed');
    If not UseIdle and (Workers[I].Wakes <> UInt64(Rounds)) then raise Exception.Create('missing wake');
    If UsePaced and (Workers[I].SequenceSum <> UInt64(Rounds) * UInt64(Rounds + 1) div 2) then
      raise Exception.Create('input sequence checksum failed');
    If (LogEvery <> 0) and (Workers[I].Sent <> UInt64(Rounds div LogEvery)) then
      raise Exception.Create('incorrect generated log count');
    If (Workers[I].Sent <> Workers[I].Delivered) or (Workers[I].SentBytes <> Workers[I].DeliveredBytes) then
      raise Exception.Create('lost or damaged log delivery');
    Inc(Wakes, Workers[I].Wakes);
    Inc(Signals, Workers[I].Signals);
    Inc(Timeouts, Workers[I].Timeouts);
    Inc(Logs, Workers[I].Delivered);
    Workers[I].Free;
  end;
  WakeMainThread := nil;
  MainWake.Event.Free;
  MainWake.Free;
  Gate.Free;
  RoundAck.Free;
  WriteLn('PULSE_WAKE mode=', Mode, ' workers=', WorkerCount, ' rounds=', Rounds, ' period_ms=', PeriodMs,
    ' wall_ns=', Elapsed, ' user_ns=', LastCpu.UserNs - FirstCpu.UserNs,
    ' kernel_ns=', LastCpu.KernelNs - FirstCpu.KernelNs, ' wakes=', Wakes,
    ' signals=', Signals, ' timeouts=', Timeouts, ' logs=', Logs,
    ' process_cycles=', CyclesAfter - CyclesBefore, ' timer_ms=', TimerResolution,
    ' dispatch_late_ns=', MaxDispatchLateNs, ' short_gaps=', ShortDispatchGaps,
    ' min_gap_ns=', MinDispatchGapNs, ' verified=1');
end;

begin
  try
    Run;
  except
    on E: Exception do begin
      WriteLn(E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
  {$ifdef MSWINDOWS}
  If TimerResolution <> 0 then TimeEndPeriod(TimerResolution);
  {$endif}
end.
