{$ifdef BREADTH_HAS_PRODUCT_IO}
{ Seek far beyond EOF on a native handle without allocating a large file. }

procedure RunBreadthLargeFilePosition;
const
  FarPosition: Int64 = 4294967321;
  Payload: array[0..7] of Byte = ($A3, 3, 0, $BC, $17, $2D, $42, $E1);
var
  Path: string;
  Stream: TFileStream;
  Position, ObservedSize: Int64;
  Value: Byte;
begin
  Path := TPath.GetTempFileName;
  try
    Stream := TFileStream.Create(Path, fmCreate);
    try
      Stream.WriteBuffer(Payload, SizeOf(Payload));
      Position := Stream.Seek(OpaqueI(FarPosition), soBeginning);
      Check((Position = FarPosition) and (Stream.Position = FarPosition), 'breadth-file-seek-retains-offset-above-four-gigabytes');
      ObservedSize := Stream.Size;
      Check((ObservedSize = SizeOf(Payload)) and (Stream.Position = FarPosition),
        'breadth-file-size-query-keeps-wide-position-and-tiny-length');
      Check(Stream.Read(Value, SizeOf(Value)) = 0, 'breadth-file-read-far-past-end-returns-eof');
      Position := Stream.Seek(OpaqueI(-19), soCurrent);
      Check((Position = FarPosition - 19) and (Stream.Position = Position),
        'breadth-file-relative-seek-keeps-high-bits-after-negative-step');
      Stream.Seek(OpaqueI(-2), soEnd);
      Stream.ReadBuffer(Value, SizeOf(Value));
      Check((Value = $42) and (Stream.Position = 7), 'breadth-file-end-relative-seek-still-reads-original-tail');
      Mix(UInt64(Position) xor UInt64(Stream.Position));
    finally
      FreeAndNil(Stream);
    end;
  finally
    DeleteFile(Path);
  end;
end;
{$endif}
