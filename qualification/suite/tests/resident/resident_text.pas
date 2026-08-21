unit resident_text;

{ Семейство `text` — строки, кодировки и ширины.

  Строка в Delphi — не буфер, а договор: ширина символа, кодовая страница,
  счётчик ссылок и разделяемый буфер, который обязан отделиться ровно в тот
  момент, когда кто-то собрался писать. Здесь проверяется именно договор.

  Разделение буфера наблюдается сравнением адресов первых символов. Сам адрес
  недетерминирован и в дайджест не идёт никогда — идёт только факт «тот же
  буфер или уже другой», а он свойство языка, а не запуска.

  Всё содержимое строк — ASCII по построению. Это не осторожность, а условие
  честности: `AnsiUpperCase` и конверсии широкой строки в байтовую вне ASCII
  зависят от кодовой страницы машины, и слой обвинял бы компилятор в настройках
  системы. Где нужна смена регистра — берутся только те функции, что для ASCII
  определены однозначно. }

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch anonymousfunctions}
  {$modeswitch functionreferences}
  {$modeswitch INLINEVARS}
{$endif}
{$Q-}{$R-}

interface

uses
  SysUtils, Classes, StrUtils, Generics.Collections, resident_core;

implementation

type
  TResidentTextPocket = class(TResidentPocket)
  private
    FKept: string;
    FBytes: AnsiString;
    FRounds: Int64;
  end;

{ Адрес первого символа: сам по себе он недетерминирован, поэтому наружу отдаётся
  только сравнение двух адресов — «один буфер или разные». }
function SameBuffer(const A, B: string): Boolean;
begin
  if (Length(A) = 0) or (Length(B) = 0) then
    Exit(Length(A) = Length(B));
  Result := Pointer(A) = Pointer(B);
end;

function SameBufferAnsi(const A, B: AnsiString): Boolean;
begin
  if (Length(A) = 0) or (Length(B) = 0) then
    Exit(Length(A) = Length(B));
  Result := Pointer(A) = Pointer(B);
end;

{ Рост до потолка и усечение обратно: за прогон случается и переезд буфера, и
  повторное занятие освободившейся памяти. }
procedure StageGrowTruncate(Carrier: TResidentCarrier);
var
  Text: TResidentText;
begin
  Text := Carrier.Text;
  if Length(Text.Wide) < 96 then
    Text.Wide := Text.Wide + 'a'
  else
    Text.Wide := System.Copy(Text.Wide, 1, 8);
  Text.Bytes := AnsiString(Text.Wide);
  Text.Utf8 := UTF8Encode(Text.Wide);
  Carrier.Text := Text;
  Carrier.FeedText(Text.Bytes);
  Carrier.Feed(UInt64(Cardinal(Length(Text.Wide))));
end;

{ Разделяемый буфер: присваивание не копирует, запись — обязана отделить. }
procedure StageCopyOnWrite(Carrier: TResidentCarrier);
var
  Source, Twin: string;
begin
  Source := Carrier.Text.Wide;
  Twin := Source;
  { Присваивание обязано оставить обоих на одном буфере. }
  Carrier.Feed(UInt64(Ord(SameBuffer(Source, Twin))));
  Carrier.Feed(UInt64(Cardinal(Length(Twin))));

  { Запись в один символ обязана отделить буфер и не задеть соседа. }
  if Length(Twin) > 0 then
  begin
    Twin[1] := 'z';
    Carrier.Feed(UInt64(Ord(SameBuffer(Source, Twin))));
    Carrier.Feed(UInt64(Word(Source[1])));
    Carrier.Feed(UInt64(Word(Twin[1])));
  end;

  { Явное отделение обязано сработать и когда сосед один. }
  Twin := Source;
  UniqueString(Twin);
  Carrier.Feed(UInt64(Ord(SameBuffer(Source, Twin))));
  Carrier.Feed(UInt64(Ord(Source = Twin)));
end;

{ Та же механика для байтовой строки: у неё свой буфер и своя кодовая страница. }
procedure StageCopyOnWriteAnsi(Carrier: TResidentCarrier);
var
  Source, Twin: AnsiString;
begin
  Source := Carrier.Text.Bytes;
  Twin := Source;
  Carrier.Feed(UInt64(Ord(SameBufferAnsi(Source, Twin))));
  if Length(Twin) > 0 then
  begin
    Twin[1] := 'q';
    Carrier.Feed(UInt64(Ord(SameBufferAnsi(Source, Twin))));
    Carrier.Feed(UInt64(Ord(Source[1])));
    Carrier.Feed(UInt64(Ord(Twin[1])));
  end;
  Carrier.Feed(UInt64(Cardinal(Length(Twin))));
