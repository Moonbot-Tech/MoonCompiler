program array_list_span_semantic;

{ C-001/R-001/R-002: proven spans before any pointer or index access in
  TArray.Copy/Sort/BinarySearch and TList.Exchange/Move.
  DCC64-measured boundaries: Move(i,i) with an invalid i is a no-op; Move
  checks source before destination (the reported index of a both-invalid
  pair); zero-count Sort/BinarySearch/Copy at Index=Length are valid;
  BinarySearch returns the insertion point for a zero count and an empty
  array. Deliberately STRICTER than DCC64 (measured defects, not canvas):
  Exchange checks both indices (DCC corrupts the heap), Copy rejects a
  negative source index (DCC's unsigned Index+Count sum wraps and reads
  out of bounds). }

{$mode delphiunicode}{$H+}
{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}cthreads,cwstring,{$endif UNIX}
  SysUtils, Generics.Collections, Generics.Defaults;

var
  Fails: Integer = 0;
  Compares: Integer = 0;

procedure Check(const Name: AnsiString; Cond: Boolean);
begin
  if not Cond then
  begin
    WriteLn('FAIL ', Name);
    Inc(Fails);
  end;
end;

function CountingCompare(const A, B: Integer): Integer;
begin
  Inc(Compares);
  Result := A - B;
end;

type
  TIntList = TList<Integer>;

function ListIs(L: TIntList; const V: array of Integer): Boolean;
var
  I: Integer;
begin
  if L.Count <> Length(V) then
    Exit(False);
  for I := 0 to High(V) do
    if L[I] <> V[I] then
      Exit(False);
  Result := True;
end;

procedure ExpectRange(const Name: AnsiString; Proc: TProc; const WantIndexMark: AnsiString);
begin
  try
    Proc();
    Check(Name + '-raised', False);
  except
    on E: EArgumentOutOfRangeException do
      Check(Name + '-msg', (WantIndexMark = '') or (Pos(WantIndexMark, AnsiString(E.Message)) > 0));
    on E: Exception do
    begin
      WriteLn('  got ', E.ClassName, ' "', E.Message, '"');
      Check(Name + '-class', False);
    end;
  end;
end;

var
  L: TIntList;
  A, B, E: TArray<Integer>;
  Cmp: IComparer<Integer>;
  FoundIdx: SizeInt;
  SR: TBinarySearchResult;
  SL: TSortedList<Integer>;
  I: Integer;
