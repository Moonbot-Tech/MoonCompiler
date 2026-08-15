program dvl_reject_with_ambiguous_ok;
{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch anonymousfunctions}
  {$modeswitch functionreferences}
  {$modeswitch INLINEVARS}
{$endif}
{$APPTYPE CONSOLE}
{$Q-}{$R-}
uses SysUtils;
type
  TA = record
    X: Integer;
  end;
  TB = record
    Y: Integer;
  end;
var
  A: TA;
  B: TB;
begin
  A.X := 1;
  B.Y := 2;
  with A, B do
    WriteLn(X + Y);
end.
