program lightweight_boundaries_semantic;
{$APPTYPE CONSOLE}
{$IFDEF FPC}{$mode delphiunicode}{$ENDIF}
uses {$IFDEF UNIX}cthreads,{$ENDIF} {$IFDEF MSWINDOWS}Windows,{$ENDIF}
  SysUtils, Classes, SyncObjs, System.TimeSpan;

procedure Check(Value: Boolean; const Context: string);
begin
  if not Value then raise Exception.Create(Context);
end;

type
  TWaiter = class(TThread)
    Signal: TLightweightEvent;
    Permits: TLightweightSemaphore;
    Outcome: TWaitResult;
    Repeats: Integer;
    procedure Execute; override;
  end;

procedure TWaiter.Execute;
var I: Integer;
begin
  Outcome:=wrError;
  if Assigned(Signal) then
    Outcome:=Signal.WaitFor(5000)
  else
    for I:=1 to Repeats do
    begin
      Outcome:=Permits.WaitFor(5000);
      if Outcome<>wrSignaled then Break;
    end;
end;

procedure CheckEvent;
var
  Event: TLightweightEvent;
  Threads: array[0..3] of TWaiter;
  I, Round: Integer;
  Start: UInt64;
begin
  Event:=TLightweightEvent.Create(False,0);
  try
    Check(not Event.IsSet and (Event.WaitFor(0)=wrTimeout),'initial event');
    Event.Release;
    Check(not Event.IsSet,'inherited Release does not signal an event');
    Event.SetEvent;
    Check(Event.IsSet and (Event.WaitFor(0)=wrSignaled) and (Event.WaitFor(0)=wrSignaled),'manual reset event');
    Event.ResetEvent;
    for Round:=1 to 20 do
    begin
      for I:=0 to High(Threads) do
      begin
        Threads[I]:=TWaiter.Create(True);
        Threads[I].Signal:=Event;
        Threads[I].Start;
      end;
      try
        Start:=GetTickCount64;
        while (Event.BlockedCount<Round*Length(Threads)) and (GetTickCount64-Start<5000) do
          TThread.Yield;
        Check(Event.BlockedCount=Round*Length(Threads),'waiter registration');
        Event.SetEvent;
        Event.ResetEvent;
        for I:=0 to High(Threads) do
        begin
          Threads[I].WaitFor;
          Check(Threads[I].FatalException=nil,'event worker exception');
          Check(Threads[I].Outcome=wrSignaled,'Set/Reset lost an already registered waiter');
        end;
        Check(Event.WaitFor(0)=wrTimeout,'reset applies to new waiters');
      finally
        Event.SetEvent;
        for I:=0 to High(Threads) do Threads[I].Free;
        Event.ResetEvent;
      end;
    end;
  finally Event.Free; end;
end;

procedure CheckSemaphore;
var
  Semaphore: TLightweightSemaphore;
  Threads: array[0..5] of TWaiter;
  I: Integer;
  Raised: Boolean;
begin
  Semaphore:=TLightweightSemaphore.Create(1,600);
  try
    Check((Semaphore.CurrentCount=1) and (Semaphore.WaitFor(0)=wrSignaled),'initial permit');
    Check(Semaphore.WaitFor(0)=wrTimeout,'permit consumed exactly once');
    Check(Semaphore.Release=0,'default Release returns previous permit count');
    Check(Semaphore.WaitFor(0)=wrSignaled,'default Release adds one permit');
    Check(Semaphore.Release(600)=0,'previous permit count');
    Raised:=False;
    try Semaphore.Release; except on E: ESyncObjectException do Raised:=True; end;
    Check(Raised and (Semaphore.CurrentCount=600),'overflow leaves count unchanged');
    for I:=1 to 600 do Check(Semaphore.WaitFor(0)=wrSignaled,'drain initial permits');
    for I:=0 to High(Threads) do
    begin
      Threads[I]:=TWaiter.Create(True);
      Threads[I].Permits:=Semaphore;
      Threads[I].Repeats:=100;
      Threads[I].Start;
    end;
    try
      for I:=1 to 200 do Semaphore.Release(3);
      for I:=0 to High(Threads) do
      begin
        Threads[I].WaitFor;
        Check(Threads[I].FatalException=nil,'semaphore worker exception');
        Check(Threads[I].Outcome=wrSignaled,'permit wakeup lost');
      end;
      Check(Semaphore.CurrentCount=0,'all permits accounted for');
    finally
      for I:=0 to High(Threads) do Threads[I].Free;
    end;
  finally Semaphore.Free; end;
