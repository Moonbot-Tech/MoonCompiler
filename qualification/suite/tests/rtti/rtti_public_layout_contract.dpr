program rtti_public_layout_contract;
uses System.SysUtils,System.TypInfo;
procedure Check(C:Boolean;const Why:string);begin if not C then raise Exception.Create(Why);end;
procedure SetStack(var Value:SizeInt);begin Value:=42;end;
procedure Callback(Instance:Pointer;Args:PPointer);begin PInteger(Instance)^:=73;end;
procedure SetHelper(var Helper:TInvokeHelper);begin Helper:=@Callback;end;
procedure SetName(var Name:PShortString;Value:PShortString);begin Name:=Value;end;
var V:TVmtMethodExEntry; R:TRecMethodExEntry; T:TIntfMethodEntry;
 P,Q:TVmtMethodParam; Name:ShortString; N:Integer;
begin
 { These are ordinary writable local records, never writes to emitted RTTI. }
 V:=Default(TVmtMethodExEntry);R:=Default(TRecMethodExEntry);T:=Default(TIntfMethodEntry);
 SetStack(V.StackSize);SetStack(R.StackSize);SetStack(T.StackSize);
 Check((V.StackSize=42) and (R.StackSize=42) and (T.StackSize=42),'native StackSize var API');
 SetHelper(V.InvokeHelper);SetHelper(R.InvokeHelper);SetHelper(T.InvokeHelper);
 N:=0;V.InvokeHelper(@N,nil);Check(N=73,'VMT helper storage');
 N:=0;R.InvokeHelper(@N,nil);Check(N=73,'record helper storage');
 N:=0;T.InvokeHelper(@N,nil);Check(N=73,'interface helper storage');
 Name:='local name';SetName(V.NamePtr,@Name);SetName(R.NamePtr,@Name);SetName(T.NamePtr,@Name);
 Check((V.NamePtr=@Name) and (R.NamePtr=@Name) and (T.NamePtr=@Name),'native name pointer var API');
 P:=Default(TVmtMethodParam);SetName(P.NamePtr,@Name);Q:=P;
 Check(Q.NamePtr=P.NamePtr,'public value-copy pointer semantics');
 Move(P,Q,SizeOf(P));Check(Q.NamePtr=@Name,'public Move pointer semantics');
 Writeln('RTTI_PUBLIC_LAYOUT_CONTRACT_PASS');
end.
