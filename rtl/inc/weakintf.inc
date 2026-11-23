{ A weak field holds its actual interface pointer. Track the field address and
  target independently: the owner may move or disappear before the target.
  Interface queries, allocations and disposal can call user code. Do them
  outside the registry lock. }
const
  InitialWeakBuckets = 16;
  TargetHintCount = 256;
  WeakPageShift = 10;

type
  PWeakEntry = ^TWeakEntry;
  PPWeakEntry = ^PWeakEntry;
  TWeakEntry = record
    Slot: PPointer;
    Target: TObject;
    NextSlot, NextTarget: PWeakEntry;
    PrevSlot, PrevTarget: PPWeakEntry;
  end;
  PWeakTable = ^TWeakTable;
  TWeakTable = record
    ByPage, ByTarget: PPWeakEntry;
    Count, Mask: SizeUInt;
  end;
  TTargetHint = record
    Count: SizeUInt;
    Target: Pointer;
  end;

var
  WeakTable: PWeakTable;
  WeakLock: LongInt;
  { These hints outlive any resized table. Only read pointer identity outside
    the lock. A collision falls back to the locked lookup until the bin empties. }
  WeakTargets: array[0..TargetHintCount-1] of TTargetHint;

procedure EnterWeakTable; inline;
begin
  while InterlockedCompareExchange(WeakLock,1,0)<>0 do
    ThreadSwitch;
end;

procedure LeaveWeakTable; inline;
begin
  InterlockedExchange(WeakLock,0);
end;

function WeakTableActive: Boolean; inline;
begin
  Result:=Assigned(WeakTable);
end;

function PageBucket(Slot: Pointer): SizeInt; inline;
begin
  Result:=(PtrUInt(Slot) shr WeakPageShift) and WeakTable^.Mask;
end;

function TargetHash(Target: TObject): PtrUInt; inline;
var
  Address: PtrUInt;
begin
  Address:=PtrUInt(Target);
  Result:=(Address shr 4) xor (Address shr 12);
end;

function FindWeakSlot(Slot: PPointer): PPWeakEntry;
begin
  Result:=@WeakTable^.ByPage[PageBucket(Slot)];
  while Assigned(Result^) and (Result^^.Slot<>Slot) do
    Result:=@Result^^.NextSlot;
end;

procedure AttachSlot(E: PWeakEntry); inline;
begin
  E^.PrevSlot:=@WeakTable^.ByPage[PageBucket(E^.Slot)];
  E^.NextSlot:=E^.PrevSlot^;
  if Assigned(E^.NextSlot) then E^.NextSlot^.PrevSlot:=@E^.NextSlot;
  E^.PrevSlot^:=E;
end;

procedure DetachSlot(E: PWeakEntry); inline;
begin
  E^.PrevSlot^:=E^.NextSlot;
  if Assigned(E^.NextSlot) then E^.NextSlot^.PrevSlot:=E^.PrevSlot;
end;

procedure LinkTarget(E: PWeakEntry); inline;
begin
  E^.PrevTarget:=@WeakTable^.ByTarget[TargetHash(E^.Target) and WeakTable^.Mask];
  E^.NextTarget:=E^.PrevTarget^;
  if Assigned(E^.NextTarget) then E^.NextTarget^.PrevTarget:=@E^.NextTarget;
  E^.PrevTarget^:=E;
end;

procedure AttachTarget(E: PWeakEntry; Target: TObject);
var
  H: ^TTargetHint;
begin
  H:=@WeakTargets[TargetHash(Target) and (TargetHintCount-1)];
  if H^.Count=0 then H^.Target:=Target
  else if H^.Target<>Pointer(Target) then H^.Target:=@WeakTargets;
  Inc(H^.Count);
  E^.Target:=Target;
  LinkTarget(E);
end;

procedure DetachTarget(E: PWeakEntry);
var
  H: ^TTargetHint;
begin
  E^.PrevTarget^:=E^.NextTarget;
  if Assigned(E^.NextTarget) then E^.NextTarget^.PrevTarget:=E^.PrevTarget;
  H:=@WeakTargets[TargetHash(E^.Target) and (TargetHintCount-1)];
  Dec(H^.Count);
  if H^.Count=0 then H^.Target:=nil;
end;

