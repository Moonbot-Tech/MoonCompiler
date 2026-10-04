unit negative;
{$mode delphi}{$H+}{$Q-}{$R-}{$asmmode intel}{$goto on}{$INLINE OFF}
interface
procedure InitNegative;
function OneUse(N:Integer):QWord;
function RuntimeBase(N:Integer):QWord;
function CallInLoop(N:Integer):QWord;
function BranchInLoop(N:Integer):QWord;
function SideEntry(N:Integer):QWord;
function AsmInLoop(N:Integer):QWord;
function TryInLoop(N:Integer):QWord;
function RedefinedBase(N:Integer):QWord;
function ZeroTrip(N:Integer):QWord;
implementation
type TData=array[0..255] of LongWord; PData=^TData;
var Data,Other:TData; Base:PData;
procedure InitNegative;
var I:Integer;
begin
  for I:=0 to 255 do begin Data[I]:=I*17+3;Other[I]:=I*19+7;end;
  Base:=@Data;
end;
function OneUse(N:Integer):QWord;
var I,J:Integer;
begin Result:=0;for I:=1 to N do for J:=0 to 63 do Result:=Result+Data[J];end;
function RuntimeBase(N:Integer):QWord;
var I,J:Integer;P:PData;
begin P:=Base;Result:=0;for I:=1 to N do for J:=0 to 63 do Result:=Result+P^[J]+P^[J+1];end;
procedure Touch(I:Integer);
begin Inc(Data[I],3);end;
function CallInLoop(N:Integer):QWord;
var I,J:Integer;
begin Result:=0;for I:=1 to N do for J:=0 to 63 do begin
  Result:=Result+Data[J];Touch(J);Result:=Result+Data[J+1];
end;end;
function BranchInLoop(N:Integer):QWord;
var I,J:Integer;
begin Result:=0;for I:=1 to N do for J:=0 to 63 do begin
  Result:=Result+Data[J];if (J and 1)<>0 then Result:=Result+Other[J];Result:=Result+Data[J+1];
end;end;
function SideEntry(N:Integer):QWord;
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
function AsmInLoop(N:Integer):QWord;
var I,J:Integer;
begin Result:=0;for I:=1 to N do for J:=0 to 63 do begin
  Result:=Result+Data[J];asm nop end;Result:=Result+Data[J+1];
end;end;
function TryInLoop(N:Integer):QWord;
var I,J:Integer;
begin Result:=0;for I:=1 to N do for J:=0 to 63 do
  try Result:=Result+Data[J];finally Result:=Result+Data[J+1];end;
end;
function RedefinedBase(N:Integer):QWord;
var I,J:Integer;K:LongWord;
begin Result:=0;for I:=1 to N do for J:=0 to 63 do begin
  K:=Data[J]+Other[J];Result:=Result+K;K:=Data[J+1]+Other[J+1];Result:=Result+K;
end;end;
function ZeroTrip(N:Integer):QWord;
var J:Integer;
begin Result:=0;J:=0;while J<N do begin Result:=Result+Data[J and 255]+Data[(J+1) and 255];Inc(J);end;end;
end.
