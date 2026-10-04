program pulse_threads;

{$ifndef FPC}
  {$APPTYPE CONSOLE}
{$endif}

{$ifdef FPC}
  {$mode delphi}{$H+}
{$endif}

{$Q-}{$R-}

uses
  {$if defined(FPC) and not defined(PULSE_DEFAULT_MM)}
  mormot.core.fpcx64mm,
  {$ifend}
  {$I ../common/pulse_placement_uses.inc}
  SysUtils,
  Classes,
  SyncObjs,
  perf_clock in '..\common\perf_clock.pas',
  pulse_process_metrics in '..\common\pulse_process_metrics.pas',
  pulse_harness in '..\common\pulse_harness.pas';

{$I ../common/pulse_program_prefix.inc}

const
  MaxThreadCount = 8;
  WorkerInner = 256;
  { Keep the independent CPU body much longer than one event wake-up so this
    case measures parallel code throughput rather than its start barrier. }
  CpuWorkMultiplier = 32768;
  SharedReadMultiplier = 64;
  ContentionMultiplier = 32;
  AllocWorkMultiplier = 16;
  { One complete period of the size generator, independent of calibration. }
  AllocBlock = 16384;
  CrossBlockPerThread = AllocBlock div 4;

type
  TWorkKind = (wkEmpty, wkIndependent, wkSharedRead, wkLockedWrite,
    wkFalseSharing, wkPadded, wkAllocFree, wkAllocFree96, wkCrossFree, wkArenaProbe);

  TCounter = record
    Value: UInt64;
  end;

  TPaddedCounter = record
    Value: UInt64;
    Padding: array[0..7] of UInt64;
  end;

  TPulseWorkerBase = class(TThread)
  protected
    FKind: TWorkKind;
    FIndex: Integer;
    FIterations: Integer;
    function InitialDigest: UInt64; inline;
    function RunIndependent: UInt64;
    function RunSharedRead: UInt64;
    function RunLockedWrite: UInt64;
    function RunFalseSharing: UInt64;
    function RunPadded: UInt64;
    function RunAllocFree: UInt64;
    function RunAllocFree96: UInt64;
    function RunCrossFree: UInt64;
    procedure ProbeArenas;
    procedure RunWork;
  public
    Digest: UInt64;
    ArenaClass, ArenaOwner: array[0..2] of Pointer;
  end;

  TPulseWorker = class(TPulseWorkerBase)
  protected
    procedure Execute; override;
  public
    constructor Create(Kind: TWorkKind; Index, Iterations: Integer);
  end;

  TPersistentWorker = class(TPulseWorkerBase)
  private
    FFailureMessage: string;
    FDiscard: Boolean;
  protected
    procedure Execute; override;
  public
    constructor Create(Index: Integer);
    procedure Configure(Kind: TWorkKind; Iterations: Integer);
    property FailureMessage: string read FFailureMessage;
  end;

  TQueueRole = (qrProducer, qrConsumer);

  TQueueWorker = class(TThread)
  private
    FRole: TQueueRole;
    FCount: Integer;
    procedure RunWork;
  protected
    procedure Execute; override;
  public
    Digest: UInt64;
    constructor Create(Role: TQueueRole; Count: Integer);
  end;

var
  StartEvent: TEvent;
  SharedLock: TCriticalSection;
  SharedValue: UInt64;
  SharedData: array[0..8191] of UInt64;
  Counters: array[0..MaxThreadCount - 1] of TCounter;
  PaddedCounters: array[0..MaxThreadCount - 1] of TPaddedCounter;
  PersistentWorkers: array[0..MaxThreadCount - 1] of TPersistentWorker;
  PersistentStartEvents: array[0..MaxThreadCount - 1] of TEvent;
  PersistentDoneEvents: array[0..MaxThreadCount - 1] of TEvent;
  PersistentStop: Boolean;
  CrossPointers: array of Pointer;
  CrossPerThread: Integer;
  QueueLock: TCriticalSection;
  QueueData: array[0..1023] of UInt64;
  QueueHead, QueueTail, QueueUsed: Integer;
  ActiveThreadCount: Integer;

