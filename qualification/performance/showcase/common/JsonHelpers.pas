unit JsonHelpers;

{$INLINE ON}
{$OPTIMIZATION ON}

// ============================================================================
// JsonHelpers — чтение TDocVariantData и разбор крупных JSON через TJsonDocument.
//
// HOT PATH. Модуль разбирает рыночные WS-потоки (трейды, стаканы, ликвидации,
// тикеры) — тысячи сообщений в секунду. Ставка на скорость: один поиск VarData
// на поле, прямой доступ без аллокаций, ×9 быстрее System.JSON. Где скорость
// спорит с красотой — выбираем скорость (поэтому single-overload LoadNum дублирует
// разбор, а не делегирует double-версии — чтобы не платить конверсией на hot path).
//
// --- РЕКОМЕНДУЕМЫЙ СТИЛЬ (чистый, 76.8 ns на 7 полей) ---
//
//   uses mormot.core.variants, JsonHelpers;
//
//   Методы TDocVariantFastHelper СОЗНАТЕЛЬНО без inline. Не возвращать без замера: бенч
//   (BinanceTradeParseBench, полный разбор aggTrade) дал инлайну ~20 ns из
//   ~1250 ns на сообщение (1.6%, меньше шума прогонов) — call overhead
//   ~2 ns/поле, доминирует _Json. Цена инлайна: +237 байт кода на КАЖДЫЙ
//   колл-сайт (~+37 КБ на весь бот, давит I-cache) и mormot.core.unicode
//   (+text для RawUtf8-LoadStr) в uses каждого вызывателя строго ДО
//   SysUtils — иначе UpperCase/LowerCase/TrimLeft/TrimRight(RawUtf8) без
//   overload перехватывают резолв строковых вызовов (детект перехватов:
//   src\Test\shadow_scan.py).
//
//   function ParseAggTrade(const V: Variant): TParsedTrade;
//   var D: PDocVariantData;
//   begin
//     Result := Default(TParsedTrade);
//     if not _Safe(V, D) then Exit;
//     D.LoadI64 ('a', Result.AggregateTradeId);
//     D.LoadNum ('p', Result.Price);
//     D.LoadBool('m', Result.IsBuyerMaker);
//     ...
//   end;
//
//
// --- МАКСИМАЛЬНАЯ СКОРОСТЬ (74.2 ns, на 3.5% быстрее, но уродливо) ---
//
// Если профайлер покажет что парсинг — горячая точка (он не покажет),
// можно руками раскрыть GetVarData в caller:
//
//   function ParseAggTrade(const V: Variant): TParsedTrade;
//   var
//     D: PDocVariantData;
//     pv: PVarData;
//   begin
//     Result := Default(TParsedTrade);
//     if not _Safe(V, D) then Exit;
//     pv := D.GetVarData('a'); if pv <> nil then VariantToInt64(PVariant(pv)^, Result.AggregateTradeId);
//     pv := D.GetVarData('f'); if pv <> nil then VariantToInt64(PVariant(pv)^, Result.TradeIdFirst);
//     pv := D.GetVarData('m'); if pv <> nil then VariantToBoolean(PVariant(pv)^, Result.IsBuyerMaker);
//     ...
//   end;
//
// Экономия 2.6 ns на запись ≈ 2.6 мкс/сек CPU при 1000 trade/s.
// Физически неизмеримо. Не используй это кроме как в бенчмарках.
//
// ============================================================================
// БЕЗОПАСНОСТЬ:
//
// - Поля нет / поле null / неподходящий variant-type → aValue не меняется
//   (исключение: LoadNum на битой varString пишет 0 через GetExtended; если это
//   важно, используй TryLoadNum).
//   Всегда делай Result := Default(...) перед Load*, тогда отсутствующее
//   поле == 0/false/пусто без лишних if'ов. Старое "If V.p <> NULL" не нужно.
//
// - ПАРНЫЕ МЕТОДЫ:
//     LoadNum / LoadI64 / LoadBool / LoadStr  = optional-поля. Нет поля/null/не тот тип
//       оставляет default; boolean не нужен, код короче.
//     TryLoadNum / TryLoadI64 / TryLoadBool / TryLoadStr = required-поля. Возвращают true только
//       если поле реально есть, не null и прошло проверку значения; используй их
//       для guard-веток типа "без symbol нельзя продолжать" или "без цены нельзя
//       обновлять Bid/Ask".
//
// - Если нужно РАЗЛИЧАТЬ "поля нет" vs "поле есть и == 0" — используй HasValue.
//
// - Имена полей ищутся CASE-SENSITIVE (dvoNameCaseSensitive в JSON_OPTIONS_FASTMEM/FASTCS):
//   ключ в Load*/SameText/HasValue писать байт-в-байт как на проводе ('avgPriceMins',
//   не 'AvgPriceMins'). Промах по регистру молча даёт "поля нет" (default), не ошибку.
//   Это же касается late-binding (x.field) — реальный случай: exchangeInfo Binance,
//   y^.AvgPriceMins годами молча возвращал NULL.
//
// - ⚠ МИНА: case-sensitivity — свойство ПАРСА, не хелперов. _JsonFast (mormot-дефолт) парсит БЕЗ
//   dvoNameCaseSensitive → те же Load*/late-binding над таким документом ищут БЕЗ регистра и берут
//   ПЕРВОЕ по порядку payload'а совпавшее поле. На биржевых JSON с однобуквенными парами это ПОДМЕНА
//   значения, а не «поля нет»: Binance kline несёт l/L, v/V, q/Q, t/T — LoadNum('l') над _JsonFast-доком
//   отдал "L" (lastTradeId, в payload раньше "l") вместо low → MinP=миллиарды, текущий бар молча прятался
//   Y-фильтром чарта (прод-баг 2026-07-09; выжившие поля выживали только удачным порядком). Порядок полей —
//   не контракт. Входной wire-JSON парсить ТОЛЬКО GetObjFromJSON / _Json(JSON_OPTIONS_FASTCS/FASTMEM);
//   _JsonFast на данных с провода запрещён.
//
// - Все variant-типы обработаны без GPF, включая varStringByRef и
//   varVariantByRef (разворачиваются автоматически).
//
// - ×9 быстрее vs Delphi System.JSON (см. test\BenchParse.dpr):
//     AggTrade  (11 полей):  Delphi 6905 ns  vs  mormot 760 ns
//     OrderBook (10+10 lvl): Delphi 33720 ns vs  mormot 3740 ns
// ============================================================================
//
// ============================================================================
// СИНТАКСИС  ::  D.X  vs  D^.X
// ============================================================================
//
// Методы (Load*, HasValue, SameText, GetVarData, GetAsArray, GetAsDocVariant,
// GetDocVariantByPath, Fields и т.д.) можно вызывать как D.LoadX(...) или
// D^.LoadX(...) — оба варианта работают независимо от того, объявлен D как
// TDocVariantData (значение) или PDocVariantData (указатель). Delphi делает
// implicit dereference для record-методов через указатель.
//
// Свойства (S[], U[], I[], B[], D[], Count, Items, Objects, Values[]) — для
// PDocVariantData ОБЯЗАТЕЛЬНО через D^.S['key'], D^.Count, arr^.Objects.
// Implicit dereference на свойства не распространяется.
//
// ============================================================================
// ПРОВЕРКА NULL  ::  старое  v.field <> NULL   →   новое
// ============================================================================
//
// Старый стиль (HyperParser):
//   If (obj.data <> NULL) and (obj.data.markPx <> NULL)
//      and ToDouble(obj.data.markPx, m.Mark) then ...
//   ↑ каждое .field — это VarDispInvoke с поиском по строке. Медленно + кидает
//     исключения если по пути что-то не объект.
//
// Новый стиль:
//   var D: PDocVariantData;
//   m := Default(TMarket);              // ← обнулили всё разом
//   if not _Safe(V, D) then Exit;       // V вообще не document? — выходим
//   D.LoadNum('markPx', m.Mark);        // нет поля / null → m.Mark остаётся 0
//
//   ВАЖНО: Default + Load == встроенная защита от null. Никаких if'ов.
//          Отсутствующее поле всегда == 0/false/пусто, и это правильное
//          значение в 99% случаев.
//
// HasValue нужен ТОЛЬКО когда 0 — это валидное значение, и его надо отличить
// от "поля нет/null":
//   If D.HasValue('funding') then begin
//     D.LoadNum('funding', m.FundingRate);
//     m.HasFunding := true;
//   end;
//   ↑ это редкий случай. Обычно Default+Load достаточно.
//
// ============================================================================
// ГЛУБОКО ВЛОЖЕННЫЙ ОБЪЕКТ  ::  data.response.payload.data.markPx
// ============================================================================
//
// Старое (HyperParser):
//   If (LastObj.data <> NULL)
//      and (LastObj.data.response.payload.data <> NULL)
//      and (LastObj.data.response.payload.data.markPx <> NULL) then
//     ToDouble(LastObj.data.response.payload.data.markPx, m.Mark);
//   ↑ 5 уровней × VarDispInvoke × поиск по имени = медленно, плюс при null
//     посередине — Variant exception.
//
// Новое — два эквивалентных способа (по бенчу скорость одинаковая, ~1125 ns):
//
// Способ A — GetDocVariantByPath с дотированной нотацией (короче):
//   var inner: PDocVariantData;
//   if not _Safe(V, D) then Exit;
//   if D.GetDocVariantByPath('data.response.payload.data', inner) then
//   begin
//     inner.LoadNum('markPx',      m.Mark);
//     inner.LoadNum('funding',     m.Funding);
//     inner.LoadI64('updatedTime', m.LastUpd);
//   end;
//
// Способ B — ручные шаги через GetAsDocVariant (контролируешь каждый уровень,
//            удобно если нужно лочить ошибку именно на конкретном уровне):
//   var r, p, d2: PDocVariantData;
//   if not _Safe(V, D)              then Exit;
//   if not D.GetAsDocVariant ('data',     r)  then Exit;
//   if not r.GetAsDocVariant ('response', p)  then Exit;
//   if not p.GetAsDocVariant ('payload',  d2) then Exit;
//   if not d2.GetAsDocVariant('data',     r)  then Exit;
//   r.LoadNum('markPx', m.Mark);
//
// Оба способа возвращают false если ЛЮБОЙ уровень не существует или не объект.
// Никаких эксепшенов, никакого late binding. Скорость одинаковая.
//
// ============================================================================
// МАССИВЫ  ::  for ... in ...
// ============================================================================
//
// У TDocVariantData есть несколько энумераторов. Выбирай по типу содержимого:
//
// ВАЖНО: mORMot GetAsArray возвращает false для пустого массива [] (Count = 0).
// Если поле обязано быть массивом, но [] является валидным значением, используй
// GetAsArrayOrEmpty — он различает пустой массив и отсутствующее/битое поле:
//
//   if D.GetAsArrayOrEmpty('balances', arr) then
//     for item in arr^.Objects do ...;
//
// ----------------------------------------------------------------------------
// Items  →  PVariant         универсальный, для массивов СКАЛЯРОВ
// ----------------------------------------------------------------------------
//   var v: PVariant;
//   for v in arr^.Items do
//     Sum := Sum + double(v^);
//
//   - Возвращает PVariant на каждый элемент Values[].
//   - НЕ разворачивает byref, НЕ фильтрует ничего.
//   - Используй только когда элементы — простые значения (числа, строки).
//
// ----------------------------------------------------------------------------
// Objects  →  PDocVariantData    ⭐ ОСНОВНОЙ для массивов ОБЪЕКТОВ/массивов
// ----------------------------------------------------------------------------
//   var item: PDocVariantData;
//   if D.GetAsArray('balances', arr) then
//     for item in arr^.Objects do
//     begin
//       item.LoadNum('total', A.Total);
//       item.LoadNum('hold',  A.Hold);
//       FList.Add(A);
//     end;
//
//   ⭐ ПОЧЕМУ Objects лучше Items+_Safe для массива объектов:
//      1. Возвращает СРАЗУ PDocVariantData — никакого _Safe(x^) в цикле
//      2. Автоматически разворачивает varVariantByRef (сделано в MoveNext)
//      3. ПРОПУСКАЕТ элементы которые не TDocVariantData (мусор/null/числа)
//      4. Один лукап на элемент вместо двух
//
//   Тонкость: счётчик собранных элементов считаешь руками (i := 0; inc(i)),
//   потому что Objects может пропустить итерации:
//     i := 0;
//     SetLength(Result.Items, arr^.Count);   // верхняя граница
//     for item in arr^.Objects do begin
//       ParseOne(item^, Result.Items[i]);
//       inc(i);
//     end;
//     SetLength(Result.Items, i);            // обрезаем до реального
//
// Objects работает и для МАССИВА МАССИВОВ (orderbook [["50000","0.5"],...])
// потому что вложенный массив = тоже TDocVariantData (с VKind=dvArray):
//
//   if D.GetAsArray('bids', arr) then
//     for lvl in arr^.Objects do
//       if lvl^.Count >= 2 then begin
//         Bids[i].Price := GetExtended(pointer(VariantToUtf8(lvl^.Values[0])));
//         Bids[i].Qty   := GetExtended(pointer(VariantToUtf8(lvl^.Values[1])));
//         inc(i);
//       end;
//
// ----------------------------------------------------------------------------
// Fields  →  TDocVariantFields(Name, Value)   для ОБЪЕКТА (не массива)
// ----------------------------------------------------------------------------
//   for e in D.Fields do
//     Writeln(e.Name^, '=', e.Value^);
//
//   Когда нужно пройти ВСЕ поля объекта где имена заранее не известны
//   (например {"BTC":12345, "ETH":234, "SOL":56}).
//
// ----------------------------------------------------------------------------
// FieldNames  →  PRawUtf8     только имена полей объекта
// FieldValues →  PVariant     только значения полей объекта (= Items)
// ----------------------------------------------------------------------------
// ============================================================================
//
// ============================================================================
// СТРОКИ  ::  как вытаскивать string / RawUtf8
// ============================================================================
//
// ИМЕНОВАННЫЕ ПОЛЯ — единообразный стиль через LoadStr (аналог LoadI64/Num/Bool):
//
//   Result := Default(TAsset);          // все строки пустые, числа нули
//   D.LoadStr ('coin',   A.Currency);   // string  (UnicodeString)
//   D.LoadStr ('symbol', A.SymbolRaw);  // RawUtf8  (тот же метод, overload по типу)
//
//     ↑ нет поля / null → aValue не трогается. Никаких if'ов.
//     ↑ overload по типу var-параметра: string vs RawUtf8 выбирается компилятором.
//     ↑ если строка обязательна и пустая строка невалидна — используй TryLoadStr.
//
// ЕСЛИ ТЕБЕ НУЖНА АЛЬТЕРНАТИВА (прямой доступ, свойства TDocVariantData):
//
//   s := D^.S['coin'];                  // → string
//   u := D^.U['coin'];                  // → RawUtf8
//
//     ↑ всегда перезаписывают (нет поля / null → пустая строка).
//       Подходит только когда defaults тебе не нужны.
//
// РАЗЛИЧАТЬ "ПОЛЯ НЕТ" ОТ "ПОЛЕ ЕСТЬ, НО ПУСТО":
//
//   if D^.GetAsRawUtf8('coin', u) then ...
//     ↑ редкий кейс. Обычно LoadStr + Default достаточно.
//
// ИЗ МАССИВА / variant без имени (есть только v^):
//
//   VariantToString(v^, s);             // → string
//   u := VariantToUtf8(v^);             // → RawUtf8 (самый быстрый)
//
// ----------------------------------------------------------------------------
// СРАВНЕНИЕ СТРОКИ — SameText
// ----------------------------------------------------------------------------
//
// Вместо аллокации промежуточной переменной:
//
//   if D.SameText('channel', 'trades') then ...
//   if D.SameText('type',    'userRole') then ...
//   if D.SameText('coin',    cfg.Currency) then ...     // string переменная ok
//
//     ↑ нет поля / null → false. Сравнение ASCII case-insensitive
//       (через VariantEquals + PropNameEquals). Идеально для крипто-кодов
//       и названий API-каналов. Для Unicode case-compare (кириллица) —
//       используй LoadStr + System.SysUtils.SameText.
//
// ----------------------------------------------------------------------------
// ВАЖНО: НЕ ИСПОЛЬЗУЙ VarToStr / VarToStrDef
// ----------------------------------------------------------------------------
//
// VarToStr(v) это RTL (System.Variants) — идёт через variant dispatcher (COM).
// Работает корректно (UTF-8 не ломает), но медленнее mormot-функций:
//
//   Массив 20 строк (см. test\BenchParse.dpr):
//     VarToStr(v^)        : 1800 ns/call  (baseline)
//     VariantToString(v^) : 1560 ns/call  x1.15
//     VariantToUtf8(v^)   : 1140 ns/call  x1.58
//
// Нет ни одной причины использовать VarToStr в mormot-коде — просто замена
// функции даёт +14..58% бесплатно.
//
// Также НЕ пиши Utf8ToString(D^.U['key']) — это двойной конверт, эквивалент
// D^.S['key'] в один вызов.
// ============================================================================

