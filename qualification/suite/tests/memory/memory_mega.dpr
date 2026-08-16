program memory_mega;

{ Deterministic memory-manager qualification.

  Every pointer has exactly one owner.  Cross-thread ownership is transferred
  through a fixed-capacity queue protected by an RTL critical section.  The
  producer publishes a completely initialized block and never touches it
  again; the consumer removes the block before checking/reallocating/freeing
  it.  Therefore a failure belongs to the allocator, not to a data race in the
  test.

  Usage: memory_mega [quick|full|soak] [decimal-seed]

  Each phase writes its effective seed before it begins.  This is deliberately
  an ownership-correct workload: no phase intentionally reuses, double-frees,
  or reads a pointer after handing it to another owner.
}

{$ifdef FPC}
  {$mode delphi}{$H+}
{$endif}
{$APPTYPE CONSOLE}
{$Q-}{$R-}

uses
{$ifdef FPC}
  mormot.core.fpcx64mm,
  {$ifndef windows}
  cthreads,
  {$endif}
{$else}
  Winapi.Windows,
{$endif}
  SysUtils,
  Classes;

const
  WorkerCount = 4;
  FuzzSlotCount = 512;
  SweepWindowSize = 64;
  QueueCapacity = 257;
  SaturationCanaryCount = 128;
  SaturationSlotCount = 32;
  SaturationWorkerLimit = 26; // stay below the authorized 27 logical CPUs

  TransitionSizeCount = 43;
  TransitionSizes: array[0..TransitionSizeCount - 1] of Integer = (
    1, 7, 8, 9, 15, 16, 17, 23, 24, 25, 31, 32, 33,
    47, 48, 49, 55, 56, 57, 63, 64, 65, 127, 128, 129,
    255, 256, 257, 511, 512, 513, 2599, 2600, 2601,
    17495, 17496, 17497, 17504, 17505, 65536, 100500, 300000,
    1048576);

  LifecycleSizeCount = 20;
  LifecycleSizes: array[0..LifecycleSizeCount - 1] of Integer = (
    1, 8, 16, 24, 32, 48, 56, 64, 120, 128,
    200, 248, 256, 320, 800, 1200, 2600, 17496, 17497, 100500);

type
  TRunMode = (rmQuick, rmFull, rmSoak);

  TRunConfig = record
    Mode: TRunMode;
    FuzzSoloOps: Integer;
    FuzzWorkerOps: Integer;
    TransferBlocks: Integer;
    LifecycleRounds: Integer;
    SaturationMs: Integer;
  end;

  TBlock = record
    Data: PByte;
    Size: Integer;
    Id: Integer;
    Pattern: UInt64;
  end;

  TBlockArray = array of TBlock;

  TFuzzSlot = record
    Data: PByte;
    Size: Integer;
    Pattern: Byte;
  end;

  TFuzzThread = class(TThread)
  private
    FId: Integer;
    FOps: Integer;
    FRng: UInt64;
    FSlots: array[0..FuzzSlotCount - 1] of TFuzzSlot;
    procedure Fail(ACode, ASlot: Integer);
    procedure Drain;
  protected
    procedure Execute; override;
  public
    ErrorCode: Integer;
    ErrorSlot: Integer;
    ErrorMessage: string;
    constructor Create(AId, AOps: Integer; ASeed: UInt64);
    procedure Run;
  end;

  TBlockQueue = class
  private
    FLock: TRTLCriticalSection;
    FItems: array[0..QueueCapacity - 1] of TBlock;
    FHead: Integer;
    FTail: Integer;
    FCount: Integer;
    FDone: Boolean;
    FAborted: Boolean;
    FErrorCode: Integer;
    FErrorBlock: Integer;
    FErrorText: string;
  public
    constructor Create;
    destructor Destroy; override;
    function Push(var Block: TBlock): Boolean;
    function Pop(out Block: TBlock): Boolean;
    function TryPush(var Block: TBlock): Boolean;
    function TryPop(out Block: TBlock): Boolean;
    procedure MarkDone;
    procedure ReportError(Code, BlockId: Integer; const Detail: string);
    procedure CheckResult;
  end;

  TSaturationThread = class(TThread)
  private
    FId: Integer;
    FDurationMs: Integer;
    FSeed: UInt64;
    FInbound: TBlockQueue;
    FOutbound: TBlockQueue;
    FProbeIterations: Integer;
    FSlots: array[0..SaturationSlotCount - 1] of TBlock;
    procedure Consume(var Block: TBlock; Random: UInt64);
    procedure Probe(const Block: TBlock; Random: UInt64);
    procedure RunProbe;
  protected
    procedure Execute; override;
  public
    ErrorCode: Integer;
    ErrorBlock: Integer;
    ErrorMessage: string;
    Operations: Int64;
    Checksum: UInt64;
    constructor Create(AId, ADurationMs: Integer; ASeed: UInt64;
      AInbound, AOutbound: TBlockQueue; AProbeOnly: Boolean);
  end;

  TProducerThread = class(TThread)
  private
    FQueue: TBlockQueue;
    FProducerId: Integer;
    FBlockCount: Integer;
    FFixedSize: Integer;
    FSeed: UInt64;
  protected
    procedure Execute; override;
  public
    ErrorCode: Integer;
    constructor Create(AQueue: TBlockQueue; AProducerId, ABlockCount,
      AFixedSize: Integer; ASeed: UInt64);
  end;

  TConsumerThread = class(TThread)
  private
    FQueue: TBlockQueue;
    FConsumerId: Integer;
  protected
    procedure Execute; override;
  public
    ErrorCode: Integer;
    constructor Create(AQueue: TBlockQueue; AConsumerId: Integer);
  end;

var
  Config: TRunConfig;
  GlobalSeed: UInt64;
  StartedAt: UInt64;