constructor TPulseWorker.Create(Kind: TWorkKind; Index, Iterations: Integer);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FKind := Kind;
  FIndex := Index;
  FIterations := Iterations;
end;

procedure TPulseWorker.Execute;
begin
  PinWorkerThread(FIndex);
  PulseInitializeThreadCoreCounter;
  try
    StartEvent.WaitFor(INFINITE);
    RunWork;
  finally
    PulseShutdownThreadCoreCounter;
  end;
end;

function TPulseWorkerBase.InitialDigest: UInt64;
begin
  Result := UInt64(FIndex + 1) * UInt64($9E3779B185EBCA87);
end;

function TPulseWorkerBase.RunIndependent: UInt64;
var
  I, J: Integer;
  X: UInt64;
begin
  X := InitialDigest;
  for I := 1 to FIterations do
    for J := 1 to WorkerInner do
      X := X * UInt64(2862933555777941757) + UInt64(3037000493);
  Result := X;
end;

function TPulseWorkerBase.RunSharedRead: UInt64;
var
  I, J: Integer;
  X: UInt64;
begin
  X := InitialDigest;
  for I := 1 to FIterations do
    for J := 0 to 1023 do
      X := X + SharedData[(J * 7 + FIndex) and High(SharedData)];
  Result := X;
end;

function TPulseWorkerBase.RunLockedWrite: UInt64;
var
  I: Integer;
begin
  for I := 1 to FIterations * WorkerInner do
  begin
    SharedLock.Acquire;
    try
      Inc(SharedValue);
    finally
      SharedLock.Release;
    end;
  end;
  Result := InitialDigest;
end;

function TPulseWorkerBase.RunFalseSharing: UInt64;
var
  I: Integer;
begin
  for I := 1 to FIterations * WorkerInner do
    Inc(Counters[FIndex].Value);
  Result := InitialDigest;
end;

function TPulseWorkerBase.RunPadded: UInt64;
var
  I: Integer;
begin
  for I := 1 to FIterations * WorkerInner do
    Inc(PaddedCounters[FIndex].Value);
  Result := InitialDigest;
end;

function TPulseWorkerBase.RunAllocFree: UInt64;
var
  I, J, Size: Integer;
  X: UInt64;
  P: PByte;
begin
  X := InitialDigest;
  for I := 1 to FIterations do
    for J := 1 to AllocBlock do
    begin
      Size := 16 + ((J * 37 + FIndex * 101) and (AllocBlock - 1));
      GetMem(P, Size);
      P[0] := Byte(J);
      X := X + P[0];
      FreeMem(P);
    end;
  If X <> InitialDigest + UInt64(FIterations) * AllocBlock * 255 div 2 then
    raise EAbort.Create('parallel-alloc input/digest mismatch');
  Result := X;
end;

function TPulseWorkerBase.RunAllocFree96: UInt64;
var
  I: Integer;
  X: UInt64;
  P: PByte;
begin
  X := InitialDigest;
  for I := 1 to FIterations * 64 do
  begin
    GetMem(P, 96);
    P[0] := Byte(I);
    P[95] := Byte(I shr 8);
    X := X + P[0] + P[95];
    FreeMem(P);
  end;
  Result := X;
end;

function TPulseWorkerBase.RunCrossFree: UInt64;
var
  I, Offset: Integer;
  X: UInt64;
  P: PByte;
begin
  X := InitialDigest;
  Offset := FIndex * CrossPerThread;
  for I := 0 to CrossPerThread - 1 do
  begin
    P := CrossPointers[Offset + I];
    X := X + P[0];
    FreeMem(P);
  end;
  Result := X;
  If X <> InitialDigest + UInt64(CrossPerThread) * 255 div 2 then
    raise EAbort.Create('cross-free input/digest mismatch');
