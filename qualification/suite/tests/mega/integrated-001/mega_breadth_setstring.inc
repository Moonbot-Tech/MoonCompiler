{ SetString takes a counted UTF-16 span even when the destination shared its old buffer. }

procedure BreadthReplaceFromSpan(var Dest: UnicodeString; Start, Count: Integer);
var
  Pinned: UnicodeString;
  Raw: PWideChar;
begin
  Pinned := Dest;
  Raw := PWideChar(Pinned);
  Inc(Raw, Start);
  SetString(Dest, Raw, Count);
end;

procedure RunBreadthCountedUnicodeSpan;
const
  OriginalUnits: array[0..5] of Word = ($0041, $221A, 0, $D834, $DD1E, $0042);
  SliceUnits: array[0..3] of Word = ($221A, 0, $D834, $DD1E);
var
  Dest, Original, Saved: UnicodeString;
begin
  SetLength(Dest, Length(OriginalUnits));
  Move(OriginalUnits[0], Dest[1], SizeOf(OriginalUnits));
  Original := Dest;
  BreadthReplaceFromSpan(Dest, Integer(OpaqueI(1)), Integer(OpaqueI(4)));
  Check((Length(Dest) = Length(SliceUnits)) and CompareMem(Pointer(Dest), @SliceUnits[0], SizeOf(SliceUnits)),
    'breadth-setstring-counted-utf16-copy-includes-zero-and-surrogate');
  Check((Length(Original) = Length(OriginalUnits)) and CompareMem(Pointer(Original), @OriginalUnits[0], SizeOf(OriginalUnits)),
    'breadth-setstring-from-shared-buffer-preserves-original');
  BreadthReplaceFromSpan(Dest, Integer(OpaqueI(1)), Integer(OpaqueI(3)));
  Check((Length(Dest) = 3) and CompareMem(Pointer(Dest), @SliceUnits[1], 3 * SizeOf(Word)),
    'breadth-setstring-pins-originally-unique-buffer-before-replacement');
  Saved := Dest;
  SetString(Dest, PWideChar(nil), Integer(OpaqueI(0)));
  Check((Dest = '') and (Length(Saved) = 3) and CompareMem(Pointer(Saved), @SliceUnits[1], 3 * SizeOf(Word)),
    'breadth-setstring-empty-span-releases-only-destination');
  Mix(UInt64(Length(Saved)));
end;
