program tdelphivariantstring1;

{$ifdef FPC}
  {$mode delphiunicode}
{$endif}

uses
{$ifdef unix}
  cwstring,
{$endif}
  Variants;

const
  CAscii = 'constant';
{$ifdef FPC_WIDESTRING_EQUAL_UNICODESTRING}
  DefaultUnicodeVariantType = varOleStr;
{$else}
  DefaultUnicodeVariantType = varUString;
{$endif}

type
  TAssignmentProbe = record
    Tag: Integer;
    class operator Implicit(const Source: UnicodeString): TAssignmentProbe;
    class operator Implicit(const Source: AnsiString): TAssignmentProbe;
  end;

  TTextHolder = class
  private
    FText: string;
  public
    property Text: string read FText write FText;
  end;

class operator TAssignmentProbe.Implicit(
  const Source: UnicodeString): TAssignmentProbe;
begin
  Result.Tag:=1;
end;

class operator TAssignmentProbe.Implicit(
  const Source: AnsiString): TAssignmentProbe;
begin
  Result.Tag:=2;
end;

procedure RequireVariant(const Value: Variant; ExpectedType: Word;
  const ExpectedText: string; ErrorCode: Byte);
var
  Actual: string;
begin
  if VarType(Value)<>ExpectedType then
    Halt(ErrorCode);
  Actual:=Value;
  if Actual<>ExpectedText then
    Halt(ErrorCode);
end;

procedure PutString(const Source: string; var Dest: Variant);
begin
  Dest:=Source;
end;

function ReturnString: string;
begin
  Result:=WideChar($0410)+WideChar($20ac)+'R';
end;

var
  Box, CopyBox: Variant;
  DefaultText: string;
  UnicodeText: UnicodeString;
  WideText: WideString;
  AnsiText: AnsiString;
  AssignmentProbe: TAssignmentProbe;
  Holder: TTextHolder;
