program timezone_fd0;

{$mode delphiunicode}

{$ifdef unix}
uses
  BaseUnix,
  SysUtils,
  Unix;

{$i ../../../../rtl/unix/timezonefile.inc}

procedure Fail(const Name,Actual,Expected: string);
begin
  WriteLn('FAIL ',Name,': actual="',Actual,'" expected="',Expected,'"');
  Halt(1);
end;

procedure WriteFixture(const FileName: string; const Contents: RawByteString);
var
  f: LongInt;
begin
  f:=fpOpen(FileName,O_WrOnly or O_Creat or O_Trunc,$180);
  if f<0 then
    Fail('create-'+FileName,IntToStr(fpGetErrNo),'0');
  try
    if (Contents<>'') and (fpWrite(f,Contents[1],Length(Contents))<>Length(Contents)) then
      Fail('write-'+FileName,IntToStr(fpGetErrNo),'0');
  finally
    fpClose(f);
  end;
end;

procedure Expect(const Name,Actual,Expected: string);
begin
  if Actual<>Expected then
    Fail(Name,Actual,Expected);
end;
{$endif}

{$ifdef unix}
var
  Root,LocationFile,PrimaryFile,AlternativeFile,UnreadableLocation: string;
{$endif}
begin
{$ifdef unix}
  Root:=IncludeTrailingPathDelimiter(GetTempDir(False))+'moon-timezone-'+IntToStr(fpGetPid);
  LocationFile:=Root+DirectorySeparator+'timezone';
  PrimaryFile:=Root+DirectorySeparator+'localtime';
  AlternativeFile:=Root+DirectorySeparator+'alt-localtime';
  UnreadableLocation:=Root+DirectorySeparator+'timezone-dir';
  if fpMkDir(Root,$1C0)<>0 then
    Fail('mkdir-root',IntToStr(fpGetErrNo),'0');
  try
    WriteFixture(LocationFile,'Europe/Berlin'+LineEnding);
    WriteFixture(PrimaryFile,'primary');
    WriteFixture(AlternativeFile,'alternative');
    Expect('location-content',ResolveUnixTimezoneFile(LocationFile,PrimaryFile,AlternativeFile),'Europe/Berlin');

    WriteFixture(LocationFile,'');
    Expect('empty-location-fallback',ResolveUnixTimezoneFile(LocationFile,PrimaryFile,AlternativeFile),PrimaryFile);
    fpUnlink(PrimaryFile);
    Expect('alternative-fallback',ResolveUnixTimezoneFile(LocationFile,PrimaryFile,AlternativeFile),AlternativeFile);
    fpUnlink(AlternativeFile);
    Expect('missing-fallback',ResolveUnixTimezoneFile(LocationFile,PrimaryFile,AlternativeFile),'');

    WriteFixture(PrimaryFile,'primary');
    if fpMkDir(UnreadableLocation,$1C0)<>0 then
      Fail('mkdir-unreadable',IntToStr(fpGetErrNo),'0');
    Expect('read-error-fallback',ResolveUnixTimezoneFile(UnreadableLocation,PrimaryFile,AlternativeFile),PrimaryFile);

    WriteFixture(LocationFile,'Etc/UTC'+LineEnding);
    fpClose(0);
    Expect('descriptor-zero-content',ResolveUnixTimezoneFile(LocationFile,PrimaryFile,AlternativeFile),'Etc/UTC');
    if fpFcntl(0,F_GETFD,0)>=0 then
      Fail('descriptor-zero-close','open','closed');
  finally
    fpUnlink(LocationFile);
    fpUnlink(PrimaryFile);
    fpUnlink(AlternativeFile);
    fpRmDir(UnreadableLocation);
    fpRmDir(Root);
  end;
{$endif}
  WriteLn('TIMEZONE_FD0_OK');
end.
