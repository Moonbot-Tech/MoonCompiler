unit chimera_wire;

{ Орган «провод»: шифрованный кадр Арбитража и его полезная нагрузка.

  Источник: `MoonBot/Arb\ArbProto.pas` (тот же юнит лежит и на
  стороне сервера Арбитража). Перенесено дословно по форме:

    * упакованные записи проводных структур с точными размерами;
    * дополнение до блока `((L shr 4) + 1) shl 4` — заметьте, оно ВСЕГДА
      добавляет хотя бы один байт, даже когда длина уже кратна блоку;
    * дополнение пишется прямо в будущий выходной буфер, и шифрование идёт
      НА МЕСТЕ: источник и приёмник — один и тот же адрес;
    * растущий буфер: длина назначается только когда не хватает, ёмкость
      между вызовами сохраняется;
    * вектор из атомарного счётчика в исключающем ИЛИ с маской;
    * нетипизированные `const`/`var` параметры с отдельно переданной длиной;
    * разбор самоограниченного потока `[длина][имя][счёт]×[биржа][цена]` до
      конца расшифрованного тела, без внешнего указания числа записей.

  Заменено оснасткой: источник случайности вектора (здесь он детерминирован,
  иначе ответ нельзя было бы сверять между сборками) и сеть.

  Факт, добытый замером и важный для понимания формы: `TAesGcm` использует
  РОВНО ДВЕНАДЦАТЬ первых байтов вектора, остальные четыре не влияют ни на
  шифротекст, ни на метку. Поэтому живой код законно кладёт на провод только
  двенадцать байтов из шестнадцати, а мусор в хвосте при разборе безвреден.
  Здесь это проверяется отдельным утверждением, а не принимается на веру.

  Оракулы:

    1. **стандартный вектор AES-GCM** — внешняя истина для самого шифра;
    2. **канонический кадр** — точные длины и смещения частей, а не только
       «расшифровалось обратно»;
    3. **независимый разборщик** полезной нагрузки, написанный по-другому:
       по срезам, а не по указателю;
    4. **отказы**: порча шифротекста, порча метки, чужой ключ, обрезанный
       вход, неверное дополнение — каждый обязан быть отвергнут. }

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch INLINEVARS}
{$endif}
{$Q-}{$R-}

interface

uses
  SysUtils, mormot.core.base, mormot.crypt.core, chimera_body;

const
  ChiIvLen    = 12;
  ChiTagLen   = 16;
  ChiBlockLen = 16;
  ChiVer      = 2;

type
  TChiKey = THash128;

  { Проводные записи. Размеры — часть контракта, а не следствие раскладки. }
  TChiPingBase = packed record
    Ver:      Byte;
    MainId:   Integer;
    Platform: Byte;
  end;

  TChiRespBody = packed record
    Ver:  Byte;
    BKey: TChiKey;
  end;

function ChiWireRun: Int64;

implementation

{ ═══ Вектор ══════════════════════════════════════════════════════════════

  Форма живого кода: монотонный счётчик в исключающем ИЛИ с маской. Маска
  здесь постоянна, а не случайна: ответ обязан совпадать между сборками.
  Проверка того, что счётчик действительно монотонен и векторы не
  повторяются, идёт отдельно и не входит в печатаемое число. }

var
  IvCounter: Int64 = 0;
  IvMask: Int64 = Int64($5DEECE66D5A17);

procedure MakeIv(out AIv: THash128Rec);
begin
  AIv.L := AtomicIncrement(IvCounter) xor IvMask;
  AIv.H := 0;
end;

procedure FixedIv(out AIv: THash128Rec; Seed: Int64);
begin
  AIv.L := Seed;
  AIv.H := 0;
end;

{ ═══ Кадр ════════════════════════════════════════════════════════════════ }

procedure EncryptFrame(const AKey: TChiKey; APlain: Pointer; APlainLen: Integer;
  AAad: Pointer; AAadLen: Integer; const AIv: THash128Rec;
  var ACipher: TBytes; out ACipherLen: Integer);
