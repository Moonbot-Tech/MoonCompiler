unit resident_cipher;

{ Шифры — второй после хешей источник **внешнего** эталона.

  Здесь считается по спецификациям, и ответы взяты из них же: блок AES из
  приложения к FIPS-197, поток ChaCha20 из RFC 8439. Эти числа не выводятся из
  нашего кода, поэтому совпадение с ними — настоящий ответ, а не согласие
  программы с самой собой.

  Вес тоже настоящий: раунды AES с подстановкой, сдвигом строк и смешиванием
  столбцов в поле, четверть-раунды ChaCha с вращениями — это длинные цепочки
  зависимых операций, где каждый шаг ждёт предыдущего.

  И третье, ради чего они здесь: **обратимость**. Зашифрованное и расшифрованное
  обязано совпасть с исходным байт в байт, причём расшифровывает другой поток —
  ключ и данные едут к нему, ответ едет обратно. }

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch INLINEVARS}
{$endif}
{$Q-}{$R-}

interface

uses
  SysUtils, Classes, Generics.Collections, resident_core, resident_hash;

implementation

type
  TAesKey = array[0 .. 15] of Byte;
  TAesBlock = array[0 .. 15] of Byte;
  TAesSchedule = array[0 .. 175] of Byte;

  TChaChaState = array[0 .. 15] of Cardinal;
  TChaChaKey = array[0 .. 31] of Byte;
  TChaChaNonce = array[0 .. 11] of Byte;

const
  { Таблица подстановки AES — из спецификации. }
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

  { Известные ответы. AES — приложение B к FIPS-197. }
  AesKeyHex = '2B7E151628AED2A6ABF7158809CF4F3C';
  AesPlainHex = '3243F6A8885A308D313198A2E0370734';
  AesCipherHex = '3925841D02DC09FBDC118597196A0B32';

var
  InvSBox: array[0 .. 255] of Byte;

type
  { Поток, которому отдают ключ и шифротекст: он расшифровывает и возвращает
    открытый текст. Данные приходят до старта, ответ забирают после завершения. }
  TDecipherHand = class(TThread)
  private
    FKey: TAesKey;
    FData: TBytes;
    FPlain: TBytes;
  public
    constructor Create(const AKey: TAesKey; const AData: TBytes);
    procedure Execute; override;
    property Plain: TBytes read FPlain;
  end;

  TResidentCipherPocket = class(TResidentPocket)
  private
    FStream: TBytes;
    FRounds: Int64;
  end;



function HexToBytes(const S: string): TBytes;
var
  I, V: Integer;

  function Digit(C: Char): Integer;
  begin
    case C of
      '0' .. '9': Result := Ord(C) - Ord('0');
      'A' .. 'F': Result := Ord(C) - Ord('A') + 10;
      'a' .. 'f': Result := Ord(C) - Ord('a') + 10;
    else
      Result := 0;
    end;
  end;

begin
  SetLength(Result, Length(S) div 2);
  for I := 0 to High(Result) do
  begin
    V := Digit(S[I * 2 + 1]) * 16 + Digit(S[I * 2 + 2]);
    Result[I] := Byte(V);
  end;
end;

function BytesToHex(const B: TBytes): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(B) do
    Result := Result + IntToHex(B[I], 2);
end;

{ --------------------------------------------------------------- AES ------ }

{ Умножение в поле из 256 элементов: сдвиг с приведением по неприводимому
  многочлену. Это сердце смешивания столбцов. }
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

procedure DecryptBlock(var Block: TAesBlock; const Schedule: TAesSchedule);
var
  Round_, I, C: Integer;
  Temp: TAesBlock;
  A0, A1, A2, A3: Byte;
