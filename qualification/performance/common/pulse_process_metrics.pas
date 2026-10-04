unit pulse_process_metrics;

{$ifdef FPC}
  {$mode delphi}{$H+}
{$endif}

interface

type
  TPulseCoreCounter = record
    Cycles: UInt64;
    EnabledTime: UInt64;
    RunningTime: UInt64;
    ContextSwitches: UInt64;
    Raw: array[0..3] of UInt64;
  end;

  TPulseMemoryMetrics = record
    ResidentBytes: UInt64;
    PrivateBytes: UInt64;
    PeakResidentBytes: UInt64;
    PageFaultCount: UInt64;
  end;

procedure PulseInitializeCoreCounter(Required: Boolean; PmuType: Cardinal = 0);
procedure PulseShutdownCoreCounter;
function PulseReadCoreCounter: TPulseCoreCounter;
procedure PulseInitializeThreadCoreCounter;
procedure PulseShutdownThreadCoreCounter;
procedure PulseStartThreadCoreCounter(out Started: TPulseCoreCounter);
procedure PulseStopThreadCoreCounter(const Started: TPulseCoreCounter);
function PulseCoreCounterName: string;
function PulseCoreCounterInProcess: Boolean;
procedure PulseWriteRawEvents(const Started, Stopped: TPulseCoreCounter);
function PulseReadTraceTime100ns: UInt64;
function PulseReadProcessCpuNs: UInt64;
function PulseReadThreadCycles: UInt64;
function PulseReadProcessCycles: UInt64;
function PulseReadProcessorIdleCycles(Processor: Integer): UInt64;
function PulseReadMemoryMetrics: TPulseMemoryMetrics;

implementation

uses
  {$ifdef FPC}
  SysUtils
    {$ifdef LINUX}
  , BaseUnix
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
procedure PulseGetSystemTimePreciseAsFileTime(out SystemTimeAsFileTime:
  TFileTime); stdcall; external 'kernel32.dll' name
  'GetSystemTimePreciseAsFileTime';
function PulseQueryThreadCycleTime(ThreadHandle: THandle;
  out CycleTime: UInt64): BOOL; stdcall; external 'kernel32.dll'
  name 'QueryThreadCycleTime';
function PulseQueryProcessCycleTime(ProcessHandle: THandle;
  out CycleTime: UInt64): BOOL; stdcall; external 'kernel32.dll'
  name 'QueryProcessCycleTime';
function PulseQueryIdleProcessorCycleTime(var BufferLength: Cardinal;
  ProcessorIdleCycleTime: Pointer): BOOL; stdcall; external 'kernel32.dll'
  name 'QueryIdleProcessorCycleTime';

type
  TPulseProcessMemoryCounters = record
    Size: DWORD;
    PageFaultCount: DWORD;
    PeakWorkingSetSize: NativeUInt;
    WorkingSetSize: NativeUInt;
    QuotaPeakPagedPoolUsage: NativeUInt;
    QuotaPagedPoolUsage: NativeUInt;
    QuotaPeakNonPagedPoolUsage: NativeUInt;
    QuotaNonPagedPoolUsage: NativeUInt;
    PagefileUsage: NativeUInt;
    PeakPagefileUsage: NativeUInt;
    PrivateUsage: NativeUInt;
  end;

function PulseGetProcessMemoryInfo(ProcessHandle: THandle;
  var Counters: TPulseProcessMemoryCounters; Size: DWORD): BOOL; stdcall;
  external 'psapi.dll' name 'GetProcessMemoryInfo';

function FileTimeTicks(const Value: TFileTime): UInt64;
begin
  Result := UInt64(Value.dwLowDateTime) or
    (UInt64(Value.dwHighDateTime) shl 32);
end;
{$endif}

