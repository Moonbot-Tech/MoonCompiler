program utf16_pos_semantic;
{$mode delphiunicode}
{$pointermath on}
{$R-}{$Q-}
uses {$ifdef MSWINDOWS}Windows,{$else}BaseUnix,{$endif} SysUtils, StrUtils;
var Checks: UInt64;
procedure Require(Value: Boolean; const Where: UnicodeString);
begin
  Inc(Checks);
  If not Value then
    raise Exception.Create(Where);
end;
function PosReference(const Needle, Haystack: UnicodeString; Offset: SizeInt): SizeInt;
var I, J: SizeInt;
begin
  Result := 0;
  If (Length(Needle) = 0) or (Offset <= 0) then
    Exit;
  for I := Offset to Length(Haystack) - Length(Needle) + 1 do
  begin
    J := 1;
    while (J <= Length(Needle)) and (Needle[J] = Haystack[I + J - 1]) do
      Inc(J);
    If J > Length(Needle) then
      Exit(I);
  end;
end;
procedure PosChecks;
var S, N: UnicodeString;
    Round, I, K, Offset, Len: Integer;
    Seed: Cardinal;
begin
  Seed := 123456789;
  for Round := 0 to 2047 do
  begin
    SetLength(S, Round mod 97);
    for I := 1 to Length(S) do
    begin
      Seed := Seed * 1664525 + 1013904223;
      If Round mod 4 = 0 then
        S[I] := WideChar(Seed shr 16)
      else
        S[I] := WideChar((Seed shr 28) mod 4);
    end;
    for K := 0 to 8 do
    begin
      Len := (Round + K) mod 17;
      N := Copy(S, 1 + ((Round * K) mod 97), Len);
      If K and 1 <> 0 then
        N := N + WideChar($7777);
      for Offset := -2 to Length(S) + 2 do
        Require(Pos(N,S,Offset)=PosReference(N,S,Offset),
          'Pos round=' + IntToStr(Round) + ' key=' + IntToStr(K) + ' offset=' + IntToStr(Offset));
    end;
  end;
end;
function GuardMap: PByte;
{$ifdef MSWINDOWS}
var OldProtect: DWORD;
{$endif}
begin
  {$ifdef MSWINDOWS}
  Result := VirtualAlloc(nil,3*4096,MEM_RESERVE or MEM_COMMIT,PAGE_NOACCESS);
  Require(Result<>nil,'text guard allocation');
  Require(VirtualProtect(Result+4096,4096,PAGE_READWRITE,OldProtect),'text guard middle page');
  {$else}
  Result := fpMMap(nil,3*4096,PROT_NONE,MAP_PRIVATE or MAP_ANONYMOUS,-1,0);
  Require(Result<>Pointer(-1),'text guard allocation');
  Require(fpMProtect(Result+4096,4096,PROT_READ or PROT_WRITE)=0,'text guard middle page');
  {$endif}
end;
procedure ReleaseGuardMap(P: PByte);
begin
  {$ifdef MSWINDOWS}
  Require(VirtualFree(P,0,MEM_RELEASE),'text guard release');
  {$else}
  Require(fpMUnmap(P,3*4096)=0,'text guard release');
  {$endif}
end;

procedure Compare(const N,S: UnicodeString; Offset: SizeInt);
var E,A: SizeInt;
begin
  E:=PosReference(N,S,Offset);
  A:=Pos(N,S,Offset);
  Require(A=E,Format('shape %d/%d off %d: %d expected %d',[Length(N),Length(S),Offset,A,E]));
  Require(PosEx(N,S,Offset)=E,'PosEx delegates to bounded UTF16 search');
  if Length(N)=1 then Require(Pos(N[1],S,Offset)=E,'UnicodeChar overload');
end;
procedure Wrappers;
type TPos = function(const N,S: UnicodeString; Offset: SizeInt): SizeInt;
     TWPos = function(const N,S: WideString; Offset: SizeInt): SizeInt;
var P: TPos;
    WP: TWPos;
    W,N: WideString;
    U: UnicodeString;
    A: RawByteString;
    S: ShortString;
    I: SizeInt;
