program negative_semantic;
{$mode delphi}{$H+}
uses negative,inline_base,inline_consumer;
type TCase=function(N:Integer):QWord;
const Cases:array[0..9] of TCase=(@OneUse,@RuntimeBase,@CallInLoop,@BranchInLoop,
  @SideEntry,@AsmInLoop,@TryInLoop,@RedefinedBase,@ZeroTrip,@CrossUnit);
  Names:array[0..9] of string=('OneUse','RuntimeBase','CallInLoop','BranchInLoop',
    'SideEntry','AsmInLoop','TryInLoop','RedefinedBase','ZeroTrip','CrossUnit');
var I,J:Integer;
begin
  for I:=0 to High(Cases) do for J:=-1 to 17 do begin
    InitNegative;InitInline;WriteLn(Names[I],' ',J,' ',Cases[I](J));
  end;
end.
