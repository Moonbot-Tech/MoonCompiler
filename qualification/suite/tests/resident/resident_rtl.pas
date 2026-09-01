unit resident_rtl;

{ Семейство `rtl` — библиотека времени выполнения.

  Компилятор без своей библиотеки — половина договора. Здесь проверяется вторая
  половина: поток в памяти, кодировки, сведения о типах, календарь и примитивы
  синхронизации. Всё это код, который компилятор собрал сам себе, и ошибка в
  нём выглядит для программы точно так же, как ошибка в кодогенерации.

  Ничего, зависящего от настроек машины, здесь нет. Форматирование дат и чисел
  по локали, регистр вне ASCII, часовой пояс, текущее время — всё это свойства
  окружения, и слой их не касается: календарь берётся только через кодирование
  и раскодирование, а не через строки.

  Примитивы синхронизации проверяются на объектах, локальных для одной стадии
  одного потока. Это не поддавки: у блокировки, счётчика и монитора есть
  договор и без конкуренции — вложенный вход, парность, возвращаемое значение,
  — и вот он предъявляется. Конкуренцию же создаёт само кольцо, всеми своими
  потоками сразу. }

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
  SysUtils, Classes, SyncObjs, DateUtils, TypInfo, Generics.Collections,
  resident_core;

implementation

type
  { Класс со сведениями о себе: `published` заставляет компилятор построить
    таблицы, по которым его свойства видны на ходу. }
  TResidentSubject = class(TPersistent)
  private
    FCount: Integer;
    FTitle: string;
    FWeight: Int64;
    FFlag: Boolean;
  published
    property Count: Integer read FCount write FCount;
    property Title: string read FTitle write FTitle;
    property Weight: Int64 read FWeight write FWeight;
    property Flag: Boolean read FFlag write FFlag;
  end;

  TResidentRtlPocket = class(TResidentPocket)
  private
    FStream: TMemoryStream;
    FLock: TCriticalSection;
    FCounter: Int64;
    FRounds: Int64;
  public
    destructor Destroy; override;
  end;

destructor TResidentRtlPocket.Destroy;
begin
  FStream.Free;
  FLock.Free;
  inherited Destroy;
end;

{ Поток в памяти: позиция, размер и содержимое — три независимых обещания. }
procedure StageMemoryStream(Carrier: TResidentCarrier);
var
  Stream: TMemoryStream;
  Value, Back: Int64;
  I, Room: Integer;
  Ok: Boolean;
begin
  Stream := TMemoryStream.Create;
  try
    Room := 8 + (Carrier.Lap mod 24);
    for I := 0 to Room - 1 do
    begin
      Value := Carrier.Tag.Wide + I;
      Stream.WriteBuffer(Value, SizeOf(Value));
    end;
    Carrier.Feed(UInt64(Stream.Size));
    Carrier.Feed(UInt64(Stream.Position));
    Carrier.Feed(UInt64(Ord(Stream.Size = Int64(Room) * SizeOf(Int64))));

    { Перемотка в начало и чтение обратно: всё записанное обязано вернуться. }
    Stream.Position := 0;
    Ok := True;
    for I := 0 to Room - 1 do
    begin
      Stream.ReadBuffer(Back, SizeOf(Back));
      if Back <> Carrier.Tag.Wide + I then
        Ok := False;
    end;
    Carrier.Feed(UInt64(Ord(Ok)));
    Carrier.Feed(UInt64(Stream.Position));

    { Позиционирование от конца и от текущего места. }
    Carrier.Feed(UInt64(Stream.Seek(Int64(0), soFromEnd)));
    Carrier.Feed(UInt64(Stream.Seek(-SizeOf(Int64), soFromCurrent)));
    Stream.ReadBuffer(Back, SizeOf(Back));
    Carrier.Feed(UInt64(Back));
    Carrier.Feed(UInt64(Ord(Back = Carrier.Tag.Wide + Room - 1)));

    { Усечение обязано обрезать хвост и подвинуть позицию в берега. }
    Stream.Size := SizeOf(Int64);
    Carrier.Feed(UInt64(Stream.Size));
    Stream.Position := 0;
    Stream.ReadBuffer(Back, SizeOf(Back));
    Carrier.Feed(UInt64(Back));
  finally
    Stream.Free;
  end;
end;

