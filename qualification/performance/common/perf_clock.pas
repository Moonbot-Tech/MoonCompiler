unit perf_clock;

{$ifdef FPC}
  {$mode delphi}{$H+}
  {$asmmode intel}
{$endif}

interface

type
  TPerfStamp = record
    WallNs: UInt64;
    ThreadCpuNs: UInt64;
    Tsc: UInt64;
  end;

  TPerfDelta = record
    WallNs: UInt64;
    ThreadCpuNs: UInt64;
    TscTicks: UInt64;
  end;

procedure InitializePerfClock;
function PinBenchmarkThread: Integer;
function CanPinWorkerThreads(Count: Integer): Boolean;
function PinWorkerThread(Ordinal: Integer): Integer;
function BeginPerfStamp: TPerfStamp;
function EndPerfStamp(const Started: TPerfStamp): TPerfDelta;
function MeasureTscOverhead(Iterations: Integer): UInt64;

implementation

uses
  {$ifdef FPC}
  SysUtils
    {$ifdef LINUX}
  , Linux
  , UnixType
    {$endif}
    {$ifdef MSWINDOWS}
  , Windows
    {$endif}
  {$else}
  System.SysUtils,
  Winapi.Windows
  {$endif};

{$ifdef MSWINDOWS}
var
  TimerFrequency: Int64;
{$endif}

function ReadWallNs: UInt64;
{$ifdef MSWINDOWS}
var
  Counter: Int64;
begin
  If not QueryPerformanceCounter(Counter) then
    RaiseLastOSError;
  Result := UInt64(Counter div TimerFrequency) * UInt64(1000000000) +
    UInt64(Counter mod TimerFrequency) * UInt64(1000000000) div
    UInt64(TimerFrequency);
end;
{$else}
var
  Timestamp: UnixType.TTimeSpec;
begin
  If clock_gettime(CLOCK_MONOTONIC_RAW, @Timestamp) <> 0 then
    RaiseLastOSError;
  Result := UInt64(Timestamp.tv_sec) * UInt64(1000000000) +
    UInt64(Timestamp.tv_nsec);
end;
{$endif}

{$ifdef MSWINDOWS}
function FileTimeTicks(const Value: TFileTime): UInt64;
begin
  Result := UInt64(Value.dwLowDateTime) or
    (UInt64(Value.dwHighDateTime) shl 32);
end;
{$endif}

function ReadThreadCpuNs: UInt64;
{$ifdef MSWINDOWS}
var
  CreationTime, ExitTime, KernelTime, UserTime: TFileTime;
begin
  If not GetThreadTimes(GetCurrentThread, CreationTime, ExitTime, KernelTime,
    UserTime) then
    RaiseLastOSError;
  Result := (FileTimeTicks(KernelTime) + FileTimeTicks(UserTime)) * 100;
end;
{$else}
var
  Timestamp: UnixType.TTimeSpec;
begin
  If clock_gettime(CLOCK_THREAD_CPUTIME_ID, @Timestamp) <> 0 then
    RaiseLastOSError;
  Result := UInt64(Timestamp.tv_sec) * UInt64(1000000000) +
    UInt64(Timestamp.tv_nsec);
end;
{$endif}

function ReadTscStart: UInt64;
{$ifdef FPC}nostackframe; assembler; asm{$else}asm .noframe{$endif}
        lfence
        rdtsc
        shl     rdx, 32
        or      rax, rdx
end;

function ReadTscStop: UInt64;
{$ifdef FPC}nostackframe; assembler; asm{$else}asm .noframe{$endif}
        rdtscp
        shl     rdx, 32
        or      rax, rdx
        lfence
end;

procedure InitializePerfClock;
begin
  {$ifdef MSWINDOWS}
  If not QueryPerformanceFrequency(TimerFrequency) then
    RaiseLastOSError;
  {$endif}
end;

function PinBenchmarkThread: Integer;
{$ifdef MSWINDOWS}
var
  ProcessMask, SystemMask, SelectedMask: DWORD_PTR;