end;

procedure TPulseWorkerBase.ProbeArenas;
{$if defined(FPC) and not defined(PULSE_DEFAULT_MM)}
const
  Sizes: array[0..2] of Integer = (96, 232, 1500);
var
  I: Integer;
  P: Pointer;
{$ifend}
begin
  {$if defined(FPC) and not defined(PULSE_DEFAULT_MM)}
  for I := 0 to High(Sizes) do
  begin
    GetMem(P, Sizes[I]);
    ArenaClass[I] := Fpcx64mmTestSmallBlockType(P);
    ArenaOwner[I] := Fpcx64mmTestSmallMediumInfo(P);
    FreeMem(P);
  end;
  {$ifend}
end;

procedure TPulseWorkerBase.RunWork;
var
  CoreStarted: TPulseCoreCounter;
begin
  PulseStartThreadCoreCounter(CoreStarted);
  try
    case FKind of
      wkEmpty:
        Digest := UInt64(FIndex);
      wkIndependent:
        Digest := RunIndependent;
      wkSharedRead:
        Digest := RunSharedRead;
      wkLockedWrite:
        Digest := RunLockedWrite;
      wkFalseSharing:
        Digest := RunFalseSharing;
      wkPadded:
        Digest := RunPadded;
      wkAllocFree:
        Digest := RunAllocFree;
      wkAllocFree96:
        Digest := RunAllocFree96;
      wkCrossFree:
        Digest := RunCrossFree;
      wkArenaProbe:
        ProbeArenas;
    end;
  finally
    PulseStopThreadCoreCounter(CoreStarted);
  end;
end;

constructor TPersistentWorker.Create(Index: Integer);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FIndex := Index;
end;

procedure TPersistentWorker.Configure(Kind: TWorkKind; Iterations: Integer);
begin
  FKind := Kind;
  FIterations := Iterations;
  FFailureMessage := '';
end;

procedure TPersistentWorker.Execute;
begin
  If FDiscard then
    Exit;
  PinWorkerThread(FIndex);
  PulseInitializeThreadCoreCounter;
  try
    while True do
    begin
      PersistentStartEvents[FIndex].WaitFor(INFINITE);
      PersistentStartEvents[FIndex].ResetEvent;
      If PersistentStop then
        Exit;
      try
        RunWork;
      except
        on E: Exception do
          FFailureMessage := E.ClassName + ': ' + E.Message;
        else
          FFailureMessage := 'non-Exception object';
      end;
      PersistentDoneEvents[FIndex].SetEvent;
    end;
  finally
    PulseShutdownThreadCoreCounter;
  end;
end;

constructor TQueueWorker.Create(Role: TQueueRole; Count: Integer);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FRole := Role;
  FCount := Count;
end;

procedure TQueueWorker.Execute;
begin
  PinWorkerThread(Ord(FRole));
  PulseInitializeThreadCoreCounter;
  try
    StartEvent.WaitFor(INFINITE);
    RunWork;
  finally
    PulseShutdownThreadCoreCounter;
  end;
end;

procedure TQueueWorker.RunWork;
var
  I: Integer;
  Value: UInt64;
  Done: Boolean;
  CoreStarted: TPulseCoreCounter;
begin
  PulseStartThreadCoreCounter(CoreStarted);
  try
    Digest := 0;
    Value := 0;
    If FRole = qrProducer then
    begin
      for I := 1 to FCount do
      begin
        repeat
          Done := False;
          QueueLock.Acquire;
          try
            If QueueUsed < Length(QueueData) then
            begin
              QueueData[QueueTail] := UInt64(I);
              QueueTail := (QueueTail + 1) and High(QueueData);
              Inc(QueueUsed);
              Done := True;
            end;
          finally
            QueueLock.Release;
          end;
          If not Done then
            Sleep(0);
        until Done;
      end;
      Digest := UInt64(FCount);
    end
    else
      for I := 1 to FCount do
      begin
        repeat
          Done := False;
          QueueLock.Acquire;
          try
            If QueueUsed > 0 then
            begin
              Value := QueueData[QueueHead];
              QueueHead := (QueueHead + 1) and High(QueueData);
              Dec(QueueUsed);
              Done := True;
            end;
          finally
            QueueLock.Release;
          end;
          If not Done then
            Sleep(0);
        until Done;
        Digest := Digest + Value;
      end;
  finally
    PulseStopThreadCoreCounter(CoreStarted);
  end;
