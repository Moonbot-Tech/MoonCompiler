program dvl_reject_stdtype_tproc;
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
var
  P: TProc;
  Seen: Integer;
begin
  Seen := 0;
  P := procedure
    begin
      Inc(Seen);
    end;
  P();
  WriteLn(Seen);
end.