var
  Gcm: TAesGcm;
  Tag: THash128;
  PadLen, PaddedN: Integer;
  P, CipherStart: PByte;
begin
  { Дополнение по PKCS7. Обратите внимание: при длине, уже кратной блоку,
    добавляется ЦЕЛЫЙ лишний блок — иначе разбор не отличил бы данные от
    дополнения. }
  PaddedN := ((APlainLen shr 4) + 1) shl 4;
  PadLen := PaddedN - APlainLen;
  ACipherLen := ChiIvLen + ChiTagLen + PaddedN;
  { Растущий буфер: длина назначается только когда не хватает. }
  if Length(ACipher) < ACipherLen then SetLength(ACipher, ACipherLen);

  CipherStart := @ACipher[ChiIvLen + ChiTagLen];
  if APlainLen > 0 then Move(APlain^, CipherStart^, APlainLen);
  FillChar(PByte(CipherStart + APlainLen)^, PadLen, Byte(PadLen));

  Gcm := TAesGcm.Create(AKey, 128);
  try
    Gcm.IV := THash128(AIv);
    if (AAad <> nil) and (AAadLen > 0) then Gcm.AesGcmAad(AAad, AAadLen);
    { Шифрование на месте: источник и приёмник — один адрес. }
    Gcm.Encrypt(CipherStart, CipherStart, PaddedN);
    Gcm.AesGcmFinal(Tag, ChiTagLen);
  finally
    Gcm.Free;
  end;

  P := @ACipher[0];
  Move(AIv, P^, ChiIvLen);
  Move(Tag, PByte(P + ChiIvLen)^, ChiTagLen);
end;

function DecryptFrame(const AKey: TChiKey; ACipher: Pointer; ACipherLen: Integer;
  AAad: Pointer; AAadLen: Integer;
  var APlain: TBytes; out APlainLen: Integer): Boolean;
var
  Gcm: TAesGcm;
  Iv: THash128Rec;
  Tag: THash128;
  BodyLen: Integer;
  BodyIn: PByte;
  PadLen: Byte;
  P: PByte;
begin
  Result := False;
  APlainLen := 0;
  if ACipherLen < ChiIvLen + ChiTagLen + ChiBlockLen then Exit;

  BodyLen := ACipherLen - ChiIvLen - ChiTagLen;
  if (BodyLen and (ChiBlockLen - 1)) <> 0 then Exit;

  P := ACipher;
  { На проводе двенадцать байтов вектора; старшие четыре остаются такими,
    какими были в переменной. На шифр они не влияют — проверено отдельно. }
  Iv.L := 0;
  Iv.H := 0;
  Move(P[0], Iv, ChiIvLen);
  Move(P[ChiIvLen], Tag, ChiTagLen);
  BodyIn := P + ChiIvLen + ChiTagLen;

  if Length(APlain) < BodyLen then SetLength(APlain, BodyLen);
  Gcm := TAesGcm.Create(AKey, 128);
  try
    Gcm.IV := THash128(Iv);
    if (AAad <> nil) and (AAadLen > 0) then Gcm.AesGcmAad(AAad, AAadLen);
    Gcm.Decrypt(BodyIn, @APlain[0], BodyLen);
    if not Gcm.AesGcmFinal(Tag, ChiTagLen) then Exit;
  finally
    Gcm.Free;
  end;

  PadLen := APlain[BodyLen - 1];
  if (PadLen = 0) or (PadLen > ChiBlockLen) or (PadLen > BodyLen) then Exit;

  APlainLen := BodyLen - PadLen;
  Result := True;
end;

{ Нетипизированные обёртки: запись приходит без типа, длина отдельно. }

procedure EncryptRec(const AKey: TChiKey; const ARec; ARecLen: Integer;
  const AIv: THash128Rec; var ACipher: TBytes; out ACipherLen: Integer);
begin
  EncryptFrame(AKey, @ARec, ARecLen, nil, 0, AIv, ACipher, ACipherLen);
