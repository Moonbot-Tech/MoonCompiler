{ Sort and search only a slice of records with unsigned keys and managed payloads. }

type
  TBreadthSliceSortRow = record
    Key: UInt64;
    Text: UnicodeString;
  end;

  TBreadthSortComparer = class(TComparer<TBreadthSliceSortRow>)
    function Compare({$ifdef BREADTH_LEGACY_COMPARER}constref{$else}const{$endif} Left, Right: TBreadthSliceSortRow): Integer; override;
  end;

function TBreadthSortComparer.Compare(
  {$ifdef BREADTH_LEGACY_COMPARER}constref{$else}const{$endif} Left, Right: TBreadthSliceSortRow): Integer;
begin
  Result := Ord(Left.Key > Right.Key) - Ord(Left.Key < Right.Key);
end;

procedure RunBreadthGenericSortSlice;
const
  HighKey = UInt64($8000000000000005);
  MaxKey = UInt64($FFFFFFFFFFFFFFFC);
{$ifdef BREADTH_LEGACY_COMPARER}
type
  TSliceAlgorithms = TArrayHelper<TBreadthSliceSortRow>;
{$endif}
var
  Rows: array[0..4] of TBreadthSliceSortRow;
  Query: TBreadthSliceSortRow;
  Comparer: IComparer<TBreadthSliceSortRow>;
  Index: {$ifdef BREADTH_LEGACY_COMPARER}NativeInt{$else}Integer{$endif};

  function Search: Boolean;
  begin
    {$ifdef BREADTH_LEGACY_COMPARER}
    Result := TSliceAlgorithms.BinarySearch(Rows, Query, Index, Comparer, 1, 3);
    {$else}
    Result := TArray.BinarySearch<TBreadthSliceSortRow>(Rows, Query, Index, Comparer, 1, 3);
    {$endif}
  end;
begin
  Rows[0].Key := HighKey;
  Rows[0].Text := 'before';
  Rows[1].Key := MaxKey;
  Rows[1].Text := 'serial-' + IntToStr(OpaqueI(7120)) + #0'!';
  Rows[2].Key := HighKey;
  Rows[2].Text := 'middle';
  Rows[3].Key := 9;
  Rows[3].Text := 'first';
  Rows[4].Key := 9;
  Rows[4].Text := 'after';
  Comparer := TBreadthSortComparer.Create;
  {$ifdef BREADTH_LEGACY_COMPARER}
  TSliceAlgorithms.Sort(Rows, Comparer, 1, 3);
  {$else}
  TArray.Sort<TBreadthSliceSortRow>(Rows, Comparer, 1, 3);
  {$endif}
  Check((Rows[0].Text = 'before') and (Rows[4].Text = 'after'), 'breadth-generic-sort-does-not-touch-outside-slice');
  Check((Rows[1].Key = 9) and (Rows[1].Text = 'first') and (Rows[2].Key = HighKey) and (Rows[2].Text = 'middle')
    and (Rows[3].Key = MaxKey) and (Rows[3].Text = 'serial-7120'#0'!'), 'breadth-generic-sort-keeps-managed-values-with-unsigned-keys');

  Query.Key := HighKey;
  Query.Text := 'different text';
  Check(Search and (Index = 2),
    'breadth-generic-search-uses-comparer-and-reports-index-in-original-array');
  Inc(Query.Key);
  Check((not Search) {$ifndef BREADTH_LEGACY_COMPARER}and (Index = 3){$endif},
    'breadth-generic-search-reports-insertion-index-inside-slice');
  Query.Key := High(UInt64);
  Check((not Search) {$ifndef BREADTH_LEGACY_COMPARER}and (Index = 4){$endif},
    'breadth-generic-search-reports-insertion-index-at-slice-end');
end;