{ Перекачка между потоками: сколько ушло, столько и пришло, байт в байт. }
procedure StageStreamCopy(Carrier: TResidentCarrier);
var
  Source, Target: TMemoryStream;
  Data: TBytes;
  I, Room: Integer;
  Ok: Boolean;
begin
  Source := TMemoryStream.Create;
  Target := TMemoryStream.Create;
  try
    Room := 32 + (Carrier.Lap mod 96);
    SetLength(Data, Room);
    for I := 0 to Room - 1 do
      Data[I] := Byte((Carrier.Tag.Wide + I) and $FF);
    Source.WriteBuffer(Data[0], Room);

    Source.Position := 0;
    Carrier.Feed(UInt64(Target.CopyFrom(Source, Source.Size)));
    Carrier.Feed(UInt64(Ord(Target.Size = Source.Size)));

    Ok := CompareMem(Source.Memory, Target.Memory, Room);
    Carrier.Feed(UInt64(Ord(Ok)));

    { Перекачка нуля байт с текущей позиции переносит остаток целиком. }
    Source.Position := 0;
    Target.Position := 0;
    Target.Size := 0;
    Carrier.Feed(UInt64(Target.CopyFrom(Source, 0)));
    Carrier.Feed(UInt64(Target.Size));
  finally
    Source.Free;
    Target.Free;
  end;
end;

{ Поток, живущий между оборотами: дописанное на прошлом обороте обязано быть на
  месте и на следующем. }
procedure StageStreamAcrossLaps(Carrier: TResidentCarrier);
var
  Pocket: TResidentRtlPocket;
  Value, Back: Int64;
  WasSize: Int64;
begin
  Pocket := Carrier.PocketAs<TResidentRtlPocket>('rtl-stream');
  if Pocket.FStream = nil then
    Pocket.FStream := TMemoryStream.Create;

  WasSize := Pocket.FStream.Size;
  Pocket.FStream.Position := WasSize;
  Value := Carrier.Tag.Wide + Carrier.Lap;
  Pocket.FStream.WriteBuffer(Value, SizeOf(Value));
  Carrier.Feed(UInt64(Pocket.FStream.Size));
  Carrier.Feed(UInt64(Ord(Pocket.FStream.Size = WasSize + SizeOf(Int64))));

  { Самая первая запись обязана лежать там же, где её оставили. }
  Pocket.FStream.Position := 0;
  Pocket.FStream.ReadBuffer(Back, SizeOf(Back));
  Carrier.Feed(UInt64(Back));

  Inc(Pocket.FRounds);
  Carrier.Feed(UInt64(Pocket.FRounds));

  { Дойдя до потолка, поток обнуляется — за прогон случается и рост, и сброс. }
  if Pocket.FStream.Size >= 512 then
  begin
    Pocket.FStream.Clear;
    Carrier.Feed(UInt64(Pocket.FStream.Size));
    Pocket.FRounds := 0;
  end;
end;

{ Кодировки: ASCII обязан пройти любой перегон без потерь, а длины в байтах —
  соответствовать выбранной кодировке. }
procedure StageEncoding(Carrier: TResidentCarrier);
var
  Source, Back: string;
  Utf8, Utf16: TBytes;
begin
  Source := Carrier.Text.Wide;

  Utf8 := TEncoding.UTF8.GetBytes(Source);
  Back := TEncoding.UTF8.GetString(Utf8);
  Carrier.Feed(UInt64(Cardinal(Length(Utf8))));
  Carrier.Feed(UInt64(Ord(Back = Source)));

  Utf16 := TEncoding.Unicode.GetBytes(Source);
  Back := TEncoding.Unicode.GetString(Utf16);
  Carrier.Feed(UInt64(Cardinal(Length(Utf16))));
  Carrier.Feed(UInt64(Ord(Back = Source)));
  { Каждый символ ASCII занимает два байта в UTF-16 и один в UTF-8. }
  Carrier.Feed(UInt64(Ord(Length(Utf16) = Length(Source) * 2)));
  Carrier.Feed(UInt64(Ord(Length(Utf8) = Length(Source))));

  Utf8 := TEncoding.ASCII.GetBytes(Source);
  Carrier.Feed(UInt64(Cardinal(Length(Utf8))));
  Carrier.Feed(UInt64(Ord(TEncoding.ASCII.GetString(Utf8) = Source)));

  { Пустая строка обязана дать пустой набор байт, а не отказ. }
  Utf8 := TEncoding.UTF8.GetBytes('');
  Carrier.Feed(UInt64(Cardinal(Length(Utf8))));
