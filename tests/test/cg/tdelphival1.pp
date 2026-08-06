{ %OPT=-O3 }
program tdelphival1;

{$ifdef FPC}
  {$mode delphi}
  {$H+}
{$endif}

procedure CheckInteger(const Text: string; ExpectedValue, ExpectedCode: Integer; ExitCode: Byte);
var
  Value, Code: Integer;
begin
  Value := 12345;
  Val(Text, Value, Code);
  If (Value <> ExpectedValue) or (Code <> ExpectedCode) then Halt(ExitCode);
end;

procedure SetTexts(const Text: ShortString; out S8: ShortString;
  out SA: AnsiString; out SW: WideString; out SU: UnicodeString);
begin
  S8 := Text;
  SA := Text;
  SW := Text;
  SU := Text;
end;

procedure CheckWidthMatrix;
var
  S8: ShortString;
  SA: AnsiString;
  SW: WideString;
  SU: UnicodeString;
  Code: Integer;
  SInt8: ShortInt;
  UInt8: Byte;
  SInt16: SmallInt;
  UInt16: Word;
  SInt32: Integer;
  UInt32: Cardinal;
  SInt64: Int64;
  UInt64Value: UInt64;
begin
  SetTexts('128', S8, SA, SW, SU);
  Val(S8, SInt8, Code); If (SInt8 <> -128) or (Code <> 0) then Halt(20);
  Val(SA, SInt8, Code); If (SInt8 <> -128) or (Code <> 0) then Halt(21);
  Val(SW, SInt8, Code); If (SInt8 <> -128) or (Code <> 0) then Halt(22);
  Val(SU, SInt8, Code); If (SInt8 <> -128) or (Code <> 0) then Halt(23);

  SetTexts('256', S8, SA, SW, SU);
  Val(S8, UInt8, Code); If (UInt8 <> 0) or (Code <> 0) then Halt(24);
  Val(SA, UInt8, Code); If (UInt8 <> 0) or (Code <> 0) then Halt(25);
  Val(SW, UInt8, Code); If (UInt8 <> 0) or (Code <> 0) then Halt(26);
  Val(SU, UInt8, Code); If (UInt8 <> 0) or (Code <> 0) then Halt(27);

  SetTexts('32768', S8, SA, SW, SU);
  Val(S8, SInt16, Code); If (SInt16 <> -32768) or (Code <> 0) then Halt(28);
  Val(SA, SInt16, Code); If (SInt16 <> -32768) or (Code <> 0) then Halt(29);
  Val(SW, SInt16, Code); If (SInt16 <> -32768) or (Code <> 0) then Halt(30);
  Val(SU, SInt16, Code); If (SInt16 <> -32768) or (Code <> 0) then Halt(31);

  SetTexts('65536', S8, SA, SW, SU);
  Val(S8, UInt16, Code); If (UInt16 <> 0) or (Code <> 0) then Halt(32);
  Val(SA, UInt16, Code); If (UInt16 <> 0) or (Code <> 0) then Halt(33);
  Val(SW, UInt16, Code); If (UInt16 <> 0) or (Code <> 0) then Halt(34);
  Val(SU, UInt16, Code); If (UInt16 <> 0) or (Code <> 0) then Halt(35);

  SetTexts('2147483648', S8, SA, SW, SU);
  Val(S8, SInt32, Code); If (SInt32 <> Low(Integer)) or (Code <> 10) then Halt(36);
  Val(SA, SInt32, Code); If (SInt32 <> Low(Integer)) or (Code <> 10) then Halt(37);
  Val(SW, SInt32, Code); If (SInt32 <> Low(Integer)) or (Code <> 10) then Halt(38);
  Val(SU, SInt32, Code); If (SInt32 <> Low(Integer)) or (Code <> 10) then Halt(39);

  SetTexts('4294967296', S8, SA, SW, SU);
  Val(S8, UInt32, Code); If (UInt32 <> 0) or (Code <> 0) then Halt(40);
  Val(SA, UInt32, Code); If (UInt32 <> 0) or (Code <> 0) then Halt(41);
  Val(SW, UInt32, Code); If (UInt32 <> 0) or (Code <> 0) then Halt(42);
  Val(SU, UInt32, Code); If (UInt32 <> 0) or (Code <> 0) then Halt(43);

  SetTexts('9223372036854775808', S8, SA, SW, SU);
  Val(S8, SInt64, Code); If (SInt64 <> Low(Int64)) or (Code <> 19) then Halt(44);
  Val(SA, SInt64, Code); If (SInt64 <> Low(Int64)) or (Code <> 19) then Halt(45);
  Val(SW, SInt64, Code); If (SInt64 <> Low(Int64)) or (Code <> 19) then Halt(46);
  Val(SU, SInt64, Code); If (SInt64 <> Low(Int64)) or (Code <> 19) then Halt(47);

  SetTexts('18446744073709551616', S8, SA, SW, SU);
  Val(S8, UInt64Value, Code); If (UInt64Value <> UInt64(1844674407370955161)) or (Code <> 20) then Halt(48);
  Val(SA, UInt64Value, Code); If (UInt64Value <> UInt64(1844674407370955161)) or (Code <> 20) then Halt(49);
  Val(SW, UInt64Value, Code); If (UInt64Value <> UInt64(1844674407370955161)) or (Code <> 20) then Halt(50);
  Val(SU, UInt64Value, Code); If (UInt64Value <> UInt64(1844674407370955161)) or (Code <> 20) then Halt(51);
