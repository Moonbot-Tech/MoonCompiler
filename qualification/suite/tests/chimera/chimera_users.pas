unit chimera_users;

{ Орган «список пользователей»: устаревшая связка шифра и подписи.

  Источник: `Arbitrage/Users\MoonBotUsers.pas` — запрос
  списка пользователей у сервера. Путь живой: список заводится в ядре
  приложения и используется сервером арбитража. Перенесено дословно по форме:

    * соль собирается форматированием ТРЁХ чисел подряд в шестнадцатеричном
      виде, и её длина потому непостоянна;
    * вектор для шифра берётся ВЫРЕЗКОЙ ИЗ СЕРЕДИНЫ соли, а не заводится
      отдельно;
    * дополнение до блока — НУЛЕВЫМИ БАЙТАМИ в цикле `while`, а не по
      правилу с длиной в хвосте. Это прямая противоположность проводу
      арбитража, где дополнение хранит свою длину, и именно поэтому обе формы
      нужны рядом: у нулевого дополнения хвост данных неотличим от набивки;
    * подпись двухступенчатая: сперва отпечаток соли идёт ВНУТРЬ шифруемого
      сообщения, потом отпечаток уже зашифрованного и перекодированного —
      наружу, вместе с перчинкой и той же солью;
    * отпечаток здесь устаревший, шестнадцатибайтовый, и это часть контракта
      с сервером, а не выбор;
    * готовые куски кодируются для адреса и склеиваются в тело запроса.

  Заменено оснасткой: сеть и источник случайности соли — здесь она
  детерминирована, иначе ответ нельзя было бы сверять между сборками.

  Почему это отдельная форма от провода арбитража:

    * там дополнение по правилу и проверяется при разборе, здесь — нулями и
      не проверяется никак. Разбор обязан знать длину заранее либо срезать
      хвостовые нули, а это разные ответы для данных, которые сами кончаются
      нулём;
    * там вектор строится из счётчика, здесь вырезается из строки, и его
      длина зависит от того, что соль достаточно длинная;
    * там один отпечаток, здесь два разных, на разных секретах.

  Оракулы:

    1. стандартные векторы устаревшего отпечатка и отпечатка с ключом;
    2. круговой обход шифра: расшифровать и убедиться, что исходное
       сообщение получается ровно до набивки;
    3. свойства набивки: длина кратна блоку, добавлено меньше блока, и
       сообщение, уже кратное блоку, НЕ получает лишнего блока — в отличие от
       провода арбитража, где получает всегда;
    4. маскировка адреса предъявляется таблицей на всех краях длины. }

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch INLINEVARS}
{$endif}
{$Q-}{$R-}

interface

uses
  SysUtils, Math, mormot.core.base, mormot.crypt.core, chimera_body;

function ChiUsersRun: Int64;

implementation

const
  IdUsers = 'CHI-ARB-USERS-001';

{ ═══ Отпечатки ═══════════════════════════════════════════════════════════ }

function Md5Hex(const AData: RawByteString): string;
var
  D: TMd5Digest;
  I: Integer;
  H: TMd5;
begin
  H.Full(Pointer(AData), Length(AData), D);
  Result := '';
  for I := 0 to High(D) do
    Result := Result + LowerCase(IntToHex(D[I], 2));
end;

{ Отпечатка с ключом на устаревшем алгоритме в библиотеке нет, поэтому он
  собран прямо здесь по определению: ключ дополняется до размера блока,
  дважды складывается с разными набивками, и алгоритм применяется дважды.
  Правильность подтверждается стандартным вектором ниже. }
function HmacMd5Hex(const AKey, AData: RawByteString): string;
const
  BlockSize = 64;
var
  H: TMd5;
  Inner, Outer: TMd5Digest;
  Key: array [0 .. BlockSize - 1] of Byte;
  Pad: array [0 .. BlockSize - 1] of Byte;
  Short: TMd5Digest;
  I: Integer;
begin
  FillChar(Key, SizeOf(Key), 0);
  if Length(AKey) > BlockSize then
  begin
    H.Full(Pointer(AKey), Length(AKey), Short);
    Move(Short, Key, SizeOf(Short));
  end
  else if Length(AKey) > 0 then
    Move(Pointer(AKey)^, Key, Length(AKey));

  for I := 0 to BlockSize - 1 do Pad[I] := Key[I] xor $36;
  H.Init;
  H.Update(Pad, BlockSize);
  if Length(AData) > 0 then H.Update(Pointer(AData)^, Length(AData));
  H.Final(Inner);

  for I := 0 to BlockSize - 1 do Pad[I] := Key[I] xor $5C;
  H.Init;
  H.Update(Pad, BlockSize);
  H.Update(Inner, SizeOf(Inner));
  H.Final(Outer);

  Result := '';
  for I := 0 to High(Outer) do
    Result := Result + LowerCase(IntToHex(Outer[I], 2));
