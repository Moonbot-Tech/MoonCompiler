program OomOwnership;
{$mode delphi}{$H+}{$asmmode intel}
uses mormot.core.fpcx64mm, SysUtils, Windows;
var ReadyEvent, DoneEvent, WorkerHandle: THandle;
    WorkerId: DWORD;
    LockByte: PByte;
    TookLock: Boolean;
    Held: array[0..99999] of Pointer;
    Count,I: Integer;
    P: Pointer;
function TryLock(P: PByte): Boolean; nostackframe; assembler;
asm
  mov eax,$100
  lock cmpxchg byte ptr [rcx],ah
  sete al
end;
function Worker(Arg: Pointer): DWORD; stdcall;
begin
  If WaitForSingleObject(ReadyEvent,10000)<>WAIT_OBJECT_0 then Exit(2);
  TookLock:=TryLock(LockByte);
  SetEvent(DoneEvent);
  Result:=0;
end;
procedure Observe(P: PByte);
begin
  LockByte:=P;
  SetEvent(ReadyEvent);
  If WaitForSingleObject(DoneEvent,10000)<>WAIT_OBJECT_0 then Halt(3);
end;
begin
  ReadyEvent:=CreateEvent(nil,False,False,nil);
  DoneEvent:=CreateEvent(nil,False,False,nil);
  WorkerHandle:=CreateThread(nil,65536,@Worker,nil,0,WorkerId);
  If (ReadyEvent=0) or (DoneEvent=0) or (WorkerHandle=0) then Halt(4);
  ReturnNilIfGrowHeapFails:=True;
  OomArm(1);
  repeat
    P:=GetMem(65536);
    If P=nil then Break;
    If Count=Length(Held) then Halt(5);
    Held[Count]:=P;
    Inc(Count);
  until False;
  OomSetMediumReturnObserver(@Observe);
  P:=GetMem(65536);
  OomSetMediumReturnObserver(nil);
  OomArm(0);
  If (P<>nil) or (LockByte=nil) then Halt(6);
  WriteLn('OWNERSHIP took_foreign_lock=',Ord(TookLock),' locked_after_caller=',LockByte^);
  // Zero alone is insufficient: the old caller cleared a foreign owner's lock.
  If LockByte^<>0 then Halt(8);
  for I:=0 to Count-1 do FreeMem(Held[I]);
  WaitForSingleObject(WorkerHandle,10000);
  CloseHandle(WorkerHandle);
  CloseHandle(ReadyEvent);
  CloseHandle(DoneEvent);
  If TookLock then Halt(1);
  If CurrentHeapFragmentationStatus.Errors<>0 then Halt(7);
  WriteLn('OWNERSHIP_PASS');
end.
