{ Two managed out formals can designate the same caller slot. }

type
  TBreadthOutBatch = procedure(out First, Second: IInterface; Reject: Boolean; var AliasSeen: Boolean);

procedure BreadthReplaceTwoOwners(out First, Second: IInterface; Reject: Boolean; var AliasSeen: Boolean);
begin
  Check((First = nil) and (Second = nil), 'breadth-two-out-parameters-clear-their-caller-slots');
  First := TIntersectionOwner.Create;
  AliasSeen := Second <> nil;
  If Reject then
    raise EAbort.Create('out replacement stopped');
  Second := TIntersectionOwner.Create;
end;

procedure BreadthExerciseOutBatch(Aliased, Reject: Boolean);
var
  Packet: record
    Primary, Secondary: IInterface;
    Guard: Int64;
  end;
  Next: PInterface;
  WriteBatch: TBreadthOutBatch;
  AliasSeen, Caught: Boolean;
  ExpectedReleased: Integer;
begin
  TIntersectionOwner.Destroyed := 0;
  Packet.Primary := TIntersectionOwner.Create;
  Packet.Secondary := TIntersectionOwner.Create;
  Packet.Guard := OpaqueI(89000000041);
  If Aliased then
    Next := @Packet.Primary
  else
    Next := @Packet.Secondary;
  WriteBatch := BreadthReplaceTwoOwners;
  AliasSeen := False;
  Caught := False;
  try
    WriteBatch(Packet.Primary, Next^, Reject, AliasSeen);
  except
    on E: EAbort do Caught := E.Message = 'out replacement stopped';
  end;
  Check((AliasSeen = Aliased) and (Caught = Reject), 'breadth-two-out-parameters-observe-actual-alias-and-exit');
  ExpectedReleased := 2 - Ord(Aliased and Reject);
  Check((TIntersectionOwner.Destroyed = ExpectedReleased) and (Packet.Primary <> nil)
    and ((Packet.Secondary <> nil) = (Aliased or not Reject)) and (Packet.Guard = 89000000041),
    'breadth-two-out-parameters-release-only-replaced-owners');
  Packet.Primary := nil;
  Packet.Secondary := nil;
  Check(TIntersectionOwner.Destroyed = 4 - Ord(Reject), 'breadth-two-out-parameters-final-clear-balances-owners');
  Mix(UInt64(TIntersectionOwner.Destroyed));
end;

procedure RunBreadthTwoOutParameters;
begin
  BreadthExerciseOutBatch(False, False);
  BreadthExerciseOutBatch(False, True);
  BreadthExerciseOutBatch(True, False);
  BreadthExerciseOutBatch(True, True);
end;