end;

function RunOneShotWorkers(Kind: TWorkKind; Iterations: Integer): UInt64;
var
  Workers: array[0..MaxThreadCount - 1] of TPulseWorker;
  I, Created: Integer;
  FailureMessage: string;
begin
  StartEvent.ResetEvent;
  Created := 0;
  Result := 0;
  FailureMessage := '';
  try
    for I := 0 to ActiveThreadCount - 1 do
    begin
      Workers[I] := TPulseWorker.Create(Kind, I, Iterations);
      Inc(Created);
      Workers[I].Start;
    end;
    StartEvent.SetEvent;
    for I := 0 to Created - 1 do
    begin
      Workers[I].WaitFor;
      If assigned(Workers[I].FatalException) then
      begin
        If Workers[I].FatalException is Exception then
          FailureMessage := Exception(Workers[I].FatalException).ClassName + ': ' +
            Exception(Workers[I].FatalException).Message
        else
          FailureMessage := 'non-Exception object';
      end;
      Result := Result xor (Workers[I].Digest + UInt64(I));
    end;
  finally
    { A constructor/start failure must not leave already-created suspended
      workers behind. }
    StartEvent.SetEvent;
    for I := 0 to Created - 1 do
    begin
      Workers[I].WaitFor;
      Workers[I].Free;
    end;
  end;
  If FailureMessage <> '' then
    raise EAbort.Create('worker failed: ' + FailureMessage);
end;

function RunPersistentWorkers(Kind: TWorkKind; Iterations: Integer): UInt64;
var
  I: Integer;
  FailureMessage: string;
begin
  for I := 0 to ActiveThreadCount - 1 do
  begin
    PersistentWorkers[I].Configure(Kind, Iterations);
    PersistentDoneEvents[I].ResetEvent;
    PersistentStartEvents[I].SetEvent;
  end;
  Result := 0;
  FailureMessage := '';
  for I := 0 to ActiveThreadCount - 1 do
  begin
    PersistentDoneEvents[I].WaitFor(INFINITE);
    If PersistentWorkers[I].FailureMessage <> '' then
      FailureMessage := PersistentWorkers[I].FailureMessage;
    Result := Result xor (PersistentWorkers[I].Digest + UInt64(I));
  end;
  If FailureMessage <> '' then
    raise EAbort.Create('persistent worker failed: ' + FailureMessage);
end;

function CaseThreadStartJoin(Iterations: Integer): UInt64;
var
  I: Integer;
begin
  ActiveThreadCount := 4;
  Result := 0;
  for I := 1 to Iterations do
    Result := Result + RunOneShotWorkers(wkEmpty, 1);
end;

function CaseIndependent(Iterations: Integer): UInt64;
begin Result := RunPersistentWorkers(wkIndependent, Iterations); end;

function CaseIndependent1(Iterations: Integer): UInt64;
begin ActiveThreadCount := 1; Result := CaseIndependent(Iterations * CpuWorkMultiplier); end;
function CaseIndependent2(Iterations: Integer): UInt64;
begin ActiveThreadCount := 2; Result := CaseIndependent(Iterations * CpuWorkMultiplier); end;
function CaseIndependent4(Iterations: Integer): UInt64;
begin ActiveThreadCount := 4; Result := CaseIndependent(Iterations * CpuWorkMultiplier); end;
function CaseIndependent8(Iterations: Integer): UInt64;
begin ActiveThreadCount := 8; Result := CaseIndependent(Iterations * CpuWorkMultiplier); end;

