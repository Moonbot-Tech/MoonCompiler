program memory_massive;

{ Short, structurally broad memory-manager qualification.

  This is deliberately not a time soak.  It combines ownership-correct
  allocator races which are common in large applications:

  * one managed envelope crosses five threads and is reallocated at every hop;
  * synchronized workers allocate locally, then a different worker reallocates
    and frees the whole burst;
  * three adjacent small classes are locked to force concurrent GetMem calls
    through the allocator's real sleep/yield path;
  * forced small and medium lock collisions populate the deferred-free lists;
  * immutable managed values are retained, copied-on-write and unwound by
    exceptions concurrently.

  No phase contains an intentional application data race.  Ownership changes
  only while an item is inside a critical-section queue or across a completed
  barrier generation.

  Usage: memory_massive [quick|medium|long] [decimal-seed]
}

{$ifdef FPC}
  {$mode delphi}{$H+}
{$endif}
{$ifndef MOONBOT_MM_PROFILE_REQUIRED}
  {$fatal memory_massive requires MOONBOT_MM_PROFILE_REQUIRED}
{$endif}
{$ifndef FPCMM_MOONSHARD}
  {$fatal memory_massive requires FPCMM_MOONSHARD}
{$endif}
{$APPTYPE CONSOLE}
{$Q-}{$R-}

uses
  mormot.core.fpcx64mm,
  {$if defined(FPC) and not defined(WINDOWS)}
  cthreads,
  {$ifend}
  SysUtils,
  Classes,
  perf_clock,
  pulse_process_metrics;

const
  PipelineStageCount = 5;
  PipelineQueueCapacity = 127;
  ContentionWorkerCount = 8;
  ContentionMaximumBatch = 128;
  DeferredWorkerCount = 8;
  FanoutWorkerCount = 8;

  PipelineSizeCount = 23;
  PipelineSizes: array[0..PipelineSizeCount - 1] of Integer = (
    1, 15, 16, 17, 63, 64, 65, 95, 96, 97,
    255, 256, 257, 2599, 2600, 2601, 17408, 17409, 100500,
    2097151, 2097152, 2097153, 1048577);

  ContentionSizeCount = 15;
  ContentionSizes: array[0..ContentionSizeCount - 1] of Integer = (
    16, 64, 96, 256, 1024, 2599, 2600, 2601,
    16384, 17408, 17409, 100500, 1048575, 1048576, 2097153);

type
  TRunMode = (rmQuick, rmMedium, rmLong);

  TRunConfig = record
    Mode: TRunMode;
    PipelineTickets: Integer;
    ContentionRounds: Integer;
    FanoutIterations: Integer;
    ForcedAllocIterations: Integer;
    SmallDeferredBlocks: Integer;
    MediumDeferredBlocks: Integer;
  end;

  IGuardProbe = interface
    function Valid: Boolean;
  end;

  TGuardProbe = class(TInterfacedObject, IGuardProbe)
  private
    FId: Integer;
    FPayload: TBytes;
  public
    constructor Create(AId: Integer);
    destructor Destroy; override;
    function Valid: Boolean;
  end;

  TManagedLeaf = record
    Text: UnicodeString;
    Raw: RawByteString;
    Values: array of UInt64;
  end;

  TEnvelope = record
    Id: Integer;
    Stage: Integer;
    Raw: PByte;
    RawSize: Integer;
    Text: UnicodeString;
    Ansi: RawByteString;
    Bytes: TBytes;
    Leaves: array of TManagedLeaf;
    Guard: IGuardProbe;
  end;
  PEnvelope = ^TEnvelope;

  TEnvelopeQueue = class
  private
    FLock: TRTLCriticalSection;
    FItems: array[0..PipelineQueueCapacity - 1] of PEnvelope;
    FHead: Integer;
    FTail: Integer;
    FCount: Integer;
    FDone: Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    function Push(var Item: PEnvelope): Boolean;
    function Pop(out Item: PEnvelope): Boolean;
    function TryPop(out Item: PEnvelope): Boolean;
    procedure MarkDone;
  end;

  TPipelineThread = class(TThread)
  private
    FStage: Integer;
    FTicketCount: Integer;
    FSeed: UInt64;
    FInput: TEnvelopeQueue;
    FOutput: TEnvelopeQueue;
  protected
    procedure Execute; override;
  public
    Operations: Int64;
    Digest: UInt64;
    constructor Create(AStage, ATicketCount: Integer; ASeed: UInt64;
      AInput, AOutput: TEnvelopeQueue);
  end;

  TGenerationBarrier = class
  private
    FParticipants: Integer;
    FCount: LongInt;
    FGeneration: LongInt;
    FAborted: LongInt;
  public
    constructor Create(AParticipants: Integer);
    procedure Abort;
    function Wait: Boolean;
  end;

  TContentionCell = record
    Data: PByte;
    Size: Integer;
    Pattern: Byte;
  end;

  TContentionThread = class(TThread)
  private
    FId: Integer;
    FRounds: Integer;
    FSeed: UInt64;
    FBarrier: TGenerationBarrier;
    procedure Fail(const Text: string);
  protected
    procedure Execute; override;
  public
    Operations: Int64;
    Digest: UInt64;
    constructor Create(AId, ARounds: Integer; ASeed: UInt64;
      ABarrier: TGenerationBarrier);
  end;

  TPointerArray = array of Pointer;

  TDeferredFreeThread = class(TThread)
  private
    FPointers: ^TPointerArray;
    FFirst: Integer;
    FLast: Integer;
    FStartEvent: PRTLEvent;
    FReady: PLongInt;
    FCompleted: PLongInt;
  protected
    procedure Execute; override;
  public
    Freed: Integer;
    Digest: UInt64;
    ErrorText: string;
    constructor Create(var Pointers: TPointerArray; AFirst, ALast: Integer;
      AStartEvent: PRTLEvent; AReady, ACompleted: PLongInt);
  end;

  TForcedAllocThread = class(TThread)
  private
    FId: Integer;
    FSize: Integer;
    FIterations: Integer;
    FStartEvent: PRTLEvent;
    FReady: PLongInt;
    FEntered: PLongInt;
    FCompleted: PLongInt;
  protected
    procedure Execute; override;
  public
    Operations: Int64;
    Digest: UInt64;
    ErrorText: string;
    constructor Create(AId, ASize, AIterations: Integer;
      AStartEvent: PRTLEvent; AReady, AEntered, ACompleted: PLongInt);
  end;

  TManagedFanoutThread = class(TThread)
  private
    FId: Integer;
    FIterations: Integer;
    FText: UnicodeString;
    FAnsi: RawByteString;
    FBytes: TBytes;
    FGuard: IGuardProbe;
  protected
    procedure Execute; override;
  public
    Operations: Int64;
    Digest: UInt64;
    ErrorText: string;
    constructor Create(AId, AIterations: Integer; const AText: UnicodeString;
      const AAnsi: RawByteString; const ABytes: TBytes;
      const AGuard: IGuardProbe);
  end;

