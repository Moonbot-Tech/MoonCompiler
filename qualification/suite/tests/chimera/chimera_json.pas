unit chimera_json;

{ Орган «разбор ответа»: продуктовая цепочка от сырого тела до полей.

  Источники: `MoonBot/Common\JsonHelpers.pas` — принятый в боте
  способ доставать поля, и разборщики движков, которые этим способом
  пользуются. Цепочка перенесена целиком, а не по кускам: сырое тело ответа →
  разбор в документ → чтение полей по именам → обход объекта с НЕИЗВЕСТНЫМИ
  ключами → спуск по вложенному пути → массив объектов → сборка своей
  структуры → перевод в строку → поиск по ней.

  Перенесено дословно по форме:

    * поля читаются по ИМЕНИ, а имена чувствительны к регистру: биржа шлёт
      `p`, `q`, `T`, и заглавная от строчной здесь отличается;
    * значение может прийти числом ЛИБО строкой — биржи шлют цены обоими
      способами, и разбор обязан взять оба;
    * отсутствующее поле оставляет переменную нетронутой, а не бросает: перед
      чтением её обнуляют, и это часть правила, а не небрежность;
    * объект с неизвестными ключами обходится по парам «имя-значение», а не
      по индексам;
    * вложенность достаётся спуском по пути, а не цепочкой проверок.

  Заменено оснасткой: сеть. Тела ответов лежат здесь константами и совпадают
  по строению с настоящими.

  Оракулы:

    1. **известные значения**: для каждого тела заранее выписано, что обязано
       получиться в каждом поле — это внешняя истина, а не «разобралось без
       ошибки»;
    2. **канонический пересбор**: из разобранной структуры собирается тело
       обратно и разбирается снова — второй разбор обязан дать то же;
    3. **независимый сканер**: простые числовые поля достаются вручную поиском
       по подстроке, без разборщика вообще. }

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch INLINEVARS}
{$endif}
{$Q-}{$R-}

interface

uses
  SysUtils, Variants, mormot.core.base, mormot.core.text,
  mormot.core.data, mormot.core.variants, chimera_body;

type
  { Одна сделка из потока биржи. }
  TChiWsTrade = record
    Id:      Int64;
    Price:   Double;
    Qty:     Double;
    Time:    Int64;
    Maker:   Boolean;
    Symbol:  RawUtf8;
  end;

  { Описание рынка из ответа о бирже. }
  TChiSymbolInfo = record
    Symbol:    RawUtf8;
    Status:    RawUtf8;
    Base:      RawUtf8;
    Quote:     RawUtf8;
    TickSize:  Double;
    StepSize:  Double;
    Filters:   Integer;
  end;

function ChiJsonRun: Int64;

implementation

const
  IdJson = 'CHI-MB-JSON-001';
  IdMor  = 'CHI-MOR-MAP-001';
  IdScan = 'CHI-MB-SCAN-001';

  { Тела ответов: строение как у настоящих, значения выписаны сюда, чтобы их
    можно было предъявить как внешнюю истину. }
  BodyTrade: RawUtf8 =
    '{"e":"aggTrade","E":1735689600123,"s":"BTCUSDT","a":1234567,' +
    '"p":"64250.15","q":"0.0035","f":100,"l":105,"T":1735689600100,' +
    '"m":true,"M":true}';

  { То же, но цены числами, а не строками: так шлёт часть бирж. }
  BodyTradeNum: RawUtf8 =
    '{"e":"aggTrade","E":1735689600123,"s":"BTCUSDT","a":1234567,' +
    '"p":64250.15,"q":0.0035,"T":1735689600100,"m":false}';

  { Вложенность и массив объектов. }
  BodyInfo: RawUtf8 =
    '{"timezone":"UTC","serverTime":1735689600000,' +
    '"rateLimits":[{"rateLimitType":"REQUEST_WEIGHT","limit":6000}],' +
    '"symbols":[' +
    '{"symbol":"BTCUSDT","status":"TRADING","baseAsset":"BTC",' +
    '"quoteAsset":"USDT","filters":[' +
    '{"filterType":"PRICE_FILTER","tickSize":"0.01000000"},' +
    '{"filterType":"LOT_SIZE","stepSize":"0.00001000"}]},' +
    '{"symbol":"ETHUSDT","status":"BREAK","baseAsset":"ETH",' +
    '"quoteAsset":"USDT","filters":[' +
    '{"filterType":"PRICE_FILTER","tickSize":"0.10000000"},' +
    '{"filterType":"LOT_SIZE","stepSize":"0.00010000"}]}]}';

  { Объект с НЕИЗВЕСТНЫМИ ключами: имена монет заранее не известны. }
  BodyBalances: RawUtf8 =
    '{"BTC":0.5,"ETH":12.25,"USDT":10000.75,"PEPE":123456789.5}';

