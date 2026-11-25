program ioutils_api_semantic;

{$mode delphi}{$H+}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  cwstring,
  {$ifdef linux}BaseUnix, Unix,{$endif}
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

{$ifdef linux}
function SetEnv(Name, Value: PAnsiChar; Overwrite: Integer): Integer; cdecl; external 'c' name 'setenv';

procedure CheckFileTimes(const FileName: string);
const
  ZoneFile = '/usr/share/zoneinfo/America/New_York';
var
  Info: TDateTimeInfoRec;
  Native: TStat;
  LocalStamp, Stamp: TDateTime;
  Hour: Integer;
begin
  LocalStamp:=EncodeDateTime(2022,4,5,6,7,8,375);
  TFile.SetLastAccessTime(FileName,LocalStamp);
  Check(FileGetDateTimeInfo(FileName,Info),'read timestamp record');
  Check(MilliSecondsBetween(Info.LastAccessTime,LocalStamp)=0,'access property milliseconds');
  Check(fpStat(UTF8Encode(FileName),Native)=0,'read native ctime');
  Check(MilliSecondOf(Info.CreationTime)=Native.st_ctime_nsec div 1000000,'creation property milliseconds');
  if not FileExists(ZoneFile) then Exit;
  Check(SetEnv('TZ',':/usr/share/zoneinfo/America/New_York',1)=0,'set fold timezone');
  Check(ReadTimezoneFile(ZoneFile),'load fold timezone');
  LocalStamp:=EncodeDateTime(2024,11,3,1,30,0,625);
  for Hour:=5 to 6 do
    begin
    Stamp:=EncodeDateTime(2024,11,3,Hour,30,0,625);
    TFile.SetLastWriteTimeUtc(FileName,Stamp);
    Check(MilliSecondsBetween(TFile.GetLastWriteTimeUtc(FileName),Stamp)=0,'distinct fold instants');
    Check(MilliSecondsBetween(TFile.GetLastWriteTime(FileName),LocalStamp)=0,'local TFile timestamp in fold');
    Check(FileGetDateTimeInfo(FileName,Info),'read fold timestamp');
    Check(MilliSecondsBetween(Info.TimeStamp,LocalStamp)=0,'local timestamp in fold');
    end;
end;
{$endif}

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

    Stamp:=EncodeDateTime(2020,5,6,7,8,11,625);
    TFile.SetLastWriteTimeUtc(FileName,Stamp);
    Check(MilliSecondsBetween(TFile.GetLastWriteTimeUtc(FileName),Stamp)=0,
      'file last-write UTC');
    TFile.Copy(FileName,SecondFile,True);
    Check(MilliSecondsBetween(TFile.GetLastWriteTimeUtc(SecondFile),Stamp)=0,'copied last-write UTC');
    TFile.SetLastAccessTimeUtc(FileName,IncMillisecond(Stamp,250));
    Check(MilliSecondsBetween(TFile.GetLastWriteTimeUtc(FileName),Stamp)=0,'access change preserves write timestamp');
    TFile.SetLastAccessTimeUtc(FileName,Stamp);
    Check(SameSecond(TFile.GetLastAccessTimeUtc(FileName),Stamp),
      'file last-access UTC');

    LocalStamp:=EncodeDateTime(2021,6,7,8,9,10,123);
    TFile.SetLastWriteTime(FileName,LocalStamp);
    Check(MilliSecondsBetween(TFile.GetLastWriteTime(FileName),LocalStamp)=0,
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
    {$ifdef linux}
    CheckFileTimes(FileName);
    {$endif}
  finally
    TDirectory.Delete(Root,True);
  end;
  WriteLn('IOUTILS_API_PASS');
end.