{$ifdef LINUX}
const
  PulsePerfEventOpenSyscall = 298;
  PulsePerfTypeHardware = 0;
  PulsePerfTypeRaw = 4;
  PulsePerfCountHardwareCpuCycles = 0;
  PulsePerfFormatTotalTimeEnabled = 1;
  PulsePerfFormatTotalTimeRunning = 2;
  PulsePerfSampleIp = 1;
  PulsePerfPinned = UInt64(1) shl 2;
  PulsePerfExcludeHypervisor = UInt64(1) shl 6;
  PulsePerfPreciseIp2 = UInt64(2) shl 15;
  { FRONTEND_RETIRED.* (event C6, umask 01) picks its sub-event in the
    frontend MSR: perf takes it from config1 and opens it only as a precise
    sampling event (Sol 10-P on Cascade Lake: precise_ip 2, period 10000). }
  PulseFrontendRetired = $01C6;
  PulseFrontendSamplePeriod = 10000;
  PulseFrontendFormat = '/sys/bus/event_source/devices/cpu/format/frontend';

type
  TPulsePerfEventAttr = packed record
    EventType: Cardinal;
    Size: Cardinal;
    Config: UInt64;
    SamplePeriod: UInt64;
    SampleType: UInt64;
    ReadFormat: UInt64;
    Flags: UInt64;
    WakeupEvents: Cardinal;
    BreakpointType: Cardinal;
    Config1: UInt64;
    Config2: UInt64;
    BranchSampleType: UInt64;
    SampleRegistersUser: UInt64;
    SampleStackUser: Cardinal;
    ClockId: LongInt;
    SampleRegistersInterrupt: UInt64;
    AuxiliaryWatermark: Cardinal;
    SampleMaximumStack: Word;
    Reserved2: Word;
    AuxiliarySampleSize: Cardinal;
    Reserved3: Cardinal;
    SignalData: UInt64;
  end;

  TPulsePerfReadData = packed record
    Value: UInt64;
    EnabledTime: UInt64;
    RunningTime: UInt64;
  end;

var
  PulseCoreCounterFd: LongInt = -1;
  PulseRawCounterFd: array[0..3] of LongInt;
  PulseRawCount: Integer = 0;
  PulseCoreCounterRequired: Boolean = False;
  PulseWorkerCycles: Int64 = 0;
  PulseWorkerEnabledTime: Int64 = 0;
  PulseWorkerRunningTime: Int64 = 0;

threadvar
  PulseThreadCoreCounterFd: LongInt;
  PulseThreadCoreCounterOpened: Boolean;

function PulseGetPageSize: LongInt; cdecl; external 'c' name 'getpagesize';
function PulseSyscall(Number: NativeInt; Attributes: Pointer; Pid, Cpu,
  GroupFd: NativeInt; Flags: NativeUInt): NativeInt; cdecl;
  external 'c' name 'syscall';
{$endif}

procedure PulseInitializeCoreCounter(Required: Boolean; PmuType: Cardinal);
{$ifdef MSWINDOWS}
begin
  { xperf configures and samples TotalCycles globally.  The qualification
    runner joins those ETW samples to each benchmark PID after the matrix. }
end;
{$else}
  {$ifdef LINUX}
var
  Attributes: TPulsePerfEventAttr;
  RawText, Token: string;
  Separator: Integer;