end;

function DecryptToRec(const AKey: TChiKey; ACipher: Pointer;
  ACipherLen: Integer; var ARec; ARecLen: Integer): Boolean;
var
  Plain: TBytes;
  PlainLen: Integer;
begin
  Result := DecryptFrame(AKey, ACipher, ACipherLen, nil, 0, Plain, PlainLen);
  if not Result then Exit;
  if PlainLen <> ARecLen then
  begin
    Result := False;
    Exit;
  end;
  Move(Plain[0], ARec, ARecLen);
end;

{ ═══ Полезная нагрузка ═══════════════════════════════════════════════════

  Самоограниченный поток: повторяющиеся блоки до конца тела, без внешнего
  указания их числа. }

type
  TChiQuote = record
    Name: AnsiString;
    Platforms: array of Byte;
    Prices: array of Single;
  end;
  TChiQuotes = array of TChiQuote;

function BuildPayload(const Quotes: TChiQuotes): TBytes;
var
  I, J, Pos, Need: Integer;
begin
  Need := 1;
  for I := 0 to High(Quotes) do
    Need := Need + 1 + Length(Quotes[I].Name) + 1
            + Length(Quotes[I].Platforms) * 5;
  Result := nil;
  SetLength(Result, Need);
  Result[0] := ChiVer;
  Pos := 1;
  for I := 0 to High(Quotes) do
  begin
    Result[Pos] := Byte(Length(Quotes[I].Name));
    Inc(Pos);
    if Length(Quotes[I].Name) > 0 then
    begin
      Move(Quotes[I].Name[1], Result[Pos], Length(Quotes[I].Name));
      Inc(Pos, Length(Quotes[I].Name));
    end;
    Result[Pos] := Byte(Length(Quotes[I].Platforms));
    Inc(Pos);
    for J := 0 to High(Quotes[I].Platforms) do
    begin
      Result[Pos] := Quotes[I].Platforms[J];
      Inc(Pos);
      Move(Quotes[I].Prices[J], Result[Pos], 4);
      Inc(Pos, 4);
    end;
  end;
end;

{ Разбор по указателю — форма живого клиента. }
function ParsePayload(Data: PByte; Len: Integer; out Quotes: TChiQuotes): Boolean;
var
  Stop: PByte;
  N, Cnt, I: Integer;
begin
  Quotes := nil;
  Result := False;
  if Len < 1 then Exit;
  Stop := Data + Len;
  Inc(Data);
  while Data < Stop do
  begin
    N := Data^;
    Inc(Data);
    if Data + N + 1 > Stop then Exit;
    SetLength(Quotes, Length(Quotes) + 1);
    with Quotes[High(Quotes)] do
    begin
      SetLength(Name, N);
      if N > 0 then Move(Data^, Name[1], N);
      Inc(Data, N);
      Cnt := Data^;
      Inc(Data);
      if Data + Cnt * 5 > Stop then Exit;
      SetLength(Platforms, Cnt);
      SetLength(Prices, Cnt);
      for I := 0 to Cnt - 1 do
      begin
        Platforms[I] := Data^;
        Inc(Data);
        Move(Data^, Prices[I], 4);
        Inc(Data, 4);
      end;
    end;
  end;
  Result := Data = Stop;
end;

{ Независимый разбор — по срезам массива, без единого указателя. }
function ParseBySlices(const Data: TBytes; Len: Integer;
  out Quotes: TChiQuotes): Boolean;
var
  P, N, Cnt, I, K: Integer;
