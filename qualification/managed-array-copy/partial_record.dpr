program partial_record;
{$mode delphiunicode}
uses mormot.core.fpcx64mm,SysUtils;
type
 ERefused=class(Exception);
 TFail=class(TObject,IInterface)
  Refs:Integer;
  function QueryInterface(constref IID:TGUID;out Obj):HResult; {$ifdef MSWINDOWS}stdcall{$else}cdecl{$endif};
  function _Release:LongInt; {$ifdef MSWINDOWS}stdcall{$else}cdecl{$endif};
  function _AddRef:LongInt; {$ifdef MSWINDOWS}stdcall{$else}cdecl{$endif};
 end;
 TInner=record
  Tag:Integer;
  Ref:IInterface;
  class operator Finalize(var X:TInner);
 end;
 TOuter=record A,B:TInner; end;
var Armed:Boolean; Unstarted:Integer;
function TFail._AddRef:LongInt; {$ifdef MSWINDOWS}stdcall{$else}cdecl{$endif};
begin if Armed then raise ERefused.Create('refuse');Inc(Refs);Result:=Refs;end;
function TFail._Release:LongInt; {$ifdef MSWINDOWS}stdcall{$else}cdecl{$endif};
begin Dec(Refs);Result:=Refs;end;
function TFail.QueryInterface(constref IID:TGUID;out Obj):HResult; {$ifdef MSWINDOWS}stdcall{$else}cdecl{$endif};
begin Result:=E_NOINTERFACE;end;
class operator TInner.Finalize(var X:TInner);
begin if Armed and (X.Tag=0) then Inc(Unstarted);end;
var A,B:TArray<TOuter>;Obj:IInterface;Raw:TFail;Caught:Boolean;
begin
 Raw:=TFail.Create;Obj:=Raw;SetLength(A,1);A[0].A.Tag:=1;A[0].B.Tag:=2;
 A[0].A.Ref:=Obj;A[0].B.Ref:=Obj;B:=A;Armed:=True;Caught:=False;
 try SetLength(A,2);except on ERefused do Caught:=True;end;
 Armed:=False;
 WriteLn('PARTIAL_RECORD ',Caught,' unstarted_finalizers=',Unstarted);
 if not Caught or (Unstarted<>0) then Halt(1);
 A:=nil;B:=nil;Obj:=nil;
 if Raw.Refs<>0 then Halt(2);
 Raw.Free;
end.
