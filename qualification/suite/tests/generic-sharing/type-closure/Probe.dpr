program Probe;
{$APPTYPE CONSOLE}
uses System.SysUtils,System.TypInfo,System.Rtti,Core,A,B;
type TInfoFunc=function(I:Integer):PTypeInfo;
var C:TRttiContext;
procedure Check(const N:string; F:TInfoFunc);
var R:TRttiType; M:TRttiMethod;
procedure FieldAndReturn(const FieldName,MethodName:string; Index:Integer);
begin
 Writeln(N,'_',Index,'_',FieldName,'_FIELD=',R.GetField(FieldName).FieldType.Handle=F(Index));
 Writeln(N,'_',Index,'_',FieldName,'_RETURN=',R.GetMethod(MethodName).ReturnType.Handle=F(Index));
end;
begin
 R:=C.GetType(F(1));FieldAndReturn('Value','Read',0);
 R:=C.GetType(F(3));FieldAndReturn('Value','Read',2);
 R:=C.GetType(F(4));FieldAndReturn('Items','GetItems',5);FieldAndReturn('Ptr','GetPtr',6);
 FieldAndReturn('Cls','GetClass',7);FieldAndReturn('Callback','GetCallback',8);FieldAndReturn('Nested','GetNested',9);
 Writeln(N,'_ARRAY_ALIAS=',F(0)=F(5));
 Writeln(N,'_NESTED_CLASSINFO=',C.GetType(F(9)).AsInstance.MetaclassType.ClassInfo=F(9));
 R:=C.GetType(F(10));M:=R.GetMethod('ToArray');
 Writeln(N,'_DICT_RETURN=',(M<>nil) and (M.ReturnType.Handle=F(0)));
end;
begin
 C:=TRttiContext.Create;
 try Check('A',A.Info);Check('B',B.Info);
 Writeln('ARRAY_SHARED=',A.Info(0)=B.Info(0));Writeln('PROCVAR_SHARED=',A.Info(2)=B.Info(2));
 Writeln('NESTED_PTR_SHARED=',A.Info(6)=B.Info(6));Writeln('NESTED_CLASSREF_SHARED=',A.Info(7)=B.Info(7));
 Writeln('NESTED_CALLBACK_SHARED=',A.Info(8)=B.Info(8));Writeln('NESTED_CLASS_SHARED=',A.Info(9)=B.Info(9));
 Writeln('DICT_VALUES=',A.DictionaryWorks and B.DictionaryWorks);
 finally C.Free;end;
end.
