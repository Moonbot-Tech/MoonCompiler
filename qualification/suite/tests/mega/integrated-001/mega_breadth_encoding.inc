{ An explicit UTF-8 stream stores counted characters through NUL and a surrogate pair. }

procedure RunBreadthEncodingStream;
const
  Wire: array[0..8] of Byte = ($4B, 0, $F0, $9F, $99, $82, $E2, $82, $AC);
  Padded: array[0..12] of Byte = ($FF, $FF, $4B, 0, $F0, $9F, $99, $82, $E2, $82, $AC, $FF, $FF);
var
  Stream: TStringStream;
  Source, Text: UnicodeString;
  Readback: array[0..8] of Byte;
  Buffer: TBytes;
begin
  Source := 'K'#0#$D83D#$DE42#$20AC;
  Stream := TStringStream.Create(Source, TEncoding.UTF8, False);
  try
    Check(Stream.Size = SizeOf(Wire),
      'breadth-encoding-stream-counts-utf8-bytes-across-nul');
    Stream.Position := 0;
    Stream.ReadBuffer(Readback, SizeOf(Readback));
    Check(CompareMem(@Readback[0], @Wire[0], SizeOf(Wire)), 'breadth-encoding-stream-exact-utf8-without-bom');
    Check(Stream.{$ifdef FPC}UnicodeDataString{$else}DataString{$endif} = Source, 'breadth-encoding-stream-decodes-full-text-at-end');
    Check(Stream.Position = SizeOf(Wire), 'breadth-encoding-stream-text-property-keeps-stream-position');
    SetLength(Buffer, SizeOf(Padded));
    Move(Padded[0], Buffer[0], SizeOf(Padded));
    Text := TEncoding.UTF8.GetString(Buffer, 2, SizeOf(Wire));
    Check(Text = Source, 'breadth-encoding-decodes-offset-and-count-with-invalid-neighbors');
  finally
    Stream.Free;
  end;
  Check(TEncoding.UTF8.GetByteCount(Source) = SizeOf(Wire), 'breadth-encoding-stream-does-not-own-global-encoder');
end;
