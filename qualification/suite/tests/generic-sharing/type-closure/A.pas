unit A;
interface
uses System.SysUtils,System.TypInfo,Core,System.Generics.Collections;
type TA=TArray<Integer>; TF=TFn<Integer>; TB=TBox<TA>; TFB=TBox<TF>; TC=TContainer<Integer>;
function Info(I:Integer):PTypeInfo;
function DictionaryWorks:Boolean;
implementation
function Info(I:Integer):PTypeInfo;
begin
 case I of
  0:Result:=TypeInfo(TA);
  1:Result:=TypeInfo(TB);
  2:Result:=TypeInfo(TF);
  3:Result:=TypeInfo(TFB);
  4:Result:=TypeInfo(TC);
  5:Result:=TypeInfo(TC.TValues);
  6:Result:=TypeInfo(TC.TPtr);
  7:Result:=TypeInfo(TC.TClassRef);
  8:Result:=TypeInfo(TC.TCallback);
  9:Result:=TypeInfo(TC.TNested);
  10:Result:=TypeInfo(TDictionary<Integer,Integer>.TValueCollection);
  else Result:=nil;
 end;
end;
function DictionaryWorks:Boolean;
var D:TDictionary<Integer,Integer>; V:TArray<Integer>;
begin D:=TDictionary<Integer,Integer>.Create;try D.Add(1,10);D.Add(2,20);V:=D.Values.ToArray;Result:=(Length(V)=2) and (V[0]+V[1]=30);finally D.Free;end;end;
end.
