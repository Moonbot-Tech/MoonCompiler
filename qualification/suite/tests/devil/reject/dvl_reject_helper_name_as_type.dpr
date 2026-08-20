program dvl_reject_helper_name_as_type;
{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch anonymousfunctions}
  {$modeswitch functionreferences}
  {$modeswitch INLINEVARS}
{$endif}
{$APPTYPE CONSOLE}
{$Q-}{$R-}
uses
{$ifdef FPC}
  mormot.core.fpcx64mm,
  {$ifdef UNIX}cthreads,{$endif}
{$endif}
  SysUtils;
type
  TBox = class
  end;
  TBoxHelper = class helper for TBox
  public
    class var HelperShared: Integer;
  end;

begin
  TBoxHelper.HelperShared := 5;
  WriteLn(TBoxHelper.HelperShared);
end.
