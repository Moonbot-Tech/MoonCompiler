program m_constref;
{$ifdef FPC}{$mode delphiunicode}{$H+}{$modeswitch advancedrecords}{$endif}
{$APPTYPE CONSOLE}
uses
{$ifdef FPC}
  mormot.core.fpcx64mm,
{$endif}
  SysUtils;

procedure Touch(const [ref] V: Integer);
begin
  WriteLn(V);
end;

begin
  Touch(7);
end.