begin
  PulseCoreCounterFd := -1;
  PulseRawCount := 0;
  PulseCoreCounterRequired := Required;
  PulseWorkerCycles := 0;
  PulseWorkerEnabledTime := 0;
  PulseWorkerRunningTime := 0;
  RawText := GetEnvironmentVariable('PULSE_RAW_CONFIGS');
  If not Required then
  begin
    If RawText <> '' then
      raise EArgumentException.Create(
        'PULSE_RAW_CONFIGS needs PULSE_METHOD_QUALIFICATION=1');
    Exit;
  end;
  FillChar(Attributes, SizeOf(Attributes), 0);
  Attributes.EventType := PulsePerfTypeHardware;
  Attributes.Size := SizeOf(Attributes);
  { Linux hybrid PMUs encode an explicit hardware PMU type in config[63:32].
    Zero retains the kernel default; a single-core probe may select cpu_atom. }
  Attributes.Config := PulsePerfCountHardwareCpuCycles or (UInt64(PmuType) shl 32);
  Attributes.ReadFormat := PulsePerfFormatTotalTimeEnabled or
    PulsePerfFormatTotalTimeRunning;
  Attributes.Flags := PulsePerfPinned or PulsePerfExcludeHypervisor;
  PulseCoreCounterFd := PulseSyscall(PulsePerfEventOpenSyscall, @Attributes,
    0, -1, -1, 0);
  If PulseCoreCounterFd < 0 then
    RaiseLastOSError;
  { config[:config1] per event, in the cycle counter's group: each sample
    reads them over the same scheduled window. }
  Attributes.EventType := PulsePerfTypeRaw;
  while RawText <> '' do
  begin
    If PulseRawCount > High(PulseRawCounterFd) then
      raise EArgumentException.Create('PULSE_RAW_CONFIGS takes at most four events');
    Separator := Pos(',', RawText);
    If Separator = 0 then
      Separator := Length(RawText) + 1;
    Token := Copy(RawText, 1, Separator - 1);
    Delete(RawText, 1, Separator);
    Separator := Pos(':', Token);
    Attributes.Config1 := 0;
    If Separator > 0 then
    begin
      Attributes.Config1 := StrToQWord(Copy(Token, Separator + 1, Length(Token)));
      SetLength(Token, Separator - 1);
    end;
    Attributes.Config := StrToQWord(Token);
    Attributes.Flags := PulsePerfExcludeHypervisor;
    Attributes.SamplePeriod := 0;
    Attributes.SampleType := 0;
    If ((Attributes.Config and $FFFF) = PulseFrontendRetired) and
       FileExists(PulseFrontendFormat) then
    begin
      If Attributes.Config1 = 0 then
        raise EArgumentException.Create('FRONTEND_RETIRED counts nothing without ' +
          'its frontend MSR value: write config:config1, e.g. 0x1c6:0x11 (DSB_MISS)');
      Attributes.Flags := Attributes.Flags or PulsePerfPreciseIp2;
      Attributes.SamplePeriod := PulseFrontendSamplePeriod;
      Attributes.SampleType := PulsePerfSampleIp;
    end;
    PulseRawCounterFd[PulseRawCount] := PulseSyscall(PulsePerfEventOpenSyscall,
      @Attributes, 0, -1, PulseCoreCounterFd, 0);
    If PulseRawCounterFd[PulseRawCount] < 0 then
      RaiseLastOSError;
    Inc(PulseRawCount);
  end;
end;
  {$else}
begin
  If Required then
    raise EAbort.Create('hardware core counter is unsupported');
end;
  {$endif}
{$endif}

procedure PulseShutdownCoreCounter;
{$ifdef MSWINDOWS}
begin
end;
{$else}
  {$ifdef LINUX}
var
  Index: Integer;
begin
  PulseCoreCounterRequired := False;
  for Index := 0 to PulseRawCount - 1 do
    If FpClose(PulseRawCounterFd[Index]) <> 0 then
      RaiseLastOSError;
  PulseRawCount := 0;
  If PulseCoreCounterFd < 0 then
    Exit;
  If FpClose(PulseCoreCounterFd) <> 0 then
    RaiseLastOSError;
  PulseCoreCounterFd := -1;
end;
  {$else}
begin
end;
  {$endif}
{$endif}

function PulseReadCoreCounter: TPulseCoreCounter;
{$ifdef MSWINDOWS}
begin
  Result.Cycles := 0;
  Result.EnabledTime := 0;
  Result.RunningTime := 0;
  Result.ContextSwitches := 0;
  raise EAbort.Create('Windows core cycles are read from the xperf trace');