begin
  P:=@System.Pos;
  WP:=@System.Pos;
  Require(P('aba','abababa',2)=3,'Unicode public default calling convention');
  W:='A'#0#$0416#$D800'aba';
  N:=#$D800'a';
  for I:=-1 to Length(W)+1 do begin
    Require(WP(N,W,I)=PosReference(UnicodeString(N),UnicodeString(W),I),'Wide public overload');
    Require(Pos(WideChar($D800),W,I)=PosReference(#$D800,UnicodeString(W),I),'WideChar overload');
  end;
  U:='abababa'; A:='aba'; S:='aba';
  Require(Pos(A,U,2)=3,'RawByte to Unicode');
  Require(Pos(S,U,2)=3,'ShortString to Unicode');
  Require(Pos(U,RawByteString('xabababa'),2)=2,'Unicode to RawByte');
  W:='abababa';
  Require(Pos(A,W,2)=3,'RawByte to Wide');
  Require(Pos(S,W,2)=3,'ShortString to Wide');
end;
procedure Guards;
var MS,MN,PS,PN: PByte; S,N: UnicodeString;
    SL,NL,I,J,Mode,Offset: Integer;
begin
  MS:=GuardMap; MN:=GuardMap;
  try
    for SL:=0 to 160 do
      for NL:=0 to SL+1 do begin
        PS:=MS+8192-SL*2; PN:=MN+8192-NL*2;
        FillChar((PS-24)^,24,0); FillChar((PN-24)^,24,0);
        PSizeInt(PS-16)^:=-1; PSizeInt(PN-16)^:=-1;
        PSizeInt(PS-8)^:=SL; PSizeInt(PN-8)^:=NL;
        Pointer(S):=PS; Pointer(N):=PN;
        if SL=0 then Pointer(S):=nil;
        if NL=0 then Pointer(N):=nil;
        for Mode:=0 to 3 do begin
          for I:=0 to SL-1 do PWord(PS+I*2)^:=$d800+((I+Mode) mod 3);
          for I:=0 to NL-1 do PWord(PN+I*2)^:=$d800+(I mod 3);
          if (Mode=1) and (NL>0) then PWord(PN+(NL-1)*2)^:=$ffff;
          if (Mode=2) and (NL>1) then PWord(PN+(NL div 2)*2)^:=0;
          if Mode=3 then begin
            for I:=0 to SL-1 do PWord(PS+I*2)^:=$4141;
            for I:=0 to NL-1 do PWord(PN+I*2)^:=$4141;
            if NL>2 then PWord(PN+(NL div 2)*2)^:=$4241;
          end;
          for Offset:=-1 to SL+1 do Compare(N,S,Offset);
        end;
        Pointer(S):=nil; Pointer(N):=nil;
      end;
  finally
    Pointer(S):=nil; Pointer(N):=nil;
    ReleaseGuardMap(MN); ReleaseGuardMap(MS);
  end;
end;
{$ifdef MSWINDOWS}
procedure WideGuards;
var MS,MN,PS,PN: PByte;
    S,N: WideString;
    SL,NL,I,Offset,Expected: SizeInt;
begin
  MS:=GuardMap; MN:=GuardMap;
  try
    for SL:=1 to 96 do
      for NL:=1 to SL+1 do begin
        PS:=MS+8192-SL*2; PN:=MN+8192-NL*2;
        PLongWord(PS-4)^:=SL*2; PLongWord(PN-4)^:=NL*2;
        for I:=0 to SL-1 do PWord(PS+I*2)^:=Ord('a');
        for I:=0 to NL-1 do PWord(PN+I*2)^:=Ord('a');
        PWord(PS+(SL-1)*2)^:=$D800;
        PWord(PN+(NL-1)*2)^:=$D800;
        Pointer(S):=PS; Pointer(N):=PN;
        for Offset:=-1 to SL+1 do begin
          Expected:=0;
          if (Offset>0) and (Offset<=SL-NL+1) then Expected:=SL-NL+1;
          Require(Pos(N,S,Offset)=Expected,'guarded BSTR substring');
          Expected:=0;
          if (Offset>0) and (Offset<=SL) then Expected:=SL;
          Require(Pos(WideChar($D800),S,Offset)=Expected,'guarded BSTR char');
        end;
        Pointer(S):=nil; Pointer(N):=nil;
      end;
  finally
    Pointer(S):=nil; Pointer(N):=nil;
    ReleaseGuardMap(MN); ReleaseGuardMap(MS);
  end;
end;
{$endif}
begin
  Compare(#$4142,#$4200#$0041,1);
  Compare('a','a',High(SizeInt));
  Compare('a','a',Low(SizeInt));
  Wrappers;
  PosChecks;
  Guards;
  {$ifdef MSWINDOWS}WideGuards;{$endif}
  WriteLn('UTF16_POS_PASS',' checks=',Checks);
end.
