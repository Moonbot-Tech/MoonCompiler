program file_resource_semantic;

{$mode delphi}{$H+}
{$R ../../tests/test/units/system/tres4.res}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  {$endif UNIX}
  SysUtils,
  Classes
  {$ifdef WINDOWS}
  ,Windows
  {$endif WINDOWS};

procedure Check(ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    raise Exception.Create('FILE_RESOURCE_FAIL: ' + AMessage);
end;

procedure TestFileStream;
var
  FileName: string;
  Stream: TFileStream;
  Data, ReadBack: array[0..8191] of Byte;
  I: Integer;
  Raised: Boolean;
begin
  for I := 0 to High(Data) do
    Data[I] := Byte((I * 19 + 7) and 255);
  FileName := SysUtils.GetTempFileName(GetTempDir(False), 'rtl-file-');
  try
    Stream := TFileStream.Create(FileName, fmCreate);
    try
      Stream.WriteBuffer(Data[0], SizeOf(Data));
      Check((Stream.Size = SizeOf(Data)) and
        (Stream.Position = SizeOf(Data)), 'write size/position');
      Check(Stream.Flush, 'flush');
      Check(Stream.Seek(-31, soEnd) = SizeOf(Data) - 31, 'seek from end');
      FillChar(ReadBack, SizeOf(ReadBack), 0);
      Stream.ReadBuffer(ReadBack[0], 31);
      Check(CompareByte(Data[SizeOf(Data) - 31], ReadBack[0], 31) = 0,
        'tail payload');
      Stream.Size := 1024;
      Check((Stream.Size = 1024) and (Stream.Position = 1024), 'shrink');
      Stream.Size := 9000;
      Check((Stream.Size = 9000) and (Stream.Position = 9000), 'grow');
      Stream.Position := 8999;
      ReadBack[0] := $FF;
      Stream.ReadBuffer(ReadBack[0], 1);
      Check(ReadBack[0] = 0, 'grown range zero-filled');
    finally
      Stream.Free;
    end;

    Stream := TFileStream.Create(FileName, fmOpenRead);
    try
      Check((Stream.Size = 9000) and (Stream.FileName = FileName),
        'reopen size/name');
      Stream.ReadBuffer(ReadBack[0], 64);
      Check(CompareByte(Data[0], ReadBack[0], 64) = 0, 'reopen payload');
    finally
      Stream.Free;
    end;

    Raised := False;
    try
      Stream := TFileStream.Create(FileName + '.missing', fmOpenRead);
      Stream.Free;
    except
      on EFOpenError do
        Raised := True;
    end;
    Check(Raised, 'missing-file exception');
  finally
    SysUtils.DeleteFile(FileName);
  end;
end;

procedure TestResourceStream;
var
  Stream: TResourceStream;
  Data: array[0..31] of Byte;
  Raised: Boolean;
begin
  Stream := TResourceStream.Create(HInstance, 'mdtytul100_png', RT_RCDATA);
  try
    Check(Stream.Size = 50223, 'named resource size');
    Check(Stream.Position = 0, 'resource initial position');
    Stream.ReadBuffer(Data[0], SizeOf(Data));
    Check(Stream.Position = SizeOf(Data), 'resource read position');
    Check((Data[0] = $89) and (Data[1] = Ord('P')) and
      (Data[2] = Ord('N')) and (Data[3] = Ord('G')), 'resource payload');
  finally
    Stream.Free;
  end;

  Raised := False;
  try
    Stream := TResourceStream.Create(HInstance, 'missing-rtl-resource',
      RT_RCDATA);
    Stream.Free;
  except
    on EResNotFound do
      Raised := True;
  end;
  Check(Raised, 'missing-resource exception');
end;

begin
  try
    TestFileStream;
    TestResourceStream;
    WriteLn('FILE_RESOURCE_PASS');
  except
    on E: Exception do
    begin
      WriteLn(ErrOutput, E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
