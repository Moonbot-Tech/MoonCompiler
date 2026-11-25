{ Each active worker sees its own unit-level context even while the other threads have set theirs. }

type
  TBreadthTokenWorker = class(TThread)
  public
    Ready, ReleaseWorkers: TEvent;
    Token, Initially, Observed: Int64;
    Address: Pointer;
    Released: TWaitResult;
    procedure Execute; override;
  end;

procedure TBreadthTokenWorker.Execute;
begin
  Initially := BreadthReadThreadToken(Address);
  BreadthThreadToken := Token;
  Ready.SetEvent;
  Released := ReleaseWorkers.WaitFor(2000);
  Observed := BreadthReadThreadToken(Address);
end;

procedure RunBreadthThreadLocalTokens;
const
  MainToken: Int64 = 330000000013;
  FirstToken: Int64 = -520000000007;
  SecondToken: Int64 = 740000000023;
var
  Gate, ReadyA, ReadyB: TEvent;
  A, B: TBreadthTokenWorker;
  MainAddress: Pointer;
  BothReady: Boolean;
begin
  Gate := TEvent.Create(nil, True, False, '');
  ReadyA := nil;
  ReadyB := nil;
  A := nil;
  B := nil;
  try
    ReadyA := TEvent.Create(nil, True, False, '');
    ReadyB := TEvent.Create(nil, True, False, '');
    BreadthThreadToken := OpaqueI(MainToken);
    A := TBreadthTokenWorker.Create(True);
    A.Ready := ReadyA;
    A.ReleaseWorkers := Gate;
    A.Token := OpaqueI(FirstToken);
    B := TBreadthTokenWorker.Create(True);
    B.Ready := ReadyB;
    B.ReleaseWorkers := Gate;
    B.Token := OpaqueI(SecondToken);
    A.Start;
    B.Start;
    BothReady := (ReadyA.WaitFor(2000) = wrSignaled) and (ReadyB.WaitFor(2000) = wrSignaled);
    Check(BothReady, 'breadth-threadvar-peers-both-store-before-main-reads');
    Check((BreadthReadThreadToken(MainAddress) = MainToken) and (MainAddress = @BreadthThreadToken),
      'breadth-threadvar-main-value-survives-peer-stores-through-separate-unit');
    Gate.SetEvent;
    A.WaitFor;
    B.WaitFor;
    Check((A.Released = wrSignaled) and (B.Released = wrSignaled)
      and (A.FatalException = nil) and (B.FatalException = nil), 'breadth-threadvar-peers-complete');
    Check((A.Initially = 0) and (B.Initially = 0), 'breadth-threadvar-new-threads-start-with-zero');
    Check((A.Observed = FirstToken) and (B.Observed = SecondToken),
      'breadth-threadvar-peers-retain-independent-wide-values');
    Check((A.Address <> nil) and (B.Address <> nil) and (A.Address <> B.Address)
      and (A.Address <> MainAddress) and (B.Address <> MainAddress), 'breadth-threadvar-each-live-context-has-own-address');
    Mix(UInt64(A.Observed) xor UInt64(B.Observed));
  finally
    Gate.SetEvent;
    B.Free;
    A.Free;
    BreadthThreadToken := 0;
    ReadyB.Free;
    ReadyA.Free;
    Gate.Free;
  end;
end;
