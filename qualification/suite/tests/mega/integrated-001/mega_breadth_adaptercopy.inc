{ IStream.CopyTo crosses an internal block boundary and updates both 64-bit out counters. }

procedure RunBreadthAdapterCopy;
const
  Count = 1025;
var
  Source, Destination: TMemoryStream;
  Reader, Writer: IStream;
  Input: array[0..Count + 3] of Byte;
  Header: array[0..1] of Byte;
  ReadCount, WriteCount: UInt64;
  Status: HResult;
  I: Integer;
begin
  Source := TMemoryStream.Create;
  try
    Destination := TMemoryStream.Create;
    try
      for I := Low(Input) to High(Input) do
        Input[I] := Byte(((I * 31) xor (I shr 3)) and $FF);
      Source.WriteBuffer(Input, SizeOf(Input));
      Source.Position := 3;
      Header[0] := $A2;
      Header[1] := $79;
      Destination.WriteBuffer(Header, SizeOf(Header));
      try
        Reader := TStreamAdapter.Create(Source, soReference);
        Writer := TStreamAdapter.Create(Destination, soReference);
        ReadCount := High(UInt64);
        WriteCount := High(UInt64);
        Status := Reader.CopyTo(Writer, Count, ReadCount, WriteCount);
        Check((Status = 0) and (ReadCount = Count) and (WriteCount = Count), 'breadth-adapter-copy-fills-both-wide-out-counters');
        Check((Source.Position = Count + 3) and (Destination.Position = Count + 2) and (Destination.Size = Count + 2),
          'breadth-adapter-copy-updates-nonzero-stream-positions');
        Check((Destination.Size = Count + 2) and CompareMem(Destination.Memory, @Header[0], SizeOf(Header))
          and CompareMem(Pointer(NativeUInt(Destination.Memory) + SizeOf(Header)), @Input[3], Count),
          'breadth-adapter-copy-preserves-prefix-and-copies-exact-span');
        ReadCount := High(UInt64);
        WriteCount := High(UInt64);
        Status := Reader.CopyTo(Writer, 0, ReadCount, WriteCount);
        Check((Status = 0) and (ReadCount = 0) and (WriteCount = 0) and (Source.Position = Count + 3)
          and (Destination.Position = Count + 2), 'breadth-adapter-zero-copy-resets-outputs-and-keeps-positions');
      finally
        Reader := nil;
        Writer := nil;
      end;
    finally
      Destination.Free;
    end;
  finally
    Source.Free;
  end;
end;
