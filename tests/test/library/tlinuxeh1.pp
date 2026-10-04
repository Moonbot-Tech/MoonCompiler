{ %target=linux }
{ %needlibrary }
{ %norun }
{ %neededafter }

library tlinuxeh1;

uses
  SysUtils;

function CatchLibraryException: LongInt; cdecl;
begin
  Result:=1;
  try
    raise Exception.Create('library exception');
  except
    on E: Exception do
      Result:=42;
  end;
end;

exports
  CatchLibraryException;

begin
end.