function NextRandom(var State: UInt64): UInt64; inline;
begin
  State := State xor (State shr 12);
  State := State xor (State shl 25);
  State := State xor (State shr 27);
  Result := State * UInt64($2545F4914F6CDD1D);
end;

function PatternFor(BlockId: Integer; Seed: UInt64): UInt64; inline;
begin
  Seed := Seed xor (UInt64(Cardinal(BlockId)) * UInt64($9E3779B185EBCA87));
  Seed := Seed xor (Seed shr 29);
  Seed := Seed * UInt64($D6E8FEB86659FD93);
  Result := Seed xor (Seed shr 31);
end;

function PickSize(Random: UInt64): Integer;
var
  Bucket: Integer;
begin
  Bucket := Integer(Random mod 100);
  If Bucket < 65 then
    Result := 1 + Integer((Random shr 8) mod 256)
  else If Bucket < 82 then
    Result := 257 + Integer((Random shr 8) mod 2344)
  else If Bucket < 94 then
    Result := 2601 + Integer((Random shr 8) mod 14896)
  else If Bucket < 99 then
    Result := 17497 + Integer((Random shr 8) mod 244648)
  else
    Result := 262145 + Integer((Random shr 8) mod 786432);
end;

procedure Require(Condition: Boolean; const MessageText: string);
begin
  If not Condition then
    raise Exception.Create(MessageText);
end;

procedure BeginPhase(const Name: string);
begin
  WriteLn('MEMORY_MEGA_PHASE ', Name, ' seed=', GlobalSeed);
  {$ifdef FPCX64MM_DIAGNOSTIC}
  Fpcx64mmDebugSetContext(PAnsiChar(Name));
  {$endif FPCX64MM_DIAGNOSTIC}
end;

procedure VerifyHeapAfterPhase(const Name: string);
begin
  {$ifdef FPCX64MM_DIAGNOSTIC}
  Fpcx64mmDebugSetContext(PAnsiChar(Name));
  Fpcx64mmDebugVerifyHeap;
  {$endif FPCX64MM_DIAGNOSTIC}
end;

procedure FillBlock(const Block: TBlock);
var
  I, J, WordCount: Integer;
  Value: UInt64;
begin
  WordCount := Block.Size div SizeOf(UInt64);
  for I := 0 to WordCount - 1 do
    PUInt64(Block.Data)[I] := Block.Pattern xor
      (UInt64(I) * UInt64($9E3779B185EBCA87));
  If Block.Size and 7 <> 0 then begin
    Value := Block.Pattern xor
      (UInt64(WordCount) * UInt64($9E3779B185EBCA87));
    for J := 0 to (Block.Size and 7) - 1 do
      Block.Data[WordCount * SizeOf(UInt64) + J] := PByte(@Value)[J];
  end;
end;

function FirstMismatch(const Block: TBlock; Limit: Integer): Integer;
var
  I, J, WordCount: Integer;
  Expected: UInt64;
begin
  If Limit > Block.Size then
    Limit := Block.Size;
  WordCount := Limit div SizeOf(UInt64);
  for I := 0 to WordCount - 1 do begin
    Expected := Block.Pattern xor
      (UInt64(I) * UInt64($9E3779B185EBCA87));
    If PUInt64(Block.Data)[I] <> Expected then
      for J := 0 to SizeOf(UInt64) - 1 do
        If Block.Data[I * SizeOf(UInt64) + J] <> PByte(@Expected)[J] then
          Exit(I * SizeOf(UInt64) + J);
  end;
  If Limit and 7 <> 0 then begin
    Expected := Block.Pattern xor
      (UInt64(WordCount) * UInt64($9E3779B185EBCA87));
    for J := 0 to (Limit and 7) - 1 do
      If Block.Data[WordCount * SizeOf(UInt64) + J] <> PByte(@Expected)[J] then
        Exit(WordCount * SizeOf(UInt64) + J);
  end;
  Result := -1;
end;

function ExpectedByte(const Block: TBlock; Offset: Integer): Byte; inline;
var
  Expected: UInt64;
begin
  Expected := Block.Pattern xor
    (UInt64(Offset div SizeOf(UInt64)) * UInt64($9E3779B185EBCA87));
  Result := PByte(@Expected)[Offset and 7];
end;

procedure VerifyBlock(const Block: TBlock; const Context: string);
var
  Bad: Integer;
begin
  Require(Block.Data <> nil, Format('%s: nil block id=%d size=%d',
    [Context, Block.Id, Block.Size]));
  Require((NativeUInt(Block.Data) and 15) = 0,
    Format('%s: alignment id=%d size=%d address=%x',
      [Context, Block.Id, Block.Size, NativeUInt(Block.Data)]));
  Bad := FirstMismatch(Block, Block.Size);
  If Bad >= 0 then
    raise Exception.CreateFmt(
      '%s: content id=%d size=%d offset=%d expected=%d actual=%d',
      [Context, Block.Id, Block.Size, Bad, ExpectedByte(Block, Bad),
       Block.Data[Bad]]);
end;

procedure AllocateBlock(var Block: TBlock; BlockId, Size: Integer;
  Seed: UInt64);
begin
  {$ifdef FPCX64MM_DIAGNOSTIC}
  Fpcx64mmDebugSetContext('block-allocate');
  {$endif FPCX64MM_DIAGNOSTIC}
  Block.Id := BlockId;
  Block.Size := Size;
  Block.Pattern := PatternFor(BlockId, Seed);
  GetMem(Block.Data, Size);
  Require(Block.Data <> nil, Format('GetMem returned nil id=%d size=%d',
    [BlockId, Size]));
  Require((NativeUInt(Block.Data) and 15) = 0,
    Format('alignment id=%d size=%d address=%x',
      [BlockId, Size, NativeUInt(Block.Data)]));
  FillBlock(Block);
