program tdelphirawbyteconcat1;

{$ifdef FPC}
  {$mode delphi}
  {$codepage utf8}
{$endif}
{$h+}

uses
{$ifdef UNIX}
  cwstring,
{$endif}
{$ifdef FPC}
  SysUtils;
{$else}
  System.SysUtils;
{$endif}

type
  TAnsi1251 = type AnsiString(1251);
  TAnsiUtf8 = type AnsiString(65001);
  TAnsi850 = type AnsiString(850);
  TAnsi866 = type AnsiString(866);

procedure Fail(Code: Integer);
begin
  Halt(Code);
end;

procedure PutBytes(var S: RawByteString; const Bytes: array of Byte;
  CodePage: Word);
var
  I: Integer;
begin
  SetLength(S, Length(Bytes));
  for I := 0 to High(Bytes) do
    S[I + 1] := AnsiChar(Bytes[I]);
  SetCodePage(S, CodePage, False);
end;

procedure CheckBytes(const S: RawByteString; const Bytes: array of Byte;
  Code: Integer);
var
  I: Integer;
begin
  if Length(S) <> Length(Bytes) then
    Fail(Code);
  for I := 0 to High(Bytes) do
    if Byte(S[I + 1]) <> Bytes[I] then
      Fail(Code);
end;

var
  A, B, C, R: RawByteString;
  U, WideTail: UnicodeString;
  WideTailPtr: PWideChar;
  A1251: TAnsi1251;
  AUtf8: TAnsiUtf8;
  A850: TAnsi850;
  A866: TAnsi866;
  Short: ShortString;
  Ch: AnsiChar;
begin
  PutBytes(A, [$41, $C3], 1251);
  PutBytes(B, [$C2, $A9, $42], 65001);
  PutBytes(C, [$80, $FF], 866);

  R := A + B;
  CheckBytes(R, [$41, $C3, $C2, $A9, $42], 1);
  if StringCodePage(R) <> 1251 then
    Fail(2);

  R := A + B + C;
  CheckBytes(R, [$41, $C3, $C2, $A9, $42, $80, $FF], 3);
  if StringCodePage(R) <> 1251 then
    Fail(4);

  R := A;
  R := R + B;
  CheckBytes(R, [$41, $C3, $C2, $A9, $42], 5);
  if StringCodePage(R) <> 1251 then
    Fail(6);

  R := RawByteString('') + B;
  CheckBytes(R, [$C2, $A9, $42], 7);
  if StringCodePage(R) <> 65001 then
    Fail(8);

  PutBytes(R, [$C3, $A9], 1251);
  if R <> RawByteString(#$C3#$A9) then
    Fail(9);

  A1251 := TAnsi1251(R);
  SetCodePage(R, 65001, False);
  AUtf8 := TAnsiUtf8(R);
  Short := #$C3#$A9;
  Ch := 'A';
  if not ((R = A1251) and (A1251 = R) and
          (R = AUtf8) and (AUtf8 = R) and
          (R = Short) and (Short = R) and
          (RawByteString('A') = Ch) and (Ch = RawByteString('A'))) then
    Fail(10);

  A850 := 'a';
  A866 := 'b';
  R := A850 + A866;
  if StringCodePage(R) <> DefaultSystemCodePage then
    Fail(11);
  R := A850 + A850;
  if StringCodePage(R) <> DefaultSystemCodePage then
    Fail(12);

  R := RawByteString('raw/') + RawByteString(#$C3#$A9);
  CheckBytes(R, [$72, $61, $77, $2F, $C3, $A9], 13);

  R := B + '!';
  CheckBytes(R, [$C2, $A9, $42, $21], 14);
  R := '!' + B;
  CheckBytes(R, [$21, $C2, $A9, $42], 15);

  { A genuinely Unicode operand must still select Unicode semantics. }
  U := B + UnicodeString(#$03A9);
  if U <> UnicodeString(#$00A9'B'#$03A9) then
    Fail(16);
  WideTail := #$03A9;
  WideTailPtr := PWideChar(WideTail);
  U := B + WideTailPtr;
  if U <> UnicodeString(#$00A9'B'#$03A9) then
    Fail(17);
end.