interface

uses
  mormot.core.base,
  mormot.core.text,      // VariantToUtf8
  mormot.core.unicode,   // StringToUtf8
  mormot.core.variants, mormot.core.data, mormot.core.json, mormot.core.os, System.SysUtils, System.Variants,
  System.SyncObjs;

type
  TDocVariantFastHelper = record helper for TDocVariantData
    /// возвращает массив, включая валидный пустой []; отсутствующее поле или не-массив → false
    function GetAsArrayOrEmpty(const aName: RawUtf8; out aArray: PDocVariantData): boolean;
    /// Int64 — для varInt64/varInteger/varBoolean + byref
    procedure LoadI64 (const aName: RawUtf8; var aValue: Int64);
    /// Int64 для полей где API биржи шлёт целое число строкой
    /// ("ts":"1778101214576"). BitGet/OKX trade timestamps. Обычный LoadI64
    /// на такой varString вернёт 0.
    procedure LoadI64Str(const aName: RawUtf8; var aValue: Int64);
    /// Boolean — для varBoolean + byref
    procedure LoadBool(const aName: RawUtf8; var aValue: boolean);
    /// Double — для всех числовых типов + varString ("0.01633000") + byref
    procedure LoadNum (const aName: RawUtf8; var aValue: double);  overload;
    /// Single — то же, но прямо в single-поле (TTrade.Price/Qty и т.п.); делегирует double
    procedure LoadNum (const aName: RawUtf8; var aValue: single);  overload;

    /// как LoadNum, но ВОЗВРАЩАЕТ успех (замена RTL TryStrToFloat для
    /// required-numeric веток): true только если поле есть, не null и
    /// сконвертировалось в число — число-вариант, либо varString с валидным
    /// dot-инвариантным парсом (включая "0"). Мусор / нет поля / null → false,
    /// aValue не трогается. ⚠ отличие от LoadNum: на битой строке даёт false,
    /// а не молчаливый 0.
    function TryLoadNum(const aName: RawUtf8; var aValue: double): boolean;  overload;
    /// single-версия TryLoadNum; делегирует double (это не hot-path трейдов).
    function TryLoadNum(const aName: RawUtf8; var aValue: single): boolean;  overload;
    /// Int64-аналог TryLoadNum (замена RTL TryStrToInt64): true только если поле
    /// есть, не null и это целое — int-вариант или varString с валидным целым.
    /// Float / мусор / нет поля / null → false, aValue не трогается.
    function TryLoadI64(const aName: RawUtf8; var aValue: Int64): boolean;
    /// Boolean-аналог TryLoadNum: true только если поле есть, не null и это JSON bool.
    /// Строки/числа не принимаем: для биржевых bool-полей это битый контракт.
    function TryLoadBool(const aName: RawUtf8; var aValue: boolean): boolean;

    /// required numeric slot из массива (например orderbook level [price,qty]).
    /// true только если индекс существует и значение сконвертировалось; мусор /
    /// короткая строка массива / null → false, aValue не трогается.
    function TryLoadSlotNum(const aIndex: integer; var aValue: double): boolean; overload;
    /// single-версия TryLoadSlotNum.
    function TryLoadSlotNum(const aIndex: integer; var aValue: single): boolean; overload;
    /// required Int64 slot из массива (например kline open-time).
    function TryLoadSlotI64(const aIndex: integer; var aValue: Int64): boolean;

    /// string (UnicodeString) — через mormot VariantToString, UTF-8 safe
    procedure LoadStr (const aName: RawUtf8; var aValue: string);  overload;
    /// RawUtf8 — без конверта в UnicodeString, самый быстрый для дальнейшего mormot-кода
    procedure LoadStr (const aName: RawUtf8; var aValue: RawUtf8); overload;
    /// required string: true только если поле есть, не null и строка не пустая.
    /// Используй для обязательных ключей типа symbol/s; пустая строка = fail.
    function TryLoadStr(const aName: RawUtf8; var aValue: string): boolean;  overload;
    /// RawUtf8-версия TryLoadStr.
    function TryLoadStr(const aName: RawUtf8; var aValue: RawUtf8): boolean; overload;

    /// true если поле есть И не null (для случаев когда 0 нужно отличать от "нет")
    function HasValue(const aName: RawUtf8): boolean;

    /// case-insensitive ASCII сравнение поля со значением (PropNameEquals).
    /// Поля нет / null → false. Идеально для крипто-кодов и названий channels.
    /// Для Unicode case-compare (кириллица и т.п.) НЕ ПОДХОДИТ — используй
    /// LoadStr + RTL SameText, если кейс реально появится.
    function SameText(const aName, aValue: RawUtf8): boolean;
  end;

