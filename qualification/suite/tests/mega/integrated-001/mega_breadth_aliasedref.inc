{ A by-value interface must survive clearing a caller slot passed again by reference. }

type
  TBreadthDelivered = record
    Payload: IBreadthTaggedOwner;
    Ticket: Int64;
    Note: AnsiString;
  end;

  TBreadthRouter = function(Key: Int64; A, B: Double; var Slot: IBreadthTaggedOwner;
    Snapshot: IBreadthTaggedOwner; Reject: Boolean; var Observed: Int64): TBreadthDelivered; cdecl;

function BreadthRouteByValue(Key: Int64; A, B: Double; var Slot: IBreadthTaggedOwner;
  Snapshot: IBreadthTaggedOwner; Reject: Boolean; var Observed: Int64): TBreadthDelivered; cdecl;
begin
  Slot := nil;
  If (Snapshot <> nil) and (TBreadthTaggedOwner.Destroyed = 0) then
    Observed := Snapshot.Tag;
  If Reject then
    raise EAbort.Create('route rejection');
  Result.Payload := Snapshot;
  Result.Ticket := Key + Observed + Trunc(A * 16.0) - Trunc(B * 8.0);
  Result.Note := AnsiString('delivered');
end;

procedure BreadthExerciseRouter(Reject: Boolean);
var
  Route: TBreadthRouter;
  Slot: IBreadthTaggedOwner;
  Packet, Pending: TBreadthDelivered;
  Observed: Int64;
  Caught: Boolean;
begin
  Route := BreadthRouteByValue;
  Slot := TBreadthTaggedOwner.Create;
  Packet.Ticket := -901;
  Packet.Note := 'prior';
  Observed := 0;
  Caught := False;
  try
    Pending := Route(OpaqueI(9000000053), OpaqueD(2.5), OpaqueD(-0.75), Slot, Slot, Reject, Observed);
    Packet := Pending;
  except
    on E: EAbort do Caught := E.Message = 'route rejection';
  end;
  Check((Slot = nil) and (Observed = 74000000051) and (Caught = Reject), 'breadth-by-value-interface-outlives-source-slot-clear');
  If Reject then
    Check((Packet.Ticket = -901) and (Packet.Note = 'prior') and (Packet.Payload = nil),
      'breadth-by-value-interface-unwind-keeps-staged-result-unpublished')
  else
    Check((Packet.Ticket = 83000000150) and (Packet.Note = 'delivered') and (Packet.Payload <> nil)
      and (Packet.Payload.Tag = 74000000051) and (TBreadthTaggedOwner.Destroyed = 0),
      'breadth-by-value-interface-success-transfers-reference-to-result');
  Mix(UInt64(Packet.Ticket));
end;

procedure RunBreadthByValueInterface;
begin
  TBreadthTaggedOwner.Destroyed := 0;
  BreadthExerciseRouter(False);
  Check(TBreadthTaggedOwner.Destroyed = 1, 'breadth-by-value-interface-success-releases-on-scope-exit');
  TBreadthTaggedOwner.Destroyed := 0;
  BreadthExerciseRouter(True);
  Check(TBreadthTaggedOwner.Destroyed = 1, 'breadth-by-value-interface-failure-releases-on-scope-exit');
end;