end;

{ Ширина символа и элемента: контракт драйвера — вся программа в UTF-16. }
procedure StageWidths(Carrier: TResidentCarrier);
var
  Wide: string;
  Bytes: AnsiString;
  Small: UTF8String;
begin
  Wide := Carrier.Text.Wide;
  Bytes := Carrier.Text.Bytes;
  Small := Carrier.Text.Utf8;
  Carrier.Feed(UInt64(Cardinal(SizeOf(Wide[1]))));
  Carrier.Feed(UInt64(Cardinal(SizeOf(Bytes[1]))));
  Carrier.Feed(UInt64(Cardinal(SizeOf(Small[1]))));
  Carrier.Feed(UInt64(Cardinal(SizeOf(Char))));
  Carrier.Feed(UInt64(Cardinal(SizeOf(AnsiChar))));
  Carrier.Feed(UInt64(Cardinal(SizeOf(WideChar))));
  { Длина строки считается в символах, а не в байтах — и это тоже договор. }
  Carrier.Feed(UInt64(Cardinal(Length(Wide))));
  Carrier.Feed(UInt64(Cardinal(Length(Bytes))));
end;

{ Кодовая страница байтовой строки: она часть типа, а не свойство содержимого. }
procedure StageCodePage(Carrier: TResidentCarrier);
var
  Raw: RawByteString;
  Bytes: AnsiString;
  Small: UTF8String;
begin
  Bytes := Carrier.Text.Bytes;
  Small := Carrier.Text.Utf8;
  Raw := Bytes;
  Carrier.Feed(UInt64(Cardinal(StringCodePage(Bytes))));
  Carrier.Feed(UInt64(Cardinal(StringCodePage(Small))));
  Carrier.Feed(UInt64(Cardinal(StringElementSize(Bytes))));
  Carrier.Feed(UInt64(Cardinal(StringElementSize(Small))));
  Carrier.Feed(UInt64(Cardinal(Length(Raw))));
  { Присваивание между строками разных кодовых страниц обязано перекодировать
    содержимое, а не переставить ярлык. }
  Carrier.Feed(UInt64(Ord(Length(Small) >= Length(Bytes))));
end;

{ Кольцевой перегон широкая → байтовая → широкая: ASCII обязан вернуться
  побайтово тем же. }
procedure StageAnsiRoundTrip(Carrier: TResidentCarrier);
var
  Start, Back: string;
  Middle: AnsiString;
begin
  Start := Carrier.Text.Wide;
  Middle := AnsiString(Start);
  Back := string(Middle);
  Carrier.Feed(UInt64(Ord(Start = Back)));
  Carrier.Feed(UInt64(Cardinal(Length(Middle))));
  Carrier.FeedWide(Back);
end;

{ То же через UTF-8: длина в байтах может вырасти, содержимое — нет. }
procedure StageUtf8RoundTrip(Carrier: TResidentCarrier);
var
  Start, Back: string;
  Middle: UTF8String;
begin
  Start := Carrier.Text.Wide;
  Middle := UTF8Encode(Start);
  Back := UTF8ToString(Middle);
  Carrier.Feed(UInt64(Ord(Start = Back)));
  Carrier.Feed(UInt64(Cardinal(Length(Middle))));
  Carrier.Feed(UInt64(Ord(Length(Middle) >= Length(Start))));
end;

{ Нарезка: `Copy` за границами обязана усечься, а не выйти за буфер. }
procedure StageSlice(Carrier: TResidentCarrier);
var
  Source, Part: string;
  Len: Integer;
begin
  Source := Carrier.Text.Wide;
  Len := Length(Source);

  Part := System.Copy(Source, 1, 4);
  Carrier.Feed(UInt64(Cardinal(Length(Part))));
  Carrier.FeedWide(Part);

  { Запрос длиннее остатка обязан вернуть остаток, а не мусор за концом. }
  Part := System.Copy(Source, Len - 1, 1000);
  Carrier.Feed(UInt64(Cardinal(Length(Part))));

  { Начало за концом строки обязано дать пустую строку. }
  Part := System.Copy(Source, Len + 10, 5);
  Carrier.Feed(UInt64(Cardinal(Length(Part))));
  Carrier.Feed(UInt64(Ord(Part = '')));

  { Нулевая длина — тоже пустая строка, а не «до конца». }
  Part := System.Copy(Source, 1, 0);
  Carrier.Feed(UInt64(Cardinal(Length(Part))));
