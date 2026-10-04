program middle_throw;
{$define EXPECT_L1_FIXED}
{$ifdef FPC}{$mode delphiunicode}{$endif}
{$APPTYPE CONSOLE}

uses
  {$ifdef FPC}mormot.core.fpcx64mm,{$endif}
  SysUtils, Variants;

type
  ECopyRefused = class(Exception);
  TRefusing = class(TObject, IInterface)
  public
    Refs: Integer;
    function QueryInterface({$ifdef FPC}constref{$else}const{$endif} IID: TGUID; out Obj): HResult; {$ifdef MSWINDOWS}stdcall{$else}cdecl{$endif};
    function _AddRef: Integer; {$ifdef MSWINDOWS}stdcall{$else}cdecl{$endif};
    function _Release: Integer; {$ifdef MSWINDOWS}stdcall{$else}cdecl{$endif};
  end;
  TPair = record
    First, Second: IInterface;
  end;
  TStaticPair = array[0..1] of IInterface;
  TProbeVariant = class(TCustomVariantType)
  public
    procedure Clear(var V: TVarData); override;
    procedure Copy(var Dest: TVarData; const Source: TVarData; const Indirect: Boolean); override;
  end;

var
  Calls, FailAt, Tokens, NextToken: Integer;
  TokenLive: array[1..128] of Boolean;
  DuplicateClear: Integer;
  VariantType: TProbeVariant;
  ThrowAfterWrite: Boolean;

procedure BeforeCopy;
begin
  Inc(Calls);
  If Calls=FailAt then
    raise ECopyRefused.Create('second copy refused');
end;

function TRefusing.QueryInterface({$ifdef FPC}constref{$else}const{$endif} IID: TGUID; out Obj): HResult; {$ifdef MSWINDOWS}stdcall{$else}cdecl{$endif};
begin
  Result:=E_NOINTERFACE;
end;

function TRefusing._AddRef: Integer; {$ifdef MSWINDOWS}stdcall{$else}cdecl{$endif};
begin
  BeforeCopy;
  Inc(Refs);
  Result:=Refs;
end;

function TRefusing._Release: Integer; {$ifdef MSWINDOWS}stdcall{$else}cdecl{$endif};
begin
  Dec(Refs);
  Result:=Refs;
end;

procedure TProbeVariant.Clear(var V: TVarData);
begin
  If V.VInteger>0 then begin
    If not TokenLive[V.VInteger] then
      Inc(DuplicateClear)
    else begin
      TokenLive[V.VInteger]:=False;
      Dec(Tokens);
    end;
  end;
  V.VType:=varEmpty;
end;

procedure TProbeVariant.Copy(var Dest: TVarData; const Source: TVarData; const Indirect: Boolean);
begin
  If Indirect then
    RaiseInvalidOp;
  if not ThrowAfterWrite then BeforeCopy;
  Inc(NextToken);
  Inc(Tokens);
  TokenLive[NextToken]:=True;
  Dest.VType:=VarType;
  Dest.VInteger:=NextToken;
  if ThrowAfterWrite then BeforeCopy;
end;

procedure Probe(Kind, Operation: Integer);
var
  A,B: TArray<IInterface>;
  R,S: TArray<TPair>;
  P,Q: TArray<TStaticPair>;
  V,W: TArray<Variant>;
  Item: TRefusing;
  I, BeforeRefs, AfterRefs: Integer;
  Original: Pointer;
  Caught: Boolean;
  {$ifdef FPC}BeforeHeap,AfterHeap: TMMFragmentationStatus;{$endif}
