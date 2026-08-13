program Fpc41447NoreturnDefinition;

{$mode objfpc}

uses
  SysUtils;

procedure Stop; forward;

procedure Stop; noreturn;
begin
  raise Exception.Create('not called');
end;

begin
end.
