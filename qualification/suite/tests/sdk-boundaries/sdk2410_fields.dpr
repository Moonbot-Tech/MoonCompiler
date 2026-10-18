program sdk2410_fields;

{$mode delphi}{$H+}{$codepage utf8}

uses {$IF defined(UNIX) and (SIZEOF(Char)=1)}cwstring,{$ENDIF} SysUtils, Classes, Variants, DB, BufDataset;

type
  TSetterProbe = class(TStringField)
  public
    Calls: Integer;
  protected
    procedure SetAsAnsiString(const Value: AnsiString); override;
  end;

procedure TSetterProbe.SetAsAnsiString(const Value: AnsiString);
begin
  Inc(Calls);
  inherited SetAsAnsiString(Value);
end;

var Checks: Integer;

{$IFDEF MSWINDOWS}
function NativeOEMCP: Cardinal; stdcall; external 'kernel32' name 'GetOEMCP';
function NativeWideToMultiByte(CodePage, Flags: Cardinal; Source: PWideChar; SourceLength: Integer;
  Target: PAnsiChar; TargetLength: Integer; DefaultChar: PAnsiChar; UsedDefaultChar: Pointer): Integer;
  stdcall; external 'kernel32' name 'WideCharToMultiByte';
{$ENDIF}

procedure Check(Condition: Boolean; const Name: string);
begin
  Inc(Checks);
  If not Condition then raise Exception.Create('FIELDS_FAIL: '+Name);
end;

{$IF SIZEOF(Char)=2}
procedure MixedVariantPages;
var D: TBufDataset;
begin
  D:=TBufDataset.Create(nil);
  try
    D.FieldDefs.Add('s8',ftString,100,0,False,False,1,CP_UTF8);
    D.FieldDefs.Add('s1251',ftString,100,0,False,False,2,1251);
    D.FieldDefs.Add('m8',ftMemo,0,0,False,False,3,CP_UTF8);
    D.FieldDefs.Add('m1251',ftMemo,0,0,False,False,4,1251);
    D.CreateDataset;
    D.Append;
    D.FieldByName('s8').AsString:='Привет';
    D.FieldByName('s1251').AsString:='Привет';
    D.FieldByName('m8').AsString:='Привет';
    D.FieldByName('m1251').AsString:='Привет';
    Check(D['s8']=D['s1251'],'equal string Variants across code pages');
    Check(D['m8']=D['m1251'],'equal memo Variants across code pages');
    Check(not (D['s8']<>D['s1251']),'string Variant inequality');
    Check(not (D['m8']<>D['m1251']),'memo Variant inequality');
    Check(UnicodeString(D['s8']+D['s1251'])='ПриветПривет','mixed string Variant concatenation');
    Check(UnicodeString(D['m8']+D['m1251'])='ПриветПривет','mixed memo Variant concatenation');
  finally
    D.Free;
  end;
end;

procedure VirtualSetter;
var D: TBufDataset; P: TSetterProbe;
begin
  D:=TBufDataset.Create(nil);
  try
    P:=TSetterProbe.Create(D);
    P.FieldName:='probe';
    P.Size:=100;
    P.DataSet:=D;
    D.CreateDataset;
    D.Append;
    P.AsString:='A';
    Check((P.Calls=1) and (P.AsString='A'),'virtual ANSI setter via string');
    TField(P).AsUnicodeString:='B';
    Check((P.Calls=2) and (P.AsString='B'),'virtual ANSI setter via Unicode');
    P.Value:='C';
    Check((P.Calls=3) and (P.AsString='C'),'virtual ANSI setter via Value');
  finally
    D.Free;
  end;
end;
{$ENDIF}

function SameBytes(const A,B: RawByteString): Boolean;
begin
  Result:=(Length(A)=Length(B)) and ((Length(A)=0) or CompareMem(Pointer(A),Pointer(B),Length(A)));
end;

function ACPBytes(const Value: UnicodeString): RawByteString; noinline;
var A: AnsiString;
begin
  A:=Value;
  Result:=A;
end;