end;

procedure CheckUnsignedLexicalMatrix;
var
  S8: ShortString;
  SA: AnsiString;
  SW: WideString;
  SU: UnicodeString;
  Value: UInt64;
  Code: Integer;
begin
  SetTexts('%101', S8, SA, SW, SU);
  Val(S8, Value, Code); If (Value <> 0) or (Code <> 1) then Halt(60);
  Val(SA, Value, Code); If (Value <> 0) or (Code <> 1) then Halt(61);
  Val(SW, Value, Code); If (Value <> 0) or (Code <> 1) then Halt(62);
  Val(SU, Value, Code); If (Value <> 0) or (Code <> 1) then Halt(63);

  SetTexts('&17', S8, SA, SW, SU);
  Val(S8, Value, Code); If (Value <> 0) or (Code <> 1) then Halt(64);
  Val(SA, Value, Code); If (Value <> 0) or (Code <> 1) then Halt(65);
  Val(SW, Value, Code); If (Value <> 0) or (Code <> 1) then Halt(66);
  Val(SU, Value, Code); If (Value <> 0) or (Code <> 1) then Halt(67);

  SetTexts('42 ', S8, SA, SW, SU);
  Val(S8, Value, Code); If (Value <> 42) or (Code <> 3) then Halt(68);
  Val(SA, Value, Code); If (Value <> 42) or (Code <> 3) then Halt(69);
  Val(SW, Value, Code); If (Value <> 42) or (Code <> 3) then Halt(70);
  Val(SU, Value, Code); If (Value <> 42) or (Code <> 3) then Halt(71);

  SetTexts(#9'42', S8, SA, SW, SU);
  Val(S8, Value, Code); If (Value <> 0) or (Code <> 1) then Halt(72);
  Val(SA, Value, Code); If (Value <> 0) or (Code <> 1) then Halt(73);
  Val(SW, Value, Code); If (Value <> 0) or (Code <> 1) then Halt(74);
  Val(SU, Value, Code); If (Value <> 0) or (Code <> 1) then Halt(75);

  SetTexts('-1', S8, SA, SW, SU);
  Val(S8, Value, Code); If (Value <> 0) or (Code <> 2) then Halt(76);
  Val(SA, Value, Code); If (Value <> 0) or (Code <> 2) then Halt(77);
  Val(SW, Value, Code); If (Value <> 0) or (Code <> 2) then Halt(78);
  Val(SU, Value, Code); If (Value <> 0) or (Code <> 2) then Halt(79);
end;

var
  S8: ShortString;
  SA: AnsiString;
  I, Code: Integer;
  I64: Int64;
  U64: UInt64;
begin
  CheckInteger('%101', 0, 1, 1);
  CheckInteger('&17', 0, 1, 2);
  CheckInteger('42 ', 42, 3, 3);

  S8 := '42 ';
  I := 12345;
  Val(S8, I, Code);
  If (I <> 42) or (Code <> 3) then Halt(4);

  SA := '42 ';
  I := 12345;
  Val(SA, I, Code);
  If (I <> 42) or (Code <> 3) then Halt(5);

  Val('2147483648', I, Code);
  If (I <> Low(Integer)) or (Code <> 10) then Halt(6);

  Val('9223372036854775808', I64, Code);
  If (I64 <> Low(Int64)) or (Code <> 19) then Halt(7);

  Val('18446744073709551616', U64, Code);
  If (U64 <> UInt64(1844674407370955161)) or (Code <> 20) then Halt(8);

  CheckWidthMatrix;
  CheckUnsignedLexicalMatrix;
end.
