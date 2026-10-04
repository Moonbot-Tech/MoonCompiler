unit pulse_harness;

{$ifdef FPC}
  {$mode delphi}{$H+}
  {$asmmode intel}
{$endif}

interface

uses
  Classes,
  SysUtils,
  perf_clock,
  pulse_process_metrics;

type
  TPulseCaseProc = function(Iterations: Integer): UInt64;

  TPulseProfile = record
    Name: string;
    Samples: Integer;
    TargetBatchNs: UInt64;
    WarmupNs: UInt64;
    MaximumIterations: Integer;
    FixedIterations: Integer;
    MethodQualification: Boolean;
    CooldownMs: Integer;
  end;

procedure PulseInitialize(const ProgramName: string;
  out Profile: TPulseProfile; out SelectedCase: string);
function CaseSelected(const SelectedCase, CaseName: string): Boolean;
procedure PulseRunCase(const ProgramName, CaseName, Layer, UnitName: string;
  CaseProc: TPulseCaseProc; OperationsPerIteration: UInt64;
  const Profile: TPulseProfile; const SelectedCase: string; var Found: Boolean; WorkBody: Pointer = nil);
{ The case with the data it works on: Data is PulseData of each. A procedure of
  its own name: the calls without data compile as before and move nothing, and
  the image keeps one PulseRunCase, the anchor the tools look up. }
procedure PulseRunCaseData(const ProgramName, CaseName, Layer, UnitName: string;
  CaseProc: TPulseCaseProc; OperationsPerIteration: UInt64;
  const Profile: TPulseProfile; const SelectedCase: string; var Found: Boolean; WorkBody: Pointer;
  const Data: string);
function PulseData(const Name: string; Address: Pointer): string;
procedure PulseFinish(const ProgramName, SelectedCase: string; Found: Boolean);

var
  { A block the case body allocates, left here by one store after its loop:
    each PULSE_SAMPLE prints the one its sample ran on as block. }
  PulseCaseBlock: Pointer;

implementation

