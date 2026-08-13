program memory_small_arena_collision;

{$mode delphi}

uses
  cthreads,
  mormot.core.fpcx64mm,
  Linux,
  UnixType,
  SysUtils,
  Classes;

const
  RequestSize = 128;
  SampleCount = 7;
  Iterations = 2000000;

type
  TTimings = array[0..SampleCount - 1] of QWord;
  TWarmThread = class(TThread)
  protected
    procedure Execute; override;
  end;

procedure TWarmThread.Execute;
begin
end;

function ReadTimeNs: QWord;
var
  Timestamp: TTimeSpec;
begin
  If clock_gettime(CLOCK_MONOTONIC_RAW, @Timestamp) <> 0 then
    RaiseLastOSError;
  Result := QWord(Timestamp.tv_sec) * QWord(1000000000) +
    QWord(Timestamp.tv_nsec);
end;

procedure Sort(var Values: TTimings);
var
  I, J: Integer;
  V: QWord;
begin
  for I := 1 to High(Values) do
  begin
    V := Values[I];
    J := I - 1;
    while (J >= 0) and (Values[J] > V) do
    begin
      Values[J + 1] := Values[J];
      Dec(J);
    end;
    Values[J + 1] := V;
  end;
end;

var
  Anchor, P: Pointer;
  AnchorCapacity, CollisionCapacity, I, Sample: PtrUInt;
  Started, Elapsed: QWord;
  Timings: TTimings;
  WarmThread: TWarmThread;
begin
  WarmThread := TWarmThread.Create(False);
  WarmThread.WaitFor;
  WarmThread.Free;
  InitializeMemoryManager;
  Anchor := _GetMem(RequestSize);
  If Anchor = nil then
    raise Exception.Create('anchor allocation failed');
  AnchorCapacity := _MemSize(Anchor);
  Fpcx64mmTestLockSmallBlockType(Anchor, True);
  try
    P := _GetMem(RequestSize);
    If P = nil then
      raise Exception.Create('collision allocation failed');
    CollisionCapacity := _MemSize(P);
    _FreeMem(P);
    for Sample := 0 to High(Timings) do
    begin
      Started := ReadTimeNs;
      for I := 1 to Iterations do
      begin
        P := _GetMem(RequestSize);
        If P = nil then
          raise Exception.Create('timed allocation failed');
        _FreeMem(P);
      end;
      Elapsed := ReadTimeNs - Started;
      Timings[Sample] := Elapsed div Iterations;
    end;
  finally
    Fpcx64mmTestLockSmallBlockType(Anchor, False);
    _FreeMem(Anchor);
  end;
  FreeAllMemory;
  Sort(Timings);
  WriteLn('SMALL_ARENA_COLLISION request=', RequestSize,
    ' anchor-capacity=', AnchorCapacity,
    ' collision-capacity=', CollisionCapacity,
    ' median-ns=', Timings[SampleCount div 2],
    ' min-ns=', Timings[0], ' max-ns=', Timings[High(Timings)]);
  If CollisionCapacity <> AnchorCapacity then
    Halt(10);
end.
