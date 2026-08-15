program i128;
{$mode delphiunicode}{$H+}
{$Q-}{$R-}
uses SysUtils;
var
  A, B, R: Int128;
begin
  A := Int128((UInt128(UInt64($0000000000000000)) shl 64) or UInt128(UInt64($0000000000000001)));
  B := Int128((UInt128(UInt64($0000000000000000)) shl 64) or UInt128(UInt64($8000000000000000)));
  R := A xor B;
  WriteLn('low  = ', IntToHex(UInt64(R and $FFFFFFFFFFFFFFFF), 16));
  WriteLn('high = ', IntToHex(UInt64((UInt128(R) shr 64) and $FFFFFFFFFFFFFFFF), 16));
  WriteLn('expected low 8000000000000001 high 0000000000000000');
end.
