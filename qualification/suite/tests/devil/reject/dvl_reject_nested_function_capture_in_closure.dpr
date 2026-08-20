program dvl_reject_nested_function_capture_in_closure;
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
procedure Outer;
  procedure Inner;
  begin
    WriteLn('inner');
  end;
var
  P: TProc;
begin
  P := procedure
       begin
         Inner;
       end;
  P();
end;
begin
  Outer;
end.
