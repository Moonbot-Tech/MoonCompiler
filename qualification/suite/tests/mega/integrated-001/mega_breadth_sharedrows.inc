{ Same-sized rectangular SetLength detaches both aliased rows and their shared outer array. }

type
  TBreadthPacketRow = array of TBreadthDelivered;
  TBreadthPacketGrid = array of TBreadthPacketRow;

procedure RunBreadthSharedRows;
var
  Active, Frozen: TBreadthPacketGrid;
  InitialOwner: Pointer;
begin
  TBreadthTaggedOwner.Destroyed := 0;
  SetLength(Active, 2);
  SetLength(Active[0], 2);
  Active[0, 0].Payload := TBreadthTaggedOwner.Create;
  Active[0, 0].Ticket := OpaqueI(-211);
  Active[0, 0].Note := 'left';
  Active[0, 1].Payload := TBreadthTaggedOwner.Create;
  Active[0, 1].Note := 'right';
  Active[1] := Active[0];
  Frozen := Active;
  InitialOwner := Pointer(Frozen[0, 0].Payload);

  SetLength(Active, Integer(OpaqueI(2)), Integer(OpaqueI(2)));
  Check((Length(Active) = 2) and (Length(Active[0]) = 2) and (Length(Active[1]) = 2)
    and (Pointer(Active[0]) <> Pointer(Active[1])) and (Pointer(Frozen[0]) = Pointer(Frozen[1])),
    'breadth-rectangular-same-size-splits-previously-shared-active-rows');
  Active[0, 0].Payload := TBreadthTaggedOwner.Create;
  Active[0, 0].Ticket := OpaqueI(703);
  Active[0, 0].Note := 'edited';
  Active[1, 1].Payload := nil;
  Check((Active[0, 0].Ticket = 703) and (Active[0, 0].Note = 'edited') and (Active[1, 1].Payload = nil)
    and (Active[1, 0].Ticket = -211) and (Active[1, 0].Note = 'left') and (Pointer(Active[1, 0].Payload) = InitialOwner)
    and (Active[0, 1].Payload <> nil) and (Active[0, 1].Note = 'right'), 'breadth-rectangular-row-edits-are-independent');
  Check((Frozen[0, 0].Ticket = -211) and (Frozen[0, 0].Note = 'left') and (Frozen[1, 1].Payload <> nil)
    and (TBreadthTaggedOwner.Destroyed = 0), 'breadth-rectangular-snapshot-keeps-shared-original-rows-and-owners');
  Mix(UInt64(Active[0, 0].Ticket));
  Active := nil;
  Check(TBreadthTaggedOwner.Destroyed = 1, 'breadth-rectangular-active-clear-releases-only-new-owner');
  Frozen := nil;
  Check(TBreadthTaggedOwner.Destroyed = 3, 'breadth-rectangular-frozen-clear-releases-original-owners-once');
end;