{ ═══ Разбор ══════════════════════════════════════════════════════════════

  Значение может прийти числом или строкой — берём оба, как биржа шлёт. }

function LoadNumAny(const D: PDocVariantData; const Name: RawUtf8;
  var Value: Double): Boolean;
var
  Idx: Integer;
  S: RawUtf8;
begin
  Result := False;
  Idx := D^.GetValueIndex(Name);
  if Idx < 0 then Exit;
  { Значение может прийти строкой — берём оба вида, как шлют биржи. }
  if VarIsStr(D^.Values[Idx]) then
  begin
    S := VariantToUtf8(D^.Values[Idx]);
    Result := ToDouble(S, Value);
  end
  else
    Result := VariantToDouble(D^.Values[Idx], Value);
end;

function LoadI64Any(const D: PDocVariantData; const Name: RawUtf8;
  var Value: Int64): Boolean;
var
  Idx: Integer;
begin
  Idx := D^.GetValueIndex(Name);
  Result := (Idx >= 0) and VariantToInt64(D^.Values[Idx], Value);
end;

function ParseTrade(const Body: RawUtf8; out T: TChiWsTrade): Boolean;
var
  Doc: TDocVariantData;
  D: PDocVariantData;
begin
  T := Default(TChiWsTrade);
  Result := Doc.InitJson(Body, JSON_FAST_FLOAT);
  if not Result then Exit;
  D := @Doc;
  { Перед чтением поле обнулено — отсутствующее оставит ноль, а не мусор. }
  LoadI64Any(D, 'a', T.Id);
  LoadNumAny(D, 'p', T.Price);
  LoadNumAny(D, 'q', T.Qty);
  LoadI64Any(D, 'T', T.Time);
  VariantToBoolean(D^.Value['m'], T.Maker);
  T.Symbol := VariantToUtf8(D^.Value['s']);
end;

{ ═══ Проверка ════════════════════════════════════════════════════════════ }

{ Независимый сканер: число достаётся поиском по подстроке, без разборщика. }
function ScanNumber(const Body, Key: RawUtf8; out Value: Double): Boolean;
var
  P, Stop: Integer;
  S: RawUtf8;
begin
  Value := 0;
  Result := False;
  P := Pos(RawUtf8('"' + Key + '":'), Body);
  if P = 0 then Exit;
  Inc(P, Length(Key) + 3);
  { Кавычка вокруг числа не мешает: её просто пропускаем. }
  if (P <= Length(Body)) and (Body[P] = '"') then Inc(P);
  Stop := P;
  while (Stop <= Length(Body))
        and (AnsiChar(Body[Stop]) in ['0' .. '9', '.', '-', '+', 'e', 'E']) do
    Inc(Stop);
  S := Copy(Body, P, Stop - P);
  Result := ToDouble(S, Value);
end;


{ ═══ CHI-MB-SCAN-001: посимвольный разбор потока сделок ══════════════════ }

