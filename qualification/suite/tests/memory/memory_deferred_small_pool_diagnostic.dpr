program memory_deferred_small_pool_diagnostic;
{$mode delphi}
uses mormot.core.fpcx64mm,
  {$ifdef UNIX} cthreads, {$endif}
  Classes, SysUtils;
type
  TFreeThread = class(TThread)
    P: Pointer;
    Freed: PtrUInt;
    procedure Execute; override;
  end;
procedure TFreeThread.Execute;
begin
  Freed := FreeMem(P);
end;
procedure Require(B: Boolean; const S: string);
begin
  if not B then begin
    WriteLn('FAIL ', S);
    Halt(1);
  end;
end;
const
  TestSize = 800;
  MaxPointers = 8192;
var
  Pointers: array[0..MaxPointers - 1] of Pointer;
  Count, I: Integer;
  P, Pool, FirstPool, Info, Pending, Physical: Pointer;
  Worker: TFreeThread;
  Flags, Header: PtrUInt;
  Fragmentation: TMMFragmentationStatus;
  Mode: string;
begin
  Mode := ParamStr(1);
  Count := 0;
  FirstPool := nil;
  repeat
    P := GetMem(TestSize);
    Pool := Fpcx64mmTestSmallPool(P);
    if FirstPool = nil then
      FirstPool := Pool;
    if Pool <> FirstPool then begin
      FreeMem(P);
      break;
    end;
    Require(Count < MaxPointers, 'small pool did not roll over');
    Pointers[Count] := P;
    Inc(Count);
  until false;
  Require(Count > 1, 'insufficient blocks');
  for I := 0 to Count - 2 do
    FreeMem(Pointers[I]);
  P := Pointers[Count - 1];
  Info := Fpcx64mmTestSmallMediumInfo(P);
  Worker := TFreeThread.Create(true);
  Worker.P := P;
  Fpcx64mmTestLockMediumInfo(Info, true);
  try
    Worker.Start;
    Worker.WaitFor;
  finally
    Fpcx64mmTestLockMediumInfo(Info, false);
  end;
  Require(Worker.FatalException = nil, 'free worker exception');
  Require(Worker.Freed <> 0, 'zero free size');
  Pending := Fpcx64mmTestMediumInfoLastFree(Info);
  Require(Pending = FirstPool, 'wrong pending pool');
  Flags := Fpcx64mmTestBlockFlags(Pending);
  Require(Flags and 7 = 6, 'wrong pending flags');
  Require(PCardinal(PByte(Pending) + 32)^ = 0, 'nonempty pool');
  Fragmentation := CurrentHeapFragmentationStatus;
  Require(Fragmentation.Errors = 0, 'physical fragmentation errors');
  Require(Fpcx64mmTestMediumInfoLastFree(Info) = FirstPool, 'queue unexpectedly drained');
  WriteLn('READY pending-internal-pool count=', Count, ' flags=', Flags,
    ' physical-errors=', Fragmentation.Errors, ' emptybytes=', Fragmentation.EmptySmallPoolBytes);
  Flush(Output);
  // Deliberate corruption uses the packed allocator layouts: the block header
  // precedes payload by 8 bytes, BlocksInUse is at +32, and Reserved1 at +16
  // of the 2 MiB-aligned physical medium pool. This small pool has no live user payload.
  Header := PPtrUInt(PByte(Pending) - 8)^;
  if Mode = 'owner' then begin
    Physical := Pointer(PtrUInt(Pending) and not PtrUInt((1 shl 21) - 1));
    PPointer(PByte(Physical) + 16)^ := Pointer(1);
  end else if Mode = 'header' then
    PPtrUInt(PByte(Pending) - 8)^ := (Header and PtrUInt(-16)) or 7
  else if Mode = 'size' then
    PPtrUInt(PByte(Pending) - 8)^ := PtrUInt(-16) or 6
  else if Mode = 'nonempty' then
    PCardinal(PByte(Pending) + 32)^ := 1
  else if Mode = 'chain' then
    PPointer(Pending)^ := Pointer(1)
  else if Mode = 'interior' then begin
    // An arena address with convincing flags is insufficient: it must be an
    // actual block boundary, not a fabricated node inside a released pool.
    P := PByte(Pending) + 64;
    PPtrUInt(PByte(P) - 8)^ := ((Header and PtrUInt(-16)) - 64) or 6;
    PCardinal(PByte(P) + 32)^ := 0;
    PPointer(P)^ := nil;
    PPointer(Pending)^ := P;
  end
  else if Mode = 'cycle' then
    PPointer(Pending)^ := Pending;
  Fpcx64mmDebugSetContext('forced-internal-small-pool');
  Fpcx64mmDebugVerifyHeap;
  Require(Mode = 'healthy', 'corruption was accepted');
  WriteLn('DEFERRED_SMALL_POOL_DIAGNOSTIC_PASS');
  Flush(Output);
  Worker.Free;
end.
