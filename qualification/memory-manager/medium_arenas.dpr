program medium_arenas;

{$mode delphi}{$H+}
{$APPTYPE CONSOLE}
{$Q-}{$R-}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  {$endif UNIX}
  SysUtils,
  Classes;

const
  WorkerCount = 8;
  BlocksPerWorker = 32;
  MediumSize = 100500;
  MediumAlignmentMask = (1 shl 21) - 1;
  MediumOwnerOffset = 2 * SizeOf(Pointer);

type
  TBlock = record
    Data: Pointer;
    Pattern: Byte;
  end;
  TBlockArray = array of TBlock;

  TAllocateWorker = class(TThread)
  private
    FBlocks: ^TBlockArray;
    FId: Integer;
  protected
    procedure Execute; override;
  public
    ErrorCode: Integer;
    constructor Create(var Blocks: TBlockArray; Id: Integer);
  end;

  TReleaseWorker = class(TThread)
  private
    FBlocks: ^TBlockArray;
  protected
    procedure Execute; override;
  public
    ErrorCode: Integer;
    constructor Create(var Blocks: TBlockArray);
  end;

function BlockOwner(Data: Pointer): Pointer; inline;
var
  Pool: PtrUInt;
begin
  Pool := PtrUInt(Data) and not PtrUInt(MediumAlignmentMask);
  Result := PPointer(Pool + MediumOwnerOffset)^;
end;

constructor TAllocateWorker.Create(var Blocks: TBlockArray; Id: Integer);
begin
  inherited Create(True);
  FBlocks := @Blocks;
  FId := Id;
end;

procedure TAllocateWorker.Execute;
var
  I: Integer;
begin
  try
    for I := 0 to High(FBlocks^) do begin
      FBlocks^[I].Pattern := Byte(FId * 29 + I + 1);
      ErrorCode := 100 + I * 10;
      GetMem(FBlocks^[I].Data, MediumSize);
      Inc(ErrorCode);
      If FBlocks^[I].Data = nil then begin
        ErrorCode := 1;
        Exit;
      end;
      FillChar(FBlocks^[I].Data^, MediumSize, FBlocks^[I].Pattern);
      ErrorCode := 0;
    end;
  except
    If ErrorCode = 0 then
      ErrorCode := 2;
  end;
end;

constructor TReleaseWorker.Create(var Blocks: TBlockArray);
begin
  inherited Create(True);
  FBlocks := @Blocks;
end;

procedure TReleaseWorker.Execute;
var
  I, NewSize, PreservedLast: Integer;
  P: PByte;
begin
  try
    for I := 0 to High(FBlocks^) do begin
      ErrorCode := 100 + I * 10;
      P := FBlocks^[I].Data;
      If (P = nil) or
         (P[0] <> FBlocks^[I].Pattern) or
         (P[MediumSize div 2] <> FBlocks^[I].Pattern) or
         (P[MediumSize - 1] <> FBlocks^[I].Pattern) then begin
        ErrorCode := 10;
        Exit;
      end;
      If Odd(I) then
        NewSize := 200000
      else
        NewSize := 18000;
      ReallocMem(FBlocks^[I].Data, NewSize);
      Inc(ErrorCode);
      P := FBlocks^[I].Data;
      If NewSize < MediumSize then
        PreservedLast := NewSize - 1
      else
        PreservedLast := MediumSize - 1;
      If (P = nil) or
         (P[0] <> FBlocks^[I].Pattern) or
         (P[PreservedLast] <> FBlocks^[I].Pattern) then begin
        ErrorCode := 11;
        Exit;
      end;
      FreeMem(FBlocks^[I].Data);
      FBlocks^[I].Data := nil;
      ErrorCode := 0;
    end;
  except
    If ErrorCode = 0 then
      ErrorCode := 12;
  end;
end;

var
  Blocks: array[0..WorkerCount - 1] of TBlockArray;
  Allocators: array[0..WorkerCount - 1] of TAllocateWorker;
  Releasers: array[0..WorkerCount - 1] of TReleaseWorker;
  Owners: array[0..WorkerCount - 1] of Pointer;
  I, J, K, OwnerCount: Integer;
  Owner: Pointer;
begin
  If Pos(' medarena', FPCMM_FLAGS) = 0 then
    raise Exception.Create('medium arenas are not active');

  for I := 0 to High(Blocks) do begin
    SetLength(Blocks[I], BlocksPerWorker);
    Allocators[I] := TAllocateWorker.Create(Blocks[I], I);
  end;
  for I := 0 to High(Allocators) do
    Allocators[I].Start;
  for I := 0 to High(Allocators) do begin
    Allocators[I].WaitFor;
    If Allocators[I].ErrorCode <> 0 then
      raise Exception.CreateFmt('allocator %d failed: %d',
        [I, Allocators[I].ErrorCode]);
    Allocators[I].Free;
  end;

  OwnerCount := 0;
  for I := 0 to High(Blocks) do
    for J := 0 to High(Blocks[I]) do begin
      Owner := BlockOwner(Blocks[I][J].Data);
      If Owner = nil then
        raise Exception.Create('medium pool has no owner');
      K := 0;
      while (K < OwnerCount) and (Owners[K] <> Owner) do
        Inc(K);
      If K = OwnerCount then begin
        Owners[OwnerCount] := Owner;
        Inc(OwnerCount);
      end;
    end;
  If OwnerCount < 2 then
    raise Exception.CreateFmt('only %d medium arena observed', [OwnerCount]);

  for I := 0 to High(Releasers) do
    Releasers[I] := TReleaseWorker.Create(Blocks[(I + 1) mod WorkerCount]);
  for I := 0 to High(Releasers) do
    Releasers[I].Start;
  for I := 0 to High(Releasers) do begin
    Releasers[I].WaitFor;
    If Releasers[I].ErrorCode <> 0 then
      raise Exception.CreateFmt('releaser %d failed: %d',
        [I, Releasers[I].ErrorCode]);
    Releasers[I].Free;
  end;

  {$ifdef FPCX64MM_DIAGNOSTIC}
  Fpcx64mmDebugVerifyHeap;
  {$endif FPCX64MM_DIAGNOSTIC}
  WriteLn('PASS owners=', OwnerCount,
    ' allocations=', WorkerCount * BlocksPerWorker);
end.
