program file_boundaries_semantic;
{$APPTYPE CONSOLE}
{$IFDEF FPC}{$mode delphiunicode}{$ENDIF}
uses {$IFDEF UNIX}cwstring,{$ENDIF} SysUtils, Classes, System.IOUtils;
procedure Check(Value: Boolean; const Context: string);
begin
  if not Value then raise Exception.Create(Context);
end;
var
  Paths: array[0..31] of string;
  Stream: TFileStream;
  I, J: Integer;
  Raised: Boolean;
  ByteValue: Byte;
begin
  try
    for I:=0 to High(Paths) do
    begin
      Paths[I]:=TPath.GetTempFileName;
      Check(FileExists(Paths[I]),'temporary file is reserved');
      for J:=0 to I-1 do Check(Paths[I]<>Paths[J],'temporary names are distinct');
    end;
    Stream:=TFile.Open(Paths[0],TFileMode.fmOpen,TFileAccess.faWrite);
    try
      ByteValue:=73;
      Stream.WriteBuffer(ByteValue,1);
    finally Stream.Free; end;
    Raised:=False;
    try
      Stream:=TFile.Open(Paths[0],TFileMode.fmCreateNew,TFileAccess.faWrite);
      Stream.Free;
    except on E: EInOutError do Raised:=True; end;
    Check(Raised,'create-new rejects an existing file');
    Check((Length(TFile.ReadAllBytes(Paths[0]))=1) and (TFile.ReadAllBytes(Paths[0])[0]=73),
      'create-new preserves existing data');
    Check(DeleteFile(Paths[1]),'remove own reserved file');
    Stream:=TFile.Open(Paths[1],TFileMode.fmCreateNew,TFileAccess.faReadWrite);
    try
      Stream.WriteBuffer(ByteValue,1);
      Stream.Position:=0;
      ByteValue:=0;
      Stream.ReadBuffer(ByteValue,1);
      Check(ByteValue=73,'create-new handle is owned by returned stream');
    finally Stream.Free; end;
    {$IFDEF MSWINDOWS}
    Check(TPath.Combine('C:\base','\next')='\next','root-relative combine');
    Check(TPath.Combine('C:\base','D:\next')='D:\next','absolute combine');
    Check(TPath.Combine('C:\base','next')='C:\base\next','relative combine');
    {$ENDIF}
  finally
    for I:=0 to High(Paths) do
      if Paths[I]<>'' then DeleteFile(Paths[I]);
  end;
  WriteLn('FILE_BOUNDARIES_PASS');
end.