end;

{ Набор байт: своя длина, своё копирование, свои границы. }
procedure StageBytes(Carrier: TResidentCarrier);
var
  Data, Twin: TBytes;
  I, Room: Integer;
  Sum: UInt64;
begin
  Room := 16 + (Carrier.Lap mod 32);
  SetLength(Data, Room);
  for I := 0 to Room - 1 do
    Data[I] := Byte((Carrier.Tag.Wide + I * 3) and $FF);

  Sum := 0;
  for I := 0 to Room - 1 do
    Sum := Sum + Data[I];
  Carrier.Feed(Sum);
  Carrier.Feed(UInt64(Cardinal(Length(Data))));

  Twin := System.Copy(Data, 0, Room);
  Carrier.Feed(UInt64(Ord(CompareMem(@Data[0], @Twin[0], Room))));
  Twin[0] := Byte(Twin[0] + 1);
  Carrier.Feed(UInt64(Ord(Data[0] <> Twin[0])));

  { Усечение и рост: голова обязана уцелеть, хвост при росте — обнулиться. }
  SetLength(Twin, 4);
  Carrier.Feed(UInt64(Twin[3]));
  SetLength(Twin, 8);
  Carrier.Feed(UInt64(Twin[7]));
  Carrier.Feed(UInt64(Cardinal(Length(Twin))));
end;

{ Календарь: кодирование и раскодирование даты — чистая арифметика по правилам
  календаря, без единого обращения к настройкам машины. }
procedure StageCalendar(Carrier: TResidentCarrier);
var
  Stamp: TDateTime;
  Y, M, D: Word;
  Shift: Integer;
begin
  Stamp := EncodeDate(2000, 1, 1);
  DecodeDate(Stamp, Y, M, D);
  Carrier.Feed(UInt64(Y));
  Carrier.Feed(UInt64(M));
  Carrier.Feed(UInt64(D));
  Carrier.Feed(UInt64(Cardinal(DayOfWeek(Stamp))));

  { Високосный год: последний день февраля обязан быть двадцать девятым. }
  Carrier.Feed(UInt64(Ord(IsLeapYear(2000))));
  Carrier.Feed(UInt64(Ord(IsLeapYear(1900))));
  Carrier.Feed(UInt64(Ord(IsLeapYear(2024))));
  Carrier.Feed(UInt64(Ord(IsLeapYear(2023))));
  Carrier.Feed(UInt64(Cardinal(DaysInAMonth(2000, 2))));
  Carrier.Feed(UInt64(Cardinal(DaysInAMonth(1900, 2))));

  { Сдвиг на сутки и обратно обязан вернуть в ту же точку. }
  Shift := 1 + (Carrier.Lap mod 400);
  Stamp := IncDay(EncodeDate(2000, 1, 1), Shift);
  DecodeDate(Stamp, Y, M, D);
  Carrier.Feed(UInt64(Y));
  Carrier.Feed(UInt64(M));
  Carrier.Feed(UInt64(D));
  Carrier.Feed(UInt64(Cardinal(DaysBetween(EncodeDate(2000, 1, 1), Stamp))));
  Carrier.Feed(UInt64(Ord(IncDay(Stamp, -Shift) = EncodeDate(2000, 1, 1))));

  { Граница месяца и года — самое частое место ошибок в календаре. }
  Carrier.Feed(UInt64(Ord(IncDay(EncodeDate(1999, 12, 31), 1) =
                          EncodeDate(2000, 1, 1))));
  Carrier.Feed(UInt64(Ord(IncMonth(EncodeDate(2000, 1, 31), 1) =
                          EncodeDate(2000, 2, 29))));
end;

{ Сведения о типах: имя, род и границы обязаны быть на месте и совпадать с тем,
  что видно из языка. }
procedure StageTypeInfo(Carrier: TResidentCarrier);
var
  Info: PTypeInfo;
  Data: PTypeData;
