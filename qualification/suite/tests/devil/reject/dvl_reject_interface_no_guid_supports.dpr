program dvl_reject_interface_no_guid_supports;
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
  INoGuid = interface
    function V: Integer;
  end;
var
  I: INoGuid;
  O: TObject;
begin
  O := TObject.Create;
  if Supports(O, INoGuid, I) then
    WriteLn(I.V);
  O.Free;
end.
