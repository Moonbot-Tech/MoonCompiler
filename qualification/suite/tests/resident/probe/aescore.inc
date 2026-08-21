type
  TAesKey = array[0 .. 15] of Byte;
  TAesBlock = array[0 .. 15] of Byte;
  TAesSchedule = array[0 .. 175] of Byte;


const
  SBox: array[0 .. 255] of Byte = (
    $63, $7C, $77, $7B, $F2, $6B, $6F, $C5, $30, $01, $67, $2B, $FE, $D7, $AB, $76,
    $CA, $82, $C9, $7D, $FA, $59, $47, $F0, $AD, $D4, $A2, $AF, $9C, $A4, $72, $C0,
    $B7, $FD, $93, $26, $36, $3F, $F7, $CC, $34, $A5, $E5, $F1, $71, $D8, $31, $15,
    $04, $C7, $23, $C3, $18, $96, $05, $9A, $07, $12, $80, $E2, $EB, $27, $B2, $75,
    $09, $83, $2C, $1A, $1B, $6E, $5A, $A0, $52, $3B, $D6, $B3, $29, $E3, $2F, $84,
    $53, $D1, $00, $ED, $20, $FC, $B1, $5B, $6A, $CB, $BE, $39, $4A, $4C, $58, $CF,
    $D0, $EF, $AA, $FB, $43, $4D, $33, $85, $45, $F9, $02, $7F, $50, $3C, $9F, $A8,
    $51, $A3, $40, $8F, $92, $9D, $38, $F5, $BC, $B6, $DA, $21, $10, $FF, $F3, $D2,
    $CD, $0C, $13, $EC, $5F, $97, $44, $17, $C4, $A7, $7E, $3D, $64, $5D, $19, $73,
    $60, $81, $4F, $DC, $22, $2A, $90, $88, $46, $EE, $B8, $14, $DE, $5E, $0B, $DB,
    $E0, $32, $3A, $0A, $49, $06, $24, $5C, $C2, $D3, $AC, $62, $91, $95, $E4, $79,
    $E7, $C8, $37, $6D, $8D, $D5, $4E, $A9, $6C, $56, $F4, $EA, $65, $7A, $AE, $08,
    $BA, $78, $25, $2E, $1C, $A6, $B4, $C6, $E8, $DD, $74, $1F, $4B, $BD, $8B, $8A,
    $70, $3E, $B5, $66, $48, $03, $F6, $0E, $61, $35, $57, $B9, $86, $C1, $1D, $9E,
    $E1, $F8, $98, $11, $69, $D9, $8E, $94, $9B, $1E, $87, $E9, $CE, $55, $28, $DF,
    $8C, $A1, $89, $0D, $BF, $E6, $42, $68, $41, $99, $2D, $0F, $B0, $54, $BB, $16);
  KeyRef: array[0..15] of Byte = ($2B,$7E,$15,$16,$28,$AE,$D2,$A6,$AB,$F7,$15,$88,$09,$CF,$4F,$3C);
  PlainRef: array[0..15] of Byte = ($32,$43,$F6,$A8,$88,$5A,$30,$8D,$31,$31,$98,$A2,$E0,$37,$07,$34);

function GfMul(A, B: Byte): Byte;
var
  Product: Byte;
  I: Integer;
  High_: Boolean;
begin
  Product := 0;
  for I := 0 to 7 do
  begin
    if (B and 1) <> 0 then
      Product := Product xor A;
    High_ := (A and $80) <> 0;
    A := Byte(A shl 1);
    if High_ then
      A := A xor $1B;
    B := B shr 1;
  end;
  Result := Product;
end;
procedure ExpandKey(const Key: TAesKey; out Schedule: TAesSchedule);
var
  I: Integer;
  Temp: array[0 .. 3] of Byte;
  Rcon: Byte;
begin
  for I := 0 to 15 do
    Schedule[I] := Key[I];
  Rcon := 1;
  I := 16;
  while I < 176 do
  begin
    Temp[0] := Schedule[I - 4];
    Temp[1] := Schedule[I - 3];
    Temp[2] := Schedule[I - 2];
    Temp[3] := Schedule[I - 1];
    if I mod 16 = 0 then
    begin
      { Поворот, подстановка и добавление раундовой константы. }
      var T := Temp[0];
      Temp[0] := SBox[Temp[1]] xor Rcon;
      Temp[1] := SBox[Temp[2]];
      Temp[2] := SBox[Temp[3]];
      Temp[3] := SBox[T];
      Rcon := GfMul(Rcon, 2);
    end;
    Schedule[I] := Schedule[I - 16] xor Temp[0];
    Schedule[I + 1] := Schedule[I - 15] xor Temp[1];
    Schedule[I + 2] := Schedule[I - 14] xor Temp[2];
    Schedule[I + 3] := Schedule[I - 13] xor Temp[3];
    Inc(I, 4);
  end;
end;
procedure AddRoundKey(var Block: TAesBlock; const Schedule: TAesSchedule;
  Round_: Integer);
var
  I: Integer;
begin
  for I := 0 to 15 do
    Block[I] := Block[I] xor Schedule[Round_ * 16 + I];
end;
procedure EncryptBlock(var Block: TAesBlock; const Schedule: TAesSchedule);
var
  Round_, I, C: Integer;
  Temp: TAesBlock;
  A0, A1, A2, A3: Byte;
begin
  AddRoundKey(Block, Schedule, 0);
  for Round_ := 1 to 10 do
  begin
    for I := 0 to 15 do
      Block[I] := SBox[Block[I]];

    { Сдвиг строк: строка r сдвигается влево на r позиций. Состояние лежит по
      столбцам, поэтому строка — это каждый четвёртый байт. }
    Temp := Block;
    for I := 0 to 3 do
    begin
      Block[I * 4 + 1] := Temp[((I + 1) mod 4) * 4 + 1];
      Block[I * 4 + 2] := Temp[((I + 2) mod 4) * 4 + 2];
      Block[I * 4 + 3] := Temp[((I + 3) mod 4) * 4 + 3];
    end;

    if Round_ < 10 then
      for C := 0 to 3 do
      begin
        A0 := Block[C * 4];
        A1 := Block[C * 4 + 1];
        A2 := Block[C * 4 + 2];
        A3 := Block[C * 4 + 3];
        Block[C * 4] := GfMul(A0, 2) xor GfMul(A1, 3) xor A2 xor A3;
        Block[C * 4 + 1] := A0 xor GfMul(A1, 2) xor GfMul(A2, 3) xor A3;
        Block[C * 4 + 2] := A0 xor A1 xor GfMul(A2, 2) xor GfMul(A3, 3);
        Block[C * 4 + 3] := GfMul(A0, 3) xor A1 xor A2 xor GfMul(A3, 2);
      end;

    AddRoundKey(Block, Schedule, Round_);
  end;
end;
