program linux_xdg_paths_contract_semantic;
{ %TARGET=linux }
{$mode delphiunicode}{$H+}
uses mormot.core.fpcx64mm, cthreads, cwstring, System.SysUtils,
  System.Classes, System.IOUtils, Process;
var Root,Config: string; G:TGUID; Child:TProcess; I:Integer;
procedure Check(OK: Boolean; const Name: string);
begin
  if not OK then raise Exception.Create('XDG_PATHS: '+Name);
end;
begin
  if ParamStr(1)='--child' then begin
    Check(TPath.GetDocumentsPath=ParamStr(2),'configured documents');
    Halt(0);
  end;
  CreateGUID(G);
  Root:=TPath.Combine(TPath.GetTempPath,'moon-xdg-'+GUIDToString(G));
  TDirectory.CreateDirectory(Root+'/config');
  TDirectory.CreateDirectory(Root+'/documents');
  try
    TFile.WriteAllText(Root+'/config/user-dirs.dirs','XDG_DOCUMENTS_DIR="'+Root+'/documents"'+#10);
    for I:=0 to 1 do begin
      Config:=Root+'/config';
      if I=1 then Config:=Config+'/';
      Child:=TProcess.Create(nil);
      try
        Child.Executable:=ParamStr(0);
        Child.Parameters.Add('--child');
        Child.Parameters.Add(Root+'/documents');
        Child.Environment.Add('XDG_CONFIG_HOME='+Config);
        Child.Options:=[poWaitOnExit];
        Child.Execute;
        Check(Child.ExitStatus=0,'child '+IntToStr(I));
      finally Child.Free; end;
    end;
  finally TDirectory.Delete(Root,True); end;
  WriteLn('LINUX_XDG_PATHS_CONTRACT_PASS');
end.
