program tmoonnamespacequalified1;

{$mode delphi}

uses
  SysUtils;

begin
  if ParamCount<0 then
    begin
      SysUtils.DeleteFile('never-created');
      System.SysUtils.DeleteFile('never-created');
    end;
end.
