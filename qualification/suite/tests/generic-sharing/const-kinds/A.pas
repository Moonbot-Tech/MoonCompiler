unit A;
{$mode objfpc}{$H+}
interface
uses Core;
type
 Bool1=specialize TBool<True>;
 Bool2=specialize TBool<False>;
 BoolOuter=specialize TOuter<Bool1>;
 Int1=specialize TInt<-1>;
 Int2=specialize TInt<1>;
 IntOuter=specialize TOuter<Int1>;
 QWord1=specialize TQWord<18446744073709551615>;
 QWord2=specialize TQWord<1>;
 QWordOuter=specialize TOuter<QWord1>;
 WideInt1=specialize TWideInt<(UInt128(1) shl 64)>;
 WideInt2=specialize TWideInt<(UInt128(2) shl 64)>;
 WideIntOuter=specialize TOuter<WideInt1>;
 Enum1=specialize TEnum<One>;
 Enum2=specialize TEnum<Two>;
 EnumOuter=specialize TOuter<Enum1>;
 Char1=specialize TChar<'a'>;
 Char2=specialize TChar<'b'>;
 CharOuter=specialize TOuter<Char1>;
 Text1=specialize TText<'abc'>;
 Text2=specialize TText<'abd'>;
 TextOuter=specialize TOuter<Text1>;
 Unicode1=specialize TUnicode<#1046#1046>;
 Unicode2=specialize TUnicode<#1071#1071>;
 UnicodeOuter=specialize TOuter<Unicode1>;
 Nil1=specialize TNil<nil>;
 Nil2=specialize TNil<nil>;
 NilOuter=specialize TOuter<Nil1>;
implementation
end.