end;

procedure ReallocateBlock(var Block: TBlock; NewSize: Integer;
  const Context: string);
var
  OldSize, Keep, Bad: Integer;
begin
  {$ifdef FPCX64MM_DIAGNOSTIC}
  Fpcx64mmDebugSetContext('block-reallocate');
  {$endif FPCX64MM_DIAGNOSTIC}
  VerifyBlock(Block, Context + '-before');
  OldSize := Block.Size;
  ReallocMem(Block.Data, NewSize);
  Require(Block.Data <> nil, Format('%s: realloc nil id=%d old=%d new=%d',
    [Context, Block.Id, OldSize, NewSize]));
  Require((NativeUInt(Block.Data) and 15) = 0,
    Format('%s: realloc alignment id=%d new=%d address=%x',
      [Context, Block.Id, NewSize, NativeUInt(Block.Data)]));
  Keep := OldSize;
  If NewSize < Keep then
    Keep := NewSize;
  Block.Size := NewSize;
  Bad := FirstMismatch(Block, Keep);
  Require(Bad < 0,
    Format('%s: realloc prefix id=%d old=%d new=%d offset=%d',
      [Context, Block.Id, OldSize, NewSize, Bad]));
  FillBlock(Block);
  VerifyBlock(Block, Context + '-after');
end;

procedure FreeBlock(var Block: TBlock; const Context: string);
begin
  {$ifdef FPCX64MM_DIAGNOSTIC}
  Fpcx64mmDebugSetContext('block-free');
  {$endif FPCX64MM_DIAGNOSTIC}
  VerifyBlock(Block, Context);
  FreeMem(Block.Data);
  Block.Data := nil;
  Block.Size := 0;
end;

function TransferSize(BlockId, FixedSize: Integer; Seed: UInt64): Integer;
var
  R: UInt64;
begin
  If FixedSize > 0 then
    Exit(FixedSize);
  R := Seed xor (UInt64(Cardinal(BlockId)) * UInt64($D6E8FEB86659FD93));
  Result := PickSize(R);
  case BlockId and 31 of
    0: Result := 1;
    1: Result := 56;
    2: Result := 64;
    3: Result := 128;
    4: Result := 256;
    5: Result := 257;
    6: Result := 2599;
    7: Result := 2600;
    8: Result := 2601;
    9: Result := 17495;
    10: Result := 17496;
    11: Result := 17497;
    12: Result := 17504;
    13: Result := 17505;
    14: Result := 100500;
    15: Result := 300000;
  end;
end;

function TransferReallocSize(const Block: TBlock): Integer;
begin
  case Block.Id and 7 of
    0: Result := Block.Size;
    1: Result := 56;
    2: Result := 256;
    3: Result := 2600;
    4: Result := 17496;
    5: Result := 17497;
    6: Result := 100500;
  else
    Result := 300000;
  end;
end;

procedure TestContracts;
var
  P: PByte;
  I: Integer;
begin
  P := nil;
  GetMem(P, 0);
  Require(P <> nil, 'GetMem(0) did not return an allocatable block');
  P[0] := $A5;
  FreeMem(P);

  P := nil;
  ReallocMem(P, 257);
  Require(P <> nil, 'ReallocMem(nil,size) returned nil');
  FillChar(P^, 257, $3C);
  ReallocMem(P, 0);
  Require(P = nil, 'ReallocMem(pointer,0) did not clear the pointer');

  P := AllocMem(4097);
  Require(P <> nil, 'AllocMem returned nil');
  for I := 0 to 4096 do
    Require(P[I] = 0, Format('AllocMem not zero at offset=%d', [I]));
  FreeMem(P);
  FreeMem(nil);
  WriteLn('PASS contracts');
end;

procedure TestSizeSweep;
var
  Window: array[0..SweepWindowSize - 1] of TBlock;
  I, Slot, Size, BlockId: Integer;
begin
  FillChar(Window, SizeOf(Window), 0);
  BlockId := 0;
  for Size := 1 to 20000 do begin
    Slot := BlockId mod SweepWindowSize;
    If Window[Slot].Data <> nil then
      FreeBlock(Window[Slot], 'sweep-small-release');
    AllocateBlock(Window[Slot], BlockId, Size, GlobalSeed);
    Inc(BlockId);
  end;
  Size := 20251;
  while Size <= 300000 do begin
    Slot := BlockId mod SweepWindowSize;
    If Window[Slot].Data <> nil then
      FreeBlock(Window[Slot], 'sweep-medium-release');
    AllocateBlock(Window[Slot], BlockId, Size, GlobalSeed);
    Inc(BlockId);
    Inc(Size, 251);
  end;
  for I := 0 to High(Window) do
    If Window[I].Data <> nil then
      FreeBlock(Window[I], 'sweep-drain');
  WriteLn('PASS size-sweep allocations=', BlockId);
end;

procedure TestReallocMatrix;
var
  Block: TBlock;
  I, J, BlockId: Integer;
begin
  Block.Data := nil;
  Block.Size := 0;
  Block.Id := 0;
  Block.Pattern := 0;
  BlockId := 1000000;
  for I := 0 to TransitionSizeCount - 1 do
    for J := 0 to TransitionSizeCount - 1 do begin
      AllocateBlock(Block, BlockId, TransitionSizes[I], GlobalSeed);
      ReallocateBlock(Block, TransitionSizes[J], 'realloc-matrix');
      FreeBlock(Block, 'realloc-matrix-release');
      Inc(BlockId);
    end;
  WriteLn('PASS realloc-matrix transitions=',
    TransitionSizeCount * TransitionSizeCount);
end;

