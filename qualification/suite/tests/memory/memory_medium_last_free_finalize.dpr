program memory_medium_last_free_finalize;

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
  BeforeAlloc, AfterAlloc, AfterFree: TMMFragmentationStatus;
begin
  InitializeMemoryManager;
  BeforeAlloc := CurrentHeapFragmentationStatus;
  P := _GetMem(100000);
  If P = nil then
    raise Exception.Create('custom allocation failed');
  AfterAlloc := CurrentHeapFragmentationStatus;
  If AfterAlloc.LiveMediumBytes <= BeforeAlloc.LiveMediumBytes then
    raise Exception.Create('medium allocation was not counted');
  Worker := TFreeThread.Create(P);
  try
    Fpcx64mmTestLockMedium(P, true);
    Worker.Start;
    Worker.WaitFor;
    Fpcx64mmTestLockMedium(P, false);
    If Worker.FatalException <> nil then
      raise Exception.Create('free worker failed');
    If Worker.FreedSize = 0 then
      raise Exception.Create('free worker returned zero');
    If Fpcx64mmTestMediumLastFree(P) <> P then
      raise Exception.Create('expected pending medium free');
    AfterFree := CurrentHeapFragmentationStatus;
    If AfterFree.LiveMediumBytes <> BeforeAlloc.LiveMediumBytes then
      raise Exception.Create('pending medium free still counted as live');
  finally
    Worker.Free;
  end;
  writeln('PENDING_MEDIUM_FREE_READY');
  Flush(Output);
  FreeAllMemory;
  writeln('MEDIUM_LAST_FREE_FINALIZE_PASS');
end.
