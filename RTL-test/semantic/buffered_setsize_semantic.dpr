program buffered_setsize_semantic;

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

procedure Check(ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    raise Exception.Create('BUFFERED_SETSIZE_FAIL: ' + AMessage);
end;

procedure Run;
var
  FileName: string;
  Plain: TFileStream;
  Buffered: TBufferedFileStream;
  Data: array[0..4095] of Byte;
  I: Integer;
begin
  for I := 0 to High(Data) do
    Data[I] := Byte((I * 17 + 5) and 255);
  FileName := GetTempFileName(GetTempDir(False), 'rtl-bufsize-');
  try
    Plain := TFileStream.Create(FileName, fmCreate);
    try
      Plain.WriteBuffer(Data[0], SizeOf(Data));
      Plain.Size := 9000;
      Check(Plain.Size = 9000, 'neighbor TFileStream grow');
      Plain.Size := SizeOf(Data);
    finally
      Plain.Free;
    end;

    Buffered := TBufferedFileStream.Create(FileName, fmOpenReadWrite);
    try
      Check(Buffered.Size = SizeOf(Data), 'constructor reads existing size');
      Buffered.Position := 100;
      Data[0] := $7C;
      Buffered.WriteBuffer(Data[0], 1);
      Buffered.Size := 9000;
      Check(Buffered.Size = 9000, 'grow cached size: ' +
        IntToStr(Buffered.Size));
      Check(Buffered.Position = 9000, 'grow position');
      Buffered.Position := 8999;
      Data[0] := $FF;
      Buffered.ReadBuffer(Data[0], 1);
      Check(Data[0] = 0, 'grown range is zero-filled');
      Buffered.Size := 222;
      Check(Buffered.Size = 222, 'shrink cached size');
      Check(Buffered.Position = 222, 'shrink position');
      Buffered.InitializeCache(1024, 4);
      Check(Buffered.Size = 222, 'cache reinitialize preserves size');
    finally
      Buffered.Free;
    end;

    Plain := TFileStream.Create(FileName, fmOpenRead);
    try
      Check(Plain.Size = 222, 'underlying file size');
      Plain.Position := 100;
      Plain.ReadBuffer(Data[0], 1);
      Check(Data[0] = $7C, 'dirty page flushed before resize');
    finally
      Plain.Free;
    end;
  finally
    DeleteFile(FileName);
  end;
end;

begin
  try
    Run;
    WriteLn('BUFFERED_SETSIZE_PASS');
  except
    on E: Exception do
    begin
      WriteLn(ErrOutput, E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