var
  Config: TRunConfig;
  GlobalSeed: UInt64;
  GuardCreated: LongInt;
  GuardDestroyed: LongInt;
  PipelineAborted: LongInt;
  PipelineErrorLock: TRTLCriticalSection;
  PipelineErrorText: string;
  ContentionErrorLock: TRTLCriticalSection;
  ContentionErrorText: string;
  ContentionCells: array[0..ContentionWorkerCount - 1,
    0..ContentionMaximumBatch - 1] of TContentionCell;

function NextRandom(var State: UInt64): UInt64; inline;
begin
  State := State xor (State shr 12);
  State := State xor (State shl 25);
  State := State xor (State shr 27);
  Result := State * UInt64($2545F4914F6CDD1D);
end;

procedure Require(Condition: Boolean; const Text: string);
begin
  If not Condition then
    raise Exception.Create(Text);
end;

function IsPipelineAborted: Boolean; inline;
begin
  Result := InterlockedExchangeAdd(PipelineAborted, 0) <> 0;
end;

procedure AbortPipeline(const Text: string);
begin
  EnterCriticalSection(PipelineErrorLock);
  try
    If PipelineErrorText = '' then
      PipelineErrorText := Text;
    InterlockedExchange(PipelineAborted, 1);
  finally
    LeaveCriticalSection(PipelineErrorLock);
  end;
end;

function MixDigest(Value, Item: UInt64): UInt64; inline;
begin
  Result := (Value xor Item) * UInt64($9E3779B185EBCA87);
  Result := Result xor (Result shr 29);
end;

function RawPattern(Id, Offset: Integer): Byte; inline;
var
  Value: UInt64;
begin
  Value := UInt64(Cardinal(Id)) * UInt64($D6E8FEB86659FD93) +
    UInt64(Cardinal(Offset)) * UInt64($9E3779B185EBCA87);
  Result := Byte(Value xor (Value shr 17) xor (Value shr 41));
end;

procedure FillRaw(Item: PEnvelope; FromOffset: Integer);
var
  I: Integer;
begin
  for I := FromOffset to Item^.RawSize - 1 do
    Item^.Raw[I] := RawPattern(Item^.Id, I);
end;

procedure VerifyRaw(Item: PEnvelope; Limit: Integer; const Context: string);
var
  I: Integer;
begin
  Require(Item^.Raw <> nil, Context + ': raw=nil');
  Require((NativeUInt(Item^.Raw) and 15) = 0,
    Context + ': raw alignment');
  If Limit > Item^.RawSize then
    Limit := Item^.RawSize;
  for I := 0 to Limit - 1 do
    If Item^.Raw[I] <> RawPattern(Item^.Id, I) then
      raise Exception.CreateFmt('%s: raw id=%d stage=%d offset=%d',
        [Context, Item^.Id, Item^.Stage, I]);
end;

function ExpectedText(Id, Stage: Integer): UnicodeString;
begin
  Result := UnicodeString('ticket:') + UnicodeString(IntToStr(Id)) +
    UnicodeString(':stage:') + UnicodeString(IntToStr(Stage));
end;

function ExpectedAnsi(Id, Stage: Integer): RawByteString;
begin
  Result := RawByteString('raw:') + RawByteString(IntToStr(Id)) +
    RawByteString(':stage:') + RawByteString(IntToStr(Stage));
end;

procedure FillManaged(Item: PEnvelope);
var
  I, J, ByteCount, ValueCount: Integer;
begin
  Item^.Text := ExpectedText(Item^.Id, Item^.Stage);
  Item^.Ansi := ExpectedAnsi(Item^.Id, Item^.Stage);
  ByteCount := 17 + ((Item^.Id * 13 + Item^.Stage * 29) and 511);
  SetLength(Item^.Bytes, ByteCount);
  for I := 0 to High(Item^.Bytes) do
    Item^.Bytes[I] := Byte(Item^.Id xor Item^.Stage xor (I * 37));
  SetLength(Item^.Leaves, 1 + (Item^.Id and 3));
  for I := 0 to High(Item^.Leaves) do begin
    Item^.Leaves[I].Text := Item^.Text + UnicodeString(':leaf:') +
      UnicodeString(IntToStr(I));
    Item^.Leaves[I].Raw := Item^.Ansi + RawByteString(':leaf:') +
      RawByteString(IntToStr(I));
    ValueCount := 1 + ((Item^.Id + Item^.Stage + I) and 15);
    SetLength(Item^.Leaves[I].Values, ValueCount);
    for J := 0 to ValueCount - 1 do
      Item^.Leaves[I].Values[J] :=
        UInt64(Cardinal(Item^.Id)) shl 32 xor
        UInt64(Cardinal(Item^.Stage)) shl 24 xor
        UInt64(Cardinal(I)) shl 16 xor UInt64(Cardinal(J));
  end;
end;

procedure VerifyManaged(Item: PEnvelope; const Context: string);
var
  I, J, ExpectedCount: Integer;
  TextValue: UnicodeString;
  AnsiValue: RawByteString;
  ExpectedValue: UInt64;
begin
  TextValue := ExpectedText(Item^.Id, Item^.Stage);
  AnsiValue := ExpectedAnsi(Item^.Id, Item^.Stage);
  Require(Item^.Text = TextValue, Context + ': UnicodeString');
  Require(Item^.Ansi = AnsiValue, Context + ': RawByteString');
  ExpectedCount := 17 + ((Item^.Id * 13 + Item^.Stage * 29) and 511);
  Require(Length(Item^.Bytes) = ExpectedCount, Context + ': bytes length');
  for I := 0 to High(Item^.Bytes) do
    Require(Item^.Bytes[I] = Byte(Item^.Id xor Item^.Stage xor (I * 37)),
      Context + ': bytes content');
  Require(Length(Item^.Leaves) = 1 + (Item^.Id and 3),
    Context + ': leaves length');
  for I := 0 to High(Item^.Leaves) do begin
    Require(Item^.Leaves[I].Text = TextValue + UnicodeString(':leaf:') +
      UnicodeString(IntToStr(I)), Context + ': leaf text');
    Require(Item^.Leaves[I].Raw = AnsiValue + RawByteString(':leaf:') +
      RawByteString(IntToStr(I)), Context + ': leaf raw');
    ExpectedCount := 1 + ((Item^.Id + Item^.Stage + I) and 15);
    Require(Length(Item^.Leaves[I].Values) = ExpectedCount,
      Context + ': leaf values length');
    for J := 0 to ExpectedCount - 1 do begin
      ExpectedValue := UInt64(Cardinal(Item^.Id)) shl 32 xor
        UInt64(Cardinal(Item^.Stage)) shl 24 xor
        UInt64(Cardinal(I)) shl 16 xor UInt64(Cardinal(J));
      Require(Item^.Leaves[I].Values[J] = ExpectedValue,
        Context + ': leaf values content');
    end;
  end;
  Require((Item^.Guard <> nil) and Item^.Guard.Valid,
    Context + ': interface guard');
