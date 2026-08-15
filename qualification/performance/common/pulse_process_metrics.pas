unit pulse_process_metrics;

{$ifdef FPC}
  {$mode delphi}{$H+}
{$endif}

interface

function PulseReadProcessCpuNs: UInt64;
function PulseReadThreadCycles: UInt64;

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
function PulseQueryThreadCycleTime(ThreadHandle: THandle;
  out CycleTime: UInt64): BOOL; stdcall; external 'kernel32.dll'
  name 'QueryThreadCycleTime';

function FileTimeTicks(const Value: TFileTime): UInt64;
begin
  Result := UInt64(Value.dwLowDateTime) or
    (UInt64(Value.dwHighDateTime) shl 32);
end;
{$endif}

function PulseReadProcessCpuNs: UInt64;
{$ifdef MSWINDOWS}
var
  CreationTime, ExitTime, KernelTime, UserTime: TFileTime;
begin
  If not GetProcessTimes(GetCurrentProcess, CreationTime, ExitTime, KernelTime,
    UserTime) then
    RaiseLastOSError;
  Result := (FileTimeTicks(KernelTime) + FileTimeTicks(UserTime)) * 100;
end;
{$else}
var
  Timestamp: UnixType.TTimeSpec;
begin
  If clock_gettime(CLOCK_PROCESS_CPUTIME_ID, @Timestamp) <> 0 then
    RaiseLastOSError;
  Result := UInt64(Timestamp.tv_sec) * UInt64(1000000000) +
    UInt64(Timestamp.tv_nsec);
end;
{$endif}

function PulseReadThreadCycles: UInt64;
{$ifdef MSWINDOWS}
begin
  If not PulseQueryThreadCycleTime(GetCurrentThread, Result) then
    RaiseLastOSError;
end;
{$else}
begin
  { Linux exact cycles are collected around the process by perf stat. }
  Result := 0;
end;
{$endif}

end.
