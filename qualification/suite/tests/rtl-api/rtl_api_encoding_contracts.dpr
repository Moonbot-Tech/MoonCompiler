program rtl_api_encoding_contracts;

{$APPTYPE CONSOLE}

{$ifdef FPC}
  {$mode delphiunicode}
  {$modeswitch inlinevars}
{$endif}

uses
  {$ifdef unix}
  cwstring,
  {$endif}
  SysUtils;

procedure Check(ACondition: Boolean; const AName: string);
begin
  if not ACondition then
    begin
      WriteLn('FAIL ',AName);
      Halt(1);
    end;
end;

procedure CheckEncoding(CodePage: Integer; const Sample,Name: string;
  ExpectedSingleByte: Boolean; CheckSingleByte: Boolean = True);
var
  Bytes,Buffer: TBytes;
  Encoding,Clone: TEncoding;
  Maximum,Written: Integer;
begin
  Encoding:=TEncoding.GetEncoding(CodePage);
  try
    Bytes:=Encoding.GetBytes(Sample);
    if CheckSingleByte then
      Check(Encoding.IsSingleByte=ExpectedSingleByte,Name+'-single-byte');
    Maximum:=Encoding.GetMaxByteCount(Length(Sample));
    Check(Maximum>=Length(Bytes),Name+'-maximum');
    Check(Encoding.GetMaxByteCount(0)>=Length(Encoding.GetBytes('')),
      Name+'-empty-maximum');

    SetLength(Buffer,Maximum);
    Written:=Encoding.GetBytes(Sample,1,Length(Sample),Buffer,0);
    Check(Written=Length(Bytes),Name+'-capacity-written');
    if Written>0 then
      Check(CompareMem(@Buffer[0],@Bytes[0],Written),Name+'-capacity-content');

    Clone:=Encoding.Clone;
    try
      Check(Clone.GetMaxByteCount(Length(Sample))>=Length(Clone.GetBytes(Sample)),
        Name+'-clone-maximum');
      if CheckSingleByte then
        Check(Clone.IsSingleByte=ExpectedSingleByte,Name+'-clone-single-byte');
    finally
      Clone.Free;
    end;
  finally
    Encoding.Free;
  end;
end;

procedure CheckDefault;
var
  Bytes: TBytes;
  Encoding: TEncoding;
  Sample: string;
begin
  Sample:='ASCII '+#$0416+#$4E2D;
  Encoding:=TEncoding.Default;
  Bytes:=Encoding.GetBytes(Sample);
  Check(Encoding.GetMaxByteCount(Length(Sample))>=Length(Bytes),'default-maximum');
end;

begin
  CheckEncoding(1251,'Cyrillic '+#$0416,'cp1251',True);
  CheckEncoding(1252,'Euro '+#$20AC,'cp1252',True);
  CheckEncoding(932,#$65E5#$672C#$8A9E,'cp932',False);
  CheckEncoding(936,#$4E2D#$6587,'cp936',False);
  {$ifdef unix}
  CheckEncoding(51932,#$65E5#$672C#$8A9E,'euc-jp',False);
  {$endif}
  CheckEncoding(54936,#$4E2D#$6587#$D83D#$DE00,'gb18030',False);
  CheckEncoding(CP_UTF7,'ASCII '+#$20AC,'utf7',False);
  CheckEncoding(CP_UTF8,'ASCII '+#$20AC#$D83D#$DE00,'utf8',False);
  CheckEncoding(CP_UTF16,'ASCII '+#$20AC,'utf16',False);
  CheckEncoding(CP_UTF16BE,'ASCII '+#$20AC,'utf16be',False);
  CheckEncoding(65534,'fallback '+#$0416,'invalid-page-fallback',False,False);
  CheckDefault;
  WriteLn('RTL_API_ENCODING_CONTRACTS_OK');
end.
