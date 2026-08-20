program numeric_text_semantic;

{$mode delphi}{$H+}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}cthreads,cwstring,{$endif UNIX}
  SysUtils;

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then
    raise Exception.Create('NUMERIC_TEXT_FAIL: '+MessageText);
end;

procedure CheckCompilerProcs;
var
  Code: Integer;
  D: Double;
  S: UnicodeString;
begin
  Str(Integer(Low(Integer)),S);
  Check(S='-2147483648','Str Integer minimum');
  Str(Int64(Low(Int64)),S);
  Check(S='-9223372036854775808','Str Int64 minimum');
  Str(QWord(High(QWord)),S);
  Check(S='18446744073709551615','Str QWord maximum');
  Str(Double(1.25):0:2,S);
  Check(S='1.25','Str Double fixed');
  Str(Double(-0.0):0:2,S);
  Check(S='-0.00','Str negative zero');

  Val(UnicodeString('1.25'),D,Code);
  Check((Code=0) and (D=1.25),'Val Double');
  Val(UnicodeString('1')+UnicodeChar($0661),D,Code);
  Check(Code<>0,'Val rejects non-ASCII digit');
end;

procedure CheckSysUtils;
var
  BadTypeRejected: Boolean;
  D: Double;
  I64: Int64;
  LongPart: UnicodeString;
  Original: UnicodeString;
  Q: UInt64;
  Settings: TFormatSettings;
  S: UnicodeString;
begin
  Settings:=DefaultFormatSettings;
  Settings.DecimalSeparator:='.';
  Settings.ThousandSeparator:=',';

  Check(TryStrToFloat('  -12.5  ',D,Settings) and (D=-12.5),
    'TryStrToFloat surrounding spaces');
  Check(not TryStrToFloat('1,234.5',D,Settings),
    'TryStrToFloat rejects thousands');
  Check(not TryStrToFloat(UnicodeString('1')+UnicodeChar($0661),D,Settings),
    'TryStrToFloat rejects non-ASCII digit');
  Check(not TryStrToFloat('1'+UnicodeChar(#0)+'2',D,Settings),
    'TryStrToFloat rejects embedded NUL');

  S:=FloatToStr(1.25,Settings);
  Check(S='1.25','FloatToStr exact');
  S:=FloatToStr(-0.0,Settings);
  Check(S='0','FloatToStr negative zero');
  Check(FloatToStr(0.00001,Settings)='1E-5',
    'FloatToStr Delphi lower exponent threshold');
  Check(FloatToStr(0.0001,Settings)='0.0001',
    'FloatToStr fixed lower boundary');
  Check(FloatToStr(1.0e14,Settings)='100000000000000',
    'FloatToStr fixed upper boundary');
  Check(FloatToStr(1.0e15,Settings)='1E15',
    'FloatToStr exponent upper boundary');
  Settings.DecimalSeparator:=UnicodeChar($066B);
  Check(FloatToStr(1.25,Settings)=UnicodeString('1')+UnicodeChar($066B)+'25',
    'FloatToStr Unicode decimal separator');
  Check(FloatToStr(1.25e100,Settings)=
    UnicodeString('1')+UnicodeChar($066B)+'25E100',
    'FloatToStr Unicode decimal separator in exponent form');
  Check(Format('%.3f',[1.25],Settings)=
    UnicodeString('1')+UnicodeChar($066B)+'250',
    'Format exact fixed float with Unicode decimal separator');
  Settings.DecimalSeparator:='.';

  Original:='shared-value';
  S:=Format('%s',[Original],Settings);
  Check(S=Original,'Format exact UnicodeString');
  S[1]:='S';
  Check(Original='shared-value','Format exact UnicodeString copy on write');
  S:=Format('%S',[UnicodeChar($0416)],Settings);
  Check(S=UnicodeString(#$0416),'Format exact WideChar');
  S:=Format('%s',[AnsiString('ansi')],Settings);
  Check(S='ansi','Format exact AnsiString fallback');
  S:=Format('%s',[UnicodeString('')],Settings);
  Check(S='','Format exact empty UnicodeString');

  I64:=Low(Int64);
  Q:=High(UInt64);
  Check(Format('%d',[Low(Integer)],Settings)='-2147483648',
    'Format exact Integer');
  Check(Format('%D',[I64],Settings)='-9223372036854775808',
    'Format exact Int64');
  Check(Format('%u',[Cardinal(High(Cardinal))],Settings)='4294967295',
    'Format exact Cardinal');
  Check(Format('%U',[Q],Settings)='18446744073709551615',
    'Format exact UInt64');

  S:=Format('%d|%u|%.2f|%s',[-42,Cardinal(42),1.25,'ok'],Settings);
  Check(S='-42|42|1.25|ok','mixed Format');
  Check(Format('literal',[123],Settings)='literal',
    'Format literal ignores unused arguments');
  Check(Format('%%:%d:%s',[9,UnicodeString(#$0416)],Settings)=
    UnicodeString('%:9:')+UnicodeChar($0416),
    'Format simple escaped percent and Unicode text');
  Check(Format('%.3f',[1.25],Settings)='1.250',
    'Format exact fixed float');
  Check(Format('%F',[1.25],Settings)='1.25',
    'Format exact fixed float default precision');
  Check(Format('%.3f',[Currency(1.25)],Settings)='1.250',
    'Format exact fixed Currency');
  S:=Format('%d|%d|%u|%u',
    [Low(Integer),Low(Int64),Cardinal(High(Cardinal)),High(UInt64)],Settings);
  Check(S='-2147483648|-9223372036854775808|4294967295|18446744073709551615',
    'Format integer boundaries');

  S:=Format('%-8s|%8s|%.3s',['abc','xy','abcdef'],Settings);
  Check(S='abc     |      xy|abc','Format alignment and precision');
  S:=Format('%8.4d|%-8u',[12,Cardinal(34)],Settings);
  Check(S='    0012|34      ','Format numeric padding');
  S:=Format('%8.4d|%-8.4d|%.20u',[-12,-34,High(UInt64)],Settings);
  Check(S='   -0012|-0034   |18446744073709551615',
    'Format signed and maximum numeric padding');
  S:=Format('%1:d/%0:s',['name',7],Settings);
  Check(S='7/name','Format explicit indexes');
  S:=Format('prefix:%1:d/%0:s:suffix',['name',7],Settings);
  Check(S='prefix:7/name:suffix','Format fallback after a literal prefix');
  S:=Format('%%:%d',[9],Settings);
  Check(S='%:9','Format escaped percent');
  S:=Format('%b|%x|%s',[True,Cardinal($2A),UnicodeChar('Z')],Settings);
  Check(S='True|2A|Z','Format type dispatch');
  BadTypeRejected:=False;
  try
    S:=Format('%d',[UnicodeString('wrong')],Settings);
  except
    on EConvertError do
      BadTypeRejected:=True;
  end;
  Check(BadTypeRejected,'Format rejects a wrong argument type');
  LongPart:=StringOfChar(UnicodeChar('x'),5000);
  S:=Format(LongPart+'|%s|%d',[UnicodeString(#$0416),42],Settings);
  Check(S=LongPart+'|'+UnicodeString(#$0416)+'|42','Format grows output buffer');
end;

begin
  try
    CheckCompilerProcs;
    CheckSysUtils;
    WriteLn('NUMERIC_TEXT_PASS');
  except
    on E: Exception do
      begin
        WriteLn(ErrOutput,E.ClassName,': ',E.Message);
        Halt(1);
      end;
  end;
end.
