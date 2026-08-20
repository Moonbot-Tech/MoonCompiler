program dvl_reject_int64_arg_vs_integer_cardinal;
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
function Pick(const V: Integer): Integer; overload;
begin
  Result := 1;
end;

function Pick(const V: Cardinal): Integer; overload;
begin
  Result := 2;
end;

var
  W: Int64;
begin
  W := 7;
  WriteLn(Pick(W));
end.
