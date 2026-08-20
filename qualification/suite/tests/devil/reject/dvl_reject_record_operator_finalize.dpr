program dvl_reject_record_operator_finalize;
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
    class operator Finalize(var Dest: TRec);
  end;

class operator TRec.Finalize(var Dest: TRec);
begin
  WriteLn('gone');
end;

var
  R: TRec;
begin
  R.Slot := 1;
  WriteLn(R.Slot);
end.