begin
  FailAt:=0;
  Calls:=0;
  Item:=TRefusing.Create;
  case Kind of
    0: begin
      SetLength(A,4);
      for I:=0 to 3 do A[I]:=Item;
      B:=A;
      Original:=Pointer(A);
    end;
    1: begin
      SetLength(R,2);
      for I:=0 to 1 do begin R[I].First:=Item; R[I].Second:=Item; end;
      S:=R;
      Original:=Pointer(R);
    end;
    2: begin
      SetLength(P,2);
      for I:=0 to 1 do begin P[I][0]:=Item; P[I][1]:=Item; end;
      Q:=P;
      Original:=Pointer(P);
    end;
    3: begin
      SetLength(V,4);
      for I:=0 to 3 do begin
        Inc(NextToken);
        Inc(Tokens);
        TokenLive[NextToken]:=True;
        TVarData(V[I]).VType:=VariantType.VarType;
        TVarData(V[I]).VInteger:=NextToken;
      end;
      W:=V;
      Original:=Pointer(V);
    end;
  end;
  BeforeRefs:=Item.Refs+Tokens;
  {$ifdef FPC}BeforeHeap:=CurrentHeapFragmentationStatus;{$endif}
  Calls:=0;
  FailAt:=2;
  Caught:=False;
  try
    case Kind of
      0: case Operation of
        0: SetLength(A,8);
        1: A:=Copy(A);
        2: SetLength(A,2);
        3: A:=Copy(A,0,2);
      end;
      1: case Operation of
        0: SetLength(R,4);
        1: R:=Copy(R);
        2: SetLength(R,1);
        3: R:=Copy(R,0,1);
      end;
      2: case Operation of
        0: SetLength(P,4);
        1: P:=Copy(P);
        2: SetLength(P,1);
        3: P:=Copy(P,0,1);
      end;
      3: case Operation of
        0: SetLength(V,8);
        1: V:=Copy(V);
        2: SetLength(V,2);
        3: V:=Copy(V,0,2);
      end;
    end;
  except
    on ECopyRefused do Caught:=True;
  end;
  FailAt:=0;
  AfterRefs:=Item.Refs+Tokens;
  {$ifdef FPC}AfterHeap:=CurrentHeapFragmentationStatus;{$endif}
  If not Caught or (Calls<>2) then Halt(10);
  case Kind of
    0: If (Pointer(A)<>Original) or (Pointer(B)<>Original) or (Length(A)<>4) then Halt(11);
    1: If (Pointer(R)<>Original) or (Pointer(S)<>Original) or (Length(R)<>2) then Halt(12);
    2: If (Pointer(P)<>Original) or (Pointer(Q)<>Original) or (Length(P)<>2) then Halt(13);
    3: If (Pointer(V)<>Original) or (Pointer(W)<>Original) or (Length(V)<>4) then Halt(14);
  end;
  A:=nil; B:=nil; R:=nil; S:=nil; P:=nil; Q:=nil; V:=nil; W:=nil;
  Write('PROBE ',Kind,' ',Operation,' refs ',BeforeRefs,' ',AfterRefs,' leftover ',Item.Refs+Tokens,' duplicate ',DuplicateClear);
  {$ifdef FPC}
  Write(' live_delta ',Int64(AfterHeap.LiveSmallBytes+AfterHeap.LiveMediumBytes+AfterHeap.LiveLargeBytes)-
    Int64(BeforeHeap.LiveSmallBytes+BeforeHeap.LiveMediumBytes+BeforeHeap.LiveLargeBytes));
  If (BeforeHeap.Errors<>0) or (AfterHeap.Errors<>0) then Halt(15);
  {$ifdef EXPECT_L1_FIXED}
  If (Item.Refs+Tokens<>0) or (DuplicateClear<>0) then Halt(16);
  If AfterHeap.LiveSmallBytes+AfterHeap.LiveMediumBytes+AfterHeap.LiveLargeBytes<>
    BeforeHeap.LiveSmallBytes+BeforeHeap.LiveMediumBytes+BeforeHeap.LiveLargeBytes then Halt(17);
  {$endif}
  {$endif}
  WriteLn;
  Item.Free;
  // Baseline diagnostics use one case per process so leaks cannot contaminate another case.
end;

var Kind,Operation:Integer;
begin
  try
    raise ECopyRefused.Create('second copy refused');
  except
    on ECopyRefused do Calls:=0;
  end;
  VariantType:=TProbeVariant.Create;
  try
    if ParamCount=0 then begin
      ThrowAfterWrite:=False;
      for Kind:=0 to 3 do
        for Operation:=0 to 3 do Probe(Kind,Operation);
      ThrowAfterWrite:=True;
      for Operation:=0 to 3 do Probe(3,Operation);
    end else begin
      ThrowAfterWrite:=ParamStr(3)='after';
      Probe(StrToInt(ParamStr(1)),StrToInt(ParamStr(2)));
    end;
  finally
    VariantType.Free;
  end;
end.
