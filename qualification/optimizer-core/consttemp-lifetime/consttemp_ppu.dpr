program consttemp_ppu;
{$mode delphi}{$H+}{$Q-}{$R-}{$INLINE ON}
uses consttemp_unit;
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
