{$ifdef BREADTH_HAS_TEXT_STREAMS}
{ A UTF-8 writer preserves a pair at the byte-buffer edge and emits the BOM once. }

procedure RunBreadthBufferedTextWriter;
const
  Bom: array[0..2] of Byte = ($EF, $BB, $BF);
  Tail: array[0..6] of Byte = ($F0, $9F, $99, $82, 0, Ord('Z'), Ord('!'));
var
  Stream: TMemoryStream;
  Writer: TStreamWriter;
  Prefix: array[0..125] of Byte;
  Text: UnicodeString;
begin
  Stream := TMemoryStream.Create;
  try
    Writer := TStreamWriter.Create(Stream, TEncoding.UTF8, 128);
    try
      Writer.AutoFlush := False;
      Text := UnicodeString(StringOfChar('k', Length(Prefix))) + #$D83D#$DE42#0'Z';
      Writer.Write(Text);
      Writer.Flush;
      Check(Stream.Size = 135, 'breadth-text-writer-flushes-bom-and-complete-unicode-buffer');
    finally
      Writer.Free;
    end;

    Writer := TStreamWriter.Create(Stream, TEncoding.UTF8, 128);
    try
      Writer.Write('!');
    finally
      Writer.Free;
    end;
    FillChar(Prefix, SizeOf(Prefix), Ord('k'));
    Check((Stream.Size = 136) and CompareMem(Stream.Memory, @Bom[0], SizeOf(Bom))
      and CompareMem(Pointer(NativeUInt(Stream.Memory) + 3), @Prefix[0], SizeOf(Prefix)),
      'breadth-text-writer-emits-single-bom-and-exact-prefix');
    Check((Stream.Size = 136) and CompareMem(Pointer(NativeUInt(Stream.Memory) + 129), @Tail[0], SizeOf(Tail)),
      'breadth-text-writer-retains-pair-nul-and-appended-byte');
  finally
    Stream.Free;
  end;
end;
{$endif}
