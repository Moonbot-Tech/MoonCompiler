unit A;interface uses System.SysUtils,System.TypInfo,Core;
type TPad1=record A:array[0..1]of Byte;end;TPad2=record A:array[0..2]of Byte;end;TPad3=record A:array[0..3]of Byte;end;TPad4=record A:array[0..4]of Byte;end;TPad5=record A:array[0..5]of Byte;end;TPad6=record A:array[0..6]of Byte;end;TPad7=record A:array[0..7]of Byte;end;TPad8=record A:array[0..8]of Byte;end;TPad9=record A:array[0..9]of Byte;end;TPad10=record A:array[0..10]of Byte;end;TPad11=record A:array[0..11]of Byte;end;TPad12=record A:array[0..12]of Byte;end;TPad13=record A:array[0..13]of Byte;end;TPad14=record A:array[0..14]of Byte;end;TPad15=record A:array[0..15]of Byte;end;TPad16=record A:array[0..16]of Byte;end;
type TB=TBox<Integer>;
function Info(I:Integer):PTypeInfo;
function NewBox:TObject;
function ReadBox(O:TObject):Integer;
implementation
function Info(I:Integer):PTypeInfo;var O:TB;
begin case I of
0:Result:=TypeInfo(TB);
1:Result:=TypeInfo(O.Items);
2:Result:=TypeInfo(O.OtherItems);
3:Result:=TypeInfo(O.Matrix);
4:Result:=TypeInfo(O.Matrix[0]);
5:Result:=TypeInfo(O.Extra);
6:Result:=TypeInfo(O.Extra.More);
else Result:=nil;end;end;
function NewBox:TObject;var O:TB;begin O:=TB.Create;SetLength(O.Items,1);O.Items[0]:=41;Result:=O;end;
function ReadBox(O:TObject):Integer;begin Result:=TB(O).Items[0];end;
end.