// TJsonDocument: полный разбор mORMot в рабочем тексте и одном массиве узлов.
// Строки и имена в узлах ссылаются на текст; LoadStr копирует только запрошенную строку.
// Ключи case-sensitive. Get пропускает поддеревья, Items сохраняет позиции, Objects
// пропускает скаляры. ToVariant явно материализует выбранное поддерево в DOM.
//
// Parse(const Text) сохраняет исходник и владеет рабочей копией. Нестандартные опции,
// пустые имена, скалярный корень и глубина >128 используют совместимый DOM fallback.
// ParseOwned(var Text) передаёт строку документу, обнуляет Text; алиасы остаются целы,
// при них нужна копия. Без алиасов SetLength может переместить буфер ради padding.
// ParseOwned(pointer, length, capacity, options) НЕ владеет памятью: вызывающий
// гарантирует эксклюзивный изменяемый буфер с 16 дополнительными байтами до Clear.
// Owned-методы без DOM fallback: неподдерживаемый документ возвращает false.
//
// TJsonValue и перечислители заимствованы: недействительны после Clear/Parse/Free.
// Документ принадлежит одному потоку; независимые документы можно разбирать параллельно.
// Clear освобождает рабочий текст, индекс и ленивый writer. Кэш интернирования не нужен.
//
//   Doc := TJsonDocument.Create;
//   try
//     If Doc.Parse(Response) then
//       for var Item in Doc.Root.Get('result').Get('list').Objects do begin
//         Item.LoadStr('symbol', Symbol);
//         Item.TryLoadNum('lastPrice', Price); // false оставляет Price без изменения
//       end;
//   finally
//     Doc.Free;
//   end;
const
  TapeMask = $0fffffff;
  ViewOptions: TDocVariantOptions = [dvoReturnNullForUnknownProperty, dvoValueCopiedByReference,
    dvoNameCaseSensitive, dvoAllowDoubleValue];

type
  TJsonDocument = class;
  TJsonKind = (jkMissing, jkNull, jkBoolean, jkInt64, jkDouble, jkString, jkArray, jkObject);
  TJsonNode = record
  private
    FNameOffset: Integer;
    FMeta: Cardinal;
    function GetKind: TJsonKind; inline;
    procedure SetKind(Value: TJsonKind); inline;
    function GetNameLength: Integer; inline;
    procedure SetNameLength(Value: Integer); inline;
    function GetWasInteger32: Boolean; inline;
    procedure SetWasInteger32(Value: Boolean); inline;
  public
    property NameOffset: Integer read FNameOffset write FNameOffset;
    property NameLength: Integer read GetNameLength write SetNameLength;
    property Kind: TJsonKind read GetKind write SetKind;
    property WasInteger32: Boolean read GetWasInteger32 write SetWasInteger32;
    case Integer of
      0: (Offset, Len: Integer);
      1: (Number: Double);
      2: (IntegerValue: Int64);
  end;
  PJsonNode = ^TJsonNode;

  TJsonValue = record
  private
    FOwner: TJsonDocument; // compact tree; native DOM uses FParent, including fallback
    FIndex: Integer;
    FParent: PDocVariantData;
    function Node: PJsonNode; inline;
    function Dom: PVariant;
    function IsDom: Boolean; inline;
    function GetKind: TJsonKind;
    function GetCount: Integer;
    function GetName: RawUtf8;
    function GetNameString: string;
    function FindNode(const Name: RawUtf8): PJsonNode; overload;
    function FindNode(Name: PUtf8Char; Len: Integer): PJsonNode; overload;
    function Find(const Name: RawUtf8): TJsonValue;
    function GetItem(Index: Integer): TJsonValue;
    procedure ScalarVariant(out Value: Variant);
  public
    function Get(const Name: RawUtf8): TJsonValue;
    function GetByPath(const Path: RawUtf8): TJsonValue;
    function GetAsObject(const Name: RawUtf8; out Value: TJsonValue): Boolean;
    function GetAsArray(const Name: RawUtf8; out Value: TJsonValue): Boolean;
    function GetAsArrayOrEmpty(const Name: RawUtf8; out Value: TJsonValue): Boolean;
    function GetAsDocVariant(const Name: RawUtf8; out Value: TJsonValue): Boolean;
    function GetDocVariantByPath(const Path: RawUtf8; out Value: TJsonValue): Boolean;
    function HasValue(const Name: RawUtf8): Boolean;
    function SameText(const Name, Value: RawUtf8): Boolean; overload;
    function SameText(const Value: RawUtf8): Boolean; overload;
    function TryNum(var Value: Double): Boolean;
    function TryI64(var Value: Int64): Boolean;
    function TryBool(var Value: Boolean): Boolean;
    function TryStr(var Value: string): Boolean; overload;
    function TryStr(var Value: RawUtf8): Boolean; overload;
    function TryLoadNum(const Name: RawUtf8; var Value: Double): Boolean; overload;
    function TryLoadNum(const Name: RawUtf8; var Value: Single): Boolean; overload;
    function TryLoadI64(const Name: RawUtf8; var Value: Int64): Boolean;
    function TryLoadBool(const Name: RawUtf8; var Value: Boolean): Boolean;
    function TryLoadStr(const Name: RawUtf8; var Value: string): Boolean; overload;
    function TryLoadStr(const Name: RawUtf8; var Value: RawUtf8): Boolean; overload;
    function TryLoadSlotNum(Index: Integer; var Value: Double): Boolean; overload;
    function TryLoadSlotNum(Index: Integer; var Value: Single): Boolean; overload;
    function TryLoadSlotI64(Index: Integer; var Value: Int64): Boolean;
    procedure LoadNum(const Name: RawUtf8; var Value: Double); overload;
    procedure LoadNum(const Name: RawUtf8; var Value: Single); overload;
    procedure LoadI64(const Name: RawUtf8; var Value: Int64);
    procedure LoadI64Str(const Name: RawUtf8; var Value: Int64);
    procedure LoadBool(const Name: RawUtf8; var Value: Boolean);
    procedure LoadStr(const Name: RawUtf8; var Value: string); overload;
    procedure LoadStr(const Name: RawUtf8; var Value: RawUtf8); overload;
    // Explicit materialization / legacy coercion of objects creates a DOM only
    // for that subtree. Ordinary typed reads of wire fields do not use this.
    function ToVariant: Variant;
    property Kind: TJsonKind read GetKind;
    property Count: Integer read GetCount;
    property Name: RawUtf8 read GetName;
    property NameString: string read GetNameString;
    property Item[Index: Integer]: TJsonValue read GetItem;
  end;

  TJsonEnumerator = record
  private
    FOwner: TJsonDocument;
    FParent: PDocVariantData;
    FNext, FRemaining: Integer;
    FObjectsOnly: Boolean;
    FCurrent: TJsonValue;
  public
    function GetEnumerator: TJsonEnumerator;
    function MoveNext: Boolean;
    property Current: TJsonValue read FCurrent;
  end;

  TJsonDocument = class
  private
    FBuffer: RawUtf8;
    FNodes: TArray<TJsonNode>;
    FNodeCount: Integer;
    FData: PUtf8Char;
    FWriter: TJsonWriter;
    FWriterLock: TOSLightLock;
    FRefCount: Integer;
    FDom: Variant;
    FFallback, FValid: Boolean;
    procedure AddNode(const N: TJsonNode);
    function EndIndex(Index: Integer): Integer; inline;
    function BuildIndex(Buffer: PUtf8Char; TextLength: Integer): Boolean;
    procedure WriteValue(Index: Integer; Writer: TJsonWriter);
    function JsonText(Index: Integer): RawUtf8;
    function GetRoot: TJsonValue;
    function GetIndexBytes: NativeInt;
  public
    constructor Create;
    destructor Destroy; override;
    function Parse(const Text: RawUtf8): Boolean; overload;
    function Parse(const Text: RawUtf8; const Options: TDocVariantOptions): Boolean; overload;
    // Transfers the string; aliases retain their bytes. No DOM fallback.
    function ParseOwned(var Text: RawUtf8): Boolean; overload;
    // Borrows exclusive mutable storage until Clear; requires 16 padding bytes.
    // Failure may modify the buffer; Root is missing. No DOM fallback.
    function ParseOwned(Buffer: PUtf8Char; TextLength, Capacity: NativeInt;
      const Options: TDocVariantOptions): Boolean; overload;
    procedure Clear;
    property InputPointer: PUtf8Char read FData;
    property Root: TJsonValue read GetRoot;
    property UsedDomFallback: Boolean read FFallback;
    property IndexBytes: NativeInt read GetIndexBytes;
  end;

  TJsonValueHelper = record helper for TJsonValue
    function Objects: TJsonEnumerator;
    function Items: TJsonEnumerator;
    function Fields: TJsonEnumerator;
  end;