procedure TestPoolLifecycle;
const
  BlockCount = 384;
var
  Blocks: array[0..BlockCount - 1] of TBlock;
  SizeIndex, Round, I, BlockId: Integer;
begin
  FillChar(Blocks, SizeOf(Blocks), 0);
  BlockId := 2000000;
  for SizeIndex := 0 to LifecycleSizeCount - 1 do
    for Round := 1 to Config.LifecycleRounds do begin
      for I := 0 to High(Blocks) do begin
        AllocateBlock(Blocks[I], BlockId, LifecycleSizes[SizeIndex],
          GlobalSeed xor UInt64(Round));
        Inc(BlockId);
      end;
      for I := 1 to High(Blocks) do
        If Odd(I) then
          FreeBlock(Blocks[I], 'lifecycle-odd');
      for I := 1 to High(Blocks) do
        If Odd(I) then begin
          AllocateBlock(Blocks[I], BlockId, LifecycleSizes[SizeIndex],
            GlobalSeed xor UInt64(Round));
          Inc(BlockId);
        end;
      for I := High(Blocks) downto 0 do
        FreeBlock(Blocks[I], 'lifecycle-drain');
      for I := 1 to 256 do begin
        AllocateBlock(Blocks[0], BlockId, LifecycleSizes[SizeIndex],
          GlobalSeed xor UInt64(Round));
        Inc(BlockId);
        FreeBlock(Blocks[0], 'lifecycle-single');
      end;
    end;
  WriteLn('PASS pool-lifecycle rounds=', Config.LifecycleRounds,
    ' sizes=', LifecycleSizeCount);
end;

constructor TFuzzThread.Create(AId, AOps: Integer; ASeed: UInt64);
begin
  inherited Create(True);
  FId := AId;
  FOps := AOps;
  FRng := ASeed xor (UInt64(Cardinal(AId)) shl 32) xor
    UInt64($6D6F6F6E626F7421);
end;

procedure TFuzzThread.Fail(ACode, ASlot: Integer);
begin
  If ErrorCode = 0 then begin
    ErrorCode := ACode;
    ErrorSlot := ASlot;
  end;
end;

procedure TFuzzThread.Drain;
var
  SlotIndex, J: Integer;
begin
  for SlotIndex := 0 to High(FSlots) do
    If FSlots[SlotIndex].Data <> nil then begin
      If ErrorCode = 0 then
        for J := 0 to FSlots[SlotIndex].Size - 1 do
          If FSlots[SlotIndex].Data[J] <> FSlots[SlotIndex].Pattern then begin
            Fail(5, SlotIndex);
            Break;
          end;
      FreeMem(FSlots[SlotIndex].Data);
      FSlots[SlotIndex].Data := nil;
    end;
end;

procedure TFuzzThread.Run;
var
  K, SlotIndex, J, NewSize, Keep: Integer;
  R: UInt64;
  Slot: ^TFuzzSlot;
begin
  try
    for K := 1 to FOps do begin
      R := NextRandom(FRng);
      SlotIndex := Integer(R mod FuzzSlotCount);
      Slot := @FSlots[SlotIndex];
      If Slot^.Data = nil then begin
        Slot^.Size := PickSize(R shr 16);
        Slot^.Pattern := Byte(R shr 56) or 1;
        GetMem(Slot^.Data, Slot^.Size);
        If (Slot^.Data = nil) or
           ((NativeUInt(Slot^.Data) and 15) <> 0) then begin
          Fail(1, SlotIndex);
          Break;
        end;
        FillChar(Slot^.Data^, Slot^.Size, Slot^.Pattern);
      end else begin
        for J := 0 to Slot^.Size - 1 do
          If Slot^.Data[J] <> Slot^.Pattern then begin
            Fail(2, SlotIndex);
            Break;
          end;
        If ErrorCode <> 0 then
          Break;
        If ((R shr 40) and 3) = 0 then begin
          NewSize := PickSize(R shr 24);
          Keep := Slot^.Size;
          If NewSize < Keep then
            Keep := NewSize;
          ReallocMem(Slot^.Data, NewSize);
          If Slot^.Data = nil then begin
            Fail(3, SlotIndex);
            Break;
          end;
          for J := 0 to Keep - 1 do
            If Slot^.Data[J] <> Slot^.Pattern then begin
              Fail(4, SlotIndex);
              Break;
            end;
          If ErrorCode <> 0 then
            Break;
          Slot^.Size := NewSize;
          Slot^.Pattern := Byte(R shr 48) or 1;
          FillChar(Slot^.Data^, Slot^.Size, Slot^.Pattern);
        end else begin
          FreeMem(Slot^.Data);
          Slot^.Data := nil;
        end;
      end;
    end;
  finally
    Drain;
  end;
end;

procedure TFuzzThread.Execute;
begin
  {$ifdef FPCX64MM_DIAGNOSTIC}
  Fpcx64mmDebugSetContext('independent-fuzz-worker');
  {$endif FPCX64MM_DIAGNOSTIC}
  try
    Run;
  except
    on E: Exception do begin
      ErrorCode := 100;
      ErrorSlot := -1;
      ErrorMessage := E.ClassName + ': ' + E.Message;
    end;
  end;
end;

procedure TestIndependentFuzz;
var
  Solo: TFuzzThread;
  Workers: array[0..WorkerCount - 1] of TFuzzThread;
  I: Integer;