end;

{ Вставка и удаление: длина обязана меняться ровно на длину куска. }
procedure StageInsertDelete(Carrier: TResidentCarrier);
var
  Work: string;
  Before, Mid, After: Integer;
begin
  Work := Carrier.Text.Wide;
  Before := Length(Work);

  Insert('QRS', Work, 2);
  Mid := Length(Work);
  Carrier.Feed(UInt64(Cardinal(Mid - Before)));
  Carrier.FeedWide(System.Copy(Work, 1, 6));

  Delete(Work, 2, 3);
  After := Length(Work);
  Carrier.Feed(UInt64(Cardinal(Mid - After)));
  Carrier.Feed(UInt64(Ord(After = Before)));
  Carrier.Feed(UInt64(Ord(Work = Carrier.Text.Wide)));

  { Удаление за границей обязано быть безвредным. }
  Delete(Work, Length(Work) + 5, 3);
  Carrier.Feed(UInt64(Cardinal(Length(Work))));
end;

{ Сравнения: только ASCII, поэтому порядок определён однозначно и не зависит
  от настроек машины. }
procedure StageCompare(Carrier: TResidentCarrier);
var
  A, B: string;
begin
  A := 'abcdef';
  B := 'abcdeg';
  Carrier.Feed(UInt64(Ord(A = B)));
  Carrier.Feed(UInt64(Ord(A < B)));
  Carrier.Feed(UInt64(Ord(A > B)));
  Carrier.Feed(UInt64(Ord(A <> B)));
  Carrier.Feed(UInt64(Cardinal(Ord(CompareStr(A, B) < 0))));
  Carrier.Feed(UInt64(Cardinal(Ord(CompareStr(B, A) > 0))));
  Carrier.Feed(UInt64(Cardinal(Ord(CompareStr(A, A) = 0))));
  { Регистронезависимое сравнение на ASCII определено однозначно. }
  Carrier.Feed(UInt64(Cardinal(Ord(CompareText('ABC', 'abc') = 0))));
  { Строка короче своего же префикса-продолжения. }
  Carrier.Feed(UInt64(Ord('abc' < 'abcd')));
  Carrier.Feed(UInt64(Ord('' < 'a')));
end;

{ Цепочка конкатенаций: буфер переезжает многократно, содержимое обязано
  накапливаться ровно в том порядке, в каком его добавляли. }
procedure StageConcatChain(Carrier: TResidentCarrier);
var
  Work: string;
  I, Rounds: Integer;
begin
  Rounds := 4 + (Carrier.Lap mod 9);
  Work := '';
  for I := 1 to Rounds do
    Work := Work + Char(Word(Ord('a') + (I mod 26))) + '-';
  Carrier.Feed(UInt64(Cardinal(Length(Work))));
  Carrier.FeedWide(Work);

  { Конкатенация в другом порядке даёт другую строку — порядок здесь значим. }
  Carrier.Feed(UInt64(Ord(Work + 'x' = 'x' + Work)));
  Carrier.Feed(UInt64(Ord(Length(Work + 'x') = Length('x' + Work))));
end;

{ Посимвольный обход: индекс строки — с единицы, и это часть договора. }
procedure StageCharWalk(Carrier: TResidentCarrier);
var
  Source: string;
  I: Integer;
  Sum: UInt64;
begin
  Source := Carrier.Text.Wide;
  Sum := 0;
  for I := 1 to Length(Source) do
    Sum := Sum + UInt64(Word(Source[I]));
  Carrier.Feed(Sum);
  Carrier.Feed(UInt64(Cardinal(Low(string))));
  Carrier.Feed(UInt64(Cardinal(Length(Source))));

  { Обход по значению обязан дать ту же сумму, что и по индексу. }
  Sum := 0;
  for var Ch in Source do
    Sum := Sum + UInt64(Word(Ch));
  Carrier.Feed(Sum);
end;

{ Форматирование: спецификаторы целых и строк определены однозначно, дробных
  здесь нет — их вид зависит от настроек, а не от компилятора. }
procedure StageFormat(Carrier: TResidentCarrier);
var
  Made: string;
  Tag: TResidentTag;
