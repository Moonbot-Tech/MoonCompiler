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
  SysUtils,
  Classes,
  SyncObjs,
  perf_clock in '..\common\perf_clock.pas',
  pulse_process_metrics in '..\common\pulse_process_metrics.pas',
  pulse_harness in '..\common\pulse_harness.pas';

const
  MaxThreadCount = 8;
  WorkerInner = 256;
  { Keep the independent CPU body much longer than one event wake-up so this
    case measures parallel code throughput rather than its start barrier. }
  CpuWorkMultiplier = 32768;
  SharedReadMultiplier = 64;
  ContentionMultiplier = 32;
  AllocWorkMultiplier = 16;

type
  TWorkKind = (wkEmpty, wkIndependent, wkSharedRead, wkLockedWrite,
    wkFalseSharing, wkPadded, wkAllocFree, wkAllocFree96, wkCrossFree);

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
    procedure RunWork;
  public
    Digest: UInt64;
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
  StartEvent.WaitFor(INFINITE);
  RunWork;
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
  I, Size: Integer;
  X: UInt64;
  P: PByte;
begin
  X := InitialDigest;
  for I := 1 to FIterations * 64 do
  begin
    Size := 16 + ((I * 37 + FIndex * 101) and 16383);
    GetMem(P, Size);
    P[0] := Byte(I);
    X := X + P[0];
    FreeMem(P);
  end;
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
end;

procedure TPulseWorkerBase.RunWork;
begin
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
  PinWorkerThread(FIndex);
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
end;

constructor TQueueWorker.Create(Role: TQueueRole; Count: Integer);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FRole := Role;
  FCount := Count;
end;

procedure TQueueWorker.Execute;
var
  I: Integer;
  Value: UInt64;
  Done: Boolean;
begin
  StartEvent.WaitFor(INFINITE);
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
begin ActiveThreadCount := 1; Result := CaseParallelAlloc(Iterations * AllocWorkMultiplier); end;
function CaseParallelAlloc2(Iterations: Integer): UInt64;
begin ActiveThreadCount := 2; Result := CaseParallelAlloc(Iterations * AllocWorkMultiplier); end;
function CaseParallelAlloc4(Iterations: Integer): UInt64;
begin ActiveThreadCount := 4; Result := CaseParallelAlloc(Iterations * AllocWorkMultiplier); end;
function CaseParallelAlloc8(Iterations: Integer): UInt64;
begin ActiveThreadCount := 8; Result := CaseParallelAlloc(Iterations * AllocWorkMultiplier); end;

function CaseParallelAlloc96_4(Iterations: Integer): UInt64;
begin ActiveThreadCount := 4; Result := CaseParallelAlloc96(Iterations * AllocWorkMultiplier); end;

function CaseParallelAlloc96_8(Iterations: Integer): UInt64;
begin ActiveThreadCount := 8; Result := CaseParallelAlloc96(Iterations * AllocWorkMultiplier); end;

function CaseCrossThreadFree(Iterations: Integer): UInt64;
var
  I, Size: Integer;
  P: PByte;
begin
  ActiveThreadCount := 4;
  Iterations := Iterations * AllocWorkMultiplier;
  CrossPerThread := Iterations * 64;
  SetLength(CrossPointers, CrossPerThread * ActiveThreadCount);
  for I := 0 to High(CrossPointers) do
  begin
    Size := 16 + ((I * 37) and 16383);
    GetMem(CrossPointers[I], Size);
    P := CrossPointers[I];
    P[0] := Byte(I);
  end;
  Result := RunPersistentWorkers(wkCrossFree, Iterations);
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

procedure InitializeData;
var
  I: Integer;
  X: UInt64;
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
  If not CanPinWorkerThreads(Length(PersistentWorkers)) then
    raise EAbort.Create('thread workload requires eight available logical CPUs');
  PersistentStop := False;
  for I := 0 to High(PersistentWorkers) do
  begin
    PersistentStartEvents[I] := TEvent.Create(nil, True, False, '');
    PersistentDoneEvents[I] := TEvent.Create(nil, True, False, '');
    PersistentWorkers[I] := TPersistentWorker.Create(I);
    PersistentWorkers[I].Start;
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
  Found: Boolean;
