program memory_small_last_free_finalize;

{$mode delphi}

uses
  cthreads,
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
begin
  InitializeMemoryManager;
  P := _GetMem(128);
  If P = nil then
    raise Exception.Create('custom allocation failed');
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
  finally
    Worker.Free;
  end;
  writeln('PENDING_SMALL_FREE_READY count=', Pending);
  Flush(Output);
  FreeAllMemory;
  writeln('SMALL_LAST_FREE_FINALIZE_PASS');
end.
