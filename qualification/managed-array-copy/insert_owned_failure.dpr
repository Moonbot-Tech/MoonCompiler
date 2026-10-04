program insert_owned_failure;
{$mode delphiunicode}
uses SysUtils;
type EStopped=class(Exception);
 TRef=class(TObject,IInterface)
  function QueryInterface(constref IID:TGUID;out Obj):HResult; {$ifdef MSWINDOWS}stdcall{$else}cdecl{$endif};
  function _AddRef:Integer; {$ifdef MSWINDOWS}stdcall{$else}cdecl{$endif};
  function _Release:Integer; {$ifdef MSWINDOWS}stdcall{$else}cdecl{$endif};
 end;
var Calls,FailAt,Refs,Checks:Integer;Original:TMemoryManager;Refused:Pointer;
function TRef.QueryInterface(constref IID:TGUID;out Obj):HResult; {$ifdef MSWINDOWS}stdcall{$else}cdecl{$endif};
begin Result:=E_NOINTERFACE;end;
function TRef._AddRef:Integer; {$ifdef MSWINDOWS}stdcall{$else}cdecl{$endif};
begin Inc(Calls);if(Calls=FailAt)and(FailAt>0)then raise EStopped.Create('acquire');Inc(Refs);Result:=Refs;end;
function TRef._Release:Integer; {$ifdef MSWINDOWS}stdcall{$else}cdecl{$endif};
begin Dec(Refs);Result:=Refs;end;
function Realloc(var P:Pointer;Size:PtrUInt):Pointer;
begin if(Refused<>nil)and(P=Refused)then begin Refused:=nil;raise EStopped.Create('allocation');end;Result:=Original.ReallocMem(P,Size);end;
procedure Check(Value:Boolean;const Name:string);
begin Inc(Checks);if not Value then begin Writeln('FAIL ',Name,' calls=',Calls,' refs=',Refs);Halt(1);end;end;
function Source(const A:TArray<IInterface>;RaiseNow:Boolean;P1,P2,P3,P4:Integer):TArray<IInterface>;noinline;
begin Check(P1+P2+P3+P4=10,'source outgoing args');if RaiseNow then raise EStopped.Create('source');Result:=Copy(A);end;
function Index(RaiseNow:Boolean):Integer;
begin if RaiseNow then raise EStopped.Create('index');Result:=1;end;
procedure Run(Kind,Failure:Integer);
var A,B:TArray<IInterface>;S:array[0..3]of IInterface;Item:TRef;I,BeforeCalls:Integer;
 Caught:Boolean;Manager:TMemoryManager;Before:Pointer;
begin
 Item:=TRef.Create;SetLength(A,4);SetLength(B,2);
 for I:=0 to 3 do begin A[I]:=Item;S[I]:=Item;end;
 for I:=0 to 1 do B[I]:=Item;
 Before:=Pointer(B);Calls:=0;FailAt:=Failure;Caught:=False;
 GetMemoryManager(Original);Manager:=Original;
 if Failure=10 then begin Refused:=Before-2*SizeOf(NativeInt);Manager.ReallocMem:=Realloc;SetMemoryManager(Manager);end;
 try
  try
   case Kind of
    0:Insert(A,B,Index(Failure=9));
    1:Insert(S,B,Index(Failure=9));
    2:Insert([A[0],A[1]],B,Index(Failure=9));
    3:Insert(Source(A,Failure=11,1,2,3,4),B,Index(Failure=9));
   end;
  except on EStopped do Caught:=True;end;
 finally SetMemoryManager(Original);FailAt:=0;Refused:=nil;end;
 BeforeCalls:=Calls;
 Check(Caught=((Failure>0)and(Failure<=BeforeCalls))or(Failure=9)or(Failure=10)or((Failure=11)and(Kind=3)),'caught');
 if Caught then begin
  Check((Pointer(B)=Before)and(Length(B)=2),'unchanged carrier');
  Check(Refs=10,'owner finalized on unwind before epilogue');
 end;
 B:=nil;Check(Refs=8,'successful source owner cleared before epilogue');
 A:=nil;for I:=0 to 3 do S[I]:=nil;
 Check(Refs=0,'all refs');Item.Free;
end;
var Kind,Failure:Integer;
begin
 for Kind:=0 to 3 do for Failure:=0 to 11 do Run(Kind,Failure);
 Writeln('INSERT_OWNED_FAILURE_PASS ',Checks);
end.