function CaseSharedRead(Iterations: Integer): UInt64;
begin
  ActiveThreadCount := 4;
  Result := RunPersistentWorkers(wkSharedRead, Iterations * SharedReadMultiplier);
end;

function CaseLockedWrite(Iterations: Integer): UInt64;
begin
  ActiveThreadCount := 4;
  SharedValue := 0;
  RunPersistentWorkers(wkLockedWrite, Iterations * ContentionMultiplier);
  Result := SharedValue;
  If Result <> UInt64(Iterations) * ContentionMultiplier * WorkerInner *
    UInt64(ActiveThreadCount) then
    raise EAbort.Create('locked-write digest mismatch');
end;

function CaseFalseSharing(Iterations: Integer): UInt64;
var
  I: Integer;
begin
  ActiveThreadCount := 4;
  FillChar(Counters, SizeOf(Counters), 0);
  RunPersistentWorkers(wkFalseSharing, Iterations * ContentionMultiplier);
  Result := 0;
  for I := 0 to ActiveThreadCount - 1 do
    Result := Result + Counters[I].Value;
end;

function CasePaddedCounters(Iterations: Integer): UInt64;
var
  I: Integer;
begin
  ActiveThreadCount := 4;
  FillChar(PaddedCounters, SizeOf(PaddedCounters), 0);
  RunPersistentWorkers(wkPadded, Iterations * ContentionMultiplier);
  Result := 0;
  for I := 0 to ActiveThreadCount - 1 do
    Result := Result + PaddedCounters[I].Value;
end;

function CaseParallelAlloc(Iterations: Integer): UInt64;
begin Result := RunPersistentWorkers(wkAllocFree, Iterations); end;

function CaseParallelAlloc96(Iterations: Integer): UInt64;
begin Result := RunPersistentWorkers(wkAllocFree96, Iterations); end;

function CaseParallelAlloc1(Iterations: Integer): UInt64;
begin ActiveThreadCount := 1; Result := CaseParallelAlloc(Iterations); end;
function CaseParallelAlloc2(Iterations: Integer): UInt64;
begin ActiveThreadCount := 2; Result := CaseParallelAlloc(Iterations); end;
function CaseParallelAlloc4(Iterations: Integer): UInt64;
begin ActiveThreadCount := 4; Result := CaseParallelAlloc(Iterations); end;
function CaseParallelAlloc8(Iterations: Integer): UInt64;
begin ActiveThreadCount := 8; Result := CaseParallelAlloc(Iterations); end;

function CaseParallelAlloc96_4(Iterations: Integer): UInt64;
begin ActiveThreadCount := 4; Result := CaseParallelAlloc96(Iterations * AllocWorkMultiplier); end;

function CaseParallelAlloc96_8(Iterations: Integer): UInt64;
begin ActiveThreadCount := 8; Result := CaseParallelAlloc96(Iterations * AllocWorkMultiplier); end;

function CaseCrossThreadFree(Iterations: Integer): UInt64;
var
  I, J, Size: Integer;
  P: PByte;
begin
  ActiveThreadCount := 4;
  CrossPerThread := CrossBlockPerThread;
  SetLength(CrossPointers, CrossPerThread * ActiveThreadCount);
  Result := 0;
  for J := 1 to Iterations do
  begin
    for I := 0 to High(CrossPointers) do
    begin
      Size := 16 + ((I * 37) and (AllocBlock - 1));
      GetMem(CrossPointers[I], Size);
      P := CrossPointers[I];
      P[0] := Byte(I);
    end;
    Result := Result + RunPersistentWorkers(wkCrossFree, 1);
  end;
  SetLength(CrossPointers, 0);
end;

function CaseProducerConsumer(Iterations: Integer): UInt64;
var
  Producer, Consumer: TQueueWorker;
  Count: Integer;
