program AuditArray;
{$mode delphiunicode}{$H+}{$inline off}
uses SysUtils;
type TVals = array of Int64;
var A,B: TVals; I,J,N: Integer; Total: Int64;
var Alias: NativeInt external name 'U_$P$AUDITARRAY_$$_A'; Saved,Delta:NativeInt;
begin
N:=StrToInt(ParamStr(1)); SetLength(A,8); SetLength(B,8);
for I:=0 to 7 do begin A[I]:=I+1; B[I]:=100+I; end;
try Total:=0; finally Total:=0; end;
Saved:=Alias; Delta:=NativeInt(Pointer(B))-Alias;
for I:=0 to N-1 do begin If I=1 then Inc(Alias,Delta); Total:=Total+A[I]+A[7-I]; end;
Alias:=Saved;
Writeln(Total);
end.
