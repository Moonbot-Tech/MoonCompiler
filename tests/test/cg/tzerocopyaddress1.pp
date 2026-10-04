program tzerocopyaddress1;
{$mode delphi}{$Q-}{$R-}
type TValues=array[0..31] of QWord; TDoubles=array[0..31] of Double;
var A,B:TValues; D,E:TDoubles;
function UnsignedPair(X:QWord):QWord; noinline;
begin
  Result:=A[Cardinal(X)]+B[Cardinal(X)]+X;
end;
function ChangedIndex(X:QWord):QWord; noinline;
begin
  Result:=A[Cardinal(X)];
  Inc(X);
  Result:=Result+B[Cardinal(X)]+X;
end;
function SignedPair(X:Integer):QWord; noinline;
begin
  Result:=PInt64(@A[16])[X]+PInt64(@B[16])[X];
end;
function ArithmeticIndex(X:Cardinal):QWord; noinline;
begin
  X:=X and 31;
  Result:=A[X]+B[X];
end;
function Dot:Double; noinline;
var I:Integer;
begin
  Result:=0;
  for I:=0 to 31 do Result:=Result+D[I]*E[I];
end;
{$push}{$O-}
function DotOracle:Double; noinline;
var I:Integer;
begin
  Result:=0;
  for I:=0 to 31 do Result:=Result+D[I]*E[I];
end;
{$pop}
var I,J:Integer; X,Y:QWord; F,G:Double;
begin
  for I:=0 to 31 do begin A[I]:=I*7+3;B[I]:=I*11+5 end;
  for J:=0 to 2 do
    for I:=0 to 30 do
    begin
      case J of
        0:X:=QWord(I);
        1:X:=$ffffffff00000000 or QWord(I);
        else X:=$8000000000000000 or QWord(I);
      end;
      Y:=A[I]+B[I]+X;
      if UnsignedPair(X)<>Y then Halt(1);
      Y:=A[I]+B[I+1]+X+1;
      if ChangedIndex(X)<>Y then Halt(2);
      if ArithmeticIndex(Cardinal(X))<>A[I]+B[I] then Halt(3);
    end;
  for I:=-16 to 15 do
    if SignedPair(I)<>A[I+16]+B[I+16] then Halt(4);
  for J:=0 to 3 do
  begin
    for I:=0 to 31 do begin D[I]:=(I-16)*0.125;E[I]:=(I mod 7-3)*0.25 end;
    case J of
      1:PQWord(@D[5])^:=$8000000000000000;
      2:PQWord(@D[5])^:=$7ff8000000000042;
      3:begin D[0]:=1E100;D[1]:=-1E100;D[2]:=0.125 end;
    end;
    F:=Dot;G:=DotOracle;
    if PQWord(@F)^<>PQWord(@G)^ then Halt(5);
  end;
end.
