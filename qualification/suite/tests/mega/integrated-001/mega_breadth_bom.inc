{ BOM detection picks a decoder and returns the byte offset of the counted payload. }

procedure RunBreadthEncodingDetection;
const
  Marked: array[0..9] of Byte = ($FE, $FF, 0, 0, $D8, $3D, $DE, $42, $20, $AC);
  Unmarked: array[0..2] of Byte = ($E2, $82, $AC);
var
  Data: TBytes;
  Detected: TEncoding;
  Offset: Integer;
begin
  SetLength(Data, SizeOf(Marked));
  Move(Marked[0], Data[0], SizeOf(Marked));
  Detected := nil;
  Offset := TEncoding.GetBufferEncoding(Data, Detected, TEncoding.UTF8);
  Check((Offset = 2) and (Detected = TEncoding.BigEndianUnicode), 'breadth-bom-detection-selects-utf16-big-endian');
  If (Offset = 2) and (Detected <> nil) then
    Check(Detected.GetString(Data, Offset, SizeOf(Marked) - Offset) = #0#$D83D#$DE42#$20AC,
      'breadth-bom-detection-offset-decodes-counted-unicode-payload');

  SetLength(Data, SizeOf(Unmarked));
  Move(Unmarked[0], Data[0], SizeOf(Unmarked));
  Detected := nil;
  Offset := TEncoding.GetBufferEncoding(Data, Detected, TEncoding.UTF8);
  Check((Offset = 0) and (Detected = TEncoding.UTF8) and (Detected.GetString(Data) = #$20AC),
    'breadth-bom-detection-uses-explicit-default-for-unmarked-utf8');
end;
