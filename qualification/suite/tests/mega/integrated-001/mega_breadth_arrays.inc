{ By-value open arrays, Slice and indexed static-array function results. }

procedure BreadthLocalSlice(Items: array of TCrossEntry; var Trace: AnsiString);
begin
  Check((Low(Items) = 0) and (High(Items) = 1), 'breadth-open-value-slice-bounds');
  Items[0].Text := Items[0].Text + '!';
  Items[0].Code := Items[0].Code + Items[1].Code * 3;
  Items[1].Text := Items[1].Text + '?';
  Trace := Items[0].Text + '/' + Items[1].Text + '/' + AnsiString(IntToStr(Items[0].Code));
end;

procedure BreadthWritableSlice(var Items: array of TCrossEntry);
var
  First: TCrossEntry;
begin
  Check((High(Items) = 1) and (Length(Items) = 2), 'breadth-open-var-slice-bounds');
  First := Items[0];
  Items[0] := Items[1];
  Items[1] := First;
  Items[0].Text := Items[0].Text + 'x';
end;

procedure RunBreadthManagedSlices;
var
  Items: array[-7..-5] of TCrossEntry;
  Snapshot: TCrossEntry;
  Trace: AnsiString;
  Count: Integer;
begin
  Items[-7].Code := OpaqueI(-37);
  Items[-7].Text := 'left';
  Items[-6].Code := OpaqueI(71);
  Items[-6].Text := 'right';
  Items[-5].Code := OpaqueI(109);
  Items[-5].Text := 'tail';
  Snapshot := Items[-6];
  Count := Integer(OpaqueI(2));
  BreadthLocalSlice(Slice(Items, Count), Trace);
  Check(Trace = AnsiString('left!/right?/176'), 'breadth-open-value-slice-local-state');
  Check((Items[-7].Code = -37) and (Items[-7].Text = AnsiString('left'))
    and (Items[-6].Text = AnsiString('right')), 'breadth-open-value-slice-caller-unchanged');
  BreadthWritableSlice(Slice(Items, Count));
  Check((Items[-7].Code = 71) and (Items[-7].Text = AnsiString('rightx'))
    and (Items[-6].Code = -37) and (Items[-6].Text = AnsiString('left')), 'breadth-open-var-slice-writes-caller');
  Check((Items[-5].Code = 109) and (Items[-5].Text = AnsiString('tail')), 'breadth-open-var-slice-tail-guard');
  Check((Snapshot.Code = 71) and (Snapshot.Text = AnsiString('right')), 'breadth-open-var-slice-shared-owner');
  Mix(UInt64(Length(Trace) + Items[-7].Code));
end;

type
  TBreadthStaticCards = array[-2..2] of Int64;

function BreadthBuildStaticCards(Anchor: Int64; Reverse: Boolean; var Count: Integer): TBreadthStaticCards; inline;
begin
  Inc(Count);
  Result[-2] := Anchor + 1;
  Result[-1] := Anchor * 3 + 2;
  Result[0] := Anchor * 7 + 3;
  If Reverse then begin
    Result[1] := Anchor * 11 - 4;
    Result[2] := Anchor * 13 - 5;
  end else begin
    Result[1] := Anchor * 11 + 4;
    Result[2] := Anchor * 13 + 5;
  end;
end;

{$R+}
procedure RunBreadthInlineArrayResult;
const
  Expected: array[-2..2] of Int64 = (-100, -301, -704, -1115, -1318);
var
  I, Index, Builds: Integer;
  Actual: Int64;
  InvalidIndex: Boolean;
begin
  Builds := 0;
  for I := Low(Expected) to High(Expected) do
  begin
    Index := Integer(OpaqueI(I));
    Actual := BreadthBuildStaticCards(OpaqueI(-101), OpaqueI(I) >= 1, Builds)[Index];
    Check(Actual = Expected[I], 'breadth-inline-static-array-indexed-result');
    Mix(UInt64(Actual));
  end;
  Check(Builds = 5, 'breadth-inline-static-array-call-count');
  Index := Integer(OpaqueI(3));
  InvalidIndex := False;
  try
    Actual := BreadthBuildStaticCards(-101, True, Builds)[Index];
    Mix(UInt64(Actual));
  except
    on ERangeError do InvalidIndex := True;
  end;
  Check(InvalidIndex, 'breadth-inline-static-array-index-checked');
end;
{$R-}

procedure RunBreadthArrayForms;
begin
  RunBreadthManagedSlices;
  RunBreadthInlineArrayResult;
end;
