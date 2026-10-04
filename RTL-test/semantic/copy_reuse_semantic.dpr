program copy_reuse_semantic;
{$mode delphiunicode}
uses SysUtils;
var Checks,Reallocations:Integer;
    Original,Hooked:TMemoryManager;
    FailAllocation:Boolean;
procedure Check(B:Boolean;const What:UnicodeString);
begin
  Inc(Checks);
  if not B then begin WriteLn('FAIL ',What);Halt(1);end;
end;
function CheckedGetMem(Size:PtrUInt):Pointer;
begin
  if FailAllocation then begin
    FailAllocation:=False;
    raise EOutOfMemory.Create('injected allocation failure');
  end;
  Result:=Original.GetMem(Size);
end;
function CheckedRealloc(var P:Pointer;Size:PtrUInt):Pointer;
begin
  Inc(Reallocations);
  if FailAllocation then begin
    FailAllocation:=False;
    raise EOutOfMemory.Create('injected reallocation failure');
  end;
  Result:=Original.ReallocMem(P,Size);
end;
function ExpectedU(const S:UnicodeString;Index,Count:Integer):UnicodeString;
var I:Integer;
begin
  Result:='';
  if Index<1 then Index:=1;
  if Count>Length(S)-Index+1 then Count:=Length(S)-Index+1;
  for I:=0 to Count-1 do Result:=Result+S[Index+I];
end;
procedure Corpus;
var S,U,Held,E:UnicodeString;A,B,AHeld,AE:RawByteString;
    N,I,J,K:Integer;
begin
  for N:=0 to 48 do begin
    SetLength(S,N);SetLength(A,N);
    for K:=1 to N do begin
      S[K]:=UnicodeChar(K*257);A[K]:=AnsiChar(K);
      if (K and 7)=0 then begin S[K]:=#0;A[K]:=#0;end;
    end;
    SetCodePage(A,1251,False);
    for I:=-1 to N+2 do for J:=-1 to N+2 do begin
      E:=ExpectedU(S,I,J);
      AE:=RawByteString(ExpectedU(UnicodeString(A),I,J));
      U:='old';B:='old';UniqueString(U);UniqueString(B);
      if (I and 1)=0 then begin Held:=U;AHeld:=B;end;
      U:=Copy(S,I,J);B:=Copy(A,I,J);
      Check((U=E) and (B=AE),'contents and clipped bounds');
      U:=Copy(S,I,J);B:=Copy(A,I,J);
      Check((U=E) and (B=AE),'reused contents');
      if Length(B)>0 then Check(StringCodePage(B)=1251,'copied codepage');
    end;
    U:=S;B:=A;
    U:=Copy(U,2,N);B:=Copy(B,2,N);
    Check((U=ExpectedU(S,2,N)) and (B=Copy(A,2,N)),'self assignment');
  end;
  U:='12345678';UniqueString(U);S:='ABCDEFGH';
  B:='12345678';UniqueString(B);A:='ABCDEFGH';SetCodePage(A,1252,False);
  SetCodePage(B,1251,False);
  Reallocations:=0;
  U:=Copy(S,1,8);B:=Copy(A,1,8);
  Check(Reallocations=0,'same-size unique Copy does not reallocate');
  Check((U=S) and (B=A) and (StringCodePage(B)=1252),'same-size codepage changes');
end;
procedure AllocationFailures;
var S,U,OldU:UnicodeString;A,B,OldA:RawByteString;Shared:Integer;Raised:Boolean;
begin
  S:='long unicode source';A:='long byte source';
  for Shared:=0 to 1 do begin
    U:='old unicode';B:='old byte';UniqueString(U);UniqueString(B);
    OldU:=U;OldA:=B;
    if Shared=0 then begin UniqueString(U);UniqueString(B);end;
    Raised:=False;FailAllocation:=True;
    try U:=Copy(S,1,Length(S));except on EOutOfMemory do Raised:=True;end;
    Check(Raised and (U=OldU),'Unicode result survives allocation failure');
    Raised:=False;FailAllocation:=True;
    try B:=Copy(A,1,Length(A));except on EOutOfMemory do Raised:=True;end;
    Check(Raised and (B=OldA),'Ansi result survives allocation failure');
  end;
end;
begin
  GetMemoryManager(Original);Hooked:=Original;
  Hooked.GetMem:=@CheckedGetMem;Hooked.ReallocMem:=@CheckedRealloc;
  SetMemoryManager(Hooked);
  try Corpus;AllocationFailures;
  finally SetMemoryManager(Original);end;
  WriteLn('COPY_REUSE_PASS',' checks=',Checks);
end.
