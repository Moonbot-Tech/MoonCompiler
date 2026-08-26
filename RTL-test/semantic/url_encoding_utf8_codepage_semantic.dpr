program url_encoding_utf8_codepage_semantic;

{$mode delphi}{$H+}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  cwstring,
  {$endif UNIX}
  System.SysUtils,
  System.NetEncoding;

procedure Check(ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    raise Exception.Create('URL_ENCODING_UTF8_CODEPAGE_FAIL: '+AMessage);
end;

function BinanceUnicodeSymbol: UnicodeString;
begin
  SetLength(Result,8);
  Result[1]:=WideChar($5e01);
  Result[2]:=WideChar($5b89);
  Result[3]:=WideChar($4eba);
  Result[4]:=WideChar($751f);
  Result[5]:='U';
  Result[6]:='S';
  Result[7]:='D';
  Result[8]:='T';
end;

procedure CheckEncoding(const AContext: string);
const
  ExpectedUnicode = '%E5%B8%81%E5%AE%89%E4%BA%BA%E7%94%9FUSDT';
  ExpectedAscii = 'AZaz09-_.!*''()@$+%2F%3F%3D%26%2B%25%00';
var
  RawBinary: RawByteString;
  RawInput: RawByteString;
begin
  Check(TNetEncoding.URL.Encode(BinanceUnicodeSymbol)=ExpectedUnicode,
    AContext+' UnicodeString');
  RawInput:=UTF8Encode(BinanceUnicodeSymbol);
  Check(TNetEncoding.URL.Encode(RawInput)=ExpectedUnicode,
    AContext+' RawByteString');
  { Length-aware encoding of an embedded NUL is the existing FPC raw-byte
    contract. Delphi's PChar-based implementation stops at NUL; this check
    prevents the byte-safe repair from regressing the FPC extension. }
  Check(TNetEncoding.URL.Encode('AZaz09-_.!*''()@$ /?=&+%'+#0)=ExpectedAscii,
    AContext+' ASCII, reserved bytes and embedded NUL');
  SetLength(RawBinary,4);
  RawBinary[1]:=AnsiChar(0);
  RawBinary[2]:=AnsiChar($7f);
  RawBinary[3]:=AnsiChar($80);
  RawBinary[4]:=AnsiChar($ff);
  Check(TNetEncoding.URL.Encode(RawBinary)='%00%7F%80%FF',
    AContext+' arbitrary raw bytes');
  Check(TNetEncoding.URL.Encode('')='',AContext+' empty input');
end;

var
  OriginalCodePage: TSystemCodePage;

begin
  OriginalCodePage:=DefaultSystemCodePage;
  try
    CheckEncoding('system code page');
    SetMultiByteConversionCodePage(CP_UTF8);
    Check(DefaultSystemCodePage=CP_UTF8,'UTF-8 code page setup');
    CheckEncoding('UTF-8 default code page');
  finally
    SetMultiByteConversionCodePage(OriginalCodePage);
  end;
  WriteLn('URL_ENCODING_UTF8_CODEPAGE_PASS');
end.
