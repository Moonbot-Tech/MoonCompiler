unit queue244hooks;
{$mode delphiunicode}
interface
uses SysUtils, Classes, SyncObjs;
procedure InstallQueueHooks;
procedure RemoveQueueHooks;
procedure BeginQueueCapture;
procedure EndQueueCapture;
function QueueWaitCalls(Side: Integer): LongInt;
procedure WaitForQueueWaiters(Side, Count: Integer);
procedure HoldQueueReturns(Side: Integer);
procedure PrepareNextReturn;
procedure CheckSingleWake;
procedure ReleaseQueueReturn;
procedure WaitForCount(var Counter: LongInt; Expected: LongInt; const Name: string);
procedure Check(Condition: Boolean; const Name: string);
implementation
var
  Original: TThreadManager;
  Capturing: Boolean;
  Captured: Integer;
  QueueEvents: array[0..1] of PEventState;
  InsideWait, WaitCalls: array[0..1] of LongInt;
  HoldSide: LongInt = -1;
  FirstReturn, ReturnGate: PEventState;

procedure Check(Condition: Boolean; const Name: string);
begin
  If not Condition then begin
    Writeln('FAIL: ', Name);
    Halt(1);
  end;
end;

procedure WaitForCount(var Counter: LongInt; Expected: LongInt; const Name: string);
var Started: QWord;
begin
  Started := GetTickCount64;
  while InterlockedCompareExchange(Counter, 0, 0) <> Expected do begin
    Check(GetTickCount64 - Started < 2000, Name);
    Sleep(1);
  end;
end;

function HookCreate(Attributes: Pointer; Manual, Initial: Boolean; const Name: AnsiString): PEventState;
begin
  Result := Original.BasicEventCreate(Attributes, Manual, Initial, Name);
  If Capturing then begin
    Check(Captured < 2, 'unexpected queue event count');
    QueueEvents[Captured] := Result;
    Inc(Captured);
  end;
end;

function HookWait(Timeout: Cardinal; State: PEventState; UseComWait: Boolean = False): LongInt;
var Side: Integer;
begin
  Side := -1;
  If State = QueueEvents[0] then Side := 0
  else If State = QueueEvents[1] then Side := 1;
  If Side >= 0 then begin
    InterlockedIncrement(WaitCalls[Side]);
    InterlockedIncrement(InsideWait[Side]);
  end;
  try
    Result := Original.BasicEventWaitFor(Timeout, State, UseComWait);
    If (Side >= 0) and (Side = HoldSide) and (Result = Ord(wrSignaled)) then begin
      Original.BasicEventSetEvent(FirstReturn);
      Check(Original.BasicEventWaitFor(2000, ReturnGate, False) = Ord(wrSignaled), 'return gate deadline');
    end;
  finally
    If Side >= 0 then InterlockedDecrement(InsideWait[Side]);
  end;
end;

procedure InstallQueueHooks;
var Hooked: TThreadManager;
begin
  GetThreadManager(Original);
  FirstReturn := Original.BasicEventCreate(nil, True, False, '');
  ReturnGate := Original.BasicEventCreate(nil, True, False, '');
  Hooked := Original;
  Hooked.BasicEventCreate := @HookCreate;
  Hooked.BasicEventWaitFor := @HookWait;
  Check(SetThreadManager(Hooked), 'install thread manager hooks');
end;

procedure RemoveQueueHooks;
begin
  Check((InsideWait[0] = 0) and (InsideWait[1] = 0), 'workers joined before removing hooks');
  Check(SetThreadManager(Original), 'restore thread manager');
  Original.BasicEventDestroy(FirstReturn);
  Original.BasicEventDestroy(ReturnGate);
end;

procedure BeginQueueCapture;
begin
  { Only call between cases, with every prior worker joined. }
  Check((InsideWait[0] = 0) and (InsideWait[1] = 0), 'no active previous queue wait');
  Captured := 0;
  WaitCalls[0] := 0;
  WaitCalls[1] := 0;
  HoldSide := -1;
  QueueEvents[0] := nil;
  QueueEvents[1] := nil;
  Capturing := True;
end;

procedure EndQueueCapture;
begin
  Capturing := False;
  Check(Captured = 2, 'capture reader and writer events');
end;

function QueueWaitCalls(Side: Integer): LongInt;
begin
  Result := InterlockedCompareExchange(WaitCalls[Side], 0, 0);
end;

procedure WaitForQueueWaiters(Side, Count: Integer);
begin
  WaitForCount(InsideWait[Side], Count, 'queue wait registration');
end;

procedure HoldQueueReturns(Side: Integer);
begin
  { Side remains fixed while workers are alive. }
  HoldSide := Side;
end;

procedure PrepareNextReturn;
begin
  Original.BasicEventResetEvent(FirstReturn);
  Original.BasicEventResetEvent(ReturnGate);
end;

procedure CheckSingleWake;
begin
  Check(Original.BasicEventWaitFor(2000, FirstReturn, False) = Ord(wrSignaled), 'first native wake');
  { The first native wait has consumed notification, but its queue operation
    is held at ReturnGate. A second immediate native wait must not succeed.
    This catches manual-reset broadcast even when Linux hides losing native
    wakeups inside BasicEventWaitFor's predicate loop. No timing threshold. }
  Check(Original.BasicEventWaitFor(0, QueueEvents[HoldSide], False) = Ord(wrTimeout), 'one item/slot must not notify another waiter');
end;

procedure ReleaseQueueReturn;
begin
  Original.BasicEventSetEvent(ReturnGate);
end;

end.
