{$if defined(HAS_ANON) and defined(BREADTH_MAIN_FORCE_QUEUE)}
{ A deferred callback keeps its captured interface alive after the posting scope exits. }

var
  BreadthQueuedTag: Int64;

procedure BreadthPostCapturedOwner(Reject: Boolean);
var
  Owner: IBreadthTaggedOwner;
begin
  Owner := TBreadthTaggedOwner.Create;
  TThread.ForceQueue(nil,
    procedure
    begin
      BreadthQueuedTag := Owner.Tag;
      If Reject then
        raise EAbort.Create('breadth queued closure');
    end);
end;

procedure RunBreadthQueuedClosure;
var
  Reject, Caught, Dispatched: Boolean;
begin
  for Reject := False to True do begin
    BreadthQueuedTag := 0;
    TBreadthTaggedOwner.Destroyed := 0;
    BreadthPostCapturedOwner(Reject);
    Check((BreadthQueuedTag = 0) and (TBreadthTaggedOwner.Destroyed = 0), 'breadth-queued-closure-keeps-owner-past-posting-scope');
    Caught := False;
    Dispatched := False;
    try
      Dispatched := CheckSynchronize(0);
    except
      on E: EAbort do Caught := E.Message = 'breadth queued closure';
    end;
    {$ifdef FPC}
    Check((Caught = Reject) and (Dispatched = not Reject), 'breadth-queued-closure-transfers-callback-exception');
    {$else}
    { Delphi routes queued exceptions to the optional application exception handler. }
    Check(not Caught and Dispatched, 'breadth-queued-closure-returns-after-callback-exception');
    {$endif}
    Check(BreadthQueuedTag = 74000000051, 'breadth-queued-closure-calls-captured-interface-after-return');
    Check(TBreadthTaggedOwner.Destroyed = 1, 'breadth-queued-closure-releases-owner-once-after-drain');
    Check(not CheckSynchronize(0), 'breadth-queued-closure-leaves-no-work-after-drain');
  end;
end;
{$ifend}