// Opt-in read-only compact parsing, not a complete TDocVariant replacement:
// field access, Value(name/index), _count/_kind/_json and serialization are supported.
// Ordinary Variant assignment retains the document/subtree; explicit varByRef
// remains borrowed as in the RTL. The DOM fallback preserves native DOM behavior.
// A compact subtree retains the whole document; JsonMaterialize detaches its data.
// JsonView borrows a stable owning Variant variable until it is overwritten/cleared:
// keep that variable alive; do not save JsonView(SomeFunctionReturningVariant()).
// JsonMaterialize creates the native DOM required by legacy _Safe/mutable consumers.
// Parse keeps its own working copy: reusable WS text requires no caller-side Copy.
//
//   var Obj := JsonParse(Response);
//   for var Item in JsonView(Obj).GetByPath('result.list').Objects do
//     Item.LoadStr('symbol', Symbol);
//   // Obj is released automatically; Symbol owns the extracted string.
function JsonParse(const Text: RawUtf8; Compact: Boolean = true): Variant; overload;
function JsonParse(const Text: RawUtf8; out Value: Variant; Compact: Boolean = true): Boolean; overload;
function JsonView(const Value: Variant): TJsonValue;
function JsonMaterialize(const Value: Variant): Variant;

implementation


function TDocVariantFastHelper.GetAsArrayOrEmpty(const aName: RawUtf8;
  out aArray: PDocVariantData): boolean;
begin
  result := GetAsDocVariant(aName, aArray) and aArray^.IsArray;
end;

function TryStoreSingle(const Value: double; var Dest: single): boolean; inline;
begin
  // IEEE-754 absolute bits are ordered: Double(MaxSingle), then overflow/Inf/NaN.
  result := (PUInt64(@Value)^ and $7fffffffffffffff) <= $47efffffe0000000;
  If result then Dest := Value;
end;

function TryVariantNum(const V: Variant; var aValue: double): boolean; inline;
var
  pv:  PVarData;
  err: integer;
  number: double;
begin
  pv := PVarData(@V);
  result := true;
  case cardinal(pv^.VType) of
    varDouble, varDate:    aValue := pv^.VDouble;
    varInteger, varOleInt: aValue := pv^.VInteger;
    varInt64:              aValue := pv^.VInt64;
    varSingle:             aValue := pv^.VSingle;
    varString, varString or varByRef: begin
      If pv^.VType = varString then number := GetExtended(PUtf8Char(pv^.VAny), err)
      else number := GetExtended(PPointer(pv^.VAny)^, err);
      result := err = 0;
      If result then aValue := number;
    end;
  else
    result := false;
  end;
end;

function TryVariantI64(const V: Variant; var aValue: Int64): boolean; inline;
var
  pv:  PVarData;
  err: integer;
  number: Int64;
begin
  pv := PVarData(@V);
  result := true;
  case cardinal(pv^.VType) of
    varInteger, varOleInt: aValue := pv^.VInteger;
    varInt64:              aValue := pv^.VInt64;
    varString, varString or varByRef: begin
      If pv^.VType = varString then number := GetInt64(PUtf8Char(pv^.VAny), err)
      else number := GetInt64(PPointer(pv^.VAny)^, err);
      result := err = 0;
      If result then aValue := number;
    end;
  else
    result := false;
  end;
end;

procedure TDocVariantFastHelper.LoadI64(const aName: RawUtf8; var aValue: Int64);
var
  pv: PVarData;
begin
  pv := GetVarData(aName);
  if pv <> nil then
    VariantToInt64(PVariant(pv)^, aValue);
end;

procedure TDocVariantFastHelper.LoadI64Str(const aName: RawUtf8; var aValue: Int64);
var
  pv: PVarData;
begin
  // Для полей где API биржи шлёт целое число строкой ("ts":"1778101214576").
  // Подтверждённые случаи: BitGet trade.ts/liq.fillTime/liq.ts, OKX trade.ts.
  // Обычный LoadI64 на такой varString молча возвращает 0.
  pv := GetVarData(aName);
  if pv = nil then exit;
  case cardinal(pv^.VType) of
    varString:                       // плоская RawUtf8
      aValue := GetInt64(PUtf8Char(pv^.VAny));
    varString or varByRef:           // байрефнутая строка
      aValue := GetInt64(PPointer(pv^.VAny)^);
  end;
end;

procedure TDocVariantFastHelper.LoadBool(const aName: RawUtf8; var aValue: boolean);
var
  pv: PVarData;
begin
  pv := GetVarData(aName);
  if pv <> nil then
    VariantToBoolean(PVariant(pv)^, aValue);
end;

procedure TDocVariantFastHelper.LoadNum(const aName: RawUtf8; var aValue: double);
var
  pv: PVarData;
begin
  pv := GetVarData(aName);
  if pv = nil then exit;
  case cardinal(pv^.VType) of
    varDouble, varDate:
      aValue := pv^.VDouble;
    varInteger, varOleInt:
      aValue := pv^.VInteger;
    varInt64:
      aValue := pv^.VInt64;
    varSingle:
      aValue := pv^.VSingle;
    varString:                       // плоская RawUtf8 ("0.01633000")
      aValue := GetExtended(PUtf8Char(pv^.VAny));
    varString or varByRef:           // байрефнутая строка
      aValue := GetExtended(PPointer(pv^.VAny)^);
  end;
end;

procedure TDocVariantFastHelper.LoadNum(const aName: RawUtf8; var aValue: single);
var
  pv: PVarData;
begin
  // Прямой разбор в single, без делегирования double-версии: на hot path лишняя
  // конверсия single<->double не нужна. case держать синхронно с double-overload выше.
  pv := GetVarData(aName);
  if pv = nil then exit;
  case cardinal(pv^.VType) of
    varDouble, varDate:
      aValue := pv^.VDouble;
    varInteger, varOleInt:
      aValue := pv^.VInteger;
    varInt64:
      aValue := pv^.VInt64;
    varSingle:
      aValue := pv^.VSingle;
    varString:                       // плоская RawUtf8 ("0.01633000")
      aValue := GetExtended(PUtf8Char(pv^.VAny));
    varString or varByRef:           // байрефнутая строка
      aValue := GetExtended(PPointer(pv^.VAny)^);
  end;
end;

function TDocVariantFastHelper.TryLoadNum(const aName: RawUtf8; var aValue: double): boolean;
var
  pv:  PVarData;
begin
  pv := GetVarData(aName);
  result := (pv <> nil) and TryVariantNum(PVariant(pv)^, aValue);
end;

function TDocVariantFastHelper.TryLoadNum(const aName: RawUtf8; var aValue: single): boolean;
var
  d: double;
begin
  result := TryLoadNum(aName, d) and TryStoreSingle(d, aValue);
end;

function TDocVariantFastHelper.TryLoadI64(const aName: RawUtf8; var aValue: Int64): boolean;
var
  pv:  PVarData;
begin
  pv := GetVarData(aName);
  result := (pv <> nil) and TryVariantI64(PVariant(pv)^, aValue);
end;

function TDocVariantFastHelper.TryLoadBool(const aName: RawUtf8; var aValue: boolean): boolean;
var
  pv: PVarData;
begin
  result := false;
  pv := GetVarData(aName);
  if pv = nil then exit;
  case cardinal(pv^.VType) of
    varBoolean, varBoolean or varByRef:
      begin
        VariantToBoolean(PVariant(pv)^, aValue);
        result := true;
      end;
  end;
end;

procedure TDocVariantFastHelper.LoadStr(const aName: RawUtf8; var aValue: string);
var
  pv: PVarData;
begin
  pv := GetVarData(aName);
  if (pv <> nil) and (cardinal(pv^.VType) > varNull) then
    VariantToString(PVariant(pv)^, aValue);
end;

procedure TDocVariantFastHelper.LoadStr(const aName: RawUtf8; var aValue: RawUtf8);
var
  pv: PVarData;
begin
  pv := GetVarData(aName);
  if (pv <> nil) and (cardinal(pv^.VType) > varNull) then
    aValue := VariantToUtf8(PVariant(pv)^);
end;

function TDocVariantFastHelper.TryLoadSlotNum(const aIndex: integer; var aValue: double): boolean;
begin
  result := (aIndex >= 0) and (aIndex < Count) and TryVariantNum(Values[aIndex], aValue);
end;

function TDocVariantFastHelper.TryLoadSlotNum(const aIndex: integer; var aValue: single): boolean;
var
  d: double;
begin
  result := TryLoadSlotNum(aIndex, d) and TryStoreSingle(d, aValue);
end;

function TDocVariantFastHelper.TryLoadSlotI64(const aIndex: integer; var aValue: Int64): boolean;
begin
  result := (aIndex >= 0) and (aIndex < Count) and TryVariantI64(Values[aIndex], aValue);
end;

function TDocVariantFastHelper.TryLoadStr(const aName: RawUtf8; var aValue: string): boolean;
var
  pv: PVarData;
begin
  result := false;
  pv := GetVarData(aName);
  if (pv <> nil) and (cardinal(pv^.VType) > varNull) then begin
    VariantToString(PVariant(pv)^, aValue);
    result := aValue <> '';
  end;
end;

function TDocVariantFastHelper.TryLoadStr(const aName: RawUtf8; var aValue: RawUtf8): boolean;
var
  pv: PVarData;
begin
  result := false;
  pv := GetVarData(aName);
  if (pv <> nil) and (cardinal(pv^.VType) > varNull) then begin
    aValue := VariantToUtf8(PVariant(pv)^);
    result := aValue <> '';
  end;
