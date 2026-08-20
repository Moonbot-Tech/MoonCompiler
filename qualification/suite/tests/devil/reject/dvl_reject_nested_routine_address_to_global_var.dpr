program dvl_reject_nested_routine_address_to_global_var;
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
  TStep = procedure;

var
  Step: TStep;

procedure Host;
  procedure Inner;
  begin
    WriteLn('inner');
  end;
begin
  Step := Inner;
end;

begin
  Host;
  Step;
end.
