{ A by-value slice acquires nested owners and retires its edited copy on unwind. }

function BreadthEditCopiedOwners(Items: array of TBreadthDelivered; Reject: Boolean): TBreadthDelivered;
begin
  Check((High(Items) = 1) and (Items[0].Payload <> nil) and (Items[1].Payload <> nil),
    'breadth-open-value-slice-receives-nested-interface-fields');
  Items[0].Payload := TBreadthTaggedOwner.Create;
  Items[0].Ticket := Items[0].Ticket + Items[1].Ticket * 2;
  Items[0].Note := Items[0].Note + '-edited';
  Items[1].Payload := nil;
  If Reject then
    raise EAbort.Create('slice edit rejected');
  Result := Items[0];
end;

procedure BreadthExerciseCopiedOwners(Reject: Boolean);
var
  Source: array[-4..-2] of TBreadthDelivered;
  Packet, Pending: TBreadthDelivered;
  FirstOwner, SecondOwner: Pointer;
  Caught: Boolean;
begin
  Source[-4].Payload := TBreadthTaggedOwner.Create;
  Source[-4].Ticket := OpaqueI(-71);
  Source[-4].Note := 'left';
  Source[-3].Payload := TBreadthTaggedOwner.Create;
  Source[-3].Ticket := OpaqueI(37);
  Source[-3].Note := 'right';
  Source[-2].Ticket := -301;
  FirstOwner := Pointer(Source[-4].Payload);
  SecondOwner := Pointer(Source[-3].Payload);
  Packet.Ticket := 41;
  Packet.Note := 'previous';
  Caught := False;
  try
    Pending := BreadthEditCopiedOwners(Slice(Source, Integer(OpaqueI(2))), Reject);
    Packet := Pending;
  except
    on E: EAbort do Caught := E.Message = 'slice edit rejected';
  end;
  Check((Pointer(Source[-4].Payload) = FirstOwner) and (Pointer(Source[-3].Payload) = SecondOwner)
    and (Source[-4].Ticket = -71) and (Source[-4].Note = 'left')
    and (Source[-3].Ticket = 37) and (Source[-3].Note = 'right') and (Source[-2].Ticket = -301),
    'breadth-open-value-slice-local-edit-leaves-caller-records-intact');
  If Reject then
    Check(Caught and (Packet.Payload = nil) and (Packet.Ticket = 41) and (Packet.Note = 'previous')
      and (TBreadthTaggedOwner.Destroyed = 1), 'breadth-open-value-slice-unwind-releases-local-edit')
  else
    Check(not Caught and (Packet.Ticket = 3) and (Packet.Note = 'left-edited') and (Packet.Payload <> nil)
      and (Pointer(Packet.Payload) <> FirstOwner) and (Pointer(Packet.Payload) <> SecondOwner)
      and (TBreadthTaggedOwner.Destroyed = 0), 'breadth-open-value-slice-return-transfers-edited-owner');
  Mix(UInt64(Packet.Ticket));
end;

procedure RunBreadthCopiedOwners;
var
  Reject: Boolean;
begin
  for Reject := False to True do begin
    TBreadthTaggedOwner.Destroyed := 0;
    BreadthExerciseCopiedOwners(Reject);
    Check(TBreadthTaggedOwner.Destroyed = 3, 'breadth-open-value-slice-releases-all-three-owners');
  end;
end;
