unit semraise;
{$mode delphi}
interface
procedure RaiseCallback;
implementation
uses SysUtils;
procedure RaiseCallback;
begin
  raise Exception.Create('final callback');
end;
end.