begin
  Info := TypeInfo(Int64);
  Carrier.Feed(UInt64(Cardinal(Ord(Info^.Kind))));
  Carrier.FeedWide(string(Info^.Name));

  Info := TypeInfo(string);
  Carrier.Feed(UInt64(Cardinal(Ord(Info^.Kind))));

  Info := TypeInfo(Boolean);
  Carrier.Feed(UInt64(Cardinal(Ord(Info^.Kind))));
  Data := GetTypeData(Info);
  Carrier.Feed(UInt64(Cardinal(Data^.MinValue)));
  Carrier.Feed(UInt64(Cardinal(Data^.MaxValue)));

  Info := TypeInfo(Byte);
  Data := GetTypeData(Info);
  Carrier.Feed(UInt64(Cardinal(Data^.MinValue)));
  Carrier.Feed(UInt64(Cardinal(Data^.MaxValue)));
  Carrier.Feed(UInt64(Cardinal(Ord(Data^.OrdType))));

  Info := TypeInfo(SmallInt);
  Data := GetTypeData(Info);
  Carrier.Feed(UInt64(Cardinal(Data^.MinValue)));
  Carrier.Feed(UInt64(Cardinal(Data^.MaxValue)));
end;

{ Свойства, видимые на ходу: компилятор построил таблицы, и они обязаны
  описывать ровно то, что объявлено. }
procedure StageProperties(Carrier: TResidentCarrier);
var
  Subject: TResidentSubject;
  Props: PPropList;
  Count, I: Integer;
  Prop: PPropInfo;
begin
  Subject := TResidentSubject.Create;
  try
    Subject.Count := Carrier.Serial;
    Subject.Title := Carrier.Text.Wide;
    Subject.Weight := Carrier.Tag.Wide;
    Subject.Flag := True;

    Count := GetPropList(Subject.ClassInfo, Props);
    try
      Carrier.Feed(UInt64(Cardinal(Count)));
      for I := 0 to Count - 1 do
      begin
        Carrier.FeedWide(string(Props^[I]^.Name));
        Carrier.Feed(UInt64(Cardinal(Ord(Props^[I]^.PropType^.Kind))));
      end;
    finally
      FreeMem(Props);
    end;

    { Чтение и запись через таблицы обязаны совпасть с прямым обращением. }
    Prop := GetPropInfo(Subject.ClassInfo, 'Count');
    Carrier.Feed(UInt64(Ord(Prop <> nil)));
    Carrier.Feed(UInt64(Cardinal(GetOrdProp(Subject, Prop))));
    SetOrdProp(Subject, Prop, 4242);
    Carrier.Feed(UInt64(Cardinal(Subject.Count)));

    Prop := GetPropInfo(Subject.ClassInfo, 'Title');
    Carrier.FeedWide(GetStrProp(Subject, Prop));
    SetStrProp(Subject, Prop, 'renamed');
    Carrier.FeedWide(Subject.Title);

    Prop := GetPropInfo(Subject.ClassInfo, 'Weight');
    Carrier.Feed(UInt64(GetInt64Prop(Subject, Prop)));

    { Отсутствующее свойство обязано не находиться, а не давать что попало. }
    Carrier.Feed(UInt64(Ord(GetPropInfo(Subject.ClassInfo, 'Missing') = nil)));
  finally
    Subject.Free;
  end;
end;

{ Метка-идентификатор: разбор и сборка строкового вида обязаны быть взаимно
  обратными. }
procedure StageGuid(Carrier: TResidentCarrier);
var
  Left, Right: TGUID;
  Text: string;
begin
  { Разбор строкового вида кольцом не проверяется: на этом компиляторе
    `StringToGUID` отвергает любой правильный вход, и стадия отказывала бы
    каждый оборот, заслоняя всё остальное. Дефект предъявлен отдельной находкой
    со своим пробником; здесь остаётся то, что обязано работать независимо, —
    сборка строкового вида, равенство и пустая метка. }
  Left := TGUID.Empty;
  Left.D1 := $4D5A0001;
  Left.D2 := $1234;
  Left.D3 := $5678;
  Left.D4[0] := Byte(Carrier.Serial and $FF);
  Left.D4[7] := $FF;

  Text := GUIDToString(Left);
  Carrier.FeedWide(Text);
  Carrier.Feed(UInt64(Cardinal(Length(Text))));
  Carrier.Feed(UInt64(Ord(Length(Text) = 38)));
  Carrier.Feed(UInt64(Ord(Text[1] = '{')));
  Carrier.Feed(UInt64(Ord(Text[38] = '}')));
  Carrier.Feed(UInt64(Cardinal(SizeOf(TGUID))));
  Carrier.Feed(UInt64(Left.D1));
  Carrier.Feed(UInt64(Left.D2));
  Carrier.Feed(UInt64(Left.D3));
  Carrier.Feed(UInt64(Left.D4[7]));

  Right := Left;
  Carrier.Feed(UInt64(Ord(IsEqualGUID(Left, Right))));
  Right.D1 := Right.D1 + 1;
  Carrier.Feed(UInt64(Ord(IsEqualGUID(Left, Right))));
  Carrier.Feed(UInt64(Ord(GUIDToString(Right) <> Text)));

  Left := TGUID.Empty;
  Carrier.Feed(UInt64(Left.D1));
  Carrier.Feed(UInt64(Ord(IsEqualGUID(Left, TGUID.Empty))));
  Carrier.Feed(UInt64(Ord(Left.IsEmpty)));
