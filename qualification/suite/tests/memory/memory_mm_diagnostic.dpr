program memory_mm_diagnostic;

{$mode delphi}
{$H+}

{$if not defined(FPCX64MM_DIAGNOSTIC) or defined(FPCMM_STANDALONE) or
     not defined(FPCMM_SMALLLASTFREE_TEST) or
     not defined(FPCMM_MEDIUMLASTFREE_TEST)}
  {$fatal memory_mm_diagnostic requires diagnostic and pending-list test modes}
{$endif}

uses
  mormot.core.fpcx64mm,
  cthreads,
  SysUtils,
  Classes;

procedure Require(Condition: Boolean; MessageText: PAnsiChar);
begin
  if not Condition then
  begin
    WriteLn('MEMORY_MM_DIAGNOSTIC_FAIL ', MessageText);
    Halt(1);
  end;
end;

procedure RequirePattern(P: PByte; Count: PtrUInt; Pattern: Byte;
  Name: PAnsiChar);
var
  I: PtrUInt;
begin
  for I := 0 to Count - 1 do
    if P[I] <> Pattern then
    begin
      WriteLn('MEMORY_MM_DIAGNOSTIC_FAIL ', Name, ' offset=', I);
      Halt(1);
    end;
end;

type
  TSingleFreeThread = class(TThread)
  private
    FPointer: Pointer;
    FFreedSize: PtrUInt;
  protected
    procedure Execute; override;
  public
    constructor Create(P: Pointer);
    property FreedSize: PtrUInt read FFreedSize;
  end;

constructor TSingleFreeThread.Create(P: Pointer);
begin
  inherited Create(True);
  FPointer := P;
end;

procedure TSingleFreeThread.Execute;
begin
  FFreedSize := FreeMem(FPointer);
end;

procedure QueueOneSmallFree(out P: PByte; out Worker: TSingleFreeThread);
begin
  P := GetMem(128);
  Worker := TSingleFreeThread.Create(P);
  Fpcx64mmTestLockSmallBlockType(P, True);
  try
    Worker.Start;
    Worker.WaitFor;
  finally
    Fpcx64mmTestLockSmallBlockType(P, False);
  end;
  Require(Worker.FatalException = nil, 'pending free worker');
  Require(Worker.FreedSize <> 0, 'pending free size');
  Require(Fpcx64mmTestSmallLastFreeCount(P) = 1, 'pending free count');
end;

procedure QueueOneMediumFree(out P: PByte; out Worker: TSingleFreeThread);
begin
  P := GetMem(100000);
  Worker := TSingleFreeThread.Create(P);
  Fpcx64mmTestLockMedium(P, True);
  try
    Worker.Start;
    Worker.WaitFor;
  finally
    Fpcx64mmTestLockMedium(P, False);
  end;
  Require(Worker.FatalException = nil, 'pending medium worker');
  Require(Worker.FreedSize <> 0, 'pending medium size');
  Require(Fpcx64mmTestMediumLastFree(P) = P, 'pending medium head');
end;

procedure RunHealthy;
var
  P, Q, PendingP, PendingMediumP: PByte;
  I, OldCapacity: PtrUInt;
  PoisonedBefore: QWord;
  MM: TMemoryManager;
  Worker, MediumWorker: TSingleFreeThread;
begin
  Fpcx64mmDebugSetContext('diagnostic-healthy');

  GetMem(P, 96);
  RequirePattern(P, 96, $A5, 'GetMem new-fill');
  Require(MemSize(P) >= 96, 'GetMem logical capacity');
  OldCapacity := MemSize(P);
  RequirePattern(P, OldCapacity, $A5, 'GetMem full new-fill');
  for I := 0 to OldCapacity - 1 do
    P[I] := $3C;
  ReallocMem(P, 300000);
  Require(P <> nil, 'ReallocMem result');
  Require(MemSize(P) >= 300000, 'ReallocMem logical capacity');
  RequirePattern(P, OldCapacity, $3C, 'ReallocMem full old capacity');
  Require(P[OldCapacity] = $A5, 'ReallocMem new-fill first');
  Require(P[MemSize(P) - 1] = $A5, 'ReallocMem new-fill last');
  PoisonedBefore := Fpcx64mmDebugFreedPoisonCount;
  FreeMem(P);
  Require(Fpcx64mmDebugFreedPoisonCount = PoisonedBefore + 1,
    'FreeMem poison counter');
  P := nil;

  ReallocMem(P, 112);
  Require(P <> nil, 'ReallocMem nil result');
  RequirePattern(P, MemSize(P), $A5, 'ReallocMem nil new-fill');
  ReallocMem(P, 0);
  Require(P = nil, 'ReallocMem zero result');

  GetMem(P, 120);
  GetMemoryManager(MM);
  Require(MM.FreememSize(P, 120) >= 120, 'FreeMemSize result');
  P := nil;

  Q := AllocMem(327641);
  Require(Q <> nil, 'AllocMem result');
  Require(MemSize(Q) >= 327641, 'AllocMem large logical capacity');
  RequirePattern(Q, 327641, 0, 'AllocMem zero-fill');
  // This VerifyHeap has one tracked large block, exercising its list membership
  // and reciprocal-link invariants before the release path changes the list.
  Fpcx64mmDebugVerifyHeap;
  FreeMem(Q);

  QueueOneSmallFree(PendingP, Worker);
  try
    Fpcx64mmDebugSetContext('diagnostic-small-pending');
    Fpcx64mmDebugVerifyHeap;
  finally
    Worker.Free;
  end;

  QueueOneMediumFree(PendingMediumP, MediumWorker);
  try
    Fpcx64mmDebugSetContext('diagnostic-medium-pending');
    Fpcx64mmDebugVerifyHeap;
  finally
    MediumWorker.Free;
  end;

  Fpcx64mmDebugSetContext('diagnostic-healthy');
  Fpcx64mmDebugVerifyHeap;
  WriteLn('MEMORY_MM_DIAGNOSTIC_PASS healthy');