function NewWeakTable(Buckets: SizeUInt): PWeakTable;
begin
  if Buckets>(High(SizeInt)-SizeOf(TWeakTable)) div (2*SizeOf(Pointer)) then HandleError(203);
  Result:=AllocMem(SizeOf(TWeakTable)+2*Buckets*SizeOf(Pointer));
  if not Assigned(Result) then HandleError(203);
  Result^.ByPage:=Pointer(Result+1);
  Result^.ByTarget:=Result^.ByPage+Buckets;
  Result^.Mask:=Buckets-1;
end;

procedure ReplaceWeakTable(var Spare: PWeakTable);
var
  Old: PWeakTable;
  I: SizeUInt;
  E, Next: PWeakEntry;
begin
  Old:=WeakTable;
  WeakTable:=Spare;
  Spare:=Old;
  if not Assigned(Old) then exit;
  WeakTable^.Count:=Old^.Count;
  for I:=0 to Old^.Mask do
    begin
      E:=Old^.ByPage[I];
      while Assigned(E) do
        begin
          Next:=E^.NextSlot;
          AttachSlot(E);
          LinkTarget(E);
          E:=Next;
        end;
    end;
end;

function TakeEmptyWeakTable: PWeakTable; inline;
begin
  Result:=nil;
  if WeakTable^.Count=0 then
    begin
      Result:=WeakTable;
      WeakTable:=nil;
    end;
end;

procedure RemoveWeakSlot(var D: Pointer);
var
  E: PWeakEntry;
  Link: PPWeakEntry;
  Empty: PWeakTable;
begin
  E:=nil;
  Empty:=nil;
  EnterWeakTable;
  if Assigned(WeakTable) then
    begin
      Link:=FindWeakSlot(@D);
      E:=Link^;
      if Assigned(E) then
        begin
          DetachSlot(E);
          DetachTarget(E);
          Dec(WeakTable^.Count);
          Empty:=TakeEmptyWeakTable;
        end;
    end;
  D:=nil;
  LeaveWeakTable;
  if Assigned(E) then Dispose(E);
  if Assigned(Empty) then FreeMem(Empty);
end;

procedure fpc_weak_intf_assign(var D: Pointer; const S: Pointer); [public,alias:'FPC_WEAK_INTF_ASSIGN']; compilerproc;
var
  Target: TObject;
  Value: Pointer;
  Spare, E: PWeakEntry;
  SpareTable: PWeakTable;
  Buckets: SizeUInt;
begin
  Value:=S;
  if not Assigned(Value) then
    begin
      if Assigned(D) then RemoveWeakSlot(D);
      exit;
    end;
  Target:=nil;
  { A separately linked System owns another registry and cannot notify ours. }
  if (IUnknown(Value).QueryInterface(IObjectInstance,Target)<>S_OK) or
    not Assigned(Target) or not Target.InheritsFrom(TObject) then
    HandleErrorAddrFrameInd(228,get_pc_addr,get_frame);
  Spare:=nil;
  SpareTable:=nil;
  try
    repeat
      EnterWeakTable;
      if Assigned(SpareTable) and (not Assigned(WeakTable) or (SpareTable^.Mask>WeakTable^.Mask)) then
        ReplaceWeakTable(SpareTable);
      Buckets:=InitialWeakBuckets;
      if Assigned(WeakTable) then
        begin
          E:=nil;
          if Assigned(D) then E:=FindWeakSlot(@D)^;
          if Assigned(E) then
            begin
              if E^.Target<>Target then
                begin
                  DetachTarget(E);
                  AttachTarget(E,Target);
                end;
              D:=Value;
              LeaveWeakTable;
              break;
            end;
          Buckets:=0;
          if WeakTable^.Count div 4>WeakTable^.Mask then Buckets:=2*(WeakTable^.Mask+1);
          if (Buckets=0) and Assigned(Spare) then
            begin
              Spare^.Slot:=@D;
              AttachSlot(Spare);
              AttachTarget(Spare,Target);
              Inc(WeakTable^.Count);
              D:=Value;
              LeaveWeakTable;
              Spare:=nil;
              break;
            end;
        end;
      LeaveWeakTable;
      if not Assigned(Spare) then
        begin
          New(Spare);
          if not Assigned(Spare) then HandleError(203);
        end;
      if Assigned(SpareTable) then begin FreeMem(SpareTable); SpareTable:=nil end;
      if Buckets<>0 then SpareTable:=NewWeakTable(Buckets);
    until false;
  finally
    if Assigned(Spare) then Dispose(Spare);
    if Assigned(SpareTable) then FreeMem(SpareTable);
  end;