begin
  AddRoundKey(Block, Schedule, 10);
  for Round_ := 9 downto 0 do
  begin
    { Обратный сдвиг строк. }
    Temp := Block;
    for I := 0 to 3 do
    begin
      Block[((I + 1) mod 4) * 4 + 1] := Temp[I * 4 + 1];
      Block[((I + 2) mod 4) * 4 + 2] := Temp[I * 4 + 2];
      Block[((I + 3) mod 4) * 4 + 3] := Temp[I * 4 + 3];
    end;

    for I := 0 to 15 do
      Block[I] := InvSBox[Block[I]];

    AddRoundKey(Block, Schedule, Round_);

    if Round_ > 0 then
      for C := 0 to 3 do
      begin
        A0 := Block[C * 4];
        A1 := Block[C * 4 + 1];
        A2 := Block[C * 4 + 2];
        A3 := Block[C * 4 + 3];
        Block[C * 4] := GfMul(A0, 14) xor GfMul(A1, 11) xor GfMul(A2, 13) xor
                        GfMul(A3, 9);
        Block[C * 4 + 1] := GfMul(A0, 9) xor GfMul(A1, 14) xor GfMul(A2, 11) xor
                            GfMul(A3, 13);
        Block[C * 4 + 2] := GfMul(A0, 13) xor GfMul(A1, 9) xor GfMul(A2, 14) xor
                            GfMul(A3, 11);
        Block[C * 4 + 3] := GfMul(A0, 11) xor GfMul(A1, 13) xor GfMul(A2, 9) xor
                            GfMul(A3, 14);
      end;
  end;
end;

{ Шифрование потока блоками со сцеплением: каждый блок перед шифрованием
  складывается с предыдущим шифротекстом, поэтому одинаковые куски открытого
  текста дают разный шифр. }
function EncryptChained(const Key: TAesKey; const Data: TBytes): TBytes;
var
  Schedule: TAesSchedule;
  Block, Prev: TAesBlock;
  I, J, Blocks: Integer;
begin
  ExpandKey(Key, Schedule);
  Blocks := Length(Data) div 16;
  SetLength(Result, Blocks * 16);
  FillChar(Prev, SizeOf(Prev), 0);
  for I := 0 to Blocks - 1 do
  begin
    for J := 0 to 15 do
      Block[J] := Data[I * 16 + J] xor Prev[J];
    EncryptBlock(Block, Schedule);
    for J := 0 to 15 do
      Result[I * 16 + J] := Block[J];
    Prev := Block;
  end;
end;

function DecryptChained(const Key: TAesKey; const Data: TBytes): TBytes;
var
  Schedule: TAesSchedule;
  Block, Prev, Cipher: TAesBlock;
  I, J, Blocks: Integer;
begin
  ExpandKey(Key, Schedule);
  Blocks := Length(Data) div 16;
  SetLength(Result, Blocks * 16);
  FillChar(Prev, SizeOf(Prev), 0);
  for I := 0 to Blocks - 1 do
  begin
    for J := 0 to 15 do
      Block[J] := Data[I * 16 + J];
    Cipher := Block;
    DecryptBlock(Block, Schedule);
    for J := 0 to 15 do
      Result[I * 16 + J] := Block[J] xor Prev[J];
    Prev := Cipher;
  end;
end;

{ ----------------------------------------------------------- ChaCha20 ----- }

function RotL(Value: Cardinal; Bits: Integer): Cardinal; inline;
begin
  Result := (Value shl Bits) or (Value shr (32 - Bits));
end;

procedure ChaChaBlock(const Key: TChaChaKey; const Nonce: TChaChaNonce;
  Counter: Cardinal; out Output_: array of Byte);
var
  State, Work: TChaChaState;
  I, R: Integer;

  procedure Quarter(var A, B, C, D: Cardinal);
  begin
    A := A + B;
    D := RotL(D xor A, 16);
    C := C + D;
    B := RotL(B xor C, 12);
    A := A + B;
    D := RotL(D xor A, 8);
    C := C + D;
    B := RotL(B xor C, 7);
  end;

