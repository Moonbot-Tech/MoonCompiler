program memory_small_last_free_finalize;

{$mode delphi}

uses
  {$ifdef unix}
  cthreads,
  {$endif}
  Classes,
  SysUtils,
  mormot.core.fpcx64mm;

type
  TFreeThread = class(TThread)
  private
    FPointer: pointer;
    FFreedSize: PtrUInt;
  protected
    procedure Execute; override;
  public
    constructor Create(P: pointer);
    property FreedSize: PtrUInt read FFreedSize;
  end;

constructor TFreeThread.Create(P: pointer);
begin
  inherited Create(true);
  FPointer := P;
end;

procedure TFreeThread.Execute;
begin
  FFreedSize := _FreeMem(FPointer);
end;

var
  P: pointer;
  Worker: TFreeThread;
  Pending: cardinal;
  BeforeAlloc, AfterAlloc, AfterFree: TMMStatus;
begin
  InitializeMemoryManager;
  BeforeAlloc := CurrentHeapStatus;
  P := _GetMem(128);
  If P = nil then
    raise Exception.Create('custom allocation failed');
  AfterAlloc := CurrentHeapStatus;
  If AfterAlloc.SmallBlocks <> BeforeAlloc.SmallBlocks + 1 then
    raise Exception.CreateFmt('allocated small block count mismatch: %d -> %d',
      [BeforeAlloc.SmallBlocks, AfterAlloc.SmallBlocks]);
  Worker := TFreeThread.Create(P);
  try
    Fpcx64mmTestLockSmallBlockType(P, true);
    Worker.Start;
    Worker.WaitFor;
    Fpcx64mmTestLockSmallBlockType(P, false);
    If Worker.FatalException <> nil then
      raise Exception.Create('free worker failed');
    If Worker.FreedSize = 0 then
      raise Exception.Create('free worker returned zero');
    Pending := Fpcx64mmTestSmallLastFreeCount(P);
    If Pending <> 1 then
      raise Exception.CreateFmt('expected one pending small free, got %d',
        [Pending]);
    AfterFree := CurrentHeapStatus;
    If AfterFree.SmallBlocks <> BeforeAlloc.SmallBlocks then
      raise Exception.CreateFmt('deferred free still reported live: %d -> %d',
        [BeforeAlloc.SmallBlocks, AfterFree.SmallBlocks]);
    If AfterFree.SmallBlocksSize <> BeforeAlloc.SmallBlocksSize then
      raise Exception.CreateFmt('deferred free bytes still reported live: %d -> %d',
        [BeforeAlloc.SmallBlocksSize, AfterFree.SmallBlocksSize]);
  finally
    Worker.Free;
  end;
  writeln('PENDING_SMALL_FREE_READY count=', Pending);
  Flush(Output);
  FreeAllMemory;
  writeln('SMALL_LAST_FREE_FINALIZE_PASS');
end.