end;

procedure AssignWeakInterface(var D: Pointer; const S: Pointer); external name 'FPC_WEAK_INTF_ASSIGN';

procedure WeakMoveOwned(const Source; var Dest; Size: SizeInt);
var
  FirstPage, Pages, I, Offset: PtrUInt;
  Link: PPWeakEntry;
  E, Moved: PWeakEntry;
begin
  if (Size<=0) or (@Source=@Dest) then exit;
  EnterWeakTable;
  Move(Source,Dest,Size);
  if Assigned(WeakTable) then
    begin
      FirstPage:=PtrUInt(@Source) shr WeakPageShift;
      Pages:=((PtrUInt(@Source)+PtrUInt(Size)-1) shr WeakPageShift)-FirstPage+1;
      if Pages>WeakTable^.Mask+1 then Pages:=WeakTable^.Mask+1;
      Moved:=nil;
      for I:=0 to Pages-1 do
        begin
          Link:=@WeakTable^.ByPage[(FirstPage+I) and WeakTable^.Mask];
          while Assigned(Link^) do
            begin
              E:=Link^;
              if PtrUInt(E^.Slot)>=PtrUInt(@Source) then
                begin
                  Offset:=PtrUInt(E^.Slot)-PtrUInt(@Source);
                  if Offset<PtrUInt(Size) then
                    begin
                      DetachSlot(E);
                      E^.Slot:=PPointer(PtrUInt(@Dest)+Offset);
                      E^.NextSlot:=Moved;
                      Moved:=E;
                      continue;
                    end;
                end;
              Link:=@E^.NextSlot;
            end;
        end;
      { Reinsert only after the scan, including for overlapping moves. }
      while Assigned(Moved) do
        begin
          E:=Moved;
          Moved:=E^.NextSlot;
          AttachSlot(E);
        end;
    end;
  LeaveWeakTable;
end;

procedure fpc_weak_swap_owned(A,B,Scratch: Pointer; Size: SizeInt); [public,alias:'FPC_WEAK_SWAP_OWNED']; compilerproc;
begin
  if A=B then exit;
  WeakMoveOwned(A^,Scratch^,Size);
  WeakMoveOwned(B^,A^,Size);
  WeakMoveOwned(Scratch^,B^,Size);
end;

procedure ClearWeakTarget(Target: TObject);
var
  E, Next, Removed: PWeakEntry;
  Table: PWeakTable;
  Hash: PtrUInt;
  Hint: Pointer;
begin
  Hash:=TargetHash(Target);
  Hint:=WeakTargets[Hash and (TargetHintCount-1)].Target;
  if (Hint<>Pointer(Target)) and (Hint<>@WeakTargets) then exit;
  Table:=nil;
  Removed:=nil;
  EnterWeakTable;
  if Assigned(WeakTable) then
    begin
      E:=WeakTable^.ByTarget[Hash and WeakTable^.Mask];
      while Assigned(E) do
        begin
          Next:=E^.NextTarget;
          if E^.Target=Target then
            begin
              E^.Slot^:=nil;
              DetachSlot(E);
              DetachTarget(E);
              E^.NextSlot:=Removed;
              Removed:=E;
              Dec(WeakTable^.Count);
            end;
          E:=Next;
        end;
      Table:=TakeEmptyWeakTable;
    end;
  LeaveWeakTable;
  while Assigned(Removed) do
    begin
      E:=Removed;
      Removed:=E^.NextSlot;
      Dispose(E);
    end;
  if Assigned(Table) then FreeMem(Table);
end;

class operator TWeakInterfaceSlot.Initialize(var Slot: TWeakInterfaceSlot);
begin
  if WeakTableActive then RemoveWeakSlot(Slot.Value)
  else Slot.Value:=nil;
end;

class operator TWeakInterfaceSlot.Finalize(var Slot: TWeakInterfaceSlot);
begin
  if Assigned(Slot.Value) then
    AssignWeakInterface(Slot.Value,nil);
end;

class operator TWeakInterfaceSlot.Copy(constref Source: TWeakInterfaceSlot; var Dest: TWeakInterfaceSlot);
begin
  AssignWeakInterface(Dest.Value,Source.Value);
end;

class operator TWeakInterfaceSlot.AddRef(var Slot: TWeakInterfaceSlot);
begin
  if Assigned(Slot.Value) then
    AssignWeakInterface(Slot.Value,Slot.Value);
end;
