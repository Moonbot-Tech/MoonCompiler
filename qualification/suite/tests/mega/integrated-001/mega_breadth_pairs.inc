{ Two static-array results remain alive when passed directly as typed open-array arguments. }

type
  TBreadthPacketPair = array[-3..-2] of TBreadthDelivered;

function BreadthBuildPacketPair(Key: Int64; Initial: AnsiChar; var Builds: Integer): TBreadthPacketPair;
begin
  Inc(Builds);
  Result[-3].Payload := TBreadthTaggedOwner.Create;
  Result[-3].Ticket := Key;
  Result[-3].Note := Initial + AnsiString('0');
  Result[-2].Payload := TBreadthTaggedOwner.Create;
  Result[-2].Ticket := -Key + 13;
  Result[-2].Note := Initial + AnsiString('1');
end;

function BreadthConsumePacketPairs(const Left, Right: array of TBreadthDelivered; Reject: Boolean): TCrossEntry;
begin
  Check((Length(Left) = 2) and (Length(Right) = 2), 'breadth-static-array-results-arrive-as-two-open-slices');
  Check((TBreadthTaggedOwner.Destroyed = 0) and (Left[0].Payload <> nil) and (Left[1].Payload <> nil)
    and (Right[0].Payload <> nil) and (Right[1].Payload <> nil), 'breadth-static-array-results-keep-four-owners-through-consumer');
  If Reject then
    raise EAbort.Create('packet pairs rejected');
  Result.Code := Left[0].Ticket + Right[1].Ticket;
  Result.Text := Left[0].Note + '/' + Right[1].Note;
end;

procedure BreadthExercisePacketPairs(Reject: Boolean);
var
  Builds: Integer;
  Caught: Boolean;
  Answer, Pending: TCrossEntry;
begin
  Builds := 0;
  Caught := False;
  Answer.Code := -31;
  Answer.Text := 'old';
  try
    Pending := BreadthConsumePacketPairs(
      BreadthBuildPacketPair(OpaqueI(22000000039), 'L', Builds), BreadthBuildPacketPair(OpaqueI(-17000000087), 'R', Builds), Reject);
    Answer := Pending;
  except
    on E: EAbort do Caught := E.Message = 'packet pairs rejected';
  end;
  Check((Builds = 2) and (Caught = Reject), 'breadth-static-array-results-build-once-and-route-unwind');
  If Reject then
    Check((Answer.Code = -31) and (Answer.Text = 'old'), 'breadth-static-array-results-rejected-call-leaves-published-result')
  else
    Check((Answer.Code = 39000000139) and (Answer.Text = 'L0/R1'), 'breadth-static-array-results-keep-distinct-payloads');
  Mix(UInt64(Answer.Code));
end;

procedure RunBreadthTemporaryPairs;
var
  Reject: Boolean;
begin
  for Reject := False to True do begin
    TBreadthTaggedOwner.Destroyed := 0;
    BreadthExercisePacketPairs(Reject);
    Check(TBreadthTaggedOwner.Destroyed = 4, 'breadth-static-array-results-release-all-temporary-owners');
  end;
end;