end;

function PipelineSize(Id, Stage: Integer): Integer; inline;
begin
  Result := PipelineSizes[(Id * 7 + Stage * 11) mod PipelineSizeCount];
end;

constructor TGuardProbe.Create(AId: Integer);
var
  I: Integer;
begin
  inherited Create;
  FId := AId;
  SetLength(FPayload, 31 + (AId and 127));
  for I := 0 to High(FPayload) do
    FPayload[I] := Byte(AId xor (I * 19));
  InterlockedIncrement(GuardCreated);
end;

destructor TGuardProbe.Destroy;
begin
  InterlockedIncrement(GuardDestroyed);
  inherited Destroy;
end;

function TGuardProbe.Valid: Boolean;
var
  I: Integer;
begin
  Result := Length(FPayload) = 31 + (FId and 127);
  If not Result then
    Exit;
  for I := 0 to High(FPayload) do
    If FPayload[I] <> Byte(FId xor (I * 19)) then
      Exit(False);
end;

procedure DestroyEnvelope(var Item: PEnvelope);
begin
  If Item = nil then
    Exit;
  If Item^.Raw <> nil then begin
    FreeMem(Item^.Raw);
    Item^.Raw := nil;
  end;
  Dispose(Item);
  Item := nil;
end;

function CreateEnvelope(Id: Integer): PEnvelope;
begin
  Result := nil;
  New(Result);
  try
    Result^.Id := Id;
    Result^.Stage := 0;
    Result^.RawSize := PipelineSize(Id, 0);
    GetMem(Result^.Raw, Result^.RawSize);
    Require(Result^.Raw <> nil, 'pipeline GetMem returned nil');
    FillRaw(Result, 0);
    Result^.Guard := TGuardProbe.Create(Id);
    FillManaged(Result);
    VerifyRaw(Result, Result^.RawSize, 'pipeline-create');
    VerifyManaged(Result, 'pipeline-create');
  except
    DestroyEnvelope(Result);
    raise;
  end;
end;

procedure TransformEnvelope(Item: PEnvelope; NewStage: Integer);
var
  OldSize, NewSize, Keep: Integer;
  TextAlias, TextCopy: UnicodeString;
  AnsiAlias, AnsiCopy: RawByteString;
begin
  Require(NewStage = Item^.Stage + 1, 'pipeline stage order');
  VerifyRaw(Item, Item^.RawSize, 'pipeline-before');
  VerifyManaged(Item, 'pipeline-before');

  TextAlias := Item^.Text;
  TextCopy := TextAlias;
  UniqueString(TextCopy);
  If TextCopy <> '' then
    TextCopy[1] := WideChar(Ord(TextCopy[1]) xor 1);
  Require(Item^.Text = TextAlias, 'UnicodeString COW changed source');
  AnsiAlias := Item^.Ansi;
  AnsiCopy := AnsiAlias;
  UniqueString(AnsiCopy);
  If AnsiCopy <> '' then
    AnsiCopy[1] := AnsiChar(Ord(AnsiCopy[1]) xor 1);
  Require(Item^.Ansi = AnsiAlias, 'RawByteString COW changed source');

  OldSize := Item^.RawSize;
  NewSize := PipelineSize(Item^.Id, NewStage);
  ReallocMem(Item^.Raw, NewSize);
  Require(Item^.Raw <> nil, 'pipeline ReallocMem returned nil');
  Keep := OldSize;
  If NewSize < Keep then
    Keep := NewSize;
  Item^.RawSize := NewSize;
  VerifyRaw(Item, Keep, 'pipeline-realloc-prefix');
  FillRaw(Item, Keep);
  Item^.Stage := NewStage;
  FillManaged(Item);
  VerifyRaw(Item, Item^.RawSize, 'pipeline-after');
  VerifyManaged(Item, 'pipeline-after');
end;

constructor TEnvelopeQueue.Create;
begin
  inherited Create;
  InitCriticalSection(FLock);
end;

destructor TEnvelopeQueue.Destroy;
begin
  DoneCriticalSection(FLock);
  inherited Destroy;
end;

function TEnvelopeQueue.Push(var Item: PEnvelope): Boolean;
begin
  repeat
    If IsPipelineAborted then
      Exit(False);
    EnterCriticalSection(FLock);
    If FCount < PipelineQueueCapacity then begin
      FItems[FTail] := Item;
      Item := nil;
      Inc(FTail);
      If FTail = PipelineQueueCapacity then
        FTail := 0;
      Inc(FCount);
      LeaveCriticalSection(FLock);
      Exit(True);
    end;
    LeaveCriticalSection(FLock);
    Sleep(0);
  until False;
end;

function TEnvelopeQueue.Pop(out Item: PEnvelope): Boolean;
begin
  Item := nil;
  repeat
    If IsPipelineAborted then
      Exit(False);
    EnterCriticalSection(FLock);
    If FCount > 0 then begin
      Item := FItems[FHead];
      FItems[FHead] := nil;
      Inc(FHead);
      If FHead = PipelineQueueCapacity then
        FHead := 0;
      Dec(FCount);
      LeaveCriticalSection(FLock);
      Exit(True);
    end;
    If FDone then begin
      LeaveCriticalSection(FLock);
      Exit(False);
    end;
    LeaveCriticalSection(FLock);
    Sleep(0);
  until False;
end;

function TEnvelopeQueue.TryPop(out Item: PEnvelope): Boolean;
begin
  Item := nil;
  EnterCriticalSection(FLock);
  If FCount = 0 then
    Result := False
  else begin
    Item := FItems[FHead];
    FItems[FHead] := nil;
    Inc(FHead);
    If FHead = PipelineQueueCapacity then
      FHead := 0;
    Dec(FCount);
    Result := True;
  end;
  LeaveCriticalSection(FLock);
end;

procedure TEnvelopeQueue.MarkDone;
begin
  EnterCriticalSection(FLock);
  FDone := True;
  LeaveCriticalSection(FLock);
end;

constructor TPipelineThread.Create(AStage, ATicketCount: Integer;
  ASeed: UInt64; AInput, AOutput: TEnvelopeQueue);
begin
  inherited Create(True);
  FStage := AStage;
  FTicketCount := ATicketCount;
  FSeed := ASeed;
  FInput := AInput;
  FOutput := AOutput;
