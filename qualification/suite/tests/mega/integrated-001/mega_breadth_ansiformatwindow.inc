{ A legacy printer formats a counted label into a fixed output window. }

procedure RunBreadthAnsiFormatWindow;
const
  Fmt: AnsiString = '%s:%d';
  Text: AnsiString = 'M' + #0 + 'Z';
  Full: array[0..8] of AnsiChar = ('M', #0, 'Z', ':', '-', '4', '2', '0', '0');
var
  Buf: array[0..15] of AnsiChar;
  Count: Cardinal;
begin
  FillChar(Buf, SizeOf(Buf), $EE);
  Count := FormatBuf(Buf[2], Cardinal(OpaqueI(6)), Fmt[1], Length(Fmt), [Text, OpaqueI(-4200)]);
  Check((Count = 6) and CompareMem(@Buf[2], @Full[0], 6), 'breadth-format-window-truncates-counted-label-and-number-to-limit');
  Check((Buf[0] = #$EE) and (Buf[1] = #$EE) and (Buf[8] = #$EE),
    'breadth-format-window-preserves-prefix-and-first-byte-after-output');
  Count := FormatBuf(Buf[2], Length(Buf) - 3, Fmt[1], Length(Fmt), [Text, OpaqueI(-4200)]);
  Check((Count = SizeOf(Full)) and CompareMem(@Buf[2], @Full[0], SizeOf(Full)) and (Buf[11] = #$EE),
    'breadth-format-window-retry-returns-actual-size-and-complete-text');
  Mix(UInt64(Count));
end;
