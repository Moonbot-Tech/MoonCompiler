program dvl_stress_015_edge_case_labels;
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
  V: Int64;
  Seen: Integer;

function Opaque(X: Int64): Int64;
begin
  Result := X xor 0;
end;

begin
  Seen := 0;
  V := Opaque(High(Int64));
  case V of
    Low(Int64): Seen := 1;
    Low(Int64) + 1: Seen := 2;
    -1: Seen := 3;
    0: Seen := 4;
    High(Int64) - 1: Seen := 5;
    High(Int64): Seen := 6;
  else
    Seen := 7;
  end;
  WriteLn(Seen);
end.