end;

procedure TPipelineThread.Execute;
var
  I: Integer;
  Item: PEnvelope;
begin
  Item := nil;
  try
    If FStage = 0 then begin
      for I := 0 to FTicketCount - 1 do begin
        If IsPipelineAborted then
          Break;
        Item := CreateEnvelope(I + 1);
        Digest := MixDigest(Digest, UInt64(Cardinal(Item^.Id)) xor FSeed);
        If not FOutput.Push(Item) then begin
          DestroyEnvelope(Item);
          Break;
        end;
        Inc(Operations);
      end;
    end else begin
      while FInput.Pop(Item) do begin
        TransformEnvelope(Item, FStage);
        Digest := MixDigest(Digest,
          UInt64(Cardinal(Item^.Id)) shl 32 xor
          UInt64(Cardinal(Item^.RawSize)) xor UInt64(Cardinal(FStage)));
        If FOutput = nil then
          DestroyEnvelope(Item)
        else If not FOutput.Push(Item) then begin
          DestroyEnvelope(Item);
          Break;
        end;
        Inc(Operations);
      end;
    end;
  except
    on E: Exception do begin
      DestroyEnvelope(Item);
      AbortPipeline(Format('stage=%d %s: %s',
        [FStage, E.ClassName, E.Message]));
    end;
  end;
  If FOutput <> nil then
    FOutput.MarkDone;
end;

function TestPipeline: UInt64;
var
  Queues: array[0..PipelineStageCount - 2] of TEnvelopeQueue;
  Workers: array[0..PipelineStageCount - 1] of TPipelineThread;
  Item: PEnvelope;
  I: Integer;
begin
  PipelineErrorText := '';
  InterlockedExchange(PipelineAborted, 0);
  for I := 0 to High(Queues) do
    Queues[I] := TEnvelopeQueue.Create;
  for I := 0 to High(Workers) do begin
    If I = 0 then
      Workers[I] := TPipelineThread.Create(I, Config.PipelineTickets,
        GlobalSeed, nil, Queues[0])
    else If I = High(Workers) then
      Workers[I] := TPipelineThread.Create(I, Config.PipelineTickets,
        GlobalSeed, Queues[I - 1], nil)
    else
      Workers[I] := TPipelineThread.Create(I, Config.PipelineTickets,
        GlobalSeed, Queues[I - 1], Queues[I]);
  end;
  for I := 0 to High(Workers) do
    Workers[I].Start;
  for I := 0 to High(Workers) do
    Workers[I].WaitFor;
  Result := 0;
  for I := 0 to High(Workers) do begin
    Require(Workers[I].FatalException = nil,
      Format('pipeline FatalException stage=%d', [I]));
    Require(Workers[I].Operations = Config.PipelineTickets,
      Format('pipeline operations stage=%d got=%d expected=%d',
        [I, Workers[I].Operations, Config.PipelineTickets]));
    Result := MixDigest(Result, Workers[I].Digest);
    Workers[I].Free;
  end;
  for I := 0 to High(Queues) do begin
    while Queues[I].TryPop(Item) do
      DestroyEnvelope(Item);
    Queues[I].Free;
  end;
  Require(PipelineErrorText = '', 'pipeline: ' + PipelineErrorText);
  Require(GuardCreated = GuardDestroyed,
    Format('pipeline guards created=%d destroyed=%d',
      [GuardCreated, GuardDestroyed]));
end;

constructor TGenerationBarrier.Create(AParticipants: Integer);
begin
  inherited Create;
  FParticipants := AParticipants;
end;

procedure TGenerationBarrier.Abort;
begin
  InterlockedExchange(FAborted, 1);
end;

function TGenerationBarrier.Wait: Boolean;
var
  Generation: LongInt;
begin
  If InterlockedExchangeAdd(FAborted, 0) <> 0 then
    Exit(False);
  Generation := InterlockedExchangeAdd(FGeneration, 0);
  If InterlockedIncrement(FCount) = FParticipants then begin
    InterlockedExchange(FCount, 0);
    InterlockedIncrement(FGeneration);
    Exit(True);
  end;
  while InterlockedExchangeAdd(FGeneration, 0) = Generation do begin
    If InterlockedExchangeAdd(FAborted, 0) <> 0 then
      Exit(False);
    TThread.Yield;
  end;
  Result := InterlockedExchangeAdd(FAborted, 0) = 0;
end;

function ContentionBatch(Size: Integer): Integer; inline;
begin
  If Size <= 2601 then
    Result := ContentionMaximumBatch
  else If Size <= 100500 then
    Result := 32
  else
    Result := 4;
end;

procedure TContentionThread.Fail(const Text: string);
begin
  EnterCriticalSection(ContentionErrorLock);
  try
    If ContentionErrorText = '' then
      ContentionErrorText := Format('worker=%d %s', [FId, Text]);
  finally
    LeaveCriticalSection(ContentionErrorLock);
  end;
  FBarrier.Abort;
end;

constructor TContentionThread.Create(AId, ARounds: Integer; ASeed: UInt64;
  ABarrier: TGenerationBarrier);
begin
  inherited Create(True);
  FId := AId;
  FRounds := ARounds;
  FSeed := ASeed xor (UInt64(Cardinal(AId)) * UInt64($D6E8FEB86659FD93));
  FBarrier := ABarrier;
end;

procedure TContentionThread.Execute;
var
  Round, I, Size, NewSize, Batch, Owner, Keep: Integer;
  Cell: ^TContentionCell;
  P: PByte;
  R: UInt64;
