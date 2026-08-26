program ioutils_api_semantic;

{$mode delphi}{$H+}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  cwstring,
  {$endif UNIX}
  System.SysUtils,
  System.Classes,
  System.DateUtils,
  System.IOUtils;

procedure Check(aCondition: Boolean; const aMessage: string);
begin
  if not aCondition then
    raise Exception.Create('IOUTILS_API_FAIL: '+aMessage);
end;

function SameSecond(const aLeft,aRight: TDateTime): Boolean;
begin
  Result:=Abs(SecondsBetween(aLeft,aRight))<=1;
end;

function CountItems(const aItems: IEnumerable<string>): Integer;
var
  Enumerator: IEnumerator<string>;
begin
  Result:=0;
  Enumerator:=aItems.GetEnumerator;
  while Enumerator.MoveNext do
    begin
    Check(Enumerator.GetCurrent<>'','enumerator current');
    Inc(Result);
    end;
end;

function OnlyLog(const aPath: string; const aSearchRec: TSearchRec): Boolean;
begin
  Result:=SameText(ExtractFileExt(aSearchRec.Name),'.log');
end;

var
  Missing,Root,SubDir,FileName,SecondFile: string;
  LocalStamp,Stamp,CreationBefore: TDateTime;

begin
  Root:=TPath.Combine(TPath.GetTempPath,
    'moon-ioutils-'+TPath.GetRandomFileName);
  SubDir:=TPath.Combine(Root,'sub');
  FileName:=TPath.Combine(Root,'one.txt');
  SecondFile:=TPath.Combine(SubDir,'two.log');
  Missing:=TPath.Combine(Root,'missing.txt');
  TDirectory.CreateDirectory(SubDir);
  try
    TFile.WriteAllText(FileName,'one');
    TFile.WriteAllText(SecondFile,'two');
    Check(TDirectory.GetDirectoryRoot(Root)=
      TPath.GetPathRoot(TPath.GetFullPath(Root)),'directory root');

    Stamp:=EncodeDateTime(2020,5,6,7,8,10,0);
    TFile.SetLastWriteTimeUtc(FileName,Stamp);
    Check(SameSecond(TFile.GetLastWriteTimeUtc(FileName),Stamp),
      'file last-write UTC');
    TFile.SetLastAccessTimeUtc(FileName,Stamp);
    Check(SameSecond(TFile.GetLastAccessTimeUtc(FileName),Stamp),
      'file last-access UTC');

    LocalStamp:=EncodeDateTime(2021,6,7,8,9,10,0);
    TFile.SetLastWriteTime(FileName,LocalStamp);
    Check(SameSecond(TFile.GetLastWriteTime(FileName),LocalStamp),
      'file last-write local');

    TDirectory.SetLastWriteTimeUtc(SubDir,Stamp);
    Check(SameSecond(TDirectory.GetLastWriteTimeUtc(SubDir),Stamp),
      'directory last-write UTC');
    TDirectory.SetLastAccessTimeUtc(SubDir,Stamp);
    Check(SameSecond(TDirectory.GetLastAccessTimeUtc(SubDir),Stamp),
      'directory last-access UTC');

    CreationBefore:=TFile.GetCreationTimeUtc(FileName);
    TFile.SetCreationTimeUtc(FileName,Stamp);
    {$ifdef WINDOWS}
    Check(SameSecond(TFile.GetCreationTimeUtc(FileName),Stamp),
      'file creation UTC');
    {$else WINDOWS}
    Check(SameSecond(TFile.GetCreationTimeUtc(FileName),CreationBefore),
      'POSIX creation time remains read-only');
    {$endif WINDOWS}

    Check(CountItems(TDirectory.GetFilesEnumerator(Root))=1,
      'top-level file enumerator');
    Check(CountItems(TDirectory.GetDirectoriesEnumerator(Root))=1,
      'top-level directory enumerator');
    Check(CountItems(TDirectory.GetFilesEnumerator(Root,'*',
      TSearchOption.soAllDirectories))=2,'recursive file enumerator');
    Check(CountItems(TDirectory.GetFilesEnumerator(Root,
      TSearchOption.soAllDirectories,@OnlyLog))=1,
      'predicate file enumerator');
    Check(CountItems(TDirectory.GetFileSystemEntriesEnumerator(Root))=2,
      'filesystem-entry enumerator');

    try
      TDirectory.GetDirectoryRoot('');
      Check(False,'empty directory root rejected');
    except
      on E: EInOutError do
        ;
    end;
    try
      TFile.SetLastWriteTimeUtc(Missing,Stamp);
      Check(False,'missing timestamp path rejected');
    except
      on E: EOSError do
        ;
    end;
  finally
    TDirectory.Delete(Root,True);
  end;
  WriteLn('IOUTILS_API_PASS');
end.