begin
  Solo := TFuzzThread.Create(0, Config.FuzzSoloOps, GlobalSeed);
  try
    Solo.Run;
    Require(Solo.ErrorCode = 0,
      Format('fuzz solo code=%d slot=%d seed=%u exception=%s',
        [Solo.ErrorCode, Solo.ErrorSlot, GlobalSeed, Solo.ErrorMessage]));
  finally
    Solo.Free;
  end;

  for I := 0 to High(Workers) do
    Workers[I] := TFuzzThread.Create(I + 1, Config.FuzzWorkerOps,
      GlobalSeed);
  for I := 0 to High(Workers) do
    Workers[I].Start;
  for I := 0 to High(Workers) do
    Workers[I].WaitFor;
  for I := 0 to High(Workers) do begin
    Require(Workers[I].ErrorCode = 0,
      Format('fuzz worker=%d code=%d slot=%d seed=%u exception=%s',
        [I + 1, Workers[I].ErrorCode, Workers[I].ErrorSlot, GlobalSeed,
         Workers[I].ErrorMessage]));
    Workers[I].Free;
  end;
  WriteLn('PASS independent-fuzz ops=',
    Int64(Config.FuzzSoloOps) + Int64(WorkerCount) * Config.FuzzWorkerOps,
    ' seed=', GlobalSeed);
end;

constructor TBlockQueue.Create;
begin
  inherited Create;
  InitCriticalSection(FLock);
end;

destructor TBlockQueue.Destroy;
begin
  DoneCriticalSection(FLock);
  inherited Destroy;
end;

function TBlockQueue.Push(var Block: TBlock): Boolean;
begin
  repeat
    EnterCriticalSection(FLock);
    If FAborted then begin
      LeaveCriticalSection(FLock);
      Exit(False);
    end;
    If FCount < QueueCapacity then begin
      FItems[FTail] := Block;
      Block.Data := nil;
      Inc(FTail);
      If FTail = QueueCapacity then
        FTail := 0;
      Inc(FCount);
      LeaveCriticalSection(FLock);
      Exit(True);
    end;
    LeaveCriticalSection(FLock);
    Sleep(0);
  until False;
end;

function TBlockQueue.Pop(out Block: TBlock): Boolean;
begin
  Block.Data := nil;
  Block.Size := 0;
  Block.Id := 0;
  Block.Pattern := 0;
  repeat
    EnterCriticalSection(FLock);
    If FAborted then begin
      LeaveCriticalSection(FLock);
      Exit(False);
    end;
    If FCount > 0 then begin
      Block := FItems[FHead];
      FItems[FHead].Data := nil;
      Inc(FHead);
      If FHead = QueueCapacity then
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

function TBlockQueue.TryPush(var Block: TBlock): Boolean;
begin
  EnterCriticalSection(FLock);
  If FAborted or (FCount = QueueCapacity) then
    Result := False
  else begin
    FItems[FTail] := Block;
    Block.Data := nil;
    Inc(FTail);
    If FTail = QueueCapacity then
      FTail := 0;
    Inc(FCount);
    Result := True;
  end;
  LeaveCriticalSection(FLock);
end;

function TBlockQueue.TryPop(out Block: TBlock): Boolean;
begin
  Block.Data := nil;
  Block.Size := 0;
  Block.Id := 0;
  Block.Pattern := 0;
  EnterCriticalSection(FLock);
  If FCount = 0 then
    Result := False
  else begin
    Block := FItems[FHead];
    FItems[FHead].Data := nil;
    Inc(FHead);
    If FHead = QueueCapacity then
      FHead := 0;
    Dec(FCount);
    Result := True;
  end;
  LeaveCriticalSection(FLock);
end;

procedure TBlockQueue.MarkDone;
begin
  EnterCriticalSection(FLock);
  FDone := True;
  LeaveCriticalSection(FLock);
end;

procedure TBlockQueue.ReportError(Code, BlockId: Integer; const Detail: string);
var
  FirstError: Boolean;
begin
  FirstError := False;
  EnterCriticalSection(FLock);
  If not FAborted then begin
    FAborted := True;
    FErrorCode := Code;
    FErrorBlock := BlockId;
    FErrorText := Detail;
    FirstError := True;
  end;
  LeaveCriticalSection(FLock);
  If FirstError then
    WriteLn('MEMORY_MEGA_TRANSFER_ERROR code=', Code, ' block=', BlockId,
      ' detail=', Detail, ' seed=', GlobalSeed);
end;

procedure TBlockQueue.CheckResult;
begin
  Require(not FAborted, Format('transfer code=%d block=%d detail=%s seed=%u',
    [FErrorCode, FErrorBlock, FErrorText, GlobalSeed]));
  Require(FCount = 0, Format('transfer queue not empty count=%d', [FCount]));
end;

constructor TProducerThread.Create(AQueue: TBlockQueue; AProducerId,
  ABlockCount, AFixedSize: Integer; ASeed: UInt64);
begin
  inherited Create(True);
  FQueue := AQueue;
  FProducerId := AProducerId;
  FBlockCount := ABlockCount;
  FFixedSize := AFixedSize;
  FSeed := ASeed;
end;

procedure TProducerThread.Execute;
var
  I, BlockId, Size: Integer;
  Block: TBlock;
begin
  {$ifdef FPCX64MM_DIAGNOSTIC}
  Fpcx64mmDebugSetContext('transfer-producer');
  {$endif FPCX64MM_DIAGNOSTIC}
  FillChar(Block, SizeOf(Block), 0);
  try
    for I := 0 to FBlockCount - 1 do begin
      BlockId := FProducerId * 100000000 + I;
      Size := TransferSize(BlockId, FFixedSize, FSeed);
      AllocateBlock(Block, BlockId, Size, FSeed);
      If not FQueue.Push(Block) then begin
        {$ifdef FPCX64MM_DIAGNOSTIC}
        Fpcx64mmDebugSetContext('producer-aborted-free');
        {$endif FPCX64MM_DIAGNOSTIC}
        If Block.Data <> nil then
          FreeMem(Block.Data);
        Exit;
      end;
    end;
  except
    on E: Exception do begin
      ErrorCode := 1;
      {$ifdef FPCX64MM_DIAGNOSTIC}
      Fpcx64mmDebugSetContext('producer-exception-free');
      {$endif FPCX64MM_DIAGNOSTIC}
      If Block.Data <> nil then
        FreeMem(Block.Data);
      FQueue.ReportError(101, FProducerId, E.ClassName + ': ' + E.Message);
    end;
  end;
