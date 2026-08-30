unit chimera_sign;

{ Орган «подписи»: сборка строки подписи биржевого запроса и её отпечаток.

  Источники: `ByBitEngine.pas`, `BitGetEngine.pas`, `GateEngine.pas`,
  `HuobiEngine.pas`, `OKXEngine.pas` — методы `BuildHMAC`. Форм четыре, и они
  различаются не мелочами, а устройством:

    * СЛИТНАЯ: `отметка + ключ + окно + параметры`, отпечаток шестнадцатеричной
      строкой;
    * ПУТЕВАЯ: `отметка + метод + версия + путь`, параметры через
      вопросительный знак ТОЛЬКО если они есть, тело ТОЛЬКО если оно есть,
      отпечаток в печатном виде;
    * СТРОЧНАЯ: части разделены ПЕРЕВОДОМ СТРОКИ, а вместо самого тела в
      строку подписи кладётся его отдельный отпечаток; итог считается на
      более длинном отпечатке;
    * СОРТИРУЮЩАЯ: параметры разбираются в список, СОРТИРУЮТСЯ своим
      сравнением (сначала по коду первого символа, и лишь при равенстве —
      без учёта регистра), каждый кусок кодируется для адреса, и только
      потом склеивается строка из метода, узла, пути и параметров через
      переводы строк. Список параметров при этом и вход, и выход.

  Пустая часть меняет не только длину, но и состав разделителей — а это ровно
  тот случай, где сворачивание условий даёт молча другую строку и отказ биржи
  на подписи.

  Заменено оснасткой: часы (отметка времени приходит параметром) и ключи.

  Оракулы:

    1. **стандартные векторы RFC 4231** для отпечатка с ключом — внешняя
       истина, не зависящая ни от нашего кода, ни от компилятора;
    2. **таблица ожидаемых строк подписи**, выписанная по правилам биржи
       вручную: каждое сочетание пустых и непустых частей предъявляется
       целиком, а не проверяется на длину;
    3. **отпечаток от собранной строки** сверяется с отпечатком, посчитанным
       от той же строки, собранной по-другому — конкатенацией списка кусков. }

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch INLINEVARS}
{$endif}
{$Q-}{$R-}

interface

uses
  SysUtils, mormot.core.base, mormot.crypt.core, chimera_body;

type
  TChiReqKind = (rkGet, rkPost, rkPut, rkDelete, rkPatch);

function ChiSignRun: Int64;

implementation

{ ═══ Отпечаток ═══════════════════════════════════════════════════════════ }

function HmacHex(const AKey, AData: RawByteString): string;
var
  Mac: THash256;
  I: Integer;
begin
  HmacSha256(pointer(AKey), pointer(AData), Length(AKey), Length(AData), Mac);
  Result := '';
  for I := 0 to 31 do
    Result := Result + LowerCase(IntToHex(THash256Rec(Mac).b[I], 2));
end;

function HmacBytes(const AKey, AData: RawByteString): TBytes;
var
  Mac: THash256;
begin
  HmacSha256(pointer(AKey), pointer(AData), Length(AKey), Length(AData), Mac);
  SetLength(Result, 32);
  Move(Mac, Result[0], 32);
end;

{ Печатный вид — своей таблицей, чтобы не зависеть от библиотеки. }
const
  B64: array [0 .. 63] of AnsiChar =
    ('A','B','C','D','E','F','G','H','I','J','K','L','M','N','O','P',
     'Q','R','S','T','U','V','W','X','Y','Z','a','b','c','d','e','f',
     'g','h','i','j','k','l','m','n','o','p','q','r','s','t','u','v',
     'w','x','y','z','0','1','2','3','4','5','6','7','8','9','+','/');

function ToBase64(const Data: TBytes): string;
var
  I, N: Integer;
  Chunk: Cardinal;