procedure Fields(CodePage: TSystemCodePage; const Value: UnicodeString);
var D: TBufDataset; S,M: TField; I: Integer;
begin
  D:=TBufDataset.Create(nil);
  try
    D.FieldDefs.Add('s',ftString,100,0,False,False,1,CodePage);
    D.FieldDefs.Add('m',ftMemo,0,0,False,False,2,CodePage);
    D.CreateDataset;
    D.Append;
    S:=D.FieldByName('s');
    M:=D.FieldByName('m');
    For I:=0 to 3 do begin
      If I=0 then begin
        S.AsUTF8String:=UTF8Encode(Value);
        M.AsUTF8String:=UTF8Encode(Value);
      end else begin
        {$IF SIZEOF(Char)=2}
        If I=1 then begin
          S.AsString:=Value;
          M.AsString:=Value;
        end else If I=2 then begin
          S.AsUnicodeString:=Value;
          M.AsUnicodeString:=Value;
        end else begin
          S.Value:=Value;
          M.Value:=Value;
        end;
        {$ELSE}
        M.AsUnicodeString:=Value;
        {$ENDIF}
      end;
      Check(SameBytes(S.AsUTF8String,UTF8Encode(Value)),'string UTF8 roundtrip CP='+IntToStr(CodePage));
      Check(SameBytes(M.AsUTF8String,UTF8Encode(Value)),'memo UTF8 roundtrip CP='+IntToStr(CodePage));
      {$IF SIZEOF(Char)=2}
      Check(S.AsString=Value,'string Unicode read');
      Check(S.AsUnicodeString=Value,'string Unicode property');
      Check(S.AsWideString=Value,'string WideString property');
      Check(M.AsString=Value,'memo Unicode read');
      Check(UnicodeString(S.Value)=Value,'string Variant value');
      Check(UnicodeString(M.Value)=Value,'memo Variant value');
      Check(UnicodeString(D['s'])=Value,'dataset string Variant');
      Check(UnicodeString(D['m'])=Value,'dataset memo Variant');
      {$ENDIF}
      Check(M.AsUnicodeString=Value,'memo Unicode property');
      Check(M.AsWideString=Value,'memo WideString property');
    end;
    S.Clear;
    M.Clear;
    Check((S.AsUTF8String='') and (M.AsUTF8String=''),'NULL getters');
    Check(VarIsNull(S.Value) and VarIsNull(M.Value),'NULL Variant values');
    S.AsUTF8String:='';
    M.AsUTF8String:='';
    Check((S.AsUTF8String='') and (M.AsUTF8String=''),'empty getters');
    D.Post;
  finally
    D.Free;
  end;
end;

procedure StoredBytes(CodePage: TSystemCodePage; const Value: UnicodeString; const Expected: RawByteString);
var D: TBufDataset; S,M: TField; B: array[0..511] of AnsiChar; Raw: RawByteString; Stream: TMemoryStream;
begin
  D:=TBufDataset.Create(nil);
  Stream:=TMemoryStream.Create;
  try
    D.FieldDefs.Add('s',ftString,100,0,False,False,1,CodePage);
    D.FieldDefs.Add('m',ftMemo,0,0,False,False,2,CodePage);
    D.CreateDataset;
    D.Append;
    S:=D.FieldByName('s');
    M:=D.FieldByName('m');
    {$IF SIZEOF(Char)=2}
    S.AsString:=Value;
    {$ELSE}
    S.AsUTF8String:=UTF8Encode(Value);
    {$ENDIF}
    M.AsUnicodeString:=Value;
    FillChar(B,SizeOf(B),0);
    Check(S.GetData(@B),'storage field exists');
    SetString(Raw,PAnsiChar(@B),StrLen(PAnsiChar(@B)));
    Check(SameBytes(Raw,Expected),'stored string bytes CP='+IntToStr(CodePage));
    TBlobField(M).SaveToStream(Stream);
    SetString(Raw,PAnsiChar(Stream.Memory),Stream.Size);
    Check(SameBytes(Raw,Expected),'stored memo bytes CP='+IntToStr(CodePage));
  finally
    Stream.Free;
    D.Free;
  end;
end;

{$IFDEF MSWINDOWS}
procedure OEMFields;
var Value: UnicodeString; Buffer: array[0..7] of AnsiChar; Expected: RawByteString; N: Integer;
begin
  Value:=#$2591;
  N:=NativeWideToMultiByte(NativeOEMCP,0,PWideChar(Value),Length(Value),@Buffer,SizeOf(Buffer),nil,nil);
  Check(N>0,'native OEM encoding oracle');
  SetString(Expected,PAnsiChar(@Buffer),N);
  StoredBytes(CP_OEMCP,Value,Expected);
  Fields(CP_OEMCP,Value);
end;
{$ENDIF}

const RussianBytes: array[0..5] of Byte=($CF,$F0,$E8,$E2,$E5,$F2);
var Russian: RawByteString;
begin
  try
    {$IF SIZEOF(Char)=2}
    MixedVariantPages;
    VirtualSetter;
    {$ENDIF}
    Fields(CP_UTF8,'Привет 中文 '+#$D83D#$DE42);
    Fields(1251,'Привет');
    Fields(CP_ACP,'Ascii text');
    Fields(CP_NONE,'Ascii text');
    SetString(Russian,PAnsiChar(@RussianBytes),Length(RussianBytes));
    StoredBytes(1251,'Привет',Russian);
    {$IF SIZEOF(Char)=2}
    StoredBytes(CP_NONE,'Привет',ACPBytes('Привет'));
    {$ENDIF}
    {$IFDEF MSWINDOWS}
    OEMFields;
    {$ENDIF}
    Writeln('FIELDS_PASS checks=',Checks);
  except
    on E: Exception do begin
      Writeln(E.ClassName,': ',E.Message);
      Halt(1);
    end;
  end;
end.
