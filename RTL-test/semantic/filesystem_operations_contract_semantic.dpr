program filesystem_operations_contract_semantic;
{$mode delphiunicode}{$H+}
uses mormot.core.fpcx64mm, {$IFDEF UNIX}cthreads,cwstring,BaseUnix,{$ENDIF}
  {$IFDEF MSWINDOWS}Winapi.Windows,{$ENDIF}
  System.SysUtils, System.Classes, System.IOUtils;
var Root: string;
procedure Check(OK: Boolean; const Name: string);
begin
  if not OK then raise Exception.Create('FILESYSTEM_OPERATIONS: '+Name);
end;
procedure ExpectedFailure(Operation: Integer; Kind: ExceptClass);
var Got: Boolean; F: TFileStream; Attr: TFileAttributes;
begin
  Got:=False;
  try
    case Operation of
      0: TFile.Delete(Root+'/missing');
      1: TDirectory.Delete(Root+'/missing');
      2: TDirectory.Delete(Root+'/missing',True);
      3: TDirectory.CreateDirectory(Root+'/file/child');
      4: TFile.SetAttributes(Root+'/missing',[]);
      5: Attr:=TFile.GetAttributes(Root+'/missing');
      6: TDirectory.GetFiles(Root+'/missing');
      7: begin F:=TFile.OpenWrite(Root+'/missing'); F.Free; end;
      8: TDirectory.Copy(Root+'/src',Root+'/src/child');
      9: TFile.Copy(Root+'/file',Root+'/file',True);
      10: TDirectory.GetFiles(Root+'/file');
    end;
  except
    on E:Exception do begin
      Check(E.InheritsFrom(Kind),'wrong error for '+IntToStr(Operation)+': '+E.ClassName+': '+E.Message);
      Got:=True;
    end;
  end;
  Check(Got,'missing error for '+IntToStr(Operation));
end;

procedure CopyAndErrors;
var I: Integer;
begin
  {$IFDEF MSWINDOWS}
  Check(TPath.IsExtendedPrefixed('\\?\C:\x'),'extended path prefix');
  Check(not TPath.IsExtendedPrefixed(';;?\C:\x'),'PATH list separator is not a directory separator');
  Check(TPath.IsUNCRooted('\\server\share'),'native UNC root');
  Check(TPath.IsUNCRooted('//server/share'),'forward-slash UNC root');
  Check(not TPath.IsUNCRooted('\\?\C:\x'),'extended drive is not UNC');
  {$ENDIF}
  TDirectory.CreateDirectory(Root+'/src/nested');
  TDirectory.CreateDirectory(Root+'/empty');
  TFile.WriteAllText(Root+'/src/nested/a.txt','payload '+Char($20ac));
  TFile.WriteAllText(Root+'/src/'+Char($416)+'.txt','Unicode name');
  TFile.WriteAllText(Root+'/file','preserve me');
  TDirectory.Copy(Root+'/src',Root+'/dst');
  Check(TFile.ReadAllText(Root+'/dst/nested/a.txt')='payload '+Char($20ac),'nested copy');
  Check(TFile.ReadAllText(Root+'/dst/'+Char($416)+'.txt')='Unicode name','Unicode path');
  TFile.WriteAllText(Root+'/src/nested/a.txt','changed');
  TDirectory.Copy(Root+'/src',Root+'/dst',False);
  Check(TFile.ReadAllText(Root+'/dst/nested/a.txt')='changed','overwrite existing destination');
  Check(Length(TDirectory.GetFiles(Root+'/empty'))=0,'empty directory');
  Check(Length(TDirectory.GetFiles(Root+'/src','*.missing'))=0,'no mask matches');
  Check(Length(TDirectory.GetFiles(Root+'/src','*.txt',TSearchOption.soAllDirectories))=2,'recursive files');
  ExpectedFailure(0,EInOutError);
  ExpectedFailure(1,EDirectoryNotFoundException);
  ExpectedFailure(2,EDirectoryNotFoundException);
  ExpectedFailure(3,EInOutError);
  ExpectedFailure(4,EFileNotFoundException);
  ExpectedFailure(5,EFileNotFoundException);
  ExpectedFailure(6,EDirectoryNotFoundException);
  ExpectedFailure(7,EFileNotFoundException);
  ExpectedFailure(8,EArgumentException);
  ExpectedFailure(9,EInOutError);
  ExpectedFailure(10,EDirectoryNotFoundException);
  Check(TFile.ReadAllText(Root+'/file')='preserve me','failed copy preserves source');
  TDirectory.CreateDirectory(Root+'/collision/nested/a.txt');
  TDirectory.Copy(Root+'/src',Root+'/collision',True);
  Check(TFile.ReadAllText(Root+'/collision/'+Char($416)+'.txt')='Unicode name','ignore local copy error continues');
end;