begin
  Quotes := nil;
  Result := False;
  if Len < 1 then Exit;
  P := 1;
  while P < Len do
  begin
    N := Data[P];
    Inc(P);
    if P + N + 1 > Len then Exit;
    SetLength(Quotes, Length(Quotes) + 1);
    K := High(Quotes);
    SetLength(Quotes[K].Name, N);
    for I := 0 to N - 1 do
      Quotes[K].Name[I + 1] := AnsiChar(Data[P + I]);
    Inc(P, N);
    Cnt := Data[P];
    Inc(P);
    if P + Cnt * 5 > Len then Exit;
    SetLength(Quotes[K].Platforms, Cnt);
    SetLength(Quotes[K].Prices, Cnt);
    for I := 0 to Cnt - 1 do
    begin
      Quotes[K].Platforms[I] := Data[P];
      Inc(P);
      Move(Data[P], Quotes[K].Prices[I], 4);
      Inc(P, 4);
    end;
  end;
  Result := P = Len;
end;

function SameQuotes(const A, B: TChiQuotes): Boolean;
var
  I, J: Integer;
begin
  Result := Length(A) = Length(B);
  if not Result then Exit;
  for I := 0 to High(A) do
  begin
    if A[I].Name <> B[I].Name then Exit(False);
    if Length(A[I].Platforms) <> Length(B[I].Platforms) then Exit(False);
    for J := 0 to High(A[I].Platforms) do
    begin
      if A[I].Platforms[J] <> B[I].Platforms[J] then Exit(False);
      if PCardinal(@A[I].Prices[J])^ <> PCardinal(@B[I].Prices[J])^ then
        Exit(False);
    end;
  end;
end;

{ ═══ Дополнительные данные ═══════════════════════════════════════════════

  Подаются штатным для библиотеки способом — тем, который действительно
  участвует в подсчёте метки. }

function TagWithAad(AadByte: Byte): THash128;
var
  Gcm: TAesGcm;
  Key, Iv: THash128;
  Nonce: THash256;
  Pt, Ct: array [0 .. 15] of Byte;
  Aad: RawByteString;
  I: Integer;
begin
  FillChar(Key, SizeOf(Key), $A5);
  FillChar(Iv, SizeOf(Iv), $11);
  FillChar(Nonce, SizeOf(Nonce), 0);
  for I := 0 to 15 do Pt[I] := I;
  if AadByte <> 0 then
  begin
    SetLength(Aad, 8);
    for I := 1 to 8 do Aad[I] := AnsiChar(AadByte);
  end
  else
    Aad := '';
  Gcm := TAesGcm.Create(Key, 128);
  try
    Gcm.IV := Iv;
    Gcm.MacSetNonce(True, Nonce, Aad);
    Gcm.Encrypt(@Pt, @Ct, 16);
    Gcm.AesGcmFinal(Result, ChiTagLen);
  finally
    Gcm.Free;
  end;
end;

function SameTag(const A, B: THash128): Boolean;
begin
  Result := CompareMem(@A, @B, SizeOf(THash128));
end;

function AadRoundTrip(EncByte, DecByte: Byte): Boolean;
var
  Gcm: TAesGcm;
  Key, Iv, Tag: THash128;
  Nonce: THash256;
  Pt, Ct, Back: array [0 .. 15] of Byte;
  AadEnc, AadDec: RawByteString;
  I: Integer;
begin
  FillChar(Key, SizeOf(Key), $A5);
  FillChar(Iv, SizeOf(Iv), $11);
  FillChar(Nonce, SizeOf(Nonce), 0);
  for I := 0 to 15 do Pt[I] := I;
  SetLength(AadEnc, 8);
  SetLength(AadDec, 8);
  for I := 1 to 8 do
  begin
    AadEnc[I] := AnsiChar(EncByte);
    AadDec[I] := AnsiChar(DecByte);
  end;

  Gcm := TAesGcm.Create(Key, 128);
  try
    Gcm.IV := Iv;
    Gcm.MacSetNonce(True, Nonce, AadEnc);
    Gcm.Encrypt(@Pt, @Ct, 16);
    Gcm.AesGcmFinal(Tag, ChiTagLen);
  finally
    Gcm.Free;
  end;

  Gcm := TAesGcm.Create(Key, 128);
  try
    Gcm.IV := Iv;
    Gcm.MacSetNonce(False, Nonce, AadDec);
    Gcm.Decrypt(@Ct, @Back, 16);
    Result := Gcm.AesGcmFinal(Tag, ChiTagLen);
  finally
    Gcm.Free;
  end;
