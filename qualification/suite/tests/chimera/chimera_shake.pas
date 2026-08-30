unit chimera_shake;

{ Орган «рукопожатие»: разбор ответа сервера при подключении и строковая
  работа вокруг него.

  ── CHI-MB-SHAKE-001 ──────────────────────────────────────────────────────
  Источник: `MoonBot/websocket\WebSocket.Thread.pas` ::
  `TWSThread.DoHandshake`, `HttpHeaderIs`, `HttpHeaderContains` (та же форма —
  в `Arbitrage/webSocket\WebSocket.Thread.pas`). Перенесено
  дословно по форме:

    * запрос собирается склейкой строк, и путь приводится к виду с ведущей
      косой чертой ТРЕМЯ разными дорогами: пусто, уже с чертой, без черты;
    * ключ подключения — шестнадцать байт в печатном виде, ответ сервера
      обязан быть отпечатком этого ключа со сшитой к нему постоянной строкой,
      тоже в печатном виде;
    * конец заголовков ищется в кольцевом буфере сравнением ЧЕТЫРЁХ БАЙТ
      одним словом — не посимвольно. Данные приходят кусками, и граница
      четвёрки может лечь между кусками;
    * заголовки читаются по имени БЕЗ учёта регистра, значение сравнивается
      началом строки, а список расширений — поиском подстроки без учёта
      регистра;
    * непрошеный подпротокол — отказ, даже если всё остальное верно.

  ── CHI-ARB-NAMEHASH-001 ──────────────────────────────────────────────────
  Источник: `MoonBot/Arb\ArbClientU.pas` — имя рынка режется по
  разделителю, левая часть переводится из байтов провода в строку программы, а
  по правой считается контрольная сумма имени. Рядом — приведение имён к
  нижнему регистру и сравнение стороны сделки без учёта регистра, как в
  `GroupManager.pas` и разборщиках движков.

  Заменено оснасткой: сокет и источник случайности ключа.

  Оракулы:

    1. известные векторы: отпечаток и контрольная сумма проверяются
       общепринятыми значениями, печатный вид — своим кодировщиком, написанным
       здесь по таблице;
    2. правильность проверки текста в кодировке предъявляется таблицей: рядом
       стоят законные и порченые последовательности, и для каждой заранее
       выписан ответ;
    3. приход ответа кусками проверяется прогоном по ВСЕМ местам разреза: где
       бы ни легла граница, ответ обязан получиться один и тот же. }

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch INLINEVARS}
{$endif}
{$Q-}{$R-}

interface

uses
  SysUtils, Classes, Generics.Collections,
  mormot.core.base, mormot.core.text, mormot.core.data, mormot.core.buffers,
  mormot.core.unicode, mormot.crypt.core, chimera_body;

function ChiShakeRun: Int64;

implementation

const
  IdShake = 'CHI-MB-SHAKE-001';
  IdHash  = 'CHI-ARB-NAMEHASH-001';

  { Постоянная строка рукопожатия из описания протокола. }
  ShakeSalt = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

{ ═══ Живая форма: чтение заголовков ══════════════════════════════════════ }

function HttpHeaderIs(P: PUtf8Char; UpperName: PAnsiChar; UpperValue: PAnsiChar): Boolean;
var
  Hdr: RawUtf8;
begin
  Hdr := FindIniNameValue(P, UpperName);
  Result := IdemPChar(Pointer(Hdr), UpperValue);
end;

function HttpHeaderContains(P: PUtf8Char; UpperName: PAnsiChar; const SubStr: RawUtf8): Boolean;
var
  Hdr: RawUtf8;
begin
  Hdr := FindIniNameValue(P, UpperName);
  Result := PosExI(SubStr, Hdr, 1) > 0;
end;

{ ═══ Живая форма: сборка запроса ═════════════════════════════════════════ }

function BuildRequest(const AUrlPath, AHost, AOrigin, AKey: RawUtf8;
  ADeflate: Boolean): RawUtf8;
var
  Path: RawUtf8;
