program buffers_memory_semantic;

{$mode delphi}{$H+}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  cwstring,
  {$endif UNIX}
  SysUtils,
  Classes;

procedure Check(ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    raise Exception.Create('BUFFERS_MEMORY_FAIL: ' + AMessage);
end;

procedure TestMoveAndFill;
const
  Sizes: array[0..13] of Integer =
    (0, 1, 2, 3, 7, 8, 15, 16, 31, 32, 63, 64, 255, 4096);
var
  Source, Target, Expected: array[0..4351] of Byte;
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
            'Move payload');
        if TargetOffset > 0 then
          Check(Target[TargetOffset - 1] = $A5, 'Move left guard');
        Check(Target[TargetOffset + Size] = $A5, 'Move right guard');
      end;

  for I := 0 to High(Target) do
  begin
    Target[I] := Byte(I and 255);
    Expected[I] := Target[I];
  end;
  for I := 0 to 4095 do
    Expected[17 + I] := Byte(I and 255);
  Move(Target[0], Target[17], 4096);
  Check(CompareByte(Target[0], Expected[0], SizeOf(Target)) = 0,
    'Move overlap forward');

  for I := 0 to High(Target) do
  begin
    Target[I] := Byte(I and 255);
    Expected[I] := Target[I];
  end;
  for I := 0 to 4095 do
    Expected[I] := Byte((17 + I) and 255);
  Move(Target[17], Target[0], 4096);
  Check(CompareByte(Target[0], Expected[0], SizeOf(Target)) = 0,
    'Move overlap backward');

  for I := 0 to High(Sizes) do
    for TargetOffset := 0 to 3 do
    begin
      Size := Sizes[I];
      FillChar(Target, SizeOf(Target), $A5);
      FillChar(Target[TargetOffset], Size, (I * 17) and 255);
      for J := 0 to Size - 1 do
        Check(Target[TargetOffset + J] = Byte((I * 17) and 255),
          'FillChar payload');
      if TargetOffset > 0 then
        Check(Target[TargetOffset - 1] = $A5, 'FillChar left guard');
      Check(Target[TargetOffset + Size] = $A5, 'FillChar right guard');
    end;
end;

procedure TestMemoryStreams;
var
  Stream: TMemoryStream;
  BytesStream: TBytesStream;
  Source, Target, Bytes: TBytes;
  I: Integer;
  Value: Byte;
  Raised: Boolean;
begin
  SetLength(Source, 200000);
  for I := 0 to High(Source) do
    Source[I] := Byte((I * 31 + 9) and 255);
  Stream := TMemoryStream.Create;
  try
    Check((Stream.Size = 0) and (Stream.Position = 0), 'initial state');
    Stream.WriteBuffer(Source[0], Length(Source));
    Check((Stream.Size = Length(Source)) and
      (Stream.Position = Length(Source)), 'grow/write');
    SetLength(Target, Length(Source));
    Stream.Position := 0;
    Stream.ReadBuffer(Target[0], Length(Target));
    Check(CompareByte(Source[0], Target[0], Length(Source)) = 0,
      'read payload');
    Stream.Position := 150000;
    Stream.Size := 1000;
    Check((Stream.Size = 1000) and (Stream.Position = 1000), 'shrink');
    Stream.Size := 300000;
    Check(Stream.Size = 300000, 'grow size');
    Stream.Clear;
    Check((Stream.Size = 0) and (Stream.Position = 0) and
      (Stream.Memory = nil), 'clear lifetime');
    Raised := False;
    try
      Stream.ReadBuffer(Value, 1);
    except
      on EReadError do
        Raised := True;
    end;
    Check(Raised, 'short-read exception');
  finally
    Stream.Free;
  end;

  Bytes := TBytes.Create(1, 2, 3, 4);
  BytesStream := TBytesStream.Create(Bytes);
  try
    BytesStream.Position := 1;
    Value := 9;
    BytesStream.WriteBuffer(Value, 1);
    Check((BytesStream.Bytes[1] = 9) and (Bytes[1] = 9),
      'TBytesStream managed ownership');
  finally
    BytesStream.Free;
  end;
end;

begin
  try
    TestMoveAndFill;
    TestMemoryStreams;
    WriteLn('BUFFERS_MEMORY_PASS');
  except
    on E: Exception do
    begin
      WriteLn(ErrOutput, E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