end;
{$else}
  {$ifdef LINUX}
var
  Data: TPulsePerfReadData;
  Index: Integer;
begin
  If PulseCoreCounterFd < 0 then
    raise EAbort.Create('hardware core counter is not initialized');
  Data.Value := 0;
  Data.EnabledTime := 0;
  Data.RunningTime := 0;
  If FpRead(PulseCoreCounterFd, Data, SizeOf(Data)) <> SizeOf(Data) then
    RaiseLastOSError;
  Result.Cycles := Data.Value +
    UInt64(InterlockedExchangeAdd64(PulseWorkerCycles, 0));
  Result.EnabledTime := Data.EnabledTime +
    UInt64(InterlockedExchangeAdd64(PulseWorkerEnabledTime, 0));
  Result.RunningTime := Data.RunningTime +
    UInt64(InterlockedExchangeAdd64(PulseWorkerRunningTime, 0));
  Result.ContextSwitches := 0;
  FillChar(Result.Raw, SizeOf(Result.Raw), 0);
  for Index := 0 to PulseRawCount - 1 do
  begin
    If FpRead(PulseRawCounterFd[Index], Data, SizeOf(Data)) <> SizeOf(Data) then
      RaiseLastOSError;
    If Data.EnabledTime <> Data.RunningTime then
      raise EAbort.Create('raw perf event was multiplexed');
    Result.Raw[Index] := Data.Value;
  end;
end;
  {$else}
begin
  Result.Cycles := 0;
  Result.EnabledTime := 0;
  Result.RunningTime := 0;
  Result.ContextSwitches := 0;
  raise EAbort.Create('hardware core counter is unsupported');
end;
  {$endif}
{$endif}

procedure PulseInitializeThreadCoreCounter;
{$ifdef LINUX}
var
  Attributes: TPulsePerfEventAttr;
begin
  If not PulseCoreCounterRequired or PulseThreadCoreCounterOpened then
    Exit;
  FillChar(Attributes, SizeOf(Attributes), 0);
  Attributes.EventType := PulsePerfTypeHardware;
  Attributes.Size := SizeOf(Attributes);
  Attributes.Config := PulsePerfCountHardwareCpuCycles;
  Attributes.ReadFormat := PulsePerfFormatTotalTimeEnabled or
    PulsePerfFormatTotalTimeRunning;
  Attributes.Flags := PulsePerfPinned or PulsePerfExcludeHypervisor;
  PulseThreadCoreCounterFd := PulseSyscall(PulsePerfEventOpenSyscall,
    @Attributes, 0, -1, -1, 0);
  If PulseThreadCoreCounterFd < 0 then
    RaiseLastOSError;
  PulseThreadCoreCounterOpened := True;
end;
{$else}
begin
end;
{$endif}

procedure PulseShutdownThreadCoreCounter;
{$ifdef LINUX}
begin
  If not PulseThreadCoreCounterOpened then
    Exit;
  If FpClose(PulseThreadCoreCounterFd) <> 0 then
    RaiseLastOSError;
  PulseThreadCoreCounterFd := -1;
  PulseThreadCoreCounterOpened := False;
end;
{$else}
begin
end;
{$endif}

procedure PulseStartThreadCoreCounter(out Started: TPulseCoreCounter);
{$ifdef LINUX}
var
  Data: TPulsePerfReadData;
begin
  Started.Cycles := 0;
  Started.EnabledTime := 0;
  Started.RunningTime := 0;
  Started.ContextSwitches := 0;
  If not PulseCoreCounterRequired then
    Exit;
  PulseInitializeThreadCoreCounter;
  Data.Value := 0;
  Data.EnabledTime := 0;
  Data.RunningTime := 0;
  If FpRead(PulseThreadCoreCounterFd, Data, SizeOf(Data)) <> SizeOf(Data) then
    RaiseLastOSError;
  Started.Cycles := Data.Value;
  Started.EnabledTime := Data.EnabledTime;
  Started.RunningTime := Data.RunningTime;