{ Источник: `MoonBot/ByBitParser.pas` :: FastParseTradesWS —
  разбор потока сделок ByBit в обход разборщика. Живой путь зовётся на КАЖДОЕ
  сообщение потока сделок, поэтому и написан руками.

  Перенесено дословно по форме:

    * тело опознаётся по буквам на ФИКСИРОВАННЫХ позициях, без всякого
      разбора: одиннадцатая, семнадцатая и двадцать вторая. Не совпали —
      сообщение чужое;
    * имя рынка вырезается со следующей позиции до кавычки;
    * дальше идёт автомат по символам со счётчиком вложенности фигурных
      скобок: объект внутри сделки не должен породить новую сделку;
    * поле опознаётся ОГЛЯДКОЙ НАЗАД: двоеточие, перед ним кавычка, а перед
      именем — либо кавычка (имя из одной буквы), либо буква `P` (имя из
      трёх, где важна последняя). Дальше выбор идёт по букве через одну
      назад, а одна из веток смотрит ещё на символ назад и на символ вперёд;
    * числа берутся ПРЯМО ИЗ СЕРЕДИНЫ тела по указателю, без вырезания
      подстроки: одно по указателю с кодом ошибки, другое по паре указателей
      начало-конец;
    * массив результата растёт на каждый объект, а место под следующий
      выделяется заранее. }

type
  TChiHOrder = record
    Price:     Double;
    Quantity:  Double;
    Time:      Int64;
    OrderType: Integer;   { 0 — покупка, 1 — продажа }
    FillType:  Integer;   { 1 — обычная, 2 — с улучшением цены }
  end;

  TChiHOrders = array of TChiHOrder;

function ScanTrades(const InputText: string; var Orders: TChiHOrders;
  var MName: string): Boolean;
var
  k, j, N, L: Integer;
  TT:         Int64;
  err:        Integer;
  nextTrade:  Boolean;
  NewObj:     Integer;
begin
  Result := False;

  var s := UTF8String(InputText);
  N := Length(s);
  if N < 45 then Exit;
  if not ((s[11] = 'p') and (s[17] = 'T') and (s[22] = '.')) then Exit;

  k := 23;
  j := k;
  while (k < N) and (s[k] <> '"') do Inc(k);
  MName := Copy(string(s), j, k - j);
  while (k < N) and (s[k] <> '[') do Inc(k);
  Inc(k);

  L := -1;
  SetLength(Orders, 1);
  NewObj := 0;

  repeat

    if s[k] = '{' then
    begin
      if NewObj = 0 then
      begin
        Inc(L);
        SetLength(Orders, L + 1);
        Orders[L].FillType := 1;
      end;
      Inc(NewObj);
    end;
    if s[k] = '}' then Dec(NewObj);

    if (s[k] = ':') and (s[k - 1] = '"') and ((s[k - 3] = '"') or (s[k - 3] = 'P')) and (L >= 0) then
    begin
      if s[k + 1] = ' ' then Inc(k);
      j := k + 1;
      repeat
        Inc(j);
        nextTrade := (s[j] = '}');

        if s[j] = '{' then Inc(NewObj);
        if nextTrade then Dec(NewObj);

        if j >= N then Exit;
      until (s[j] = ',') or nextTrade;

      case s[k - 2] of
        'p': Orders[L].Price := GetExtended(@s[k + 2], err);
        'v': Orders[L].Quantity := GetExtended(@s[k + 2], err);
        'S': if s[k + 2] = 'S' then Orders[L].OrderType := 1 else Orders[L].OrderType := 0;
        'T': begin TT := GetInteger(@s[k + 1], @s[j]); Orders[L].Time := TT; Result := True; end;
        'I': if (s[k - 4] = 'R') and (s[k + 1] = 't') then Orders[L].FillType := 2;
      end;
      k := j + 1;

    end;

    Inc(k);
  until (k >= N);
end;

{ Оракул: то же тело, разобранное разборщиком. Другой алгоритм, другой код,
  общего с автоматом — только исходные байты. }
function OracleTrades(const AText: RawUtf8; out AName: RawUtf8): TChiHOrders;
var
  Root: TDocVariantData;
  Arr:  PDocVariantData;
  Cnt:  Integer;