begin
  Count := Iterations * WorkerInner * AllocWorkMultiplier;
  QueueHead := 0;
  QueueTail := 0;
  QueueUsed := 0;
  StartEvent.ResetEvent;
  Producer := TQueueWorker.Create(qrProducer, Count);
  Consumer := TQueueWorker.Create(qrConsumer, Count);
  try
    Producer.Start;
    Consumer.Start;
    StartEvent.SetEvent;
    Producer.WaitFor;
    Consumer.WaitFor;
    Result := Producer.Digest xor Consumer.Digest;
    If QueueUsed <> 0 then
      raise EAbort.Create('producer-consumer queue not empty');
  finally
    Producer.Free;
    Consumer.Free;
  end;
end;

function ManagerName: string;
begin
  {$ifdef FPC}
    {$ifdef PULSE_DEFAULT_MM}
    Result := 'fpc-default';
    {$else}
    Result := 'moon-fpcx64mm';
    {$endif}
  {$else}
  Result := 'delphi-default-fastmm4';
  {$endif}
end;

procedure InitializeData(SelectAllocatorRows, ReportAllocatorRows: Boolean);
var
  I, J, Row, Selected, RejectedCount, Attempts: Integer;
  X: UInt64;
  Worker: TPersistentWorker;
  Rejected: array[0..511] of TPersistentWorker;
begin
  X := UInt64($D1B54A32D192ED03);
  for I := 0 to High(SharedData) do
  begin
    X := X * UInt64(2862933555777941757) + UInt64(3037000493);
    SharedData[I] := X;
  end;
  StartEvent := TEvent.Create(nil, True, False, '');
  SharedLock := TCriticalSection.Create;
  QueueLock := TCriticalSection.Create;
  ActiveThreadCount := 4;
  { An eight-core stand shares the last worker logical CPU with the mostly
    waiting coordinator.  This keeps every worker's SMT sibling free.  With
    nine physical CPUs the affinity reservation gives the coordinator its own. }
  If not CanPinWorkerThreads(Length(PersistentWorkers)) then
    raise EAbort.Create('thread workload requires eight available logical CPUs');
  PersistentStop := False;
  for I := 0 to High(PersistentWorkers) do
  begin
    PersistentStartEvents[I] := TEvent.Create(nil, True, False, '');
    PersistentDoneEvents[I] := TEvent.Create(nil, True, False, '');
  end;
  If SelectAllocatorRows then begin
    { Fix preferred small rows, not just the number of distinct rows: different
      row sets can share different medium owners across request classes. Keep
      rejected threads alive until selection finishes so pthread ids cannot
      immediately be recycled into the same rejected row. }
    Selected := 0;
    RejectedCount := 0;
    try
      for Attempts := 1 to Length(Rejected) do
      begin
        Worker := TPersistentWorker.Create(-1);
        Row := Cardinal(Cardinal(Worker.ThreadID) * Cardinal($9E3779B1)) shr 27;
        If (Row < MaxThreadCount) and not Assigned(PersistentWorkers[Row]) then
        begin
          Worker.FIndex := Row;
          PersistentWorkers[Row] := Worker;
          Inc(Selected);
        end
        else
        begin
          Rejected[RejectedCount] := Worker;
          Inc(RejectedCount);
        end;
        If Selected = MaxThreadCount then
          Break;
      end;
    finally
      for I := 0 to RejectedCount - 1 do
      begin
        Rejected[I].FDiscard := True;
        Rejected[I].Start;
        Rejected[I].WaitFor;
        Rejected[I].Free;
      end;
    end;
    If Selected <> MaxThreadCount then
      raise EAbort.Create('could not select allocator rows 0..7');
  end
  else
    for I := 0 to High(PersistentWorkers) do
    begin
      PersistentWorkers[I] := TPersistentWorker.Create(I);
      Attempts := MaxThreadCount;
    end;
  for I := 0 to High(PersistentWorkers) do
    PersistentWorkers[I].Start;
  If ReportAllocatorRows then begin
    WriteLn('PULSE_THREADSET candidates=', Attempts,
      ' controlled=', Ord(SelectAllocatorRows));
    { Only one live worker probes at a time; concurrent probes could observe
      transient fallback classes instead of the preferred allocation class. }
    for I := 0 to High(PersistentWorkers) do
    begin
      Worker := PersistentWorkers[I];
      Worker.Configure(wkArenaProbe, 1);
      PersistentDoneEvents[I].ResetEvent;
      PersistentStartEvents[I].SetEvent;
      PersistentDoneEvents[I].WaitFor(INFINITE);
      If Worker.FailureMessage <> '' then
        raise EAbort.Create(Worker.FailureMessage);
      Row := Cardinal(Cardinal(Worker.ThreadID) * Cardinal($9E3779B1)) shr 27;
      Write('PULSE_WORKER worker=', I, ' row=', Row, ' tid=',
        IntToHex(NativeUInt(Worker.ThreadID), 16));
      for J := 0 to 2 do
        Write(' class', J, '=', IntToHex(NativeUInt(Worker.ArenaClass[J]), 16),
          ' owner', J, '=', IntToHex(NativeUInt(Worker.ArenaOwner[J]), 16));
      WriteLn;
    end;
  end;
