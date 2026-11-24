{$if defined(HAS_ANON) and defined(HAS_INLINEVAR)}
{ A typed for-in variable keeps its managed captured item after Break and exhaustion. }

function BreadthCaptureLoopPacket(const Packets: array of TBreadthDelivered; StopAt: Integer;
  var Visits: Integer): TBreadthScopedAction;
begin
  Result := nil;
  for var Item: TBreadthDelivered in Packets do begin
    Inc(Visits);
    If Visits = 1 then
      Result := function(Delta: Integer): TCrossEntry
        begin
          Check(Item.Payload <> nil, 'breadth-for-in-closure-keeps-typed-item-owner');
          Result.Code := Item.Ticket + Item.Payload.Tag + Delta;
          Result.Text := Item.Note + ':' + AnsiString(IntToStr(Delta));
        end;
    If Visits = StopAt then
      Break;
  end;
end;

function BreadthMakeLoopCapture(StopAt: Integer; var Visits: Integer): TBreadthScopedAction;
var
  Rows: array[1..3] of TBreadthDelivered;
  I: Integer;
begin
  for I := Low(Rows) to High(Rows) do begin
    Rows[I].Payload := TBreadthTaggedOwner.Create;
    Rows[I].Ticket := OpaqueI(13000000001) * I;
    Rows[I].Note := AnsiString('row-' + IntToStr(I));
  end;
  Result := BreadthCaptureLoopPacket(Rows, StopAt, Visits);
end;

procedure BreadthExerciseLoopCapture(StopAt, ExpectedVisits: Integer; ExpectedCode: Int64; const ExpectedText: AnsiString);
var
  Action: TBreadthScopedAction;
  Answer: TCrossEntry;
  Visits: Integer;
begin
  Visits := 0;
  Action := BreadthMakeLoopCapture(StopAt, Visits);
  Check((Visits = ExpectedVisits) and (TBreadthTaggedOwner.Destroyed = 2),
    'breadth-for-in-closure-releases-uncaptured-source-items');
  Answer := Action(Integer(OpaqueI(7)));
  Check((Answer.Code = ExpectedCode) and (Answer.Text = ExpectedText), 'breadth-for-in-closure-observes-last-assigned-item');
  Mix(UInt64(Answer.Code));
end;

procedure RunBreadthLoopCapture;
var
  Empty: TBreadthScopedAction;
  Visits: Integer;
begin
  Visits := 0;
  Empty := BreadthCaptureLoopPacket([], 1, Visits);
  Check(not Assigned(Empty) and (Visits = 0), 'breadth-for-in-closure-empty-source-returns-no-callback');

  TBreadthTaggedOwner.Destroyed := 0;
  BreadthExerciseLoopCapture(2, 2, 100000000060, 'row-2:7');
  Check(TBreadthTaggedOwner.Destroyed = 3, 'breadth-for-in-closure-break-releases-last-item');

  TBreadthTaggedOwner.Destroyed := 0;
  BreadthExerciseLoopCapture(4, 3, 113000000061, 'row-3:7');
  Check(TBreadthTaggedOwner.Destroyed = 3, 'breadth-for-in-closure-exhaustion-releases-last-item');
end;
{$ifend}
