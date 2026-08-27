program html_encoding_spans_semantic;

{$mode delphiunicode}{$H+}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}cthreads,cwstring,{$endif UNIX}
  SysUtils, System.NetEncoding;

var
  Failures: Integer = 0;

procedure Check(const Name: RawByteString; Condition: Boolean);
begin
  if not Condition then
  begin
    WriteLn('FAIL ',Name);
    Inc(Failures);
  end;
end;

var
  U, UResult: UnicodeString;
  R, RResult: RawByteString;
begin
  U:='plain-'#$0416;
  UResult:=TNetEncoding.HTML.Encode(U);
  Check('unicode-noop-value',UResult=U);
  Check('unicode-noop-alias',Pointer(UResult)=Pointer(U));

  U:='A'#0'&<>'''#$0416'"';
  UResult:=TNetEncoding.HTML.Encode(U);
  Check('unicode-encode-span',UResult='A'#0'&amp;&lt;&gt;'''#$0416'&quot;');
  Check('unicode-encode-length',Length(UResult)=Length('A'#0'&amp;&lt;&gt;'''#$0416'&quot;'));

  U:='A'#0'&amp;|&zzz;|a&amp|&#65;|&#x42;|&#X43;|&apos;|&#0;|&#128512;|&#x1F642;|&#x;|&#65x;|&#x110000;';
  UResult:=TNetEncoding.HTML.Decode(U);
  Check('unicode-decode-span',UResult='A'#0'&|&zzz;|a&amp|A|B|C|''|'#0'|'#$d83d#$de00'|'#$d83d#$de42'|&#x;|&#65x;|&#x110000;');
  U:='plain';
  UResult:=TNetEncoding.HTML.Decode(U);
  Check('unicode-decode-noop-alias',Pointer(UResult)=Pointer(U));

  R:='plain';
  SetCodePage(R,1251,False);
  RResult:=TNetEncoding.HTML.Encode(R);
  Check('raw-noop-alias',Pointer(RResult)=Pointer(R));
  Check('raw-noop-codepage',StringCodePage(RResult)=1251);

  R:='A'#0'&<>"';
  SetCodePage(R,1251,False);
  RResult:=TNetEncoding.HTML.Encode(R);
  Check('raw-encode-span',RResult='A'#0'&amp;&lt;&gt;&quot;');
  Check('raw-encode-codepage',StringCodePage(RResult)=1251);

  R:=UTF8Encode(UnicodeString('A'#0'&amp;|'#$0416));
  RResult:=TNetEncoding.HTML.Decode(R);
  Check('raw-decode-span',UTF8Decode(RResult)=UnicodeString('A'#0'&|'#$0416));

  if Failures<>0 then
    Halt(1);
  WriteLn('HTML_ENCODING_SPANS_OK');
end.
