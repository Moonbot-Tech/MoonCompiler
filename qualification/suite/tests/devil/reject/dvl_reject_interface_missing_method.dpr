program dvl_reject_interface_missing_method;
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
  IThing = interface
    function Val: Integer;
  end;
  TThing = class(TInterfacedObject, IThing)
  end;
var
  T: IThing;
begin
  T := TThing.Create;
  WriteLn(T.Val);
end.