end;

function TDocVariantFastHelper.HasValue(const aName: RawUtf8): boolean;
var
  pv: PVarData;
begin
  pv := GetVarData(aName);
  result := (pv <> nil) and (cardinal(pv^.VType) > varNull);
end;

function TDocVariantFastHelper.SameText(const aName, aValue: RawUtf8): boolean;
var
  pv: PVarData;
begin
  pv := GetVarData(aName);
  result := (pv <> nil)
            and (cardinal(pv^.VType) > varNull)
            and VariantEquals(PVariant(pv)^, aValue, {CaseSensitive=}false);
end;

type
  TJsonVariantData = packed record
    VType, Reserved: Word;
    Index: Integer;
    Owner: TJsonDocument;
    Padding: Pointer;
  end;

  TJsonVariantType = class(TSynInvokeableVariantType)
  public
    constructor Create; override;
    procedure Clear(var V: TVarData); override;
    procedure Copy(var Dest: TVarData; const Source: TVarData; const Indirect: Boolean); override;
    procedure CastTo(var Dest: TVarData; const Source: TVarData; const AVarType: TVarType); override;
    procedure ToJson(W: TJsonWriter; Value: PVarData); override;
    function IntGet(var Dest: TVarData; const Instance: TVarData;
      Name: PAnsiChar; NameLen: PtrInt; NoException: Boolean): Boolean; override;
    function DoFunction(var Dest: TVarData; const V: TVarData;
      const Name: {$IFDEF FPC}AnsiString{$ELSE}string{$ENDIF}; const Arguments: TVarDataArray): Boolean; override;
    function IsVoid(const V: TVarData): Boolean; override;
  end;

var
  JsonVariantType: TJsonVariantType;

type
  TJsonIndexReader = record
    P, Base: PUtf8Char;
    Doc: TJsonDocument;
    Valid: Boolean;
    function Separator: AnsiChar;
    function StringEnd(S: PUtf8Char; out HasEscape: Boolean): PUtf8Char;
    function ReadValue(NameOffset, NameLength, Depth: Integer): AnsiChar;
  end;

