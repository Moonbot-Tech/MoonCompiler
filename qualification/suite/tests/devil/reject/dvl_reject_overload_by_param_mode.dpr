program dvl_reject_overload_by_param_mode;
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
function Pick(const V: Int64): Integer; overload;
begin
  Result := 1;
end;

function Pick(var V: Int64): Integer; overload;
begin
  Result := 2;
end;

var
  X: Int64;
begin
  X := 7;
  WriteLn(Pick(X));
end.
