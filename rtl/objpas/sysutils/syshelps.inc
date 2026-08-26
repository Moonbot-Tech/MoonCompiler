{%MainUnit sysutils.pp}
{ ---------------------------------------------------------------------
  TStringHelper
  ---------------------------------------------------------------------}

{$ifdef IS_ANSISTRINGHELPER}
type
  TTrimMode = {$push} {$scopedenums on} (Left, Right, Both) {$pop};

{ Public string-helper ranges use clamp/no-match semantics.  Normalize them
  before any 1-based index or pointer is formed, and use subtraction rather
  than Start+Count so hostile SizeInt values cannot wrap. }
function NormalizeForwardStringSpan(Total: SizeInt;
  var StartIndex, ACount: SizeInt): Boolean; inline;
var
  Remaining: SizeInt;
begin
  if (StartIndex<0) or (StartIndex>Total) or (ACount<=0) then
    Exit(False);
  Remaining:=Total-StartIndex;
  if ACount>Remaining then
    ACount:=Remaining;
  Result:=ACount>0;
end;

function NormalizeReverseStringSpan(Total: SizeInt;
  var StartIndex, ACount: SizeInt): Boolean; inline;
begin
  if (Total<=0) or (StartIndex<0) or (ACount<=0) then
    Exit(False);
  if StartIndex>=Total then
    StartIndex:=Total-1;
  if ACount>StartIndex+1 then
    ACount:=StartIndex+1;
  Result:=True;
end;
{$endif}

{$IF not defined(IS_SHORTSTRINGHELPER) and not defined(IS_UNICODESTRINGHELPER)}
// Doubles with (wide/ansi)string...
Function HaveChar(AChar : TStringChar; const AList: array of TStringChar) : Boolean; inline;

Var
  I : SizeInt;

begin
  I:=0;
  while (I<=High(AList)) and (AList[I]<>AChar) do
    Inc(I);
  Result:=I<=High(AList);
end;

{ case-insensitive range equality with the CompareText ASCII fold - lets the
  IgnoreCase facades compare in place instead of building Copy/LowerCase
  temporaries per call }
Function SameTextRange(P1,P2 : PTStringChar; L : SizeInt) : Boolean;

Var
  C1,C2 : Cardinal;

begin
  Result:=False;
  While L>0 do
    begin
    C1:=Ord(P1^);
    C2:=Ord(P2^);
    if C1<>C2 then
      begin
      if (C1>=Ord('a')) and (C1<=Ord('z')) then
        Dec(C1,32);
      if (C2>=Ord('a')) and (C2<=Ord('z')) then
        Dec(C2,32);
      if C1<>C2 then
        exit;
      end;
    Inc(P1);
    Inc(P2);
    Dec(L);
    end;
  Result:=True;
end;

