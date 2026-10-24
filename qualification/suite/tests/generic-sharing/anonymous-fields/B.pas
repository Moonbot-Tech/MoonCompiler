unit B;interface uses System.SysUtils,System.TypInfo,Core;
type TPad1=record A:array[0..1]of Byte;end;TPad2=record A:array[0..2]of Byte;end;
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
