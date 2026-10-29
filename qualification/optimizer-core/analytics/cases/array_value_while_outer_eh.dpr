program CacheEH;
{$mode delphiunicode}{$H+}{$inline off}
uses SysUtils;
type TVals=array of Int64;
function Fold(A:TVals; N:Integer):Int64; noinline;
var I:Integer;
begin

Result:=0;
try Writeln('sibling'); finally Writeln('done'); end;
I:=0; while I<N do begin Result:=Result+A[I]+A[7-I]; Inc(I); end;
end;
var Input:TVals; I,N:Integer;
begin
N:=StrToInt(ParamStr(1)); SetLength(Input,8);
for I:=0 to 7 do Input[I]:=I+1;
Writeln(Fold(Input,N));
end.