end;

{ ═══ Проверка ════════════════════════════════════════════════════════════ }

const
  { Края дополнения: пусто, один байт, перед блоком, ровно блок, за блоком, и
    крупные размеры. }
  PadLens: array [0 .. 9] of Integer =
    (0, 1, 15, 16, 17, 31, 32, 33, 255, 1024);

  IdWire  = 'CHI-ARB-WIRE-001';
  IdPad   = 'CHI-ARB-WIRE-002';
  IdPlace = 'CHI-ARB-WIRE-003';
  IdParse = 'CHI-ARB-WIRE-004';
  IdCrypt = 'CHI-ARB-CRYPT-001';
  IdIv    = 'CHI-ARB-CRYPT-002';

function MakeQuotes(Count: Integer; Seed: UInt64): TChiQuotes;
var
  Src: TChiSource;
  I, J, N: Integer;
begin
  Result := nil;
  SetLength(Result, Count);
  Src := ChiSource(Seed);
  for I := 0 to Count - 1 do
  begin
    { Имя нулевой длины — законный край самоограниченного потока. }
    N := Src.NextBelow(9);
    SetLength(Result[I].Name, N);
    for J := 1 to N do
      Result[I].Name[J] := AnsiChar(Ord('A') + Src.NextBelow(26));
    N := Src.NextBelow(4);
    SetLength(Result[I].Platforms, N);
    SetLength(Result[I].Prices, N);
    for J := 0 to N - 1 do
    begin
      Result[I].Platforms[J] := Src.NextBelow(200);
      Result[I].Prices[J] := 0.5 + Src.NextUnit * 100;
    end;
  end;
end;

function ChiWireRun: Int64;
var
  Key, Other: TChiKey;
  Iv: THash128Rec;
  Cipher, Plain, Reused: TBytes;
  CipherLen, PlainLen, I, J, Len: Integer;
  Acc: UInt64;
  Src: TChiSource;
  Body, Payload: TBytes;
  Quotes, Got, Got2: TChiQuotes;
  Ping: TChiPingBase;
  PingBack: TChiPingBase;
  Resp: TChiRespBody;
  Gcm: TAesGcm;
  VecKey, VecIv: THash128;
  VecPt, VecCt: array [0 .. 15] of Byte;
  VecTag: THash128;
  Hex: string;
  Ivs: array [0 .. 63] of Int64;
  Ok: Boolean;
