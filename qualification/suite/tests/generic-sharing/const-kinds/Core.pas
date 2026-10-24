unit Core;
{$mode objfpc}{$H+}
interface
type TBit=(One,Two);TBits=set of TBit;
 generic TBool<const N:Boolean>=class class function Value:Boolean;static;end;
 generic TInt<const N:Int64>=class class function Value:Int64;static;end;
 generic TQWord<const N:QWord>=class class function Value:QWord;static;end;
 generic TWideInt<const N:UInt128>=class class function Value:UInt128;static;end;
 generic TEnum<const N:TBit>=class class function Value:TBit;static;end;
 generic TChar<const N:Char>=class class function Value:Char;static;end;
 generic TText<const N:AnsiString>=class class function Value:AnsiString;static;end;
 generic TUnicode<const N:UnicodeString>=class class function Value:UnicodeString;static;end;
 generic TNil<const N:Pointer>=class class function Value:Pointer;static;end;
 generic TOuter<T>=class end;
implementation
class function TBool.Value:Boolean;begin Result:=N;end;
class function TInt.Value:Int64;begin Result:=N;end;
class function TQWord.Value:QWord;begin Result:=N;end;
class function TWideInt.Value:UInt128;begin Result:=N;end;
class function TEnum.Value:TBit;begin Result:=N;end;
class function TChar.Value:Char;begin Result:=N;end;
class function TText.Value:AnsiString;begin Result:=N;end;
class function TUnicode.Value:UnicodeString;begin Result:=N;end;
class function TNil.Value:Pointer;begin Result:=N;end;
end.