end;

{ Блокировка без конкурентов: у неё есть договор и в одиночестве — вложенный
  вход обязан требовать столько же выходов, сколько было входов. }
procedure StageCriticalSection(Carrier: TResidentCarrier);
var
  Lock: TCriticalSection;
  Trail: Int64;
begin
  Lock := TCriticalSection.Create;
  try
    Trail := 0;
    Lock.Enter;
    try
      Trail := Trail * 10 + 1;
      { Повторный вход тем же потоком обязан пройти без ожидания. }
      Lock.Enter;
      try
        Trail := Trail * 10 + 2;
      finally
        Lock.Leave;
      end;
      Trail := Trail * 10 + 3;
    finally
      Lock.Leave;
    end;
    Carrier.Feed(UInt64(Trail));

    { Проба свободной блокировки обязана удаться, а занятой тем же потоком —
      тоже удаться, потому что блокировка рекурсивна. }
    Carrier.Feed(UInt64(Ord(Lock.TryEnter)));
    Carrier.Feed(UInt64(Ord(Lock.TryEnter)));
    Lock.Leave;
    Lock.Leave;
  finally
    Lock.Free;
  end;
end;

{ Монитор объекта: тот же договор, но встроенный в сам объект. }
procedure StageMonitor(Carrier: TResidentCarrier);
var
  Subject: TResidentSubject;
  Trail: Int64;
begin
  Subject := TResidentSubject.Create;
  try
    { Вложенный вход тем же потоком здесь НЕ проверяется, и это осознанно: на
      этом компиляторе он вешает поток намертво, а кольцо обязано доезжать до
      отчёта. Такое поведение предъявляется отдельным пробником, а не ценой
      всего прогона. }
    Trail := 0;
    TMonitor.Enter(Subject);
    try
      Trail := Trail * 10 + 1;
    finally
      TMonitor.Exit(Subject);
    end;
    TMonitor.Enter(Subject);
    try
      Trail := Trail * 10 + 2;
    finally
      TMonitor.Exit(Subject);
    end;
    Carrier.Feed(UInt64(Trail));
    Carrier.Feed(UInt64(Ord(TMonitor.TryEnter(Subject))));
    TMonitor.Exit(Subject);
  finally
    Subject.Free;
  end;
end;

{ Неделимые операции над локальной переменной: без конкурентов их результат
  известен точно, и он обязан совпасть с обычной арифметикой. }
procedure StageInterlocked(Carrier: TResidentCarrier);
var
  Counter: Int64;
  Slot: Integer;
  Was: Int64;
begin
  Counter := Carrier.Tag.Wide;
  Was := TInterlocked.Increment(Counter);
  Carrier.Feed(UInt64(Was));
  Carrier.Feed(UInt64(Ord(Was = Carrier.Tag.Wide + 1)));
  Carrier.Feed(UInt64(TInterlocked.Decrement(Counter)));
  Carrier.Feed(UInt64(Ord(Counter = Carrier.Tag.Wide)));

  Carrier.Feed(UInt64(TInterlocked.Add(Counter, 10)));
  Carrier.Feed(UInt64(Counter));

  { Обмен возвращает прежнее значение, а не новое. }
  Was := TInterlocked.Exchange(Counter, Int64(777));
  Carrier.Feed(UInt64(Was));
  Carrier.Feed(UInt64(Counter));

  { Условный обмен срабатывает только при совпадении ожидаемого. }
  Was := TInterlocked.CompareExchange(Counter, Int64(888), Int64(777));
  Carrier.Feed(UInt64(Was));
  Carrier.Feed(UInt64(Counter));
  Was := TInterlocked.CompareExchange(Counter, Int64(999), Int64(777));
  Carrier.Feed(UInt64(Was));
  Carrier.Feed(UInt64(Counter));

  Slot := Carrier.Serial;
  Carrier.Feed(UInt64(Cardinal(TInterlocked.Increment(Slot))));
  Carrier.Feed(UInt64(Cardinal(Slot)));
