program memory_hot_small_pool;

{$mode delphi}
{$H+}

uses
  mormot.core.fpcx64mm;

const
  ColdFreeCount = 8;
  TestSize = 1024;

procedure Require(Condition: boolean; const MessageText: string);
begin
  if not Condition then
  begin
    WriteLn('MEMORY_HOT_SMALL_POOL_FAIL ', MessageText);
    Halt(1);
  end;
end;

var
  BeforeStatus, AfterStatus: TMMStatus;
  BlockType: pointer;
  P: pointer;
  {$ifdef FPCMM_MOONSHARD}
  Reused, Second: pointer;
  {$endif FPCMM_MOONSHARD}
  I: integer;

begin
  BeforeStatus := CurrentHeapStatus;
  BlockType := nil;
  for I := 1 to ColdFreeCount do
  begin
    P := GetMem(TestSize);
    BlockType := Fpcx64mmTestSmallBlockType(P);
    FreeMem(P);
    {$ifdef FPCMM_MOONSHARD}
    Require(Fpcx64mmTestSmallEmptyPoolReuseScore(BlockType) = cardinal(I),
      'cold empty-pool score mismatch');
    {$else}
    Require(Fpcx64mmTestSmallEmptyPoolReuseScore(BlockType) = 0,
      'non-product profile changed the empty-pool score');
    {$endif FPCMM_MOONSHARD}
    Require(Fpcx64mmTestSmallRetainedPool(BlockType) = nil,
      'cold size class retained a pool too early');
  end;
  P := GetMem(TestSize);
  BlockType := Fpcx64mmTestSmallBlockType(P);
  FreeMem(P);
  {$ifdef FPCMM_MOONSHARD}
  Require(Fpcx64mmTestSmallEmptyPoolReuseScore(BlockType) = ColdFreeCount,
    'hot empty-pool score exceeded its saturation threshold');
  Require(Fpcx64mmTestSmallRetainedPool(BlockType) <> nil,
    'hot size class did not retain a reusable pool');
  Reused := GetMem(TestSize);
  Require(Reused = P, 'retained hot pool did not return its free block');
  Second := GetMem(TestSize);
  FreeMem(Reused);
  FreeMem(Second);
  Require(Fpcx64mmTestSmallEmptyPoolReuseScore(BlockType) = 0,
    'drained multi-block workload did not reset the empty-pool score');
  Require(Fpcx64mmTestSmallRetainedPool(BlockType) = nil,
    'stale reuse history kept the drained multi-block pool');
  P := GetMem(TestSize);
  BlockType := Fpcx64mmTestSmallBlockType(P);
  FreeMem(P);
  Require(Fpcx64mmTestSmallEmptyPoolReuseScore(BlockType) = 1,
    'reuse history did not restart after the workload changed');
  Require(Fpcx64mmTestSmallRetainedPool(BlockType) = nil,
    'first cold cycle retained a pool after the workload changed');
  {$else}
  Require(Fpcx64mmTestSmallEmptyPoolReuseScore(BlockType) = 0,
    'non-product profile retained reuse history');
  Require(Fpcx64mmTestSmallRetainedPool(BlockType) = nil,
    'non-product profile retained an empty pool');
  {$endif FPCMM_MOONSHARD}
  AfterStatus := CurrentHeapStatus;
  Require(AfterStatus.SmallBlocks = BeforeStatus.SmallBlocks,
    'hot-pool reuse changed the live small-block count');
  Require(AfterStatus.SmallBlocksSize = BeforeStatus.SmallBlocksSize,
    'hot-pool reuse changed the live small-byte count');
  WriteLn('MEMORY_HOT_SMALL_POOL_PASS score=',
    Fpcx64mmTestSmallEmptyPoolReuseScore(BlockType));
end.
