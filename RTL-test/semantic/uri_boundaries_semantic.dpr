program uri_boundaries_semantic;
{$APPTYPE CONSOLE}
{$mode delphiunicode}
uses {$IFDEF UNIX}cwstring,{$ENDIF} SysUtils, URIParser;
procedure Check(Value: Boolean; const Context: string);
begin
  if not Value then raise Exception.Create(Context);
end;
var Path, URI, Recovered, Resolved: string;
begin
  Path:=IncludeTrailingPathDelimiter(GetTempDir)+UnicodeChar($03BB)+' '+UnicodeChar($4E2D)+'.txt';
  URI:=FilenameToURI(Path);
  Check(Pos('%ce%bb',LowerCase(URI))>0,'UTF8 lambda escaping');
  Check(Pos('%e4%b8%ad',LowerCase(URI))>0,'UTF8 CJK escaping');
  Check(URIToFilename(URI,Recovered) and (Recovered=Path),'filename roundtrip');
  Check(ResolveRelativeURI('https://host/path/',UnicodeChar($03BB),Resolved),'resolve Unicode URI');
  Check(LowerCase(Resolved)='https://host/path/%ce%bb','resolved UTF8 URI');
  Check(URIToFilename('file:///test/%',Recovered),'literal percent URI');
  Check(Copy(Recovered,Length(Recovered),1)='%','incomplete percent preserved');
  Check(URIToFilename('file:///test/%0',Recovered),'one-digit escape URI');
  Check(Copy(Recovered,Length(Recovered)-1,2)='%0','incomplete hex preserved');
  WriteLn('URI_BOUNDARIES_PASS');
end.