function TJsonIndexReader.Separator: AnsiChar;
begin
  P := GotoNextNotSpace(P);
  Result := P^;
  If Result = #0 then exit;
  If not (Result in [',', '}', ']']) then begin
    Valid := false;
    exit(#0);
  end;
  P := GotoNextNotSpace(P + 1);
end;

// Check the closing quote before mORMot unescapes in place. Plain strings remain slices.
function TJsonIndexReader.StringEnd(S: PUtf8Char; out HasEscape: Boolean): PUtf8Char;
var
  Tab: PJsonCharSet;
begin
  Tab := @JSON_CHARS;
  HasEscape := false;
  repeat
    Inc(S);
    If not (jcJsonStringMarker in Tab[S^]) then continue;
    If S^ = '"' then break;
    If (S^ = #0) or (S[1] = #0) then exit(nil);
    HasEscape := true;
    Inc(S);
  until false;
  Result := S;
end;

function ReadJsonScalar(var Info: TGetJsonField; var N: TJsonNode): Boolean;
var
  Scalar: Variant;
begin
  // Keep managed Variant initialization/finalization out of the string/container
  // path. Scalar numbers use exactly the same conversion as the DOM parser.
  JsonToAnyVariant(Scalar, Info, @ViewOptions);
  Result := true;
  case TVarData(Scalar).VType of
    varNull: N.Kind := jkNull;
    varBoolean: begin
      N.Kind := jkBoolean;
      N.IntegerValue := Ord(TVarData(Scalar).VBoolean);
    end;
    varInteger: begin
      N.Kind := jkInt64;
      N.WasInteger32 := true;
      N.IntegerValue := TVarData(Scalar).VInteger;
    end;
    varInt64: begin
      N.Kind := jkInt64;
      N.IntegerValue := TVarData(Scalar).VInt64;
    end;
    varDouble: begin
      N.Kind := jkDouble;
      N.Number := TVarData(Scalar).VDouble;
    end;
  else
    Result := false;
  end;
end;

function TJsonIndexReader.ReadValue(NameOffset, NameLength, Depth: Integer): AnsiChar;
var
  N: TJsonNode;
  Index, Count, KeyLength: Integer;
  Key, Quote, Delim: PUtf8Char;
  HasEscape: Boolean;
  Closing: AnsiChar;
  Info: TGetJsonField;
begin
  Result := #0;
  If Depth > 128 then begin
    Valid := false;
    exit;
  end;
  N := Default(TJsonNode);
  N.NameOffset := NameOffset;
  N.NameLength := NameLength;
  P := GotoNextNotSpace(P);
  If P^ in ['{', '['] then begin
    If P^ = '{' then begin
      N.Kind := jkObject;
      Closing := '}';
    end else begin
      N.Kind := jkArray;
      Closing := ']';
    end;
    Index := Doc.FNodeCount;
    Doc.AddNode(N);
    Count := 0;
    P := GotoNextNotSpace(P + 1);
    If P^ <> Closing then repeat
      If N.Kind = jkObject then begin
        P := GotoNextNotSpace(P);
        If P^ <> '"' then begin
          Valid := false;
          exit;
        end;
        Quote := StringEnd(P, HasEscape);
        If Quote = nil then begin
          Valid := false;
          exit;
        end;
        If HasEscape then begin
          If GotoNextNotSpace(Quote + 1)^ <> ':' then begin
            Valid := false;
            exit;
          end;
          Key := GetJsonPropName(P, @KeyLength);
          If (Key = nil) or (KeyLength = 0) then begin
            Valid := false;
            exit;
          end;
        end else begin
          Key := P + 1;
          KeyLength := Quote - Key;
          Quote^ := #0;
          P := GotoNextNotSpace(Quote + 1);
          If (KeyLength = 0) or (P^ <> ':') then begin
            Valid := false;
            exit;
          end;
          Inc(P);
        end;
        Result := ReadValue(Key - Base, KeyLength, Depth + 1);
      end else
        Result := ReadValue(-1, 0, Depth + 1);
      If not Valid then exit;
      Inc(Count);
      If Result = Closing then break;
      If Result <> ',' then begin
        Valid := false;
        exit;
      end;
    until false
    else
      Inc(P);
    N.Len := Count;
    N.Offset := Doc.FNodeCount;
    Doc.FNodes[Index] := N;
    Result := Separator;
  end else begin
    Info.Json := P;
    If P^ = '"' then begin
      Quote := StringEnd(P, HasEscape);
      If Quote = nil then begin
        Valid := false;
        exit;
      end;
      Delim := GotoNextNotSpace(Quote + 1);
      If not (Delim^ in [#0, ',', '}', ']']) then begin
        Valid := false;
        exit;
      end;
      N.Kind := jkString;
      If HasEscape then begin
        Info.GetJsonField;
        If Info.Json = nil then begin
          Valid := false;
          exit;
        end;
        N.Offset := Info.Value - Base;
        N.Len := Info.ValueLen;
        P := Info.Json;
        Result := Info.EndOfObject;
      end else begin
        N.Offset := (P + 1) - Base;
        N.Len := Quote - (P + 1);
        Quote^ := #0;
        Result := Delim^;
        If Delim^ = #0 then P := Delim else P := Delim + 1;
      end;
    end else begin
      Valid := ReadJsonScalar(Info, N);
      If (Info.Json = nil) or not Valid then begin
        Valid := false;
        exit;
      end;
      P := Info.Json;
      Result := Info.EndOfObject;
    end;
    Doc.AddNode(N);
  end;
end;

function TJsonNode.GetKind: TJsonKind;
begin
  Result := TJsonKind(FMeta shr 29);
end;
procedure TJsonNode.SetKind(Value: TJsonKind);
begin
  FMeta := (FMeta and $1fffffff) or (Cardinal(Value) shl 29);
end;
function TJsonNode.GetNameLength: Integer;
begin
  Result := FMeta and TapeMask;
end;
procedure TJsonNode.SetNameLength(Value: Integer);
begin
  FMeta := (FMeta and $f0000000) or Cardinal(Value);
end;
function TJsonNode.GetWasInteger32: Boolean;
begin
  Result := FMeta and $10000000 <> 0;
end;
procedure TJsonNode.SetWasInteger32(Value: Boolean);
begin
  FMeta := (FMeta and $efffffff) or (Cardinal(Value) shl 28);
end;

constructor TJsonDocument.Create;
begin
  inherited;
  FWriterLock.Init;
end;

procedure TJsonDocument.AddNode(const N: TJsonNode);
begin
  If FNodeCount = Length(FNodes) then SetLength(FNodes, NextGrow(FNodeCount));
  FNodes[FNodeCount] := N;
  Inc(FNodeCount);
end;

destructor TJsonDocument.Destroy;
begin
  FWriter.Free;
  FWriterLock.Done;
  inherited;
end;

procedure TJsonDocument.Clear;
begin
  FValid := false;
  FData := nil;
  FBuffer := '';
  FNodes := nil;
  FNodeCount := 0;
  FreeAndNil(FWriter);
  VarClear(FDom);
  FFallback := false;
end;

function TJsonDocument.BuildIndex(Buffer: PUtf8Char; TextLength: Integer): Boolean;
var
  Reader: TJsonIndexReader;
begin
  Result := false;
  If not (GotoNextNotSpace(Buffer)^ in ['{', '[']) then exit;
  FData := Buffer;
  Reader.Base := Buffer;
  Reader.P := Buffer;
  Reader.Doc := Self;
  Reader.Valid := true;
  SetLength(FNodes, TextLength div 12 + 8);
  FValid := (Reader.ReadValue(-1, 0, 0) = #0) and Reader.Valid and (Reader.P - Buffer = TextLength);
  Result := FValid;
end;

function TJsonDocument.ParseOwned(Buffer: PUtf8Char; TextLength, Capacity: NativeInt;
  const Options: TDocVariantOptions): Boolean;
begin
  Clear;
  Result := false;
  If (Buffer = nil) or (TextLength <= 0) or (TextLength > TapeMask) or (Capacity < TextLength + 16) or
    (Options - [dvoInternNames, dvoInternValues] <> ViewOptions) then exit;
  FillChar((Buffer + TextLength)^, 16, 0);
  try
    Result := BuildIndex(Buffer, TextLength);
  finally
    If not Result then Clear;
  end;
end;

function TJsonDocument.ParseOwned(var Text: RawUtf8): Boolean;
var
  Len: Integer;
begin
  Clear;
  Result := false;
  Len := Length(Text);
  If (Len = 0) or (Len > TapeMask) then exit;
  SetLength(Text, Len + 16);
  FillChar((PUtf8Char(Pointer(Text)) + Len)^, 16, 0);
  FBuffer := Text;
  Text := '';
  try
    Result := BuildIndex(Pointer(FBuffer), Len);
  finally
    If not Result then Clear;
  end;
end;

function TJsonDocument.Parse(const Text: RawUtf8): Boolean;
begin
  Result := Parse(Text, ViewOptions);
end;

function TJsonDocument.Parse(const Text: RawUtf8; const Options: TDocVariantOptions): Boolean;
begin
  Clear;
  try
    If (Text <> '') and (Length(Text) <= TapeMask) and
      (Options - [dvoInternNames, dvoInternValues] = ViewOptions) then begin
      SetLength(FBuffer, Length(Text) + 16);
      MoveFast(Pointer(Text)^, Pointer(FBuffer)^, Length(Text));
      FillChar((PUtf8Char(Pointer(FBuffer)) + Length(Text))^, 16, 0);
      BuildIndex(Pointer(FBuffer), Length(Text));
    end;
    If not FValid then begin
      Clear;
      FFallback := true;
      FValid := _Json(Text, FDom, Options);
    end;
    Result := FValid;
  except
    Clear;
    raise;
  end;
end;

function TJsonDocument.EndIndex(Index: Integer): Integer;
var
  N: PJsonNode;
begin
  N := @FNodes[Index];
  If N.Kind in [jkArray, jkObject] then Result := N.Offset else Result := Index + 1;
end;

function TJsonDocument.GetRoot: TJsonValue;
begin
  Result := Default(TJsonValue);
  If not FValid then exit;
  If FFallback then begin
    Result.FParent := @FDom;
    Result.FIndex := -1;
  end else
    Result.FOwner := Self;
end;

function TJsonDocument.GetIndexBytes: NativeInt;
begin
  Result := NativeInt(Length(FNodes)) * SizeOf(TJsonNode);
end;

function TJsonValue.Node: PJsonNode;
begin
  Result := Pointer(@FOwner.FNodes[FIndex]);
end;

function TJsonValue.Dom: PVariant;
begin
  If FIndex < 0 then Result := PVariant(FParent)
  else Result := @FParent^.Values[FIndex];
  Result := PVariant(VarDataFromVariant(Result^));
end;

function TJsonValue.IsDom: Boolean;
begin
  Result := FOwner = nil;
end;

procedure WriteTapeScalar(Owner: TJsonDocument; Index: Integer; Writer: TJsonWriter);
var
  Value: TJsonValue;
  Scalar: Variant;
begin
  Value.FOwner := Owner;
  Value.FIndex := Index;
  Value.ScalarVariant(Scalar);
  Writer.AddVariant(Scalar);
end;

procedure TJsonDocument.WriteValue(Index: Integer; Writer: TJsonWriter);
var
  N: PJsonNode;
  Child: Integer;
  IsObject: Boolean;
begin
  N := Pointer(@FNodes[Index]);
  case N.Kind of
    jkString: begin
      Writer.Add('"');
      Writer.AddJsonEscape(FData + N.Offset, N.Len);
      Writer.Add('"');
    end;
    jkArray, jkObject: begin
      IsObject := N.Kind = jkObject;
      If IsObject then Writer.Add('{') else Writer.Add('[');
      Child := Index + 1;
      for var I := 0 to N.Len - 1 do begin
        If I <> 0 then Writer.Add(',');
        If IsObject then begin
          var Field: PJsonNode := Pointer(@FNodes[Child]);
          Writer.Add('"');
          Writer.AddJsonEscape(FData + Field.NameOffset, Field.NameLength);
          Writer.Add('"', ':');
        end;
        WriteValue(Child, Writer);
        Child := EndIndex(Child);
      end;
      If IsObject then Writer.Add('}') else Writer.Add(']');
    end;
  else
    WriteTapeScalar(Self, Index, Writer);
  end;
end;

function TJsonDocument.JsonText(Index: Integer): RawUtf8;
begin
  // Reuse the writer without per-subtree allocations. Shared immutable
  // Variants may serialize concurrently; the returned string is independent.
  FWriterLock.Lock;
  try
    If FWriter = nil then FWriter := TJsonWriter.CreateOwnedStream(4096, true);
    FWriter.CancelAll;
    WriteValue(Index, FWriter);
    FWriter.SetText(Result);
  finally
    FWriterLock.UnLock;
  end;
end;

function TJsonValue.GetKind: TJsonKind;
var
  D: PDocVariantData;
begin
  If (FOwner = nil) and (FParent = nil) then exit(jkMissing);
  If not IsDom then exit(Node.Kind);
  case TVarData(Dom^).VType of
    varEmpty, varNull: Result := jkNull;
    varBoolean: Result := jkBoolean;
    varInteger, varInt64: Result := jkInt64;
    varDouble, varCurrency: Result := jkDouble;
    varString: Result := jkString;
  else
    If _Safe(Dom^, D) then begin
      If D^.Kind = dvArray then Result := jkArray else Result := jkObject;
    end else
      Result := jkMissing;
  end;
end;

function TJsonValue.GetCount: Integer;
begin
  Result := 0;
  If not (Kind in [jkArray, jkObject]) then exit;
  If IsDom then Result := _Safe(Dom^)^.Count else Result := Node.Len;
end;

function TJsonValue.GetName: RawUtf8;
begin
  Result := '';
  If (FOwner = nil) and (FParent = nil) then exit;
  If IsDom then begin
    If (FParent <> nil) and (FIndex >= 0) and (FParent^.Kind = dvObject) then Result := FParent^.Names[FIndex];
  end else If Node.NameOffset >= 0 then
    FastSetString(Result, PUtf8Char(FOwner.FData) + Node.NameOffset, Node.NameLength);
end;

function TJsonValue.GetNameString: string;
begin
  Result := '';
  If (FOwner = nil) and (FParent = nil) then exit;
  If IsDom then begin
    If (FIndex >= 0) and (FParent^.Kind = dvObject) then Result := string(FParent^.Names[FIndex]);
  end else If Node.NameOffset >= 0 then
    Result := Utf8DecodeToString(FOwner.FData + Node.NameOffset, Node.NameLength);
end;

function TJsonValue.Find(const Name: RawUtf8): TJsonValue;
var
  D: PDocVariantData;
  I: Integer;
  N: PJsonNode;
begin
  Result := Default(TJsonValue);
  If (FOwner = nil) and (FParent = nil) then exit;
  If IsDom then begin
    If not (Kind in [jkObject, jkArray]) then exit;
    D := _Safe(Dom^);
    I := D.GetValueIndex(Name);
    If I < 0 then exit;
    Result.FParent := D;
  end else begin
    N := FindNode(Name);
    If N = nil then exit;
    I := (NativeInt(N) - NativeInt(@FOwner.FNodes[0])) div SizeOf(TJsonNode);
  end;
  Result.FOwner := FOwner;
  Result.FIndex := I;
end;

function TJsonValue.FindNode(const Name: RawUtf8): PJsonNode;
var
  I: NativeInt;
  Err: Integer;
begin
  Result := nil;
  If FOwner = nil then exit;
  If Node.Kind = jkArray then begin
    If Name = '' then exit;
    I := GetInteger(Pointer(Name), Err);
    If (Err = 0) and (I >= 0) and (I < Node.Len) then Result := GetItem(I).Node;
  end else If Node.Kind = jkObject then
    Result := FindNode(Pointer(Name), Length(Name));
end;

function TJsonValue.FindNode(Name: PUtf8Char; Len: Integer): PJsonNode;
var
  I, Stop: Integer;
begin
  Result := nil;
  If Len = 0 then exit;
  Stop := Node.Offset;
  I := FIndex + 1;
  while I < Stop do begin
    Result := @FOwner.FNodes[I];
    If (Result.NameLength = Len) and CompareMem(FOwner.FData + Result.NameOffset, Name, Len) then exit;
    I := FOwner.EndIndex(I);
  end;
  Result := nil;
end;

function TJsonValue.Get(const Name: RawUtf8): TJsonValue;
begin
  Result := Find(Name);
end;

function TJsonValue.GetItem(Index: Integer): TJsonValue;
begin
  Result := Default(TJsonValue);
  If (Index < 0) or (Index >= Count) then exit;
  Result.FOwner := FOwner;
  If IsDom then begin
    Result.FParent := _Safe(Dom^);
    Result.FIndex := Index;
  end else begin
    Result.FIndex := FIndex + 1;
    If Node.Offset = FIndex + Node.Len + 1 then
      Inc(Result.FIndex, Index)
    else
      for var I := 1 to Index do Result.FIndex := FOwner.EndIndex(Result.FIndex);
  end;
end;

function TJsonValue.GetByPath(const Path: RawUtf8): TJsonValue;
var
  P, Start: PUtf8Char;
  N: PJsonNode;
  D: PDocVariantData;
  Slot: Integer;
  Index: NativeUInt;
begin
  Result := Self;
  P := Pointer(Path);
  If (P = nil) or ((FOwner = nil) and (FParent = nil)) then exit(Default(TJsonValue));
  repeat
    Start := P;
    while not (P^ in [#0, '.']) do Inc(P);
    If Start = P then exit(Default(TJsonValue));
    case Result.Kind of
      jkObject: begin
        If IsDom then begin
          D := _Safe(Result.Dom^);
          Slot := D.GetValueIndex(Start, P - Start, D.IsCaseSensitive);
          If Slot < 0 then exit(Default(TJsonValue));
          Result.FParent := D;
          Result.FIndex := Slot;
        end else begin
          N := Result.FindNode(Start, P - Start);
          If N = nil then exit(Default(TJsonValue));
          Result.FIndex := (NativeInt(N) - NativeInt(@FOwner.FNodes[0])) div SizeOf(TJsonNode);
        end;
      end;
      jkArray: begin
        If not (Start^ in ['0'..'9']) then exit(Default(TJsonValue));
        Index := GetCardinal(Start, P);
        If Index >= Cardinal(Result.Count) then exit(Default(TJsonValue));
        Result := Result.GetItem(Index);
      end;
    else
      exit(Default(TJsonValue));
    end;
    If P^ = #0 then exit;
    Inc(P);
  until false;
end;

function TJsonValue.GetAsObject(const Name: RawUtf8; out Value: TJsonValue): Boolean;
begin
  Value := Find(Name);
  Result := (Value.Kind = jkObject) and (Value.Count <> 0);
end;

function TJsonValue.GetAsArray(const Name: RawUtf8; out Value: TJsonValue): Boolean;
begin
  Result := GetAsArrayOrEmpty(Name, Value) and (Value.Count <> 0);
end;

function TJsonValue.GetAsArrayOrEmpty(const Name: RawUtf8; out Value: TJsonValue): Boolean;
begin
  Value := Find(Name);
  Result := Value.Kind = jkArray;
end;

function TJsonValue.GetAsDocVariant(const Name: RawUtf8; out Value: TJsonValue): Boolean;
begin
  Value := Find(Name);
  Result := Value.Kind in [jkArray, jkObject];
end;

function TJsonValue.GetDocVariantByPath(const Path: RawUtf8; out Value: TJsonValue): Boolean;
begin
  Value := GetByPath(Path);
  Result := Value.Kind in [jkArray, jkObject];
end;

function TJsonValue.HasValue(const Name: RawUtf8): Boolean;
begin
  Result := not (Find(Name).Kind in [jkMissing, jkNull]);
end;

procedure TJsonValue.ScalarVariant(out Value: Variant);
begin
  VarClear(Value);
  case Kind of
    jkNull, jkMissing: TVarData(Value).VType := varNull;
    jkBoolean: Value := Node.IntegerValue <> 0;
    jkInt64:
      If Node.WasInteger32 then Value := Integer(Node.IntegerValue) else Value := Node.IntegerValue;
    jkDouble: Value := Node.Number;
  end;
end;

function TJsonValue.ToVariant: Variant;
var
  D: PDocVariantData;
  S: RawUtf8;
begin
  If (FOwner = nil) and (FParent = nil) then exit(Null);
  If IsDom then exit(Dom^);
  case Kind of
    jkString: begin
      FastSetString(S, PUtf8Char(FOwner.FData) + Node.Offset, Node.Len);
      Result := S;
    end;
    jkArray, jkObject: begin
      // Delphi may reuse a nonempty function-result temporary between iterations.
      // TDocVariantData.Init* initializes raw storage; it does not clear its old value.
      VarClear(Result);
      D := @TDocVariantData(Result);
      If Kind = jkArray then D.InitArray([], ViewOptions) else D.InitObject([], ViewOptions);
      for var V in Self.Items do
        If Kind = jkArray then D.AddItem(V.ToVariant) else D.AddValue(V.Name, V.ToVariant);
    end;
  else
    ScalarVariant(Result);
  end;
end;

function TJsonValue.SameText(const Value: RawUtf8): Boolean;
var
  V: Variant;
begin
  If Kind in [jkMissing, jkNull] then exit(false);
  If IsDom then exit(VariantEquals(Dom^, Value, false));
  If Kind = jkString then
    exit(PropNameEquals(PAnsiChar(FOwner.FData) + Node.Offset, PAnsiChar(Pointer(Value)), Node.Len, Length(Value)));
  V := ToVariant;
  Result := VariantEquals(V, Value, false);
end;

function TJsonValue.SameText(const Name, Value: RawUtf8): Boolean;
var
  N: PJsonNode;
begin
  If not IsDom then begin
    N := FindNode(Name);
    If N = nil then exit(false);
    If N.Kind = jkString then
      exit(PropNameEquals(PAnsiChar(FOwner.FData) + N.Offset, PAnsiChar(Pointer(Value)), N.Len, Length(Value)));
  end;
  Result := Find(Name).SameText(Value);
end;

function NodeNum(Owner: TJsonDocument; N: PJsonNode; var Value: Double): Boolean;
var
  Err: Integer;
  Number: Double;
begin
  If N = nil then exit(false);
  Result := true;
  case N.Kind of
    jkInt64: Value := N.IntegerValue;
    jkDouble: Value := N.Number;
    jkString: begin
      Number := GetExtended(PUtf8Char(Owner.FData) + N.Offset, Err);
      Result := Err = 0;
      If Result then Value := Number;
    end;
  else
    Result := false;
  end;
end;

function NodeI64(Owner: TJsonDocument; N: PJsonNode; var Value: Int64): Boolean;
var
  Err: Integer;
  Number: Int64;
begin
  If N = nil then exit(false);
  Result := true;
  case N.Kind of
    jkInt64: Value := N.IntegerValue;
    jkString: begin
      Number := GetInt64(PUtf8Char(Owner.FData) + N.Offset, Err);
      Result := Err = 0;
      If Result then Value := Number;
    end;
  else
    Result := false;
  end;
end;

function TJsonValue.TryNum(var Value: Double): Boolean;
begin
  If (FOwner = nil) and (FParent = nil) then exit(false);
  If IsDom then Result := TryVariantNum(Dom^, Value) else Result := NodeNum(FOwner, Node, Value);
end;

function TJsonValue.TryI64(var Value: Int64): Boolean;
begin
  If (FOwner = nil) and (FParent = nil) then exit(false);
  If IsDom then Result := TryVariantI64(Dom^, Value) else Result := NodeI64(FOwner, Node, Value);
end;

function TJsonValue.TryBool(var Value: Boolean): Boolean;
begin
  Result := Kind = jkBoolean;
  If not Result then exit;
  If IsDom then VariantToBoolean(Dom^, Value) else Value := Node.IntegerValue <> 0;
end;

function TJsonValue.TryStr(var Value: string): Boolean;
var
  V: Variant;
begin
  Result := not (Kind in [jkMissing, jkNull]);
  If not Result then exit;
  If not IsDom and (Kind = jkString) then
    Value := Utf8DecodeToString(PUtf8Char(FOwner.FData) + Node.Offset, Node.Len)
  else If not IsDom and (Kind in [jkArray, jkObject]) then
    Value := Utf8ToString(FOwner.JsonText(FIndex))
  else begin
    V := ToVariant;
    VariantToString(V, Value);
  end;
  Result := Value <> '';
end;

function TJsonValue.TryStr(var Value: RawUtf8): Boolean;
var
  V: Variant;
begin
  Result := not (Kind in [jkMissing, jkNull]);
  If not Result then exit;
  If not IsDom and (Kind = jkString) then
    FastSetString(Value, PUtf8Char(FOwner.FData) + Node.Offset, Node.Len)
  else If not IsDom and (Kind in [jkArray, jkObject]) then
    Value := FOwner.JsonText(FIndex)
  else begin
    V := ToVariant;
    Value := VariantToUtf8(V);
  end;
  Result := Value <> '';
end;

function TJsonValue.TryLoadNum(const Name: RawUtf8; var Value: Double): Boolean;
begin
  If IsDom then Result := Find(Name).TryNum(Value)
  else Result := NodeNum(FOwner, FindNode(Name), Value);
end;

function TJsonValue.TryLoadI64(const Name: RawUtf8; var Value: Int64): Boolean;
begin
  If IsDom then Result := Find(Name).TryI64(Value)
  else Result := NodeI64(FOwner, FindNode(Name), Value);
end;

function TJsonValue.TryLoadNum(const Name: RawUtf8; var Value: Single): Boolean;
var
  D: Double;
begin
  Result := TryLoadNum(Name, D) and TryStoreSingle(D, Value);
end;

function TJsonValue.TryLoadBool(const Name: RawUtf8; var Value: Boolean): Boolean;
var
  N: PJsonNode;
begin
  If IsDom then exit(Find(Name).TryBool(Value));
  N := FindNode(Name);
  Result := (N <> nil) and (N.Kind = jkBoolean);
  If Result then Value := N.IntegerValue <> 0;
end;

function TJsonValue.TryLoadStr(const Name: RawUtf8; var Value: string): Boolean;
var
  N: PJsonNode;
begin
  If not IsDom then begin
    N := FindNode(Name);
    If N = nil then exit(false);
    If N.Kind = jkString then begin
      Value := Utf8DecodeToString(PUtf8Char(FOwner.FData) + N.Offset, N.Len);
      exit(Value <> '');
    end;
  end;
  Result := Find(Name).TryStr(Value);
end;

function TJsonValue.TryLoadStr(const Name: RawUtf8; var Value: RawUtf8): Boolean;
var
  N: PJsonNode;
begin
  If not IsDom then begin
    N := FindNode(Name);
    If N = nil then exit(false);
    If N.Kind = jkString then begin
      FastSetString(Value, PUtf8Char(FOwner.FData) + N.Offset, N.Len);
      exit(Value <> '');
    end;
  end;
  Result := Find(Name).TryStr(Value);
end;

function TJsonValue.TryLoadSlotNum(Index: Integer; var Value: Double): Boolean;
begin
  Result := GetItem(Index).TryNum(Value);
end;

function TJsonValue.TryLoadSlotI64(Index: Integer; var Value: Int64): Boolean;
begin
  Result := GetItem(Index).TryI64(Value);
end;

function TJsonValue.TryLoadSlotNum(Index: Integer; var Value: Single): Boolean;
var
  D: Double;
begin
  Result := TryLoadSlotNum(Index, D) and TryStoreSingle(D, Value);
end;

procedure TJsonValue.LoadNum(const Name: RawUtf8; var Value: Double);
var
  N: PJsonNode;
  D: PDocVariantData;
begin
  If FParent <> nil then begin
    If _Safe(Dom^, D) then D.LoadNum(Name, Value);
    exit;
  end;
  N := FindNode(Name);
  If (N <> nil) and (N.Kind = jkString) then
    Value := GetExtended(PUtf8Char(FOwner.FData) + N.Offset)
  else
    NodeNum(FOwner, N, Value);
end;

procedure TJsonValue.LoadI64(const Name: RawUtf8; var Value: Int64);
var
  N: PJsonNode;
  D: PDocVariantData;
begin
  If FParent <> nil then begin
    If _Safe(Dom^, D) then D.LoadI64(Name, Value);
    exit;
  end;
  N := FindNode(Name);
  If N = nil then exit;
  case N.Kind of
    jkNull: Value := 0;
    jkBoolean, jkInt64: Value := N.IntegerValue;
  end;
end;

procedure TJsonValue.LoadNum(const Name: RawUtf8; var Value: Single);
var
  D: Double;
begin
  D := Value;
  LoadNum(Name, D);
  Value := D;
end;

procedure TJsonValue.LoadI64Str(const Name: RawUtf8; var Value: Int64);
var
  N: PJsonNode;
  D: PDocVariantData;
begin
  If FParent <> nil then begin
    If _Safe(Dom^, D) then D.LoadI64Str(Name, Value);
    exit;
  end;
  N := FindNode(Name);
  If (N <> nil) and (N.Kind = jkString) then
    Value := GetInt64(PUtf8Char(FOwner.FData) + N.Offset);
end;

procedure TJsonValue.LoadBool(const Name: RawUtf8; var Value: Boolean);
var
  N: PJsonNode;
  D: PDocVariantData;
begin
  If FParent <> nil then begin
    If _Safe(Dom^, D) then D.LoadBool(Name, Value);
    exit;
  end;
  N := FindNode(Name);
  If N = nil then exit;
  case N.Kind of
    jkBoolean: Value := N.IntegerValue <> 0;
    jkInt64: If N.WasInteger32 then Value := N.IntegerValue = 1;
    jkString: Value := (N.Len <> 0) and GetBoolean(FOwner.FData + N.Offset);
  end;
end;

procedure TJsonValue.LoadStr(const Name: RawUtf8; var Value: string);
begin
  TryLoadStr(Name, Value);
end;

procedure TJsonValue.LoadStr(const Name: RawUtf8; var Value: RawUtf8);
begin
  TryLoadStr(Name, Value);
end;

function TJsonValueHelper.Items: TJsonEnumerator;
begin
  Result := Default(TJsonEnumerator);
  Result.FRemaining := Count;
  If Result.FRemaining = 0 then exit;
  Result.FOwner := FOwner;
  If IsDom then Result.FParent := _Safe(Dom^) else begin
    Result.FNext := FIndex + 1;
  end;
end;

function TJsonValueHelper.Objects: TJsonEnumerator;
begin
  Result := Items;
  Result.FObjectsOnly := true;
end;

function TJsonValueHelper.Fields: TJsonEnumerator;
begin
  Result := Default(TJsonEnumerator);
  If Kind = jkObject then Result := Items;
end;

function TJsonEnumerator.GetEnumerator: TJsonEnumerator;
begin
  Result := Self;
end;

function TJsonEnumerator.MoveNext: Boolean;
begin
  while FRemaining <> 0 do begin
    Dec(FRemaining);
    FCurrent.FOwner := FOwner;
    FCurrent.FParent := FParent;
    FCurrent.FIndex := FNext;
    If FOwner = nil then Inc(FNext) else FNext := FOwner.EndIndex(FNext);
    If not FObjectsOnly or (FCurrent.Kind in [jkArray, jkObject]) then exit(true);
  end;
  Result := false;
end;

function JsonView(const Value: Variant): TJsonValue;
var
  V: PVarData;
begin
  Result := Default(TJsonValue);
  V := VarDataFromVariant(Value);
  If V.VType = JsonVariantType.VarType then begin
    Result.FOwner := TJsonVariantData(V^).Owner;
    Result.FIndex := TJsonVariantData(V^).Index;
  end else begin
    Result.FParent := Pointer(V);
    Result.FIndex := -1;
  end;
end;

procedure AssignJsonValue(var Dest: TVarData; const Value: TJsonValue);
begin
  If not Value.IsDom and (Value.Kind in [jkArray, jkObject]) then begin
    // Retain before clearing: Dest may be the last owner of this subtree.
    TInterlocked.Increment(Value.FOwner.FRefCount);
    VarClear(Variant(Dest));
    Dest := Default(TVarData);
    Dest.VType := JsonVariantType.VarType;
    TJsonVariantData(Dest).Owner := Value.FOwner;
    TJsonVariantData(Dest).Index := Value.FIndex;
  end else
    Variant(Dest) := Value.ToVariant;
end;

function JsonParse(const Text: RawUtf8; out Value: Variant; Compact: Boolean): Boolean;
var
  Doc: TJsonDocument;
begin
  If not Compact then exit(_Json(Text, Value, ViewOptions));
  Doc := TJsonDocument.Create;
  try
    Result := Doc.Parse(Text);
    If not Result or Doc.UsedDomFallback then Value := Doc.FDom
    else begin
      AssignJsonValue(TVarData(Value), Doc.Root);
      Doc := nil;
    end;
  finally
    Doc.Free;
  end;
end;

function JsonParse(const Text: RawUtf8; Compact: Boolean): Variant;
begin
  JsonParse(Text, Result, Compact);
end;

function JsonMaterialize(const Value: Variant): Variant;
begin
  Result := JsonView(Value).ToVariant;
end;

constructor TJsonVariantType.Create;
begin
  inherited;
  fOptions := [sioHasToJson];
end;

procedure TJsonVariantType.Clear(var V: TVarData);
var
  Doc: TJsonDocument;
begin
  Doc := TJsonVariantData(V).Owner;
  V := Default(TVarData);
  If TInterlocked.Decrement(Doc.FRefCount) = 0 then Doc.Free;
end;

procedure TJsonVariantType.Copy(var Dest: TVarData; const Source: TVarData; const Indirect: Boolean);
var
  Saved: TVarData;
begin
  Saved := VarDataFromVariant(Variant(Source))^;
  TInterlocked.Increment(TJsonVariantData(Saved).Owner.FRefCount);
  VarClear(Variant(Dest));
  Dest := Saved;
end;

procedure TJsonVariantType.ToJson(W: TJsonWriter; Value: PVarData);
begin
  TJsonVariantData(Value^).Owner.WriteValue(TJsonVariantData(Value^).Index, W);
end;

procedure TJsonVariantType.CastTo(var Dest: TVarData; const Source: TVarData; const AVarType: TVarType);
var
  Text: RawUtf8;
begin
  Text := TJsonVariantData(Source).Owner.JsonText(TJsonVariantData(Source).Index);
  RawUtf8ToVariant(Text, Dest, AVarType);
end;

function TJsonVariantType.IntGet(var Dest: TVarData; const Instance: TVarData;
  Name: PAnsiChar; NameLen: PtrInt; NoException: Boolean): Boolean;
var
  View, Field: TJsonValue;
  Key: RawUtf8;
  N: PJsonNode;
begin
  View := JsonView(Variant(Instance));
  If (NameLen > 4) and (Name[0] = '_') then begin
    If PropNameEquals(Name, '_count', NameLen, 6) then begin
      Variant(Dest) := View.Count;
      exit(true);
    end;
    If PropNameEquals(Name, '_kind', NameLen, 5) then begin
      If View.Kind = jkArray then Variant(Dest) := Ord(dvArray) else Variant(Dest) := Ord(dvObject);
      exit(true);
    end;
    If PropNameEquals(Name, '_json', NameLen, 5) then begin
      Variant(Dest) := View.FOwner.JsonText(View.FIndex);
      exit(true);
    end;
  end;
  Field := Default(TJsonValue);
  If View.Kind = jkObject then begin
    N := View.FindNode(PUtf8Char(Name), NameLen);
    If N <> nil then begin
      Field.FOwner := View.FOwner;
      Field.FIndex := (NativeInt(N) - NativeInt(@View.FOwner.FNodes[0])) div SizeOf(TJsonNode);
    end;
  end else begin
    FastSetString(Key, Name, NameLen);
    Field := View.Get(Key);
  end;
  Result := Field.Kind <> jkMissing;
  AssignJsonValue(Dest, Field);
end;

function TJsonVariantType.DoFunction(var Dest: TVarData; const V: TVarData;
  const Name: {$IFDEF FPC}AnsiString{$ELSE}string{$ENDIF}; const Arguments: TVarDataArray): Boolean;
var
  View: TJsonValue;
  Key: RawUtf8;
  Index: Integer;
begin
  Result := true;
  If Length(Arguments) = 0 then begin
    // Match dvoReturnNullForUnknownProperty after IntGet misses.
    Variant(Dest) := Null;
    exit;
  end;
  If Length(Arguments) = 1 then begin
    If (Name = '_') or System.SysUtils.SameText(Name, 'Value') then begin
      View := JsonView(Variant(V));
      If VariantToInteger(Variant(Arguments[0]), Index) then
        AssignJsonValue(Dest, View.Item[Index])
      else begin
        Key := VariantToUtf8(Variant(Arguments[0]));
        AssignJsonValue(Dest, View.Get(Key));
      end;
      exit;
    end;
  end;
  Result := false;
end;

function TJsonVariantType.IsVoid(const V: TVarData): Boolean;
begin
  Result := JsonView(Variant(V)).Count = 0;
end;

initialization
  // Register with the RTL only. mORMot Lookup assumes borrowed IntGet results
  // and drops intermediate TVarData without Clear; our getters return owners.
  // Its generic serializer still dispatches ToJson via the RTL type registry.
  JsonVariantType := TJsonVariantType.Create;

end.
