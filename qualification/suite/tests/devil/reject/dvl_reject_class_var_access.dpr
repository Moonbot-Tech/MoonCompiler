program dvl_reject_class_var_access;
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
  TCounter = class
    class var Count: Integer;
  end;
begin
  TCounter.Count := 3;
  WriteLn(TCounter.Count);
end.
