{ Checked loop latches and conversions at ordinal range boundaries. }

{$Q+}
procedure BreadthExtremeLoops(StartHigh, FinishHigh, StartLow, FinishLow: Int64;
  var Ascending, Descending, AscendingFinally, DescendingFinally: Integer);
var
  Value: Int64;
  Lane, Visits: Integer;
begin
  Visits := 0;
  for Value := StartHigh to FinishHigh do
  begin
    Lane := Integer(UInt64(Value) and 7);
    try
      Inc(Visits);
      If Visits > 4 then Break;
      If Lane = 5 then Continue;
      Ascending := Ascending * 10 + Lane;
    finally
      AscendingFinally := AscendingFinally * 10 + Lane;
    end;
  end;
  Visits := 0;
  for Value := StartLow downto FinishLow do
  begin
    Lane := Integer(UInt64(Value) and 7);
    try
      Inc(Visits);
      If Visits > 4 then Break;
      If Lane = 2 then Continue;
      Descending := Descending * 10 + Lane;
    finally
      DescendingFinally := DescendingFinally * 10 + Lane;
    end;
  end;
end;
{$Q-}

procedure RunBreadthCheckedExtremeLoops;
var
  Ascending, Descending, AscFinally, DescFinally: Integer;
begin
  Ascending := 0;
  Descending := 0;
  AscFinally := 0;
  DescFinally := 0;
  BreadthExtremeLoops(OpaqueI(High(Int64) - 3), OpaqueI(High(Int64)),
    OpaqueI(Low(Int64) + 3), OpaqueI(Low(Int64)), Ascending, Descending, AscFinally, DescFinally);
  Check((Ascending = 467) and (AscFinally = 4567), 'breadth-checked-for-no-overflow-at-high-int64');
  Check((Descending = 310) and (DescFinally = 3210), 'breadth-checked-downto-no-overflow-at-low-int64');
  Mix(UInt64(AscFinally * 10000 + DescFinally));
end;

procedure RunBreadthSetSelectorDomain;
const
  Probes: array[0..11] of Integer = (-256, -225, -1, 0, 1, 31, 32, 63, 127, 255, 256, 287);
  Guarded: array[0..11] of Integer = (0, 0, 0, 3, 1, 3, 0, 0, 2, 2, 0, 0);
  Truncated: array[0..11] of Integer = (3, 3, 2, 3, 1, 3, 0, 0, 2, 2, 3, 3);
var
  Small: TSmallSet;
  Big: TByteSet;
  I, Value, Actual: Integer;
begin
  Small := [0, 1, 31];
  Big := [0, 31, 127, 255];
  for I := Low(Probes) to High(Probes) do
  begin
    Value := Integer(OpaqueI(Probes[I]));
    Actual := Ord(Value in Small) + 2 * Ord(Value in Big);
    Check(Actual = Guarded[I], 'breadth-set-narrow-domain-rejects-outside-integers');
    Actual := Ord(Byte(Value) in Small) + 2 * Ord(Byte(Value) in Big);
    Check(Actual = Truncated[I], 'breadth-set-explicit-byte-truncation-before-membership');
    Mix(UInt64(Actual));
  end;
end;

var
  BreadthCreatedOwners: Integer;

function BreadthOwnerArgument(AbortBuild: Boolean): IInterface;
begin
  If AbortBuild and (BreadthCreatedOwners = 4) then
    raise EAbort.Create('dynamic array constructor argument');
  Result := TIntersectionOwner.Create;
  Inc(BreadthCreatedOwners);
end;

function BreadthOwnerArray(AbortBuild: Boolean): TArray<IInterface>;
begin
  Result := TArray<IInterface>.Create(BreadthOwnerArgument(AbortBuild),
    BreadthOwnerArgument(AbortBuild), BreadthOwnerArgument(AbortBuild));
end;

procedure BreadthCheckOwnerArray;
var
  Kept, Pending: TArray<IInterface>;
  Caught: Boolean;
begin
  Kept := BreadthOwnerArray(False);
  Check((Length(Kept) = 3) and (BreadthCreatedOwners = 3) and (TIntersectionOwner.Destroyed = 0),
    'breadth-dynarray-constructor-owned-elements');
  Caught := False;
  try
    Pending := BreadthOwnerArray(True);
    Kept := Pending;
  except
    on EAbort do Caught := True;
  end;
  Check(Caught, 'breadth-dynarray-constructor-argument-throws');
  { The second evaluation throws whichever argument it happens to be. }
  Check((BreadthCreatedOwners = 4) and (TIntersectionOwner.Destroyed = 1),
    'breadth-dynarray-constructor-cleans-failed-arguments');
  Check((Length(Kept) = 3) and (Kept[0] <> nil) and (Kept[1] <> nil) and (Kept[2] <> nil),
    'breadth-dynarray-constructor-keeps-previous-value');
  Mix(UInt64(Length(Kept)));
end;

procedure RunBreadthArrayConstructorCleanup;
begin
  BreadthCreatedOwners := 0;
  TIntersectionOwner.Destroyed := 0;
  BreadthCheckOwnerArray;
  Check(TIntersectionOwner.Destroyed = BreadthCreatedOwners, 'breadth-dynarray-constructor-releases-final-owners');
end;

type
  TBreadthWordOverlay = packed record
    Start: Byte;
    LengthWord: Word;
    Tag: Byte;
    Data: Cardinal;
  end;

procedure BreadthChangeOverlay(var Raw: UInt64; var LengthWord: Word; NewLength: Word;
  out Observed: UInt64);
begin
  LengthWord := NewLength;
  Observed := Raw;
  Raw := Raw xor UInt64($FF000000);
end;

procedure RunBreadthAbsoluteOverlay;
var
  Raw, Observed: UInt64;
  Fields: TBreadthWordOverlay absolute Raw;
begin
  Raw := UInt64(OpaqueI($1122334455667788));
  Check((Fields.Start = $88) and (Fields.LengthWord = $6677) and (Fields.Tag = $55) and (Fields.Data = $11223344),
    'breadth-absolute-packed-field-loads');
  BreadthChangeOverlay(Raw, Fields.LengthWord, Word(OpaqueI($D3E5)), Observed);
  Check(Observed = UInt64($1122334455D3E588), 'breadth-absolute-var-store-visible-through-wide-alias');
  Check((Raw = UInt64($11223344AAD3E588)) and (Fields.Tag = $AA), 'breadth-absolute-wide-store-visible-through-byte-field');
  Fields.Data := Cardinal(OpaqueI($960F23AE));
  Check(Raw = UInt64($960F23AEAAD3E588), 'breadth-absolute-high-dword-store');
  Mix(Raw);
end;

procedure RunBreadthBoundaryForms;
begin
  RunBreadthCheckedExtremeLoops;
  RunBreadthSetSelectorDomain;
  RunBreadthArrayConstructorCleanup;
  RunBreadthAbsoluteOverlay;
end;
