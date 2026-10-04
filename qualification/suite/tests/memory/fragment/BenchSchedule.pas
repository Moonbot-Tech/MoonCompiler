unit BenchSchedule;

// Test-only scheduling at completed allocator calls. Every allocation stays in the stock MM.
interface

type
  TCheckpoint = procedure;

procedure InstallSchedule;
procedure RemoveSchedule;
procedure StartCounting(Stride: Int64; Callback: TCheckpoint);
function StopCounting: Int64;

implementation

var
  Original: TMemoryManager;

threadvar
  Counting: Boolean;
  Calls, Next, Step: Int64;
  Checkpoint: TCheckpoint;

procedure Completed; inline;
begin
  If not Counting then exit;
  Inc(Calls);
  If Assigned(Checkpoint) and (Calls >= Next) then begin
    Inc(Next, Step);
    Counting := false;
    try
      Checkpoint;
    finally
      Counting := true;
    end;
  end;
end;

function ScheduledGetMem(Size: PtrUInt): Pointer;
begin
  Result := Original.GetMem(Size);
  Completed;
end;

function ScheduledAllocMem(Size: PtrUInt): Pointer;
begin
  Result := Original.AllocMem(Size);
  Completed;
end;

function ScheduledReallocMem(var P: Pointer; Size: PtrUInt): Pointer;
begin
  Result := Original.ReallocMem(P, Size);
  Completed;
end;

procedure InstallSchedule;
var
  MM: TMemoryManager;
begin
  GetMemoryManager(Original);
  MM := Original;
  MM.GetMem := ScheduledGetMem;
  MM.AllocMem := ScheduledAllocMem;
  MM.ReallocMem := ScheduledReallocMem;
  SetMemoryManager(MM);
end;

procedure RemoveSchedule;
begin
  SetMemoryManager(Original);
end;

procedure StartCounting(Stride: Int64; Callback: TCheckpoint);
begin
  Calls := 0;
  Step := Stride;
  Next := Stride;
  Checkpoint := Callback;
  Counting := true;
end;

function StopCounting: Int64;
begin
  Counting := false;
  Result := Calls;
end;

end.