begin
  if AUrlPath = '' then
    Path := '/'
  else if AUrlPath[1] = '/' then
    Path := AUrlPath
  else
    Path := '/' + AUrlPath;

  Result :=
    'GET ' + Path + ' HTTP/1.1'#13#10 +
    'Host: ' + AHost + #13#10 +
    'Upgrade: websocket'#13#10 +
    'Connection: Upgrade'#13#10 +
    'User-Agent: MoonBot-WS/1.0'#13#10 +
    'Sec-WebSocket-Key: ' + AKey + #13#10 +
    'Sec-WebSocket-Version: 13'#13#10;
  if AOrigin <> '' then
    Result := Result + 'Origin: ' + AOrigin + #13#10;
  if ADeflate then
    Result := Result + 'Sec-WebSocket-Extensions: permessage-deflate; client_max_window_bits'#13#10;
  Result := Result + #13#10;
end;

{ ═══ Живая форма: приём ответа кусками и его проверка ════════════════════ }

type
  TChiShakeResult = (srOk, srNoStatus, srNoUpgrade, srNoConnection,
                     srBadAccept, srUnwantedProtocol);

  { Кольцо приёма: ответ кладётся кусками, конец заголовков ищется словом. }
  TChiShakeReader = class
  private
    FRing:    array of Byte;
    FRingLen: Integer;
    FRingPos: Integer;
    FDeflate: Boolean;
    FNoTakeover: Boolean;
    FExtensions: RawUtf8;
    FReads:   Integer;
  public
    constructor Create;
    function Feed(const AChunk: RawByteString): Boolean;
    function Check(const AWsKey: RawUtf8): TChiShakeResult;
    property NoTakeover: Boolean read FNoTakeover;
    property Extensions: RawUtf8 read FExtensions;
    property Reads: Integer read FReads;
    property Rest: Integer read FRingPos;
  end;

constructor TChiShakeReader.Create;
begin
  inherited Create;
  SetLength(FRing, 8192);
  FDeflate := True;
end;

{ Возвращает истину, когда конец заголовков уже виден. Сравнение идёт
  четырьмя байтами сразу, поэтому граница куска внутри этой четвёрки — не
  особый случай, а обычный: следующий кусок просто дополняет кольцо. }
function TChiShakeReader.Feed(const AChunk: RawByteString): Boolean;
var
  HdrEnd: Integer;
begin
  Move(Pointer(AChunk)^, FRing[FRingLen], Length(AChunk));
  Inc(FRingLen, Length(AChunk));
  Inc(FReads);
  HdrEnd := -1;
  for var I := 0 to FRingLen - 4 do
    if PCardinal(@FRing[I])^ = $0A0D0A0D then
    begin
      HdrEnd := I + 4;
      Break;
    end;
  Result := HdrEnd > 0;
  if Result then
    FRingPos := HdrEnd;
end;

function TChiShakeReader.Check(const AWsKey: RawUtf8): TChiShakeResult;
var
  RespStr:        RawUtf8;
  RespPtr:        PUtf8Char;
  AcceptInput:    RawUtf8;
  ExpectedAccept: RawUtf8;
  GotAccept:      RawUtf8;
  ExtVal:         RawUtf8;
  Sha:            TSha1;
  Dig:            TSha1Digest;
begin
  FastSetString(RespStr, Pointer(FRing), FRingPos);
  RespPtr := Pointer(RespStr);

  if not IdemPChar(RespPtr, 'HTTP/1.1 101 ') then
    Exit(srNoStatus);
  if not HttpHeaderIs(RespPtr, 'UPGRADE: ', 'WEBSOCKET') then
    Exit(srNoUpgrade);
  if not HttpHeaderContains(RespPtr, 'CONNECTION: ', 'upgrade') then
    Exit(srNoConnection);

  AcceptInput := AWsKey + ShakeSalt;
  Sha.Full(Pointer(AcceptInput), Length(AcceptInput), Dig);
  ExpectedAccept := BinToBase64(@Dig, SizeOf(Dig));
  GotAccept := FindIniNameValue(RespPtr, 'SEC-WEBSOCKET-ACCEPT: ');
  if GotAccept <> ExpectedAccept then
    Exit(srBadAccept);

  if FindIniNameValue(RespPtr, 'SEC-WEBSOCKET-PROTOCOL: ') <> '' then
    Exit(srUnwantedProtocol);

  if FDeflate then
  begin
    ExtVal := FindIniNameValue(RespPtr, 'SEC-WEBSOCKET-EXTENSIONS: ');
    if ExtVal <> '' then
      FExtensions := ExtVal;
    if PosExI('permessage-deflate', ExtVal, 1) > 0 then
      FNoTakeover := PosExI('server_no_context_takeover', ExtVal, 1) > 0;
  end;
  Result := srOk;