begin
  try
    If not FBarrier.Wait then
      Exit;
    for Round := 0 to FRounds - 1 do begin
      Size := ContentionSizes[Round mod ContentionSizeCount];
      Batch := ContentionBatch(Size);
      for I := 0 to Batch - 1 do begin
        Cell := @ContentionCells[FId, I];
        Cell^.Size := Size;
        Cell^.Pattern := Byte(FId * 31 + Round * 7 + I) or 1;
        R := NextRandom(FSeed);
        If (Round and 3) = 0 then begin
          Cell^.Data := AllocMem(Size);
          If (Cell^.Data = nil) or (Cell^.Data[0] <> 0) or
             (Cell^.Data[Size - 1] <> 0) then begin
            Fail('AllocMem zero contract');
            Exit;
          end;
        end else If (Round and 3) = 1 then
          Cell^.Data := GetMemory(Size)
        else
          GetMem(Cell^.Data, Size);
        If Cell^.Data = nil then begin
          Fail('allocation returned nil');
          Exit;
        end;
        FillChar(Cell^.Data^, Size, Cell^.Pattern);
        Digest := MixDigest(Digest, R xor UInt64(Cardinal(Size)));
        Inc(Operations);
      end;
      If not FBarrier.Wait then
        Exit;

      Owner := (FId + ContentionWorkerCount - 1) mod ContentionWorkerCount;
      for I := 0 to Batch - 1 do begin
        Cell := @ContentionCells[Owner, I];
        P := Cell^.Data;
        If (P = nil) or (P[0] <> Cell^.Pattern) or
           (P[Cell^.Size - 1] <> Cell^.Pattern) then begin
          Fail(Format('remote content round=%d item=%d', [Round, I]));
          Exit;
        end;
        If (Round mod 3) = 1 then begin
          NewSize := ContentionSizes[(Round * 5 + I) mod ContentionSizeCount];
          Keep := Cell^.Size;
          If NewSize < Keep then
            Keep := NewSize;
          ReallocMem(Cell^.Data, NewSize);
          P := Cell^.Data;
          If (P = nil) or (P[0] <> Cell^.Pattern) or
             (P[Keep - 1] <> Cell^.Pattern) then begin
            Fail(Format('remote realloc round=%d item=%d', [Round, I]));
            Exit;
          end;
          Cell^.Size := NewSize;
          FillChar(P^, NewSize, Cell^.Pattern);
          Inc(Operations);
        end;
        Digest := MixDigest(Digest,
          UInt64(Cardinal(Cell^.Size)) xor UInt64(Cell^.Pattern));
        If Odd(Round) then
          FreeMemory(Cell^.Data)
        else
          FreeMem(Cell^.Data);
        Cell^.Data := nil;
        Inc(Operations);
      end;
      If not FBarrier.Wait then
        Exit;
    end;
  except
    on E: Exception do
      Fail(UnicodeString(E.ClassName) + ': ' + E.Message);
  end;
end;

function TestContention(out OperationCount: Int64): UInt64;
var
  Barrier: TGenerationBarrier;
  Workers: array[0..ContentionWorkerCount - 1] of TContentionThread;
  I, J: Integer;
begin
  FillChar(ContentionCells, SizeOf(ContentionCells), 0);
  ContentionErrorText := '';
  OperationCount := 0;
  Barrier := TGenerationBarrier.Create(ContentionWorkerCount);
  try
    for I := 0 to High(Workers) do
      Workers[I] := TContentionThread.Create(I, Config.ContentionRounds,
        GlobalSeed, Barrier);
    for I := 0 to High(Workers) do
      Workers[I].Start;
    for I := 0 to High(Workers) do
      Workers[I].WaitFor;
    Result := 0;
    for I := 0 to High(Workers) do begin
      Inc(OperationCount, Workers[I].Operations);
      Result := MixDigest(Result, Workers[I].Digest);
      Workers[I].Free;
    end;
  finally
    Barrier.Free;
  end;
  for I := 0 to High(ContentionCells) do
    for J := 0 to High(ContentionCells[I]) do
      If ContentionCells[I, J].Data <> nil then begin
        FreeMem(ContentionCells[I, J].Data);
        ContentionCells[I, J].Data := nil;
      end;
  Require(ContentionErrorText = '', 'contention: ' + ContentionErrorText);
end;

constructor TDeferredFreeThread.Create(var Pointers: TPointerArray;
  AFirst, ALast: Integer; AStartEvent: PRTLEvent;
  AReady, ACompleted: PLongInt);
begin
  inherited Create(True);
  FPointers := @Pointers;
  FFirst := AFirst;
  FLast := ALast;
  FStartEvent := AStartEvent;
  FReady := AReady;
  FCompleted := ACompleted;
end;

procedure TDeferredFreeThread.Execute;
var
  I: Integer;
  P: Pointer;
  FreedSize: PtrUInt;
begin
  try
    try
      InterlockedIncrement(FReady^);
      RTLEventWaitFor(FStartEvent);
      for I := FFirst to FLast do begin
        P := FPointers^[I];
        FreedSize := MemSize(P);
        If FreedSize = 0 then
          raise Exception.CreateFmt('deferred MemSize returned zero item=%d', [I]);
        FreeMem(P);
        FPointers^[I] := nil;
        Digest := MixDigest(Digest, UInt64(FreedSize) xor UInt64(Cardinal(I)));
        Inc(Freed);
      end;
    except
      on E: Exception do
        ErrorText := UnicodeString(E.ClassName) + ': ' + E.Message;
    end;
  finally
    InterlockedIncrement(FCompleted^);
  end;
end;

constructor TForcedAllocThread.Create(AId, ASize, AIterations: Integer;
  AStartEvent: PRTLEvent; AReady, AEntered, ACompleted: PLongInt);
begin
  inherited Create(True);
  FId := AId;
  FSize := ASize;
  FIterations := AIterations;
  FStartEvent := AStartEvent;
  FReady := AReady;
  FEntered := AEntered;
  FCompleted := ACompleted;
end;

procedure TForcedAllocThread.Execute;
var
  I: Integer;
  P: PByte;
  AllocatedSize: PtrUInt;
begin
  try
    try
      InterlockedIncrement(FReady^);
      RTLEventWaitFor(FStartEvent);
      InterlockedIncrement(FEntered^);
      for I := 1 to FIterations do begin
        GetMem(P, FSize);
        If P = nil then
          raise Exception.Create('forced GetMem returned nil');
        AllocatedSize := MemSize(P);
        If AllocatedSize < PtrUInt(FSize) then
          raise Exception.CreateFmt('forced MemSize=%d requested=%d',
            [AllocatedSize, FSize]);
        P[0] := Byte(I xor FId);
        P[FSize - 1] := Byte((I * 17) xor FId);
        Digest := MixDigest(Digest,
          UInt64(P[0]) shl 16 xor UInt64(P[FSize - 1]) shl 8 xor
          UInt64(Cardinal(FId)));
        FreeMem(P);
        Inc(Operations);
      end;
    except
      on E: Exception do
        ErrorText := UnicodeString(E.ClassName) + ': ' + E.Message;
    end;
  finally
    InterlockedIncrement(FCompleted^);
  end;
end;

function TestForcedGetMemContention(out OperationCount: Int64): UInt64;
var
  Workers: array[0..DeferredWorkerCount - 1] of TForcedAllocThread;
  StartEvents: array[0..DeferredWorkerCount - 1] of PRTLEvent;
  Ready, Entered, Completed: LongInt;
  SleepBefore: Cardinal;
  Deadline: UInt64;
  I: Integer;
  LocksHeld: Boolean;
