program threaded_captured;

{$mode delphiunicode}{$H+}{$R-}{$Q-}{$modeswitch nestedprocvars}

uses
{$ifdef UNIX}
  cthreads,
{$endif}
  SysUtils;

type
  TValues = array of Int64;
  TWorker = function(Parameter: Pointer): PtrInt is nested;

const
  SpinLimit = 1000000000;

var
  Callback: TWorker;
  Request, Done: LongInt;

function Trampoline(Parameter: Pointer): PtrInt;
begin
  Result := Callback(Parameter);
end;

procedure Run;
var
  A, B, KeepA: TValues;
  I, Count, Spins: Integer;
  Total: Int64;
  WorkerHandle: TThreadID;

  function Worker(Parameter: Pointer): PtrInt;
  var
    Attempts: Integer;
  begin
    Attempts := 0;
    while (Volatile(Request) = 0) and (Attempts < SpinLimit) do Inc(Attempts);
    If Volatile(Request) = 0 then begin
      Volatile(Done) := -1;
      Exit(1);
    end;
    A := B;
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
  { Retain the original payload, so a stale descriptor produces a wrong sum
    without reading freed memory. A itself is captured through the static link. }
  KeepA := A;
  Total := 0;
  Callback := Worker;
  WorkerHandle := BeginThread(@Trampoline, nil);
  If WorkerHandle = 0 then Halt(11);
  try
    Writeln('before');
  finally
    Writeln('after');
  end;

  for I := 0 to Count - 1 do begin
    If I = 1 then begin
      Volatile(Request) := 1;
      Spins := 0;
      while (Volatile(Done) = 0) and (Spins < SpinLimit) do Inc(Spins);
      If Volatile(Done) <> 1 then Break;
    end;
    Total := Total + A[I] + A[4 - I];
  end;

  Volatile(Request) := 1;
  If WaitForThreadTerminate(WorkerHandle, 10000) <> 0 then Halt(12);
  CloseThread(WorkerHandle);
  Callback := nil;
  If Volatile(Done) <> 1 then Halt(13);
  Writeln(Total);
  If Total <> 78 then Halt(78);
  If Length(KeepA) <> 5 then Halt(79);
end;

begin
  Run;
end.
