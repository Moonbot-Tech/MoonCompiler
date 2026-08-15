program dvl_reject_inherited_without_parent;
{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch anonymousfunctions}
  {$modeswitch functionreferences}
  {$modeswitch INLINEVARS}
{$endif}
{$APPTYPE CONSOLE}
{$Q-}{$R-}
uses SysUtils;
type
  TThing = class
    procedure P;
  end;
procedure TThing.P;
begin
  inherited;
  WriteLn('ok');
end;
var
  T: TThing;
begin
  T := TThing.Create;
  T.P;
  T.Free;
end.
