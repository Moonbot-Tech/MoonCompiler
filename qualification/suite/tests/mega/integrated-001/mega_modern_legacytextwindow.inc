{$ifdef BREADTH_HAS_PRODUCT_IO}
{ Convert only the Cyrillic body of a legacy packet, keeping binary framing out of the text. }

procedure RunBreadthLegacyTextWindow;
const
  Legacy: array[0..11] of Byte = ($A3, $FF, $D1, $F7, $B8, $F2, 0, $B9, $31, $37, $EF, 2);
  ExpectedUtf8: array[0..13] of Byte = ($D0, $A1, $D1, $87, $D1, $91, $D1, $82, 0, $E2, $84, $96, $31, $37);
  ExpectedText: UnicodeString = #$0421#$0447#$0451#$0442#0#$2116'17';
var
  Enc: TEncoding;
  Packet, Utf, Restored: TBytes;
begin
  SetLength(Packet, SizeOf(Legacy));
  Move(Legacy, Packet[0], SizeOf(Legacy));
  Enc := TEncoding.GetEncoding(1251);
  try
    Utf := TEncoding.Convert(Enc, TEncoding.UTF8, Packet, Integer(OpaqueI(2)), 8);
    Check((Length(Utf) = SizeOf(ExpectedUtf8)) and CompareMem(Pointer(Utf), @ExpectedUtf8[0], SizeOf(ExpectedUtf8)),
      'breadth-legacy-text-window-transcodes-only-cyrillic-payload-at-offset');
    Check(TEncoding.UTF8.GetString(Utf) = ExpectedText, 'breadth-legacy-text-window-keeps-cyrillic-nul-and-number-sign');
    Restored := TEncoding.Convert(TEncoding.UTF8, Enc, Utf);
    Check((Length(Restored) = 8) and CompareMem(Pointer(Restored), @Legacy[2], 8),
      'breadth-legacy-text-window-writes-original-windows-codepage-bytes');
    Check(CompareMem(Pointer(Packet), @Legacy[0], SizeOf(Legacy)), 'breadth-legacy-text-window-leaves-source-frame-intact');
    Mix(UInt64(Length(Utf) * 100 + Length(Restored)));
  finally
    Enc.Free;
  end;
end;
{$endif}