begin
  Result := nil;
  AName := '';
  { Чувствительность к регистру здесь не вкус, а необходимость: в сделке
    рядом живут поле 's' (рынок) и поле 'S' (сторона), и поиск без учёта
    регистра отдал бы имя рынка вместо стороны. }
  if not Root.InitJson(AText, JSON_FAST_FLOAT + [dvoNameCaseSensitive]) then Exit;
  AName := VariantToUtf8(Root.Value['topic']);
  Delete(AName, 1, Pos(RawUtf8('.'), AName));
  if not Root.GetAsDocVariant('data', Arr) then Exit;
  Cnt := 0;
  SetLength(Result, Arr^.Count);
  for var Item in Arr^.Objects do
  begin
    Result[Cnt].Price := GetExtended(Pointer(VariantToUtf8(Item^.Value['p'])));
    Result[Cnt].Quantity := GetExtended(Pointer(VariantToUtf8(Item^.Value['v'])));
    Result[Cnt].Time := Item^.I['T'];
    if VariantToUtf8(Item^.Value['S']) = 'Sell'
      then Result[Cnt].OrderType := 1
      else Result[Cnt].OrderType := 0;
    if (Item^.GetValueIndex('RPI') >= 0) and Item^.B['RPI']
      then Result[Cnt].FillType := 2
      else Result[Cnt].FillType := 1;
    Inc(Cnt);
  end;
  SetLength(Result, Cnt);
end;

procedure RunScanner(var Acc: UInt64);
const
  { Тела совпадают по строению с настоящим потоком сделок: опознание по
    позициям держится на слове `publicTrade`, дальше имя рынка и массив. }
  Two = '{"topic":"publicTrade.BTCUSDT","type":"snapshot","ts":1756500000000,' +
        '"data":[{"T":1756500000123,"s":"BTCUSDT","S":"Buy","v":"0.015","p":"65000.5",' +
        '"L":"PlusTick","i":"a1","BT":false},' +
        '{"T":1756500000456,"s":"BTCUSDT","S":"Sell","v":"1.25","p":"64999.25",' +
        '"L":"MinusTick","i":"a2","BT":false}]}';
  WithRpi = '{"topic":"publicTrade.ETHUSDT","type":"snapshot","ts":1756500000000,' +
        '"data":[{"T":1756500000999,"s":"ETHUSDT","S":"Buy","v":"3.5","p":"2500.75",' +
        '"RPI":true,"L":"PlusTick","i":"b1","BT":false}]}';
  Nested = '{"topic":"publicTrade.SOLUSDT","type":"snapshot","ts":1756500000000,' +
        '"data":[{"T":1756500001000,"s":"SOLUSDT","S":"Sell","v":"10","p":"150.5",' +
        '"extra":{"depth":1,"tag":"x"},"i":"c1","BT":false}]}';
  Alien = '{"topic":"orderbook.50.BTCUSDT","type":"snapshot","data":[]}';
var
  Got:   TChiHOrders;
  Want:  TChiHOrders;
  MName: string;
  WName: RawUtf8;
