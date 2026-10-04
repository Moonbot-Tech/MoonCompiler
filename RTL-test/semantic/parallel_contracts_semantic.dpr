program parallel_contracts_semantic;

{$mode delphi}{$H+}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  cwstring,
  {$endif UNIX}
  System.SysUtils,
  System.Threading;

const
  IterationCount = 65536;

procedure Check(ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    raise Exception.Create('PARALLEL_CONTRACTS_FAIL: '+AMessage);
end;

procedure CheckInt32Reservation;
var
  Round, I: Integer;
  Seen: array of LongInt;
  LoopResult: TParallel.TLoopResult;
begin
  SetLength(Seen,IterationCount);
  for Round:=1 to 8 do
    begin
    FillChar(Seen[0],Length(Seen)*SizeOf(Seen[0]),0);
    LoopResult:=TParallel.&For(0,High(Seen),
      procedure(Index: Integer)
      begin
        AtomicIncrement(Seen[Index]);
      end);
    Check(LoopResult.Completed,'Int32 loop did not complete');
    for I:=0 to High(Seen) do
      Check(Seen[I]=1,'Int32 reservation at '+IntToStr(I));
    end;
end;

procedure CheckInt64Reservation;
var
  Round, I: Integer;
  Seen: array of LongInt;
  LoopResult: TParallel.TLoopResult;
begin
  SetLength(Seen,IterationCount);
  for Round:=1 to 8 do
    begin
    FillChar(Seen[0],Length(Seen)*SizeOf(Seen[0]),0);
    LoopResult:=TParallel.&For(Int64(0),Int64(High(Seen)),
      procedure(Index: Int64)
      begin
        AtomicIncrement(Seen[Index]);
      end);
    Check(LoopResult.Completed,'Int64 loop did not complete');
    for I:=0 to High(Seen) do
      Check(Seen[I]=1,'Int64 reservation at '+IntToStr(I));
    end;
end;

procedure CheckInt32State;
var
  NonNilCount: LongInt;
  LoopResult: TParallel.TLoopResult;
  LoopProc: TParallel.TInt32LoopStateProc;
begin
  NonNilCount:=0;
  LoopProc:=
    procedure(Index: Integer; LoopState: TParallel.TLoopState)
    begin
      Check(Assigned(LoopState),'nil Int32 loop state');
      Check((LoopState as TParallel.TLoopState32).CurrentIteration=Index,
        'stale Int32 current iteration');
      AtomicIncrement(NonNilCount);
      if Index=17 then
        LoopState.Break;
    end;
  LoopResult:=TParallel.&For(Integer(0),Integer(127),LoopProc);
  Check(not LoopResult.Completed,'Int32 Break reported completion');
  Check(Integer(LoopResult.LowestBreakIteration)=17,'Int32 lowest break');
  Check(NonNilCount>0,'Int32 state callback was not called');
end;

procedure CheckInt64State;
var
  NonNilCount: LongInt;
  LoopResult: TParallel.TLoopResult;
  LoopProc: TParallel.TInt64LoopStateProc;
begin
  NonNilCount:=0;
  LoopProc:=
    procedure(Index: Int64; LoopState: TParallel.TLoopState)
    begin
      Check(Assigned(LoopState),'nil Int64 loop state');
      Check((LoopState as TParallel.TLoopState64).CurrentIteration=Index,
        'stale Int64 current iteration');
      AtomicIncrement(NonNilCount);
      if Index=19 then
        LoopState.Break;
    end;
  LoopResult:=TParallel.&For(Int64(0),Int64(127),LoopProc);
  Check(not LoopResult.Completed,'Int64 Break reported completion');
  Check(Int64(LoopResult.LowestBreakIteration)=19,'Int64 lowest break');
  Check(NonNilCount>0,'Int64 state callback was not called');
end;

procedure CheckBreakStopsCurrentStride;
var
  Pool: TThreadPool;
  Seen: array[0..31] of LongInt;
  I: Integer;
  LoopResult: TParallel.TLoopResult;
  LoopProc: TParallel.TInt32LoopStateProc;
begin
  FillChar(Seen,SizeOf(Seen),0);
  Pool:=TThreadPool.Create;
  try
    Check(Pool.SetMinWorkerThreads(0),'single-worker pool minimum');
    Check(Pool.SetMaxWorkerThreads(1),'single-worker pool maximum');
    Pool.UnlimitedWorkerThreadsWhenBlocked:=False; // no thread past the maximum
    LoopProc:=
      procedure(Index: Integer; LoopState: TParallel.TLoopState)
      begin
        Inc(Seen[Index]);
        if Index=3 then
          LoopState.Break;
      end;
    LoopResult:=TParallel.&For(8,0,High(Seen),LoopProc,Pool);
    Check(not LoopResult.Completed,'stride Break reported completion');
    Check(Integer(LoopResult.LowestBreakIteration)=3,'stride lowest break');
    for I:=0 to 3 do
      Check(Seen[I]=1,'stride prefix at '+IntToStr(I));
    for I:=4 to High(Seen) do
      Check(Seen[I]=0,'stride tail after Break at '+IntToStr(I));
  finally
    Pool.Free;
  end;
end;

begin
  CheckInt32Reservation;
  CheckInt64Reservation;
  CheckInt32State;
  CheckInt64State;
  CheckBreakStopsCurrentStride;
  WriteLn('PARALLEL_CONTRACTS_SEMANTIC_PASS');
end.