begin
  FillChar(Workers, SizeOf(Workers), 0);
  FillChar(StartEvents, SizeOf(StartEvents), 0);
  Ready := 0;
  Entered := 0;
  Completed := 0;
  LocksHeld := False;
  OperationCount := 0;
  Result := 0;
  try
    for I := 0 to High(StartEvents) do
      StartEvents[I] := RTLEventCreate;
    for I := 0 to High(Workers) do begin
      Workers[I] := TForcedAllocThread.Create(I, 512,
        Config.ForcedAllocIterations, StartEvents[I], @Ready, @Entered,
        @Completed);
      Workers[I].Start;
    end;
    Deadline := GetTickCount64 + 5000;
    while InterlockedExchangeAdd(Ready, 0) <> DeferredWorkerCount do
      If GetTickCount64 >= Deadline then
        raise Exception.CreateFmt('forced allocation ready stalled ready=%d',
          [Ready])
      else
        TThread.Yield;
    { 512 maps to class 528.  Lock it and its two larger fallbacks in every
      MoonShard arena, forcing _GetMem into ReleaseCoreSafe. }
    Fpcx64mmTestLockSmallRequestClasses(512, 3, True);
    LocksHeld := True;
    SleepBefore := Fpcx64mmTestSmallGetmemSleepCount;
    for I := 0 to High(StartEvents) do
      RTLEventSetEvent(StartEvents[I]);
    Deadline := GetTickCount64 + 5000;
    while ((InterlockedExchangeAdd(Entered, 0) <> DeferredWorkerCount) or
           (Fpcx64mmTestSmallGetmemSleepCount = SleepBefore)) and
          (GetTickCount64 < Deadline) do
      TThread.Yield;
    Require(InterlockedExchangeAdd(Entered, 0) = DeferredWorkerCount,
      Format('forced allocation entry stalled entered=%d', [Entered]));
    Require(Fpcx64mmTestSmallGetmemSleepCount <> SleepBefore,
      'forced allocation did not reach ReleaseCore contention');
    Require(InterlockedExchangeAdd(Completed, 0) = 0,
      'forced allocation escaped three locked classes');
    Fpcx64mmTestLockSmallRequestClasses(512, 3, False);
    LocksHeld := False;
    Deadline := GetTickCount64 + 5000;
    while (InterlockedExchangeAdd(Completed, 0) <> DeferredWorkerCount) and
          (GetTickCount64 < Deadline) do
      TThread.Yield;
    Require(InterlockedExchangeAdd(Completed, 0) = DeferredWorkerCount,
      Format('forced allocation workers stalled completed=%d', [Completed]));
    for I := 0 to High(Workers) do begin
      Workers[I].WaitFor;
      Require(Workers[I].ErrorText = '', 'forced allocation worker: ' +
        Workers[I].ErrorText);
      Require(Workers[I].Operations = Config.ForcedAllocIterations,
        'forced allocation operation count');
      Inc(OperationCount, Workers[I].Operations);
      Result := MixDigest(Result, Workers[I].Digest);
    end;
  finally
    If LocksHeld then
      Fpcx64mmTestLockSmallRequestClasses(512, 3, False);
    for I := 0 to High(StartEvents) do
      If StartEvents[I] <> nil then
        RTLEventSetEvent(StartEvents[I]);
    for I := 0 to High(Workers) do
      If Workers[I] <> nil then begin
        Workers[I].WaitFor;
        Workers[I].Free;
      end;
    for I := 0 to High(StartEvents) do
      If StartEvents[I] <> nil then
        RTLEventDestroy(StartEvents[I]);
  end;
end;

function RunDeferredCollision(Size, BlockCount: Integer;
  Small: Boolean): UInt64;
var
  Pointers: TPointerArray;
  Workers: array[0..DeferredWorkerCount - 1] of TDeferredFreeThread;
  StartEvents: array[0..DeferredWorkerCount - 1] of PRTLEvent;
  DrainPointers: TPointerArray;
  Sentinel, Probe, Probe2: Pointer;
  I, First, Last, Freed, DrainCount: Integer;
  Ready, Completed: LongInt;
  Deadline: UInt64;
  LockHeld: Boolean;
begin
  SetLength(Pointers, BlockCount);
  GetMem(Sentinel, Size);
  Require(Sentinel <> nil, 'deferred sentinel allocation');
  for I := 0 to High(Pointers) do begin
    GetMem(Pointers[I], Size);
    Require(Pointers[I] <> nil, 'deferred allocation');
    PByte(Pointers[I])[0] := Byte(I);
  end;
  Ready := 0;
  Completed := 0;
  LockHeld := False;
  FillChar(Workers, SizeOf(Workers), 0);
  FillChar(StartEvents, SizeOf(StartEvents), 0);
  try
    for I := 0 to High(StartEvents) do
      StartEvents[I] := RTLEventCreate;
    for I := 0 to High(Workers) do begin
      First := I * BlockCount div DeferredWorkerCount;
      Last := (I + 1) * BlockCount div DeferredWorkerCount - 1;
      Workers[I] := TDeferredFreeThread.Create(Pointers, First, Last,
        StartEvents[I], @Ready, @Completed);
      Workers[I].Start;
    end;
    Deadline := GetTickCount64 + 5000;
    while InterlockedExchangeAdd(Ready, 0) <> DeferredWorkerCount do
      If GetTickCount64 >= Deadline then
        raise Exception.CreateFmt('deferred ready stalled ready=%d', [Ready])
      else
        TThread.Yield;
    { Creating and starting TThread may allocate the same small class.  Lock
      only after every worker has entered Execute and reached the start gate. }
    If Small then
      Fpcx64mmTestLockSmallBlockType(Sentinel, True)
    else
      Fpcx64mmTestLockMedium(Sentinel, True);
    LockHeld := True;
    for I := 0 to High(StartEvents) do
      RTLEventSetEvent(StartEvents[I]);
    Deadline := GetTickCount64 + 5000;
    while (InterlockedExchangeAdd(Completed, 0) <> DeferredWorkerCount) and
          (GetTickCount64 < Deadline) do
      TThread.Yield;
    If InterlockedExchangeAdd(Completed, 0) <> DeferredWorkerCount then begin
      If Small then
        Fpcx64mmTestLockSmallBlockType(Sentinel, False)
      else
        Fpcx64mmTestLockMedium(Sentinel, False);
      LockHeld := False;
      for I := 0 to High(Workers) do
        Workers[I].WaitFor;
      raise Exception.CreateFmt(
        'deferred workers stalled completed=%d expected=%d',
        [Completed, DeferredWorkerCount]);
    end;
    for I := 0 to High(Workers) do
      Workers[I].WaitFor;
    Result := 0;
    Freed := 0;
    for I := 0 to High(Workers) do begin
      Require(Workers[I].ErrorText = '', 'deferred worker: ' +
        Workers[I].ErrorText);
      Inc(Freed, Workers[I].Freed);
      Result := MixDigest(Result, Workers[I].Digest);
    end;
    Require(Freed = BlockCount,
      Format('deferred freed=%d expected=%d', [Freed, BlockCount]));
    If Small then
      Require(Fpcx64mmTestSmallLastFreeCount(Sentinel) = Cardinal(BlockCount),
        Format('small pending=%d expected=%d',
          [Fpcx64mmTestSmallLastFreeCount(Sentinel), BlockCount]))
    else
      Require(Fpcx64mmTestMediumLastFree(Sentinel) <> nil,
        'medium pending list is empty');
  finally
    If LockHeld then begin
      If Small then
        Fpcx64mmTestLockSmallBlockType(Sentinel, False)
      else
        Fpcx64mmTestLockMedium(Sentinel, False);
    end;
    for I := 0 to High(StartEvents) do
      If StartEvents[I] <> nil then
        RTLEventSetEvent(StartEvents[I]);
    for I := 0 to High(Workers) do
      If Workers[I] <> nil then begin
        Workers[I].WaitFor;
        Workers[I].Free;
      end;
    for I := 0 to High(StartEvents) do
      If StartEvents[I] <> nil then
        RTLEventDestroy(StartEvents[I]);
  end;
  If Small then begin
    { A free which empties its pool can return before visiting the pending
      list.  That is valid: GetMem consumes pending same-class blocks in O(1).
      Drain through the public allocation path and then release the live set. }
    SetLength(DrainPointers, BlockCount);
    DrainCount := 0;
    while Fpcx64mmTestSmallLastFreeCount(Sentinel) <> 0 do begin
      Require(DrainCount < Length(DrainPointers),
        'small pending count exceeds inserted blocks');
      GetMem(DrainPointers[DrainCount], Size);
      Require(DrainPointers[DrainCount] <> nil,
        'small pending drain allocation');
      Inc(DrainCount);
    end;
    Require(DrainCount = BlockCount,
      Format('small pending drained=%d expected=%d',
        [DrainCount, BlockCount]));
    for I := 0 to DrainCount - 1 do
      FreeMem(DrainPointers[I]);
    FreeMem(Sentinel);
  end else begin
    FreeMem(Sentinel);
    GetMem(Probe2, Size);
    Require(Probe2 <> nil, 'medium deferred anchor allocation');
    DrainCount := 0;
    while Fpcx64mmTestMediumLastFree(Probe2) <> nil do begin
      Require(DrainCount < BlockCount,
        'medium pending list did not make progress');
      GetMem(Probe, Size);
      Require(Probe <> nil, 'medium deferred drain allocation');
      FreeMem(Probe);
      Inc(DrainCount);
    end;
    Require(Fpcx64mmTestMediumLastFree(Probe2) = nil,
      'medium pending list was not drained');
    FreeMem(Probe2);
  end;