begin
  ChiCovered(IdScan);

  { ── Две сделки: обе стороны, цены и объёмы строками ── }
  ChiClaim(ScanTrades(Two, Got, MName), 'автомат: тело сделок не принято');
  ChiClaim(MName = 'BTCUSDT', 'автомат: имя рынка вырезано неверно');
  Want := OracleTrades(RawUtf8(Two), WName);
  ChiClaim(Length(Got) = Length(Want), 'автомат: число сделок разошлось с разборщиком');
  ChiClaim(string(WName) = MName, 'автомат: имя рынка разошлось с разборщиком');
  for var I := 0 to High(Want) do
  begin
    ChiClaim(ChiNear(Got[I].Price, Want[I].Price, 1E-9), 'автомат: цена разошлась');
    ChiClaim(ChiNear(Got[I].Quantity, Want[I].Quantity, 1E-9), 'автомат: объём разошёлся');
    ChiClaim(Got[I].Time = Want[I].Time, 'автомат: время разошлось');
    ChiClaim(Got[I].OrderType = Want[I].OrderType, 'автомат: направление разошлось');
    ChiClaim(Got[I].FillType = Want[I].FillType, 'автомат: вид исполнения разошёлся');
  end;
  ChiClaim(Got[0].OrderType <> Got[1].OrderType,
    'автомат: обе сделки одного направления — ветвь стороны проверена вхолостую');

  { Внешняя истина: значения выписаны заранее. Без неё автомат и разборщик
    сверялись бы через ОБЩИЙ разбор числа из указателя, и общая ошибка
    осталась бы незамеченной. }
  ChiClaim(Got[0].Price = 65000.5, 'автомат: цена первой сделки не та, что в теле');
  ChiClaim(Got[0].Quantity = 0.015, 'автомат: объём первой сделки не тот');
  ChiClaim(Got[0].Time = 1756500000123, 'автомат: время первой сделки не то');
  ChiClaim(Got[0].OrderType = 0, 'автомат: первая сделка не покупка');
  ChiClaim(Got[1].Price = 64999.25, 'автомат: цена второй сделки не та');
  ChiClaim(Got[1].Quantity = 1.25, 'автомат: объём второй сделки не тот');
  ChiClaim(Got[1].Time = 1756500000456, 'автомат: время второй сделки не то');
  ChiClaim(Got[1].OrderType = 1, 'автомат: вторая сделка не продажа');
  ChiBranch(IdScan, 'known-values');
  ChiBranch(IdScan, 'two-trades-both-sides');
  Acc := ChiMix(Acc, Length(Got));

  { ── Улучшение цены: ветвь с оглядкой на два символа назад и один вперёд ── }
  ChiClaim(ScanTrades(WithRpi, Got, MName), 'автомат: тело с улучшением не принято');
  ChiClaim(MName = 'ETHUSDT', 'автомат: имя рынка второго тела неверно');
  Want := OracleTrades(RawUtf8(WithRpi), WName);
  ChiClaim(Length(Got) = 1, 'автомат: сделок не одна');
  ChiClaim(Got[0].FillType = 2, 'автомат: улучшение цены не распознано');
  ChiClaim(Got[0].FillType = Want[0].FillType, 'автомат: вид исполнения разошёлся с разборщиком');
  ChiClaim(ChiNear(Got[0].Price, Want[0].Price, 1E-9), 'автомат: цена сделки с улучшением разошлась');
  ChiBranch(IdScan, 'price-improvement');

  { ── Вложенный объект внутри сделки не имеет права породить новую ── }
  ChiClaim(ScanTrades(Nested, Got, MName), 'автомат: тело с вложенным объектом не принято');
  Want := OracleTrades(RawUtf8(Nested), WName);
  ChiClaim(Length(Got) = 1, 'автомат: вложенный объект посчитан за сделку');
  ChiClaim(Length(Want) = 1, 'автомат: разборщик тоже насчитал лишнее');
  ChiClaim(ChiNear(Got[0].Quantity, Want[0].Quantity, 1E-9), 'автомат: объём при вложенности разошёлся');
  ChiClaim(Got[0].OrderType = 1, 'автомат: направление при вложенности неверно');
  ChiBranch(IdScan, 'nested-object');
  Acc := ChiMix(Acc, Got[0].Time);

  { ── Чужое тело и короткое тело отбиваются опознанием по позициям ── }
  ChiClaim(not ScanTrades(Alien, Got, MName), 'автомат: чужое тело принято за сделки');
  ChiBranch(IdScan, 'alien-body');
  ChiClaim(not ScanTrades('{"topic":"publicTrade.X"}', Got, MName),
    'автомат: короткое тело принято');
  ChiBranch(IdScan, 'too-short');
end;

function ChiJsonRun: Int64;
var
  T: TChiWsTrade;
  Doc, Sub: TDocVariantData;
  D, Sym, Filt: PDocVariantData;
  Acc: UInt64;
  I, Found, Unknown: Integer;
  Infos: array of TChiSymbolInfo;
  Info: TChiSymbolInfo;
  V: Variant;
  Num, Scanned: Double;
  Text, Rebuilt: RawUtf8;
  Total: Double;
  Ok: Boolean;
  E: TDocVariantFields;
