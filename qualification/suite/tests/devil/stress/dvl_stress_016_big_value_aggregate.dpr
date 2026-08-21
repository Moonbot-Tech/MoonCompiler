program dvl_stress_016_big_value_aggregate;
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
  TBig = record
    Mark: Int64;
    Body: array[0..8191] of Byte;
  end;

function Take(const A: TBig; B: TBig): Int64;
begin
  Result := A.Mark + B.Mark + A.Body[0] + B.Body[High(B.Body)];
end;

var
  X: TBig;
begin
  FillChar(X, SizeOf(X), 0);
  X.Mark := 5;
  X.Body[0] := 6;
  X.Body[High(X.Body)] := 7;
  WriteLn(Take(X, X), ' ', SizeOf(TBig));
end.
