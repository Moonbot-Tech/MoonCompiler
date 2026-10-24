program Probe;{$APPTYPE CONSOLE}
uses {$IFDEF UNIX}cthreads,ffi.manager,{$ENDIF} System.SysUtils,System.TypInfo,System.Rtti,A,B;
type TInfo=function(I:Integer):PTypeInfo;
var C:TRttiContext;I:Integer;X,Y:TObject;F:TRttiField;V:TValue;
procedure Check(const N:string;Get:TInfo);
var R:TRttiType;
begin
 R:=C.GetType(Get(0));
 Writeln(N,'_ITEMS=',R.GetField('Items').FieldType.Handle=Get(1));
 Writeln(N,'_OTHER=',R.GetField('OtherItems').FieldType.Handle=Get(2));
 Writeln(N,'_MATRIX=',R.GetField('Matrix').FieldType.Handle=Get(3));
 Writeln(N,'_ELEMENT=',TRttiDynamicArrayType(C.GetType(Get(3))).ElementType.Handle=Get(4));
 Writeln(N,'_RECORD=',R.GetField('Extra').FieldType.Handle=Get(5));
 Writeln(N,'_RECORD_FIELD=',C.GetType(Get(5)).GetField('More').FieldType.Handle=Get(6));
 Writeln(N,'_SIBLINGS_DISTINCT=',Get(1)<>Get(2));
end;
begin C:=TRttiContext.Create;try
 Check('A',A.Info);Check('B',B.Info);
 for I:=0 to 6 do Writeln('SHARED_',I,'=',A.Info(I)=B.Info(I));
 X:=A.NewBox;Y:=B.NewBox;
 try F:=C.GetType(A.Info(0)).GetField('Items');V:=F.GetValue(X);
 Writeln('VALUE_INFO=',V.TypeInfo=B.Info(1));
 Writeln('VALUE_GET=',V.GetArrayElement(0).AsInteger=41);
 V.SetArrayElement(0,TValue.From<Integer>(71));F.SetValue(Y,V);
 Writeln('VALUE_SET=',(A.ReadBox(X)=71) and (B.ReadBox(Y)=71));
 finally X.Free;Y.Free;end;
finally C.Free;end;end.