end;

{ Счётчик, живущий в кармане: он обязан считать обороты без единой потери, и
  считается неделимо — хотя карман и принадлежит одному носителю. }
procedure StageCounterAcrossLaps(Carrier: TResidentCarrier);
var
  Pocket: TResidentRtlPocket;
begin
  Pocket := Carrier.PocketAs<TResidentRtlPocket>('rtl-counter');
  if Pocket.FLock = nil then
    Pocket.FLock := TCriticalSection.Create;

  Pocket.FLock.Enter;
  try
    Inc(Pocket.FCounter);
  finally
    Pocket.FLock.Leave;
  end;

  Carrier.Feed(UInt64(Pocket.FCounter));
  Carrier.Feed(UInt64(TInterlocked.Read(Pocket.FCounter)));
  Carrier.Feed(UInt64(Ord(Pocket.FCounter = Int64(Carrier.Lap) + 1)));
end;

{ Список строк через поток: сохранённое и загруженное обязано совпасть. }
procedure StagePersist(Carrier: TResidentCarrier);
var
  Source, Back: TStringList;
  Stream: TMemoryStream;
  I: Integer;
  Ok: Boolean;
begin
  Source := TStringList.Create;
  Back := TStringList.Create;
  Stream := TMemoryStream.Create;
  try
    for I := 0 to 5 do
      Source.Add('line-' + IntToStr(I) + '-' + IntToStr(Carrier.Serial));
    Source.SaveToStream(Stream, TEncoding.UTF8);
    Carrier.Feed(UInt64(Stream.Size));

    Stream.Position := 0;
    Back.LoadFromStream(Stream, TEncoding.UTF8);
    Carrier.Feed(UInt64(Cardinal(Back.Count)));
    Ok := Back.Count = Source.Count;
    for I := 0 to Back.Count - 1 do
      if (I < Source.Count) and (Back[I] <> Source[I]) then
        Ok := False;
    Carrier.Feed(UInt64(Ord(Ok)));
    Carrier.FeedWide(Back[0]);
  finally
    Source.Free;
    Back.Free;
    Stream.Free;
  end;
end;

{ Исключение как объект: класс, сообщение и приведение к строке. }
procedure StageExceptionShape(Carrier: TResidentCarrier);
var
  Name, Text: string;
begin
  Name := '';
  Text := '';
  try
    raise EInvalidOperation.Create('resident: shaped');
  except
    on E: Exception do
    begin
      Name := E.ClassName;
      Text := E.Message;
      Carrier.Feed(UInt64(Ord(E is EInvalidOperation)));
      Carrier.Feed(UInt64(Ord(E.InheritsFrom(Exception))));
      Carrier.Feed(UInt64(Ord(E.ClassType = EInvalidOperation)));
      Carrier.FeedWide(E.ClassParent.ClassName);
    end;
  end;
  Carrier.FeedWide(Name);
  Carrier.FeedWide(Text);
  Carrier.Feed(UInt64(Cardinal(Length(Name))));
end;

initialization
  ResidentRegisterStage('rtl-bytes', @StageBytes);
  ResidentRegisterStage('rtl-calendar', @StageCalendar);
  ResidentRegisterStage('rtl-counter-across-laps', @StageCounterAcrossLaps);
  ResidentRegisterStage('rtl-critical-section', @StageCriticalSection);
  ResidentRegisterStage('rtl-encoding', @StageEncoding);
  ResidentRegisterStage('rtl-exception-shape', @StageExceptionShape);
  ResidentRegisterStage('rtl-guid', @StageGuid);
  ResidentRegisterStage('rtl-interlocked', @StageInterlocked);
  ResidentRegisterStage('rtl-memory-stream', @StageMemoryStream);
  ResidentRegisterStage('rtl-monitor', @StageMonitor);
  ResidentRegisterStage('rtl-persist', @StagePersist);
  ResidentRegisterStage('rtl-properties', @StageProperties);
  ResidentRegisterStage('rtl-stream-across-laps', @StageStreamAcrossLaps);
  ResidentRegisterStage('rtl-stream-copy', @StageStreamCopy);
  ResidentRegisterStage('rtl-type-info', @StageTypeInfo);

end.
