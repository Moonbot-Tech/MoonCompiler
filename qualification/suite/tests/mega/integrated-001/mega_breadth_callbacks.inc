{ Overload calls and RTL callbacks retain their side effects under optimization. }

type
  TBreadthComparable = record
    Key: Int64;
    LabelText: AnsiString;
    class operator Equal(const Left, Right: TBreadthComparable): Boolean;
    class operator NotEqual(const Left, Right: TBreadthComparable): Boolean;
  end;

var
  BreadthEqualCalls, BreadthNotEqualCalls: Integer;

class operator TBreadthComparable.Equal(const Left, Right: TBreadthComparable): Boolean;
begin
  Inc(BreadthEqualCalls);
  Result := Left.Key = Right.Key;
end;

class operator TBreadthComparable.NotEqual(const Left, Right: TBreadthComparable): Boolean;
begin
  Inc(BreadthNotEqualCalls);
  Result := Left.Key <> Right.Key;
end;

{$B-}
function BreadthLazyCompare(const A, B, C: TBreadthComparable): Boolean;
begin
  Result := (A = B) or (B <> C);
end;

{$B+}
function BreadthEagerCompare(const A, B, C: TBreadthComparable): Boolean;
begin
  Result := (A = B) or (B <> C);
end;
{$B-}

procedure RunBreadthComparisonOverloads;
var
  A, B, C: TBreadthComparable;
begin
  A.Key := OpaqueI(72000000059);
  B.Key := OpaqueI(72000000059);
  C.Key := OpaqueI(-85000000071);
  A.LabelText := 'left';
  B.LabelText := 'right';
  C.LabelText := 'alternate';
  BreadthEqualCalls := 0;
  BreadthNotEqualCalls := 0;
  Check(BreadthLazyCompare(A, B, C), 'breadth-operator-overload-lazy-equality');
  Check((BreadthEqualCalls = 1) and (BreadthNotEqualCalls = 0), 'breadth-operator-overload-lazy-call-counts');
  Check(BreadthEagerCompare(A, B, C), 'breadth-operator-overload-eager-equality');
  Check((BreadthEqualCalls = 2) and (BreadthNotEqualCalls = 1), 'breadth-operator-overload-eager-call-counts');
  Check(not BreadthLazyCompare(C, A, B), 'breadth-operator-overload-both-false');
  Check((BreadthEqualCalls = 3) and (BreadthNotEqualCalls = 2), 'breadth-operator-overload-lazy-rhs-evaluated');
  Check(A = A, 'breadth-operator-overload-same-variable-equality');
  Check(BreadthEqualCalls = 4, 'breadth-operator-overload-same-variable-is-still-a-call');
  Mix(UInt64(BreadthEqualCalls * 10 + BreadthNotEqualCalls));
end;

type
  TBreadthSortOwner = class(TBreadthSortValue)
    class var Destroyed: Integer;
    destructor Destroy; override;
  end;

var
  BreadthSortComparisons: Integer;

destructor TBreadthSortOwner.Destroy;
begin
  Inc(Destroyed);
  inherited;
end;

function BreadthAbortingCompare(List: TStringList; A, B: Integer): Integer;
begin
  Inc(BreadthSortComparisons);
  If BreadthSortComparisons = 4 then
    raise EAbort.Create('sort comparator');
  Result := BreadthCompareStrings(List, A, B);
end;

procedure RunBreadthSortUnwind;
var
  List: TStringList;
  Item: TBreadthSortOwner;
  I, Number: Integer;
  Seen: set of 0..7;
  Caught: Boolean;
begin
  TBreadthSortOwner.Destroyed := 0;
  List := TStringList.Create;
  try
    List.OwnsObjects := True;
    for I := 7 downto 0 do begin
      Number := List.Add(IntToStr(I));
      Item := TBreadthSortOwner.Create;
      List.Objects[Number] := Item;
      Item.Key := OpaqueI(50000000007) * I;
      Item.Tie := I;
    end;
    BreadthSortComparisons := 0;
    Caught := False;
    try
      List.CustomSort(BreadthAbortingCompare);
    except
      on EAbort do Caught := True;
    end;
    Check(Caught and (BreadthSortComparisons = 4), 'breadth-sort-callback-exception-propagates');
    Check((List.Count = 8) and (TBreadthSortOwner.Destroyed = 0), 'breadth-sort-exception-retains-count-and-owners');
    Seen := [];
    for I := 0 to List.Count - 1 do begin
      Number := StrToInt(List[I]);
      Check((Number >= 0) and (Number <= 7) and (TBreadthSortOwner(List.Objects[I]).Tie = Number),
        'breadth-sort-exception-preserves-string-object-pair');
      If (Number >= 0) and (Number <= 7) then
        Include(Seen, Number);
    end;
    Check(Seen = [0..7], 'breadth-sort-exception-retains-permutation');
    List.CustomSort(BreadthCompareStrings);
    for I := 0 to List.Count - 1 do
      Check((List[I] = IntToStr(I)) and (TBreadthSortOwner(List.Objects[I]).Tie = I), 'breadth-sort-can-resume-after-exception');
  finally
    List.Free;
  end;
  Check(TBreadthSortOwner.Destroyed = 8, 'breadth-sort-releases-all-owners');
  Mix(UInt64(TBreadthSortOwner.Destroyed));
end;

procedure RunBreadthCallbackForms;
begin
  RunBreadthComparisonOverloads;
  RunBreadthSortUnwind;
end;