end;
{$else}
begin
  Started.Cycles := 0;
  Started.EnabledTime := 0;
  Started.RunningTime := 0;
  Started.ContextSwitches := 0;
end;
{$endif}

procedure PulseStopThreadCoreCounter(const Started: TPulseCoreCounter);
{$ifdef LINUX}
var
  Data: TPulsePerfReadData;
begin
  If not PulseCoreCounterRequired then
    Exit;
  Data.Value := 0;
  Data.EnabledTime := 0;
  Data.RunningTime := 0;
  If FpRead(PulseThreadCoreCounterFd, Data, SizeOf(Data)) <> SizeOf(Data) then
    RaiseLastOSError;
  InterlockedExchangeAdd64(PulseWorkerCycles,
    Int64(Data.Value - Started.Cycles));
  InterlockedExchangeAdd64(PulseWorkerEnabledTime,
    Int64(Data.EnabledTime - Started.EnabledTime));
  InterlockedExchangeAdd64(PulseWorkerRunningTime,
    Int64(Data.RunningTime - Started.RunningTime));
end;
{$else}
begin
end;
{$endif}

function PulseCoreCounterName: string;
begin
  {$ifdef MSWINDOWS}
  Result := 'unavailable-query-cycle-time-used';
  {$else}
    {$ifdef LINUX}
  Result := 'perf-event-thread-cpu-cycles';
    {$else}
  Result := 'unsupported';
    {$endif}
  {$endif}
end;

function PulseCoreCounterInProcess: Boolean;
begin
  {$ifdef LINUX}
  Result := True;
  {$else}
  Result := False;
  {$endif}
end;

{ ' rawN=<delta>' of each PULSE_RAW_CONFIGS event, into the sample line. }
procedure PulseWriteRawEvents(const Started, Stopped: TPulseCoreCounter);
{$ifdef LINUX}
var
  Index: Integer;
begin
  for Index := 0 to PulseRawCount - 1 do
    Write(' raw', Index, '=', Stopped.Raw[Index] - Started.Raw[Index]);
end;
{$else}
begin
end;
{$endif}

function PulseReadTraceTime100ns: UInt64;
{$ifdef MSWINDOWS}
var
  Timestamp: TFileTime;
begin
  PulseGetSystemTimePreciseAsFileTime(Timestamp);
  Result := FileTimeTicks(Timestamp);
end;
{$else}
var
  Timestamp: UnixType.TTimeSpec;
begin
  If clock_gettime(CLOCK_REALTIME, @Timestamp) <> 0 then
    RaiseLastOSError;
  Result := UInt64(Timestamp.tv_sec) * UInt64(10000000) +
    UInt64(Timestamp.tv_nsec) div 100;
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

function PulseReadProcessCycles: UInt64;
{$ifdef MSWINDOWS}
begin
  { Sum of cycles consumed by all process threads, including worker threads. }
  If not PulseQueryProcessCycleTime(GetCurrentProcess, Result) then
    RaiseLastOSError;
end;
{$else}
begin
  { Linux reports the same through CLOCK_PROCESS_CPUTIME_ID in nanoseconds. }
  Result := 0;
end;
{$endif}

function PulseReadProcessorIdleCycles(Processor: Integer): UInt64;
{$ifdef MSWINDOWS}
var
  BufferLength: Cardinal;
  IdleCycles: array[0..63] of UInt64;
begin
  If (Processor < Low(IdleCycles)) or (Processor > High(IdleCycles)) then
    raise EArgumentException.Create('processor index is out of range');
  BufferLength := SizeOf(IdleCycles);
  If not PulseQueryIdleProcessorCycleTime(BufferLength, @IdleCycles[0]) then
    RaiseLastOSError;
  If Processor >= Integer(BufferLength div SizeOf(UInt64)) then
    raise EArgumentException.Create('processor index is out of range');
  Result := IdleCycles[Processor];
