program buffers_streams_semantic;

{$mode delphi}{$H+}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  cwstring,
  {$endif UNIX}
  SysUtils,
  Classes,
  BufStream;

type
  TPartialReadStream = class(TMemoryStream)
  public
    function Read(var Buffer; Count: LongInt): LongInt; override;
  end;

  TShortWriteStream = class(TMemoryStream)
  public
    function Write(const Buffer; Count: LongInt): LongInt; override;
  end;

  TZeroWriteStream = class(TMemoryStream)
  public
    function Write(const Buffer; Count: LongInt): LongInt; override;
  end;

function TPartialReadStream.Read(var Buffer; Count: LongInt): LongInt;
begin
  if Count > 7 then
    Count := 7;
  Result := inherited Read(Buffer, Count);
end;

function TShortWriteStream.Write(const Buffer; Count: LongInt): LongInt;
begin
  if Count > 5 then
    Count := 5;
  Result := inherited Write(Buffer, Count);
end;

function TZeroWriteStream.Write(const Buffer; Count: LongInt): LongInt;
begin
  Result := 0;
end;

procedure Check(ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    raise Exception.Create('BUFFERS_STREAMS_FAIL: ' + AMessage);
end;

procedure TestMoveAndFill;
const
  Sizes: array[0..17] of Integer =
    (0, 1, 2, 3, 7, 8, 15, 16, 17, 31, 32, 33, 63, 64, 65, 255, 4096, 8192);
var
  Source, Target, Expected: array[0..8447] of Byte;
  I, J, Size, SourceOffset, TargetOffset: Integer;
begin
  for I := 0 to High(Source) do
    Source[I] := Byte((I * 29 + 17) and 255);
  for I := 0 to High(Sizes) do
    for SourceOffset := 0 to 3 do
      for TargetOffset := 0 to 3 do
      begin
        Size := Sizes[I];
        FillChar(Target, SizeOf(Target), $A5);
        Move(Source[SourceOffset], Target[TargetOffset], Size);
        for J := 0 to Size - 1 do
          Check(Target[TargetOffset + J] = Source[SourceOffset + J],
            'Move size/alignment payload');
        if TargetOffset > 0 then
          Check(Target[TargetOffset - 1] = $A5, 'Move left guard');
        Check(Target[TargetOffset + Size] = $A5, 'Move right guard');
      end;

  for I := 0 to High(Expected) do
  begin
    Target[I] := Byte(I and 255);
    Expected[I] := Target[I];
  end;
  for I := 0 to 4095 do
    Expected[17 + I] := Byte(I and 255);
  Move(Target[0], Target[17], 4096);
  for I := 0 to High(Target) do
    Check(Target[I] = Expected[I], 'Move overlap forward');

  for I := 0 to High(Expected) do
  begin
    Target[I] := Byte(I and 255);
    Expected[I] := Target[I];
  end;
  for I := 0 to 4095 do
    Expected[I] := Byte((17 + I) and 255);
  Move(Target[17], Target[0], 4096);
  for I := 0 to High(Target) do
    Check(Target[I] = Expected[I], 'Move overlap backward');

  for I := 0 to High(Sizes) do
    for TargetOffset := 0 to 3 do
    begin
      Size := Sizes[I];
      FillChar(Target, SizeOf(Target), $A5);
      FillChar(Target[TargetOffset], Size, (I * 17) and 255);
      for J := 0 to Size - 1 do
        Check(Target[TargetOffset + J] = Byte((I * 17) and 255),
          'FillChar size/alignment payload');
      if TargetOffset > 0 then
        Check(Target[TargetOffset - 1] = $A5, 'FillChar left guard');
      Check(Target[TargetOffset + Size] = $A5, 'FillChar right guard');
    end;
end;

procedure WritePattern(AStream: TStream; ACount: Integer);
var
  Buffer: array[0..4095] of Byte;
  I, Chunk: Integer;
begin
  for I := 0 to High(Buffer) do
    Buffer[I] := Byte((I * 31 + 9) and 255);
  while ACount > 0 do
  begin
    Chunk := ACount;
    if Chunk > SizeOf(Buffer) then
      Chunk := SizeOf(Buffer);
    AStream.WriteBuffer(Buffer[0], Chunk);
    Dec(ACount, Chunk);
  end;
end;

procedure CheckPattern(AStream: TStream; ACount: Integer; const AMessage: string);
var
  Buffer: array[0..4095] of Byte;
  I, Chunk, Offset: Integer;
begin
  Offset := 0;
  while ACount > 0 do
  begin
    Chunk := ACount;
    if Chunk > SizeOf(Buffer) then
      Chunk := SizeOf(Buffer);
    AStream.ReadBuffer(Buffer[0], Chunk);
    for I := 0 to Chunk - 1 do
      Check(Buffer[I] = Byte(((Offset + I) * 31 + 9) and 255), AMessage);
    Inc(Offset, Chunk);
    Dec(ACount, Chunk);
  end;
end;

procedure TestCopyFrom;
const
  Sizes: array[0..5] of Integer = (0, 1, 31, 4096, 131072, 262177);
var
  Source: TPartialReadStream;
  Target: TMemoryStream;
  ShortTarget: TShortWriteStream;
  ZeroTarget: TZeroWriteStream;
  I: Integer;
  Raised: Boolean;
begin
  for I := 0 to High(Sizes) do
  begin
    Source := TPartialReadStream.Create;
    Target := TMemoryStream.Create;
    try
      WritePattern(Source, Sizes[I]);
      Source.Position := Source.Size div 3;
      Check(Target.CopyFrom(Source, 0) = Sizes[I], 'CopyFrom count=0 result');
      Check((Target.Size = Sizes[I]) and (Source.Position = Source.Size),
        'CopyFrom count=0 positions');
      Target.Position := 0;
      CheckPattern(Target, Sizes[I], 'CopyFrom count=0 payload');
    finally
      Target.Free;
      Source.Free;
    end;
  end;

  Source := TPartialReadStream.Create;
  Target := TMemoryStream.Create;
  try
    WritePattern(Source, 200);
    Source.Position := 17;
    Check(Target.CopyFrom(Source, 63) = 63, 'CopyFrom exact count result');
    Check((Source.Position = 80) and (Target.Size = 63), 'CopyFrom exact positions');
  finally
    Target.Free;
    Source.Free;
  end;

  Source := TPartialReadStream.Create;
  Target := TMemoryStream.Create;
  try
    WritePattern(Source, 10);
    Source.Position := 0;
    Raised := False;
    try
      Target.CopyFrom(Source, 20);
    except
      on EReadError do
        Raised := True;
    end;
    Check(Raised, 'CopyFrom short source exception');
  finally
    Target.Free;
    Source.Free;
  end;

  Source := TPartialReadStream.Create;
  ShortTarget := TShortWriteStream.Create;
  try
    WritePattern(Source, 20);
    Source.Position := 0;
    Check(ShortTarget.CopyFrom(Source, 20) = 20,
      'CopyFrom short destination result');
    Check(ShortTarget.Size = 20, 'CopyFrom short destination payload');
  finally
    ShortTarget.Free;
    Source.Free;
  end;

  Source := TPartialReadStream.Create;
  ZeroTarget := TZeroWriteStream.Create;
  try
    WritePattern(Source, 20);
    Source.Position := 0;
    Raised := False;
    try
      ZeroTarget.CopyFrom(Source, 20);
    except
      on EWriteError do
        Raised := True;
    end;
    Check(Raised, 'CopyFrom zero-progress destination exception');
  finally
    ZeroTarget.Free;
    Source.Free;
  end;
end;

procedure TestMemoryStreams;
var
  Stream: TMemoryStream;
  BytesStream: TBytesStream;
  Bytes: TBytes;
  Value: Byte;
  Raised: Boolean;
begin
  Stream := TMemoryStream.Create;
  try
    Check((Stream.Size = 0) and (Stream.Position = 0), 'memory initial state');
    WritePattern(Stream, 200000);
    Check((Stream.Size = 200000) and (Stream.Position = 200000), 'memory grow/write');
    Stream.Position := 0;
    CheckPattern(Stream, 200000, 'memory read payload');
    Stream.Position := 150000;
    Stream.Size := 1000;
    Check((Stream.Size = 1000) and (Stream.Position = 1000), 'memory shrink position');
    Stream.Size := 300000;
    Check(Stream.Size = 300000, 'memory resize large');
    Stream.Clear;
    Check((Stream.Size = 0) and (Stream.Position = 0) and (Stream.Memory = nil),
      'memory clear ownership');
    Raised := False;
    try
      Stream.ReadBuffer(Value, 1);
    except
      on EReadError do
        Raised := True;
    end;
    Check(Raised, 'memory short read exception');
  finally
    Stream.Free;
  end;

  Bytes := TBytes.Create(1, 2, 3, 4);
  BytesStream := TBytesStream.Create(Bytes);
  try
    BytesStream.Position := 1;
    Value := 9;
    BytesStream.WriteBuffer(Value, 1);
    Check(BytesStream.Bytes[1] = 9, 'bytes stream payload/ownership');
  finally
    BytesStream.Free;
  end;
end;

procedure TestFileAndBufferedStreams;
var
  FileName: string;
  FileStream: TFileStream;
  Buffered: TBufferedFileStream;
  Buffer: array[0..8191] of Byte;
  I: Integer;
  Raised: Boolean;
begin
  FileName := GetTempFileName(GetTempDir(False), 'rtl-stream-');
  try
    FileStream := TFileStream.Create(FileName, fmCreate);
    try
      for I := 0 to High(Buffer) do
        Buffer[I] := Byte((I * 13 + 5) and 255);
      FileStream.WriteBuffer(Buffer[0], SizeOf(Buffer));
      Check((FileStream.Size = SizeOf(Buffer)) and
        (FileStream.Seek(-17, soEnd) = SizeOf(Buffer) - 17), 'file write/seek');
      FileStream.Size := 4096;
      Check((FileStream.Size = 4096) and (FileStream.Position <= 4096),
        'file resize');
      FileStream.Size := 9000;
      Check(FileStream.Size = 9000, 'file resize extend: ' +
        IntToStr(FileStream.Size));
      FileStream.Size := 4096;
    finally
      FileStream.Free;
    end;

    Buffered := TBufferedFileStream.Create(FileName, fmOpenReadWrite);
    try
      Buffered.Position := 100;
      FillChar(Buffer, 333, $7C);
      Buffered.WriteBuffer(Buffer[0], 333);
      Buffered.Flush;
      Buffered.Position := 100;
      FillChar(Buffer, 333, 0);
      Buffered.ReadBuffer(Buffer[0], 333);
      for I := 0 to 332 do
        Check(Buffer[I] = $7C, 'buffered write/flush/read');
      Buffered.Size := 9000;
      Check(Buffered.Size = 9000, 'buffered resize extend: ' +
        IntToStr(Buffered.Size));
      Buffered.Size := 222;
      Check(Buffered.Size = 222, 'buffered resize shrink: ' +
        IntToStr(Buffered.Size));
    finally
      Buffered.Free;
    end;

    Raised := False;
    try
      FileStream := TFileStream.Create(FileName + '.missing', fmOpenRead);
      FileStream.Free;
    except
      on EFOpenError do
        Raised := True;
    end;
    Check(Raised, 'file open error');
  finally
    DeleteFile(FileName);
  end;
end;

begin
  try
    TestMoveAndFill;
    TestCopyFrom;
    TestMemoryStreams;
    TestFileAndBufferedStreams;
    WriteLn('BUFFERS_STREAMS_PASS');
  except
    on E: Exception do
    begin
      WriteLn(ErrOutput, E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
