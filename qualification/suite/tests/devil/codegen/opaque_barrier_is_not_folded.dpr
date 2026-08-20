program opaque_barrier_is_not_folded;
{$ifdef FPC}
  {$mode delphiunicode}{$H+}
{$endif}
{$APPTYPE CONSOLE}
{$Q-}{$R-}
uses
{$ifdef FPC}
  mormot.core.fpcx64mm,
  {$ifdef UNIX}cthreads,{$endif}
{$endif}
  SysUtils;
function Opaque(V: UInt64): UInt64;
begin
  Result := V xor 0;
end;

var
  R: UInt64;
begin
  R := Opaque(255) and $FF;
  WriteLn(R);
end.
