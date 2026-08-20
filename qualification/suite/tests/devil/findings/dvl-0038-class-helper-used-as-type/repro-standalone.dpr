program helper_class_var;
{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch anonymousfunctions}
  {$modeswitch functionreferences}
  {$modeswitch INLINEVARS}
{$endif}
{$APPTYPE CONSOLE}
uses
{$ifdef FPC}
  mormot.core.fpcx64mm,
{$endif}
  SysUtils, TypInfo, Rtti;

type
  TBox = class
  end;
  TBoxHelper = class helper for TBox
  public
    class var HelperShared: Integer;
  end;

begin
  TBoxHelper.HelperShared := 5;
  WriteLn('helper class var = ', TBoxHelper.HelperShared);
end.