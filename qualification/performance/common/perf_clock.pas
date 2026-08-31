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
    Cpu: Integer;
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
function EndDiagnosticPerfStamp(const Started: TPerfStamp): TPerfDelta;
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

{$ifdef LINUX}
type
  { glibc cpu_set_t is 1024 bits on Linux x86-64.  Keep the ABI-shaped type
    local: the RTL's internal cpu_set_t is not part of the public unit API. }
  TLinuxCpuSet = record
    Bits: array[0..15] of QWord;
  end;
  PLinuxCpuSet = ^TLinuxCpuSet;

var
  LinuxReservedCpuSet: TLinuxCpuSet;
  LinuxReservedCpuSetReady: Boolean;

function LinuxSchedGetAffinity(Pid: LongInt; CpuSetSize: SizeUInt;
  Mask: PLinuxCpuSet): LongInt; cdecl; external 'c' name 'sched_getaffinity';
function LinuxSchedSetAffinity(Pid: LongInt; CpuSetSize: SizeUInt;
  Mask: PLinuxCpuSet): LongInt; cdecl; external 'c' name 'sched_setaffinity';
function LinuxSchedGetCpu: LongInt; cdecl; external 'c' name 'sched_getcpu';

function LinuxCurrentCpu: Integer;
begin
  Result := LinuxSchedGetCpu;
  If Result < 0 then
    RaiseLastOSError;
end;

function LinuxCpuSetContains(const CpuSet: TLinuxCpuSet; Cpu: Integer): Boolean;
begin
  Result := (Cpu >= 0) and (Cpu < SizeOf(CpuSet) * 8) and
    ((CpuSet.Bits[Cpu div 64] and (QWord(1) shl (Cpu mod 64))) <> 0);
end;

function LinuxReservedCpuCount: Integer;
var
  Cpu: Integer;
begin
  Result := 0;
  for Cpu := 0 to SizeOf(LinuxReservedCpuSet) * 8 - 1 do
    If LinuxCpuSetContains(LinuxReservedCpuSet, Cpu) then
      Inc(Result);
end;

procedure EnsureLinuxReservedCpuSet;
begin
  If LinuxReservedCpuSetReady then
    Exit;
  FillChar(LinuxReservedCpuSet, SizeOf(LinuxReservedCpuSet), 0);
  If LinuxSchedGetAffinity(0, SizeOf(LinuxReservedCpuSet),
    @LinuxReservedCpuSet) <> 0 then
    RaiseLastOSError;
  If LinuxReservedCpuCount = 0 then
    raise EAbort.Create('Linux Pulse affinity set is empty');
  LinuxReservedCpuSetReady := True;
end;

function LinuxReservedCpuAt(Ordinal: Integer): Integer;
var
  Cpu, Seen: Integer;
begin
  If Ordinal < 0 then
    raise EArgumentOutOfRangeException.Create('worker CPU ordinal is negative');
  EnsureLinuxReservedCpuSet;
  Seen := 0;
  for Cpu := 0 to SizeOf(LinuxReservedCpuSet) * 8 - 1 do
  begin
    If not LinuxCpuSetContains(LinuxReservedCpuSet, Cpu) then
      Continue;
    If Seen = Ordinal then
    begin
      Result := Cpu;
      Exit;
    end;
    Inc(Seen);
  end;
  raise EAbort.CreateFmt('worker CPU %d is unavailable', [Ordinal]);
end;

procedure LinuxPinCurrentThread(Cpu: Integer);
var
  CpuSet: TLinuxCpuSet;
begin
  If not LinuxCpuSetContains(LinuxReservedCpuSet, Cpu) then
    raise EAbort.CreateFmt('CPU %d is outside the reserved Pulse set', [Cpu]);
  FillChar(CpuSet, SizeOf(CpuSet), 0);
  CpuSet.Bits[Cpu div 64] := QWord(1) shl (Cpu mod 64);
  If LinuxSchedSetAffinity(0, SizeOf(CpuSet), @CpuSet) <> 0 then
    RaiseLastOSError;
  If LinuxCurrentCpu <> Cpu then
    raise EAbort.CreateFmt('Linux affinity did not pin current thread to CPU %d',
      [Cpu]);
end;
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
  {$ifdef LINUX}
begin
  { Capture taskset's process reservation before narrowing the main thread;
    child workers inherit the narrow mask but restore their own reserved CPU. }
  EnsureLinuxReservedCpuSet;
  Result := LinuxReservedCpuAt(LinuxReservedCpuCount - 1);
  LinuxPinCurrentThread(Result);
end;
  {$else}
begin
  Result := -1;
end;
  {$endif}
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
  {$ifdef LINUX}
begin
  Result := LinuxReservedCpuAt(Ordinal);
  LinuxPinCurrentThread(Result);
end;
  {$else}
begin
  Result := -1;
end;
  {$endif}
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
  {$ifdef LINUX}
begin
  If Count < 0 then
    Exit(False);
  EnsureLinuxReservedCpuSet;
  Result := LinuxReservedCpuCount >= Count;
end;
  {$else}
begin
  Result := Count >= 0;
end;
  {$endif}
{$endif}

function BeginPerfStamp: TPerfStamp;
begin
  Result.WallNs := ReadWallNs;
  Result.ThreadCpuNs := ReadThreadCpuNs;
  Result.Tsc := ReadTscStart;
  Result.Cpu := -1;
  {$ifdef LINUX}
  Result.Cpu := LinuxCurrentCpu;
  {$endif}
end;

function EndPerfStamp(const Started: TPerfStamp): TPerfDelta;
var
  StoppedTsc, StoppedCpu, StoppedWall: UInt64;
  {$ifdef LINUX}
  StoppedCpuId: Integer;
  {$endif}
begin
  StoppedTsc := ReadTscStop;
  {$ifdef LINUX}
  StoppedCpuId := LinuxCurrentCpu;
  If StoppedCpuId <> Started.Cpu then
    raise EAbort.CreateFmt('benchmark CPU migration detected: %d -> %d',
      [Started.Cpu, StoppedCpuId]);
  {$endif}
  StoppedCpu := ReadThreadCpuNs;
  StoppedWall := ReadWallNs;
  Result.TscTicks := StoppedTsc - Started.Tsc;
  Result.ThreadCpuNs := StoppedCpu - Started.ThreadCpuNs;
  Result.WallNs := StoppedWall - Started.WallNs;
end;

function EndDiagnosticPerfStamp(const Started: TPerfStamp): TPerfDelta;
var
  StoppedTsc, StoppedCpu, StoppedWall: UInt64;
  {$ifdef LINUX}
  StoppedCpuId: Integer;
  {$endif}
begin
  { Correctness workloads report timing only as provenance.  Scheduler
    migration must not turn a valid semantic run into a benchmark failure. }
  StoppedTsc := ReadTscStop;
  {$ifdef LINUX}
  StoppedCpuId := LinuxCurrentCpu;
  {$endif}
  StoppedCpu := ReadThreadCpuNs;
  StoppedWall := ReadWallNs;
  Result.TscTicks := StoppedTsc - Started.Tsc;
  {$ifdef LINUX}
  { A cross-CPU TSC delta is not a trustworthy diagnostic value on every
    supported x86-64 machine.  Zero marks it unavailable without hiding the
    wall and thread-CPU measurements. }
  If StoppedCpuId <> Started.Cpu then
    Result.TscTicks := 0;
  {$endif}
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
