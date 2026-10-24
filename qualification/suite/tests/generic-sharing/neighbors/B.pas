unit B;
{$R-}{$Q+}{$A2}
interface
function GetFunc:Pointer;
function CallFunc:Integer;
function GetArray:Pointer;
function HelperValue:Integer;
function LayoutSize:Integer;
procedure OverflowValue(X:Integer);
procedure RangeValue(X:Integer);
implementation
uses Core,HelpB;
type TFn=function:Integer;
function GetFunc:Pointer;var F:TFn; begin {$IFDEF FPC}Result:=nil;{$ELSE}F:=TTools.SizeOfType<Integer>; Result:=Pointer(F);{$ENDIF} end;
function CallFunc:Integer;begin Result:=TTools.SizeOfType<Integer>; end;
function GetArray:Pointer;begin Result:=TypeInfo(TArray<Integer>); end;
function LayoutSize:Integer;begin Result:=SizeOf(TLayout<Int64>);end;
procedure OverflowValue(X:Integer);var V:Integer;begin V:=TBox<Integer>.AddOne(X); if V=99999 then Writeln(V);end;
function HelperValue:Integer;begin Result:=TBox<Integer>.HelperRead; end;
procedure RangeValue(X:Integer);var V:Integer;begin V:=TBox<Integer>.ReadValue(X); if V=99999 then Writeln(V);end;
end.
