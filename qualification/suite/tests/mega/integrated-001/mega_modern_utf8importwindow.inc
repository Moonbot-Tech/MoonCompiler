{$ifdef BREADTH_HAS_PRODUCT_IO}
{ Decode and re-encode a borrowed byte window into already populated caller buffers. }

procedure RunBreadthUtf8ImportWindow;
const
  Frame: array[0..11] of Byte = ($FF, $FE, $CE, $BB, $F0, $9F, $9A, $80, 0, $71, $FF, $C0);
  Units: array[0..4] of Word = ($03BB, $D83D, $DE80, 0, $0071);
var
  Source, Output: TBytes;
  Chars: TCharArray;
  Count, I, Start: Integer;
begin
  SetLength(Source, SizeOf(Frame));
  Move(Frame, Source[0], SizeOf(Frame));
  SetLength(Chars, 9);
  for I := 0 to High(Chars) do
    Chars[I] := #$ACDC;
  Start := Integer(OpaqueI(2));
  Count := TEncoding.UTF8.GetChars(Source, Start, 8, Chars, Start);
  Check((Count = 5) and (TEncoding.UTF8.GetCharCount(Source, Start, 8) = 5)
    and CompareMem(@Chars[2], @Units[0], SizeOf(Units)), 'breadth-utf8-import-window-writes-exact-utf16-units-at-offset');
  Check((Chars[0] = #$ACDC) and (Chars[1] = #$ACDC) and (Chars[7] = #$ACDC) and (Chars[8] = #$ACDC),
    'breadth-utf8-import-window-keeps-neighboring-char-buffer-units');
  SetLength(Output, 10);
  FillChar(Output[0], Length(Output), $A9);
  Count := TEncoding.UTF8.GetBytes(Chars, Start, 5, Output, 1);
  Check((Count = 8) and CompareMem(@Output[1], @Frame[2], 8) and (Output[0] = $A9) and (Output[9] = $A9),
    'breadth-utf8-import-window-encodes-borrowed-characters-into-exact-byte-range');
  Check(CompareMem(Pointer(Source), @Frame[0], SizeOf(Frame)), 'breadth-utf8-import-window-never-mutates-source');
  Mix(UInt64(Count));
end;
{$endif}
