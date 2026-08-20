program dvl_reject_record_operator_assign;
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
    class operator Assign(var Dest: TRec; var Src: TRec);
  end;

class operator TRec.Assign(var Dest: TRec; var Src: TRec);
begin
  Dest.Slot := Src.Slot + 1;
end;

var
  A, B: TRec;
begin
  A.Slot := 1;
  B := A;
  WriteLn(B.Slot);
end.