begin
  { Первые четыре слова — постоянные из спецификации: "expand 32-byte k". }
  State[0] := $61707865;
  State[1] := $3320646E;
  State[2] := $79622D32;
  State[3] := $6B206574;
  for I := 0 to 7 do
    State[4 + I] := Cardinal(Key[I * 4]) or (Cardinal(Key[I * 4 + 1]) shl 8) or
                    (Cardinal(Key[I * 4 + 2]) shl 16) or
                    (Cardinal(Key[I * 4 + 3]) shl 24);
  State[12] := Counter;
  for I := 0 to 2 do
    State[13 + I] := Cardinal(Nonce[I * 4]) or (Cardinal(Nonce[I * 4 + 1]) shl 8) or
                     (Cardinal(Nonce[I * 4 + 2]) shl 16) or
                     (Cardinal(Nonce[I * 4 + 3]) shl 24);

  Work := State;
  for R := 1 to 10 do
  begin
    { Столбцы. }
    Quarter(Work[0], Work[4], Work[8], Work[12]);
    Quarter(Work[1], Work[5], Work[9], Work[13]);
    Quarter(Work[2], Work[6], Work[10], Work[14]);
    Quarter(Work[3], Work[7], Work[11], Work[15]);
    { Диагонали. }
    Quarter(Work[0], Work[5], Work[10], Work[15]);
    Quarter(Work[1], Work[6], Work[11], Work[12]);
    Quarter(Work[2], Work[7], Work[8], Work[13]);
    Quarter(Work[3], Work[4], Work[9], Work[14]);
  end;

  for I := 0 to 15 do
  begin
    Work[I] := Work[I] + State[I];
    Output_[I * 4] := Byte(Work[I] and $FF);
    Output_[I * 4 + 1] := Byte((Work[I] shr 8) and $FF);
    Output_[I * 4 + 2] := Byte((Work[I] shr 16) and $FF);
    Output_[I * 4 + 3] := Byte((Work[I] shr 24) and $FF);
  end;
end;

{ Шифрование потоком: гамма складывается с данными. Расшифрование — та же
  операция, поэтому обратимость здесь встроена в устройство шифра. }
procedure ChaChaApply(const Key: TChaChaKey; const Nonce: TChaChaNonce;
  Counter: Cardinal; var Data: TBytes);
var
  Gamma: array[0 .. 63] of Byte;
  I, Block, Taken: Integer;
begin
  Block := 0;
  I := 0;
  while I < Length(Data) do
  begin
    ChaChaBlock(Key, Nonce, Counter + Cardinal(Block), Gamma);
    Taken := Length(Data) - I;
    if Taken > 64 then
      Taken := 64;
    for var J := 0 to Taken - 1 do
      Data[I + J] := Data[I + J] xor Gamma[J];
    Inc(I, Taken);
    Inc(Block);
  end;
end;

constructor TDecipherHand.Create(const AKey: TAesKey; const AData: TBytes);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FKey := AKey;
  FData := AData;
end;

procedure TDecipherHand.Execute;
begin
  FPlain := DecryptChained(FKey, FData);
end;

function SameBytes(const A, B: TBytes): Boolean;
begin
  Result := Length(A) = Length(B);
  if Result and (Length(A) > 0) then
    Result := CompareMem(@A[0], @B[0], Length(A));
end;

{ ------------------------------------------------------------- стадии ----- }

{ Известные ответы из спецификаций: один блок AES и его расшифровка. }
procedure StageAesVector(Carrier: TResidentCarrier);
var
  KeyBytes, PlainBytes, WantBytes: TBytes;
  Key: TAesKey;
  Block: TAesBlock;
  Schedule: TAesSchedule;
  I: Integer;
begin
  KeyBytes := HexToBytes(AesKeyHex);
  PlainBytes := HexToBytes(AesPlainHex);
  WantBytes := HexToBytes(AesCipherHex);
  for I := 0 to 15 do
  begin
    Key[I] := KeyBytes[I];
    Block[I] := PlainBytes[I];
  end;

  ExpandKey(Key, Schedule);
  EncryptBlock(Block, Schedule);

  var Got: TBytes;
  SetLength(Got, 16);
  for I := 0 to 15 do
    Got[I] := Block[I];
  Carrier.Claim(SameBytes(Got, WantBytes), 'aes: block does not match FIPS-197');
  Carrier.FeedWide(BytesToHex(Got));

  { Расшифровка обязана вернуть исходный блок. }
  DecryptBlock(Block, Schedule);
  for I := 0 to 15 do
    Got[I] := Block[I];
  Carrier.Claim(SameBytes(Got, PlainBytes), 'aes: decrypt did not restore the block');

  { Умножение в поле: проверяемые свойства без всякого эталона. }
  Carrier.Claim(GfMul(1, 1) = 1, 'gf: one is not neutral');
  Carrier.Claim(GfMul(2, 3) = GfMul(3, 2), 'gf: multiplication is not commutative');
  Carrier.Claim(GfMul(GfMul(2, 3), 5) = GfMul(2, GfMul(3, 5)),
                'gf: multiplication is not associative');
  Carrier.Claim(GfMul(14, 9) <> 0, 'gf: product of nonzero is zero');
  { Подстановка обязана быть перестановкой: обратная возвращает исходное. }
  for I := 0 to 255 do
    Carrier.Claim(InvSBox[SBox[I]] = Byte(I), 'aes: substitution is not a permutation');
