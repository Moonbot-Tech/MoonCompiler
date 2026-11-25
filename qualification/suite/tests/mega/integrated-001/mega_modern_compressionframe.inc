{$ifdef BREADTH_HAS_PRODUCT_IO}
{ The raw DEFLATE member is zlib.compress(b'alpha\0\xce\xbb' * 37, wbits=-15). }

procedure RunBreadthInflateFrame;
const
  Prefix: array[0..1] of Byte = ($E1, 0);
  Deflated: array[0..14] of Byte = ($4B, $CC, $29, $C8, $48, $64, $38, $B7, $3B, $71, $94, $C6, $4B, $03, 0);
  Trailer: array[0..2] of Byte = ($F4, $91, $0D);
  Pattern: array[0..7] of Byte = ($61, $6C, $70, $68, $61, 0, $CE, $BB);
var
  Wire: TMemoryStream;
  Reader: TZDecompressionStream;
  Data: array[0..295] of Byte;
  Slice: array[0..6] of Byte;
  Remaining: array[0..2] of Byte;
  I: Integer;
  Match: Boolean;
begin
  Wire := TMemoryStream.Create;
  try
    Wire.WriteBuffer(Prefix, SizeOf(Prefix));
    Wire.WriteBuffer(Deflated, SizeOf(Deflated));
    Wire.WriteBuffer(Trailer, SizeOf(Trailer));
    Wire.Position := OpaqueI(SizeOf(Prefix));
    Reader := TZDecompressionStream.Create(Wire, -15);
    try
      Reader.ReadBuffer(Data[0], 147);
      Reader.ReadBuffer(Data[147], SizeOf(Data) - 147);
      Match := True;
      for I := Low(Data) to High(Data) do
        Match := Match and (Data[I] = Pattern[I and 7]);
      Check(Match and (Reader.Position = SizeOf(Data)), 'breadth-inflate-frame-decodes-independent-golden-member');
      Reader.Position := OpaqueI(11);
      Reader.ReadBuffer(Slice, SizeOf(Slice));
      Match := True;
      for I := Low(Slice) to High(Slice) do
        Match := Match and (Slice[I] = Pattern[(11 + I) and 7]);
      Check(Match and (Reader.Position = 18), 'breadth-inflate-frame-back-seek-restarts-from-original-source-offset');
      Reader.Seek(0, soEnd);
      Check(Reader.Position = SizeOf(Data), 'breadth-inflate-frame-seek-end-counts-uncompressed-bytes');
    finally
      Reader.Free;
    end;
    Check(Wire.Position = SizeOf(Prefix) + SizeOf(Deflated), 'breadth-inflate-frame-leaves-source-at-first-trailer-byte');
    Wire.ReadBuffer(Remaining, SizeOf(Remaining));
    Check(CompareMem(@Remaining[0], @Trailer[0], SizeOf(Trailer)), 'breadth-inflate-frame-keeps-following-wire-field-available');
    Mix(UInt64(Wire.Position * 17 + Slice[0]));
  finally
    Wire.Free;
  end;
end;

procedure RunBreadthDeflateFrame;
const
  Prefix: array[0..2] of Byte = ($DE, $AD, $BE);
  MessageBytes: array[0..8] of Byte = (0, $91, $BB, 17, $CC, $FC, $E1, 0, $FF);
  { One final stored block, little-endian LEN=9 and one's-complement NLEN. }
  Expected: array[0..16] of Byte = ($DE, $AD, $BE, 1, 9, 0, $F6, $FF, 0, $91, $BB, 17, $CC, $FC, $E1, 0, $FF);
var
  Wire: TMemoryStream;
  Writer: TZCompressionStream;
begin
  Wire := TMemoryStream.Create;
  try
    Wire.WriteBuffer(Prefix, SizeOf(Prefix));
    Writer := TZCompressionStream.Create(Wire, zcNone, -15);
    try
      Writer.WriteBuffer(MessageBytes[0], 4);
      Wire.Position := 0;
      Writer.WriteBuffer(MessageBytes[4], SizeOf(MessageBytes) - 4);
      Check((Writer.Position = SizeOf(MessageBytes)) and (Writer.Size = SizeOf(MessageBytes)),
        'breadth-deflate-frame-position-and-size-report-uncompressed-input');
    finally
      Writer.Free;
    end;
    Check((Wire.Size = SizeOf(Expected)) and (Wire.Position = SizeOf(Expected))
      and CompareMem(Wire.Memory, @Expected[0], SizeOf(Expected)),
      'breadth-deflate-frame-writes-final-stored-block-at-original-offset');
    Mix(UInt64(Wire.Position));
  finally
    Wire.Free;
  end;
end;
{$endif}
