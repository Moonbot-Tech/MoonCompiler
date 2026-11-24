{$ifdef HAS_ANON}
{ A procedure reference clears a managed out record before entering its captured frame. }

type
  TBreadthOutClosure = reference to procedure(Key: Int64; Scale: Double; out Packet: TBreadthDelivered);

function BreadthMakeOutClosure(Reject: Boolean): TBreadthOutClosure;
var
  Owner: IBreadthTaggedOwner;
begin
  Owner := TBreadthTaggedOwner.Create;
  Result := procedure(Key: Int64; Scale: Double; out Packet: TBreadthDelivered)
    begin
      Check((Packet.Payload = nil) and (Packet.Note = '') and (TBreadthTaggedOwner.Destroyed = 1),
        'breadth-procedure-reference-out-clears-caller-managed-fields-before-body');
      Packet.Ticket := Key + Owner.Tag + Trunc(Scale * 8);
      Packet.Note := 'begun';
      If Reject then
        raise EAbort.Create('breadth out closure');
      Packet.Payload := Owner;
      Packet.Note := 'complete';
    end;
end;

procedure BreadthExerciseOutClosure(Reject: Boolean);
var
  FillPacket: TBreadthOutClosure;
  Packet: TBreadthDelivered;
  Caught: Boolean;
begin
  Packet.Payload := TBreadthTaggedOwner.Create;
  Packet.Note := 'old';
  Packet.Ticket := 73;
  FillPacket := BreadthMakeOutClosure(Reject);
  Caught := False;
  try
    FillPacket(OpaqueI(-39000000031), OpaqueD(2.625), Packet);
  except
    on E: EAbort do Caught := E.Message = 'breadth out closure';
  end;
  Check((Caught = Reject) and (Packet.Ticket = 35000000041), 'breadth-procedure-reference-out-keeps-wide-partial-write');
  If Reject then
    Check((Packet.Note = 'begun') and (Packet.Payload = nil), 'breadth-procedure-reference-out-exposes-committed-fields-on-exception')
  else
    Check((Packet.Note = 'complete') and (Packet.Payload <> nil) and (Packet.Payload.Tag = 74000000051),
      'breadth-procedure-reference-out-publishes-captured-owner-on-success');
end;

procedure RunBreadthManagedOutClosure;
var
  Reject: Boolean;
begin
  for Reject := False to True do begin
    TBreadthTaggedOwner.Destroyed := 0;
    BreadthExerciseOutClosure(Reject);
    Check(TBreadthTaggedOwner.Destroyed = 2, 'breadth-procedure-reference-out-releases-captured-and-replaced-owner');
  end;
end;
{$endif}