end;

procedure FinalizeData;
var
  I: Integer;
begin
  PersistentStop := True;
  for I := 0 to High(PersistentWorkers) do
    PersistentStartEvents[I].SetEvent;
  for I := 0 to High(PersistentWorkers) do
  begin
    PersistentWorkers[I].WaitFor;
    PersistentWorkers[I].Free;
    PersistentDoneEvents[I].Free;
    PersistentStartEvents[I].Free;
  end;
  QueueLock.Free;
  SharedLock.Free;
  StartEvent.Free;
end;

procedure Run;
var
  Profile: TPulseProfile;
  SelectedCase, UnitName: string;
  Found, RuntimeInitialized, AllocatorCase: Boolean;
begin
  {$ifdef PULSE_PROGRAM_PREFIX}PulseProgramPrefix;{$endif}
  PulseInitialize('pulse_threads', Profile, SelectedCase);
  RuntimeInitialized := Profile.Name <> 'list';
  AllocatorCase := (Pos('parallel-alloc-free-', SelectedCase) > 0) or
    (Pos('cross-thread-free-4', SelectedCase) > 0);
  If RuntimeInitialized then
    InitializeData(AllocatorCase and
      (GetEnvironmentVariable('PULSE_FIXED_ALLOCATOR_ROWS') <> ''),
      AllocatorCase);
  UnitName := ManagerName;
  Found := False;
  try
    PulseRunCase('pulse_threads', 'thread-start-join-4', 'os+rtl', 'TThread',
      @CaseThreadStartJoin, 4, Profile, SelectedCase, Found, Pointer(@TPulseWorkerBase.RunWork));
    PulseRunCase('pulse_threads', 'independent-cpu-1', 'compiler+os', 'TThread',
      @CaseIndependent1, WorkerInner * CpuWorkMultiplier, Profile,
      SelectedCase, Found, Pointer(@TPulseWorkerBase.RunIndependent));
    PulseRunCase('pulse_threads', 'independent-cpu-2', 'compiler+os', 'TThread',
      @CaseIndependent2, 2 * WorkerInner * CpuWorkMultiplier, Profile,
      SelectedCase, Found, Pointer(@TPulseWorkerBase.RunIndependent));
    PulseRunCase('pulse_threads', 'independent-cpu-4', 'compiler+os', 'TThread',
      @CaseIndependent4, 4 * WorkerInner * CpuWorkMultiplier, Profile,
      SelectedCase, Found, Pointer(@TPulseWorkerBase.RunIndependent));
    PulseRunCase('pulse_threads', 'independent-cpu-8', 'compiler+os', 'TThread',
      @CaseIndependent8, 8 * WorkerInner * CpuWorkMultiplier, Profile,
      SelectedCase, Found, Pointer(@TPulseWorkerBase.RunIndependent));
    PulseRunCase('pulse_threads', 'shared-read-4', 'compiler+memory', 'TThread',
      @CaseSharedRead, 4 * 1024 * SharedReadMultiplier, Profile,
      SelectedCase, Found, Pointer(@TPulseWorkerBase.RunSharedRead));
    PulseRunCase('pulse_threads', 'locked-increment-4', 'rtl+os',
      'TCriticalSection', @CaseLockedWrite,
      4 * WorkerInner * ContentionMultiplier, Profile,
      SelectedCase, Found, Pointer(@TPulseWorkerBase.RunLockedWrite));
    PulseRunCase('pulse_threads', 'false-sharing-4', 'memory', 'cache-line',
      @CaseFalseSharing, 4 * WorkerInner * ContentionMultiplier, Profile,
      SelectedCase,
      Found, Pointer(@TPulseWorkerBase.RunFalseSharing));
    PulseRunCase('pulse_threads', 'padded-counters-4', 'memory', 'cache-line',
      @CasePaddedCounters, 4 * WorkerInner * ContentionMultiplier, Profile,
      SelectedCase,
      Found, Pointer(@TPulseWorkerBase.RunPadded));
    PulseRunCase('pulse_threads', 'parallel-alloc-free-1', 'mm', UnitName,
      @CaseParallelAlloc1, AllocBlock, Profile, SelectedCase,
      Found, Pointer(@TPulseWorkerBase.RunAllocFree));
    PulseRunCase('pulse_threads', 'parallel-alloc-free-2', 'mm', UnitName,
      @CaseParallelAlloc2, 2 * AllocBlock, Profile,
      SelectedCase, Found, Pointer(@TPulseWorkerBase.RunAllocFree));
    PulseRunCase('pulse_threads', 'parallel-alloc-free-4', 'mm', UnitName,
      @CaseParallelAlloc4, 4 * AllocBlock, Profile,
      SelectedCase, Found, Pointer(@TPulseWorkerBase.RunAllocFree));
    PulseRunCase('pulse_threads', 'parallel-alloc-free-8', 'mm', UnitName,
      @CaseParallelAlloc8, 8 * AllocBlock, Profile,
      SelectedCase, Found, Pointer(@TPulseWorkerBase.RunAllocFree));
    PulseRunCase('pulse_threads', 'parallel-alloc-free-96-4', 'mm', UnitName,
      @CaseParallelAlloc96_4, 4 * 64 * AllocWorkMultiplier, Profile,
      SelectedCase, Found, Pointer(@TPulseWorkerBase.RunAllocFree96));
    PulseRunCase('pulse_threads', 'parallel-alloc-free-96-8', 'mm', UnitName,
      @CaseParallelAlloc96_8, 8 * 64 * AllocWorkMultiplier, Profile,
      SelectedCase, Found, Pointer(@TPulseWorkerBase.RunAllocFree96));
    PulseRunCase('pulse_threads', 'cross-thread-free-4', 'mm', UnitName,
      @CaseCrossThreadFree, AllocBlock, Profile,
      SelectedCase, Found, Pointer(@TPulseWorkerBase.RunCrossFree));
    PulseRunCase('pulse_threads', 'producer-consumer', 'rtl+os',
      'TCriticalSection', @CaseProducerConsumer,
      WorkerInner * AllocWorkMultiplier, Profile,
      SelectedCase, Found, Pointer(@TQueueWorker.Execute));
  finally
    If RuntimeInitialized then
      FinalizeData;
  end;
  PulseFinish('pulse_threads', SelectedCase, Found);
end;

begin
  try
    Run;
  except
    on E: Exception do
    begin
      WriteLn(ErrOutput, E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
