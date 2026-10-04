program l1_contract;
{$mode delphiunicode}
uses mormot.core.fpcx64mm, SysUtils;
type
  ERefused=class(Exception);
  TCounter=class(TObject,IInterface)
    Refs:Integer;
    function QueryInterface(constref IID:TGUID;out Obj):HResult; {$ifdef MSWINDOWS}stdcall{$else}cdecl{$endif};
    function _AddRef:Integer; {$ifdef MSWINDOWS}stdcall{$else}cdecl{$endif};
    function _Release:Integer; {$ifdef MSWINDOWS}stdcall{$else}cdecl{$endif};
  end;
  TItem=record
    Value:Integer;
    Ref:IInterface;
    class operator AddRef(var Item:TItem);
    class operator Finalize(var Item:TItem);
  end;
  TPair=array[0..1] of TItem;
  TOuter=record
    Pair:TPair;
    class operator AddRef(var Item:TOuter);
    class operator Finalize(var Item:TOuter);
  end;
  TAssigned=record
    Value:Integer;
    Ref:IInterface;
    class operator Copy(constref Source:TAssigned;var Dest:TAssigned);
    class operator Finalize(var Item:TAssigned);
  end;
var Adds,OuterAdds,Copies,Releases,ThrowCopy,ThrowRelease,ThrowAdd,Checks:Integer;
    Events:UnicodeString;
procedure Check(Value:Boolean;const Name:UnicodeString);
begin
  Inc(Checks);
  if not Value then begin WriteLn('FAIL ',Name); Halt(1); end;
end;
function TCounter.QueryInterface(constref IID:TGUID;out Obj):HResult; {$ifdef MSWINDOWS}stdcall{$else}cdecl{$endif};
begin Result:=E_NOINTERFACE; end;
function TCounter._AddRef:Integer; {$ifdef MSWINDOWS}stdcall{$else}cdecl{$endif};
begin Inc(Refs); Result:=Refs; end;
function TCounter._Release:Integer; {$ifdef MSWINDOWS}stdcall{$else}cdecl{$endif};
begin
  Dec(Refs); Inc(Releases); Result:=Refs;
  if Releases=ThrowRelease then raise ERefused.Create('release');
end;
class operator TItem.AddRef(var Item:TItem);
begin
  Inc(Adds); Inc(Item.Value); Events:=Events+'i';
  if Adds=ThrowAdd then raise ERefused.Create('record AddRef');
end;
class operator TItem.Finalize(var Item:TItem);
begin end;
class operator TOuter.AddRef(var Item:TOuter);
begin Inc(OuterAdds); Events:=Events+'o'; end;
class operator TOuter.Finalize(var Item:TOuter);
begin end;
class operator TAssigned.Copy(constref Source:TAssigned;var Dest:TAssigned);
begin
  Dest.Ref:=Source.Ref;
  Dest.Value:=Source.Value;
  Inc(Copies);
  if Copies=ThrowCopy then raise ERefused.Create('after write');
end;
class operator TAssigned.Finalize(var Item:TAssigned);
begin end;
procedure AddRefContract;
var A,B:TArray<TItem>; O,P:TArray<TOuter>; Obj:TCounter;
    Operation:Integer; Caught:Boolean;
begin
  Obj:=TCounter.Create;
  for Operation:=0 to 2 do begin
    SetLength(A,2); A[0].Value:=10; A[1].Value:=20;
    A[0].Ref:=Obj; A[1].Ref:=Obj; B:=A;
    Adds:=0; Events:='';
    case Operation of
      0:SetLength(B,3);
      1:SetLength(B,1);
      2:B:=Copy(A);
    end;
    Check(Adds=2-Ord(Operation=1),'AddRef-only hook count');
    Check((A[0].Value=10) and (B[0].Value=11),'AddRef-only value');
    Check(Obj.Refs=2+Adds,'AddRef-only ownership');
    A:=nil; B:=nil; Check(Obj.Refs=0,'AddRef-only cleanup');
  end;
  SetLength(A,2); A[0].Ref:=Obj; A[1].Ref:=Obj; B:=A;
  Adds:=0; ThrowAdd:=2; Caught:=False;
  try SetLength(B,3); except on ERefused do Caught:=True; end;
  ThrowAdd:=0;
  Check(Caught and (Adds=2),'AddRef callback failure');
  Check((Pointer(A)=Pointer(B)) and (Length(B)=2),'AddRef failure old carrier');
  Check(Obj.Refs=2,'AddRef failure acquired fields reclaimed');
  A:=nil; B:=nil; Check(Obj.Refs=0,'AddRef failure cleanup');
  SetLength(O,2);
  O[0].Pair[0].Ref:=Obj; O[0].Pair[1].Ref:=Obj;
  O[1].Pair[0].Ref:=Obj; O[1].Pair[1].Ref:=Obj;
  P:=O; Adds:=0; OuterAdds:=0; Events:=''; SetLength(P,3);
  Check((Adds=4) and (OuterAdds=2),'nested hook count');
  Check(Events='iioiio','nested fields before outer hook');
  Check(Obj.Refs=8,'nested ownership');
  O:=nil; P:=nil; Check(Obj.Refs=0,'nested cleanup'); Obj.Free;