begin
  Cmp := TComparer<Integer>.Construct(CountingCompare);

  L := TIntList.Create;
  try
    L.AddRange([10, 20, 30]);

    { Move(i,i) with invalid i: measured no-op }
    L.Move(5, 5);
    Check('move-same-invalid-noop', ListIs(L, [10, 20, 30]));

    { source checked first: the both-invalid pair reports the source }
    ExpectRange('move-src-invalid', procedure begin L.Move(5, 1); end, '(5)');
    Check('move-src-state', ListIs(L, [10, 20, 30]));
    ExpectRange('move-dst-invalid', procedure begin L.Move(1, 5); end, '(5)');
    ExpectRange('move-both-order', procedure begin L.Move(5, 7); end, '(5)');
    ExpectRange('move-both-order-rev', procedure begin L.Move(7, 5); end, '(7)');
    ExpectRange('move-src-neg', procedure begin L.Move(-1, 1); end, '(-1)');
    Check('move-state-kept', ListIs(L, [10, 20, 30]));

    { valid moves still reorder }
    L.Move(0, 2);
    Check('move-valid', ListIs(L, [20, 30, 10]));
    L.Move(2, 0);
    Check('move-valid-back', ListIs(L, [10, 20, 30]));

    { Exchange: both indices proven, first index first }
    ExpectRange('exch-1-invalid', procedure begin L.Exchange(5, 1); end, '(5)');
    ExpectRange('exch-2-invalid', procedure begin L.Exchange(1, 5); end, '(5)');
    ExpectRange('exch-order', procedure begin L.Exchange(7, 5); end, '(7)');
    ExpectRange('exch-neg', procedure begin L.Exchange(-1, 1); end, '(-1)');
    Check('exch-state-kept', ListIs(L, [10, 20, 30]));
    L.Exchange(0, 2);
    Check('exch-valid', ListIs(L, [30, 20, 10]));
  finally
    L.Free;
  end;

  SetLength(A, 5);
  SetLength(B, 5);
  for I := 0 to 4 do
  begin
    A[I] := 1 + 2 * I; { 1,3,5,7,9 }
    B[I] := 0;
  end;

  { Copy: the negative-index wrap is rejected (stricter than DCC) }
  ExpectRange('copy-src-neg', procedure begin TArray.Copy<Integer>(A, B, -1, 0, 2); end, '');
  ExpectRange('copy-count-neg', procedure begin TArray.Copy<Integer>(A, B, 0, 0, -1); end, '');
  ExpectRange('copy-src-past', procedure begin TArray.Copy<Integer>(A, B, 4, 0, 2); end, '');
  ExpectRange('copy-dst-past', procedure begin TArray.Copy<Integer>(A, B, 0, 4, 2); end, '');
  Check('copy-error-state', (B[0] = 0) and (B[4] = 0));
  TArray.Copy<Integer>(A, B, 5, 5, 0);
  Check('copy-zero-at-len', True);
  TArray.Copy<Integer>(A, B, 1, 2, 3);
  Check('copy-valid', (B[2] = 3) and (B[3] = 5) and (B[4] = 7) and (B[0] = 0));

  { Sort: validate before the trivial-count exit; no comparer on <=1 }
  ExpectRange('sort-idx-neg', procedure begin TArray.Sort<Integer>(A, Cmp, -1, 2); end, '');
  ExpectRange('sort-past', procedure begin TArray.Sort<Integer>(A, Cmp, 4, 2); end, '');
  ExpectRange('sort-count-neg', procedure begin TArray.Sort<Integer>(A, Cmp, 1, -1); end, '');
  Compares := 0;
  TArray.Sort<Integer>(A, Cmp, 5, 0);
  TArray.Sort<Integer>(A, Cmp, 2, 1);
  Check('sort-trivial-no-compare', Compares = 0);
  A[0] := 9; A[1] := 7; A[2] := 5; A[3] := 3; A[4] := 1;
  TArray.Sort<Integer>(A, Cmp, 1, 3);
  Check('sort-ranged-valid', (A[0] = 9) and (A[1] = 3) and (A[2] = 5) and (A[3] = 7) and (A[4] = 1));

  { BinarySearch: proven span, SizeInt width, zero count = insertion
    point without a comparer call (DCC-measured) }
  A[0] := 1; A[1] := 3; A[2] := 5; A[3] := 7; A[4] := 9;
  ExpectRange('bs-idx-neg', procedure begin TArray.BinarySearch<Integer>(A, 5, FoundIdx, Cmp, -1, 3); end, '');
  ExpectRange('bs-past', procedure begin TArray.BinarySearch<Integer>(A, 5, FoundIdx, Cmp, 4, 2); end, '');
  ExpectRange('bs-count-neg', procedure begin TArray.BinarySearch<Integer>(A, 5, FoundIdx, Cmp, 1, -1); end, '');

  Compares := 0;
  Check('bs-zero-mid', not TArray.BinarySearch<Integer>(A, 5, FoundIdx, Cmp, 2, 0));
  Check('bs-zero-mid-idx', FoundIdx = 2);
  Check('bs-zero-at-len', not TArray.BinarySearch<Integer>(A, 5, FoundIdx, Cmp, 5, 0));
  Check('bs-zero-at-len-idx', FoundIdx = 5);
  Check('bs-zero-no-compare', Compares = 0);

  SetLength(E, 0);
  Check('bs-empty', not TArray.BinarySearch<Integer>(E, 5, FoundIdx, Cmp));
  Check('bs-empty-insert-at-0', FoundIdx = 0);

  Check('bs-found', TArray.BinarySearch<Integer>(A, 7, FoundIdx, Cmp) and (FoundIdx = 3));
  Check('bs-notfound-insert', (not TArray.BinarySearch<Integer>(A, 4, FoundIdx, Cmp)) and (FoundIdx = 2));
  Check('bs-ranged-found', TArray.BinarySearch<Integer>(A, 5, FoundIdx, Cmp, 1, 3) and (FoundIdx = 2));

  { the TBinarySearchResult overload (FPC extension) keeps the aligned
    insertion-point candidate on a zero count }
  Check('bsr-zero', not TArrayHelper<Integer>.BinarySearch(A, 5, SR, Cmp, 2, 0));
  Check('bsr-zero-candidate', (SR.FoundIndex = -1) and (SR.CandidateIndex = 2));
  ExpectRange('bsr-invalid', procedure begin TArrayHelper<Integer>.BinarySearch(A, 5, SR, Cmp, 4, 2); end, '');
  Check('bsr-found', TArrayHelper<Integer>.BinarySearch(A, 9, SR, Cmp, 0, 5) and (SR.FoundIndex = 4));

  { DCC64 returns the lower bound, not an arbitrary equal slot. This matters
    to callers which continue a range scan from FoundIdx. }
  SetLength(A, 8);
  A[0] := 0; A[1] := 0; A[2] := 1; A[3] := 1;
  A[4] := 1; A[5] := 2; A[6] := 3; A[7] := 3;
  Check('bs-first-equal-zero',
    TArray.BinarySearch<Integer>(A, 0, FoundIdx, Cmp) and (FoundIdx = 0));
  Check('bs-first-equal-one',
    TArray.BinarySearch<Integer>(A, 1, FoundIdx, Cmp) and (FoundIdx = 2));
  Check('bs-first-equal-ranged',
    TArray.BinarySearch<Integer>(A, 1, FoundIdx, Cmp, 2, 3) and
      (FoundIdx = 2));
  Check('bsr-first-equal',
    TArrayHelper<Integer>.BinarySearch(A, 1, SR, Cmp, 0, Length(A)) and
      (SR.FoundIndex = 2) and (SR.CandidateIndex = 2));

  { TSortedList consumes the SearchResult fields: the old -1 sentinel made
    the empty-list insertion point 0 by accident (-1+1); under the
    insertion-point contract the first Add must land at 0 with the value
    visible (the broken form wrote FItems[1] and exposed garbage) }
  SL := TSortedList<Integer>.Create;
  try
    Check('sorted-first-add', (SL.Add(42) = 0) and (SL[0] = 42));
    SL.Add(10);
    SL.Add(77);
    Check('sorted-order', (SL.Count = 3) and (SL[0] = 10) and (SL[1] = 42) and (SL[2] = 77));
  finally
    SL.Free;
  end;

  if Fails <> 0 then
    Halt(1);
  WriteLn('ARRAY_LIST_SPAN_OK');
end.
