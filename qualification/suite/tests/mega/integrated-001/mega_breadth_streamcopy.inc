{ CopyFrom with an explicit count and CopyFrom with zero have different source-position rules. }

procedure RunBreadthStreamCopy;
const
  Wire: array[0..7] of Byte = ($D1, $37, 0, $90, $A8, $BD, $06, $C4);
  Initial: array[0..5] of Byte = ($14, $25, $36, $47, $58, $69);
  Expected: array[0..13] of Byte = ($14, $25, 0, $90, $A8, $69, $D1, $37, 0, $90, $A8, $BD, $06, $C4);
var
  Source: TStream;
  Sink: TMemoryStream;
  Copied: Int64;
begin
  Source := TMemoryStream.Create;
  try
    Sink := TMemoryStream.Create;
    try
      Source.WriteBuffer(Wire[0], SizeOf(Wire));
      Sink.WriteBuffer(Initial[0], SizeOf(Initial));
      Source.Position := OpaqueI(2);
      Sink.Position := OpaqueI(2);
      Copied := Sink.CopyFrom(Source, OpaqueI(3));
      Check((Copied = 3) and (Source.Position = 5) and (Sink.Position = 5) and (Sink.Size = 6),
        'breadth-stream-copy-explicit-count-starts-at-current-offsets');

      Sink.Position := Sink.Size;
      Copied := Sink.CopyFrom(Source, OpaqueI(0));
      Check((Copied = 8) and (Source.Position = 8) and (Sink.Position = 14),
        'breadth-stream-copy-zero-rewinds-source-and-appends-entire-content');
      Check((Sink.Size = SizeOf(Expected)) and CompareMem(Sink.Memory, @Expected[0], SizeOf(Expected)),
        'breadth-stream-copy-overwritten-range-and-appended-bytes');
      Mix(UInt64(Copied * 16 + Sink.Size));
    finally
      Sink.Free;
    end;
  finally
    Source.Free;
  end;
end;
