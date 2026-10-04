program conversion_api_semantic;
{$mode delphiunicode}
{$M+}
uses SysUtils, Variants, TypInfo;
type
  TProperties = class
  private
    FAnsi: AnsiString;
    FUnicode: UnicodeString;
  published
    property Ansi: AnsiString read FAnsi write FAnsi;
    property Unicode: UnicodeString read FUnicode write FUnicode;
  end;
  TMarker = class(TCustomVariantType)
    procedure Clear(var V: TVarData); override;
    procedure Copy(var D: TVarData; const S: TVarData; const Indirect: Boolean); override;
    procedure CastTo(var D: TVarData; const S: TVarData; const Kind: TVarType); override;
  end;
var Checks, Calls: Integer;
    Original: TVariantManager;
procedure Check(B: Boolean; const What: UnicodeString);
begin
  Inc(Checks);
  if not B then begin WriteLn('FAIL ', What); Halt(1); end;
end;
function ReturnKind(const S: UnicodeString): Integer; overload;
begin Result:=2; end;
function ReturnKind(const S: AnsiString): Integer; overload;
begin Result:=1; end;
procedure TMarker.Clear(var V: TVarData);
begin V.VType:=varEmpty; end;
procedure TMarker.Copy(var D: TVarData; const S: TVarData; const Indirect: Boolean);
begin D:=S; end;
procedure TMarker.CastTo(var D: TVarData; const S: TVarData; const Kind: TVarType);
begin
  Inc(Calls);
  Check(Kind=varOleStr, 'custom CastTo preserves varOleStr');
  VarDataFromOleStr(D, 'custom-'#$0416#$4E2D);
end;
procedure Hook(var D: WideString; const V: Variant);
begin Inc(Calls); D:='hook-'#$0416; end;
procedure CompareReader(const V: Variant);
var W: WideString;
    U: UnicodeString;
begin
  Original.VarToWStr(W,V);
  U:=UnicodeString(W);
  Check(UnicodeString(V)=U,'Unicode cast agrees with manager');
  Check(VarToStr(V)=U,'Unicode API agrees with manager');
  Check(UTF8String(V)=UTF8Encode(U),'UTF8 shares Unicode producer');
end;
procedure Test;
var V, N: Variant;
    Ref, Outer: TVarData;
    U, OldNull, OldDate: UnicodeString;
    A: AnsiString;
    B: Byte;
    W: Word;
    SI: ShortInt;
    SM: SmallInt;
    I, I32: Integer;
    L: LongWord;
    I64: Int64;
    Q: QWord;
    F: Single;
    D: Double;
    C: Currency;
    Bool: WordBool;
    Custom: TVariantManager;
    M: TMarker;
    P: TProperties;
begin
  GetVariantManager(Original);
  V:=12345;
  Check(ReturnKind(VarToStr(V))=2,'Unicode VarToStr return type');
  Check(ReturnKind(VarToStrDef(V,''))=2,'Unicode VarToStrDef return type');
  U:='A'#0#$0416#$4E2D#$D83D#$DE00#$D800;
  V:=U;
  CompareReader(V);
  A:=UTF8Encode(U);
  SetCodePage(RawByteString(A),65001,False);
  V:=A;
  CompareReader(V);
  V:=Unassigned; CompareReader(V);
  OldNull:=NullAsStringValue;
  try
    NullAsStringValue:='null-'#$0416#$4E2D;
    N:=Null;
    FillChar(Ref,SizeOf(Ref),0);
    Ref.VType:=varVariant or varByRef;
    Ref.VPointer:=@N;
    Outer:=Ref;
    Outer.VPointer:=@Ref;
    Check(VarIsNull(PVariant(@Outer)^),'nested byref Null');
    Check(VarToStr(N)=NullAsStringValue,'configured Null string');
    Check(VarToStr(PVariant(@Outer)^)=NullAsStringValue,'configured byref Null string');
    Check(VarToStrDef(PVariant(@Outer)^,'default')='default','byref Null default');
    Check(VarToUnicodeStr(PVariant(@Outer)^)=NullAsStringValue,'Unicode wrapper Null');
    Check(VarToWideStr(PVariant(@Outer)^)=WideString(NullAsStringValue),'Wide wrapper Null');
    NullStrictConvert:=True;
    Check(VarToStr(N)=NullAsStringValue,'API Null despite strict cast');
    NullStrictConvert:=False;
    CompareReader(N);
  finally
    NullAsStringValue:=OldNull;
    NullStrictConvert:=False;
  end;
  B:=255; W:=65535; SI:=-128; SM:=-32768; I32:=Low(Integer);
  L:=High(LongWord); I64:=Low(Int64); Q:=High(QWord);
  F:=1.25; D:=-1234.125; C:=12.3456; Bool:=True;
  for I:=0 to 12 do begin
    case I of
      0: begin Ref.VType:=varByte or varByRef; Ref.VPointer:=@B; V:=B; end;
      1: begin Ref.VType:=varWord or varByRef; Ref.VPointer:=@W; V:=W; end;
      2: begin Ref.VType:=varShortInt or varByRef; Ref.VPointer:=@SI; V:=SI; end;
      3: begin Ref.VType:=varSmallInt or varByRef; Ref.VPointer:=@SM; V:=SM; end;
      4: begin Ref.VType:=varInteger or varByRef; Ref.VPointer:=@I32; V:=I32; end;
      5: begin Ref.VType:=varLongWord or varByRef; Ref.VPointer:=@L; V:=L; end;
      6: begin Ref.VType:=varInt64 or varByRef; Ref.VPointer:=@I64; V:=I64; end;
      7: begin Ref.VType:=varQWord or varByRef; Ref.VPointer:=@Q; V:=Q; end;
      8: begin Ref.VType:=varSingle or varByRef; Ref.VPointer:=@F; V:=F; end;
      9: begin Ref.VType:=varDouble or varByRef; Ref.VPointer:=@D; V:=D; end;
      10: begin Ref.VType:=varCurrency or varByRef; Ref.VPointer:=@C; V:=C; end;
      11: begin Ref.VType:=varBoolean or varByRef; Ref.VPointer:=@Bool; V:=Bool; end;
      12: begin Ref.VType:=varDate or varByRef; Ref.VPointer:=@D; V:=VarFromDateTime(D); end;
    end;
    CompareReader(V);
    CompareReader(PVariant(@Ref)^);
  end;
  Custom:=Original;
  OldDate:=DefaultFormatSettings.ShortDateFormat;
  try
    DefaultFormatSettings.ShortDateFormat:='"'#$0416#$4E2D'" yyyy-mm-dd';
    V:=VarFromDateTime(EncodeDate(2026,10,4));
    Check(VarToStr(V)=DateTimeToStr(EncodeDate(2026,10,4)),'Unicode date format avoids ANSI carrier');
  finally DefaultFormatSettings.ShortDateFormat:=OldDate; end;
  Custom.VarToWStr:=@Hook;
  SetVariantManager(Custom);
  try
    Calls:=0;
    Check(VarToStr(V)='hook-'#$0416,'API custom reader');
    Check(UTF8String(V)=UTF8Encode('hook-'#$0416),'UTF8 custom reader');
    Check(Calls=2,'custom reader called once per conversion');
  finally SetVariantManager(Original); end;
  M:=TMarker.Create;
  try
    VarClear(V);
    TVarData(V).VType:=M.VarType;
    Ref.VType:=varVariant or varByRef; Ref.VPointer:=@V;
    CompareReader(V);
    CompareReader(PVariant(@Ref)^);
    VarClear(V);
  finally M.Free; end;
  P:=TProperties.Create;
  try
    V:=12345;
    SetPropValue(P,'Ansi',V);
    SetPropValue(P,'Unicode',V);
    Check(P.Ansi='12345','ANSI RTTI value');
    Check(P.Unicode='12345','Unicode RTTI value');
    Custom:=Original;
    Custom.VarToWStr:=@Hook;
    SetVariantManager(Custom);
    try
      Calls:=0;
      SetPropValue(P,'Ansi',V);
      Check((P.Ansi='12345') and (Calls=0),'ANSI RTTI keeps the ANSI manager route');
    finally SetVariantManager(Original); end;
    V:=U;
    SetPropValue(P,'Unicode',V);
    Check(P.Unicode=U,'Unicode RTTI preserves code units');
  finally P.Free; end;
  WriteLn('CONVERSION_API_PASS',' checks=',Checks);
end;
begin Test; end.
