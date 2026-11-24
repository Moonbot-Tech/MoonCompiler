{ The C runtime calls a Pascal comparator over fixed-width packed elements. }

type
  TBreadthCCompare = function(Left, Right: Pointer): Integer; cdecl;
  PBreadthSortRow = ^TBreadthSortRow;
  TBreadthSortRow = packed record
    Kind: Byte;
    Ticket: Int64;
    Offset: SmallInt;
  end;

{$ifdef MSWINDOWS}
procedure BreadthCQSort(Data: Pointer; Count, ElementSize: NativeUInt; Compare: TBreadthCCompare);
  cdecl; external 'msvcrt.dll' name 'qsort';
function BreadthCBSearch(Key, Data: Pointer; Count, ElementSize: NativeUInt; Compare: TBreadthCCompare): Pointer;
  cdecl; external 'msvcrt.dll' name 'bsearch';
{$else}
procedure BreadthCQSort(Data: Pointer; Count, ElementSize: NativeUInt; Compare: TBreadthCCompare);
  cdecl; external 'c' name 'qsort';
function BreadthCBSearch(Key, Data: Pointer; Count, ElementSize: NativeUInt; Compare: TBreadthCCompare): Pointer;
  cdecl; external 'c' name 'bsearch';
{$endif}

var
  BreadthCComparisons: Integer;

function BreadthCompareRows(Left, Right: Pointer): Integer; cdecl;
var
  L, R: PBreadthSortRow;
begin
  Inc(BreadthCComparisons);
  L := PBreadthSortRow(Left);
  R := PBreadthSortRow(Right);
  If L^.Ticket < R^.Ticket then
    Exit(-1);
  If L^.Ticket > R^.Ticket then
    Exit(1);
  Result := Integer(L^.Offset) - Integer(R^.Offset);
end;

procedure RunBreadthCCallbacks;
const
  Tickets: array[0..4] of Int64 = (73014444049, -64424509423, 17, -64424509423, 73014444049);
  Offsets: array[0..4] of SmallInt = (32767, 19, 43, -32768, -37);
  Order: array[0..4] of Integer = (3, 1, 2, 4, 0);
var
  Rows: array[0..4] of TBreadthSortRow;
  Lookup: TBreadthSortRow;
  I, Source: Integer;
  Found: PBreadthSortRow;
begin
  for I := Low(Rows) to High(Rows) do begin
    Rows[I].Kind := Byte($E0 + I);
    Rows[I].Ticket := OpaqueI(Tickets[I]);
    Rows[I].Offset := SmallInt(OpaqueI(Offsets[I]));
  end;
  BreadthCComparisons := 0;
  BreadthCQSort(@Rows[0], Length(Rows), SizeOf(TBreadthSortRow), BreadthCompareRows);
  Check(BreadthCComparisons > 0, 'breadth-c-sort-calls-pascal-comparator');
  for I := Low(Rows) to High(Rows) do begin
    Source := Order[I];
    Check((Rows[I].Kind = $E0 + Source) and (Rows[I].Ticket = Tickets[Source]) and (Rows[I].Offset = Offsets[Source]),
      'breadth-c-sort-preserves-packed-payload-and-full-key');
    Mix(UInt64(Rows[I].Kind));
  end;
  Lookup.Kind := $77;
  Lookup.Ticket := OpaqueI(-64424509423);
  Lookup.Offset := SmallInt(OpaqueI(19));
  Found := PBreadthSortRow(BreadthCBSearch(@Lookup, @Rows[0], Length(Rows), SizeOf(TBreadthSortRow), BreadthCompareRows));
  Check(Found = @Rows[1], 'breadth-c-search-returns-exact-element-address');
  Lookup.Offset := SmallInt(OpaqueI(20));
  Found := PBreadthSortRow(BreadthCBSearch(@Lookup, @Rows[0], Length(Rows), SizeOf(TBreadthSortRow), BreadthCompareRows));
  Check(Found = nil, 'breadth-c-search-missing-pair-returns-nil');
end;