begin
  Result := '';
  I := 0;
  N := Length(Data);
  while I < N do
  begin
    Chunk := Cardinal(Data[I]) shl 16;
    if I + 1 < N then Chunk := Chunk or (Cardinal(Data[I + 1]) shl 8);
    if I + 2 < N then Chunk := Chunk or Cardinal(Data[I + 2]);
    Result := Result + Char(B64[(Chunk shr 18) and 63])
                     + Char(B64[(Chunk shr 12) and 63]);
    if I + 1 < N then
      Result := Result + Char(B64[(Chunk shr 6) and 63])
    else
      Result := Result + '=';
    if I + 2 < N then
      Result := Result + Char(B64[Chunk and 63])
    else
      Result := Result + '=';
    Inc(I, 3);
  end;
end;

{ ═══ Перенесённые формы ══════════════════════════════════════════════════ }

{ Первая биржа: слитная склейка четырёх частей, отпечаток шестнадцатеричный. }
function BuildFlat(const TimeStamp, ApiKey, RecWnd, CmdParams: string;
  const Secret: RawByteString; out RawStr: string): string;
begin
  RawStr := TimeStamp + ApiKey + RecWnd + CmdParams;
  Result := HmacHex(Secret, RawByteString(RawStr));
end;

{ Вторая биржа: путь с условными частями, отпечаток в печатном виде. }
function BuildPath(Kind: TChiReqKind; const TimeStamp, VerPrefix, Command,
  CmdParams, PayLoad: string; const Secret: RawByteString;
  out RawStr: string): string;
var
  SKind: string;
begin
  case Kind of
    rkGet:    SKind := 'GET';
    rkPost:   SKind := 'POST';
    rkPut:    SKind := 'PUT';
    rkDelete: SKind := 'DELETE';
    rkPatch:  SKind := 'PATCH';
  end;

  RawStr := TimeStamp + SKind + VerPrefix + Command;
  { Вопросительный знак появляется ТОЛЬКО при непустых параметрах. }
  if CmdParams <> '' then
    RawStr := RawStr + '?' + CmdParams;
  { Тело дописывается ТОЛЬКО если оно есть — без всякого разделителя. }
  if PayLoad <> '' then
    RawStr := RawStr + PayLoad;

  Result := ToBase64(HmacBytes(Secret, RawByteString(RawStr)));
end;

{ ═══ Строчная форма: разделитель переводом строки, отпечаток тела ═══════ }

function Sha512Hex(const AData: RawByteString): string;
var
  H: TSha512;
  D: TSha512Digest;
  I: Integer;
begin
  H.Full(Pointer(AData), Length(AData), D);
  Result := '';
  for I := 0 to High(D) do
    Result := Result + LowerCase(IntToHex(D[I], 2));
end;

function HmacSha512Hex(const AKey, AData: RawByteString): string;
var
  Mac: TSha512Digest;
  I: Integer;
begin
  HmacSha512(Pointer(AKey), Pointer(AData), Length(AKey), Length(AData), Mac);
  Result := '';
  for I := 0 to High(Mac) do
    Result := Result + LowerCase(IntToHex(Mac[I], 2));
end;

function BuildLineJoined(Kind: TChiReqKind; const TimeStamp, VerPrefix,
  Command, CmdParams, PayLoad: string; const Secret: RawByteString;
  out RawStr: string): string;