end;

constructor TConsumerThread.Create(AQueue: TBlockQueue; AConsumerId: Integer);
begin
  inherited Create(True);
  FQueue := AQueue;
  FConsumerId := AConsumerId;
end;

procedure TConsumerThread.Execute;
var
  Block: TBlock;
  NewSize: Integer;
begin
  {$ifdef FPCX64MM_DIAGNOSTIC}
  Fpcx64mmDebugSetContext('transfer-consumer');
  {$endif FPCX64MM_DIAGNOSTIC}
  FillChar(Block, SizeOf(Block), 0);
  try
    while FQueue.Pop(Block) do begin
      VerifyBlock(Block, 'transfer-consumer');
      If (Block.Id and 3) <> 0 then begin
        NewSize := TransferReallocSize(Block);
        ReallocateBlock(Block, NewSize, 'transfer-realloc');
      end;
      FreeBlock(Block, 'transfer-free');
    end;
  except
    on E: Exception do begin
      ErrorCode := 1;
      FQueue.ReportError(200 + FConsumerId, Block.Id,
        E.ClassName + ': ' + E.Message);
      {$ifdef FPCX64MM_DIAGNOSTIC}
      Fpcx64mmDebugSetContext('consumer-exception-free');
      {$endif FPCX64MM_DIAGNOSTIC}
      If Block.Data <> nil then
        FreeMem(Block.Data);
    end;
  end;
end;

procedure RunTransfer(const Name: string; ProducerCount, ConsumerCount,
  BlocksPerProducer, FixedSize: Integer);
var
  Queue: TBlockQueue;
  Producers: array of TProducerThread;
  Consumers: array of TConsumerThread;
  I: Integer;
begin
  Queue := TBlockQueue.Create;
  try
    SetLength(Producers, ProducerCount);
    SetLength(Consumers, ConsumerCount);
    for I := 0 to ConsumerCount - 1 do
      Consumers[I] := TConsumerThread.Create(Queue, I);
    for I := 0 to ProducerCount - 1 do
      Producers[I] := TProducerThread.Create(Queue, I + 1,
        BlocksPerProducer, FixedSize, GlobalSeed xor UInt64(I + 1));
    for I := 0 to ConsumerCount - 1 do
      Consumers[I].Start;
    for I := 0 to ProducerCount - 1 do
      Producers[I].Start;
    for I := 0 to ProducerCount - 1 do
      Producers[I].WaitFor;
    Queue.MarkDone;
    for I := 0 to ConsumerCount - 1 do
      Consumers[I].WaitFor;
    for I := 0 to ProducerCount - 1 do begin
      Require(Producers[I].ErrorCode = 0,
        Format('%s producer=%d failed', [Name, I]));
      Producers[I].Free;
    end;
    for I := 0 to ConsumerCount - 1 do begin
      Require(Consumers[I].ErrorCode = 0,
        Format('%s consumer=%d failed', [Name, I]));
      Consumers[I].Free;
    end;
    Queue.CheckResult;
  finally
    Queue.Free;
  end;
  WriteLn('PASS ', Name, ' blocks=',
    Int64(ProducerCount) * BlocksPerProducer,
    ' producers=', ProducerCount, ' consumers=', ConsumerCount,
    ' fixed=', FixedSize);
end;

procedure TestCrossThreadOwnership;
const
  HotSizeCount = 6;
  HotSizes: array[0..HotSizeCount - 1] of Integer =
    (56, 64, 128, 256, 800, 17496);
var
  I, HotBlocks: Integer;
begin
  RunTransfer('fan-out-mixed', 1, WorkerCount, Config.TransferBlocks, 0);
  RunTransfer('fan-in-mixed', WorkerCount, 1,
    Config.TransferBlocks div WorkerCount + 1, 0);
  RunTransfer('mesh-mixed', WorkerCount, WorkerCount,
    Config.TransferBlocks div WorkerCount + 1, 0);
  HotBlocks := Config.TransferBlocks div HotSizeCount;
  If HotBlocks < 100 then
    HotBlocks := 100;
  for I := 0 to HotSizeCount - 1 do
    RunTransfer('remote-free-hot', 1, WorkerCount, HotBlocks, HotSizes[I]);
end;

constructor TSaturationThread.Create(AId, ADurationMs: Integer; ASeed: UInt64;
  AInbound, AOutbound: TBlockQueue; AProbeOnly: Boolean);
begin
  inherited Create(True);
  if AProbeOnly <> ((AInbound = nil) and (AOutbound = nil)) then
    raise Exception.Create('saturation probe queue ownership mismatch');
  FId := AId;
  FDurationMs := ADurationMs;
  FSeed := ASeed xor (UInt64(Cardinal(AId)) * UInt64($D6E8FEB86659FD93));
  FInbound := AInbound;
  FOutbound := AOutbound;
  FProbeIterations := 0;
  If AProbeOnly then
    FProbeIterations := 8192;
end;

procedure TSaturationThread.Probe(const Block: TBlock; Random: UInt64);
var
  I, Offset: Integer;
  State: UInt64;
  Actual, Expected: Byte;