procedure Links;
var Target,LinkPath: string; Rec: TSymLinkRec; Code: Integer; Failed:Boolean;
begin
  Target:=TPath.Combine(Root,'target.txt');
  LinkPath:=TPath.Combine(Root,'link.txt');
  TFile.WriteAllText(Target,'old');
  if not TFile.CreateSymLink(LinkPath,Target) then begin
    Code:=GetLastOSError;
    {$IFDEF MSWINDOWS}
    if Code=ERROR_PRIVILEGE_NOT_HELD then begin
      Check(GetEnvironmentVariable('GITHUB_ACTIONS')<>'true','Windows CI must execute native link contracts');
      Writeln('SYMLINK_PERMISSION_UNAVAILABLE');
      Exit;
    end;
    {$ENDIF}
    Check(False,'link creation error '+IntToStr(Code));
  end;
  Check(TFile.GetSymLinkTarget(LinkPath,Rec),'created object is a symlink');
  TFile.Delete(Target);
  TFile.WriteAllText(Target,'new');
  Check(TFile.ReadAllText(LinkPath)='new','link follows replacement');
  Check(TFile.CreateSymLink(Root+'/src-link',Root+'/src'),'directory link');
  TDirectory.Delete(Root+'/src-link',True);
  Check(TFile.ReadAllText(Root+'/src/nested/a.txt')='changed','delete directory link preserves target tree');
  Check(TFile.CreateSymLink(Root+'/src/linked.txt',Target),'link inside copy tree');
  Check(TFile.CreateSymLink(Root+'/nested-alias',Root+'/src/nested'),'alias to nested source');
  Failed:=False;
  try TDirectory.Copy(Root+'/src',Root+'/nested-alias/new');
  except on E:EArgumentException do Failed:=True; end;
  Check(Failed and not TDirectory.Exists(Root+'/src/nested/new'),'alias self-copy rejected before creating destination');
  Check(TFile.CreateSymLink(Root+'/src/relative.txt','nested/a.txt'),'relative link');
  Check(TFile.ReadAllText(Root+'/src/relative.txt')='changed','relative link resolves before copying');
  Check(TFile.CreateSymLink(Root+'/src/relative-dir','nested'),'relative directory link');
  {$IFDEF MSWINDOWS}
  Check(TFileAttribute.faDirectory in TFile.GetAttributes(Root+'/src/relative-dir',False),'relative link directory kind');
  {$ENDIF}
  Check(TFile.ReadAllText(Root+'/src/relative-dir/a.txt')='changed','relative directory resolves from link parent');
  Check(TFile.CreateSymLink(Root+'/src/dangling.txt','not-created.txt'),'dangling link');
  Check(TFile.CreateSymLink(Root+'/src/cycle',Root+'/src'),'directory cycle');
  Check(Length(TDirectory.GetFiles(Root+'/src','a.txt',TSearchOption.soAllDirectories))=1,'enumeration does not follow directory links');
  TDirectory.Copy(Root+'/src',Root+'/link-copy');
  Check(TFile.GetSymLinkTarget(Root+'/link-copy/linked.txt',Rec),'copy preserves link kind');
  TFile.WriteAllText(Root+'/link-copy/nested/a.txt','copied target');
  Check(TFile.ReadAllText(Root+'/link-copy/relative.txt')='copied target','relative link stays relative');
  Check(TFile.ReadAllText(Root+'/link-copy/relative-dir/a.txt')='copied target','relative directory link stays relative');
  TFile.WriteAllText(Root+'/link-copy/not-created.txt','late target');
  Check(TFile.ReadAllText(Root+'/link-copy/dangling.txt')='late target','dangling link preserved');
  Check(TDirectory.Exists(Root+'/link-copy/cycle'),'copied directory link remains usable');
  TDirectory.Delete(Root+'/link-copy',True);
  Check(TFile.ReadAllText(Target)='new','delete copy does not delete target');
  Writeln('FILESYSTEM_LINKS_PASS');
end;

{$IFDEF UNIX}
procedure Permissions;
var Failed: Boolean;
begin
  TDirectory.CreateDirectory(Root+'/locked');
  TFile.WriteAllText(Root+'/locked/data','x');
  Check(fpChmod(Root+'/locked',0)=0,'set denied permissions');
  try
    Failed:=False;
    try TDirectory.GetFiles(Root+'/locked'); except on E:EInOutError do Failed:=True; end;
    Check(Failed,'enumeration denial is not empty');
    Failed:=False;
    try TFile.Delete(Root+'/locked/data'); except on E:EInOutError do Failed:=True; end;
    Check(Failed,'delete denial is not success');
  finally fpChmod(Root+'/locked',448); end;
end;
{$ENDIF}
var G:TGUID;
begin
  CreateGUID(G);
  Root:=TPath.Combine(TPath.GetTempPath,'moon-file-contract-'+GUIDToString(G));
  TDirectory.CreateDirectory(Root);
  try
    CopyAndErrors;
    Links;
    {$IFDEF UNIX}Permissions;{$ENDIF}
  finally
    if TDirectory.Exists(Root) then TDirectory.Delete(Root,True);
  end;
  WriteLn('FILESYSTEM_OPERATIONS_CONTRACT_PASS');
end.
