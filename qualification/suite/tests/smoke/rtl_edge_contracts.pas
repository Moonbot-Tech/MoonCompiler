program rtl_edge_contracts;

{$mode delphiunicode}

uses
  SysUtils,
  Math;

procedure Fail(const Name: string);
begin
  WriteLn('FAIL ',Name);
  Halt(1);
end;

procedure ExpectQWord(const Text: string; Expected: QWord);
var
  Value: QWord;
begin
  Value:=123;
  if not TryStrToUInt64(Text,Value) or (Value<>Expected) then
    Fail('uint64-valid-' + Text);
end;

procedure RejectQWord(const Text,Name: string);
var
  Value: QWord;
begin
  Value:=123;
  if TryStrToUInt64(Text,Value) then
    Fail('uint64-invalid-' + Name);
end;

procedure CheckUnsignedParsing;
var
  Value: DWord;
begin
  ExpectQWord('0',0);
  ExpectQWord('  +42',42);
  ExpectQWord('$ffffffffffffffff',High(QWord));
  ExpectQWord('x10',16);
  ExpectQWord('X10',16);
  ExpectQWord('0x10',16);
  ExpectQWord('12' + #0 + 'ignored',12);
  RejectQWord('','empty');
  RejectQWord('   ','spaces');
  RejectQWord(#9 + '10','tab');
  RejectQWord('%10','binary-prefix');
  RejectQWord('&10','octal-prefix');
  RejectQWord('-1','negative');
  RejectQWord('$','prefix-only');
  RejectQWord('18446744073709551616','overflow');
  if TryStrToDWord('4294967296',Value) then
    Fail('dword-overflow');
  if not TryStrToDWord('4294967295',Value) or (Value<>High(DWord)) then
    Fail('dword-high');
end;

procedure CheckPointerTextWidth;
var
  F: Text;
  FileName,Line: string;
  Empty: array[0..0] of AnsiChar;
  Value: array[0..2] of AnsiChar;
  P: PAnsiChar;
begin
  FileName:=GetTempFileName('','mct');
  try
    Assign(F,FileName);
    Rewrite(F);
    P:=nil;
    WriteLn(F,'A',P:5,'B');
    Empty[0]:=#0;
    P:=@Empty[0];
    WriteLn(F,'C',P:3,'D');
    Value[0]:='x';
    Value[1]:='y';
    Value[2]:=#0;
    P:=@Value[0];
    WriteLn(F,'E',P:4,'F');
    Close(F);

    Reset(F);
    ReadLn(F,Line);
    if Line<>'A     B' then
      Fail('pchar-nil-width');
    ReadLn(F,Line);
    if Line<>'C   D' then
      Fail('pchar-empty-width');
    ReadLn(F,Line);
    if Line<>'E  xyF' then
      Fail('pchar-value-width');
    Close(F);
  finally
    DeleteFile(FileName);
  end;
end;

procedure CheckWideRandomRange;
var
  I: Integer;
  SawNegative,SawPositive,SawDifferent: Boolean;
  Value,Previous: Int64;
begin
  if RandomRange(Int64(7),Int64(7))<>7 then
    Fail('random-equal');

  RandSeed:=123456;
  SawNegative:=False;
  SawPositive:=False;
  SawDifferent:=False;
  Previous:=RandomRange(Low(Int64),High(Int64));
  for I:=1 to 255 do
    begin
      Value:=RandomRange(Low(Int64),High(Int64));
      SawNegative:=SawNegative or (Value<0);
      SawPositive:=SawPositive or (Value>=0);
      SawDifferent:=SawDifferent or (Value<>Previous);
      Previous:=Value;
    end;
  if not(SawNegative and SawPositive and SawDifferent) then
    Fail('random-full-width-degenerate');

  for I:=0 to 255 do
    begin
      Value:=RandomRange(Int64(0),Low(Int64));
      if Value>=0 then
        Fail('random-negative-half-forward');
      Value:=RandomRange(Low(Int64),Int64(0));
      if Value>=0 then
        Fail('random-negative-half-reverse');
      Value:=RandomRange(Int64(10),Int64(-10));
      if (Value< -10) or (Value>=10) then
        Fail('random-reversed-bounds');
    end;
end;

begin
  CheckUnsignedParsing;
  CheckPointerTextWidth;
  CheckWideRandomRange;
  WriteLn('RTL_EDGE_CONTRACTS_OK');
end.
