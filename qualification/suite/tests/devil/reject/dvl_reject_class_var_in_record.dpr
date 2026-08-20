program dvl_reject_class_var_in_record;
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
  TBox = record
    class var Shared: Integer;
    class function Ask: Integer; static;
  end;

class function TBox.Ask: Integer;
begin
  Result := Shared;
end;

begin
  TBox.Shared := 7;
  WriteLn(TBox.Ask);
end.