begin
  State := Random xor Block.Pattern;
  for I := 1 to FProbeIterations do begin
    State := State * UInt64($D6E8FEB86659FD93) + UInt64($9E3779B185EBCA87);
    Offset := Integer(State mod UInt64(Block.Size));
    Actual := Block.Data[Offset];
    Expected := ExpectedByte(Block, Offset);
    If Actual <> Expected then
      raise Exception.CreateFmt(
        'saturation-probe: content id=%d size=%d offset=%d expected=%d actual=%d',
        [Block.Id, Block.Size, Offset, Expected, Actual]);
    Checksum := (Checksum shl 7) xor (Checksum shr 3) xor State xor Actual;
  end;
end;

procedure TSaturationThread.RunProbe;
var
  Deadline: UInt64;
  R: UInt64;
  I, SlotIndex, BlockId: Integer;
begin
  for I := 0 to High(FSlots) do begin
    BlockId := FId * 20000000 + I;
    R := NextRandom(FSeed);
    AllocateBlock(FSlots[I], BlockId, TransferSize(BlockId, 0, R), FSeed);
  end;
  Deadline := GetTickCount64 + UInt64(FDurationMs);
  repeat
    R := NextRandom(FSeed);
    SlotIndex := Integer((R shr 8) mod SaturationSlotCount);
    Probe(FSlots[SlotIndex], R);
    Inc(Operations);
  until GetTickCount64 >= Deadline;
  for I := 0 to High(FSlots) do
    FreeBlock(FSlots[I], 'saturation-probe-drain');
end;

procedure TSaturationThread.Consume(var Block: TBlock; Random: UInt64);
var
  NewSize: Integer;
begin
  VerifyBlock(Block, 'saturation-remote');
  If (Random and 3) = 0 then begin
    NewSize := TransferReallocSize(Block);
    ReallocateBlock(Block, NewSize, 'saturation-remote-realloc');
  end;
  FreeBlock(Block, 'saturation-remote-free');
end;

procedure TSaturationThread.Execute;
var
  Deadline: UInt64;
  R: UInt64;
  SlotIndex, BlockId, NewSize, I: Integer;
  Incoming: TBlock;
  Slot: ^TBlock;
begin
  {$ifdef FPCX64MM_DIAGNOSTIC}
  Fpcx64mmDebugSetContext('saturation-worker');
  {$endif FPCX64MM_DIAGNOSTIC}
  Incoming.Data := nil;
  try
    If FProbeIterations <> 0 then begin
      RunProbe;
      Exit;
    end;
    Deadline := GetTickCount64 + UInt64(FDurationMs);
    repeat
      R := NextRandom(FSeed);
      If FInbound.TryPop(Incoming) then begin
        Consume(Incoming, R);
        Inc(Operations);
      end;

      SlotIndex := Integer((R shr 8) mod SaturationSlotCount);
      Slot := @FSlots[SlotIndex];
      If Slot^.Data = nil then begin
        BlockId := FId * 20000000 + Integer(Operations and $00ffffff);
        AllocateBlock(Slot^, BlockId, TransferSize(BlockId, 0, R), FSeed);
      end else begin
        case (R shr 24) and 7 of
          0, 1, 2: begin
            If not FOutbound.TryPush(Slot^) then begin
              VerifyBlock(Slot^, 'saturation-local-full-queue');
              FreeBlock(Slot^, 'saturation-local-full-queue-free');
            end;
          end;
          3, 4: begin
            NewSize := TransferReallocSize(Slot^);
            ReallocateBlock(Slot^, NewSize, 'saturation-local-realloc');
          end;
        else
          FreeBlock(Slot^, 'saturation-local-free');
        end;
      end;
      Inc(Operations);
    until GetTickCount64 >= Deadline;

    for I := 0 to High(FSlots) do
      If FSlots[I].Data <> nil then
        FreeBlock(FSlots[I], 'saturation-local-drain');
  except
    on E: Exception do begin
      ErrorCode := 1;
      ErrorMessage := E.ClassName + ': ' + E.Message;
      If Incoming.Data <> nil then
        ErrorBlock := Incoming.Id
      else
        ErrorBlock := FId;
    end;
  end;
  if ErrorCode <> 0 then begin
    if Incoming.Data <> nil then begin
      FreeMem(Incoming.Data);
      Incoming.Data := nil;
    end;
    for I := 0 to High(FSlots) do
      if FSlots[I].Data <> nil then begin
        FreeMem(FSlots[I].Data);
        FSlots[I].Data := nil;
      end;
  end;
end;

procedure TestSaturation;
var
  Queues: array of TBlockQueue;
  Workers: array of TSaturationThread;
  Canaries: TBlockArray;
  AllocatorTotal, WorkerTotal, I, Index: Integer;
  Block: TBlock;
  TotalOps, MinOps, MaxOps: Int64;
  TotalChecksum: UInt64;
  PhaseStarted: UInt64;