begin
  ChiCovered(IdWire);
  ChiCovered(IdPad);
  ChiCovered(IdPlace);
  ChiCovered(IdParse);
  ChiCovered(IdCrypt);
  ChiCovered(IdIv);
  Acc := ChiOffset;
  Src := ChiSource(31337);

  { ── Размеры проводных записей — контракт, а не следствие раскладки ── }
  ChiClaim(SizeOf(TChiPingBase) = 6, 'провод: размер пинга не шесть байт');
  ChiClaim(SizeOf(TChiRespBody) = 17, 'провод: размер ответа не семнадцать');
  ChiBranch(IdWire, 'record-sizes');

  { ── Внешняя истина для шифра ── }
  FillChar(VecKey, SizeOf(VecKey), 0);
  FillChar(VecIv, SizeOf(VecIv), 0);
  FillChar(VecPt, SizeOf(VecPt), 0);
  Gcm := TAesGcm.Create(VecKey, 128);
  try
    Gcm.IV := VecIv;
    Gcm.Encrypt(@VecPt, @VecCt, 16);
    Gcm.AesGcmFinal(VecTag, ChiTagLen);
  finally
    Gcm.Free;
  end;
  Hex := '';
  for I := 0 to 15 do Hex := Hex + LowerCase(IntToHex(VecCt[I], 2));
  ChiClaim(Hex = '0388dace60b6a392f328c2b971b2fe78',
    'провод: шифротекст разошёлся со стандартным вектором');
  Hex := '';
  for I := 0 to 15 do
    Hex := Hex + LowerCase(IntToHex(THash128Rec(VecTag).b[I], 2));
  ChiClaim(Hex = 'ab6e47d42cec13bdf53a67b21257bddf',
    'провод: метка разошлась со стандартным вектором');
  ChiBranch(IdCrypt, 'nist-vector');

  { ── Хвост вектора не влияет: живой код кладёт на провод только двенадцать
       байтов из шестнадцати, и это законно ── }
  FillChar(Key, SizeOf(Key), $A5);
  FixedIv(Iv, $0102030405060708);
  SetLength(Plain, 16);
  for I := 0 to 15 do Plain[I] := I;
  Cipher := nil;
  EncryptFrame(Key, @Plain[0], 16, nil, 0, Iv, Cipher, CipherLen);
  { Меняем ТОЛЬКО байты за пределами двенадцати: они не попадают ни на провод,
    ни в сам шифр. Байты с восьмого по одиннадцатый — часть старшей половины
    записи, но они В пределах двенадцати, и трогать их здесь нельзя. }
  for I := ChiIvLen to 15 do PByteArray(@Iv)^[I] := $FF;
  Reused := nil;
  EncryptFrame(Key, @Plain[0], 16, nil, 0, Iv, Reused, Len);
  Ok := True;
  for I := ChiIvLen to CipherLen - 1 do
    if Cipher[I] <> Reused[I] then Ok := False;
  ChiClaim(Ok, 'провод: байты вектора за двенадцатым повлияли на шифр');
  ChiBranch(IdIv, 'iv-tail-ignored');

  { ── Дополнение на всех краях ── }
  for I := 0 to High(PadLens) do
  begin
    Len := PadLens[I];
    SetLength(Plain, Len);
    for J := 0 to Len - 1 do Plain[J] := Byte(J * 7 + 3);
    FixedIv(Iv, 1000 + Len);
    Cipher := nil;
    if Len = 0 then
      EncryptFrame(Key, nil, 0, nil, 0, Iv, Cipher, CipherLen)
    else
      EncryptFrame(Key, @Plain[0], Len, nil, 0, Iv, Cipher, CipherLen);

    { Канонический кадр: длина обязана быть ровно такой. }
    ChiClaim(CipherLen = ChiIvLen + ChiTagLen + ((Len shr 4) + 1) shl 4,
      'провод: длина кадра не каноническая, тело ' + IntToStr(Len));
    ChiClaim(((CipherLen - ChiIvLen - ChiTagLen) and (ChiBlockLen - 1)) = 0,
      'провод: тело не кратно блоку');
    if (Len mod ChiBlockLen) = 0 then ChiBranch(IdPad, 'full-block-adds-block');

    Reused := nil;
    ChiClaim(DecryptFrame(Key, @Cipher[0], CipherLen, nil, 0, Reused, PlainLen),
      'провод: кадр не расшифровался, тело ' + IntToStr(Len));
    ChiClaim(PlainLen = Len, 'провод: длина после разбора не сошлась');
    Ok := True;
    for J := 0 to Len - 1 do
      if Reused[J] <> Plain[J] then Ok := False;
    ChiClaim(Ok, 'провод: тело исказилось, длина ' + IntToStr(Len));
    Acc := ChiMix(Acc, CipherLen);
  end;
  ChiBranch(IdPad, 'edges');
  ChiBranch(IdPlace, 'encrypt-in-place');

  { ── Растущий буфер: ёмкость сохраняется между вызовами ── }
  Cipher := nil;
  SetLength(Plain, 1024);
  FixedIv(Iv, 7);
  EncryptFrame(Key, @Plain[0], 1024, nil, 0, Iv, Cipher, CipherLen);
  Len := Length(Cipher);
  SetLength(Plain, 16);
  FixedIv(Iv, 8);
  EncryptFrame(Key, @Plain[0], 16, nil, 0, Iv, Cipher, CipherLen);
  ChiClaim(Length(Cipher) = Len,
    'провод: буфер ужался после меньшего пакета');
  ChiClaim(CipherLen < Len, 'провод: длина не уменьшилась под меньший пакет');
  ChiBranch(IdPlace, 'grow-only-buffer');

  { Мусор от прошлого пакета не имеет права попасть в разбор: длина берётся из
    возвращённого счётчика, а не из размера буфера. }
  Reused := nil;
  ChiClaim(DecryptFrame(Key, @Cipher[0], CipherLen, nil, 0, Reused, PlainLen),
    'провод: повторно использованный буфер не разобрался');
  ChiClaim(PlainLen = 16, 'провод: хвост прошлого пакета попал в разбор');
  ChiBranch(IdPlace, 'no-stale-bytes');

  { ── Отказы ── }
  SetLength(Plain, 40);
  for I := 0 to 39 do Plain[I] := Byte(I);
  FixedIv(Iv, 99);
  Cipher := nil;
  EncryptFrame(Key, @Plain[0], 40, nil, 0, Iv, Cipher, CipherLen);

  Reused := Copy(Cipher, 0, CipherLen);
  Reused[CipherLen - 1] := Reused[CipherLen - 1] xor 1;
  Plain := nil;
  ChiClaim(not DecryptFrame(Key, @Reused[0], CipherLen, nil, 0, Plain, PlainLen),
    'провод: порченый шифротекст принят');
  ChiBranch(IdCrypt, 'reject-tampered');

  Reused := Copy(Cipher, 0, CipherLen);
  Reused[ChiIvLen] := Reused[ChiIvLen] xor $80;
  ChiClaim(not DecryptFrame(Key, @Reused[0], CipherLen, nil, 0, Plain, PlainLen),
    'провод: порченая метка принята');
  ChiBranch(IdCrypt, 'reject-bad-tag');

  FillChar(Other, SizeOf(Other), $5A);
  ChiClaim(not DecryptFrame(Other, @Cipher[0], CipherLen, nil, 0, Plain, PlainLen),
    'провод: чужой ключ принят');
  ChiBranch(IdCrypt, 'reject-wrong-key');

  ChiClaim(not DecryptFrame(Key, @Cipher[0], CipherLen - 1, nil, 0, Plain, PlainLen),
    'провод: обрезанный кадр принят');
  ChiClaim(not DecryptFrame(Key, @Cipher[0], ChiIvLen + ChiTagLen, nil, 0,
                            Plain, PlainLen),
    'провод: кадр без тела принят');
  ChiBranch(IdCrypt, 'reject-truncated');

  { ── Дополнительные данные ──

    В живом коде провод зовётся с пустыми дополнительными данными на всех
    вызовах обеих сторон, поэтому переносить их как рабочую ветку было бы
    выдумкой. Здесь проверяется само свойство связки: разные дополнительные
    данные обязаны давать разные метки, а чужие — отвергаться. Подаются они
    тем способом, который эту связку действительно задействует.

    Проверено отдельным замером: способ, которым дополнительные данные подаёт
    живой код, на метку НЕ влияет — первый же `Encrypt` сбрасывает состояние
    и подмешивает только то, что было отдано заранее. Замечание записано в
    журнал; здесь это не утверждение о компиляторе. }
  ChiClaim(not SameTag(TagWithAad($11), TagWithAad(0)),
    'провод: дополнительные данные не влияют на метку');
  ChiClaim(not SameTag(TagWithAad($11), TagWithAad($22)),
    'провод: разные дополнительные данные дали одну метку');
  ChiClaim(AadRoundTrip($11, $11), 'провод: свои дополнительные данные отвергнуты');
  ChiClaim(not AadRoundTrip($11, $22), 'провод: чужие дополнительные данные приняты');
  ChiBranch(IdCrypt, 'aad');

  { ── Нетипизированные обёртки ── }
  Ping.Ver := ChiVer;
  Ping.MainId := 123456;
  Ping.Platform := 7;
  FixedIv(Iv, 4242);
  Cipher := nil;
  EncryptRec(Key, Ping, SizeOf(Ping), Iv, Cipher, CipherLen);
  FillChar(PingBack, SizeOf(PingBack), 0);
  ChiClaim(DecryptToRec(Key, @Cipher[0], CipherLen, PingBack, SizeOf(PingBack)),
    'провод: запись не вернулась');
  ChiClaim((PingBack.Ver = Ping.Ver) and (PingBack.MainId = Ping.MainId)
           and (PingBack.Platform = Ping.Platform),
    'провод: поля записи не сошлись');
  ChiBranch(IdWire, 'untyped-wrapper');

  { Несовпадение длины обязано быть отвергнуто, а не обрезано. }
  ChiClaim(not DecryptToRec(Key, @Cipher[0], CipherLen, Resp, SizeOf(Resp)),
    'провод: запись другой длины принята');
  ChiBranch(IdWire, 'length-mismatch');

  { ── Самоограниченный поток ── }
  for I := 0 to 5 do
  begin
    Quotes := MakeQuotes(1 + I * 3, 500 + UInt64(I));
    Payload := BuildPayload(Quotes);
    FixedIv(Iv, 900 + I);
    Cipher := nil;
    EncryptFrame(Key, @Payload[0], Length(Payload), nil, 0, Iv, Cipher, CipherLen);
    Plain := nil;
    ChiClaim(DecryptFrame(Key, @Cipher[0], CipherLen, nil, 0, Plain, PlainLen),
      'поток: кадр не расшифровался');
    ChiClaim(PlainLen = Length(Payload), 'поток: длина тела не сошлась');

    ChiClaim(ParsePayload(@Plain[0], PlainLen, Got), 'поток: разбор не дошёл до конца');
    ChiClaim(SameQuotes(Quotes, Got), 'поток: разбор дал не то');
    ChiClaim(ParseBySlices(Plain, PlainLen, Got2), 'поток: разбор по срезам не дошёл');
    ChiClaim(SameQuotes(Got, Got2), 'поток: два разборщика разошлись');
    Acc := ChiMix(Acc, PlainLen);
    Acc := ChiMix(Acc, Length(Got));
  end;
  ChiBranch(IdParse, 'roundtrip');
  ChiBranch(IdParse, 'two-parsers');

  { Обрезанный поток обязан быть отвергнут, а не разобран наполовину. }
  Quotes := MakeQuotes(4, 777);
  Payload := BuildPayload(Quotes);
  ChiClaim(not ParsePayload(@Payload[0], Length(Payload) - 3, Got),
    'поток: обрезанный разобран как целый');
  ChiClaim(not ParseBySlices(Payload, Length(Payload) - 3, Got2),
    'поток: обрезанный разобран по срезам');
  ChiBranch(IdParse, 'reject-overrun');

  { Пустой поток — только версия. }
  SetLength(Payload, 1);
  Payload[0] := ChiVer;
  ChiClaim(ParsePayload(@Payload[0], 1, Got), 'поток: пустой не принят');
  ChiClaim(Length(Got) = 0, 'поток: пустой дал записи');
  ChiBranch(IdParse, 'empty');

  { ── Вектор: монотонность и отсутствие повторов ── }
  for I := 0 to High(Ivs) do
  begin
    MakeIv(Iv);
    Ivs[I] := Iv.L;
  end;
  Ok := True;
  for I := 1 to High(Ivs) do
    if Ivs[I] = Ivs[I - 1] then Ok := False;
  ChiClaim(Ok, 'вектор: два одинаковых подряд');
  ChiClaim(IvCounter = Length(Ivs), 'вектор: счётчик не совпал с числом вызовов');
  ChiBranch(IdIv, 'counter-monotonic');

  Result := Int64(Acc and $7FFFFFFFFFFF);
end;

end.
