unit inline_base;
{$mode delphi}{$H+}{$Q-}{$R-}{$INLINE ON}
interface
var InlineData:array[0..255] of LongWord;
procedure InitInline;
function Fields(K:Integer):QWord; inline;
implementation
procedure InitInline;
var I:Integer;
begin for I:=0 to 255 do InlineData[I]:=I*23+11;end;
function Fields(K:Integer):QWord; inline;
begin Result:=QWord(InlineData[K])+InlineData[K+1]+InlineData[K+2];end;
end.
