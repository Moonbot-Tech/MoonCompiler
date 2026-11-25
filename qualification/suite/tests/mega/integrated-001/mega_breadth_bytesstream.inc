{ A stream first shares its byte array, then grows into its own allocation. }

procedure RunBreadthBytesStreamGrowth;
const
  TailAt: Int64 = 4101;
  Header: array[0..3] of Byte = ($91, $AC, 0, $42);
var
  Original, Held: TBytes;
  Stream: TBytesStream;
  ByteValue: Byte;
begin
  Original := [$91, $33, 0, $42];
  Stream := TBytesStream.Create(Original);
  try
    Stream.Position := OpaqueI(1);
    ByteValue := $AC;
    Stream.WriteBuffer(ByteValue, 1);
    Check((Length(Original) = 4) and CompareMem(@Original[0], @Header[0], SizeOf(Header)),
      'breadth-bytes-stream-in-place-write-reaches-original-shared-array');

    Stream.Position := OpaqueI(TailAt);
    ByteValue := $E1;
    Stream.WriteBuffer(ByteValue, 1);
    Check((Stream.Size = TailAt + 1) and (Stream.Position = TailAt + 1)
      and (Length(Original) = 4), 'breadth-bytes-stream-growth-keeps-original-array-size');
    Stream.Position := 0;
    ByteValue := $67;
    Stream.WriteBuffer(ByteValue, 1);
    Held := Stream.Bytes;
    Check((Held[0] = $67) and (Original[0] = $91),
      'breadth-bytes-stream-growth-detaches-later-writes');
    Stream.Seek(-1, soEnd);
    Stream.ReadBuffer(ByteValue, 1);
    Check(ByteValue = $E1, 'breadth-bytes-stream-end-relative-read-finds-written-tail');
  finally
    FreeAndNil(Stream);
  end;
  Check((Length(Held) > TailAt) and (Held[0] = $67) and (Held[1] = $AC) and (Held[2] = 0)
    and (Held[3] = $42) and (Held[TailAt] = $E1), 'breadth-bytes-stream-exposed-buffer-survives-stream-destruction');
  Mix(UInt64(Held[0]) shl 8 or Held[TailAt]);
end;
