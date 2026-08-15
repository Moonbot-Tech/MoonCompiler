program dvl_reject_record_method_static_self;
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
  TRec = record
    class function F: Integer; static;
  end;
class function TRec.F: Integer;
begin
  Result := Self.F;
end;
begin
  WriteLn(TRec.F);
end.
