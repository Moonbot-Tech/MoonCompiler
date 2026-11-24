{$define BREADTH_HAS_TEXT_STREAMS}
{$ifdef FPC}
  {$if FPC_FULLVERSION < 30301}
    {$undef BREADTH_HAS_TEXT_STREAMS}
  {$endif}
{$endif}

{$ifdef BREADTH_HAS_TEXT_STREAMS}
{ The first UTF-8 sequence straddles two reader buffers before CRLF, LF and EOF. }

procedure RunBreadthBufferedTextReader;
const
  Tail: array[0..10] of Byte = ($F0, $9F, $99, $82, 13, 10, 10, Ord('e'), Ord('n'), Ord('d'), Ord('!'));
var
  Stream: TMemoryStream;
  Reader: TStreamReader;
  Prefix: array[0..126] of AnsiChar;
  Line: UnicodeString;
begin
  FillChar(Prefix, SizeOf(Prefix), Ord('x'));
  Stream := TMemoryStream.Create;
  try
    Stream.WriteBuffer(Prefix[0], SizeOf(Prefix));
    Stream.WriteBuffer(Tail[0], SizeOf(Tail));
    Stream.Position := 0;
    Reader := TStreamReader.Create(Stream, TEncoding.UTF8, False, 128);
    try
      Check((Reader.Peek = Ord('x')) and (Reader.Peek = Ord('x')), 'breadth-text-reader-double-peek-does-not-consume');
      Line := Reader.ReadLine;
      Check(Line = UnicodeString(StringOfChar('x', 127)) + #$D83D#$DE42,
        'breadth-text-reader-retains-utf8-character-across-buffer-edge');
      Check((not Reader.EndOfStream) and (Reader.ReadLine = ''), 'breadth-text-reader-preserves-empty-line-after-crlf');
      Check((Reader.Peek = Ord('e')) and (Reader.ReadLine = 'end!'), 'breadth-text-reader-returns-final-line-without-terminator');
      Check(Reader.EndOfStream and (Reader.Peek = -1) and (Reader.Read = -1), 'breadth-text-reader-repeats-end-of-stream');
    finally
      Reader.Free;
    end;
  finally
    Stream.Free;
  end;
end;
{$endif}
