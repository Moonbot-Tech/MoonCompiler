program dvl_reject_record_operator_initialize;
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
    class operator Initialize(out Dest: TRec);
  end;

class operator TRec.Initialize(out Dest: TRec);
begin
  Dest.Slot := 5;
end;

var
  R: TRec;
begin
  WriteLn(R.Slot);
end.