begin
  If not GetProcessAffinityMask(GetCurrentProcess, ProcessMask, SystemMask) then
    RaiseLastOSError;
  If ProcessMask = 0 then
    raise EAbort.Create('process affinity mask is empty');
  Result := 0;
  SelectedMask := ProcessMask;
  while (SelectedMask shr 1) <> 0 do
  begin
    Inc(Result);
    SelectedMask := SelectedMask shr 1;
  end;
  SelectedMask := DWORD_PTR(1) shl Result;
  If SetThreadAffinityMask(GetCurrentThread, SelectedMask) = 0 then
    RaiseLastOSError;
end;
{$else}
begin
  { Linux qualification pins the process with taskset before program start. }
  Result := -1;
end;
{$endif}

function PinWorkerThread(Ordinal: Integer): Integer;
{$ifdef MSWINDOWS}
var
  ProcessMask, SystemMask, CandidateMask: DWORD_PTR;
  Cpu, Seen: Integer;
begin
  If Ordinal < 0 then
    raise EArgumentOutOfRangeException.Create('worker CPU ordinal is negative');
  If not GetProcessAffinityMask(GetCurrentProcess, ProcessMask, SystemMask) then
    RaiseLastOSError;
  Seen := 0;
  for Cpu := 0 to SizeOf(DWORD_PTR) * 8 - 1 do
  begin
    CandidateMask := DWORD_PTR(1) shl Cpu;
    If (ProcessMask and CandidateMask) = 0 then
      Continue;
    If Seen = Ordinal then
    begin
      If SetThreadAffinityMask(GetCurrentThread, CandidateMask) = 0 then
        RaiseLastOSError;
      Result := Cpu;
      Exit;
    end;
    Inc(Seen);
  end;
  raise EAbort.CreateFmt('worker CPU %d is unavailable', [Ordinal]);
end;
{$else}
begin
  { Linux qualification pins worker placement outside the process. }
  Result := -1;
end;
{$endif}

function CanPinWorkerThreads(Count: Integer): Boolean;
{$ifdef MSWINDOWS}
var
  ProcessMask, SystemMask, CandidateMask: DWORD_PTR;
  Cpu, Available: Integer;
begin
  If Count < 0 then
    Exit(False);
  If not GetProcessAffinityMask(GetCurrentProcess, ProcessMask, SystemMask) then
    RaiseLastOSError;
  Available := 0;
  for Cpu := 0 to SizeOf(DWORD_PTR) * 8 - 1 do
  begin
    CandidateMask := DWORD_PTR(1) shl Cpu;
    If (ProcessMask and CandidateMask) <> 0 then
      Inc(Available);
  end;
  Result := Available >= Count;
end;
{$else}
begin
  { Linux placement is controlled by the qualification runner. }
  Result := Count >= 0;
end;
{$endif}

function BeginPerfStamp: TPerfStamp;
begin
  Result.WallNs := ReadWallNs;
  Result.ThreadCpuNs := ReadThreadCpuNs;
  Result.Tsc := ReadTscStart;
end;

function EndPerfStamp(const Started: TPerfStamp): TPerfDelta;
var
  StoppedTsc, StoppedCpu, StoppedWall: UInt64;
begin
  StoppedTsc := ReadTscStop;
  StoppedCpu := ReadThreadCpuNs;
  StoppedWall := ReadWallNs;
  Result.TscTicks := StoppedTsc - Started.Tsc;
  Result.ThreadCpuNs := StoppedCpu - Started.ThreadCpuNs;
  Result.WallNs := StoppedWall - Started.WallNs;
end;

function MeasureTscOverhead(Iterations: Integer): UInt64;
var
  I: Integer;
  Started, Stopped, Delta: UInt64;
begin
  Result := High(UInt64);
  for I := 1 to Iterations do
  begin
    Started := ReadTscStart;
    Stopped := ReadTscStop;
    Delta := Stopped - Started;
    If Delta < Result then
      Result := Delta;
  end;
end;

end.
