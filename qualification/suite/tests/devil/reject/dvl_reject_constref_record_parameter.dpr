program dvl_reject_constref_record_parameter;
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
  TRec = record
    Slot: Integer;
  end;

procedure Touch(const [ref] V: TRec);
begin
  WriteLn(V.Slot);
end;

var
  R: TRec;
begin
  R.Slot := 7;
  Touch(R);
end.
