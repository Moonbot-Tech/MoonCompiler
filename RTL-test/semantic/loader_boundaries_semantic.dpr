program loader_boundaries_semantic;
{$APPTYPE CONSOLE}
{$mode delphiunicode}
uses {$IFDEF UNIX}cwstring,{$ENDIF} SysUtils, Classes, Dynlibs, System.IOUtils;
type TAnswer = function: Integer; cdecl;
var
  Directory, LibraryPath, SourcePath: string;
  Handle: TLibHandle;
  Answer: TAnswer;
procedure Check(Value: Boolean; const Context: string);
begin
  if not Value then raise Exception.Create(Context);
end;
begin
  {$IFDEF MSWINDOWS}
  SetMultiByteConversionCodePage(1251);
  SourcePath:=ExtractFilePath(ParamStr(0))+'loader_boundary_fixture.dll';
  {$ELSE}
  SourcePath:=ExtractFilePath(ParamStr(0))+'libloader_boundary_fixture.so';
  {$ENDIF}
  Directory:=TPath.GetTempFileName;
  Check(DeleteFile(Directory),'release own reserved name');
  Directory:=Directory+UnicodeChar($03BB)+UnicodeChar($4E2D);
  Check(CreateDir(Directory),'create Unicode loader directory');
  LibraryPath:=IncludeTrailingPathDelimiter(Directory)+ExtractFileName(SourcePath);
  try
    TFile.Copy(SourcePath,LibraryPath);
    Handle:=SysUtils.SafeLoadLibrary(UnicodeString(LibraryPath));
    Check(Handle<>NilHandle,'Unicode SafeLoadLibrary');
    try
      Answer:=TAnswer(GetProcedureAddress(Handle,'Answer'));
      Check(Assigned(Answer) and (Answer()=42),'loaded fixture export');
    finally Dynlibs.UnloadLibrary(Handle); end;
    Check(SysUtils.SafeLoadLibrary(UnicodeString(LibraryPath+'.missing'))=NilHandle,'missing library result');
  finally
    DeleteFile(LibraryPath);
    RemoveDir(Directory);
  end;
  WriteLn('LOADER_BOUNDARIES_PASS');
end.