var
  PulseTscOverhead: UInt64;
  PulseAffinityCpu: Integer;
  PulseSiblingCpu: Integer;
  PulseStackPhase: NativeInt = -1;
  { PULSE_CHAIN=1: every sample carries the ticks of a known-cycle chain
    before and after it: the core clock of that sample. }
  PulseChainMode: Boolean;
  { The Data of the running PulseRunCaseData, '' otherwise. Not a parameter of
    PulseRunCase: every call without data would pass it or run its case under
    a wrapper's frame, which moves their code or the stack of the case. }
  CaseData: string;

function EnvironmentValue(const Name: string; Default: Int64): Int64; forward;

{ Decimal only: TryStrToInt also reads 0x150 or $150 as 336. }
function TryDecimal(const Text: string; out Value: Integer): Boolean;
begin
  Result := TryStrToInt(Text, Value) and (IntToStr(Value) = Text);
end;

procedure WaitForStartGate;
var
  ReadyFile, StartFile: string;
  Ready: TFileStream;
  Started, Current, TimeoutMs: Int64;
begin
  ReadyFile := GetEnvironmentVariable('PULSE_READY_FILE');
  StartFile := GetEnvironmentVariable('PULSE_START_FILE');
  If (ReadyFile = '') and (StartFile = '') then
    Exit;
  If (ReadyFile = '') or (StartFile = '') then
    raise EArgumentException.Create(
      'PULSE_READY_FILE and PULSE_START_FILE must be set together');
  Ready := TFileStream.Create(ReadyFile, fmCreate);
  Ready.Free;
  WriteLn('PULSE_READY file=', ReadyFile);
  Flush(Output);
  TimeoutMs := EnvironmentValue('PULSE_GATE_TIMEOUT_MS', 10000);
  Started := TThread.GetTickCount64;
  while not FileExists(StartFile) do
  begin
    Current := TThread.GetTickCount64;
    If abs(Current - Started) >= TimeoutMs then
      raise EAbort.Create('start gate timed out');
    Sleep(1);
  end;
end;

function EnvironmentValue(const Name: string; Default: Int64): Int64;
var
  Text: string;
begin
  Text := GetEnvironmentVariable(Name);
  If Text = '' then
    Exit(Default);
  Result := StrToInt64(Text);
  If Result <= 0 then
    raise EArgumentException.Create(Name + ' must be positive');
end;

function CaseSelected(const SelectedCase, CaseName: string): Boolean;
begin
  Result := (SelectedCase = 'all') or
    (Pos(',' + LowerCase(CaseName) + ',', ',' + SelectedCase + ',') > 0);
end;

function FixedIterationsFor(const CaseName: string; Default: Integer): Integer;
var
  Counts: TStringList;
  Value: string;
begin
  Result := Default;
  Value := GetEnvironmentVariable('PULSE_ITERATION_COUNTS');
  If Value = '' then
    Exit;
  Counts := TStringList.Create;
  try
    Counts.CommaText := Value;
    Value := Counts.Values[CaseName];
    If Value = '' then
      raise EArgumentException.Create('missing fixed iterations for ' + CaseName);
    Result := StrToInt(Value);
    If Result <= 0 then
      raise EArgumentException.Create('fixed iterations must be positive');
  finally
    Counts.Free;
  end;
end;

function EnvironmentFlag(const Name: string): Boolean;
var
  Text: string;
begin
  Text := LowerCase(GetEnvironmentVariable(Name));
  Result := (Text = '1') or (Text = 'true') or (Text = 'yes');
end;

function SelectProfile(const Name: string): TPulseProfile;
begin
  Result.Name := LowerCase(Name);
  If Result.Name = 'quick' then
  begin
    Result.Samples := 17;
    Result.TargetBatchNs := 200000;
    Result.WarmupNs := 20000000;
    Result.MaximumIterations := 100000000;
  end
  else If Result.Name = 'medium' then
  begin
    Result.Samples := 37;
    Result.TargetBatchNs := 600000;
    Result.WarmupNs := 50000000;
    Result.MaximumIterations := 500000000;
  end
  else If Result.Name = 'long' then
  begin
    Result.Samples := 101;
    Result.TargetBatchNs := 2000000;
    Result.WarmupNs := 200000000;
    Result.MaximumIterations := 1000000000;
  end
  else
    raise EArgumentException.Create('mode must be quick, medium or long');
  Result.MethodQualification := EnvironmentFlag('PULSE_METHOD_QUALIFICATION');
  Result.FixedIterations := 0;
  If GetEnvironmentVariable('PULSE_ITERATIONS') <> '' then
    Result.FixedIterations := EnvironmentValue('PULSE_ITERATIONS', 0);
  Result.Samples := EnvironmentValue('PULSE_SAMPLES', Result.Samples);
  Result.TargetBatchNs := EnvironmentValue('PULSE_BATCH_US',
    Result.TargetBatchNs div 1000) * 1000;
  Result.WarmupNs := EnvironmentValue('PULSE_WARMUP_MS',
    Result.WarmupNs div 1000000) * 1000000;
  Result.CooldownMs := 0;
  If GetEnvironmentVariable('PULSE_MEMORY_COOLDOWN_MS') <> '' then
    Result.CooldownMs := EnvironmentValue('PULSE_MEMORY_COOLDOWN_MS', 0);
end;

{$ifdef FPC}
{ Calls the case with rsp = Phase (mod 4096) at the call: the case enters at
  Phase - 8.  The shift is taken from rsp here, so warmup, calibration and
  samples reach the case through different frames and still meet one phase.
  The frame register keeps unwinding valid under the variable shift. }
{$ifdef MSWINDOWS}
{ Shift + shadow space stay below 4 KiB + 32 from shallow harness frames:
  inside the 16 KiB of stack committed at start, no guard-page probe. }
function CallAtStackPhase(CaseProc: TPulseCaseProc; Iterations: Integer;
  Phase: NativeInt): UInt64; nostackframe; assembler;
asm
        push    rbp
        .seh_pushreg rbp
        mov     rbp, rsp
        .seh_setframe rbp, 0
        .seh_endprologue
        sub     rsp, 32
        mov     rax, rsp
        sub     rax, r8
        and     eax, 4095
        sub     rsp, rax
        mov     rax, rcx
        mov     ecx, edx
        call    rax
        lea     rsp, [rbp]
        pop     rbp
end;
{$else}
function CallAtStackPhase(CaseProc: TPulseCaseProc; Iterations: Integer;
  Phase: NativeInt): UInt64; assembler;
var
  Frame: Pointer; { a local keeps FPC's rbp frame: the CFA and the epilogue use rbp }
asm
        mov     rax, rsp
        sub     rax, rdx
        and     eax, 4095
        sub     rsp, rax
        mov     rax, rdi
        mov     edi, esi
        call    rax
end;
{$endif}
{$endif}

{ Stands in for a case: returns the rsp a case sees at its first instruction. }
function PulseStackProbe(Iterations: Integer): UInt64;
{$ifdef FPC}nostackframe; assembler; asm{$else}asm .noframe{$endif}
        mov     rax, rsp
end;

function MeasureOnce(CaseProc: TPulseCaseProc; Iterations: Integer;
  out Digest: UInt64): TPerfDelta;
var
  Started: TPerfStamp;
begin
  Started := BeginPerfStamp;
{$ifdef FPC}
  If PulseStackPhase >= 0 then
    Digest := CallAtStackPhase(CaseProc, Iterations, PulseStackPhase)
  else
{$endif}
    Digest := CaseProc(Iterations);
  Result := EndPerfStamp(Started);
end;

procedure Warmup(CaseProc: TPulseCaseProc; Iterations: Integer;
  TargetNs: UInt64);
var
  Delta: TPerfDelta;
  Digest, ElapsedNs: UInt64;
begin
  ElapsedNs := 0;
  repeat
    Delta := MeasureOnce(CaseProc, Iterations, Digest);
    ElapsedNs := ElapsedNs + Delta.WallNs;
  until ElapsedNs >= TargetNs;
end;

function Calibrate(CaseProc: TPulseCaseProc; const Profile: TPulseProfile): Integer;
const
  CalibrationFloorNs = UInt64(100000);
var
  Iterations, Pass, CalibrationRepeats, MaximumPasses: Integer;
  Delta: TPerfDelta;
  Digest, FastestNs, Scaled: UInt64;

  function FastestMeasurement: UInt64;
  var
    RepeatIndex: Integer;
  begin
    Result := High(UInt64);
    for RepeatIndex := 1 to CalibrationRepeats do
    begin
      Delta := MeasureOnce(CaseProc, Iterations, Digest);
      If (Delta.WallNs > 0) and (Delta.WallNs < Result) then
        Result := Delta.WallNs;
    end;
  end;
begin
  If Profile.MethodQualification then
  begin
    CalibrationRepeats := 1;
    MaximumPasses := 2;
  end
  else
  begin
    CalibrationRepeats := 5;
    MaximumPasses := 4;
  end;
  Digest := CaseProc(1);
  Iterations := 1;
  repeat
    FastestNs := FastestMeasurement;
    If FastestNs >= CalibrationFloorNs then
      Break;
    If Iterations > Profile.MaximumIterations div 8 then
      Break;
    Iterations := Iterations * 8;
  until False;
  If FastestNs = High(UInt64) then
    raise EAbort.Create('calibration interval is below timer resolution');
  for Pass := 1 to MaximumPasses do
  begin
    Scaled := UInt64(Iterations) * Profile.TargetBatchNs div FastestNs;
    If Scaled < 1 then
      Scaled := 1;
    If Scaled > UInt64(Profile.MaximumIterations) then
      Scaled := UInt64(Profile.MaximumIterations);
    Iterations := Integer(Scaled);
    FastestNs := FastestMeasurement;
    If (FastestNs >= Profile.TargetBatchNs * 3 div 4) and
       (FastestNs <= Profile.TargetBatchNs * 5 div 4) then
      Break;
  end;
  Result := Iterations;
end;

procedure PulseInitialize(const ProgramName: string;
  out Profile: TPulseProfile; out SelectedCase: string);
var
  Mode, SiblingText, StackText: string;
  Value: Integer;
begin
  Mode := 'quick';
  SelectedCase := 'all';
  If ParamCount >= 1 then
    Mode := ParamStr(1);
  If ParamCount >= 2 then
    SelectedCase := LowerCase(ParamStr(2));
  If ParamCount > 2 then
    raise EArgumentException.Create(
      'usage: ' + ProgramName + ' [quick|medium|long|list] [case|all]');
  If SameText(Mode, 'list') then
  begin
    Profile.Name := 'list';
    Profile.Samples := 0;
    Profile.TargetBatchNs := 0;
    Profile.WarmupNs := 0;
    Profile.MaximumIterations := 0;
    Profile.FixedIterations := 0;
    Profile.MethodQualification := False;
    Profile.CooldownMs := 0;
    WriteLn('PULSE_BEGIN program=', ProgramName, ' mode=list selected=',
      SelectedCase);
    Exit;
  end;
  Profile := SelectProfile(Mode);
  InitializePerfClock;
  PulseAffinityCpu := PinBenchmarkThread;
  PulseSiblingCpu := -1;
  SiblingText := GetEnvironmentVariable('PULSE_SIBLING_CPU');
  If SiblingText <> '' then
  begin
    If not TryDecimal(SiblingText, Value) or (Value < 0) then
      raise EArgumentException.Create(
        'PULSE_SIBLING_CPU must be a decimal CPU number, got "' + SiblingText + '"');
    PulseSiblingCpu := Value;
  end;
  StackText := GetEnvironmentVariable('PULSE_STACK_PHASE');
  If (StackText = '') or SameText(StackText, 'fixed') then
    StackText := 'fixed'
  else
  begin
    {$ifdef FPC}
    If not TryDecimal(StackText, Value) or (Value < 0) or (Value > 4095) or
       ((Value and 15) <> 0) then
      raise EArgumentException.Create(
        'PULSE_STACK_PHASE must be fixed or a decimal multiple of 16 below 4096 ' +
        '(grid is a pulse_full plan: it passes each pair its phase), got "' +
        StackText + '"');
    PulseStackPhase := Value;
    {$else}
    raise EArgumentException.Create('PULSE_STACK_PHASE needs the MoonCompiler build');
    {$endif}
  end;
  PulseChainMode := EnvironmentFlag('PULSE_CHAIN');
  PulseInitializeCoreCounter(Profile.MethodQualification);
  PulseTscOverhead := MeasureTscOverhead(1000);
  WriteLn('PULSE_BEGIN program=', ProgramName, ' mode=', Profile.Name,
    ' selected=', SelectedCase, ' affinity_cpu=', PulseAffinityCpu,
    ' tsc_overhead=', PulseTscOverhead, ' samples=', Profile.Samples,
    ' batch_ns=', Profile.TargetBatchNs, ' warmup_ns=', Profile.WarmupNs,
    ' cooldown_ms=', Profile.CooldownMs,
    ' sibling_cpu=', PulseSiblingCpu,
    ' stack_phase=', StackText,
    ' method_qualification=', Ord(Profile.MethodQualification),
    ' core_counter=', PulseCoreCounterName,
    ' chain_mode=', Ord(PulseChainMode), ' chain_cycles=', PerfChainCycles);
end;

procedure PulseRunCase(const ProgramName, CaseName, Layer, UnitName: string;
  CaseProc: TPulseCaseProc; OperationsPerIteration: UInt64;
  const Profile: TPulseProfile; const SelectedCase: string; var Found: Boolean; WorkBody: Pointer);
var
  Iterations, Sample: Integer;
  OracleDigest, ExpectedDigest, Digest, StackRsp: UInt64;
  Delta: TPerfDelta;
  ProcessCpuStarted, ThreadCyclesStarted, ProcessCpuNs, ThreadCycles: UInt64;
  ProcessCyclesStarted, ProcessCycles: UInt64;
  SiblingIdleStarted, SiblingIdleCycles: UInt64;
  ChainBefore, ChainAfter: UInt64;
  TraceStarted, TraceStopped: UInt64;
  CoreStarted, CoreStopped: TPulseCoreCounter;
  MemoryBefore, MemoryAfter, MemoryCooled: TPulseMemoryMetrics;
  TotalStarted: TPerfStamp;
  TotalDelta: TPerfDelta;
  TotalProcessCpuStarted, TotalThreadCyclesStarted: UInt64;
  BodyAddress, AnchorAddress: NativeUInt;
begin
  CoreStarted.Cycles := 0;
  CoreStarted.EnabledTime := 0;
  CoreStarted.RunningTime := 0;
  CoreStarted.ContextSwitches := 0;
  CoreStopped := CoreStarted;
  MemoryBefore.ResidentBytes := 0;
  MemoryBefore.PrivateBytes := 0;
  MemoryBefore.PeakResidentBytes := 0;
  MemoryBefore.PageFaultCount := 0;
  MemoryAfter := MemoryBefore;
  MemoryCooled := MemoryBefore;
  SiblingIdleStarted := 0;
  SiblingIdleCycles := 0;
  ChainBefore := 0;
  ChainAfter := 0;
  If not CaseSelected(SelectedCase, CaseName) then
    Exit;
  Found := True;
  BodyAddress := NativeUInt(@CaseProc);
  { The one PulseRunCase of the image: the tools find body= through it. }
  AnchorAddress := NativeUInt(@PulseRunCase);
  If Profile.Name = 'list' then
  begin
    WriteLn('PULSE_CASEDEF program=', ProgramName, ' case=', CaseName,
      ' layer=', Layer, ' unit=', UnitName, ' body=', IntToHex(BodyAddress, 16),
      ' anchor=', IntToHex(AnchorAddress, 16),
      ' workbody=', IntToHex(NativeUInt(WorkBody), 16));
    Exit;
  end;
  PulseCaseBlock := nil;
  OracleDigest := CaseProc(1);
  Iterations := FixedIterationsFor(CaseName, Profile.FixedIterations);
  If Iterations = 0 then
    Iterations := Calibrate(CaseProc, Profile);
  Warmup(CaseProc, Iterations, Profile.WarmupNs);
  If (Profile.FixedIterations = 0) and (GetEnvironmentVariable('PULSE_ITERATION_COUNTS') = '') then
    Iterations := Calibrate(CaseProc, Profile);
  ExpectedDigest := CaseProc(Iterations);
  MeasureOnce(@PulseStackProbe, 0, StackRsp);
  WaitForStartGate;
  WriteLn('PULSE_CASE program=', ProgramName, ' mode=', Profile.Name,
    ' case=', CaseName, ' layer=', Layer, ' unit=', UnitName,
    ' iterations=', Iterations, ' operations=',
    UInt64(Iterations) * OperationsPerIteration, ' samples=', Profile.Samples,
    ' warmup_ns=', Profile.WarmupNs,
    ' oracle=', IntToHex(OracleDigest, 16), ' body=', IntToHex(BodyAddress, 16),
    ' anchor=', IntToHex(AnchorAddress, 16),
      ' workbody=', IntToHex(NativeUInt(WorkBody), 16),
    ' stack_rsp=', IntToHex(StackRsp, 16), CaseData);
  TotalProcessCpuStarted := PulseReadProcessCpuNs;
  TotalThreadCyclesStarted := PulseReadThreadCycles;
  TotalStarted := BeginPerfStamp;
  for Sample := 1 to Profile.Samples do
  begin
    MemoryBefore := PulseReadMemoryMetrics;
    { Outside every counted window (trace, PMU, thread cycles, TSC): the
      chain must not count as work. }
    If PulseChainMode then
      ChainBefore := ReadChainTicks;
    TraceStarted := PulseReadTraceTime100ns;
    If PulseSiblingCpu >= 0 then
      SiblingIdleStarted := PulseReadProcessorIdleCycles(PulseSiblingCpu);
    If Profile.MethodQualification and PulseCoreCounterInProcess then
      CoreStarted := PulseReadCoreCounter;
    ProcessCpuStarted := PulseReadProcessCpuNs;
    ProcessCyclesStarted := PulseReadProcessCycles;
    ThreadCyclesStarted := PulseReadThreadCycles;
    Delta := MeasureOnce(CaseProc, Iterations, Digest);
    ThreadCycles := PulseReadThreadCycles - ThreadCyclesStarted;
    ProcessCycles := PulseReadProcessCycles - ProcessCyclesStarted;
    ProcessCpuNs := PulseReadProcessCpuNs - ProcessCpuStarted;
    If Profile.MethodQualification and PulseCoreCounterInProcess then
      CoreStopped := PulseReadCoreCounter;
    If PulseSiblingCpu >= 0 then
      SiblingIdleCycles := PulseReadProcessorIdleCycles(PulseSiblingCpu) -
        SiblingIdleStarted;
    TraceStopped := PulseReadTraceTime100ns;
    If PulseChainMode then
      ChainAfter := ReadChainTicks;
    MemoryAfter := PulseReadMemoryMetrics;
    If (Profile.CooldownMs > 0) and (Sample = Profile.Samples) then
      Sleep(Profile.CooldownMs);
    MemoryCooled := PulseReadMemoryMetrics;
    If Digest <> ExpectedDigest then
      raise EAbort.Create('digest mismatch: ' + CaseName);
    If (Delta.WallNs = 0) or (Delta.TscTicks = 0) then
      raise EAbort.Create('measured interval is below timer resolution');
    Write('PULSE_SAMPLE program=', ProgramName, ' mode=', Profile.Name,
      ' case=', CaseName, ' sample=', Sample, ' iterations=', Iterations,
      ' operations=', UInt64(Iterations) * OperationsPerIteration,
      ' wall_ns=', Delta.WallNs, ' thread_cpu_ns=', Delta.ThreadCpuNs,
      ' process_cpu_ns=', ProcessCpuNs,
      ' thread_cycles=', ThreadCycles, ' process_cycles=', ProcessCycles,
      ' tsc_ticks=', Delta.TscTicks,
      ' trace_start_100ns=', TraceStarted,
      ' trace_stop_100ns=', TraceStopped,
      ' core_cycles=', CoreStopped.Cycles - CoreStarted.Cycles,
      ' core_enabled=', CoreStopped.EnabledTime - CoreStarted.EnabledTime,
      ' core_running=', CoreStopped.RunningTime - CoreStarted.RunningTime,
      ' context_switches=', CoreStopped.ContextSwitches -
      CoreStarted.ContextSwitches,
      ' memory_before_private=', MemoryBefore.PrivateBytes,
      ' memory_after_private=', MemoryAfter.PrivateBytes,
      ' memory_cooldown_private=', MemoryCooled.PrivateBytes,
      ' memory_peak_resident=', MemoryCooled.PeakResidentBytes,
      ' page_faults=', MemoryAfter.PageFaultCount - MemoryBefore.PageFaultCount,
      ' sibling_cpu=', PulseSiblingCpu,
      ' sibling_idle_cycles=', SiblingIdleCycles,
      ' chain_before=', ChainBefore, ' chain_after=', ChainAfter);
    PulseWriteRawEvents(CoreStarted, CoreStopped);
    { Per sample and without a heap string: the harness's own strings between
      runs reorder the free blocks a case draws from (inttostr-int64 runs its
      samples one block past the one it used before PULSE_CASE). }
    If PulseCaseBlock <> nil then
      Write(' block=', NativeUInt(PulseCaseBlock));
    WriteLn(' digest=', IntToHex(Digest, 16));
  end;
  TotalDelta := EndPerfStamp(TotalStarted);
  ThreadCycles := PulseReadThreadCycles - TotalThreadCyclesStarted;
  ProcessCpuNs := PulseReadProcessCpuNs - TotalProcessCpuStarted;
  WriteLn('PULSE_TOTAL program=', ProgramName, ' mode=', Profile.Name,
    ' case=', CaseName, ' samples=', Profile.Samples,
    ' operations=', UInt64(Iterations) * OperationsPerIteration *
    UInt64(Profile.Samples), ' wall_ns=', TotalDelta.WallNs,
    ' thread_cpu_ns=', TotalDelta.ThreadCpuNs,
    ' process_cpu_ns=', ProcessCpuNs, ' thread_cycles=', ThreadCycles,
    ' tsc_ticks=', TotalDelta.TscTicks);
end;

procedure PulseRunCaseData(const ProgramName, CaseName, Layer, UnitName: string;
  CaseProc: TPulseCaseProc; OperationsPerIteration: UInt64;
  const Profile: TPulseProfile; const SelectedCase: string; var Found: Boolean; WorkBody: Pointer;
  const Data: string);
begin
  CaseData := Data;
  PulseRunCase(ProgramName, CaseName, Layer, UnitName, CaseProc, OperationsPerIteration, Profile,
    SelectedCase, Found, WorkBody);
  CaseData := '';
end;

{ ' data_<name>=<address>': the program passes it as Data of the case that
  works on the data, PULSE_CASE prints it. }
function PulseData(const Name: string; Address: Pointer): string;
begin
  Result := ' data_' + Name + '=' + IntToHex(NativeUInt(Address), 16);
end;

procedure PulseFinish(const ProgramName, SelectedCase: string; Found: Boolean);
begin
  If not Found then
    raise EArgumentException.Create('unknown case: ' + SelectedCase);
  PulseShutdownCoreCounter;
  WriteLn('PULSE_END program=', ProgramName, ' status=PASS');
end;

end.