{ ordinal slice comparison for managed strings: pointer+length, an
  embedded NUL is ordinary data, equal prefixes tie-break on length -
  replaces the NUL-terminated Str(L)Comp facades, which stopped at the
  first #0 and called shorter/longer prefixes equal }
Function CompareSlices(P1 : PTStringChar; L1 : SizeInt; P2 : PTStringChar; L2 : SizeInt) : Integer;

Var
  L : SizeInt;

begin
  L:=L1;
  if L2<L then
    L:=L2;
  Result:=0;
  if L>0 then
    if SizeOf(TStringChar)=1 then
      Result:=CompareByte(P1^,P2^,L)
    else
      Result:=CompareWord(P1^,P2^,L);
  if Result=0 then
    Result:=Ord(L1>L2)-Ord(L1<L2);
end;

{ the same slice walk with the CompareText ASCII fold, returning order -
  the coIgnoreCase ranged facade compares in place through it }
Function CompareTextSlices(P1,P2 : PTStringChar; L : SizeInt) : Integer;

Var
  C1,C2 : Cardinal;

begin
  Result:=0;
  While L>0 do
    begin
    C1:=Ord(P1^);
    C2:=Ord(P2^);
    if C1<>C2 then
      begin
      if (C1>=Ord('a')) and (C1<=Ord('z')) then
        Dec(C1,32);
      if (C2>=Ord('a')) and (C2<=Ord('z')) then
        Dec(C2,32);
      if C1<>C2 then
        exit(Integer(C1)-Integer(C2));
      end;
    Inc(P1);
    Inc(P2);
    Dec(L);
    end;
end;
{$ENDIF}

function Trim(const S: TStringType; const ATrimChars: array of TStringChar; mode: TTrimMode): TStringType;

var
  start, ed, ns: SizeInt;

begin
  start := 1;
  ns := System.Length(S);
  ed := ns;
  if mode <> TTrimMode.Right then
    while (start <= ed) and HaveChar(S[start], ATrimChars) do
      inc(start);
  if mode <> TTrimMode.Left then
    while (start <= ed) and HaveChar(S[ed], ATrimChars) do
      dec(ed);
  if (start = 1) and (ed = ns) then
    Result := S
  else
    Result := Copy(S, start, ed - start + 1);
end;

function TStringHelper.GetChar(AIndex: SizeInt): TStringChar;
begin
  Result:=Self[AIndex+1];
end;


function TStringHelper.GetLength: SizeInt;

begin
  Result:=System.Length(Self);
end;


class function TStringHelper.Compare(const A: TStringType; const B: TStringType): Integer;
begin
  { the old form compared System.Length(B) characters and called a
    shorter/longer prefix equal; measured DCC64 tie-breaks on length }
  Result:=Compare(A,B,[]);
end;


class function TStringHelper.Compare(const A: TStringType; const B: TStringType;
  IgnoreCase: Boolean): Integer; //deprecated 'Use same with TCompareOptions';
begin
  if IgnoreCase then
    Result:=Compare(A,B,[coIgnoreCase])
  else
    Result:=Compare(A,B,[]);
end;


class function TStringHelper.Compare(const A: TStringType; const B: TStringType;
  Options: TCompareOptions): Integer;
var
  LenA,LenB : integer;
begin
  LenB:=System.Length(B);
  LenA:=System.Length(A);
  if LenB=LenA then
    Result:=Compare(A,0,B,0,LenB,Options)
  else if (LenB>LenA) then
    begin
    Result:=Compare(A,0,B,0,LenA,Options);
    if Result=0 then // over the length of A, both are equal.
      Result:=-1;
    end
  else // lenB<LenA
    begin
    Result:=Compare(A,0,B,0,LenB,Options);
    if Result=0 then     // Over the length of B, both are equal
       Result:=1;
    end;
end;


class function TStringHelper.Compare(const A: TStringType; IndexA: SizeInt;
  const B: TStringType; IndexB: SizeInt; ALen: SizeInt): Integer;
begin
  Result:=Compare(A,IndexA,B,IndexB,ALen,[]);
end;


class function TStringHelper.Compare(const A: TStringType; IndexA: SizeInt;
  const B: TStringType; IndexB: SizeInt; ALen: SizeInt; IgnoreCase: Boolean
  ): Integer; //deprecated 'Use same with TCompareOptions';
begin
  if IgnoreCase then
    Result:=Compare(A,IndexA,B,IndexB,ALen,[coIgnoreCase])
  else
    Result:=Compare(A,IndexA,B,IndexB,ALen,[])
end;


class function TStringHelper.Compare(const A: TStringType; IndexA: SizeInt;
  const B: TStringType; IndexB: SizeInt; ALen: SizeInt; Options: TCompareOptions
  ): Integer;

Var
  L : SizeInt;

begin
  { a negative index or length is an empty range - the old code formed a
    pointer before the string (measured DCC64 reads garbage there, a
    defect, not a canvas); the clamp of ALen to the remainders is the
    existing contract }
  If IndexA<0 then
    IndexA:=system.Length(A);
  If IndexB<0 then
    IndexB:=system.Length(B);
  L:=ALen;
  If (L>system.Length(A)-IndexA) then
    L:=system.Length(A)-IndexA;
  If (L>system.Length(B)-IndexB) then
    L:=system.Length(B)-IndexB;
  If L<=0 then
    exit(0);
  if (coIgnoreCase in Options) then
    Result:=CompareTextSlices(PTStringChar(@A[IndexA+1]),PTStringChar(@B[IndexB+1]),L)
  else
    begin
    if SizeOf(TStringChar)=1 then
      Result:=CompareByte(A[IndexA+1],B[IndexB+1],L)
    else
      Result:=CompareWord(A[IndexA+1],B[IndexB+1],L);
    end;
end;


class function TStringHelper.CompareOrdinal(const A: TStringType; const B: TStringType
  ): Integer;

begin
{$IFDEF IS_SHORTSTRINGHELPER}
  Result:=CompareSlices(PTStringChar(@A[1]),System.Length(A),
    PTStringChar(@B[1]),System.Length(B));
{$ELSE}
  Result:=CompareSlices(PTStringChar(Pointer(A)),System.Length(A),
    PTStringChar(Pointer(B)),System.Length(B));
{$ENDIF}
end;


class function TStringHelper.CompareOrdinal(const A: TStringType; IndexA: SizeInt;
  const B: TStringType; IndexB: SizeInt; ALen: SizeInt): Integer;

Var
  LA,LB : SizeInt;

begin
  { proven slices before pointer formation: the old unclamped
    NUL-terminated StrLComp read past both strings for a large ALen and
    through a garbage pointer for a negative index (measured DCC64 does
    the same - a defect, not a canvas) }
  If IndexA<0 then
    IndexA:=system.Length(A);
  If IndexB<0 then
    IndexB:=system.Length(B);
  LA:=system.Length(A)-IndexA;
  If LA>ALen then
    LA:=ALen;
  If LA<0 then
    LA:=0;
  LB:=system.Length(B)-IndexB;
  If LB>ALen then
    LB:=ALen;
  If LB<0 then
    LB:=0;
  Result:=CompareSlices(PTStringChar(@A[IndexA+1]),LA,
    PTStringChar(@B[IndexB+1]),LB);
end;


class function TStringHelper.CompareText(const A: TStringType; const B: TStringType
  ): Integer;
begin
  Result:=SUT.CompareText(A,B);
end;


class function TStringHelper.Copy(const Str: TStringType): TStringType;
begin
  Result:=Str;
{$IFNDEF IS_SHORTSTRINGHELPER}
  UniqueString(Result);
{$ENDIF}
end;


class function TStringHelper.Create(AChar: TStringChar; ACount: SizeInt): TStringType;
begin
   Result:=StringOfChar(AChar,ACount);
end;


class function TStringHelper.Create(const AValue: array of TStringChar): TStringType;

begin
  Result:=Create(AValue,0,System.Length(AValue));
end;


class function TStringHelper.Create(const AValue: array of TStringChar;
  StartIndex: SizeInt; ALen: SizeInt): TStringType;
begin
  { the source span is proven before the Move: measured DCC64 reads
    garbage from around the array for a negative or oversized range (a
    defect); its negative-length empty result is the canvas }
  if (StartIndex<0) or (StartIndex>System.Length(AValue)) then
    exit('');
  if ALen>System.Length(AValue)-StartIndex then
    ALen:=System.Length(AValue)-StartIndex;
  if ALen<0 then
    ALen:=0;
  SetLength(Result,ALen);
  { a ShortString destination silently clamps to 255 - the Move must
    follow the actual length; the old byte count also copied only half
    of a wide payload }
  if System.Length(Result)<ALen then
    ALen:=System.Length(Result);
  if ALen>0 then
    Move(AValue[StartIndex],Result[1],ALen*SizeOf(TStringChar));
end;


class function TStringHelper.EndsText(const ASubText, AText: TStringType): Boolean;
var
  L, TextLength: SizeInt;
{$IF defined(IS_ANSISTRINGHELPER) or defined(IS_SHORTSTRINGHELPER)}
  SubTextUnicode, TextUnicode: UnicodeString;
{$ENDIF}
{$IFDEF IS_ANSISTRINGHELPER}
  SubTextCodePage, TextCodePage: TSystemCodePage;
{$ENDIF}
begin
  L:=System.Length(ASubText);
  TextLength:=System.Length(AText);
  if (L=0) or (L>TextLength) then
    Exit(False);
{$IFDEF IS_ANSISTRINGHELPER}
  SubTextCodePage:=StringCodePage(ASubText);
  if (SubTextCodePage=CP_ACP) or (SubTextCodePage=CP_OEMCP) or
     (SubTextCodePage=CP_NONE) then
    SubTextCodePage:=DefaultSystemCodePage;
  TextCodePage:=StringCodePage(AText);
  if (TextCodePage=CP_ACP) or (TextCodePage=CP_OEMCP) or
     (TextCodePage=CP_NONE) then
    TextCodePage:=DefaultSystemCodePage;
  widestringmanager.Ansi2UnicodeMoveProc(
    PTStringChar(Pointer(ASubText)),SubTextCodePage,SubTextUnicode,L);
  widestringmanager.Ansi2UnicodeMoveProc(
    PTStringChar(Pointer(AText))+TextLength-L,TextCodePage,TextUnicode,L);
  Result:=SUT.CompareText(TextUnicode,SubTextUnicode)=0;
{$ELSE}
{$IFDEF IS_SHORTSTRINGHELPER}
  widestringmanager.Ansi2UnicodeMoveProc(
    PTStringChar(@ASubText[1]),DefaultSystemCodePage,SubTextUnicode,L);
  widestringmanager.Ansi2UnicodeMoveProc(
    PTStringChar(@AText[1])+TextLength-L,DefaultSystemCodePage,TextUnicode,L);
  Result:=SUT.CompareText(TextUnicode,SubTextUnicode)=0;
{$ELSE}
  Result:=SameTextRange(PTStringChar(Pointer(AText))+TextLength-L,
    PTStringChar(Pointer(ASubText)),L);
{$ENDIF}
{$ENDIF}
end;


class function TStringHelper.Equals(const a: TStringType; const b: TStringType): Boolean;
begin
  Result:=A=B;
end;


class function TStringHelper.Format(const AFormat: TStringType;
  const args: array of const): TStringType;
begin
  Result:=SUT.Format(AFormat,Args);
end;


class function TStringHelper.IsNullOrEmpty(const AValue: TStringType): Boolean;
begin
  Result:=system.Length(AValue)=0;
end;


class function TStringHelper.IsNullOrWhiteSpace(const AValue: TStringType): Boolean;
const
  LWhiteSpace = [#0..' '];
var
  I: SizeInt;
begin
  for I:=1 to System.Length(AValue) do
    if not (AValue[I] in LWhiteSpace) then
      exit(False);
  Result:=True;
end;


class function TStringHelper.Join(const Separator: TStringType;
  const Values: array of const): TStringType;

Var
  SValues : Array of TStringType;
  I,L : SizeInt;
  S : TStringType;
  P : ^TVarRec;

begin
  L:=System.Length(Values);
  SetLength(SValues,L);
  Dec(L);
  for I:=0 to L do
    begin
    S:='';
    P:=@Values[I];
    Case P^.VType of
      vtInteger  : S:=IntToStr(P^.VInteger);
      vtBoolean  : S:=BoolToStr(P^.VBoolean, True);
      vtChar     : S:=P^.VChar;
      vtPChar    : S:= TStringType(P^.VPChar);
      {$ifndef FPUNONE}
      vtExtended : S:=FloatToStr(P^.VExtended^);
      {$endif}
      vtObject   : S:=TObject(P^.VObject).Classname;
      vtClass    : S:=P^.VClass.Classname;
      vtCurrency : S:=CurrToStr(P^.VCurrency^);
      vtVariant  : S:=(P^.VVariant^);
      vtInt64    : S:=IntToStr(PInt64(P^.VInt64)^);
      vtQword    : S:=IntToStr(PQWord(P^.VQword)^);
      vtWideChar     : S:=WideString(P^.VWideChar);
      vtPWideChar     : S:=WideString(P^.VPWideChar);
      vtUnicodeString : S:=UnicodeString(P^.VUnicodeString);
      vtAnsiString    : S:=Ansistring(P^.VAnsiString);
    else
      S:=Format('Unknown type: %d',[P^.VType]);
    end;
    SValues[I]:=S;
    end;
  Result:=Join(Separator,SValues);
end;


class function TStringHelper.Join(const Separator: TStringType;
  const Values: array of TStringType): TStringType;
begin
  Result:=Join(Separator,Values,0,System.Length(Values));
end;


class function TStringHelper.Join(const Separator: TStringType;
  const Values: array of TStringType; StartIndex: SizeInt; ACount: SizeInt): TStringType;
Var
  VLen,I,CountLim,NR,NSep,N : SizeInt;
  Rp: PTStringChar;
begin
  VLen:=System.Length(Values);
  If (ACount=0)  then
    Exit('');
  CountLim:=VLen-StartIndex;
  if ACount>CountLim then
    ACount:=CountLim;
  If (ACount<0) or (StartIndex>VLen) or (StartIndex<0) then
    raise ERangeError.Create(SRangeError);
  if ACount=1 then
    exit(Values[StartIndex]);
  NSep:=System.Length(Separator);
  NR:=(ACount-1)*NSep;
  for I:=StartIndex to StartIndex+ACount-1 do
    NR:=NR+System.Length(Values[I]);
  SetLength(Result,NR);
  Rp:=@Result[1];
  for I:=StartIndex to StartIndex+ACount-1 do
     begin
        if I>StartIndex then
          begin
            Move(separator[1],Rp^,NSep*sizeof(TStringChar));
            Rp:=Rp+NSep;
          end;
        N:=System.Length(Values[I]);
        Move(Values[I][1],Rp^,N*sizeof(TStringChar));
        Rp:=Rp+N;
     end;
end;


class function TStringHelper.LowerCase(const S: TStringType): TStringType;
begin
  Result:=SUT.Lowercase(S);
end;


class function TStringHelper.Parse(const AValue: Boolean): TStringType;
begin
  Result:=BoolToStr(AValue);
end;


class function TStringHelper.Parse(const AValue: Extended): TStringType;
begin
  Result:=FloatToStr(AValue);
end;


class function TStringHelper.Parse(const AValue: Int64): TStringType;
begin
  Result:=IntToStr(AValue);
end;


class function TStringHelper.Parse(const AValue: Integer): TStringType;
begin
  Result:=IntToStr(AValue);
end;


class function TStringHelper.ToBoolean(const S: TStringType): Boolean;
begin
  Result:=StrToBool(S);
end;


class function TStringHelper.ToDouble(const S: TStringType): Double;
begin
  Result:=StrToFloat(S);
end;


class function TStringHelper.ToExtended(const S: TStringType): Extended;
begin
  Result:=StrToFloat(S);
end;


class function TStringHelper.ToInt64(const S: TStringType): Int64;
begin
  Result:=StrToInt64(S);
end;


class function TStringHelper.ToInteger(const S: TStringType): Integer;
begin
  Result:=StrToInt(S);
end;


class function TStringHelper.ToSingle(const S: TStringType): Single;
begin
  Result:=StrToFloat(S);
end;


class function TStringHelper.UpperCase(const S: TStringType): TStringType;
begin
  Result:=SUT.Uppercase(S);
end;


function TStringHelper.CompareTo(const B: TStringType): Integer;
begin
  // Order is important
  { slice comparison: an embedded NUL is data (the old StrComp stopped at
    the first #0 - so does measured DCC64, a recorded divergence in favor
    of the managed-string contract); the sign matches DCC64 on NUL-free
    strings, length tie-break included }
{$IFDEF IS_SHORTSTRINGHELPER}
  Result:=CompareSlices(PTStringChar(@Self[1]),System.Length(Self),
    PTStringChar(@B[1]),System.Length(B));
{$ELSE}
  Result:=CompareSlices(PTStringChar(Pointer(Self)),System.Length(Self),
    PTStringChar(Pointer(B)),System.Length(B));
{$ENDIF}
end;

procedure TStringHelper.CopyTo(SourceIndex: SizeInt; var destination: array of TStringChar; DestinationIndex: SizeInt; ACount: SizeInt);

begin
  { both spans proven before pointer formation, keeping the no-throw
    contract: the old form never checked the source at all (measured
    DCC64 copies garbage from past the string) and a negative
    destination index or count slipped through the single sum check }
  if (SourceIndex<0) or (SourceIndex>Length) or
     (DestinationIndex<0) or (DestinationIndex>System.Length(Destination)) then
    exit;
  if ACount>Length-SourceIndex then
    ACount:=Length-SourceIndex;
  if ACount>System.Length(Destination)-DestinationIndex then
    ACount:=System.Length(Destination)-DestinationIndex;
  if ACount<=0 then
    exit;
  Move(Self[SourceIndex+1],Destination[DestinationIndex],ACount*SizeOf(TStringChar));
end;

function TStringHelper.Contains(const AValue: TStringType; IgnoreCase: Boolean = False): Boolean;
Var
  L,NS,I,Remain,Ofs1,Ofs2 : SizeInt;
  PS,PV : PTStringChar;
  C1,C2 : TStringChar;
begin
  if not IgnoreCase then
    Exit(Pos(AValue,Self)>0);
  { scan in place with the ASCII fold instead of building two LowerCase
    copies per call; the fold class matches Pos(LowerCase,LowerCase) }
  L:=System.Length(AValue);
  NS:=System.Length(Self);
  if (L=0) or (L>NS) then
    Exit(False);
{$IFDEF IS_SHORTSTRINGHELPER}
  PS:=PTStringChar(@Self[1]);
  PV:=PTStringChar(@AValue[1]);
{$ELSE}
  PS:=PTStringChar(Pointer(Self));
  PV:=PTStringChar(Pointer(AValue));
{$ENDIF}
  C1:=PV^;
  C2:=C1;
  if (C2>='a') and (C2<='z') then
    Dec(C2,Ord('a')-Ord('A'))
  else if (C2>='A') and (C2<='Z') then
    Inc(C2,Ord('a')-Ord('A'));
  I:=0;
  while I<=NS-L do
    begin
    Remain:=NS-L-I+1;
    Ofs1:=IndexChar((PS+I)^,Remain,C1);
    if C2<>C1 then
      begin
      Ofs2:=IndexChar((PS+I)^,Remain,C2);
      if (Ofs1<0) or ((Ofs2>=0) and (Ofs2<Ofs1)) then
        Ofs1:=Ofs2;
      end;
    if Ofs1<0 then
      Exit(False);
    Inc(I,Ofs1);
    if SameTextRange(PS+I,PV,L) then
      Exit(True);
    Inc(I);
    end;
  Result:=False;
end;

function TStringHelper.CountChar(const C: TStringChar): SizeInt;

Var
  S : TStringChar;
begin
  Result:=0;
  For S in Self do
    if (S=C) then
      Inc(Result);
end;


function TStringHelper.DeQuotedString: TStringType;
begin
  Result:=DeQuotedString('''');
end;


function TStringHelper.DeQuotedString(const AQuoteChar: TStringChar): TStringType;

var
  L,I : SizeInt;
  Res : Array of TStringChar;
  PS,PD : PTStringChar;
  IsQuote : Boolean;

begin
  L:=System.Length(Self);
  if (L<2) or Not ((Self[1]=AQuoteChar) and (Self[L]=AQuoteChar)) then
    Exit(Self);
  SetLength(Res,L);
  IsQuote:=False;
  PS:=@Self[2];
  PD:=@Res[0];
  For I:=2 to L-1 do
    begin
    if (PS^=AQuoteChar) then
      begin
      IsQuote:=Not IsQuote;
      if Not IsQuote then
        begin
        PD^:=PS^;
        Inc(PD);
        end;
      end
    else
      begin
      if IsQuote then
        IsQuote:=false;
      PD^:=PS^;
      Inc(PD);
      end;
    Inc(PS);
    end;
  SetString(Result,@Res[0],PD-@Res[0]);
end;


function TStringHelper.EndsWith(const AValue: TStringType): Boolean;
begin
  Result:=EndsWith(AValue,False);
end;


function TStringHelper.EndsWith(const AValue: TStringType; IgnoreCase: Boolean): Boolean;

Var
  L,NS : SizeInt;

begin
  L:=system.Length(AVAlue);
  NS:=System.Length(Self);
  Result:=L<=NS;
  if Result then
    if IgnoreCase then
{$IFDEF IS_SHORTSTRINGHELPER}
      Result:=SameTextRange(PTStringChar(@Self[1])+(NS-L),PTStringChar(@AValue[1]),L)
{$ELSE}
      Result:=SameTextRange(PTStringChar(Pointer(Self))+(NS-L),PTStringChar(Pointer(AValue)),L)
{$ENDIF}
    else
{$IFDEF IS_SHORTSTRINGHELPER}
      Result:=CompareByte(PTStringChar(@Self[1])[NS-L],PTStringChar(@AValue[1])^,L*sizeof(TStringChar))=0;
{$ELSE}
      Result:=CompareByte(PTStringChar(Pointer(Self))[NS-L],PTStringChar(Pointer(AValue))^,L*sizeof(TStringChar))=0;
{$ENDIF}
end;


function TStringHelper.Equals(const AValue: TStringType; IgnoreCase: Boolean = False): Boolean;

begin
  if IgnoreCase then
    Result:=SameText(Self,aValue)
  else
    Result:=(Self=AValue);
end;


function TStringHelper.Format(const args: array of const): TStringType;

begin
  Result:=Format(Self,Args);
end;


function TStringHelper.GetHashCode: Integer;

// Taken from contnrs, fphash
var
  P,pmax : PTStringChar;
begin
{$push}
{$Q-}
  Result:=0;
  {$IFDEF IS_SHORTSTRINGHELPER}
  P:=PTStringChar(@Self[1]);
  {$ELSE}
  P:=PTStringChar(Self);
  {$ENDIF}
  pmax:=p+length;
  while (p<pmax) do
    begin
    Result:=LongWord(LongInt(Result shl 5) - LongInt(Result)) xor LongWord(P^);
    Inc(p);
    end;
{$pop}
end;


function TStringHelper.IndexOf(AValue: TStringChar): SizeInt;
begin
  Result:=IndexOf(AValue,0,Length);
end;


function TStringHelper.IndexOf(const AValue: TStringType): SizeInt;
begin
  Result:=IndexOf(AValue,0,Length);
end;


function TStringHelper.IndexOf(AValue: TStringChar; StartIndex: SizeInt): SizeInt;
begin
  Result:=IndexOf(AValue,StartIndex,Length);
end;


function TStringHelper.IndexOf(const AValue: TStringType; StartIndex: SizeInt
  ): SizeInt;
begin
  Result:=IndexOf(AValue,StartIndex,Length);
end;


function TStringHelper.IndexOf(AValue: TStringChar; StartIndex: SizeInt;
  ACount: SizeInt): SizeInt;
begin
  if not NormalizeForwardStringSpan(System.Length(Self),StartIndex,ACount) then
    Exit(-1);
  // pointer casts are to access self as 0 based index!
  {$IFDEF IS_SHORTSTRINGHELPER}
  Result:=IndexChar(PTStringChar(@self[1])[StartIndex],ACount,AValue);
  {$ELSE}
  Result:=IndexChar(PTStringChar(Pointer(self))[StartIndex],ACount,AValue);
  {$ENDIF}
  if Result>=0 then
    Result:=Result+StartIndex;
end;


function TStringHelper.IndexOf(const AValue: TStringType; StartIndex: SizeInt;
  ACount: SizeInt): SizeInt;

Var
  CountLim,NV,Ofs : SizeInt;
  SP,SE : PTStringChar;

begin
  if not NormalizeForwardStringSpan(System.Length(Self),StartIndex,ACount) then
    Exit(-1);
  CountLim:=System.Length(Self)-StartIndex;
{$IFNDEF IS_SHORTSTRINGHELPER}
  { a search that runs to the end of the string is exactly Pos, whose
    vectorized scan beats the generic loop below }
  if ACount=CountLim then
    Exit(System.Pos(AValue,Self,StartIndex+1)-1);
{$ENDIF}
  NV:=System.Length(AValue);
  if (NV>0) and (ACount>=NV) then
    begin
{$IFDEF IS_SHORTSTRINGHELPER}
      SP:=PTStringChar(@Self[1])+StartIndex;
{$ELSE}
      SP:=PTStringChar(Pointer(Self))+StartIndex;
{$ENDIF}
      SE:=SP+ACount-NV+1;
      repeat
        {$IFDEF IS_SHORTSTRINGHELPER}
        Ofs:=IndexChar(SP^,SE-SP,PTStringChar(@AValue[1])[0]);
        {$ELSE}
        Ofs:=IndexChar(SP^,SE-SP,PTStringChar(Pointer(AValue))[0]);
        {$ENDIF}
        if Ofs<0 then
          Break;
        SP:=SP+Ofs+1;
        {$IFDEF IS_SHORTSTRINGHELPER}
        if CompareByte(SP^,PTStringChar(@AValue[1])[1],(NV-1)*sizeof(TStringChar))=0 then
          Exit(SP-PTStringChar(@Self[1])-1);
        {$ELSE}
        if CompareByte(SP^,PTStringChar(Pointer(AValue))[1],(NV-1)*sizeof(TStringChar))=0 then
          Exit(SP-PTStringChar(Pointer(Self))-1);
        {$ENDIF}
      until false;
    end;
  Result:=-1;
end;

function TStringHelper.IndexOfUnQuoted(const AValue: TStringType; StartQuote,
  EndQuote: TStringChar; StartIndex: SizeInt = 0): SizeInt;

Var
  LV : SizeInt;

  Function MatchAt(I : SizeInt) : Boolean ; Inline;

  Var
    J : SizeInt;

  begin
    J:=1;
    Repeat
      Result:=(Self[I+J-1]=AValue[j]);
      Inc(J);
    Until (Not Result) or (J>LV);
  end;

Var
  I,L,Q,SpanCount: SizeInt;

begin
  Result:=-1;
  LV:=system.Length(AValue);
  { an empty needle never matches; without this gate MatchAt read
    AValue[1] past an empty string }
  if LV=0 then
    exit;
  SpanCount:=Length;
  if not NormalizeForwardStringSpan(Length,StartIndex,SpanCount) or
     (LV>SpanCount) then
    Exit;
  L:=StartIndex+SpanCount-LV+1;
  I:=StartIndex+1;
  Q:=0;
  if StartQuote=EndQuote then
    begin
    While (Result=-1) and (I<=L) do
      begin
      if (Self[I]=StartQuote) then
        Q:=1-Q;
      if (Q=0) and MatchAt(i) then
        Result:=I-1;
      Inc(I);
      end;
    end
  else
    begin
    While (Result=-1) and (I<=L) do
      begin
      if Self[I]=StartQuote then
        Inc(Q)
      else if (Self[I]=EndQuote) and (Q>0) then
        Dec(Q);
      if (Q=0) and MatchAt(i) then
        Result:=I-1;
      Inc(I);
      end;
    end;
end;


function TStringHelper.IndexOfAny(const AnyOf: array of TStringChar): SizeInt;
begin
  Result:=IndexOfAny(AnyOf,0,Length);
end;


function TStringHelper.IndexOfAny(const AnyOf: array of TStringChar;
  StartIndex: SizeInt): SizeInt;
begin
  Result:=IndexOfAny(AnyOf,StartIndex,Length);
end;


function TStringHelper.IndexOfAny(const AnyOf: array of TStringChar;
  StartIndex: SizeInt; ACount: SizeInt): SizeInt;

Var
  i,L : SizeInt;

begin
  Result:=-1;
  if not NormalizeForwardStringSpan(Length,StartIndex,ACount) then
    Exit;
  I:=StartIndex+1;
  L:=StartIndex+ACount;
  While (Result=-1) and (I<=L) do
    begin
    if HaveChar(Self[i],AnyOf) then
      Result:=I-1;
    Inc(I);
    end;
end;

function TStringHelper.IndexOfAny(const AnyOf: array of TStringType): SizeInt;
begin
  Result:=IndexOfAny(AnyOf,0,Length);
end;

function TStringHelper.IndexOfAny(const AnyOf: array of TStringType;
  StartIndex: SizeInt): SizeInt;
begin
  { Let the ranged facade validate and clamp.  Length-StartIndex can itself
    overflow for a hostile negative start before that facade sees it. }
  Result:=IndexOfAny(AnyOf,StartIndex,Length);
end;

function TStringHelper.IndexOfAny(const AnyOf: array of TStringType;
  StartIndex: SizeInt; ACount: SizeInt): SizeInt;

Var
  M : SizeInt;

begin
  Result:=IndexOfAny(AnyOf,StartIndex,ACount,M);
end;

function TStringHelper.IndexOfAny(const AnyOf: array of TStringType;
  StartIndex: SizeInt; ACount: SizeInt; out AMatch: SizeInt): SizeInt;

Var
  L,I : SizeInt;

begin
  Result:=-1;
  For I:=0 to System.Length(AnyOf)-1 do
    begin
    L:=IndexOf(AnyOf[i],StartIndex,ACount);
    If (L>=0) and ((Result=-1) or (L<Result)) then
      begin
      Result:=L;
      AMatch:=I;
      end;
    end;
end;


function TStringHelper.IndexOfAnyUnquoted(const AnyOf: array of TStringChar;
  StartQuote, EndQuote: TStringChar): SizeInt;
begin
  Result:=IndexOfAnyUnquoted(AnyOf,StartQuote,EndQuote,0,Length);
end;


function TStringHelper.IndexOfAnyUnquoted(const AnyOf: array of TStringChar;
  StartQuote, EndQuote: TStringChar; StartIndex: SizeInt): SizeInt;
begin
  Result:=IndexOfAnyUnquoted(AnyOf,StartQuote,EndQuote,StartIndex,Length);
end;


function TStringHelper.IndexOfAnyUnquoted(const AnyOf: array of TStringChar;
  StartQuote, EndQuote: TStringChar; StartIndex: SizeInt; ACount: SizeInt): SizeInt;

Var
  I,L : SizeInt;
  Q : SizeInt;

begin
  Result:=-1;
  { the window is ACount characters, exactly as in IndexOfAny: the old
    StartIndex+ACount-1 top scanned one character short, so the start-only
    facades (ACount=Length) never saw the last character and a quoted
    Split lost a separator in the final position (measured DCC64 finds it) }
  if not NormalizeForwardStringSpan(Length,StartIndex,ACount) then
    Exit;
  L:=StartIndex+ACount;
  I:=StartIndex+1;
  Q:=0;
  if StartQuote=EndQuote then
    begin
    While (Result=-1) and (I<=L) do
      begin
      if (Self[I]=StartQuote) then
        Q:=1-Q;
      if (Q=0) and HaveChar(Self[i],AnyOf) then
        Result:=I-1;
      Inc(I);
      end;
    end
  else
  begin
    While (Result=-1) and (I<=L) do
      begin
      if Self[I]=StartQuote then
        Inc(Q)
      else if (Self[I]=EndQuote) and (Q>0) then
        Dec(Q);
      if (Q=0) and HaveChar(Self[i],AnyOf) then
        Result:=I-1;
      Inc(I);
      end;
    end;

end;

function TStringHelper.IndexOfAnyUnquoted(const AnyOf: array of TStringType;
  StartQuote, EndQuote: TStringChar; StartIndex: SizeInt; out Matched: SizeInt
  ): SizeInt;

Var
  L,I : SizeInt;

begin
  Result:=-1;
  For I:=0 to System.Length(AnyOf)-1 do
    begin
    L:=IndexOfUnquoted(AnyOf[i],StartQuote,EndQuote,StartIndex);
    If (L>=0) and ((Result=-1) or (L<Result)) then
      begin
      Result:=L;
      Matched:=I;
      end;
    end;
end;


function TStringHelper.Insert(StartIndex: SizeInt; const AValue: TStringType
  ): TStringType;
begin
  system.Insert(AValue,Self,StartIndex+1);
  Result:=Self;
end;


function TStringHelper.IsDelimiter(const Delimiters: TStringType; Index: SizeInt
  ): Boolean;
begin
  Result:=SUT.IsDelimiter(Delimiters,Self,Index+1);
end;


function TStringHelper.IsEmpty: Boolean;
begin
  Result:=(Length=0)
end;


function TStringHelper.LastDelimiter(const Delims: TStringType): SizeInt;
begin
  Result:=SUT.LastDelimiter(Delims,Self)-1;
end;


function TStringHelper.LastIndexOf(AValue: TStringChar): SizeInt;
begin
  Result:=LastIndexOf(AValue,Length-1,Length);
end;


function TStringHelper.LastIndexOf(const AValue: TStringType): SizeInt;
begin
  Result:=LastIndexOf(AValue,Length-1,Length);
end;


function TStringHelper.LastIndexOf(AValue: TStringChar; AStartIndex: SizeInt): SizeInt;
begin
  Result:=LastIndexOf(AValue,AStartIndex,Length);
end;


function TStringHelper.LastIndexOf(const AValue: TStringType; AStartIndex: SizeInt
  ): SizeInt;
begin
  Result:=LastIndexOf(AValue,AStartIndex,Length);
end;


function TStringHelper.LastIndexOf(AValue: TStringChar; AStartIndex: SizeInt;
  ACount: SizeInt): SizeInt;

Var
  Min, StartIndex, Count: SizeInt;

begin
  Result:=-1;
  StartIndex:=AStartIndex;
  Count:=ACount;
  if not NormalizeReverseStringSpan(Length,StartIndex,Count) then
    Exit;
  Result:=StartIndex+1;
  Min:=StartIndex-Count+2;
  While (Result>=Min) and (Self[Result]<>AValue) do
    Dec(Result);
  if Result<Min then
    Result:=-1
  else
    Result:=Result-1;
end;


function TStringHelper.LastIndexOf(const AValue: TStringType; AStartIndex: SizeInt; ACount: SizeInt): SizeInt;

var
  I,L,LS,M,StartIndex,Count : SizeInt;
  S : TStringType;
  P : PTStringChar;

begin
  Result:=-1;
  LS:=system.Length(Self);
  L:=system.Length(AValue);
  StartIndex:=AStartIndex;
  Count:=ACount;
  if (L=0) or not NormalizeReverseStringSpan(LS,StartIndex,Count) or
     (L>Count) then
    Exit;
{$IFDEF IS_SHORTSTRINGHELPER}
  P:=PTStringChar(@AValue[1]);
{$ELSE}
  P:=PTStringChar(AValue);
{$ENDIF}
  S:=Self;
  I:=StartIndex-L+2; // 1 based candidate start
  M:=StartIndex-Count+2; // 1 based window start
  while (Result=-1) and (I>=M) do
    begin
    { slice equality: the old NUL-terminated StrLComp truncated the
      comparison at an embedded #0 and reported false matches }
    if CompareSlices(PTStringChar(@S[I]),L,P,L)=0 then
      Result:=I-1;
    Dec(I);
    end;
end;


function TStringHelper.LastIndexOfAny(const AnyOf: array of TStringChar): SizeInt;
begin
  Result:=LastIndexOfAny(AnyOf,Length-1,Length);
end;


function TStringHelper.LastIndexOfAny(const AnyOf: array of TStringChar;
  AStartIndex: SizeInt): SizeInt;
begin
  Result:=LastIndexOfAny(AnyOf,AStartIndex,Length);
end;


function TStringHelper.LastIndexOfAny(const AnyOf: array of TStringChar;
  AStartIndex: SizeInt; ACount: SizeInt): SizeInt;

Var
  Min, StartIndex, Count : SizeInt;

begin
  Result:=-1;
  StartIndex:=AStartIndex;
  Count:=ACount;
  if not NormalizeReverseStringSpan(Length,StartIndex,Count) then
    Exit;
  Result:=StartIndex+1;
  Min:=StartIndex-Count+2;
  While (Result>=Min) and Not HaveChar(Self[Result],AnyOf) do
    Dec(Result);
  if Result<Min then
    Result:=-1
  else
    Result:=Result-1;
end;


function TStringHelper.PadLeft(ATotalWidth: SizeInt): TStringType;
begin
  Result:=PadLeft(ATotalWidth,' ');
end;


function TStringHelper.PadLeft(ATotalWidth: SizeInt; PaddingChar: TStringChar): TStringType;
Var
  L : SizeInt;

begin
  Result:=Self;
  L:=ATotalWidth-Length;
  If L>0 then
    Result:=StringOfChar(PaddingChar,L)+Result;
end;


function TStringHelper.PadRight(ATotalWidth: SizeInt): TStringType;
begin
  Result:=PadRight(ATotalWidth,' ');
end;


function TStringHelper.PadRight(ATotalWidth: SizeInt; PaddingChar: TStringChar
  ): TStringType;

Var
  L : SizeInt;

begin
  Result:=Self;
  L:=ATotalWidth-Length;
  If L>0 then
    Result:=Result+StringOfChar(PaddingChar,L);
end;


function TStringHelper.QuotedString: TStringType;
begin
  Result:=QuotedStr(Self);
end;


function TStringHelper.QuotedString(const AQuoteChar: TStringChar): TStringType;
begin
  Result:=AnsiQuotedStr(Self,AQuoteChar);
end;


function TStringHelper.Remove(StartIndex: SizeInt): TStringType;
begin
  Result:=Remove(StartIndex,Self.Length-StartIndex);
end;


function TStringHelper.Remove(StartIndex: SizeInt; ACount: SizeInt): TStringType;
begin
  Result:=Self;
  System.Delete(Result,StartIndex+1,ACount);
end;


function TStringHelper.Replace(OldChar: TStringChar; NewChar: TStringChar): TStringType;
begin
  Result:=Replace(OldChar,NewChar,[rfReplaceAll]);
end;


function TStringHelper.Replace(OldChar: TStringChar; NewChar: TStringChar;
  ReplaceFlags: TReplaceFlags): TStringType;
var
  Sp,Se,Rp : PTStringChar;
  Ofs : SizeInt;
begin
  if rfIgnoreCase in ReplaceFlags then
    exit(StringReplace(Self,OldChar,NewChar,ReplaceFlags));
{$IFDEF IS_SHORTSTRINGHELPER}
  Sp:=PTStringChar(@Self[1]);
{$ELSE}
  Sp:=PTStringChar(Pointer(Self));
{$ENDIF}
  Se:=Sp+System.Length(Self);
  Ofs:=IndexChar(Sp^,Se-Sp,OldChar);
  if Ofs<0 then
    exit(Self);
  SetLength(Result,Se-Sp);
{$IFDEF IS_SHORTSTRINGHELPER}
  Rp:=PTStringChar(@Result[1]);
{$ELSE}
  Rp:=PTStringChar(Pointer(Result));
{$ENDIF}
  repeat
    Move(Sp^,Rp^,Ofs*sizeof(TStringChar));
    Sp:=Sp+Ofs+1;
    Rp[Ofs]:=NewChar;
    Rp:=Rp+Ofs+1;
    if not (rfReplaceAll in ReplaceFlags) then
      break;
    { This loop can be removed entirely, but greatly speeds up replacing streaks of characters. }
    while (Sp<Se) and (Sp^=OldChar) do
      begin
        Rp^:=NewChar;
        Sp:=Sp+1;
        Rp:=Rp+1;
      end;
    Ofs:=IndexChar(Sp^,Se-Sp,OldChar);
  until Ofs<0;
  Move(Sp^,Rp^,(Se-Sp)*sizeof(TStringChar));
end;


function TStringHelper.Replace(const OldValue: TStringType; const NewValue: TStringType
  ): TStringType;
begin
  Result:=Replace(OldValue,NewValue,[rfReplaceAll]);
end;


function TStringHelper.Replace(const OldValue: TStringType; const NewValue: TStringType;
  ReplaceFlags: TReplaceFlags): TStringType;
begin
  Result:=StringReplace(Self,OldValue,NewValue,ReplaceFlags);
end;


function TStringHelper.Split(const Separators: array of TStringChar): TSHStringArray;
begin
  Result:=Split(Separators,#0,#0,Length+1,TStringSplitOptions.None);
end;


function TStringHelper.Split(const Separators: array of TStringChar; ACount: SizeInt
  ): TSHStringArray;
begin
  Result:=Split(Separators,#0,#0,ACount,TStringSplitOptions.None);
end;


function TStringHelper.Split(const Separators: array of TStringChar;
  Options: TStringSplitOptions): TSHStringArray;
begin
  Result:=Split(Separators,Length+1,Options);
end;


function TStringHelper.Split(const Separators: array of TStringChar; ACount: SizeInt;
  Options: TStringSplitOptions): TSHStringArray;
begin
  Result:=Split(Separators,#0,#0,ACount,Options);
end;


function TStringHelper.Split(const Separators: array of TStringType): TSHStringArray;
begin
  Result:=Split(Separators,Length+1);
end;


function TStringHelper.Split(const Separators: array of TStringType; ACount: SizeInt
  ): TSHStringArray;
begin
  Result:=Split(Separators,ACount,TStringSplitOptions.None);
end;


function TStringHelper.Split(const Separators: array of TStringType;
  Options: TStringSplitOptions): TSHStringArray;
begin
  Result:=Split(Separators,Length+1,Options);
end;


function TStringHelper.Split(const Separators: array of TStringType;
  ACount: SizeInt; Options: TStringSplitOptions): TSHStringArray;
begin
  Result:=Split(Separators,#0,#0,ACount,Options);
end;


function TStringHelper.Split(const Separators: array of TStringChar; AQuote: TStringChar
  ): TSHStringArray;
begin
  Result:=Split(Separators,AQuote,AQuote);
end;


function TStringHelper.Split(const Separators: array of TStringChar; AQuoteStart,
  AQuoteEnd: TStringChar): TSHStringArray;
begin
  Result:=Split(Separators,AQuoteStart,AQuoteEnd,TStringSplitOptions.None);
end;


function TStringHelper.Split(const Separators: array of TStringChar; AQuoteStart,
  AQuoteEnd: TStringChar; Options: TStringSplitOptions): TSHStringArray;
begin
  Result:=Split(Separators,AQuoteStart,AQuoteEnd,Length+1,Options);
end;


function TStringHelper.Split(const Separators: array of TStringChar; AQuoteStart,
  AQuoteEnd: TStringChar; ACount: SizeInt): TSHStringArray;
begin
  Result:=Split(Separators,AQuoteStart,AQuoteEnd,ACount,TStringSplitOptions.None);
end;


function TStringHelper.Split(const Separators: array of TStringChar; AQuoteStart,
  AQuoteEnd: TStringChar; ACount: SizeInt; Options: TStringSplitOptions): TSHStringArray;

  Function NextSep(StartIndex : SizeInt) : SizeInt;

  begin
    if (AQuoteStart<>#0) then
      Result:=Self.IndexOfAnyUnQuoted(Separators,AQuoteStart,AQuoteEnd,StartIndex)
    else
      Result:=Self.IndexOfAny(Separators,StartIndex);
  end;

  Procedure MaybeGrow(Curlen : SizeInt);

  begin
    if System.Length(Result)<=CurLen then
      SetLength(Result,System.Length(Result)+4+SizeInt(SizeUint(System.Length(Result)) div 4));
  end;

Var
  Sep,LastSep,Len : SizeInt;
{$IFNDEF IS_SHORTSTRINGHELPER}
  SrcLen,J : SizeInt;
  PS,PC,PE : PTStringChar;
  Hit : Boolean;
{$ENDIF}

begin
  if System.Length(Self)=0 then
    exit(nil);
{$IFNDEF IS_SHORTSTRINGHELPER}
  { Unquoted splitting: one pass over the text, the next separator found
    with the vectorized IndexChar for the common single-separator call,
    fields cut with SetString, the array grown by doubling (a dynarray
    realloc moves the string pointers without refcount traffic).  The
    general path below pays a nested call plus a HaveChar call for every
    scanned character and regrows in small steps. }
  if AQuoteStart=#0 then
    begin
      SrcLen:=System.Length(Self);
      PS:=PTStringChar(Pointer(Self));
      PE:=PS+SrcLen;
      { The overwhelmingly common no-hit case is already the complete result.
        Avoid allocating an eight-slot pointer array only to shrink it to one. }
      if ACount>=0 then
        begin
        if High(Separators)=0 then
          Sep:=IndexChar(PS^,SrcLen,Separators[0])
        else
          begin
          Sep:=-1;
          PC:=PS;
          while PC<PE do
            begin
            for J:=0 to High(Separators) do
              if PC^=Separators[J] then
                begin
                Sep:=PC-PS;
                Break;
                end;
            if Sep>=0 then
              Break;
            Inc(PC);
            end;
          end;
        if Sep<0 then
          begin
          SetLength(Result,1);
          SetString(Result[0],PS,SrcLen);
          exit;
          end;
        end;
      SetLength(Result,8);
      Len:=0;
      LastSep:=0;
      While ((ACount=0) or (Len<ACount)) and (LastSep<=SrcLen) do
        begin
        if High(Separators)=0 then
          begin
          Sep:=IndexChar((PS+LastSep)^,SrcLen-LastSep,Separators[0]);
          if Sep>=0 then
            Sep:=Sep+LastSep
          else
            Sep:=SrcLen;
          end
        else
          begin
          Sep:=SrcLen;
          PC:=PS+LastSep;
          while PC<PE do
            begin
            Hit:=False;
            for J:=0 to High(Separators) do
              if PC^=Separators[J] then
                begin
                Hit:=True;
                Break;
                end;
            if Hit then
              begin
              Sep:=PC-PS;
              Break;
              end;
            Inc(PC);
            end;
          end;
        If (Sep>LastSep) or (not (TStringSplitOptions.ExcludeEmpty=Options)) then
          begin
          if System.Length(Result)<=Len then
            SetLength(Result,System.Length(Result)*2);
          SetString(Result[Len],PS+LastSep,Sep-LastSep);
          Inc(Len);
          end;
        LastSep:=Sep+1;
        end;
      If (TStringSplitOptions.ExcludeLastEmpty=Options) then
        if (Len > 0) and (Result[Len-1] = '') then
          dec(Len);
      SetLength(Result,Len);
      exit;
    end;
{$ENDIF}
  Result:=nil;
  Len:=0;
  LastSep:=0;
  While ((ACount=0) or (Len<ACount)) and (LastSep<=System.Length(Self)) do
    begin
    Sep:=NextSep(LastSep);
    if Sep<0 then
      Sep:=System.Length(Self);
//    Writeln('Examining >',T,'< at pos ',LastSep,', till pos ',Sep);
    If (Sep>LastSep) or (not (TStringSplitOptions.ExcludeEmpty=Options)) then
      begin
      MaybeGrow(Len);
      Result[Len]:=SubString(LastSep,Sep-LastSep);
      Inc(Len);
      end;
    LastSep:=Sep+1;
    end;

  if (TStringSplitOptions.ExcludeLastEmpty=Options) then
    if (Len > 0) and (Result[Len-1] = '') then
      dec(Len);

  SetLength(Result,Len);
end;


function TStringHelper.Split(const Separators: array of TStringType; AQuote: TStringChar
  ): TSHStringArray;
begin
  Result:=SPlit(Separators,AQuote,AQuote);
end;


function TStringHelper.Split(const Separators: array of TStringType; AQuoteStart,
  AQuoteEnd: TStringChar): TSHStringArray;
begin
  Result:=SPlit(Separators,AQuoteStart,AQuoteEnd,Length+1,TStringSplitOptions.None);
end;


function TStringHelper.Split(const Separators: array of TStringType; AQuoteStart,
  AQuoteEnd: TStringChar; Options: TStringSplitOptions): TSHStringArray;
begin
  Result:=SPlit(Separators,AQuoteStart,AQuoteEnd,Length+1,Options);
end;


function TStringHelper.Split(const Separators: array of TStringType; AQuoteStart,
  AQuoteEnd: TStringChar; ACount: SizeInt): TSHStringArray;
begin
  Result:=SPlit(Separators,AQuoteStart,AQuoteEnd,ACount,TStringSplitOptions.None);
end;


function TStringHelper.Split(const Separators: array of TStringType; AQuoteStart,
  AQuoteEnd: TStringChar; ACount: SizeInt; Options: TStringSplitOptions): TSHStringArray;
Const
  BlockSize = 10;

  Function NextSep(StartIndex : SizeInt; out Match : SizeInt) : SizeInt;

  begin
    if (AQuoteStart<>#0) then
      Result:=Self.IndexOfAnyUnQuoted(Separators,AQuoteStart,AQuoteEnd,StartIndex,Match)
    else
      Result:=Self.IndexOfAny(Separators,StartIndex,Length,Match);
    if Result<>-1 then
  end;

  Procedure MaybeGrow(Curlen : SizeInt);

  begin
    if System.Length(Result)<=CurLen then
      SetLength(Result,System.Length(Result)+BlockSize);
  end;

Var
  Sep,LastSep,Len,Match : SizeInt;
  T : TStringType;

begin
  if System.Length(Self)=0 then
    exit(nil);
  SetLength(Result,BlockSize);
  Len:=0;
  LastSep:=0;
  Sep:=NextSep(0,Match);
  While (Sep<>-1) and ((ACount=0) or (Len<ACount)) do
    begin
    T:=SubString(LastSep,Sep-LastSep);
    If (T<>'') or (not (TStringSplitOptions.ExcludeEmpty=Options)) then
      begin
      MaybeGrow(Len);
      Result[Len]:=T;
      Inc(Len);
      end;
    LastSep:=Sep+System.Length(Separators[Match]);
    Sep:=NextSep(LastSep,Match);
    end;
  if (LastSep<=Length) and ((ACount=0) or (Len<ACount)) then
    begin
    T:=SubString(LastSep);
//    Writeln('Examining >',T,'< at pos,',LastSep,' till pos ',Sep);
    If (T<>'') or (not (TStringSplitOptions.ExcludeEmpty=Options)) then
      begin
      MaybeGrow(Len);
      Result[Len]:=T;
      Inc(Len);
      end;
    end;

  If (TStringSplitOptions.ExcludeLastEmpty=Options) then
    if (Len > 0) and (Result[Len-1] = '') then
      dec(Len);

  SetLength(Result,Len);
end;


function TStringHelper.StartsWith(const AValue: TStringType): Boolean;
begin
  Result:=StartsWith(AValue,False);
end;


function TStringHelper.StartsWith(const AValue: TStringType; IgnoreCase: Boolean
  ): Boolean;
Var
  L : SizeInt;

begin
  L:=System.Length(AValue);
  Result:=L<=System.Length(Self);
  if Result then
    if IgnoreCase then
{$IFDEF IS_SHORTSTRINGHELPER}
      Result:=SameTextRange(PTStringChar(@Self[1]),PTStringChar(@AValue[1]),L)
{$ELSE}
      Result:=SameTextRange(PTStringChar(Pointer(Self)),PTStringChar(Pointer(AValue)),L)
{$ENDIF}
    else
{$IFDEF IS_SHORTSTRINGHELPER}
      Result:=CompareByte(PTStringChar(@Self[1])^,PTStringChar(@AValue[1])^,L*sizeof(TStringChar))=0;
{$ELSE}
      Result:=CompareByte(PTStringChar(Pointer(Self))^,PTStringChar(Pointer(AValue))^,L*sizeof(TStringChar))=0;
{$ENDIF}
end;


function TStringHelper.Substring(AStartIndex: SizeInt): TStringType;
begin
  Result:=Self.SubString(AStartIndex,Self.Length-AStartIndex);
end;


function TStringHelper.Substring(AStartIndex: SizeInt; ALen: SizeInt): TStringType;
begin
  if (AStartIndex<=0) and (ALen>=System.Length(Self)) then
    Result:=Self
  else
    Result:=system.Copy(Self,AStartIndex+1,ALen);
end;


function TStringHelper.ToBoolean: Boolean;
begin
  Result:=StrToBool(Self);
end;


function TStringHelper.ToInteger: Integer;
begin
  Result:=StrToInt(Self);
end;


function TStringHelper.ToInt64: Int64;
begin
  Result:=StrToInt64(Self);
end;


function TStringHelper.ToSingle: Single;
begin
  Result:=StrToFLoat(Self);
end;


function TStringHelper.ToDouble: Double;
begin
  Result:=StrToFLoat(Self);
end;


function TStringHelper.ToExtended: Extended;
begin
  Result:=StrToFLoat(Self);
end;


function TStringHelper.ToCharArray: TCharArray;

begin
  Result:=ToCharArray(0,Self.Length);
end;


function TStringHelper.ToCharArray(AStartIndex: SizeInt; ALen: SizeInt
  ): TCharArray;

Var
  I : SizeInt;

begin
  { the source span is proven before element access: measured DCC64
    reads garbage for a negative or oversized range (a defect); its
    negative-length range error is the canvas, raised here by SetLength }
  if (AStartIndex<0) or (AStartIndex>Length) then
    AStartIndex:=Length;
  if ALen>Length-AStartIndex then
    ALen:=Length-AStartIndex;
  SetLength(Result,ALen);
  if SizeOf(TStringChar)=SizeOf(Char) then
    begin
    if ALen>0 then
      Move(Self[AStartIndex+1],Result[0],ALen*SizeOf(Char));
    end
  else
    For I:=0 to ALen-1 do
      Result[I]:=Self[AStartIndex+I+1];
end;


function TStringHelper.ToLower: TStringType;
begin
  Result:=LowerCase(Self);
end;


function TStringHelper.ToLowerInvariant: TStringType;
begin
  Result:=LowerCase(Self);
end;


function TStringHelper.ToUpper: TStringType;
begin
  Result:=UpperCase(Self);
end;


function TStringHelper.ToUpperInvariant: TStringType;
begin
  Result:=UpperCase(Self);
end;


function TStringHelper.Trim: TStringType;
begin
  Result:=SUT.Trim(Self);
end;


function TStringHelper.TrimLeft: TStringType;
begin
  Result:=SUT.TrimLeft(Self);
end;


function TStringHelper.TrimRight: TStringType;
begin
  Result:=SUT.TrimRight(Self);
end;


function TStringHelper.Trim(const ATrimChars: array of TStringChar): TStringType;
begin
  Result:=SUT.Trim(Self, ATrimChars, TTrimMode.Both);
end;


function TStringHelper.TrimLeft(const ATrimChars: array of TStringChar): TStringType;
begin
  Result:=SUT.Trim(Self, ATrimChars, TTrimMode.Left);
end;


function TStringHelper.TrimRight(const ATrimChars: array of TStringChar): TStringType;
begin
  Result:=SUT.Trim(Self, ATrimChars, TTrimMode.Right);
end;


function TStringHelper.TrimEnd(const ATrimChars: array of TStringChar): TStringType;
begin
  Result:=TrimRight(ATrimChars);
end;


function TStringHelper.TrimStart(const ATrimChars: array of TStringChar): TStringType;
begin
  Result:=TrimLeft(ATrimChars);
end;
