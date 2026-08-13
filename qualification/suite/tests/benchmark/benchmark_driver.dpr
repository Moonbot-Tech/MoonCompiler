program benchmark_driver;

{$ifndef FPC}
  {$APPTYPE CONSOLE}
{$endif}

uses
  {$ifdef FPC}
  SysUtils,
    {$ifdef LINUX}
  Linux,
  UnixType,
    {$endif}
    {$ifdef MSWINDOWS}
  Windows,
    {$endif}
  {$else}
  System.SysUtils,
  Winapi.Windows,
  {$endif}
  benchmark_portable in 'benchmark_portable.pas';

{$ifdef MSWINDOWS}
var
  TimerFrequency: Int64;
{$endif}

function ReadTimeNs: UInt64;
{$ifdef MSWINDOWS}
var
  Counter: Int64;
begin
  QueryPerformanceCounter(Counter);
  Result := UInt64(Counter div TimerFrequency) * UInt64(1000000000) +
    UInt64(Counter mod TimerFrequency) * UInt64(1000000000) div
    UInt64(TimerFrequency);
end;
{$else}
var
  Timestamp: UnixType.TTimeSpec;
begin
  if clock_gettime(CLOCK_MONOTONIC_RAW, @Timestamp) <> 0 then
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

function ReadThreadCpuTimeNs: UInt64;
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

function ReadPositive(const Value, Name: string): Integer;
begin
  Result := StrToInt(Value);
  if Result <= 0 then
    raise EArgumentException.Create(Name + ' must be positive');
end;

var
  Name: string;
  Iterations, Samples, Sample, WarmupIterations: Integer;
  Started, StartedCpu, ElapsedNs, CpuNs: UInt64;
  Digest: UInt64;
begin
  try
    {$ifdef MSWINDOWS}
    if not QueryPerformanceFrequency(TimerFrequency) then
      RaiseLastOSError;
    {$endif}
    if ParamCount <> 3 then
      raise EArgumentException.Create(
        'usage: benchmark_driver NAME ITERATIONS SAMPLES');
    Name := ParamStr(1);
    Iterations := ReadPositive(ParamStr(2), 'iterations');
    Samples := ReadPositive(ParamStr(3), 'samples');
    WarmupIterations := Iterations div 16;
    if WarmupIterations = 0 then
      WarmupIterations := 1;
    Digest := RunBenchmark(Name, WarmupIterations);
    WriteLn('BENCH_WARMUP name=', Name, ' iterations=', WarmupIterations,
      ' digest=', IntToHex(Digest, 16));
    for Sample := 1 to Samples do
    begin
      Started := ReadTimeNs;
      StartedCpu := ReadThreadCpuTimeNs;
      Digest := RunBenchmark(Name, Iterations);
      CpuNs := ReadThreadCpuTimeNs - StartedCpu;
      ElapsedNs := ReadTimeNs - Started;
      if (ElapsedNs = 0) or (CpuNs = 0) then
        raise EAbort.Create('sample duration is below timer resolution');
      WriteLn('BENCH_SAMPLE name=', Name, ' sample=', Sample,
        ' iterations=', Iterations, ' elapsed_ns=', ElapsedNs,
        ' cpu_ns=', CpuNs, ' digest=', IntToHex(Digest, 16));
    end;
    WriteLn('BENCH_DONE name=', Name, ' samples=', Samples);
  except
    on E: Exception do
    begin
      WriteLn('BENCH_FAIL ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
