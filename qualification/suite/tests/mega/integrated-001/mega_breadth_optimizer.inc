{ Revisit historically fragile optimizer shapes with runtime data and
  explicit outputs at the next observable boundary. }

type
  TBreadthTable = array[0..15] of Byte;
  PBreadthTable = ^TBreadthTable;

procedure RunBreadthRepeatedLookup;
const
  TableA: TBreadthTable = (4, 13, 6, 7, 2, 9, 3, 12, 1, 15, 10, 0, 14, 8, 5, 11);
  TableB: TBreadthTable = (9, 1, 13, 6, 0, 11, 3, 7, 14, 4, 12, 2, 10, 15, 5, 8);
  Initial: array[0..5] of Byte = (1, 4, 7, 11, 13, 15);
  Expected: array[0..4, 0..5] of Byte = (
    (12, 8, 14, 4, 12, 3), (13, 14, 3, 12, 3, 6), (8, 14, 15, 14, 12, 11),
    (6, 9, 4, 4, 2, 2), (15, 0, 15, 5, 15, 5));
var
  Cells: array[0..5] of Byte;
  Table: PBreadthTable;
  RoundIndex, I: Integer;
begin
  for I := Low(Initial) to High(Initial) do
    Cells[I] := Byte(OpaqueI(Initial[I]));
  Table := @TableA;
  for RoundIndex := Low(Expected) to High(Expected) do
  begin
    for I := Low(Cells) to High(Cells) do
      Cells[I] := Table^[(Cells[I] + RoundIndex + I) and 15];
    for I := Low(Cells) to High(Cells) do
      Cells[I] := Cells[I] xor Byte(RoundIndex + 1);
    for I := Low(Cells) to High(Cells) do
    begin
      Check(Cells[I] = Expected[RoundIndex, I], 'breadth-repeated-lookup-checkpoint');
      Mix(Cells[I]);
    end;
    If Table = @TableA then
      Table := @TableB
    else
      Table := @TableA;
  end;
end;

type
  TBreadthCompareSlots = array[0..7] of TCrossPacked;

function BreadthAddressBackedge(const Left, Right: TBreadthCompareSlots; Bias, Remaining: Integer): UInt64;
var
  Index, Cursor: Integer;
begin
  Cursor := 0;
  Result := 0;
  while Remaining > 0 do
  begin
    Index := (Cursor + Bias) and 7;
    If Left[Index].Prefix <> Right[Index].Prefix then
      Result := Result or (UInt64(1) shl Cursor);
    If Left[Index].Marker <> Right[Index].Marker then
      Result := Result or (UInt64(1) shl (16 + Cursor));
    If Left[Index].Value <> Right[Index].Value then
      Result := Result or (UInt64(1) shl (32 + Cursor));
    Inc(Cursor);
    Dec(Remaining);
  end;
end;

procedure RunBreadthAddressBackedge;
var
  Left, Right: TBreadthCompareSlots;
  I: Integer;
  Bits: UInt64;
begin
  for I := Low(Left) to High(Left) do
  begin
    Left[I].Prefix := Byte(OpaqueI(I + 31));
    Left[I].Marker := Word(OpaqueI(101 + I * 13));
    Left[I].Value := OpaqueI(730000003 * Int64(I));
  end;
  Right := Left;
  Check(BreadthAddressBackedge(Left, Right, Integer(OpaqueI(6)), Integer(OpaqueI(8))) = 0,
    'breadth-address-backedge-equal-control');
  Right[6].Prefix := 71;
  Right[0].Marker := $ABCD;
  Right[4].Value := -901200007;
  Bits := BreadthAddressBackedge(Left, Right, Integer(OpaqueI(6)), Integer(OpaqueI(8)));
  Check(Bits = UInt64($0000004000040001), 'breadth-address-backedge-all-fields');
  Bits := BreadthAddressBackedge(Right, Left, Integer(OpaqueI(-3)), Integer(OpaqueI(4)));
  Check(Bits = UInt64($0000000000080002), 'breadth-address-backedge-tail');
  Mix(Bits);
end;

type
  TBreadthSignedCode = type SmallInt;
  TBreadthNarrowKeys = record
    Code: TBreadthSignedCode;
    Status: LongInt;
  end;

function BreadthExtendField(var Item: TBreadthNarrowKeys; Source: Int64; Alternate: Boolean): UInt64;
var
  Raw: TBreadthSignedCode;
  ExpectedTag: UInt64;
begin
  Raw := TBreadthSignedCode(Source);
  ExpectedTag := UInt64($1234567800010000);
  with Item do
  begin
    If Alternate then begin
      Code := Raw;
      Inc(Status, 17);
    end else begin
      Code := TBreadthSignedCode(not SmallInt(Raw));
      Dec(Status, 7);
    end;
    Result := ExpectedTag or UInt64(Word(Code));
  end;
end;

procedure RunBreadthLongNarrowing;
var
  Item: TBreadthNarrowKeys;
  Key: UInt64;