begin
  DefaultText:=WideChar($0410)+WideChar($20ac)+'D';
  UnicodeText:=WideChar($0411)+WideChar($20ac)+'U';
  WideText:=WideChar($0412)+WideChar($20ac)+'W';
  AnsiText:='ansi';

  Box:=DefaultText;
  RequireVariant(Box,DefaultUnicodeVariantType,DefaultText,1);
  CopyBox:=Box;
  RequireVariant(CopyBox,DefaultUnicodeVariantType,DefaultText,2);

  Box:=UnicodeText;
  RequireVariant(Box,DefaultUnicodeVariantType,UnicodeText,3);
  Box:=WideText;
  RequireVariant(Box,varOleStr,WideText,4);
  Box:=AnsiText;
  RequireVariant(Box,varString,AnsiText,5);

  Box:='ascii literal';
  RequireVariant(Box,DefaultUnicodeVariantType,'ascii literal',10);
  Box:=#$0410#$20ac#$0041;
  RequireVariant(Box,DefaultUnicodeVariantType,
    WideChar($0410)+WideChar($20ac)+'A',11);
  Box:='';
  RequireVariant(Box,DefaultUnicodeVariantType,'',12);
  Box:=CAscii;
  RequireVariant(Box,DefaultUnicodeVariantType,CAscii,13);

  AssignmentProbe:='ascii assignment operator';
  if AssignmentProbe.Tag<>1 then
    Halt(14);
  AssignmentProbe:=AnsiString('explicit ansi assignment operator');
  if AssignmentProbe.Tag<>2 then
    Halt(15);

  Box:=UnicodeString('cast unicode');
  RequireVariant(Box,DefaultUnicodeVariantType,'cast unicode',20);
  Box:=WideString('cast wide');
  RequireVariant(Box,varOleStr,'cast wide',21);
  Box:=AnsiString('cast ansi');
  RequireVariant(Box,varString,'cast ansi',22);

  PutString(DefaultText,Box);
  RequireVariant(Box,DefaultUnicodeVariantType,DefaultText,30);
  Box:=ReturnString;
  RequireVariant(Box,DefaultUnicodeVariantType,ReturnString,31);
  Box:=DefaultText+' concat';
  RequireVariant(Box,DefaultUnicodeVariantType,DefaultText+' concat',32);

  Holder:=TTextHolder.Create;
  try
    Holder.Text:=UnicodeText;
    Box:=Holder.Text;
    RequireVariant(Box,DefaultUnicodeVariantType,UnicodeText,33);
  finally
    Holder.Free;
  end;

  DefaultText:='a'+#0+'b';
  Box:=DefaultText;
  RequireVariant(Box,DefaultUnicodeVariantType,DefaultText,40);
  DefaultText:=WideChar($d83d)+WideChar($de00);
  Box:=DefaultText;
  RequireVariant(Box,DefaultUnicodeVariantType,DefaultText,41);

  Box:=AnsiString('old ansi');
  Box:=UnicodeText;
  RequireVariant(Box,DefaultUnicodeVariantType,UnicodeText,50);
  Box:=WideString('old wide');
  Box:=UnicodeText;
  RequireVariant(Box,DefaultUnicodeVariantType,UnicodeText,51);
  Box:=42;
  Box:=UnicodeText;
  RequireVariant(Box,DefaultUnicodeVariantType,UnicodeText,52);

  Box:=UnicodeString('ab');
  CopyBox:=UnicodeString('ab');
  if not (Box=CopyBox) then
    Halt(60);
  CopyBox:=UnicodeString('cd');
  if not (Box<CopyBox) then
    Halt(61);
  if not (Box<>CopyBox) then
    Halt(62);
  CopyBox:=WideString('ab');
  if not (Box=CopyBox) then
    Halt(63);
  CopyBox:=AnsiString('ab');
  if not (Box=CopyBox) then
    Halt(64);

  Box:=UnicodeString('ab');
  CopyBox:=UnicodeString('cd');
  Box:=Box+CopyBox;
  RequireVariant(Box,DefaultUnicodeVariantType,'abcd',70);
  Box:=UnicodeString('ab');
  CopyBox:=WideString('cd');
  Box:=Box+CopyBox;
  RequireVariant(Box,DefaultUnicodeVariantType,'abcd',71);
  Box:=WideString('ab');
  CopyBox:=UnicodeString('cd');
  Box:=Box+CopyBox;
  RequireVariant(Box,varOleStr,'abcd',72);
  Box:=UnicodeString('ab');
  CopyBox:=AnsiString('cd');
  Box:=Box+CopyBox;
  RequireVariant(Box,DefaultUnicodeVariantType,'abcd',73);
  Box:=AnsiString('ab');
  CopyBox:=UnicodeString('cd');
  Box:=Box+CopyBox;
  RequireVariant(Box,varString,'abcd',74);
  Box:=WideString('ab');
  CopyBox:=AnsiString('cd');
  Box:=Box+CopyBox;
  RequireVariant(Box,varOleStr,'abcd',75);
  Box:=AnsiString('ab');
  CopyBox:=WideString('cd');
  Box:=Box+CopyBox;
  RequireVariant(Box,varString,'abcd',76);

  Box:=VarArrayOf([1,DefaultText,3.5]);
  if not VarIsArray(Box) then
    Halt(80);
  if Integer(Box[0])<>1 then
    Halt(81);
  RequireVariant(Box[1],varOleStr,DefaultText,82);
  if Double(Box[2])<>3.5 then
    Halt(83);

  CopyBox:=VarArrayCreate([0,2],varVariant);
  CopyBox[0]:=UnicodeText;
  RequireVariant(CopyBox[0],varOleStr,UnicodeText,84);
  CopyBox[1]:=AnsiText;
  RequireVariant(CopyBox[1],varOleStr,AnsiText,85);
  CopyBox[2]:=WideText;
  RequireVariant(CopyBox[2],varOleStr,WideText,86);
end.
