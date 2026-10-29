program AuditArray;
{$mode delphiunicode}{$H+}{$inline off}
uses SysUtils;
type TVals = array of Int64;
var A,B: TVals; I,J,N: Integer; Total: Int64;
type TAlias=record case Boolean of False:(Dummy:UInt64); True:(Value:Pointer); end;
var Alias:TAlias external name 'U_$P$AUDITARRAY_$$_A'; Saved:Pointer;
begin
N:=StrToInt(ParamStr(1)); SetLength(A,8); SetLength(B,8);
for I:=0 to 7 do begin A[I]:=I+1; B[I]:=100+I; end;
try Total:=0; finally Total:=0; end;
Saved:=Pointer(A);
for I:=0 to N-1 do begin If I=1 then Alias.Value:=Pointer(B); Total:=Total+A[I]+A[7-I]; end;
Alias.Value:=Saved;
Writeln(Total);
end.