end;

{ Поток данных через шифр со сцеплением и обратно — причём расшифровывает
  другой поток. Данные и ключ едут к нему, ответ едет обратно. }
procedure StageAesHandoff(Carrier: TResidentCarrier);
var
  Key: TAesKey;
  Plain, Cipher: TBytes;
  Hands: array[0 .. 2] of TDecipherHand;
  State: UInt64;
  I, Size: Integer;
  Agreed: Boolean;
begin
  State := ResidentMix(Carrier.Seed,
                       UInt64(Cardinal(Carrier.Serial * 7 + Carrier.Lap)));
  for I := 0 to 15 do
    Key[I] := Byte(ResidentNext(State) and $FF);

  { Каждый заход шифрует свой объём, кратный блоку. }
  Size := 16 * (32 + (Carrier.Lap mod 24) * 16);
  SetLength(Plain, Size);
  for I := 0 to Size - 1 do
    Plain[I] := Byte(ResidentNext(State) and $FF);

  Cipher := EncryptChained(Key, Plain);
  Carrier.Claim(Length(Cipher) = Length(Plain), 'aes: length changed');
  Carrier.Claim(not SameBytes(Cipher, Plain), 'aes: ciphertext equals plaintext');
  Carrier.Feed(UInt64(Cardinal(Size)));
  Carrier.FeedWide(BytesToHex(System.Copy(Cipher, 0, 16)));

  { Сцепление работает: два одинаковых блока подряд дают разный шифр. }
  if Size >= 32 then
  begin
    var Twin := System.Copy(Plain, 0, Size);
    for I := 0 to 15 do
      Twin[16 + I] := Twin[I];
    var TwinCipher := EncryptChained(Key, Twin);
    Carrier.Claim(not CompareMem(@TwinCipher[0], @TwinCipher[16], 16),
                  'aes: identical blocks produced identical ciphertext');
  end;

  { Расшифровка в трёх других потоках: каждый обязан вернуть исходное. }
  for I := 0 to High(Hands) do
    Hands[I] := TDecipherHand.Create(Key, Cipher);
  try
    for I := 0 to High(Hands) do
      Hands[I].Start;
    Agreed := True;
    for I := 0 to High(Hands) do
    begin
      Hands[I].WaitFor;
      if not SameBytes(Hands[I].Plain, Plain) then
        Agreed := False;
    end;
  finally
    for I := 0 to High(Hands) do
      Hands[I].Free;
  end;
  Carrier.Claim(Agreed, 'aes: another thread failed to restore the plaintext');
end;

{ Потоковый шифр: известный ответ из RFC, обратимость и независимость от того,
  какими кусками подавали данные. }
procedure StageChaCha(Carrier: TResidentCarrier);
var
  Key: TChaChaKey;
  Nonce: TChaChaNonce;
  Gamma: array[0 .. 63] of Byte;
  Data, Once, Twin: TBytes;
  State: UInt64;
  I, Size: Integer;
