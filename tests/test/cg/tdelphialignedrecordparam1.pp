program tdelphialignedrecordparam1;

{$mode delphi}

type
  TAligned1 = record
    Value: Byte;
  end align 8;

  TAligned4 = record
    Flag: Boolean;
    Bytes: array[0..2] of Byte;
  end align 8;

  TAligned7 = record
    Bytes: array[0..6] of Byte;
  end align 8;

  TAligned16 = record
    Flag: Boolean;
    Bytes: array[0..2] of Byte;
  end align 16;

function Read1(Value: TAligned1): Cardinal; noinline;
begin
  Result := Value.Value;
  Value.Value := 0;
end;

function Read4(Value: TAligned4): Cardinal; noinline;
begin
  Result := Ord(Value.Flag) or
    (Cardinal(Value.Bytes[0]) shl 8) or
    (Cardinal(Value.Bytes[1]) shl 16) or
    (Cardinal(Value.Bytes[2]) shl 24);
  FillChar(Value, SizeOf(Value), 0);
end;

function Read7(Value: TAligned7): QWord; noinline;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(Value.Bytes) do
    Result := Result or (QWord(Value.Bytes[I]) shl (I * 8));
  FillChar(Value, SizeOf(Value), 0);
end;

function Read16(Value: TAligned16): Cardinal; noinline;
begin
  Result := Ord(Value.Flag) or
    (Cardinal(Value.Bytes[0]) shl 8) or
    (Cardinal(Value.Bytes[1]) shl 16) or
    (Cardinal(Value.Bytes[2]) shl 24);
  FillChar(Value, SizeOf(Value), 0);
end;

var
  A1: TAligned1;
  A4: TAligned4;
  A7: TAligned7;
  A16: TAligned16;
begin
  FillChar(A1, SizeOf(A1), 0);
  A1.Value := $5a;
  if Read1(A1) <> $5a then
    Halt(1);
  if A1.Value <> $5a then
    Halt(2);

  FillChar(A4, SizeOf(A4), 0);
  A4.Flag := True;
  A4.Bytes[0] := $23;
  A4.Bytes[1] := $45;
  A4.Bytes[2] := $67;
  if Read4(A4) <> $67452301 then
    Halt(3);
  if (not A4.Flag) or (A4.Bytes[0] <> $23) or
      (A4.Bytes[1] <> $45) or (A4.Bytes[2] <> $67) then
    Halt(4);

  FillChar(A7, SizeOf(A7), 0);
  A7.Bytes[0] := $01;
  A7.Bytes[1] := $02;
  A7.Bytes[2] := $03;
  A7.Bytes[3] := $04;
  A7.Bytes[4] := $05;
  A7.Bytes[5] := $06;
  A7.Bytes[6] := $07;
  if Read7(A7) <> QWord($0007060504030201) then
    Halt(5);
  if (A7.Bytes[0] <> $01) or (A7.Bytes[6] <> $07) then
    Halt(6);

  FillChar(A16, SizeOf(A16), 0);
  A16.Flag := True;
  A16.Bytes[0] := $89;
  A16.Bytes[1] := $ab;
  A16.Bytes[2] := $cd;
  if Read16(A16) <> $cdab8901 then
    Halt(7);
  if (not A16.Flag) or (A16.Bytes[0] <> $89) or
      (A16.Bytes[1] <> $ab) or (A16.Bytes[2] <> $cd) then
    Halt(8);
end.
