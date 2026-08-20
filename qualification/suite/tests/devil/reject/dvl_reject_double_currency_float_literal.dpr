program dvl_reject_double_currency_float_literal;
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
function Pick(const V: Double): Integer; overload;
begin
  Result := 1;
end;

function Pick(const V: Currency): Integer; overload;
begin
  Result := 2;
end;

begin
  WriteLn(Pick(1.5));
end.
