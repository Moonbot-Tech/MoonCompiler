program dvl_reject_class_abstract_direct;
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
  TBase = class
    procedure P; virtual; abstract;
  end;
var
  B: TBase;
begin
  B := TBase.Create;
  B.Free;
  WriteLn('created');
end.
