unit Core;
interface
uses Base,HelpDef;
{$A1}
type
 TLayout<T>=record B:Byte; Value:T; E:Byte; end;
 TTools=class class function SizeOfType<T>:Integer; static; end;
 TBox<T>=class
  class function HelperRead:Integer; static;
  class function ReadValue(Index:Integer):T; static;
  class function AddOne(Value:Integer):Integer; static;
 end;
implementation
class function TTools.SizeOfType<T>:Integer; begin Result:=SizeOf(T); end;
class function TBox<T>.HelperRead:Integer; begin Result:=TScope.Tag; end;
{$R+}{$Q+}
class function TBox<T>.AddOne(Value:Integer):Integer; begin Result:=Value+1; end;
class function TBox<T>.ReadValue(Index:Integer):T;
var A:array[0..0] of T;
begin A[0]:=Default(T); Result:=A[Index]; end;
end.