end;

procedure CheckMREW;
type
  TContainer = record Lock: TLightweightMREW; end;
  PContainer = ^TContainer;
var
  Local: TLightweightMREW;
  Nested: TContainer;
  Items: array of TContainer;
  Heap: PContainer;
  Bytes: array[0..SizeOf(TLightweightMREW)-1] of Byte;
  I: Integer;
begin
  { This lock has never been used. Poison and explicitly initialize its own
    storage, inspect it, and only then call the native lock. }
  FillChar(Local,SizeOf(Local),$A5);
  Initialize(Local);
  Move(Local,Bytes,SizeOf(Bytes));
  for I:=0 to High(Bytes) do Check(Bytes[I]=0,'MREW Initialize left invalid state');
  Check(Local.TryBeginWrite,'local write');
  Local.EndWrite;
  Check(Nested.Lock.TryBeginRead,'nested local initialization');
  Nested.Lock.EndRead;
  SetLength(Items,2);
  Check(Items[1].Lock.TryBeginWrite,'dynamic array initialization');
  Items[1].Lock.EndWrite;
  New(Heap);
  try
    Check(Heap^.Lock.TryBeginWrite,'New initialization');
    Heap^.Lock.EndWrite;
  finally Dispose(Heap); end;
end;

procedure CheckSpinAndTimeout;
var
  Lock: TSpinLock;
  Event: TEvent;
  Raised, Owned: Boolean;
  I: Integer;
begin
  Lock:=TSpinLock.Create(True);
  Lock.Enter;
  try
    for I:=0 to 2 do
    begin
      Raised:=False;
      try
        case I of
          0: Lock.Enter;
          1: Lock.TryEnter;
          2: Lock.TryEnter(Cardinal(0));
        end;
      except on E: ELockRecursionException do Raised:=True; end;
      Check(Raised and Lock.IsLockedByCurrentThread,'tracked recursion contract');
    end;
  finally Lock.Exit; end;
  Check(not Lock.IsLocked,'single release');
  Lock:=TSpinLock.Create(False);
  Raised:=False;
  try Owned:=Lock.IsLockedByCurrentThread; except on E: EInvalidOpException do Raised:=True; end;
  Check(Raised,'untracked ownership query');
  Raised:=False;
  try Lock.TryEnter(TTimeSpan.FromMilliseconds(-1));
  except on E: EArgumentOutOfRangeException do Raised:=True; end;
  Check(Raised and not Lock.IsLocked,'negative spin timeout before acquisition');
  Raised:=False;
  try Lock.TryEnter(TTimeSpan.FromMilliseconds(Int64(MaxInt)+1));
  except on E: EArgumentOutOfRangeException do Raised:=True; end;
  Check(Raised and not Lock.IsLocked,'oversized spin timeout before acquisition');
  Check(Lock.TryEnter(TTimeSpan.FromTicks(-9000)),'fractional timeout truncates to zero');
  Lock.Exit;
  Check(Lock.TryEnter(TTimeSpan.Zero),'zero spin timeout');
  Lock.Exit;
  Event:=TEvent.Create(nil,True,True,'');
  try
    Raised:=False;
    try Event.WaitFor(TTimeSpan.FromMilliseconds(-1));
    except on E: EArgumentOutOfRangeException do Raised:=True; end;
    Check(Raised,'negative event timeout');
    Check(Event.WaitFor(TTimeSpan.Zero)=wrSignaled,'zero event timeout');
  finally Event.Free; end;
end;

begin
  CheckMREW;
  CheckSpinAndTimeout;
  CheckEvent;
  CheckSemaphore;
  WriteLn('LIGHTWEIGHT_BOUNDARIES_PASS');
end.
