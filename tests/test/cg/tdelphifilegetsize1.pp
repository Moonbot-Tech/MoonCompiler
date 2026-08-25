program tdelphifilegetsize1;

{$ifdef FPC}
  {$mode delphiunicode}
{$endif}

uses
  Classes,
  SysUtils,
  System.IOUtils;

procedure Check(Condition: Boolean; ErrorCode: Byte);
begin
  if not Condition then
    Halt(ErrorCode);
end;

var
  Data: array[0..6] of Byte;
  FileName,
  MissingName: string;
  Stream: TFileStream;

begin
  FileName:=ChangeFileExt(ParamStr(0),'.'+#$440+#$430+#$437+#$43C+#$435+#$440);
  MissingName:=FileName+'.missing';
  SysUtils.DeleteFile(FileName);
  SysUtils.DeleteFile(MissingName);
  Check(TFile.GetSize(MissingName)=-1,1);
  try
    Stream:=TFileStream.Create(FileName,fmCreate);
    try
      Check(TFile.GetSize(FileName)=0,2);
      FillChar(Data,SizeOf(Data),$5a);
      Stream.WriteBuffer(Data,SizeOf(Data));
    finally
      Stream.Free;
    end;
    Check(TFile.GetSize(FileName)=SizeOf(Data),3);
    Check(TFile.GetSize(ParamStr(0))>0,4);
  finally
    SysUtils.DeleteFile(FileName);
  end;
  Check(TFile.GetSize(FileName)=-1,5);
end.
