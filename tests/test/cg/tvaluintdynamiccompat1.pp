{ %OPT=-O3 }
program tvaluintdynamiccompat1;

{$H+}

procedure SetTexts(const Text: ShortString; var S8: ShortString;
  var SA: AnsiString; var SW: WideString; var SU: UnicodeString);
begin
  S8:=Text;
  SA:=Text;
  SW:=Text;
  SU:=Text;
end;

procedure CheckByte;
var
  S8: ShortString;
  SA: AnsiString;
  SW: WideString;
  SU: UnicodeString;
  Value: Byte;
  Code: Integer;
begin
  SetTexts('256',S8,SA,SW,SU);
  Val(S8,Value,Code); If (Value<>0) or (Code<>3) then Halt(1);
  Val(SA,Value,Code); If (Value<>0) or (Code<>0) then Halt(2);
  Val(SW,Value,Code); If (Value<>0) or (Code<>0) then Halt(3);
  Val(SU,Value,Code); If (Value<>0) or (Code<>0) then Halt(4);
end;

procedure CheckWord;
var
  S8: ShortString;
  SA: AnsiString;
  SW: WideString;
  SU: UnicodeString;
  Value: Word;
  Code: Integer;
begin
  SetTexts('65536',S8,SA,SW,SU);
  Val(S8,Value,Code); If (Value<>0) or (Code<>5) then Halt(5);
  Val(SA,Value,Code); If (Value<>0) or (Code<>0) then Halt(6);
  Val(SW,Value,Code); If (Value<>0) or (Code<>0) then Halt(7);
  Val(SU,Value,Code); If (Value<>0) or (Code<>0) then Halt(8);
end;

procedure CheckCardinal;
var
  S8: ShortString;
  SA: AnsiString;
  SW: WideString;
  SU: UnicodeString;
  Value: Cardinal;
  Code: Integer;
begin
  SetTexts('4294967296',S8,SA,SW,SU);
  Val(S8,Value,Code); If (Value<>0) or (Code<>10) then Halt(9);
  Val(SA,Value,Code); If (Value<>0) or (Code<>0) then Halt(10);
  Val(SW,Value,Code); If (Value<>0) or (Code<>0) then Halt(11);
  Val(SU,Value,Code); If (Value<>0) or (Code<>0) then Halt(12);
end;

procedure CheckWhitespaceAndSign;
var
  S8: ShortString;
  SA: AnsiString;
  SW: WideString;
  SU: UnicodeString;
  Value: UInt64;
  Code: Integer;
begin
  SetTexts(#9'42',S8,SA,SW,SU);
  Val(S8,Value,Code); If (Value<>42) or (Code<>0) then Halt(13);
  Val(SA,Value,Code); If (Value<>42) or (Code<>0) then Halt(14);
  Val(SW,Value,Code); If (Value<>42) or (Code<>0) then Halt(15);
  Val(SU,Value,Code); If (Value<>42) or (Code<>0) then Halt(16);

  SetTexts('-1',S8,SA,SW,SU);
  Val(S8,Value,Code); If (Value<>0) or (Code<>1) then Halt(17);
  Val(SA,Value,Code); If (Value<>0) or (Code<>1) then Halt(18);
  Val(SW,Value,Code); If (Value<>0) or (Code<>1) then Halt(19);
  Val(SU,Value,Code); If (Value<>0) or (Code<>1) then Halt(20);
end;

begin
  CheckByte;
  CheckWord;
  CheckCardinal;
  CheckWhitespaceAndSign;
end.
