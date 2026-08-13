program memory_small_pool_last_free_finalize;

{$mode delphi}

uses
  mormot.core.fpcx64mm,
  cthreads,
  Classes,
  SysUtils;

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

const
  TestSize = 800;
  MaxPointers = 8192;

var
  Pointers: array[0..MaxPointers - 1] of pointer;
  Count, I: integer;
  P, Extra, Pool, FirstPool, Info, Pending: pointer;
  Flags: PtrUInt;
  Worker: TFreeThread;
begin
  {$ifdef FPCMM_STANDALONE}
  InitializeMemoryManager;
  {$endif FPCMM_STANDALONE}
  Count := 0;
  Extra := nil;
  FirstPool := nil;
  repeat
    P := _GetMem(TestSize);
    If P = nil then
      raise Exception.Create('custom allocation failed');
    Pool := Fpcx64mmTestSmallPool(P);
    If FirstPool = nil then
      FirstPool := Pool;
    If Pool <> FirstPool then begin
      Extra := P;
      break;
    end;
    If Count = MaxPointers then
      raise Exception.Create('small pool did not roll over');
    Pointers[Count] := P;
    inc(Count);
  until false;

  If Count < 2 then
    raise Exception.Create('not enough blocks in first small pool');
  _FreeMem(Extra);
  for I := 0 to Count - 2 do
    _FreeMem(Pointers[I]);

  P := Pointers[Count - 1];
  Info := Fpcx64mmTestSmallMediumInfo(P);
  Worker := TFreeThread.Create(P);
  try
    Fpcx64mmTestLockMediumInfo(Info, true);
    try
      Worker.Start;
      Worker.WaitFor;
    finally
      Fpcx64mmTestLockMediumInfo(Info, false);
    end;
    If Worker.FatalException <> nil then
      raise Exception.Create('free worker failed');
    If Worker.FreedSize = 0 then
      raise Exception.Create('free worker returned zero');
    Pending := Fpcx64mmTestMediumInfoLastFree(Info);
    If Pending <> FirstPool then
      raise Exception.Create('expected pending small-pool medium block');
    Flags := Fpcx64mmTestBlockFlags(Pending);
    If (Flags and 7) <> 6 then
      raise Exception.CreateFmt('unexpected pending flags: %x', [Flags]);
  finally
    Worker.Free;
  end;

  writeln('PENDING_SMALL_POOL_READY count=', Count, ' flags=', Flags);
  Flush(Output);
  {$ifdef FPCMM_STANDALONE}
  FreeAllMemory;
  writeln('SMALL_POOL_LAST_FREE_FINALIZE_PASS');
  {$else}
  If Pos('repmemleak', FPCMM_FLAGS) = 0 then
    raise Exception.Create('leak-report profile is not active');
  writeln('SMALL_POOL_LAST_FREE_REPORT_PENDING');
  {$endif FPCMM_STANDALONE}
end.
