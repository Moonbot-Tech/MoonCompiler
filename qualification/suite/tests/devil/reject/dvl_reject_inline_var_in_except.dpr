program dvl_reject_inline_var_in_except;
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
begin
  try
    raise Exception.Create('x');
  except
    on E: Exception do
    begin
      var Seen := Length(E.Message);
      WriteLn(Seen);
    end;
  end;
end.
