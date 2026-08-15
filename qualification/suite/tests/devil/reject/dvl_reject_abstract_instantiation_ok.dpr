program dvl_reject_abstract_instantiation_ok;
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
  TDerived = class(TBase)
    procedure P; override;
  end;
procedure TDerived.P;
begin
  WriteLn('ok');
end;
var
  B: TBase;
begin
  B := TDerived.Create;
  B.P;
  B.Free;
end.