end;

procedure RunDoubleFree;
var
  P: Pointer;
begin
  Fpcx64mmDebugSetContext('diagnostic-double-free');
  P := GetMem(96);
  FreeMem(P);
  // The second call is intentional: the diagnostic wrapper rejects it before
  // the allocator dereferences a freed block. VerifyHeap must halt with 218.
  FreeMem(P);
  Fpcx64mmDebugVerifyHeap;
  Require(false, 'double-free detector did not stop verification');
end;

procedure RunLeak;
var
  P: Pointer;
begin
  Fpcx64mmDebugSetContext('diagnostic-leak');
  P := GetMem(88);
  Require(P <> nil, 'leak allocation');
  Fpcx64mmDebugVerifyHeap;
  WriteLn('MEMORY_MM_DIAGNOSTIC_EXPECTED_LEAK shutdown report follows');
end;

procedure RunFreeMemSizeOverflow;
var
  P: Pointer;
  MM: TMemoryManager;
begin
  Fpcx64mmDebugSetContext('diagnostic-freememsize');
  P := GetMem(120);
  GetMemoryManager(MM);
  MM.FreememSize(P, MemSize(P) + 1);
  Require(false, 'oversized FreeMemSize did not stop');
end;

procedure RunForeignPointer;
var
  Local: PtrUInt;
begin
  Fpcx64mmDebugSetContext('diagnostic-foreign');
  Local := 0;
  FreeMem(@Local);
  Require(false, 'foreign pointer did not stop');
end;

procedure RunMalformedSmallOwner;
var
  P, Pool, Owner: Pointer;
begin
  Fpcx64mmDebugSetContext('diagnostic-small-owner');
  P := GetMem(96);
  Pool := Pointer(PPtrUInt(PByte(P) - SizeOf(Pointer))^ and PtrUInt(-8));
  Owner := PPointer(Pool)^;
  PPointer(Pool)^ := PByte(Owner) + 1;
  MemSize(P);
  Require(false, 'misaligned small owner did not stop');
end;

procedure RunMalformedLargeLink;
var
  P, Q: Pointer;
begin
  Fpcx64mmDebugSetContext('diagnostic-large-link');
  P := GetMem(300000);
  Q := GetMem(400000);
  Require((P <> nil) and (Q <> nil), 'large link allocations');
  // TLargeBlockHeader.NextLargeBlockHeader is three pointers before payload.
  // The wrapper accepts the still-owned allocation, then the locked raw-list
  // check must reject the bad peer before FreeLargeBlock dereferences it.
  PPointer(PByte(P) - 3 * SizeOf(Pointer))^ := Pointer(1);
  FreeMem(P);
  Require(false, 'malformed large link did not stop');
end;

procedure RunMalformedSmallLastFree;
var
  P: PByte;
  Worker: TSingleFreeThread;
begin
  QueueOneSmallFree(P, Worker);
  Fpcx64mmDebugSetContext('diagnostic-small-list');
  Fpcx64mmTestCorruptSmallLastFreeHead(P);
  Fpcx64mmDebugVerifyHeap;
  Require(false, 'malformed small pending list did not stop');
end;

procedure RunMalformedMediumLastFree;
var
  P: PByte;
  Worker: TSingleFreeThread;
begin
  QueueOneMediumFree(P, Worker);
  Fpcx64mmDebugSetContext('diagnostic-medium-list');
  Fpcx64mmTestCorruptMediumLastFree(P);
  Fpcx64mmDebugVerifyHeap;
  Require(false, 'malformed medium pending list did not stop');
end;

type
  TDoubleFreeThread = class(TThread)
  private
    FPointer: Pointer;
  public
    constructor Create(P: Pointer);
  protected
    procedure Execute; override;
  end;

constructor TDoubleFreeThread.Create(P: Pointer);
begin
  inherited Create(True);
  FPointer := P;
end;

procedure TDoubleFreeThread.Execute;
begin
  Fpcx64mmDebugSetContext('diagnostic-worker');
  FreeMem(FPointer);
  FreeMem(FPointer);
end;

procedure RunWorkerDoubleFree;
var
  P: Pointer;
  T: TDoubleFreeThread;
begin
  P := GetMem(300000);
  T := TDoubleFreeThread.Create(P);
  T.Start;
  T.WaitFor;
  T.Free;
  Require(false, 'worker double-free did not stop process');
end;

var
  Mode: Char;
begin
  Mode := 'h';
  if (ParamCount <> 0) and (Length(ParamStr(1)) <> 0) then
    Mode := ParamStr(1)[1];
  if Mode = 'h' then
    RunHealthy
  else if Mode = 'd' then
    RunDoubleFree
  else if Mode = 'l' then
    RunLeak
  else if Mode = 's' then
    RunFreeMemSizeOverflow
  else if Mode = 'f' then
    RunForeignPointer
  else if Mode = 'o' then
    RunMalformedSmallOwner
  else if Mode = 'g' then
    RunMalformedLargeLink
  else if Mode = 'q' then
    RunMalformedSmallLastFree
  else if Mode = 'm' then
    RunMalformedMediumLastFree
  else if Mode = 'w' then
    RunWorkerDoubleFree
  else
  begin
    WriteLn('usage: memory_mm_diagnostic ',
      '[healthy|doublefree|leak|size|foreign|owner|guardlink|queue|mediumqueue|worker]');
    Halt(2);
  end;
end.
