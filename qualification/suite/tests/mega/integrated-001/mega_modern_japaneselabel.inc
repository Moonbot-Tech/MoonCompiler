{$ifdef BREADTH_HAS_PRODUCT_IO}
{ A legacy vendor label contains both full-width and single-byte characters. }

procedure RunBreadthJapaneseLabel;
const
  Expected: UnicodeString = #$8868#$90F7#$FF76'A';
  Encoded: array[0..5] of Byte = ($95, $5C, $8B, $BD, $B6, $41);
var
  Packet, Wire: TBytes;
  Cp932: TEncoding;
  LabelText: UnicodeString;
begin
  Packet := [$11, $22, $95, $5C, $8B, $BD, $B6, $41, 0, $2A];
  Cp932 := TEncoding.GetEncoding(932);
  try
    LabelText := Cp932.GetString(Packet, Integer(OpaqueI(2)), SizeOf(Encoded));
    Check(not Cp932.IsSingleByte and (Cp932.GetCharCount(Packet, 2, SizeOf(Encoded)) = 4),
      'breadth-cp932-label-counts-mixed-one-and-two-byte-characters');
    Check(LabelText = Expected, 'breadth-cp932-label-treats-trailing-backslash-byte-as-part-of-character');
    Wire := Cp932.GetBytes(LabelText);
    Check((Length(Wire) = SizeOf(Encoded)) and CompareMem(Pointer(Wire), @Encoded[0], SizeOf(Encoded)),
      'breadth-cp932-label-rewrites-exact-original-codepage');
    Mix(UInt64(Length(Wire) * 100 + Length(LabelText)));
  finally
    Cp932.Free;
  end;
end;
{$endif}