begin
  Tag := Carrier.Tag;
  Made := Format('%d|%x|%s|%.4d', [Tag.Unsigned, Tag.Unsigned,
                                   'abc', Carrier.Serial]);
  Carrier.FeedWide(Made);
  Carrier.Feed(UInt64(Cardinal(Length(Made))));

  { Порядковые ссылки на аргументы: номер обязан выбирать аргумент, а не
    сдвигать курсор. }
  Made := Format('%1:s-%0:d-%1:s', [Carrier.Serial, 'k']);
  Carrier.FeedWide(Made);

  { Ширина и выравнивание. }
  Made := Format('[%8s][%-8s]', ['ab', 'cd']);
  Carrier.FeedWide(Made);
  Carrier.Feed(UInt64(Cardinal(Length(Made))));
end;

{ Целое в строку и обратно: перегон обязан быть точным на всём домене. }
procedure StageNumberText(Carrier: TResidentCarrier);
var
  Tag: TResidentTag;
  Made: string;
  Back: Int64;
  Ok: Boolean;
begin
  Tag := Carrier.Tag;
  Made := IntToStr(Tag.Wide);
  Back := StrToInt64(Made);
  Carrier.Feed(UInt64(Ord(Back = Tag.Wide)));
  Carrier.FeedWide(Made);

  Made := IntToStr(Tag.Narrow);
  Carrier.FeedWide(Made);
  Carrier.Feed(UInt64(Ord(StrToInt(Made) = Tag.Narrow)));

  Made := IntToHex(Tag.Unsigned, 4);
  Carrier.FeedWide(Made);
  Carrier.Feed(UInt64(Cardinal(Length(Made))));

  { Разбор заведомо непригодной строки обязан отказать, а не угадать. }
  Ok := TryStrToInt64('not-a-number', Back);
  Carrier.Feed(UInt64(Ord(Ok)));
  Ok := TryStrToInt64('  12  ', Back);
  Carrier.Feed(UInt64(Ord(Ok)));
end;

{ Замена подстроки: и первое вхождение, и все сразу. }
procedure StageReplace(Carrier: TResidentCarrier);
var
  Source, Made: string;
begin
  Source := 'ab-ab-ab';
  Made := StringReplace(Source, 'ab', 'xyz', []);
  Carrier.FeedWide(Made);
  Carrier.Feed(UInt64(Cardinal(Length(Made))));

  Made := StringReplace(Source, 'ab', 'xyz', [rfReplaceAll]);
  Carrier.FeedWide(Made);
  Carrier.Feed(UInt64(Cardinal(Length(Made))));

  { Замена на пустую строку обязана укоротить, а не оставить дыру. }
  Made := StringReplace(Source, '-', '', [rfReplaceAll]);
  Carrier.FeedWide(Made);

  { Искомого нет — строка обязана вернуться неизменной. }
  Made := StringReplace(Source, 'zz', 'q', [rfReplaceAll]);
  Carrier.Feed(UInt64(Ord(Made = Source)));
end;

{ Обрезка и регистр: только ASCII, поэтому результат однозначен. }
procedure StageTrimCase(Carrier: TResidentCarrier);
var
  Source: string;
begin
  Source := '  abcDEF  ';
  Carrier.FeedWide(Trim(Source));
  Carrier.FeedWide(TrimLeft(Source));
  Carrier.FeedWide(TrimRight(Source));
  Carrier.Feed(UInt64(Cardinal(Length(Trim(Source)))));

  Carrier.FeedWide(UpperCase('abcDEF'));
  Carrier.FeedWide(LowerCase('abcDEF'));
  Carrier.Feed(UInt64(Ord(UpperCase('abc') = 'ABC')));
  Carrier.Feed(UInt64(Ord(LowerCase('ABC') = 'abc')));

  { Строка из одних пробелов обязана обрезаться в пустую. }
  Carrier.Feed(UInt64(Cardinal(Length(Trim('     ')))));
end;

{ Поиск подстроки: позиция считается с единицы, отсутствие даёт ноль. }
procedure StageSearch(Carrier: TResidentCarrier);
var
  Source: string;
begin
  Source := 'abcdefabc';
  Carrier.Feed(UInt64(Cardinal(Pos('abc', Source))));
  Carrier.Feed(UInt64(Cardinal(Pos('abc', Source, 2))));
  Carrier.Feed(UInt64(Cardinal(Pos('zz', Source))));
  Carrier.Feed(UInt64(Cardinal(Pos('', Source))));
  Carrier.Feed(UInt64(Ord(ContainsStr(Source, 'def'))));
  Carrier.Feed(UInt64(Ord(StartsStr('abc', Source))));
  Carrier.Feed(UInt64(Ord(EndsStr('abc', Source))));
  Carrier.Feed(UInt64(Cardinal(LastDelimiter('c', Source))));
