program dvl_stress_011_wide_immediate;
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
  A, B: UInt64;
  S: Int64;
  Sum: UInt64;

function Opaque(V: UInt64): UInt64;
begin
  Result := V xor 0;
end;

begin
  A := Opaque($123456789ABCDEF0);
  S := Int64(Opaque($0FEDCBA987654321));
  Sum := 0;
  B := A mod $80000000;
  Sum := Sum xor B;
  B := A and $80000000;
  Sum := Sum xor B;
  B := A or $80000000;
  Sum := Sum xor B;
  B := A xor $80000000;
  Sum := Sum xor B;
  If A >= $80000000 then
    Sum := Sum xor 1;
  B := A div $80000000;
  Sum := Sum xor B;
  S := S and Int64($80000000);
  Sum := Sum xor UInt64(S);
  B := A mod $100000000;
  Sum := Sum xor B;
  B := A and $100000000;
  Sum := Sum xor B;
  B := A or $100000000;
  Sum := Sum xor B;
  B := A xor $100000000;
  Sum := Sum xor B;
  If A >= $100000000 then
    Sum := Sum xor 1;
  B := A div $100000000;
  Sum := Sum xor B;
  B := A mod $10000000000;
  Sum := Sum xor B;
  B := A and $10000000000;
  Sum := Sum xor B;
  B := A or $10000000000;
  Sum := Sum xor B;
  B := A xor $10000000000;
  Sum := Sum xor B;
  If A >= $10000000000 then
    Sum := Sum xor 1;
  B := A div $10000000000;
  Sum := Sum xor B;
  S := S and Int64($10000000000);
  Sum := Sum xor UInt64(S);
  B := A mod $7FFFFFFFFFFFFFFF;
  Sum := Sum xor B;
  B := A and $7FFFFFFFFFFFFFFF;
  Sum := Sum xor B;
  B := A or $7FFFFFFFFFFFFFFF;
  Sum := Sum xor B;
  B := A xor $7FFFFFFFFFFFFFFF;
  Sum := Sum xor B;
  If A >= $7FFFFFFFFFFFFFFF then
    Sum := Sum xor 1;
  B := A div $7FFFFFFFFFFFFFFF;
  Sum := Sum xor B;
  B := A mod $FFFFFFFF00000000;
  Sum := Sum xor B;
  B := A and $FFFFFFFF00000000;
  Sum := Sum xor B;
  B := A or $FFFFFFFF00000000;
  Sum := Sum xor B;
  B := A xor $FFFFFFFF00000000;
  Sum := Sum xor B;
  If A >= $FFFFFFFF00000000 then
    Sum := Sum xor 1;
  B := A div $FFFFFFFF00000000;
  Sum := Sum xor B;
  S := S and Int64($FFFFFFFF00000000);
  Sum := Sum xor UInt64(S);
  WriteLn(Sum);
end.
