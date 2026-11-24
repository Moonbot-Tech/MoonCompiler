{ Code-page tags belong to a shared string buffer just as its payload does. }

procedure RunBreadthCodePageDetach;
const
  Utf8Bytes: array[0..5] of Byte = ($C3, $A9, 0, $E2, $82, $AC);
  WesternBytes: array[0..2] of Byte = ($E9, 0, $80);
var
  Wire, Relabelled, Converted: RawByteString;
  Text: UnicodeString;
begin
  SetLength(Wire, SizeOf(Utf8Bytes));
  Move(Utf8Bytes[0], Wire[1], SizeOf(Utf8Bytes));
  SetCodePage(Wire, Word(OpaqueI(65001)), False);
  Relabelled := Wire;
  Converted := Wire;
  SetCodePage(Relabelled, Word(OpaqueI(1252)), False);
  Check((StringCodePage(Wire) = 65001) and (StringCodePage(Relabelled) = 1252),
    'breadth-string-codepage-relabel-detaches-shared-header');
  Check((Length(Relabelled) = SizeOf(Utf8Bytes)) and CompareMem(Pointer(Relabelled), @Utf8Bytes[0], SizeOf(Utf8Bytes)),
    'breadth-string-codepage-relabel-keeps-bytes');

  SetCodePage(Converted, Word(OpaqueI(1252)), True);
  Check((StringCodePage(Converted) = 1252) and (Length(Converted) = SizeOf(WesternBytes)),
    'breadth-string-codepage-conversion-sets-new-header');
  If Length(Converted) = SizeOf(WesternBytes) then
    Check(CompareMem(Pointer(Converted), @WesternBytes[0], SizeOf(WesternBytes)), 'breadth-string-codepage-conversion-keeps-nul');
  Text := UnicodeString(Converted);
  Check((Length(Text) = 3) and (Ord(Text[1]) = $E9) and (Text[2] = #0) and (Ord(Text[3]) = $20AC),
    'breadth-string-codepage-unicode-decodes-explicit-tag');

  SetCodePage(Converted, Word(OpaqueI(65001)), True);
  Check((StringCodePage(Converted) = 65001) and (Length(Converted) = SizeOf(Utf8Bytes)),
    'breadth-string-codepage-roundtrip-utf8-header');
  If Length(Converted) = SizeOf(Utf8Bytes) then
    Check(CompareMem(Pointer(Converted), @Utf8Bytes[0], SizeOf(Utf8Bytes)), 'breadth-string-codepage-roundtrip-utf8-bytes');
  Check((StringCodePage(Wire) = 65001) and (Length(Wire) = SizeOf(Utf8Bytes))
    and CompareMem(Pointer(Wire), @Utf8Bytes[0], SizeOf(Utf8Bytes)), 'breadth-string-codepage-original-wire-value-unchanged');
  Mix(UInt64(Length(Text) * 100 + Length(Converted)));
end;
