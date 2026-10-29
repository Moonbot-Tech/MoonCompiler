program ring_moon;

{$mode delphiunicode}
{$H+}
{$R-}
{$Q-}

uses
  cthreads, SysUtils, Classes, SyncObjs;

const
  ClockMonotonic = 1;
  ClockProcessCpu = 2;

type
  TTimespec = record
    Seconds: Int64;
    Nanoseconds: Int64;
  end;

  TWorker = class(TThread)
    Id: Integer;
    Timeouts: Int64;
    Received: Int64;
    procedure Execute; override;
  end;

var
  Workers: TArray<TWorker>;
  Events: TArray<TEvent>;
  DoneEvent: TEvent;
  ThreadCount, Rounds, Ready, RaceStarted: Integer;
  Counter: Int64;

function clock_gettime(Id: LongInt; var Time: TTimespec): LongInt; cdecl; external 'c';

function ClockNs(Id: Integer): Int64;
var
  Time: TTimespec;
begin
  If clock_gettime(Id, Time) <> 0 then
    raise Exception.Create('clock_gettime failed');
  Result := Time.Seconds * 1000000000 + Time.Nanoseconds;
end;

procedure TWorker.Execute;
var
  Round: Integer;
  WaitResult: TWaitResult;
begin
  InterlockedIncrement(Ready);
  Round := 0;
  while Round < Rounds do begin
    WaitResult := Events[Id].WaitFor(16);
    If WaitResult = wrTimeout then begin
      If InterlockedCompareExchange(RaceStarted, 0, 0) <> 0 then Inc(Timeouts);
      Continue;
    end;
    If WaitResult <> wrSignaled then Halt(4);

    // A successful signal transfers ownership of this ordinary integer counter.
    If Counter <> Int64(Round) * ThreadCount + Id then Halt(5);
    Inc(Counter);
    Inc(Received);
    Inc(Round);
    If Counter = Int64(ThreadCount) * Rounds then begin
      DoneEvent.SetEvent;
    end else begin
      Events[(Id + 1) mod ThreadCount].SetEvent;
    end;
  end;
end;

procedure RunRing;
var
  CpuStart, WallStart, Wall, Cpu, TotalTimeouts: Int64;
begin
  SetLength(Events, ThreadCount);
  SetLength(Workers, ThreadCount);
  DoneEvent := TEvent.Create(nil, False, False, '');
  for var Index := 0 to High(Events) do Events[Index] := TEvent.Create(nil, False, False, '');
  for var Index := 0 to High(Workers) do begin
    Workers[Index] := TWorker.Create(True);
    Workers[Index].Id := Index;
  end;
  for var Worker in Workers do Worker.Start;
  while InterlockedCompareExchange(Ready, 0, 0) <> ThreadCount do Sleep(1);
  Sleep(50);

  CpuStart := ClockNs(ClockProcessCpu);
  WallStart := ClockNs(ClockMonotonic);
  InterlockedExchange(RaceStarted, 1);
  Events[0].SetEvent;
  If DoneEvent.WaitFor(INFINITE) <> wrSignaled then Halt(6);
  Wall := ClockNs(ClockMonotonic) - WallStart;
  Cpu := ClockNs(ClockProcessCpu) - CpuStart;

  for var Worker in Workers do Worker.WaitFor;
  TotalTimeouts := 0;
  for var Worker in Workers do begin
    If Worker.Received <> Rounds then raise Exception.Create('ring receive count mismatch');
    Inc(TotalTimeouts, Worker.Timeouts);
  end;
  Writeln('{"case":"ring","wall_ns":', Wall, ',"cpu_ns":', Cpu,
    ',"operations":', Counter, ',"threads":', ThreadCount, ',"timeouts":', TotalTimeouts, '}');
  // Every worker has joined; its event can now be released.
  for var Worker in Workers do Worker.Free;
  for var Event in Events do Event.Free;
  DoneEvent.Free;
end;

begin
  If ParamCount <> 3 then raise Exception.Create('Usage: ring_moon ring THREADS ROUNDS');
  ThreadCount := StrToInt(ParamStr(2));
  Rounds := StrToInt(ParamStr(3));
  If (ThreadCount <= 0) or (Rounds <= 0) then raise Exception.Create('THREADS and ROUNDS must be positive');
  RunRing;
end.
