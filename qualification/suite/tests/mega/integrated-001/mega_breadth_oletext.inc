{ An OleVariant owns the complete UTF-16 value, even past its first zero code unit. }

procedure BreadthRecoverOleText(const Carrier: OleVariant; out Dest: WideString);
begin
  Dest := WideString(Carrier);
end;

procedure RunBreadthOleWideString;
const
  Units: array[0..5] of Word = ($0410, 0, $D834, $DD1E, $03A9, $005A);
var
  Original, Alias, Restored: WideString;
  UnicodeResult: UnicodeString;
  Carrier, Snapshot: OleVariant;
begin
  SetLength(Original, Length(Units));
  Move(Units[0], Original[1], SizeOf(Units));
  Alias := Original;
  Carrier := Original;
  Check(VarType(Carrier) = varOleStr, 'breadth-ole-wide-string-keeps-ole-carrier-tag');
  Snapshot := Carrier;
  Original[Integer(OpaqueI(5))] := WideChar($003F);
  Check((Ord(Original[5]) = $003F) and (Ord(Alias[5]) = $03A9), 'breadth-ole-wide-string-index-write-detaches');
  Carrier := Unassigned;

  Restored := 'old text';
  BreadthRecoverOleText(Snapshot, Restored);
  Snapshot := Unassigned;
  Alias[1] := WideChar($0058);
  Check((Length(Restored) = Length(Units)) and CompareMem(Pointer(Restored), @Units[0], SizeOf(Units)),
    'breadth-ole-wide-string-result-survives-variant-release');
  UnicodeResult := UnicodeString(Restored);
  SetLength(Restored, 2);
  Check((Length(UnicodeResult) = Length(Units)) and CompareMem(Pointer(UnicodeResult), @Units[0], SizeOf(Units)),
    'breadth-ole-wide-string-unicode-copy-retains-zero-and-surrogate');
  Check((Ord(Alias[1]) = $0058) and (Ord(Original[1]) = $0410), 'breadth-ole-wide-string-source-copies-stay-independent');
  Mix(UInt64(Length(UnicodeResult) * 16 + Length(Restored)));
end;