end;

{ Строитель строк: накопление через TStringBuilder — свой буфер, своя политика
  роста, а результат обязан совпасть с обычной конкатенацией до символа. }
procedure StageBuilder(Carrier: TResidentCarrier);
var
  Builder: TStringBuilder;
  Plain, Built: string;
  I, Rounds: Integer;
begin
  Rounds := 6 + (Carrier.Lap mod 11);
  Plain := '';
  Builder := TStringBuilder.Create;
  try
    for I := 1 to Rounds do
    begin
      Builder.Append('n').Append(I);
      Plain := Plain + 'n' + IntToStr(I);
    end;
    Built := Builder.ToString;
    Carrier.Feed(UInt64(Cardinal(Builder.Length)));
  finally
    Builder.Free;
  end;
  Carrier.Feed(UInt64(Ord(Built = Plain)));
  Carrier.Feed(UInt64(Cardinal(Length(Built))));
  Carrier.FeedWide(Built);
end;

{ Короткая строка: длина в первом байте, потолок 255 символов, усечение молча. }
procedure StageShortString(Carrier: TResidentCarrier);
var
  Short: ShortString;
  Filler: string;
begin
  Short := 'abc';
  Carrier.Feed(UInt64(Cardinal(Length(Short))));
  Carrier.Feed(UInt64(Cardinal(SizeOf(Short))));
  Carrier.Feed(UInt64(Ord(Short[1])));
  Carrier.Feed(UInt64(Ord(Short = 'abc')));

  { Больше потолка не влезет: длина обязана упереться в 255, а не переполнить
    счётчик длины. }
  Filler := StringOfChar('q', 300);
  Short := ShortString(AnsiString(Filler));
  { Тавтологию вида «длина короткой строки не больше 255» проверять нечего —
    её знает и компилятор. Смысл в другом: усечение обязано дать ровно потолок,
    а не остаток от 300. }
  Carrier.Feed(UInt64(Cardinal(Length(Short))));
  Carrier.Feed(UInt64(Cardinal(Ord(Length(Short) = 255))));
end;

{ Указатель на строку: нулевой терминатор обязан быть на месте, а длина по
  указателю — совпасть с длиной строки. }
procedure StagePointerText(Carrier: TResidentCarrier);
var
  Source: string;
  Bytes: AnsiString;
  Wide: PChar;
  Narrow: PAnsiChar;
