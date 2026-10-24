unit A;
interface
function GetS:UnicodeString;
function GetClass:TClass;
implementation
uses Core;
function GetS:UnicodeString; begin Result:=TOuter<Integer>.TInner.S; end;
function GetClass:TClass; begin Result:=TOuter<Integer>.TInner; end;
end.