end;

{ ═══ Перенесённая форма ══════════════════════════════════════════════════ }

{ Соль: три числа подряд в шестнадцатеричном виде. Длина непостоянна — она
  зависит от значений, и от неё же зависит, хватит ли байтов на вектор. }
function MakeSalt(A, B, C: Int64): AnsiString;
begin
  Result := AnsiString(Format('%x%x%x', [A, B, C]));
end;

{ Набивка НУЛЯМИ до кратности блоку. Сообщение, уже кратное блоку, лишнего
  блока НЕ получает — и потому хвостовой ноль данных неотличим от набивки. }
function PadZero(const S: AnsiString): AnsiString;
begin
  Result := S;
  while (Length(Result) mod 16) <> 0 do
    Result := Result + #0;
end;

function EncryptCbc(const AKey, AIv, AData: RawByteString): RawByteString;
var
  Aes: TAesCbc;
  Key, Iv: THash128;
begin
  FillChar(Key, SizeOf(Key), 0);
  FillChar(Iv, SizeOf(Iv), 0);
  Move(Pointer(AKey)^, Key, Min(Length(AKey), SizeOf(Key)));
  Move(Pointer(AIv)^, Iv, Min(Length(AIv), SizeOf(Iv)));
  Aes := TAesCbc.Create(Key, 128);
  try
    Aes.IV := Iv;
    SetLength(Result, Length(AData));
    if Length(AData) > 0 then
      Aes.Encrypt(Pointer(AData), Pointer(Result), Length(AData));
  finally
    Aes.Free;
  end;
end;

function DecryptCbc(const AKey, AIv, AData: RawByteString): RawByteString;
var
  Aes: TAesCbc;
  Key, Iv: THash128;
begin
  FillChar(Key, SizeOf(Key), 0);
  FillChar(Iv, SizeOf(Iv), 0);
  Move(Pointer(AKey)^, Key, Min(Length(AKey), SizeOf(Key)));
  Move(Pointer(AIv)^, Iv, Min(Length(AIv), SizeOf(Iv)));
  Aes := TAesCbc.Create(Key, 128);
  try
    Aes.IV := Iv;
    SetLength(Result, Length(AData));
    if Length(AData) > 0 then
      Aes.Decrypt(Pointer(AData), Pointer(Result), Length(AData));
  finally
    Aes.Free;
  end;
end;

{ Печатный вид и кодирование для адреса — как в живом пути. }
const
  B64: array [0 .. 63] of AnsiChar =
    ('A','B','C','D','E','F','G','H','I','J','K','L','M','N','O','P',
     'Q','R','S','T','U','V','W','X','Y','Z','a','b','c','d','e','f',
     'g','h','i','j','k','l','m','n','o','p','q','r','s','t','u','v',
     'w','x','y','z','0','1','2','3','4','5','6','7','8','9','+','/');

function ToBase64(const Data: RawByteString): AnsiString;
var
  I, N: Integer;
  Chunk: Cardinal;
begin
  Result := '';
  I := 1;
  N := Length(Data);
  while I <= N do
  begin
    Chunk := Cardinal(Byte(Data[I])) shl 16;
    if I + 1 <= N then Chunk := Chunk or (Cardinal(Byte(Data[I + 1])) shl 8);
    if I + 2 <= N then Chunk := Chunk or Cardinal(Byte(Data[I + 2]));
    Result := Result + B64[(Chunk shr 18) and 63] + B64[(Chunk shr 12) and 63];
    if I + 1 <= N then Result := Result + B64[(Chunk shr 6) and 63]
                  else Result := Result + '=';
    if I + 2 <= N then Result := Result + B64[Chunk and 63]
                  else Result := Result + '=';
    Inc(I, 3);
  end;
end;

function EncodeUrl(const S: AnsiString): AnsiString;
var
  I: Integer;
  C: AnsiChar;
begin
  Result := '';
  for I := 1 to Length(S) do
  begin
    C := S[I];
    if (C = '+') or (C = '/') or (C = '=') or (C = '&') or (C = '%') then
      Result := Result + '%' + AnsiString(IntToHex(Ord(C), 2))
    else
      Result := Result + C;
  end;