end;

constructor TManagedFanoutThread.Create(AId, AIterations: Integer;
  const AText: UnicodeString; const AAnsi: RawByteString;
  const ABytes: TBytes; const AGuard: IGuardProbe);
begin
  inherited Create(True);
  FId := AId;
  FIterations := AIterations;
  FText := AText;
  FAnsi := AAnsi;
  FBytes := ABytes;
  FGuard := AGuard;
end;

procedure TManagedFanoutThread.Execute;
var
  I, J: Integer;
  U, UCopy: UnicodeString;
  A, ACopy: RawByteString;
  B: TBytes;
  G: IGuardProbe;
begin
  try
    for I := 1 to FIterations do begin
      U := FText;
      A := FAnsi;
      B := Copy(FBytes);
      G := FGuard;
      If (U <> FText) or (A <> FAnsi) or (G = nil) or not G.Valid then
        raise Exception.Create('managed immutable copy');
      UCopy := U;
      UniqueString(UCopy);
      UCopy[1] := WideChar(Ord(UCopy[1]) xor 1);
      ACopy := A;
      UniqueString(ACopy);
      ACopy[1] := AnsiChar(Ord(ACopy[1]) xor 1);
      If (U <> FText) or (A <> FAnsi) then
        raise Exception.Create('managed COW changed source');
      SetLength(B, Length(B) + ((I + FId) and 31));
      for J := Length(FBytes) to High(B) do
        B[J] := Byte(I xor FId xor J);
      try
        If (I and 127) = 0 then
          raise EAbort.Create('expected managed unwind');
        Digest := MixDigest(Digest,
          UInt64(Length(U)) shl 32 xor UInt64(Length(A)) xor UInt64(Length(B)));
      except
        on E: EAbort do
          Digest := MixDigest(Digest, UInt64(Cardinal(I)) xor $EAB07);
      end;
      U := '';
      A := '';
      B := nil;
      G := nil;
      Inc(Operations);
    end;
  except
    on E: Exception do
      ErrorText := UnicodeString(E.ClassName) + ': ' + E.Message;
  end;
end;

function TestManagedFanout: UInt64;
var
  Workers: array[0..FanoutWorkerCount - 1] of TManagedFanoutThread;
  SharedText: UnicodeString;
  SharedAnsi: RawByteString;
  SharedBytes: TBytes;
  SharedGuard: IGuardProbe;
  DestroyedBefore, I: Integer;
begin
  SharedText := UnicodeString('immutable-unicode-') +
    UnicodeString(IntToStr(GlobalSeed));
  SharedAnsi := RawByteString('immutable-raw-') +
    RawByteString(IntToStr(GlobalSeed));
  SetLength(SharedBytes, 1024);
  for I := 0 to High(SharedBytes) do
    SharedBytes[I] := Byte(I * 43);
  DestroyedBefore := GuardDestroyed;
  SharedGuard := TGuardProbe.Create(-1);
  for I := 0 to High(Workers) do
    Workers[I] := TManagedFanoutThread.Create(I, Config.FanoutIterations,
      SharedText, SharedAnsi, SharedBytes, SharedGuard);
  for I := 0 to High(Workers) do
    Workers[I].Start;
  for I := 0 to High(Workers) do
    Workers[I].WaitFor;
  Result := 0;
  for I := 0 to High(Workers) do begin
    Require(Workers[I].ErrorText = '', 'managed fanout: ' +
      Workers[I].ErrorText);
    Require(Workers[I].Operations = Config.FanoutIterations,
      'managed fanout operation count');
    Result := MixDigest(Result, Workers[I].Digest);
    Workers[I].Free;
  end;
  SharedGuard := nil;
  Require(GuardDestroyed = DestroyedBefore + 1,
    Format('managed shared guard destroyed=%d expected=%d',
      [GuardDestroyed, DestroyedBefore + 1]));
end;

procedure ReportPhase(const Name: string; Operations: Int64; Digest: UInt64;
  const Started: TPerfStamp; ProcessCpuStarted: UInt64);
var
  Delta: TPerfDelta;
  ProcessCpu: UInt64;