end;
{$else}
var
  CpuStat: TextFile;
  Line, Prefix, Token: string;
  Position, FieldIndex, ErrorCode: Integer;
  Value, Idle, IoWait: UInt64;
begin
  If Processor < 0 then
    raise EArgumentException.Create('processor index is out of range');
  Prefix := 'cpu' + IntToStr(Processor) + ' ';
  AssignFile(CpuStat, '/proc/stat');
  Reset(CpuStat);
  try
    while not Eof(CpuStat) do
    begin
      ReadLn(CpuStat, Line);
      If Copy(Line, 1, Length(Prefix)) <> Prefix then
        Continue;
      Delete(Line, 1, Length(Prefix));
      Idle := 0;
      IoWait := 0;
      for FieldIndex := 1 to 5 do
      begin
        Line := TrimLeft(Line);
        Position := Pos(' ', Line);
        If Position = 0 then
        begin
          Token := Line;
          Line := '';
        end
        else
        begin
          Token := Copy(Line, 1, Position - 1);
          Delete(Line, 1, Position);
        end;
        Val(Token, Value, ErrorCode);
        If ErrorCode <> 0 then
          raise EAbort.Create('invalid /proc/stat processor counter');
        If FieldIndex = 4 then
          Idle := Value
        else If FieldIndex = 5 then
          IoWait := Value;
      end;
      Result := Idle + IoWait;
      Exit;
    end;
  finally
    CloseFile(CpuStat);
  end;
  raise EArgumentException.Create('processor index is out of range');
end;
{$endif}

function PulseReadMemoryMetrics: TPulseMemoryMetrics;
{$ifdef MSWINDOWS}
var
  Counters: TPulseProcessMemoryCounters;
begin
  FillChar(Counters, SizeOf(Counters), 0);
  Counters.Size := SizeOf(Counters);
  If not PulseGetProcessMemoryInfo(GetCurrentProcess, Counters,
    SizeOf(Counters)) then
    RaiseLastOSError;
  Result.ResidentBytes := Counters.WorkingSetSize;
  Result.PrivateBytes := Counters.PrivateUsage;
  Result.PeakResidentBytes := Counters.PeakWorkingSetSize;
  Result.PageFaultCount := Counters.PageFaultCount;
end;
{$else}
var
  Statm, Status: TextFile;
  TotalPages, ResidentPages, SharedPages, PeakKilobytes, PageSize: UInt64;
  Line, ValueText: string;
  ErrorCode: Integer;
begin
  TotalPages := 0;
  ResidentPages := 0;
  SharedPages := 0;
  AssignFile(Statm, '/proc/self/statm');
  Reset(Statm);
  try
    ReadLn(Statm, TotalPages, ResidentPages, SharedPages);
  finally
    CloseFile(Statm);
  end;
  PageSize := PulseGetPageSize;
  Result.ResidentBytes := ResidentPages * PageSize;
  Result.PrivateBytes := (ResidentPages - SharedPages) * PageSize;
  Result.PeakResidentBytes := Result.ResidentBytes;
  Result.PageFaultCount := 0;
  AssignFile(Status, '/proc/self/status');
  Reset(Status);
  try
    while not Eof(Status) do
    begin
      ReadLn(Status, Line);
      If Copy(Line, 1, 6) <> 'VmHWM:' then
        Continue;
      ValueText := Trim(Copy(Line, 7, Length(Line)));
      If Pos(' ', ValueText) > 0 then
        SetLength(ValueText, Pos(' ', ValueText) - 1);
      Val(ValueText, PeakKilobytes, ErrorCode);
      If ErrorCode = 0 then
        Result.PeakResidentBytes := PeakKilobytes * UInt64(1024);
      Break;
    end;
  finally
    CloseFile(Status);
  end;
end;
{$endif}

end.