begin
  Source := Carrier.Text.Wide;
  Bytes := Carrier.Text.Bytes;
  Wide := PChar(Source);
  Narrow := PAnsiChar(Bytes);

  Carrier.Feed(UInt64(Cardinal(StrLen(Wide))));
  Carrier.Feed(UInt64(Ord(StrLen(Wide) = Cardinal(Length(Source)))));
  Carrier.Feed(UInt64(Cardinal(Length(Bytes))));
  Carrier.Feed(UInt64(Ord(Narrow[Length(Bytes)] = #0)));
  if Length(Source) > 0 then
  begin
    Carrier.Feed(UInt64(Word(Wide[0])));
    Carrier.Feed(UInt64(Ord(Wide[0] = Source[1])));
  end;

  { Пустая строка обязана дать указатель на нулевой символ, а не на ничто. }
  Source := '';
  Wide := PChar(Source);
  Carrier.Feed(UInt64(Ord(Wide <> nil)));
  Carrier.Feed(UInt64(Word(Wide[0])));
end;

function CompareByCode(List: TStringList; Left, Right: Integer): Integer;
begin
  Result := CompareStr(List[Left], List[Right]);
end;

{ Список строк: порядок, поиск и сортировка — своим компаратором, поэтому
  результат не зависит от настроек машины. }
procedure StageStringList(Carrier: TResidentCarrier);
var
  List: TStringList;
  I, Found: Integer;
begin
  List := TStringList.Create;
  try
    List.Add('delta');
    List.Add('alpha');
    List.Add('charlie');
    List.Add('bravo');
    Carrier.Feed(UInt64(Cardinal(List.Count)));
    Carrier.FeedWide(List[0]);

    { Сортировка своим сравнением: только коды символов, никакой локали.
      Сравнение — обычная функция, а не анонимная: список ждёт именно её тип,
      и подстановка анонимной непереносима. }
    List.CustomSort(@CompareByCode);
    for I := 0 to List.Count - 1 do
      Carrier.FeedWide(List[I]);

    Found := List.IndexOf('charlie');
    Carrier.Feed(UInt64(Cardinal(Found)));
    Carrier.Feed(UInt64(Cardinal(List.IndexOf('missing') + 1)));

    List.Delete(0);
    Carrier.Feed(UInt64(Cardinal(List.Count)));
    Carrier.FeedWide(List.Text);
  finally
    List.Free;
  end;
end;

{ Разбор и сборка по разделителю: сколько кусков вышло и склеились ли обратно. }
procedure StageSplitJoin(Carrier: TResidentCarrier);
var
  Parts: System.TArray<string>;
  I: Integer;
  Joined: string;
begin
  Parts := 'a,bb,ccc,,e'.Split([',']);
  Carrier.Feed(UInt64(Cardinal(Length(Parts))));
  for I := 0 to High(Parts) do
  begin
    Carrier.Feed(UInt64(Cardinal(Length(Parts[I]))));
    Carrier.FeedWide(Parts[I]);
  end;

  Joined := string.Join(',', Parts);
  Carrier.Feed(UInt64(Ord(Joined = 'a,bb,ccc,,e')));
  Carrier.FeedWide(Joined);

  { Пустая строка даёт один пустой кусок, а не ноль кусков. }
  Parts := ''.Split([',']);
  Carrier.Feed(UInt64(Cardinal(Length(Parts))));
end;

{ Строка, положенная в карман, обязана дожить до следующего оборота ровно той
  же — включая длину и содержимое. }
procedure StageKeptText(Carrier: TResidentCarrier);
var
  Pocket: TResidentTextPocket;
  Fresh: string;
begin
  Pocket := Carrier.PocketAs<TResidentTextPocket>('text-kept');
  if Pocket.FRounds > 0 then
  begin
    Carrier.Feed(UInt64(Cardinal(Length(Pocket.FKept))));
    Carrier.FeedWide(Pocket.FKept);
    Carrier.Feed(UInt64(Ord(Length(Pocket.FBytes) = Length(Pocket.FKept))));
  end;

  Fresh := Carrier.Text.Wide + IntToStr(Carrier.Lap mod 10);
  Pocket.FKept := Fresh;
  Pocket.FBytes := AnsiString(Fresh);
  Inc(Pocket.FRounds);
  Carrier.Feed(UInt64(Pocket.FRounds));
  Carrier.Feed(UInt64(Ord(SameBuffer(Pocket.FKept, Fresh))));
end;

initialization
  ResidentRegisterStage('text-ansi-roundtrip', @StageAnsiRoundTrip);
  ResidentRegisterStage('text-builder', @StageBuilder);
  ResidentRegisterStage('text-char-walk', @StageCharWalk);
  ResidentRegisterStage('text-codepage', @StageCodePage);
  ResidentRegisterStage('text-compare', @StageCompare);
  ResidentRegisterStage('text-concat-chain', @StageConcatChain);
  ResidentRegisterStage('text-copy-on-write', @StageCopyOnWrite);
  ResidentRegisterStage('text-copy-on-write-ansi', @StageCopyOnWriteAnsi);
  ResidentRegisterStage('text-format', @StageFormat);
  ResidentRegisterStage('text-grow-truncate', @StageGrowTruncate);
  ResidentRegisterStage('text-insert-delete', @StageInsertDelete);
  ResidentRegisterStage('text-kept', @StageKeptText);
  ResidentRegisterStage('text-number', @StageNumberText);
  ResidentRegisterStage('text-pointer', @StagePointerText);
  ResidentRegisterStage('text-replace', @StageReplace);
  ResidentRegisterStage('text-search', @StageSearch);
  ResidentRegisterStage('text-shortstring', @StageShortString);
  ResidentRegisterStage('text-slice', @StageSlice);
  ResidentRegisterStage('text-split-join', @StageSplitJoin);
  ResidentRegisterStage('text-stringlist', @StageStringList);
  ResidentRegisterStage('text-trim-case', @StageTrimCase);
  ResidentRegisterStage('text-utf8-roundtrip', @StageUtf8RoundTrip);
  ResidentRegisterStage('text-widths', @StageWidths);

end.