begin
  { Ключ и одноразовое число из RFC 8439: ключ 00..1f, число 00 00 00 09 ... }
  for I := 0 to 31 do
    Key[I] := Byte(I);
  FillChar(Nonce, SizeOf(Nonce), 0);
  Nonce[3] := $09;
  Nonce[7] := $4A;

  ChaChaBlock(Key, Nonce, 1, Gamma);
  { Первые байты гаммы — из спецификации. }
  Carrier.Claim(Gamma[0] = $10, 'chacha: first keystream byte differs from RFC 8439');
  Carrier.Claim(Gamma[1] = $F1, 'chacha: second keystream byte differs from RFC 8439');
  Carrier.Claim(Gamma[2] = $E7, 'chacha: third keystream byte differs from RFC 8439');
  Carrier.Claim(Gamma[63] = $4E, 'chacha: last keystream byte differs from RFC 8439');
  for I := 0 to 7 do
    Carrier.Feed(UInt64(Gamma[I]));

  { Обратимость встроена: то же наложение возвращает исходное. }
  State := ResidentMix(Carrier.Seed, UInt64(Cardinal(Carrier.Lap * 3 + 5)));
  Size := 200 + (Carrier.Lap mod 17) * 64;
  SetLength(Data, Size);
  for I := 0 to Size - 1 do
    Data[I] := Byte(ResidentNext(State) and $FF);
  Once := System.Copy(Data, 0, Size);

  ChaChaApply(Key, Nonce, 1, Data);
  Carrier.Claim(not SameBytes(Data, Once), 'chacha: ciphertext equals plaintext');
  ChaChaApply(Key, Nonce, 1, Data);
  Carrier.Claim(SameBytes(Data, Once), 'chacha: applying twice did not restore');

  { Гамма не зависит от того, каким куском её взяли: шифрование целиком и по
    частям с правильным счётчиком обязано совпасть. }
  Twin := System.Copy(Once, 0, Size);
  ChaChaApply(Key, Nonce, 1, Twin);
  var Parted := System.Copy(Once, 0, Size);
  var Head := System.Copy(Parted, 0, 64);
  var Tail := System.Copy(Parted, 64, Size - 64);
  ChaChaApply(Key, Nonce, 1, Head);
  ChaChaApply(Key, Nonce, 2, Tail);
  for I := 0 to 63 do
    Parted[I] := Head[I];
  for I := 0 to Size - 65 do
    Parted[64 + I] := Tail[I];
  Carrier.Claim(SameBytes(Parted, Twin), 'chacha: splitting the stream changed it');
  Carrier.Feed(UInt64(Cardinal(Size)));
end;

{ Шифрованный поток, растущий между оборотами: дописанное шифруется своим
  ключом, а расшифровка всего накопленного обязана вернуть исходное. }
procedure StageRunningCipher(Carrier: TResidentCarrier);
var
  Pocket: TResidentCipherPocket;
  Key: TChaChaKey;
  Nonce: TChaChaNonce;
  Piece, Whole: TBytes;
  State: UInt64;
  I, Was: Integer;
begin
  Pocket := Carrier.PocketAs<TResidentCipherPocket>('cipher-running');
  for I := 0 to 31 do
    Key[I] := Byte((Carrier.Serial * 5 + I) and $FF);
  FillChar(Nonce, SizeOf(Nonce), 0);
  Nonce[0] := Byte(Carrier.Serial and $FF);

  State := ResidentMix(Carrier.Seed, UInt64(Cardinal(Carrier.Lap)));
  SetLength(Piece, 64);
  for I := 0 to 63 do
    Piece[I] := Byte(ResidentNext(State) and $FF);

  Was := Length(Pocket.FStream);
  SetLength(Pocket.FStream, Was + 64);
  for I := 0 to 63 do
    Pocket.FStream[Was + I] := Piece[I];

  { Шифруем накопленное целиком и расшифровываем обратно: длина растёт, а
    обратимость обязана держаться. }
  Whole := System.Copy(Pocket.FStream, 0, Length(Pocket.FStream));
  ChaChaApply(Key, Nonce, 1, Whole);
  ChaChaApply(Key, Nonce, 1, Whole);
  Carrier.Claim(SameBytes(Whole, Pocket.FStream),
                'chacha: running stream lost its data');
  Carrier.Feed(UInt64(Cardinal(Length(Pocket.FStream))));

  Inc(Pocket.FRounds);
  Carrier.Feed(UInt64(Pocket.FRounds));
  if Length(Pocket.FStream) > 4096 then
    SetLength(Pocket.FStream, 0);
end;

initialization
  for var I := 0 to 255 do
    InvSBox[SBox[I]] := Byte(I);
  { Стадии AES с кольца сняты, и это вынужденно: на боевом профиле компилятор
    выбрасывает цикл табличной подстановки (см. находку про release и таблицы),
    поэтому шифрование считается неверно, а шифрование и расшифрование ломаются
    по-разному — не держится даже обратимость. В кольце они отказывали бы каждый
    оборот и заслоняли всё новое. Код оставлен готовым: как только дефект
    починят, довольно вернуть две строки регистрации.

    Сам дефект от этого не теряется — он предъявлен отдельным пробником в
    находке, где ему и место. }
  ResidentRegisterStage('cipher-chacha', @StageChaCha);
  ResidentRegisterStage('cipher-running', @StageRunningCipher);

end.
