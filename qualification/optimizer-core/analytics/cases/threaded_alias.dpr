program threaded_alias;

{$mode delphiunicode}{$H+}{$R-}{$Q-}

uses
{$ifdef UNIX}
  cthreads,
{$endif}
  SysUtils;

type
  TValues = array of Int64;

const
  SpinLimit = 1000000000;

var
  A, B: TValues;
  I, Count, Spins: Integer;
  Total: Int64;
  Saved: Pointer;
  Request, Done: LongInt;
  WorkerHandle: TThreadID;
  Alias: Pointer external name 'U_$P$THREADED_ALIAS_$$_A';

function Worker(Replacement: Pointer): PtrInt;
var
  Attempts: Integer;
begin
  Attempts := 0;
  while (Volatile(Request) = 0) and (Attempts < SpinLimit) do Inc(Attempts);
  If Volatile(Request) = 0 then begin
    Volatile(Done) := -1;
    Exit(1);
  end;
  Alias := Replacement;
  Volatile(Done) := 1;
  Result := 0;
end;

begin
  Count := 4 + Length(ParamStr(1));
  If Count <> 4 then Halt(10);
  SetLength(A, 5);
  SetLength(B, 5);
  for I := 0 to 4 do begin
    A[I] := I + 1;
    B[I] := 10 + I;
  end;
  Saved := Pointer(A);
  Total := 0;
  WorkerHandle := BeginThread(@Worker, Pointer(B));
  If WorkerHandle = 0 then Halt(11);

  { Keep this loop free of calls. The explicit link alias does not mark A's
    declaration addr_taken or different_scope, but it exposes its descriptor. }
  for I := 0 to Count - 1 do begin
    If I = 1 then begin
      Volatile(Request) := 1;
      Spins := 0;
      while (Volatile(Done) = 0) and (Spins < SpinLimit) do Inc(Spins);
      If Volatile(Done) <> 1 then Break;
    end;
    Total := Total + A[I] + A[4 - I];
  end;

  { Wake the worker even after a bounded-wait failure. Join before restoring
    the raw descriptor alias, then release the Windows thread handle. }
  Volatile(Request) := 1;
  If WaitForThreadTerminate(WorkerHandle, 10000) <> 0 then Halt(12);
  CloseThread(WorkerHandle);
  Alias := Saved;
  If Volatile(Done) <> 1 then Halt(13);
  Writeln(Total);
  If Total <> 78 then Halt(78);
end.
