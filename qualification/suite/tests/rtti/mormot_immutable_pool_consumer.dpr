program mormot_immutable_pool_consumer;
uses SysUtils,Classes,TypInfo,mormot.core.base,mormot.core.rtti,
 mormot.core.text,mormot.core.json,mormot.core.interfaces;
type
 IPoolService = interface(IInvokable)
 ['{16CCF888-1234-4567-8901-ABCDEF123456}']
 function Echo(const Payload:RawUtf8; Count:Int64):RawUtf8;
 procedure Bump(var Count:Integer);
 end;
 TData=class(TPersistent)
 private
 FName:string;
 FCount:Integer;
 published
 property Name:string read FName write FName;
 property Count:Integer read FCount write FCount;
 end;
var F:TInterfaceFactory; D,E:TData; S:RawUtf8; Valid:Boolean;
begin
 F:=TInterfaceFactory.Get(TypeInfo(IPoolService));
 if F.MethodsCount<>2 then Halt(1);
 if (F.Methods[0].Uri<>'Echo') or (F.Methods[1].Uri<>'Bump') then Halt(2);
 Writeln('CONTRACT=',F.Contract);
 D:=TData.Create; E:=TData.Create;
 try
  D.Name:='pool'; D.Count:=42;
  S:=ObjectToJson(D);
  Writeln('JSON=',S);
  JsonToObject(E,Pointer(S),Valid);
  if not Valid or (E.Name<>'pool') or (E.Count<>42) then Halt(3);
 finally E.Free; D.Free; end;
 Writeln('MORMOT_POOL_PASS');
end.