begin
  ChiCovered(IdJson);
  ChiCovered(IdMor);
  Acc := ChiOffset;

  { ── Сделка: цены строками ── }
  ChiClaim(ParseTrade(BodyTrade, T), 'разбор: тело сделки не разобралось');
  ChiClaim(T.Id = 1234567, 'разбор: номер сделки не тот');
  ChiClaim(Abs(T.Price - 64250.15) < 1E-9, 'разбор: цена не та');
  ChiClaim(Abs(T.Qty - 0.0035) < 1E-12, 'разбор: количество не то');
  ChiClaim(T.Time = 1735689600100, 'разбор: время не то');
  ChiClaim(T.Maker, 'разбор: признак не тот');
  ChiClaim(T.Symbol = 'BTCUSDT', 'разбор: имя рынка не то');
  ChiBranch(IdJson, 'price-as-string');
  Acc := ChiMix(Acc, T.Id);

  { ── То же тело, но цены числами ── }
  ChiClaim(ParseTrade(BodyTradeNum, T), 'разбор: числовое тело не разобралось');
  ChiClaim(Abs(T.Price - 64250.15) < 1E-9, 'разбор: числовая цена не та');
  ChiClaim(not T.Maker, 'разбор: числовой признак не тот');
  ChiBranch(IdJson, 'price-as-number');

  { Независимый сканер обязан дать то же число. }
  ChiClaim(ScanNumber(BodyTrade, 'p', Scanned), 'разбор: сканер не нашёл цену');
  ChiClaim(Abs(Scanned - T.Price) < 1E-9,
    'разбор: сканер и разборщик разошлись');
  ChiBranch(IdJson, 'independent-scan');

  { ── Регистр имени ──

    Набор разбора по умолчанию ищет поле БЕЗ учёта регистра: `q` найдётся по
    запросу `Q`. Для биржевого провода это опасно — там `p` и `P` бывают
    разными полями, — и чувствительность включается отдельным признаком.
    Здесь предъявлены оба поведения: сначала как есть, потом с признаком. }
  ChiClaim(ParseTrade(BodyTrade, T), 'разбор: повторный разбор не прошёл');
  Doc.Clear;
  Doc.InitJson(BodyTrade, JSON_FAST_FLOAT);
  D := @Doc;
  ChiClaim(LoadI64Any(D, 'T', T.Time), 'разбор: заглавное поле не найдено');
  Num := -1;
  ChiClaim(LoadNumAny(D, 'Q', Num),
    'разбор: без признака регистра чужой регистр не нашёлся');
  ChiClaim(Abs(Num - 0.0035) < 1E-12,
    'разбор: нечувствительный поиск дал не то значение');
  ChiBranch(IdJson, 'case-insensitive-default');

  Doc.Clear;
  Doc.InitJson(BodyTrade, JSON_FAST_FLOAT + [dvoNameCaseSensitive]);
  D := @Doc;
  Num := -1;
  ChiClaim(not LoadNumAny(D, 'Q', Num),
    'разбор: с признаком регистра чужой регистр всё равно нашёлся');
  ChiClaim(Num = -1, 'разбор: неудачное чтение тронуло переменную');
  ChiClaim(LoadNumAny(D, 'q', Num), 'разбор: своё поле не нашлось');
  ChiClaim(Abs(Num - 0.0035) < 1E-12, 'разбор: своё поле дало не то');
  ChiBranch(IdJson, 'case-sensitive');

  { Отсутствующее поле оставляет переменную как была. }
  Num := 12345;
  ChiClaim(not LoadNumAny(D, 'нетТакого', Num), 'разбор: нашлось лишнее');
  ChiClaim(Num = 12345, 'разбор: отсутствующее поле стёрло значение');
  ChiBranch(IdJson, 'missing-field');

  { ── Объект с неизвестными ключами: обход по парам ── }
  Doc.Clear;
  ChiClaim(Doc.InitJson(BodyBalances, JSON_FAST_FLOAT),
    'разбор: тело балансов не разобралось');
  Unknown := 0;
  Total := 0;
  for I := 0 to Doc.Count - 1 do
  begin
    Inc(Unknown);
    Total := Total + VariantToDoubleDef(Doc.Values[I], 0);
  end;
  ChiClaim(Unknown = 4, 'разбор: неизвестных ключей не четыре');
  ChiClaim(Abs(Total - (0.5 + 12.25 + 10000.75 + 123456789.5)) < 1E-3,
    'разбор: сумма по неизвестным ключам не та');
  ChiClaim(Doc.Names[0] = 'BTC', 'разбор: первый ключ не тот');
  ChiBranch(IdJson, 'unknown-keys');
  Acc := ChiMix(Acc, Unknown);

  { ── Вложенность и массив объектов ── }
  Doc.Clear;
  ChiClaim(Doc.InitJson(BodyInfo, JSON_FAST_FLOAT),
    'разбор: тело описания не разобралось');
  D := @Doc;

  { Спуск по пути вместо цепочки проверок. }
  V := D^.GetValueByPath('rateLimits');
  ChiClaim(not VarIsEmpty(V), 'разбор: путь к ограничениям не найден');

  Sym := D^.A['symbols'];
  ChiClaim(Sym <> nil, 'разбор: массив рынков не найден');
  ChiClaim(Sym^.Count = 2, 'разбор: рынков не два');

  SetLength(Infos, Sym^.Count);
  Found := 0;
  for I := 0 to Sym^.Count - 1 do
  begin
    Info := Default(TChiSymbolInfo);
    Sub := _Safe(Sym^.Values[I])^;
    Info.Symbol := VariantToUtf8(Sub.Value['symbol']);
    Info.Status := VariantToUtf8(Sub.Value['status']);
    Info.Base := VariantToUtf8(Sub.Value['baseAsset']);
    Info.Quote := VariantToUtf8(Sub.Value['quoteAsset']);
    Filt := Sub.A['filters'];
    if Filt <> nil then
    begin
      Info.Filters := Filt^.Count;
      { Фильтры различаются полем вида, а не порядком: искать надо по виду. }
      for var J := 0 to Filt^.Count - 1 do
      begin
        var F := _Safe(Filt^.Values[J]);
        if VariantToUtf8(F^.Value['filterType']) = 'PRICE_FILTER' then
          LoadNumAny(F, 'tickSize', Info.TickSize)
        else if VariantToUtf8(F^.Value['filterType']) = 'LOT_SIZE' then
          LoadNumAny(F, 'stepSize', Info.StepSize);
      end;
    end;
    Infos[I] := Info;
    Inc(Found);
  end;

  ChiClaim(Found = 2, 'разбор: собрано не два рынка');
  ChiClaim(Infos[0].Symbol = 'BTCUSDT', 'разбор: первый рынок не тот');
  ChiClaim(Infos[0].Status = 'TRADING', 'разбор: состояние первого не то');
  ChiClaim(Abs(Infos[0].TickSize - 0.01) < 1E-12, 'разбор: шаг цены не тот');
  ChiClaim(Abs(Infos[0].StepSize - 0.00001) < 1E-12,
    'разбор: шаг количества не тот');
  ChiClaim(Infos[1].Symbol = 'ETHUSDT', 'разбор: второй рынок не тот');
  ChiClaim(Infos[1].Status = 'BREAK', 'разбор: состояние второго не то');
  ChiClaim(Abs(Infos[1].TickSize - 0.1) < 1E-12,
    'разбор: шаг цены второго не тот');
  ChiClaim(Infos[0].Filters = 2, 'разбор: фильтров не два');
  ChiBranch(IdJson, 'nested-array');
  ChiBranch(IdJson, 'filter-by-kind');
  Acc := ChiMix(Acc, Found);
  Acc := ChiMix(Acc, PInt64(@Infos[0].TickSize)^);

  { ── Канонический пересбор: обратно в тело и снова разобрать ── }
  Rebuilt := Doc.ToJson;
  ChiClaim(Length(Rebuilt) > 0, 'разбор: пересборка дала пустое тело');
  Sub.Clear;
  ChiClaim(Sub.InitJson(Rebuilt, JSON_FAST_FLOAT),
    'разбор: пересобранное тело не разобралось');
  Sym := Sub.A['symbols'];
  ChiClaim(Sym <> nil, 'разбор: в пересобранном нет рынков');
  ChiClaim(Sym^.Count = 2, 'разбор: в пересобранном рынков не два');
  ChiClaim(VariantToUtf8(_Safe(Sym^.Values[0])^.Value['symbol'])
           = 'BTCUSDT', 'разбор: пересборка потеряла имя рынка');
  ChiBranch(IdJson, 'rebuild-roundtrip');
  Acc := ChiMix(Acc, Length(Rebuilt));

  { ── Перевод в строку и поиск по ней — конец продуктовой цепочки ── }
  Text := VariantToUtf8(Doc.Value['timezone']);
  ChiClaim(Text = 'UTC', 'разбор: строковое поле не то');
  ChiClaim(Pos(RawUtf8('BTCUSDT'), Rebuilt) > 0,
    'разбор: поиск по пересобранному телу не нашёл рынок');
  ChiBranch(IdJson, 'to-string-search');

  { ── Битое тело обязано быть отвергнуто, а не разобрано наполовину ── }
  Sub.Clear;
  Ok := Sub.InitJson(RawUtf8('{"a":1,"b":'), JSON_FAST_FLOAT);
  ChiClaim(not Ok, 'разбор: обрезанное тело принято');
  Sub.Clear;
  Ok := Sub.InitJson(RawUtf8('не json вовсе'), JSON_FAST_FLOAT);
  ChiClaim(not Ok, 'разбор: мусор принят за тело');
  ChiBranch(IdJson, 'reject-broken');

  { Пустой объект и пустой массив — законные тела. }
  Sub.Clear;
  ChiClaim(Sub.InitJson(RawUtf8('{}'), JSON_FAST_FLOAT),
    'разбор: пустой объект отвергнут');
  ChiClaim(Sub.Count = 0, 'разбор: пустой объект не пуст');
  ChiBranch(IdJson, 'empty-object');
  ChiBranch(IdMor, 'doc-variant-chain');

  { ── Спуск по вложенному пути одной строкой ── }
  Sub.Clear;
  ChiClaim(Sub.InitJson(RawUtf8('{"code":"0","data":{"response":{"payload":' +
    '{"data":{"px":"1234.5","sz":"2"}}}}}'), JSON_FAST_FLOAT),
    'разбор: тело со вложенным путём не принято');
  var Deep: PDocVariantData;
  ChiClaim(Sub.GetDocVariantByPath('data.response.payload.data', Deep),
    'разбор: спуск по пути не нашёл вложенное');
  ChiClaim(VariantToUtf8(Deep^.Value['px']) = '1234.5',
    'разбор: спуск по пути привёл не туда');
  ChiClaim(not Sub.GetDocVariantByPath('data.response.missing.data', Deep),
    'разбор: спуск по несуществующему пути удался');
  ChiBranch(IdJson, 'by-path');
  ChiBranch(IdMor, 'path-descent');

  { ── Набор настроек решает ТИП числа: с плавающей точкой против денежного.
    Денежный тип держит четыре знака после запятой, и цена монеты с пятью
    знаками на нём теряется. Движки арбитража поэтому и просят плавающий. ── }
  Sub.Clear;
  Sub.InitJson(RawUtf8('{"px":0.000012345}'), JSON_FAST);
  var AsMoney: Double := Sub.D['px'];
  Sub.Clear;
  Sub.InitJson(RawUtf8('{"px":0.000012345}'), JSON_FAST_FLOAT);
  var AsFloat: Double := Sub.D['px'];
  ChiClaim(ChiNear(AsFloat, 0.000012345, 1E-15),
    'разбор: плавающий набор потерял точность цены');
  ChiClaim(not ChiNear(AsMoney, 0.000012345, 1E-9),
    'разбор: денежный набор внезапно сохранил точность — набор не различается');
  ChiBranch(IdJson, 'float-vs-money');
  ChiBranch(IdMor, 'options-decide-number-type');

  RunScanner(Acc);

  Result := Int64(Acc and $7FFFFFFFFFFF);
end;

end.