begin
  { Pair an allocator-heavy worker with a live-canary worker, but cap the
    whole phase below the authorized CPU limit.  The allocator workers expose
    contention while canaries continuously validate independently owned data. }
  AllocatorTotal := TThread.ProcessorCount;
  If AllocatorTotal > SaturationWorkerLimit div 2 then
    AllocatorTotal := SaturationWorkerLimit div 2;
  WorkerTotal := AllocatorTotal * 2;
  Require(WorkerTotal > 0, 'processor count is zero');
  SetLength(Queues, AllocatorTotal);
  SetLength(Workers, WorkerTotal);
  SetLength(Canaries, SaturationCanaryCount);
  for I := 0 to High(Canaries) do begin
    case I and 3 of
      0: AllocateBlock(Canaries[I], 3000000 + I, 17496, GlobalSeed);
      1: AllocateBlock(Canaries[I], 3000000 + I, 17497, GlobalSeed);
      2: AllocateBlock(Canaries[I], 3000000 + I, 100500, GlobalSeed);
    else
      AllocateBlock(Canaries[I], 3000000 + I,
        300000 + (I and 15) * 65537, GlobalSeed);
    end;
  end;

  for I := 0 to AllocatorTotal - 1 do
    Queues[I] := TBlockQueue.Create;
  for I := 0 to AllocatorTotal - 1 do
    Workers[I] := TSaturationThread.Create(I, Config.SaturationMs,
      GlobalSeed, Queues[(I + AllocatorTotal - 1) mod AllocatorTotal],
      Queues[I], False);
  for I := AllocatorTotal to WorkerTotal - 1 do
    Workers[I] := TSaturationThread.Create(I, Config.SaturationMs,
      GlobalSeed, nil, nil, True);
  PhaseStarted := GetTickCount64;
  for I := 0 to WorkerTotal - 1 do
    Workers[I].Start;
  for I := 0 to WorkerTotal - 1 do
    Workers[I].WaitFor;

  TotalOps := 0;
  TotalChecksum := 0;
  MinOps := High(Int64);
  MaxOps := 0;
  for I := 0 to WorkerTotal - 1 do begin
    Require(Workers[I].ErrorCode = 0,
      Format('saturation worker=%d code=%d block=%d exception=%s seed=%u',
        [I, Workers[I].ErrorCode, Workers[I].ErrorBlock,
         Workers[I].ErrorMessage, GlobalSeed]));
    Inc(TotalOps, Workers[I].Operations);
    TotalChecksum := TotalChecksum xor Workers[I].Checksum;
    If Workers[I].Operations < MinOps then
      MinOps := Workers[I].Operations;
    If Workers[I].Operations > MaxOps then
      MaxOps := Workers[I].Operations;
    Workers[I].Free;
  end;

  Block.Data := nil;
  for I := 0 to AllocatorTotal - 1 do begin
    while Queues[I].TryPop(Block) do
      FreeBlock(Block, 'saturation-queue-drain');
    Queues[I].CheckResult;
    Queues[I].Free;
  end;

  for I := 0 to High(Canaries) do begin
    Index := (I * 73) mod SaturationCanaryCount;
    FreeBlock(Canaries[Index], 'saturation-canary');
  end;
  WriteLn('PASS saturation host_processors=', TThread.ProcessorCount,
    ' workers=', WorkerTotal,
    ' requested_ms=', Config.SaturationMs,
    ' elapsed_ms=', GetTickCount64 - PhaseStarted,
    ' ops=', TotalOps, ' min_worker_ops=', MinOps,
    ' max_worker_ops=', MaxOps, ' checksum=', TotalChecksum);
end;

procedure Configure;
var
  ModeName: string;
  Code: Integer;
begin
  Config.Mode := rmFull;
  If ParamCount > 0 then begin
    ModeName := LowerCase(ParamStr(1));
    If ModeName = 'quick' then
      Config.Mode := rmQuick
    else If ModeName = 'full' then
      Config.Mode := rmFull
    else If ModeName = 'soak' then
      Config.Mode := rmSoak
    else
      raise Exception.Create('usage: memory_mega [quick|full|soak] [seed]');
  end;
  GlobalSeed := UInt64($4D6F6F6E4D4D3236);
  If ParamCount > 1 then begin
    Val(ParamStr(2), GlobalSeed, Code);
    If Code <> 0 then
      raise Exception.Create('seed must be an unsigned decimal integer');
  end;
  case Config.Mode of
    rmQuick: begin
      Config.FuzzSoloOps := 250000;
      Config.FuzzWorkerOps := 250000;
      Config.TransferBlocks := 3000;
      Config.LifecycleRounds := 1;
      Config.SaturationMs := 3000;
    end;
    rmFull: begin
      Config.FuzzSoloOps := 4000000;
      Config.FuzzWorkerOps := 2000000;
      Config.TransferBlocks := 20000;
      Config.LifecycleRounds := 4;
      Config.SaturationMs := 30000;
    end;
    rmSoak: begin
      Config.FuzzSoloOps := 20000000;
      Config.FuzzWorkerOps := 10000000;
      Config.TransferBlocks := 100000;
      Config.LifecycleRounds := 20;
      Config.SaturationMs := 120000;
    end;
  end;
end;

function ModeText: string;
begin
  case Config.Mode of
    rmQuick: Result := 'quick';
    rmFull: Result := 'full';
  else
    Result := 'soak';
  end;
end;

begin
  StartedAt := GetTickCount64;
  try
    Configure;
    WriteLn('MEMORY_MEGA mode=', ModeText, ' seed=', GlobalSeed);
    BeginPhase('contracts');
    TestContracts;
    VerifyHeapAfterPhase('contracts');
    BeginPhase('size-sweep');
    TestSizeSweep;
    VerifyHeapAfterPhase('size-sweep');
    BeginPhase('realloc-matrix');
    TestReallocMatrix;
    VerifyHeapAfterPhase('realloc-matrix');
    BeginPhase('pool-lifecycle');
    TestPoolLifecycle;
    VerifyHeapAfterPhase('pool-lifecycle');
    BeginPhase('independent-fuzz');
    TestIndependentFuzz;
    VerifyHeapAfterPhase('independent-fuzz');
    BeginPhase('cross-thread-ownership');
    TestCrossThreadOwnership;
    VerifyHeapAfterPhase('cross-thread-ownership');
    BeginPhase('saturation');
    TestSaturation;
    VerifyHeapAfterPhase('saturation');
    WriteLn('MEMORY_MEGA_PASS elapsed_ms=', GetTickCount64 - StartedAt,
      ' seed=', GlobalSeed);
  except
    on E: Exception do begin
      WriteLn('MEMORY_MEGA_FAIL ', E.ClassName, ': ', E.Message,
        ' seed=', GlobalSeed);
      Halt(1);
    end;
  end;
end.
