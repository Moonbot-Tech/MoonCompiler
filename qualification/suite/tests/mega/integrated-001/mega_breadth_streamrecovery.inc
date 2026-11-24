{ A stream may transfer part of a request, then stop. The caller needs both
  the original error and the exact position and bytes left by the transfer. }

type
  { Delphi Win64's WriteBuffer dispatches through the NativeInt slot. }
{$ifdef FPC}
  TBreadthWriteCount = Longint;
{$else}
  TBreadthWriteCount = NativeInt;
{$endif}

  TBreadthChunkStream = class(TMemoryStream)
  public
    WriteLimit: Integer;
    function Read(var Buffer; Count: Longint): Longint; override;
    function Write(const Buffer; Count: TBreadthWriteCount): TBreadthWriteCount; override;
  end;

function TBreadthChunkStream.Read(var Buffer; Count: Longint): Longint;
begin
  Result := inherited Read(Buffer, Min(Count, 2));
end;

function TBreadthChunkStream.Write(const Buffer; Count: TBreadthWriteCount): TBreadthWriteCount;
begin
  If Position >= WriteLimit then
    Exit(0);
  If Count > 2 then
    Count := 2;
  If Count > WriteLimit - Position then
    Count := TBreadthWriteCount(WriteLimit - Position);
  Result := inherited Write(Buffer, Count);
end;

procedure RunBreadthShortReads;
const
  Input: array[0..4] of Byte = ($61, 0, $FF, $C0, $97);
var
  Source: TBreadthChunkStream;
  Data: array[0..7] of Byte;
  Rejected: Boolean;
begin
  Source := TBreadthChunkStream.Create;
  try
    Source.WriteLimit := SizeOf(Input);
    Source.WriteBuffer(Input, SizeOf(Input));
    Source.Position := 1;
    FillChar(Data, SizeOf(Data), $A5);
    Rejected := False;
    try
      Source.ReadBuffer(Data[2], 5);
    except
      on EReadError do Rejected := True;
    end;
    Check(Rejected and (Source.Position = 5), 'breadth-chunk-read-raises-only-when-source-stops');
    Check(CompareMem(@Data[2], @Input[1], 4) and (Data[1] = $A5) and (Data[6] = $A5),
      'breadth-chunk-read-keeps-exact-prefix-and-destination-guards');
    Source.Position := 0;
    Source.ReadBuffer(Data[1], SizeOf(Input));
    Check((Source.Position = SizeOf(Input)) and CompareMem(@Data[1], @Input[0], SizeOf(Input)),
      'breadth-chunk-read-retry-from-new-position');
    Mix(Data[4]);
  finally
    Source.Free;
  end;
end;

procedure RunBreadthShortWrites;
const
  Input: array[0..4] of Byte = ($17, $C1, 0, $92, $4B);
var
  Destination: TBreadthChunkStream;
  Rejected: Boolean;
begin
  Destination := TBreadthChunkStream.Create;
  try
    Destination.WriteLimit := 3;
    Rejected := False;
    try
      Destination.WriteBuffer(Input, SizeOf(Input));
    except
      on EWriteError do Rejected := True;
    end;
    Check(Rejected and (Destination.Position = 3) and (Destination.Size = 3),
      'breadth-chunk-write-reports-stop-after-partial-write');
    Check(CompareMem(Destination.Memory, @Input[0], 3), 'breadth-chunk-write-moves-source-pointer-on-each-call');
    Destination.WriteLimit := SizeOf(Input);
    Destination.WriteBuffer(Input[3], 2);
    Check((Destination.Position = SizeOf(Input)) and (Destination.Size = SizeOf(Input))
      and CompareMem(Destination.Memory, @Input[0], SizeOf(Input)),
      'breadth-chunk-write-resumes-at-committed-position');
    Mix(UInt64(Destination.Size));
  finally
    Destination.Free;
  end;
end;

procedure RunBreadthStringStreamWire;
const
  Expected: array[0..8] of Byte = ($41, 0, $C3, $A9, $F0, $9F, $98, $80, $5A);
var
  Stream: TStringStream;
  Prefix, Tail: string;
  Data: TBytes;
begin
  Prefix := 'A' + #0 + #$00E9;
  Tail := #$D83D#$DE00 + 'Z';
  Stream := TStringStream.Create(Prefix, TEncoding.UTF8, False);
  try
    Stream.Position := Stream.Size;
    Stream.WriteString(Tail);
    Data := Stream.Bytes;
    Check((Stream.Size = SizeOf(Expected)) and (Stream.Position = SizeOf(Expected))
      and (Length(Data) >= SizeOf(Expected)) and CompareMem(@Data[0], @Expected[0], SizeOf(Expected)),
      'breadth-string-stream-utf8-exact-bytes-and-byte-cursor');
    Stream.Position := 4;
    Check((Stream.ReadString(4) = Copy(Tail, 1, 2)) and (Stream.Position = 8),
      'breadth-string-stream-count-reads-bytes-not-utf16-units');
    Check((Stream.ReadString(1) = 'Z') and (Stream.Position = SizeOf(Expected)),
      'breadth-string-stream-supplementary-scalar-keeps-next-byte-aligned');
    Mix(UInt64(Stream.Position));
  finally
    Stream.Free;
  end;
  Check(TEncoding.UTF8.GetByteCount(Prefix + Tail) = SizeOf(Expected),
    'breadth-string-stream-leaves-borrowed-encoding-usable');
end;
