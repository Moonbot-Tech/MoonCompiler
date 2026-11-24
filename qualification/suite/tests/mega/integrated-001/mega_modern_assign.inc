{$ifdef HAS_MREC}
{ A custom Assign updates its destination fields in source order. }

type
  TBreadthAssignedPacket = record
    Serial: Int64;
    Owner: IInterface;
    Note: AnsiString;
    class operator Assign(var Dest: TBreadthAssignedPacket; const [ref] Source: TBreadthAssignedPacket);
  end;
  TBreadthAssignedEnvelope = record
    Guard: Integer;
    Data: TBreadthAssignedPacket;
  end;

var
  BreadthAssignCalls: Integer;

class operator TBreadthAssignedPacket.Assign(var Dest: TBreadthAssignedPacket; const [ref] Source: TBreadthAssignedPacket);
begin
  Inc(BreadthAssignCalls);
  Dest.Serial := Source.Serial * 3 + 7;
  If Source.Serial < 0 then
    raise EAbort.Create('assignment stopped');
  Dest.Owner := Source.Owner;
  Dest.Note := Source.Note + '!';
end;

procedure BreadthExerciseManagedAssign;
var
  Source: TBreadthAssignedPacket;
  Dest: TBreadthAssignedEnvelope;
  FirstOwner: Pointer;
  Caught: Boolean;
begin
  Source.Serial := OpaqueI(101);
  Source.Note := 'first';
  Source.Owner := TIntersectionOwner.Create;
  FirstOwner := Pointer(Source.Owner);
  Dest.Guard := 613;
  Dest.Data.Owner := TIntersectionOwner.Create;
  Dest.Data := Source;
  Check((BreadthAssignCalls = 1) and (TIntersectionOwner.Destroyed = 1),
    'breadth-custom-assign-releases-previous-owner-once');
  Check((Dest.Data.Serial = 310) and (Dest.Data.Note = 'first!') and (Pointer(Dest.Data.Owner) = FirstOwner),
    'breadth-custom-assign-updates-nested-destination');

  Source.Serial := OpaqueI(-519);
  Source.Note := 'second';
  Source.Owner := TIntersectionOwner.Create;
  Caught := False;
  try
    Dest.Data := Source;
  except
    on E: EAbort do Caught := E.Message = 'assignment stopped';
  end;
  Check(Caught and (BreadthAssignCalls = 2) and (Dest.Data.Serial = -1550), 'breadth-custom-assign-throw-keeps-completed-scalar');
  Check((Dest.Data.Note = 'first!') and (Pointer(Dest.Data.Owner) = FirstOwner) and (TIntersectionOwner.Destroyed = 1),
    'breadth-custom-assign-throw-leaves-unwritten-managed-fields');

  Source.Serial := OpaqueI(707);
  Dest.Data := Source;
  Check((BreadthAssignCalls = 3) and (TIntersectionOwner.Destroyed = 2) and (Dest.Guard = 613),
    'breadth-custom-assign-retry-releases-old-payload-and-keeps-neighbor');
  Check((Dest.Data.Serial = 2128) and (Dest.Data.Note = 'second!') and (Dest.Data.Owner = Source.Owner),
    'breadth-custom-assign-retry-publishes-second-payload');
  Mix(UInt64(Dest.Data.Serial));
end;

procedure RunBreadthManagedAssign;
begin
  TIntersectionOwner.Destroyed := 0;
  BreadthAssignCalls := 0;
  BreadthExerciseManagedAssign;
  Check(TIntersectionOwner.Destroyed = 3, 'breadth-custom-assign-scope-releases-all-owners');
end;
{$endif}