begin
  Delta := EndPerfStamp(Started);
  ProcessCpu := PulseReadProcessCpuNs - ProcessCpuStarted;
  WriteLn('MM_MASSIVE_PHASE name=', Name,
    ' operations=', Operations,
    ' wall_ns=', Delta.WallNs,
    ' process_cpu_ns=', ProcessCpu,
    ' tsc_ticks=', Delta.TscTicks,
    ' digest=', IntToHex(Digest, 16));
end;

procedure Configure;
var
  Name: string;
  Code: Integer;
begin
  Config.Mode := rmQuick;
  If ParamCount > 0 then begin
    Name := LowerCase(ParamStr(1));
    If Name = 'quick' then
      Config.Mode := rmQuick
    else If Name = 'medium' then
      Config.Mode := rmMedium
    else If Name = 'long' then
      Config.Mode := rmLong
    else
      raise Exception.Create('usage: memory_massive [quick|medium|long] [seed]');
  end;
  GlobalSeed := UInt64($4D41535349564521);
  If ParamCount > 1 then begin
    Val(ParamStr(2), GlobalSeed, Code);
    If Code <> 0 then
      raise Exception.Create('seed must be an unsigned decimal integer');
  end;
  case Config.Mode of
    rmQuick: begin
      Config.PipelineTickets := 1000;
      Config.ContentionRounds := 18;
      Config.FanoutIterations := 4000;
      Config.ForcedAllocIterations := 512;
      Config.SmallDeferredBlocks := 1024;
      Config.MediumDeferredBlocks := 256;
    end;
    rmMedium: begin
      Config.PipelineTickets := 4000;
      Config.ContentionRounds := 60;
      Config.FanoutIterations := 20000;
      Config.ForcedAllocIterations := 2048;
      Config.SmallDeferredBlocks := 4096;
      Config.MediumDeferredBlocks := 1024;
    end;
    rmLong: begin
      Config.PipelineTickets := 16000;
      Config.ContentionRounds := 240;
      Config.FanoutIterations := 100000;
      Config.ForcedAllocIterations := 8192;
      Config.SmallDeferredBlocks := 16384;
      Config.MediumDeferredBlocks := 4096;
    end;
  end;
end;

function ModeText: string;
begin
  case Config.Mode of
    rmQuick: Result := 'quick';
    rmMedium: Result := 'medium';
  else
    Result := 'long';
  end;
end;

var
  Started: TPerfStamp;
  ProcessCpuStarted: UInt64;
  Digest: UInt64;
  TotalDigest: UInt64;
  TotalStarted: UInt64;
  PhaseOperations: Int64;
begin
  try
    Configure;
    InitializePerfClock;
    InitCriticalSection(PipelineErrorLock);
    InitCriticalSection(ContentionErrorLock);
    TotalStarted := GetTickCount64;
    TotalDigest := 0;
    WriteLn('MM_MASSIVE_BEGIN mode=', ModeText, ' seed=', GlobalSeed);

    ProcessCpuStarted := PulseReadProcessCpuNs;
    Started := BeginPerfStamp;
    Digest := TestPipeline;
    ReportPhase('managed-five-hop',
      Int64(Config.PipelineTickets) * PipelineStageCount, Digest,
      Started, ProcessCpuStarted);
    TotalDigest := MixDigest(TotalDigest, Digest);
    {$ifdef FPCX64MM_DIAGNOSTIC}
    Fpcx64mmDebugSetContext('massive-pipeline');
    Fpcx64mmDebugVerifyHeap;
    {$endif}

    ProcessCpuStarted := PulseReadProcessCpuNs;
    Started := BeginPerfStamp;
    Digest := TestContention(PhaseOperations);
    ReportPhase('barrier-remote-realloc-free',
      PhaseOperations, Digest, Started, ProcessCpuStarted);
    TotalDigest := MixDigest(TotalDigest, Digest);
    {$ifdef FPCX64MM_DIAGNOSTIC}
    Fpcx64mmDebugSetContext('massive-contention');
    Fpcx64mmDebugVerifyHeap;
    {$endif}

    ProcessCpuStarted := PulseReadProcessCpuNs;
    Started := BeginPerfStamp;
    Digest := TestForcedGetMemContention(PhaseOperations);
    ReportPhase('forced-getmem-contention', PhaseOperations, Digest,
      Started, ProcessCpuStarted);
    TotalDigest := MixDigest(TotalDigest, Digest);

    ProcessCpuStarted := PulseReadProcessCpuNs;
    Started := BeginPerfStamp;
    { Main allocates every 512-byte block before the handoff, so all blocks
      retain one MoonShard owner arena and expose one exact pending counter. }
    Digest := RunDeferredCollision(512, Config.SmallDeferredBlocks, True);
    ReportPhase('forced-small-deferred-free', Config.SmallDeferredBlocks,
      Digest, Started, ProcessCpuStarted);
    TotalDigest := MixDigest(TotalDigest, Digest);

    ProcessCpuStarted := PulseReadProcessCpuNs;
    Started := BeginPerfStamp;
    Digest := RunDeferredCollision(100500, Config.MediumDeferredBlocks, False);
    ReportPhase('forced-medium-deferred-free', Config.MediumDeferredBlocks,
      Digest, Started, ProcessCpuStarted);
    TotalDigest := MixDigest(TotalDigest, Digest);
    {$ifdef FPCX64MM_DIAGNOSTIC}
    Fpcx64mmDebugSetContext('massive-deferred');
    Fpcx64mmDebugVerifyHeap;
    {$endif}

    ProcessCpuStarted := PulseReadProcessCpuNs;
    Started := BeginPerfStamp;
    Digest := TestManagedFanout;
    ReportPhase('immutable-managed-fanout',
      Int64(Config.FanoutIterations) * FanoutWorkerCount,
      Digest, Started, ProcessCpuStarted);
    TotalDigest := MixDigest(TotalDigest, Digest);
    {$ifdef FPCX64MM_DIAGNOSTIC}
    Fpcx64mmDebugSetContext('massive-managed-fanout');
    Fpcx64mmDebugVerifyHeap;
    {$endif}

    Require(GuardCreated = GuardDestroyed,
      Format('final guards created=%d destroyed=%d',
        [GuardCreated, GuardDestroyed]));
    WriteLn('MEMORY_MASSIVE_PASS elapsed_ms=', GetTickCount64 - TotalStarted,
      ' digest=', IntToHex(TotalDigest, 16),
      ' guards=', GuardCreated);
    DoneCriticalSection(ContentionErrorLock);
    DoneCriticalSection(PipelineErrorLock);
  except
    on E: Exception do begin
      WriteLn('MEMORY_MASSIVE_FAIL ', E.ClassName, ': ', E.Message,
        ' seed=', GlobalSeed);
      Halt(1);
    end;
  end;
end.
