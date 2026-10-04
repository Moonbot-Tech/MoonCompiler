unit consttemp_unit;
{$mode delphi}{$H+}{$Q-}{$R-}{$INLINE ON}
interface
var Data:array[0..255] of LongWord;
function Sum(N:Integer):QWord; inline;
function RealSum(N:Integer):Double; inline;
implementation
function Sum(N:Integer):QWord;
label Middle,Top;
var I,J:Integer;
begin
  Result:=0;I:=0;J:=0;
  if N<=0 then Exit;
  if (N and 1)<>0 then goto Middle;
Top:
  Result:=Result+Data[J];
Middle:
  Result:=Result+Data[J+1];Inc(J);
  if J=64 then begin J:=0;Inc(I);end;
  if I<N then goto Top;
end;
function RealSum(N:Integer):Double;
label Top;
var I:Integer;
begin
  Result:=0;I:=0;
  if N<=0 then Exit;
Top:
  Result:=Result+1.25+2.75;
  if (I and 1)<>0 then Result:=Result+1.25;
  Inc(I);
  if I<N then goto Top;
end;
end.
