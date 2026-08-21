program dvl_stress_023_record_depth;
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
  TLevel0 = record V: Integer; end;
  TLevel1 = record Inner: TLevel0; V: Integer; end;
  TLevel2 = record Inner: TLevel1; V: Integer; end;
  TLevel3 = record Inner: TLevel2; V: Integer; end;
  TLevel4 = record Inner: TLevel3; V: Integer; end;
  TLevel5 = record Inner: TLevel4; V: Integer; end;
  TLevel6 = record Inner: TLevel5; V: Integer; end;
  TLevel7 = record Inner: TLevel6; V: Integer; end;
  TLevel8 = record Inner: TLevel7; V: Integer; end;
  TLevel9 = record Inner: TLevel8; V: Integer; end;
  TLevel10 = record Inner: TLevel9; V: Integer; end;
  TLevel11 = record Inner: TLevel10; V: Integer; end;
  TLevel12 = record Inner: TLevel11; V: Integer; end;
  TLevel13 = record Inner: TLevel12; V: Integer; end;
  TLevel14 = record Inner: TLevel13; V: Integer; end;
  TLevel15 = record Inner: TLevel14; V: Integer; end;
  TLevel16 = record Inner: TLevel15; V: Integer; end;
var
  R: TLevel16;
begin
  R.V := 1;
  WriteLn(SizeOf(R));
end.