end;

{ Маскировка адреса: три символа с начала, три с конца, и особый случай для
  коротких. }
function MaskAddr(const S: string): string;
begin
  if Length(S) <= 6 then
    Result := '***'
  else
    Result := Copy(S, 1, 3) + '***' + Copy(S, Length(S) - 2, 3);
end;

{ Сборка тела запроса целиком — та же последовательность, что в живом коде. }
function BuildRequest(const Salt: AnsiString; const Prefix: AnsiString;
  const AesKey, SecretMsg, SecretSig, Pepper: RawByteString;
  out Enc, Sig: AnsiString): AnsiString;
var
  Msg: AnsiString;
  Cipher: RawByteString;
  Iv: RawByteString;
begin
  { Отпечаток соли идёт ВНУТРЬ шифруемого сообщения. }
  Msg := Prefix + AnsiString(HmacMd5Hex(SecretMsg, RawByteString(Salt)));
  { Вектор — вырезка из середины соли. }
  Iv := RawByteString(Copy(Salt, 3, 16));
  Msg := PadZero(Msg);
  Cipher := EncryptCbc(AesKey, Iv, RawByteString(Msg));
  Enc := ToBase64(Cipher);
  { Вторая подпись — от уже зашифрованного и перекодированного. }
  Sig := AnsiString(HmacMd5Hex(SecretSig,
    RawByteString(string(Enc) + string(Pepper) + string(Salt))));
  Result := '&salt=' + Salt + '&tokenx=' + EncodeUrl(Sig)
            + '&data=' + EncodeUrl(Enc);
end;

{ ═══ Проверка ════════════════════════════════════════════════════════════ }

function ChiUsersRun: Int64;
var
  Acc: UInt64;
  Salt, Enc, Sig, Body, Msg, Padded: AnsiString;
  Key, SecretMsg, SecretSig, Pepper, Iv: RawByteString;
  Cipher, Back: RawByteString;
  I, Len: Integer;
  Src: TChiSource;
  Ok: Boolean;