end;
procedure CopyFailureContract;
var A,B:TArray<TAssigned>; Obj:TCounter; Original:Pointer;
    Operation:Integer; Caught:Boolean; BeforeHeap,AfterHeap:TMMFragmentationStatus;
begin
  Obj:=TCounter.Create;
  for Operation:=0 to 2 do begin
    SetLength(A,4);
    A[0].Ref:=Obj; A[1].Ref:=Obj; A[2].Ref:=Obj; A[3].Ref:=Obj;
    A[0].Value:=123; B:=A; Original:=Pointer(A);
    BeforeHeap:=CurrentHeapFragmentationStatus;
    Copies:=0; ThrowCopy:=2; Caught:=False;
    try
      case Operation of
        0:SetLength(A,8);
        1:SetLength(A,2);
        2:A:=Copy(A);
      end;
    except on ERefused do Caught:=True; end;
    ThrowCopy:=0; AfterHeap:=CurrentHeapFragmentationStatus;
    Check(Caught and (Copies=2),'copy after-write caught');
    Check((Pointer(A)=Original) and (Pointer(B)=Original) and (Length(A)=4),'old carriers preserved');
    Check((Obj.Refs=4) and (A[0].Value=123),'after-write references reclaimed');
    Check(BeforeHeap.LiveSmallBytes+BeforeHeap.LiveMediumBytes+BeforeHeap.LiveLargeBytes=
      AfterHeap.LiveSmallBytes+AfterHeap.LiveMediumBytes+AfterHeap.LiveLargeBytes,'after-write carrier reclaimed');
    A:=nil; B:=nil; Check(Obj.Refs=0,'after-write final cleanup');
  end;
  Obj.Free;
end;
procedure ReleaseFailureContract;
var A:TArray<IInterface>; Obj:TCounter; Original:Pointer; Caught:Boolean; I:Integer;
begin
  Obj:=TCounter.Create; SetLength(A,4);
  for I:=0 to 3 do A[I]:=Obj;
  Original:=Pointer(A); Releases:=0; ThrowRelease:=2; Caught:=False;
  try SetLength(A,2); except on ERefused do Caught:=True; end;
  ThrowRelease:=0;
  Check(Caught and (Length(A)=4) and (Pointer(A)=Original),'unique shrink basic carrier guarantee');
  Check((A[2]=nil) and (A[3]=nil) and (Obj.Refs=2),'released slots cleared before callback');
  SetLength(A,2); Check((Length(A)=2) and (Obj.Refs=2),'unique shrink retry');
  A:=nil; Check(Obj.Refs=0,'unique shrink final cleanup'); Obj.Free;
end;
procedure OrdinaryContract;
var A,B:TArray<UnicodeString>; W,Z:TArray<WideString>; D:TArray<Double>;
begin
  SetLength(A,2); A[0]:='a'#0'b'; A[1]:='second'; B:=A; SetLength(B,3);
  Check((Length(A)=2) and (B[0]='a'#0'b'),'ordinary strings'); B:=Copy(A); Check(B[1]='second','ordinary copy');
  SetLength(W,2); W[0]:='wide'#0'value'; W[1]:='second'; Z:=W; SetLength(Z,3);
  Check((Length(W)=2) and (Z[0]='wide'#0'value'),'WideString grow'); Z:=Copy(W); Check(Z[1]='second','WideString copy');
  SetLength(D,2); D[0]:=2.5; SetLength(D,5); Check((D[0]=2.5) and (D[4]=0),'unmanaged grow');
end;
begin
  AddRefContract;
  CopyFailureContract;
  ReleaseFailureContract;
  OrdinaryContract;
  WriteLn('L1_CONTRACT_PASS ',Checks);
end.
