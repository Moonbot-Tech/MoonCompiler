program integer_pressure;
{$mode delphi}{$Q-}{$R-}
function Four(A,B,C,D:Int64):Int64; noinline;
var I:Integer;
begin
  Result:=0;
  for I:=0 to 999 do
    Result:=Result+A*251+B*253+C*257+D*259;
end;
function LiveFour(A,B,C,D:Int64):Int64; noinline;
var I:Integer;
begin
  Result:=0;
  for I:=0 to 999 do begin
    Result:=Result+A*251+B*253+C*257+D*259;
    If Result<0 then Result:=Result+A+B+C+D;
  end;
end;
begin
  If Four(1,2,3,4)<>2564000 then Halt(1);
  If LiveFour(1,2,3,4)<>2564000 then Halt(2);
  WriteLn('INTEGER-PRESSURE:PASS');
end.