begin
  ChiCovered(IdUsers);
  Acc := ChiOffset;
  Src := ChiSource(24680);

  { ── Внешняя истина для устаревшего отпечатка ── }
  ChiClaim(Md5Hex(RawByteString('')) = 'd41d8cd98f00b204e9800998ecf8427e',
    'список: отпечаток пустого не совпал с вектором');
  ChiClaim(Md5Hex(RawByteString('abc')) = '900150983cd24fb0d6963f7d28e17f72',
    'список: отпечаток не совпал с вектором');
  ChiBranch(IdUsers, 'md5-vector');

  { Вектор RFC 2202 для отпечатка с ключом. }
  ChiClaim(HmacMd5Hex(RawByteString('Jefe'),
                      RawByteString('what do ya want for nothing?'))
    = '750c783e6ab0b503eaa86e310a5db738',
    'список: отпечаток с ключом не совпал с вектором');
  ChiBranch(IdUsers, 'hmac-md5-vector');

  { ── Набивка нулями: свойства и отличие от провода ── }
  for Len := 0 to 40 do
  begin
    SetLength(Msg, Len);
    for I := 1 to Len do Msg[I] := AnsiChar(65 + (I mod 26));
    Padded := PadZero(Msg);
    ChiClaim((Length(Padded) mod 16) = 0,
      'список: набивка не довела до кратности, длина ' + IntToStr(Len));
    ChiClaim(Length(Padded) - Length(Msg) < 16,
      'список: набивка добавила целый блок');
    if (Len mod 16) = 0 then
    begin
      { Вот оно отличие от провода: там кратное сообщение получает ЛИШНИЙ
        блок, здесь — ничего. }
      ChiClaim(Length(Padded) = Len,
        'список: кратное сообщение получило набивку');
      ChiBranch(IdUsers, 'aligned-gets-nothing');
    end;
    Acc := ChiMix(Acc, Length(Padded));
  end;
  ChiBranch(IdUsers, 'zero-padding');

  { Хвостовой ноль данных неотличим от набивки — свойство этой формы. }
  Msg := 'abc' + #0;
  ChiClaim(PadZero(Msg) = PadZero('abc'),
    'список: ноль в данных отличим от набивки, а не должен');
  ChiBranch(IdUsers, 'zero-tail-ambiguous');

  { ── Круговой обход шифра ── }
  Key := RawByteString('0123456789abcdef');
  Iv := RawByteString('fedcba9876543210');
  for Len := 16 to 96 do
    if (Len mod 16) = 0 then
    begin
      SetLength(Msg, Len);
      for I := 1 to Len do Msg[I] := AnsiChar(Src.NextBelow(256));
      Cipher := EncryptCbc(Key, Iv, RawByteString(Msg));
      ChiClaim(Length(Cipher) = Len, 'список: шифр изменил длину');
      Back := DecryptCbc(Key, Iv, Cipher);
      ChiClaim(Back = RawByteString(Msg), 'список: круговой обход не сошёлся');
      Acc := ChiMix(Acc, Length(Cipher));
    end;
  ChiBranch(IdUsers, 'cbc-roundtrip');

  { Чужой вектор портит только первый блок — свойство сцепления. }
  SetLength(Msg, 32);
  for I := 1 to 32 do Msg[I] := AnsiChar(65 + I);
  Cipher := EncryptCbc(Key, Iv, RawByteString(Msg));
  Back := DecryptCbc(Key, RawByteString('0000000000000000'), Cipher);
  ChiClaim(Back <> RawByteString(Msg), 'список: чужой вектор ничего не изменил');
  Ok := True;
  for I := 17 to 32 do
    if Back[I] <> Msg[I] then Ok := False;
  ChiClaim(Ok, 'список: чужой вектор испортил не только первый блок');
  ChiBranch(IdUsers, 'iv-affects-first-block');

  { ── Сборка запроса целиком ── }
  SecretMsg := RawByteString('secret-msg');
  SecretSig := RawByteString('secret-sig');
  Pepper := RawByteString('pepper');
  Salt := MakeSalt($1A2B3C, 1735689600000, $4D5E6F);

  { Соль обязана быть достаточно длинной: вектор вырезается с третьего байта
    и требует шестнадцати. }
  ChiClaim(Length(Salt) >= 18, 'список: соль короче, чем нужно вектору');
  ChiBranch(IdUsers, 'salt-long-enough');

  Body := BuildRequest(Salt, 'PREFIX:', Key, SecretMsg, SecretSig, Pepper,
                       Enc, Sig);

  ChiClaim(Pos(AnsiString('&salt=' + Salt), Body) = 1,
    'список: тело запроса начинается не с соли');
  ChiClaim(Pos(AnsiString('&tokenx='), Body) > 0, 'список: нет подписи в теле');
  ChiClaim(Pos(AnsiString('&data='), Body) > 0, 'список: нет данных в теле');
  ChiBranch(IdUsers, 'request-body');

  { Отпечаток второй ступени считается от уже перекодированного, а не от
    сырого шифра — подмена порядка даёт другую подпись. }
  ChiClaim(Sig = AnsiString(HmacMd5Hex(SecretSig,
    RawByteString(string(Enc) + 'pepper' + string(Salt)))),
    'список: вторая подпись не от той строки');
  ChiBranch(IdUsers, 'two-stage-signature');

  { Печатный вид не имеет права уехать в адрес как есть. }
  ChiClaim(Pos(AnsiString('+'), EncodeUrl(RawByteString('a+b'))) = 0,
    'список: плюс не закодирован');
  ChiClaim(Pos(AnsiString('='), EncodeUrl(RawByteString('a=b'))) = 0,
    'список: знак равенства не закодирован');
  ChiBranch(IdUsers, 'url-encoded');
  Acc := ChiMix(Acc, Length(Body));

  { Другая соль — другая подпись и другие данные. }
  Salt := MakeSalt($1A2B3D, 1735689600000, $4D5E6F);
  Body := BuildRequest(Salt, 'PREFIX:', Key, SecretMsg, SecretSig, Pepper,
                       Enc, Sig);
  Acc := ChiMix(Acc, Length(Sig));

  { ── Маскировка адреса: таблица на краях длины ── }
  ChiClaim(MaskAddr('') = '***', 'список: пустой адрес замаскирован не так');
  ChiClaim(MaskAddr('abcdef') = '***', 'список: шесть символов — не звёздочки');
  ChiClaim(MaskAddr('abcdefg') = 'abc***efg',
    'список: семь символов замаскированы не так: ' + MaskAddr('abcdefg'));
  ChiClaim(MaskAddr('0x1234567890abcdef') = '0x1***def',
    'список: длинный адрес замаскирован не так');
  ChiBranch(IdUsers, 'mask-edges');

  Result := Int64(Acc and $7FFFFFFFFFFF);
end;

end.
