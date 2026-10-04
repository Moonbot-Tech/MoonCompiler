program consttemp_minimal;
{$mode delphi}{$H+}{$Q-}{$R-}
uses SysUtils;
var Data:array[0..255] of LongWord;
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
var I,N:Integer;Want:QWord;
begin
  for I:=0 to 255 do Data[I]:=I*17+3;
  for N:=-1 to 17 do begin
    Want:=0;
    if N>0 then begin
      for I:=0 to 63 do Want:=Want+Data[I]+Data[I+1];
      Want:=Want*QWord(N);
      if (N and 1)<>0 then Dec(Want,Data[0]);
    end;
    if Sum(N)<>Want then Halt(1);
    if (N>0) and (RealSum(N)<>(N*4+(N div 2)*1.25)) then Halt(2);
    if (N<=0) and (RealSum(N)<>0) then Halt(3);
  end;
  WriteLn('CONSTTEMP_PASS');
end.