end;

{ ═══ Оракул печатного вида: своя таблица, свой код ═══════════════════════ }

const
  B64Tab: array [0 .. 63] of AnsiChar =
    ('A','B','C','D','E','F','G','H','I','J','K','L','M','N','O','P',
     'Q','R','S','T','U','V','W','X','Y','Z','a','b','c','d','e','f',
     'g','h','i','j','k','l','m','n','o','p','q','r','s','t','u','v',
     'w','x','y','z','0','1','2','3','4','5','6','7','8','9','+','/');

function OracleBase64(Bin: PByte; Len: Integer): RawUtf8;
var
  Chunk: Cardinal;
  I:     Integer;
begin
  Result := '';
  I := 0;
  while I < Len do
  begin
    Chunk := Cardinal(Bin[I]) shl 16;
    if I + 1 < Len then Chunk := Chunk or (Cardinal(Bin[I + 1]) shl 8);
    if I + 2 < Len then Chunk := Chunk or Cardinal(Bin[I + 2]);
    Result := Result + B64Tab[(Chunk shr 18) and 63] + B64Tab[(Chunk shr 12) and 63];
    if I + 1 < Len
      then Result := Result + B64Tab[(Chunk shr 6) and 63]
      else Result := Result + '=';
    if I + 2 < Len
      then Result := Result + B64Tab[Chunk and 63]
      else Result := Result + '=';
    Inc(I, 3);
  end;
end;

{ ═══ Оракул проверки текста: правила кодировки своим кодом ═══════════════ }

function OracleValidUtf8(P: PByte; Len: Integer): Boolean;
var
  I, Need: Integer;
  B, Lo:   Byte;
begin
  I := 0;
  while I < Len do
  begin
    B := P[I];
    if B < $80 then
    begin
      Inc(I);
      Continue;
    end;
    Lo := $80;
    if (B >= $C2) and (B <= $DF) then Need := 1
    else if B = $E0 then begin Need := 2; Lo := $A0; end
    else if (B >= $E1) and (B <= $EF) then Need := 2
    else if B = $F0 then begin Need := 3; Lo := $90; end
    else if (B >= $F1) and (B <= $F4) then Need := 3
    else Exit(False);
    { суррогатная область в кодировке запрещена }
    if (B = $ED) and (I + 1 < Len) and (P[I + 1] >= $A0) then Exit(False);
    if B = $F4 then
      if (I + 1 < Len) and (P[I + 1] > $8F) then Exit(False);
    if I + Need >= Len then Exit(False);
    if (P[I + 1] < Lo) or (P[I + 1] > $BF) then Exit(False);
    for var K := 2 to Need do
      if (P[I + K] < $80) or (P[I + K] > $BF) then Exit(False);
    Inc(I, Need + 1);
  end;
  Result := True;
end;