const
  Sn = Char(#10);
var
  SKind, BodyHash: string;
begin
  case Kind of
    rkGet:    SKind := 'GET';
    rkPost:   SKind := 'POST';
    rkPut:    SKind := 'PUT';
    rkDelete: SKind := 'DELETE';
    rkPatch:  SKind := 'PATCH';
  end;
  { В строку подписи идёт не тело, а его отдельный отпечаток — даже когда тело
    пустое: отпечаток пустого тела всё равно есть, и он обязан там стоять. }
  BodyHash := Sha512Hex(RawByteString(PayLoad));
  RawStr := SKind + Sn + VerPrefix + Command + Sn + CmdParams + Sn
            + BodyHash + Sn + TimeStamp;
  Result := HmacSha512Hex(Secret, RawByteString(RawStr));
end;

{ ═══ Сортирующая форма ══════════════════════════════════════════════════ }

{ Сравнение живого кода: сперва по КОДУ первого символа, и лишь при равенстве
  — без учёта регистра. Порядок из него выходит неочевидный, и именно он
  попадает в подпись. }
function ChiParamCompare(const S1, S2: string): Integer;
begin
  if (S1 = '') or (S2 = '') then
    Exit(Length(S1) - Length(S2));
  Result := Ord(S1[1]) - Ord(S2[1]);
  if Result = 0 then
    Result := CompareText(S1, S2);
end;

procedure SortParams(var Items: TArray<string>);
var
  I, J: Integer;
  T: string;
begin
  { Сортировка вставками: предмет проверки — само сравнение и порядок, а не
    скорость. }
  for I := 1 to High(Items) do
  begin
    T := Items[I];
    J := I - 1;
    while (J >= 0) and (ChiParamCompare(Items[J], T) > 0) do
    begin
      Items[J + 1] := Items[J];
      Dec(J);
    end;
    Items[J + 1] := T;
  end;
end;

{ Кодирование для адреса: небезопасные символы заменяются, пробел — плюсом. }
function EncodeParam(const S: string): string;
const
  Unsafe = ['"', '''', '<', '>', '#', ':'];
var
  I: Integer;
  C: Char;
begin
  Result := '';
  for I := 1 to Length(S) do
  begin
    C := S[I];
    if C = ' ' then
      Result := Result + '+'
    else if (Ord(C) < 128) and CharInSet(C, Unsafe) then
      Result := Result + '%' + IntToHex(Ord(C), 2)
    else
      Result := Result + C;
  end;
end;

{ Список параметров здесь и вход, и выход: подпись строится по нему же, а сам
  он к концу оказывается пересобранным и отсортированным. }
function BuildSorted(Kind: TChiReqKind; const Host, Command: string;
  var CmdParams: string; const ApiKey, TimeStamp: string;
  const Secret: RawByteString; out RawStr: string): string;
const
  Lb = Char(#10);
var
  Req: string;
  Parts: TArray<string>;
  I: Integer;
  Joined: string;
begin
  if Kind = rkPost then Req := 'POST' else Req := 'GET';
  Req := Req + Lb + Host + Lb + '/' + Command + Lb;

  if CmdParams <> '' then CmdParams := CmdParams + '&';
  CmdParams := CmdParams + 'SignatureMethod=HmacSHA256&SignatureVersion=2'
               + '&AccessKeyId=' + ApiKey + '&Timestamp=' + TimeStamp;

  Parts := CmdParams.Split(['&']);
  SortParams(Parts);

  Joined := '';
  for I := 0 to High(Parts) do
  begin
    if Parts[I] = '' then Continue;
    if Joined <> '' then Joined := Joined + '&';
    Joined := Joined + EncodeParam(Parts[I]);
  end;
  CmdParams := Joined;
  RawStr := Req + Joined;
  Result := ToBase64(HmacBytes(Secret, RawByteString(RawStr)));
end;

{ ═══ Независимая сборка ══════════════════════════════════════════════════

  Те же правила, но строка собирается не наращиванием, а склейкой списка
  кусков: пустые куски в список просто не попадают. }

function JoinParts(const Parts: array of string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(Parts) do
    Result := Result + Parts[I];
end;

function PathPartsOracle(Kind: TChiReqKind; const TimeStamp, VerPrefix,
  Command, CmdParams, PayLoad: string): string;
var
  Verb, Query, Body: string;
begin
  case Kind of
    rkGet:    Verb := 'GET';
    rkPost:   Verb := 'POST';
    rkPut:    Verb := 'PUT';
    rkDelete: Verb := 'DELETE';
    rkPatch:  Verb := 'PATCH';
  end;
  if CmdParams = '' then Query := '' else Query := '?' + CmdParams;
  if PayLoad = '' then Body := '' else Body := PayLoad;
  Result := JoinParts([TimeStamp, Verb, VerPrefix, Command, Query, Body]);
end;

{ ═══ Проверка ════════════════════════════════════════════════════════════ }

const
  IdSign  = 'CHI-MB-SIGN-001';
  IdLine  = 'CHI-MB-SIGN-002';
  IdSort  = 'CHI-MB-SIGN-003';

function ChiSignRun: Int64;
var
  Acc: UInt64;
  Raw, RawB, Sig: string;
  Key: RawByteString;
  I: Integer;
  Kind: TChiReqKind;
  Params, Body: string;
  Empties: Integer;
begin
  ChiCovered(IdSign);
  ChiCovered(IdLine);
  ChiCovered(IdSort);
  Acc := ChiOffset;

  { ── Внешняя истина: векторы RFC 4231 ── }
  SetLength(Key, 20);
  for I := 1 to 20 do Key[I] := AnsiChar($0B);
  ChiClaim(HmacHex(Key, RawByteString('Hi There'))
    = 'b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7',
    'подписи: вектор 1 не сошёлся');
  ChiClaim(HmacHex(RawByteString('Jefe'),
                   RawByteString('what do ya want for nothing?'))
    = '5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843',
    'подписи: вектор 2 не сошёлся');
  ChiBranch(IdSign, 'rfc-vectors');

  { Печатный вид тоже проверяется вектором: отпечаток «Jefe» в base64. }
  ChiClaim(ToBase64(HmacBytes(RawByteString('Jefe'),
                              RawByteString('what do ya want for nothing?')))
    = 'W9zBRr9gdU5qBCQmCJV1x1oAPwidJzmDnexYuWTsOEM=',
    'подписи: печатный вид отпечатка не сошёлся');
  ChiBranch(IdSign, 'base64-vector');

  Key := RawByteString('secret-key-0123456789');

  { ── Слитная форма: строка предъявляется целиком ── }
  Sig := BuildFlat('1735689600000', 'APIKEY', '45000', 'symbol=BTCUSDT',
                   Key, Raw);
  ChiClaim(Raw = '1735689600000APIKEY45000symbol=BTCUSDT',
    'подписи: слитная строка собрана не так');
  ChiClaim(Sig = HmacHex(Key, RawByteString(Raw)),
    'подписи: отпечаток не от той строки');
  ChiBranch(IdSign, 'flat');
  Acc := ChiMix(Acc, Length(Raw));

  { Пустые параметры не имеют права оставить хвост. }
  Sig := BuildFlat('1735689600000', 'APIKEY', '45000', '', Key, Raw);
  ChiClaim(Raw = '1735689600000APIKEY4500' + '0',
    'подписи: пустые параметры изменили строку');
  ChiBranch(IdSign, 'flat-empty');

  { ── Путевая форма: все сочетания пустых и непустых частей ── }
  Empties := 0;
  for I := 0 to 3 do
  begin
    if (I and 1) = 0 then Params := '' else Params := 'a=1&b=2';
    if (I and 2) = 0 then Body := '' else Body := '{"x":1}';
    if (Params = '') or (Body = '') then Inc(Empties);

    Sig := BuildPath(rkPost, '1735689600000', '/api/v2', '/order',
                     Params, Body, Key, Raw);
    RawB := PathPartsOracle(rkPost, '1735689600000', '/api/v2', '/order',
                            Params, Body);
    ChiClaim(Raw = RawB,
      'подписи: путевая строка разошлась с независимой сборкой, случай '
      + IntToStr(I));
    ChiClaim(Sig = ToBase64(HmacBytes(Key, RawByteString(Raw))),
      'подписи: печатный отпечаток не от той строки');
    Acc := ChiMix(Acc, Length(Raw));
  end;
  ChiClaim(Empties = 3, 'подписи: пустые части не встретились');
  ChiBranch(IdSign, 'path-combinations');

  { Строки предъявляются целиком — на них ошибка видна сразу. }
  BuildPath(rkGet, 'T', '/v', '/c', '', '', Key, Raw);
  ChiClaim(Raw = 'TGET/v/c', 'подписи: пустые части оставили разделители');
  BuildPath(rkGet, 'T', '/v', '/c', 'q=1', '', Key, Raw);
  ChiClaim(Raw = 'TGET/v/c?q=1', 'подписи: параметры без вопроса');
  BuildPath(rkGet, 'T', '/v', '/c', '', 'BODY', Key, Raw);
  ChiClaim(Raw = 'TGET/v/cBODY', 'подписи: тело получило лишний разделитель');
  BuildPath(rkGet, 'T', '/v', '/c', 'q=1', 'BODY', Key, Raw);
  ChiClaim(Raw = 'TGET/v/c?q=1BODY', 'подписи: полная строка собрана не так');
  ChiBranch(IdSign, 'exact-strings');

  { Все виды запроса дают свой глагол. }
  for Kind := Low(TChiReqKind) to High(TChiReqKind) do
  begin
    BuildPath(Kind, 'T', '/v', '/c', '', '', Key, Raw);
    ChiClaim(Raw = PathPartsOracle(Kind, 'T', '/v', '/c', '', ''),
      'подписи: глагол запроса собран не так');
    Acc := ChiMix(Acc, Length(Raw));
  end;
  ChiBranch(IdSign, 'all-verbs');

  { Длинная строка параметров: наращивание управляемой строки много раз. }
  Params := '';
  for I := 1 to 300 do Params := Params + 'k' + IntToStr(I) + '=v&';
  Sig := BuildPath(rkPost, 'T', '/v', '/c', Params, '', Key, Raw);
  ChiClaim(Length(Raw) = Length('TPOST/v/c?') + Length(Params),
    'подписи: длинная строка собрана не той длины');
  ChiClaim(Sig = ToBase64(HmacBytes(Key, RawByteString(Raw))),
    'подписи: отпечаток длинной строки не тот');
  ChiBranch(IdSign, 'long-params');
  Acc := ChiMix(Acc, Length(Raw));

  { Ключ длиннее блока отпечатка обязан сначала сворачиваться — вектор
    RFC 4231 с ключом в сто тридцать один байт. }
  SetLength(Key, 131);
  for I := 1 to 131 do Key[I] := AnsiChar($AA);
  ChiClaim(HmacHex(Key, RawByteString(
      'Test Using Larger Than Block-Size Key - Hash Key First'))
    = '60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54',
    'подписи: длинный ключ свёрнут неверно');
  ChiBranch(IdSign, 'long-key');

  { ═══ Строчная форма ═══════════════════════════════════════════════════ }

  { Отпечаток длиннее: сто двадцать восемь знаков вместо шестидесяти четырёх. }
  ChiClaim(Sha512Hex(RawByteString('')) =
    'cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce'
    + '47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e',
    'подписи: отпечаток пустого тела не совпал с вектором');
  ChiClaim(Sha512Hex(RawByteString('abc')) =
    'ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a'
    + '2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f',
    'подписи: отпечаток тела не совпал с вектором');
  ChiBranch(IdLine, 'sha512-vector');

  ChiClaim(HmacSha512Hex(RawByteString('Jefe'),
                         RawByteString('what do ya want for nothing?')) =
    '164b7a7bfcf819e2e395fbe73b56e0a387bd64222e831fd610270cd7ea250554'
    + '9758bf75c05a994a6d034f65f8f0e6fdcaeab1a34d4a6b4b636e070a38bce737',
    'подписи: длинный отпечаток с ключом не совпал с вектором');
  ChiBranch(IdLine, 'hmac512-vector');

  Key := RawByteString('secret-key-0123456789');
  Sig := BuildLineJoined(rkPost, '1735689600000', '/api/v4', '/spot/orders',
                         'currency_pair=BTC_USDT', '{"amount":"1"}', Key, Raw);
  { Строка предъявляется целиком: разделители — переводы строк, а вместо тела
    в ней стоит его отдельный отпечаток. }
  ChiClaim(Raw = 'POST'#10'/api/v4/spot/orders'#10'currency_pair=BTC_USDT'#10
                 + Sha512Hex(RawByteString('{"amount":"1"}')) + #10
                 + '1735689600000',
    'подписи: строчная форма собрана не так');
  ChiClaim(Sig = HmacSha512Hex(Key, RawByteString(Raw)),
    'подписи: отпечаток строчной формы не от той строки');
  ChiBranch(IdLine, 'line-joined');
  Acc := ChiMix(Acc, Length(Raw));

  { Пустое тело не убирает свой отпечаток из строки — он там всё равно есть. }
  BuildLineJoined(rkGet, 'T', '/v4', '/spot/accounts', '', '', Key, Raw);
  ChiClaim(Pos(Sha512Hex(RawByteString('')), Raw) > 0,
    'подписи: отпечаток пустого тела пропал из строки');
  ChiClaim(Raw = 'GET'#10'/v4/spot/accounts'#10#10
                 + Sha512Hex(RawByteString('')) + #10'T',
    'подписи: строка с пустыми частями собрана не так');
  ChiBranch(IdLine, 'empty-body-still-hashed');

  { Разные тела обязаны давать разные строки — иначе подмену тела не заметят. }
  BuildLineJoined(rkPost, 'T', '/v4', '/o', '', '{"a":1}', Key, Raw);
  BuildLineJoined(rkPost, 'T', '/v4', '/o', '', '{"a":2}', Key, RawB);
  ChiClaim(Raw <> RawB, 'подписи: разные тела дали одну строку');
  ChiBranch(IdLine, 'body-affects-signature');

  { ═══ Сортирующая форма ════════════════════════════════════════════════ }

  { Сравнение живого кода устроено так, что регистр ПЕРВОГО символа значим, а
    регистр остальных — нет: первый шаг сравнивает коды, и до сравнения без
    регистра дело доходит только когда первые символы совпали точно. }
  ChiClaim(ChiParamCompare('Zebra', 'apple') < 0,
    'подписи: заглавная не встала раньше строчной по коду');
  ChiClaim(ChiParamCompare('apple', 'APPLE') > 0,
    'подписи: регистр первого символа не учтён');
  ChiClaim(ChiParamCompare('apple', 'apPLE') = 0,
    'подписи: регистр хвоста не должен различаться');
  ChiClaim(ChiParamCompare('ab', 'ac') < 0, 'подписи: второй символ не учтён');
  ChiBranch(IdSort, 'comparer');

  Params := 'symbol=btcusdt&type=buy-limit';
  Sig := BuildSorted(rkGet, 'api.example.com', 'v1/order/orders',
                     Params, 'KEY123', '2026-08-30T12:00:00', Key, Raw);

  { Список параметров и вход, и выход: к концу он пересобран и отсортирован. }
  ChiClaim(Params <> 'symbol=btcusdt&type=buy-limit',
    'подписи: список параметров не пересобран');
  ChiClaim(Pos('AccessKeyId=KEY123', Params) > 0,
    'подписи: ключ доступа не добавлен в параметры');
  ChiBranch(IdSort, 'params-in-out');

  { Порядок обязан быть тем, что даёт сравнение, а не тем, что подали. }
  ChiClaim(Params = 'AccessKeyId=KEY123&SignatureMethod=HmacSHA256'
                    + '&SignatureVersion=2&Timestamp=2026-08-30T12%3A00%3A00'
                    + '&symbol=btcusdt&type=buy-limit',
    'подписи: параметры отсортированы не так: ' + Params);
  ChiBranch(IdSort, 'sorted-order');

  { Двоеточие в отметке времени обязано быть закодировано. }
  ChiClaim(Pos('%3A', Params) > 0, 'подписи: двоеточие не закодировано');
  ChiClaim(Pos('12:00', Params) = 0, 'подписи: сырое двоеточие осталось');
  ChiBranch(IdSort, 'encoded-unsafe');

  ChiClaim(Sig = ToBase64(HmacBytes(Key, RawByteString(Raw))),
    'подписи: отпечаток сортирующей формы не от той строки');
  ChiClaim(Pos(#10, Raw) > 0, 'подписи: в строке нет переводов строк');
  ChiBranch(IdSort, 'signature');
  Acc := ChiMix(Acc, Length(Params));
  Acc := ChiMix(Acc, Length(Raw));

  { Пустые входные параметры: остаются только служебные. }
  Params := '';
  BuildSorted(rkPost, 'h', 'c', Params, 'K', 'T', Key, Raw);
  ChiClaim(Params = 'AccessKeyId=K&SignatureMethod=HmacSHA256'
                    + '&SignatureVersion=2&Timestamp=T',
    'подписи: пустые параметры собраны не так: ' + Params);
  ChiBranch(IdSort, 'empty-params');

  Result := Int64(Acc and $7FFFFFFFFFFF);
end;

end.
