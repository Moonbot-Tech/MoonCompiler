program tcpstr29;

{$mode delphi}
{$H+}

uses
  ucpstr29;

procedure Check(const S: RawByteString; ExpectedCodePage: Word;
  const ExpectedValue: RawByteString; Failure: Byte);
begin
  if StringCodePage(S) <> ExpectedCodePage then
    Halt(Failure);
  if S <> ExpectedValue then
    Halt(Failure + 1);
end;

function RuntimeValue: Integer; noinline;
begin
  Result := 789 + ParamCount;
end;

var
  S866: TAnsi866;
  S1251: TAnsi1251;
  SUtf8: TUtf8;
  SRaw: RawByteString;
  SShort: ShortString;
  SWide: UnicodeString;
begin
  { The destination type comes from a PPU and the fold happens here. }
  Str(123, S866);
  Check(S866, 866, '123', 1);

  { A one-character result follows the same destination encoding contract. }
  Str(7, S866);
  Check(S866, 866, '7', 3);

  Str(High(QWord), S1251);
  Check(S1251, 1251, '18446744073709551615', 5);

  Str(Low(Int64), SUtf8);
  Check(SUtf8, 65001, '-9223372036854775808', 7);

  { These folds happen while the producer unit is compiled. }
  FoldInUnit(S866);
  Check(S866, 866, '456', 9);
  FormatInUnit(S1251);
  Check(S1251, 1251, '    -123', 11);

  { This inline tree is loaded from the producer PPU before it is folded. }
  InlineFoldFromPpu(S866);
  Check(S866, 866, '321', 13);

  { Nonconstant values must retain the live helper path and its code page. }
  Str(RuntimeValue, S866);
  Check(S866, 866, '789', 15);
  LiveInUnit(SUtf8, RuntimeValue);
  Check(SUtf8, 65001, '789', 17);

  { RawByteString deliberately carries the neutral runtime code page. }
  Str(123, SRaw);
  Check(SRaw, 0, '123', 19);

  { Empty dynamic strings have no header and report the system code page. }
  S866 := '';
  Check(S866, DefaultSystemCodePage, '', 21);

  { Neighboring string kinds retain their values. }
  Str(7, SShort);
  if SShort <> '7' then
    Halt(23);
  Str(-4, SWide);
  if SWide <> '-4' then
    Halt(24);
end.