{ Байты провода. Литерал вида RawUtf8(#$D0#$91) байтами НЕ является: он
  сначала становится строкой символов, а потом перекодируется — и вместо двух
  байт получается девять; даже приведение к строке байтов идёт через кодовую
  страницу, и не всякое число доезжает собой. Провод же отдаёт именно байты,
  поэтому образцы собираются здесь ЧИСЛАМИ. }
function Bin(const A: array of Byte): RawByteString;
begin
  SetLength(Result, Length(A));
  if Length(A) > 0 then
    Move(A[0], Pointer(Result)^, Length(A));
end;

function WireBytes(const ABytes: RawByteString): RawUtf8;
begin
  FastSetString(Result, Pointer(ABytes), Length(ABytes));
end;

{ ═══ Оснастка: сборка ответа сервера ═════════════════════════════════════ }

function MakeAccept(const AWsKey: RawUtf8): RawUtf8;
var
  Sha: TSha1;
  Dig: TSha1Digest;
begin
  Sha.Full(Pointer(AWsKey + ShakeSalt), Length(AWsKey) + Length(ShakeSalt), Dig);
  Result := OracleBase64(@Dig[0], SizeOf(Dig));
end;

function MakeResponse(const AAccept, AExtra: RawUtf8): RawByteString;
begin
  Result := RawByteString(
    'HTTP/1.1 101 Switching Protocols'#13#10 +
    'Upgrade: WebSocket'#13#10 +
    'Connection: Upgrade'#13#10 +
    'Sec-WebSocket-Accept: ' + AAccept + #13#10 +
    AExtra +
    #13#10);
end;

{ ═══ Прогон ══════════════════════════════════════════════════════════════ }

function ChiShakeRun: Int64;
var
  Acc:      UInt64;
  Key16:    array [0 .. 15] of Byte;
  WsKey:    RawUtf8;
  Accept:   RawUtf8;
  Resp:     RawByteString;
  Reader:   TChiShakeReader;
  Src:      TChiSource;
  Sha:      TSha1;
  Dig:      TSha1Digest;
begin
  Acc := 0;

  { ── Печатный вид: общепринятые примеры и свой кодировщик ── }
  ChiCovered(IdShake);
  ChiClaim(BinToBase64(RawByteString('')) = '', 'печать: пусто дало не пусто');
  ChiClaim(BinToBase64(RawByteString('f')) = 'Zg==', 'печать: один байт неверен');
  ChiClaim(BinToBase64(RawByteString('fo')) = 'Zm8=', 'печать: два байта неверны');
  ChiClaim(BinToBase64(RawByteString('foo')) = 'Zm9v', 'печать: три байта неверны');
  ChiClaim(BinToBase64(RawByteString('foobar')) = 'Zm9vYmFy', 'печать: шесть байт неверны');
  ChiBranch(IdShake, 'base64-vectors');

  { Свой кодировщик обязан совпасть с библиотечным на всех длинах остатка. }
  Src := ChiSource(20260830);
  for var Len := 1 to 64 do
  begin
    var Bin: TBytes;
    SetLength(Bin, Len);
    for var I := 0 to Len - 1 do
      Bin[I] := Byte(Src.NextBelow(256));
    ChiClaim(BinToBase64(PAnsiChar(Pointer(Bin)), Len) = OracleBase64(@Bin[0], Len),
      'печать: библиотечная и своя запись разошлись на длине ' + IntToStr(Len));
  end;
  ChiBranch(IdShake, 'base64-matches-oracle');

  { ── Отпечаток: общепринятый пример ── }
  { Указатель берётся у переменной, а не у временной строки прямо в вызове:
    строгий компилятор такого приведения не допускает. }
  var Abc: RawUtf8 := 'abc';
  Sha.Full(Pointer(Abc), Length(Abc), Dig);
  ChiClaim(LowerCase(BinToHexLower(@Dig, SizeOf(Dig))) =
           'a9993e364706816aba3e25717850c26c9cd0d89d',
    'отпечаток: общепринятый пример не сошёлся');
  ChiBranch(IdShake, 'sha1-vector');

  { ── Сборка запроса: три дороги пути ── }
  for var I := 0 to High(Key16) do
    Key16[I] := Byte(Src.NextBelow(256));
  WsKey := BinToBase64(PAnsiChar(@Key16[0]), 16);
  ChiClaim(Length(WsKey) = 24, 'запрос: ключ подключения не той длины');

  var R1 := BuildRequest('', 'ex.com', '', WsKey, False);
  var R2 := BuildRequest('/ws/v1', 'ex.com', '', WsKey, False);
  var R3 := BuildRequest('ws/v1', 'ex.com', '', WsKey, False);
  ChiClaim(Pos(RawUtf8('GET / HTTP/1.1'), R1) = 1, 'запрос: пустой путь не стал чертой');
  ChiClaim(Pos(RawUtf8('GET /ws/v1 HTTP/1.1'), R2) = 1, 'запрос: путь с чертой испорчен');
  ChiClaim(Pos(RawUtf8('GET /ws/v1 HTTP/1.1'), R3) = 1, 'запрос: путь без черты не дополнен');
  ChiClaim(R2 = R3, 'запрос: две дороги дали разный запрос');
  ChiBranch(IdShake, 'path-three-ways');

  var R4 := BuildRequest('/ws', 'ex.com', 'https://ex.com', WsKey, True);
  ChiClaim(Pos(RawUtf8('Origin: https://ex.com'), R4) > 0, 'запрос: источник не добавлен');
  ChiClaim(Pos(RawUtf8('permessage-deflate'), R4) > 0, 'запрос: сжатие не запрошено');
  ChiClaim(Pos(RawUtf8('Origin'), R1) = 0, 'запрос: источник добавлен без надобности');
  ChiBranch(IdShake, 'optional-headers');
  Acc := ChiMix(Acc, Length(R4));

  { ── Ответ целиком: правильный обязан пройти ── }
  Accept := MakeAccept(WsKey);
  Resp := MakeResponse(Accept, '');
  Reader := TChiShakeReader.Create;
  try
    ChiClaim(Reader.Feed(Resp), 'ответ: конец заголовков не найден');
    ChiClaim(Reader.Check(WsKey) = srOk, 'ответ: правильный ответ отвергнут');
    ChiBranch(IdShake, 'accepts-valid');
    Acc := ChiMix(Acc, Reader.Rest);
  finally
    FreeAndNil(Reader);
  end;

  { ── Тот же ответ, приходящий кусками: где бы ни лёг разрез ── }
  var Splits := 0;
  for var Cut := 1 to Length(Resp) - 1 do
  begin
    Reader := TChiShakeReader.Create;
    try
      var Done := Reader.Feed(Copy(Resp, 1, Cut));
      if not Done then
        Done := Reader.Feed(Copy(Resp, Cut + 1, MaxInt));
      ChiClaim(Done, 'ответ: разрез на ' + IntToStr(Cut) + ' скрыл конец заголовков');
      ChiClaim(Reader.Check(WsKey) = srOk,
        'ответ: разрез на ' + IntToStr(Cut) + ' изменил решение');
      if Reader.Reads = 2 then Inc(Splits);
    finally
      FreeAndNil(Reader);
    end;
  end;
  ChiClaim(Splits > Length(Resp) - 8, 'ответ: почти все разрезы уложились в одно чтение');
  ChiBranch(IdShake, 'split-anywhere');
  Acc := ChiMix(Acc, Splits);

  { ── Отказы: каждая проверка обязана сработать своей причиной ── }
  Reader := TChiShakeReader.Create;
  try
    Reader.Feed(RawByteString('HTTP/1.1 400 Bad Request'#13#10'X: y'#13#10#13#10));
    ChiClaim(Reader.Check(WsKey) = srNoStatus, 'ответ: чужой код состояния принят');
  finally
    FreeAndNil(Reader);
  end;
  ChiBranch(IdShake, 'refuse-status');

  Reader := TChiShakeReader.Create;
  try
    Reader.Feed(RawByteString('HTTP/1.1 101 Switching Protocols'#13#10 +
      'Upgrade: h2c'#13#10'Connection: Upgrade'#13#10#13#10));
    ChiClaim(Reader.Check(WsKey) = srNoUpgrade, 'ответ: чужое повышение принято');
  finally
    FreeAndNil(Reader);
  end;
  ChiBranch(IdShake, 'refuse-upgrade');

  Reader := TChiShakeReader.Create;
  try
    Reader.Feed(RawByteString('HTTP/1.1 101 Switching Protocols'#13#10 +
      'Upgrade: WebSocket'#13#10'Connection: keep-alive'#13#10#13#10));
    ChiClaim(Reader.Check(WsKey) = srNoConnection, 'ответ: чужая связь принята');
  finally
    FreeAndNil(Reader);
  end;
  ChiBranch(IdShake, 'refuse-connection');

  Reader := TChiShakeReader.Create;
  try
    Reader.Feed(MakeResponse(Copy(Accept, 1, 23) + 'X', ''));
    ChiClaim(Reader.Check(WsKey) = srBadAccept, 'ответ: подложный отпечаток принят');
  finally
    FreeAndNil(Reader);
  end;
  ChiBranch(IdShake, 'refuse-accept');

  Reader := TChiShakeReader.Create;
  try
    Reader.Feed(MakeResponse(Accept, 'Sec-WebSocket-Protocol: chat'#13#10));
    ChiClaim(Reader.Check(WsKey) = srUnwantedProtocol, 'ответ: непрошеный подпротокол принят');
  finally
    FreeAndNil(Reader);
  end;
  ChiBranch(IdShake, 'refuse-protocol');

  { ── Заголовки без учёта регистра: имя, значение и подстрока ── }
  Reader := TChiShakeReader.Create;
  try
    Reader.Feed(MakeResponse(Accept,
      'sec-websocket-EXTENSIONS: PerMessage-Deflate; Server_No_Context_Takeover'#13#10));
    ChiClaim(Reader.Check(WsKey) = srOk, 'расширения: ответ с иным регистром отвергнут');
    ChiClaim(Reader.NoTakeover, 'расширения: запрет переноса словаря не распознан');
    ChiClaim(Pos(RawUtf8('PerMessage'), Reader.Extensions) > 0,
      'расширения: значение сохранено не как пришло');
  finally
    FreeAndNil(Reader);
  end;
  ChiBranch(IdShake, 'case-insensitive-headers');

  Reader := TChiShakeReader.Create;
  try
    Reader.Feed(MakeResponse(Accept, 'Sec-WebSocket-Extensions: permessage-deflate'#13#10));
    ChiClaim(Reader.Check(WsKey) = srOk, 'расширения: простое сжатие отвергнуто');
    ChiClaim(not Reader.NoTakeover, 'расширения: запрет переноса выдуман из воздуха');
  finally
    FreeAndNil(Reader);
  end;
  ChiBranch(IdShake, 'deflate-without-takeover');

  { ── Проверка текста кадра: таблица законных и порченых ── }
  var Cases: TArray<RawByteString> := [
    RawByteString('plain ascii'),
    Bin([$D0,$9F,$D1,$80,$D0,$B8,$D0,$B2,$D0,$B5,$D1,$82]),  { два байта на букву }
    Bin([$E2,$82,$AC]),                                       { три байта }
    Bin([$F0,$9F,$9A,$80]),                                   { четыре байта }
    Bin([$D0]),                                               { начало без хвоста }
    Bin([$E2,$82]),                                           { три байта, оборван }
    Bin([$80,$80]),                                           { хвост без начала }
    Bin([$C0,$AF]),                                           { избыточная запись }
    Bin([$ED,$A0,$80]),                                       { суррогат }
    Bin([$F5,$80,$80,$80])                                    { за пределом }
  ];
  var Valid := 0;
  var Broken := 0;
  for var Item in Cases do
  begin
    var Live := IsValidUtf8Buffer(PUtf8Char(Pointer(Item)), Length(Item));
    var Want := OracleValidUtf8(PByte(Pointer(Item)), Length(Item));
    ChiClaim(Live = Want, 'кодировка: библиотека и правило разошлись на образце длиной ' +
      IntToStr(Length(Item)));
    if Live then Inc(Valid) else Inc(Broken);
  end;
  ChiClaim(Valid = 4, 'кодировка: законных образцов оказалось не четыре');
  ChiClaim(Broken = 6, 'кодировка: порченых образцов оказалось не шесть');
  ChiBranch(IdShake, 'utf8-table');
  Acc := ChiMix(Acc, Valid * 100 + Broken);

  { Оборванный на последнем байте текст — то, что приходит при разрезе кадра. }
  var Long: RawByteString := '';
  for var I := 1 to 40 do
    Long := Long + Bin([$D0,$9F]);
  ChiClaim(IsValidUtf8Buffer(PUtf8Char(Pointer(Long)), Length(Long)),
    'кодировка: целый длинный текст объявлен порченым');
  ChiClaim(not IsValidUtf8Buffer(PUtf8Char(Pointer(Long)), Length(Long) - 1),
    'кодировка: текст, обрезанный посреди буквы, принят');
  ChiBranch(IdShake, 'utf8-cut-mid-letter');

  { ── Имя из провода: разрез, перевод в строку и контрольная сумма ── }
  ChiCovered(IdHash);
  ChiClaim(crc32c(0, PAnsiChar('123456789'), 9) = $E3069283,
    'сумма: общепринятый пример не сошёлся');
  ChiBranch(IdHash, 'crc32c-vector');

  var Wire: RawUtf8 := 'BTCUSDT@binance';
  var Sep := Pos(RawUtf8('@'), Wire);
  ChiClaim(Sep > 0, 'имя: разделитель не найден');
  var BaseName: string := '';
  Utf8DecodeToString(PUtf8Char(Pointer(Wire)), Sep - 1, BaseName);
  ChiClaim(BaseName = 'BTCUSDT', 'имя: левая часть переведена неверно');
  ChiClaim(crc32c(0, PAnsiChar(Pointer(StringToUtf8(BaseName))), Length(BaseName)) =
           crc32c(0, PAnsiChar('BTCUSDT'), 7),
    'имя: сумма от переведённого имени не та');
  ChiBranch(IdHash, 'split-and-hash');

  { Имя с буквами вне латиницы: длина в байтах и в символах разная, и сумма
    обязана считаться по БАЙТАМ. }
  var Uni: RawUtf8 := WireBytes(Bin([$D0,$91,$D0,$A2,$D0,$A6]) + RawByteString('@ex'));
  Sep := Pos(RawUtf8('@'), Uni);
  BaseName := '';
  Utf8DecodeToString(PUtf8Char(Pointer(Uni)), Sep - 1, BaseName);
  ChiClaim(Length(BaseName) = 3, 'имя: не латиница переведена не в три буквы');
  var Back := StringToUtf8(BaseName);
  ChiClaim(Length(Back) = 6, 'имя: обратный перевод дал не шесть байт');
  ChiClaim(crc32c(0, PAnsiChar(Pointer(Back)), Length(Back)) =
           crc32c(0, PAnsiChar(Pointer(Uni)), Sep - 1),
    'имя: сумма по байтам не совпала с суммой куска провода');
  ChiBranch(IdHash, 'non-latin-name');
  Acc := ChiMix(Acc, crc32c(0, PAnsiChar(Pointer(Back)), Length(Back)));

  { ── Приведение имён и сравнение стороны сделки ── }
  ChiClaim(LowerCaseU(RawUtf8('BinanceFutures')) = 'binancefutures',
    'имена: нижний регистр неверен');
  ChiClaim(LowerCaseU(StringToUtf8('ByBit')) = 'bybit', 'имена: перевод и регистр неверны');
  ChiClaim(SameTextU(RawUtf8('Buy'), RawUtf8('buy')), 'сторона: покупка не опознана');
  ChiClaim(SameTextU(RawUtf8('SELL'), RawUtf8('sell')), 'сторона: продажа не опознана');
  ChiClaim(not SameTextU(RawUtf8('buy'), RawUtf8('sell')), 'сторона: стороны перепутаны');
  ChiBranch(IdHash, 'case-folding');

  { Нижний регистр трогает только латиницу: имена монет в проводе — латиница,
    и байты вне её обязаны доехать нетронутыми. }
  var Mixed: RawUtf8 := WireBytes(RawByteString('ABC') + Bin([$D0,$91]) + RawByteString('DEF'));
  var Lowered := LowerCaseU(Mixed);
  ChiClaim(Copy(Lowered, 1, 3) = 'abc', 'имена: латиница не приведена');
  ChiClaim(Copy(Lowered, 4, 2) = WireBytes(Bin([$D0,$91])), 'имена: не латиница испорчена');
  ChiClaim(Length(Lowered) = Length(Mixed), 'имена: длина изменилась при приведении');
  ChiBranch(IdHash, 'lowercase-keeps-bytes');

  Result := Int64(Acc and $7FFFFFFFFFFF);
end;

end.