begin
  PulseInitialize('pulse_threads', Profile, SelectedCase);
  InitializeData;
  UnitName := ManagerName;
  Found := False;
  try
    PulseRunCase('pulse_threads', 'thread-start-join-4', 'os+rtl', 'TThread',
      @CaseThreadStartJoin, 4, Profile, SelectedCase, Found);
    PulseRunCase('pulse_threads', 'independent-cpu-1', 'compiler+os', 'TThread',
      @CaseIndependent1, WorkerInner * CpuWorkMultiplier, Profile,
      SelectedCase, Found);
    PulseRunCase('pulse_threads', 'independent-cpu-2', 'compiler+os', 'TThread',
      @CaseIndependent2, 2 * WorkerInner * CpuWorkMultiplier, Profile,
      SelectedCase, Found);
    PulseRunCase('pulse_threads', 'independent-cpu-4', 'compiler+os', 'TThread',
      @CaseIndependent4, 4 * WorkerInner * CpuWorkMultiplier, Profile,
      SelectedCase, Found);
    PulseRunCase('pulse_threads', 'independent-cpu-8', 'compiler+os', 'TThread',
      @CaseIndependent8, 8 * WorkerInner * CpuWorkMultiplier, Profile,
      SelectedCase, Found);
    PulseRunCase('pulse_threads', 'shared-read-4', 'compiler+memory', 'TThread',
      @CaseSharedRead, 4 * 1024 * SharedReadMultiplier, Profile,
      SelectedCase, Found);
    PulseRunCase('pulse_threads', 'locked-increment-4', 'rtl+os',
      'TCriticalSection', @CaseLockedWrite,
      4 * WorkerInner * ContentionMultiplier, Profile,
      SelectedCase, Found);
    PulseRunCase('pulse_threads', 'false-sharing-4', 'memory', 'cache-line',
      @CaseFalseSharing, 4 * WorkerInner * ContentionMultiplier, Profile,
      SelectedCase,
      Found);
    PulseRunCase('pulse_threads', 'padded-counters-4', 'memory', 'cache-line',
      @CasePaddedCounters, 4 * WorkerInner * ContentionMultiplier, Profile,
      SelectedCase,
      Found);
    PulseRunCase('pulse_threads', 'parallel-alloc-free-1', 'mm', UnitName,
      @CaseParallelAlloc1, 64 * AllocWorkMultiplier, Profile, SelectedCase,
      Found);
    PulseRunCase('pulse_threads', 'parallel-alloc-free-2', 'mm', UnitName,
      @CaseParallelAlloc2, 2 * 64 * AllocWorkMultiplier, Profile,
      SelectedCase, Found);
    PulseRunCase('pulse_threads', 'parallel-alloc-free-4', 'mm', UnitName,
      @CaseParallelAlloc4, 4 * 64 * AllocWorkMultiplier, Profile,
      SelectedCase, Found);
    PulseRunCase('pulse_threads', 'parallel-alloc-free-8', 'mm', UnitName,
      @CaseParallelAlloc8, 8 * 64 * AllocWorkMultiplier, Profile,
      SelectedCase, Found);
    PulseRunCase('pulse_threads', 'parallel-alloc-free-96-4', 'mm', UnitName,
      @CaseParallelAlloc96_4, 4 * 64 * AllocWorkMultiplier, Profile,
      SelectedCase, Found);
    PulseRunCase('pulse_threads', 'parallel-alloc-free-96-8', 'mm', UnitName,
      @CaseParallelAlloc96_8, 8 * 64 * AllocWorkMultiplier, Profile,
      SelectedCase, Found);
    PulseRunCase('pulse_threads', 'cross-thread-free-4', 'mm', UnitName,
      @CaseCrossThreadFree, 4 * 64 * AllocWorkMultiplier, Profile,
      SelectedCase, Found);
    PulseRunCase('pulse_threads', 'producer-consumer', 'rtl+os',
      'TCriticalSection', @CaseProducerConsumer,
      WorkerInner * AllocWorkMultiplier, Profile,
      SelectedCase, Found);
  finally
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