begin
  Item.Status := 100;
  Key := BreadthExtendField(Item, OpaqueI(Int64($0123456700008001)), True);
  Check(Key = UInt64($1234567800018001), 'breadth-extension-store-cast-negative');
  Check((SmallInt(Item.Code) = -32767) and (Item.Status = 117), 'breadth-extension-store-raw-first');
  Mix(Key);
  Key := BreadthExtendField(Item, OpaqueI(Int64($0000067800000123)), False);
  Check(Key = UInt64($123456780001FEDC), 'breadth-extension-store-cast-complement');
  Check((SmallInt(Item.Code) = -292) and (Item.Status = 110), 'breadth-extension-store-raw-second');
  Mix(Key);
end;

function BreadthStoreThroughCleanup(var Whole: TCrossPacked; var Cell: Int64; Stop: Boolean;
  var CleanupValue: Int64): Int64;
begin
  Cell := OpaqueI(7000000019);
  try
    Whole.Marker := Word(OpaqueI($8174));
    If Stop then
      raise EAbort.Create('packed store observer');
    Whole.Value := Whole.Value + 37;
    Result := Cell;
  finally
    CleanupValue := Whole.Value;
  end;
end;

procedure RunBreadthObservedEarlyStore;
var
  Item: TCrossPacked;
  CleanupValue, Returned: Int64;
  Caught: Boolean;
begin
  Item.Prefix := $D2;
  Item.Marker := 0;
  Item.Value := -5;
  CleanupValue := -7;
  Returned := -901;
  Caught := False;
  try
    Returned := BreadthStoreThroughCleanup(Item, Item.Value, True, CleanupValue);
  except
    on EAbort do Caught := True;
  end;
  Check(Caught and (Returned = -901), 'breadth-store-throw-no-scalar-return');
  Check((CleanupValue = 7000000019) and (Item.Value = 7000000019), 'breadth-store-throw-observes-first-write');
  Check((Item.Prefix = $D2) and (Item.Marker = $8174), 'breadth-store-throw-neighbor-values');
  Returned := BreadthStoreThroughCleanup(Item, Item.Value, False, CleanupValue);
  Check((Returned = 7000000056) and (CleanupValue = 7000000056), 'breadth-store-normal-observes-second-write');
  Mix(UInt64(Returned));
end;

type
  TBreadthWorklistResize = procedure(var Work: TCrossEntries; Size: Integer);

procedure BreadthResizeWorklist(var Work: TCrossEntries; Size: Integer);
begin
  SetLength(Work, Size);
  If Size = 5 then begin
    Work[2].Code := -301;
    Work[2].Text := 'new-a';
    Work[3].Code := 709;
    Work[3].Text := 'new-b';
    Work[4].Code := 499;
    Work[4].Text := 'discard';
  end;
end;

procedure RunBreadthWorklistLength;
var
  Work, Initial: TCrossEntries;
  Resize: TBreadthWorklistResize;
  Index: Integer;
  Score: Int64;
  Tags: AnsiString;
begin
  SetLength(Work, 2);
  Work[0].Code := OpaqueI(71);
  Work[0].Text := 'entry-0';
  Work[1].Code := OpaqueI(-33);
  Work[1].Text := 'entry-1';
  Initial := Work;
  Resize := BreadthResizeWorklist;
  Index := 0;
  Score := 0;
  while Index < Length(Work) do begin
    Score := Score + Work[Index].Code * (Index + 1);
    Tags := Tags + Work[Index].Text + AnsiChar('|');
    case Index of
      1: Resize(Work, 5);
      3: Resize(Work, 4);
    end;
    Inc(Index);
  end;
  Check((Index = 4) and (Score = 1938), 'breadth-worklist-length-changes-at-backedge');
  Check(Tags = AnsiString('entry-0|entry-1|new-a|new-b|'), 'breadth-worklist-after-resize-indexing');
  Check((Length(Initial) = 2) and (Initial[1].Code = -33) and (Initial[1].Text = AnsiString('entry-1')),
    'breadth-worklist-original-alias-keeps-old-length');
  Mix(UInt64(Score));
end;

function BreadthPossiblyEmptyLoop(First, Last, Divisor: Integer; var Visits: Integer): Integer;
var
  Index: Integer;
begin
  Result := 73;
  for Index := First to Last do
    try
      Result := Result + 100 div Divisor + Index;
    finally
      Inc(Visits);
    end;
end;

procedure RunBreadthZeroTripTrap;
var
  Visits, Answer: Integer;
  Threw: Boolean;
begin
  Visits := 0;
  Answer := BreadthPossiblyEmptyLoop(Integer(OpaqueI(3)), Integer(OpaqueI(5)), Integer(OpaqueI(4)), Visits);
  Check((Answer = 160) and (Visits = 3), 'breadth-zero-trip-live-control');
  Visits := 0;
  Threw := False;
  try
    Answer := BreadthPossiblyEmptyLoop(Integer(OpaqueI(5)), Integer(OpaqueI(3)), Integer(OpaqueI(0)), Visits);
  except
    on EDivByZero do Threw := True;
  end;
  Check(not Threw and (Visits = 0) and (Answer = 73), 'breadth-zero-trip-does-not-hoist-trap');
  Mix(UInt64(Answer));
end;

procedure RunBreadthOptimizerForms;
begin
  RunBreadthRepeatedLookup;
  RunBreadthAddressBackedge;
  RunBreadthLongNarrowing;
  RunBreadthObservedEarlyStore;
  RunBreadthWorklistLength;
  RunBreadthZeroTripTrap;
end;
