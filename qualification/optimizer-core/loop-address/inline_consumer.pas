unit inline_consumer;
{$mode delphi}{$H+}{$Q-}{$R-}{$INLINE ON}
interface
function CrossUnit(N:Integer):QWord;
implementation
uses inline_base;
function CrossUnit(N:Integer):QWord;
var I,J:Integer;
begin Result:=0;for I:=1 to N do for J:=0 to 63 do Result:=Result+Fields(J);end;
end.
