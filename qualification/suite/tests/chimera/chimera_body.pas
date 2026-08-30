unit chimera_body;

{             Quidquid latet apparebit, nil inultum remanebit.
                            Festina lente.

  Лист-юнит химеры: проводные типы и оснастка наблюдения.

  Роль этого юнита взята из живого кода дословно. В MoonBot есть юнит, который
  не подключает НИЧЕГО своего, и это условие его существования, а не признак
  аккуратности: межюнитная вставка тела работает только из юнита, стоящего ВНЕ
  кольца зависимостей. Прочие юниты проекта завязаны друг на друга кольцом, и
  вставка изнутри кольца мертва. Поэтому горячие методы записи живут здесь, а
  потребители подключают этот юнит напрямую, минуя алиасы.

  Химера повторяет и топологию, и содержимое. Ниже — запись ленты в
  шестнадцать байт, у которой направление сделки хранится ЗНАКОМ количества, а
  спрашивается чтением того же поля как беззнакового целого. Это намеренное
  совпадение двух имён на одном месте: вещественное поле и целочисленный взгляд
  на него. Решит оптимизатор, что запись через Single и чтение через Cardinal
  не могут указывать на одну память, — направление сделки поедет молча.

  Порядок методов внутри юнита тоже значим: тело обязано быть скомпилировано к
  точке вызова, иначе вставка не разворачивается. Листовые идут первыми.

  Здесь же — общая форма ответа органа и правила сверки. Каждая перенесённая
  работа живёт в химере не одним телом, а пятью (см. README), и все они
  отвечают одним и тем же набором величин: точные сверяются до бита, вещест-
  венные — до бита между тождественными телами и с допуском против независимо
  написанного оракула. }

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
  SysUtils, SyncObjs;

const
  { Своя шкала времени, а не заимствованная у библиотеки: сутки здесь часть
    контракта проверки, и правка библиотечной константы не должна двигать
    ожидаемые числа. }
  ChiSecsPerDay   = 86400.0;
  ChiMinsPerDay   = 1440.0;
  ChiTenthsPerDay = 864000.0;
  ChiTenthsPerMin = 600;

  { Две сделки одного направления по близкой цене, разошедшиеся во времени
    меньше чем на это, считаются одной. Значение и смысл — из ленты бота. }
  ChiSameTime = 0.2 / ChiSecsPerDay;

  { Свёртка наблюдений: биекция накопителя, поэтому единственный неверный бит
    не может сократиться по дороге. }
  ChiOffset = UInt64($CBF29CE484222325);
  ChiPrime  = UInt64($00000100000001B3);

  { Сколько величин орган предъявляет к сверке. Числа с запасом: лишняя
    незанятая ячейка не стоит ничего, а нехватка заставила бы урезать ответ
    органа под размер формы. }
  ChiExactCount = 24;
  ChiLooseCount = 24;

type
  TChiSide = (csSell, csBuy);

  { Широкая форма — та, в которой считают: время, цена и количество в двойной
    точности, направление отдельным полем. }
  TChiOrder = record
    Time:     TDateTime;
    Price:    Double;
    Quantity: Double;
    Side:     TChiSide;
    Fill:     Byte;
  end;

  { Узкая форма — та, в которой хранят и шлют. Шестнадцать байт, направление
    внутри знака количества. }
  TChiTrade = record
    Time:  TDateTime;
    Price: Single;
    Qty:   Single;
    function Quantity: Single; inline;
    function Side: TChiSide; inline;
    function IsBuy: Boolean; inline;
    function SameDirection(const Other: TChiTrade): Boolean; inline;
    procedure FromOrder(const O: TChiOrder); inline;
    procedure ToOrder(var O: TChiOrder); inline;
  end;
  PChiTrade = ^TChiTrade;

  TChiTape = array of TChiTrade;

  { Общая форма ответа органа. Точные величины — счётчики и решения, они
    обязаны совпасть до единицы у всех тел. Вещественные — накопители.
    Дайджест — свёртка последовательности принятых решений: он ловит случай,
    когда итоги сошлись, а дорога была разная. }
  TChiSum = record
    Exact:  array [0 .. ChiExactCount - 1] of Int64;
    Loose:  array [0 .. ChiLooseCount - 1] of Double;
    Digest: UInt64;
  end;

  { Детерминированный источник. Ни одного обращения к системному датчику:
    данные обязаны быть одинаковыми во всех сборках, иначе сравнивать нечего. }
  TChiSource = record
    State: UInt64;
    function NextWord: UInt64; inline;
    function NextBelow(ALimit: Integer): Integer; inline;
    function NextUnit: Double; inline;
  end;

{ Заводит источник. Отдельной функцией, а не методом: заполнять запись через
  метод — значит сперва прочитать её неинициализированной. }
function ChiSource(ASeed: UInt64): TChiSource; inline;

{ Пустой итог с засеянным накопителем свёртки. }
function ChiSumEmpty: TChiSum; inline;

{ Утверждение — жёсткое: оно не сравнивает сборку со сборкой, а предъявляет
  то, что верно само по себе. Первое нарушенное запоминается по имени, потому
  что число сломанных мест без имени первого бесполезно. }
procedure ChiClaim(Condition: Boolean; const What: string);
function ChiFailures: Integer;
function ChiFirstFailure: string;

{ Все различные нарушенные утверждения. Одно имя первого сообщения не
  показывает, сколько РАЗНЫХ мест сломалось, а это и есть первое, что нужно
  знать при разборе. }
function ChiFailureList: string;

{ Сверка тождественных тел: одни и те же действия в том же порядке, поэтому
  вещественные величины обязаны совпасть ДО БИТА. Любой допуск здесь был бы
  щелью, в которую уйдёт настоящая находка. }
procedure ChiSame(const A, B: TChiSum; const Who: string);

{ Сверка с независимо написанным оракулом: точные — до единицы, вещественные —
  с допуском, потому что порядок действий у оракула свой. }
procedure ChiClose(const A, B: TChiSum; const Who: string);

function ChiMix(Acc: UInt64; Value: Int64): UInt64;
function ChiNear(const A, B: Double; Tol: Double = 1E-9): Boolean;

{ Свёртка итога органа в одно число для печати. }
function ChiFold(const S: TChiSum): Int64;

{ ═══ Покрытие ═══════════════════════════════════════════════════════════

  Строка переписи считается закрытой не тогда, когда для неё написан код, а
  тогда, когда этот код ИСПОЛНИЛСЯ. Разница не теоретическая: за время
  постройки химеры дважды случалось, что перенесённая форма молча работала
  вхолостую — партия ни разу не перекрывалась с историей, и весь двоичный
  поиск на стыке не исполнялся ни разу. Программа при этом печатала OK.

  Поэтому каждый орган отмечает и себя, и каждую ветку, ради которой форма
  переносилась. Отметки печатаются машиночитаемо, и гейт сверяет их с
  переписью: строка без отметки — незакрытая строка, отметка без строки —
  неизвестный идентификатор. И то и другое останавливает прогон.

  Счётчики ветвей в многопоточных прогонах плавают от расписания, поэтому
  предъявляется только факт «больше нуля», а не точное число. }

{ Орган отработал по строке переписи. }
procedure ChiCovered(const AId: string);
{ Ветка внутри строки исполнилась ещё раз. }
procedure ChiBranch(const AId, ABranch: string);
{ Машиночитаемый отчёт: по строке на идентификатор, ветви отсортированы. }
function ChiCoverageReport: string;

{ Лента: восходящее время, ненулевые количества обоих знаков, цена гуляет
  вокруг единицы. Нулевое количество запрещено намеренно — у нуля два знака, и
  направление такой сделки было бы свойством представления, а не данных. }
function ChiMakeTape(Count: Integer; ASeed: UInt64): TChiTape;

implementation

{ Листовые методы записи — раньше всех, кто их зовёт. }

function TChiTrade.Quantity: Single;
begin
  Result := Abs(Qty);
end;

function TChiTrade.Side: TChiSide;
begin
  if (PCardinal(@Qty)^ and $80000000) = 0 then
    Result := csBuy
  else
    Result := csSell;
end;

function TChiTrade.IsBuy: Boolean;
begin
  Result := (PCardinal(@Qty)^ and $80000000) = 0;
end;

function TChiTrade.SameDirection(const Other: TChiTrade): Boolean;
begin
  Result := (PCardinal(@Qty)^ xor PCardinal(@Other.Qty)^) and $80000000 = 0;
end;

procedure TChiTrade.FromOrder(const O: TChiOrder);
begin
  Time := O.Time;
  Price := O.Price;
  Qty := O.Quantity;
  if O.Side = csSell then Qty := -Qty;
end;

procedure TChiTrade.ToOrder(var O: TChiOrder);
begin
  O.Time := Time;
  O.Price := Price;
  O.Quantity := Abs(Qty);
  O.Fill := 1;
  if (PCardinal(@Qty)^ and $80000000) = 0 then
    O.Side := csBuy
  else
    O.Side := csSell;
end;

function ChiSumEmpty: TChiSum;
begin
  Result := Default(TChiSum);
  Result.Digest := ChiOffset;
end;

{ Источник }

function ChiSource(ASeed: UInt64): TChiSource;
begin
  Result.State := ASeed or 1;
end;

function TChiSource.NextWord: UInt64;
begin
  State := State xor (State shl 13);
  State := State xor (State shr 7);
  State := State xor (State shl 17);
  Result := State;
end;

function TChiSource.NextBelow(ALimit: Integer): Integer;
begin
  Result := Integer((NextWord shr 33) mod UInt64(ALimit));
end;

function TChiSource.NextUnit: Double;
begin
  Result := (NextWord shr 11) * (1.0 / 9007199254740992.0);
end;

{ Наблюдение }

type
  TChiMark = record
    Id:     string;
    Branch: string;
    Count:  Int64;
  end;

var
  ClaimLock:  TCriticalSection;
  ClaimBad:   Integer;
  ClaimFirst: string;
  ClaimSeen:  array of string;
  Marks:      array of TChiMark;

procedure ChiClaim(Condition: Boolean; const What: string);
begin
  if Condition then Exit;
  ClaimLock.Acquire;
  try
    Inc(ClaimBad);
    if ClaimFirst = '' then ClaimFirst := What;
    for var I := 0 to High(ClaimSeen) do
      if ClaimSeen[I] = What then Exit;
    if Length(ClaimSeen) < 32 then
    begin
      SetLength(ClaimSeen, Length(ClaimSeen) + 1);
      ClaimSeen[High(ClaimSeen)] := What;
    end;
  finally
    ClaimLock.Release;
  end;
end;

function ChiFailures: Integer;
begin
  ClaimLock.Acquire;
  try
    Result := ClaimBad;
  finally
    ClaimLock.Release;
  end;
end;

function ChiFirstFailure: string;
begin
  ClaimLock.Acquire;
  try
    Result := ClaimFirst;
  finally
    ClaimLock.Release;
  end;
end;

procedure ChiSame(const A, B: TChiSum; const Who: string);
var
  I: Integer;
begin
  for I := 0 to ChiExactCount - 1 do
    ChiClaim(A.Exact[I] = B.Exact[I],
      Who + ': точная величина ' + IntToStr(I));
  for I := 0 to ChiLooseCount - 1 do
    ChiClaim(A.Loose[I] = B.Loose[I],
      Who + ': вещественная величина ' + IntToStr(I) + ' не бит в бит');
  ChiClaim(A.Digest = B.Digest, Who + ': разошлась дорога');
end;

procedure ChiClose(const A, B: TChiSum; const Who: string);
var
  I: Integer;
begin
  for I := 0 to ChiExactCount - 1 do
    ChiClaim(A.Exact[I] = B.Exact[I],
      Who + ': точная величина ' + IntToStr(I));
  for I := 0 to ChiLooseCount - 1 do
    ChiClaim(ChiNear(A.Loose[I], B.Loose[I]),
      Who + ': вещественная величина ' + IntToStr(I));
  ChiClaim(A.Digest = B.Digest, Who + ': разошлась дорога');
end;

{ Отметка ветви. Пустая ветвь означает сам орган: «строка отработала». }
procedure Mark(const AId, ABranch: string);
var
  I: Integer;
begin
  ClaimLock.Acquire;
  try
    for I := 0 to High(Marks) do
      if (Marks[I].Id = AId) and (Marks[I].Branch = ABranch) then
      begin
        Inc(Marks[I].Count);
        Exit;
      end;
    SetLength(Marks, Length(Marks) + 1);
    Marks[High(Marks)].Id := AId;
    Marks[High(Marks)].Branch := ABranch;
    Marks[High(Marks)].Count := 1;
  finally
    ClaimLock.Release;
  end;
end;

procedure ChiCovered(const AId: string);
begin
  Mark(AId, '');
end;

procedure ChiBranch(const AId, ABranch: string);
begin
  Mark(AId, ABranch);
end;

function ChiCoverageReport: string;
var
  I, J, K: Integer;
  Ids: array of string;
  Line: string;
  Order: array of Integer;
  Tmp: Integer;
begin
  Result := '';
  ClaimLock.Acquire;
  try
    { Порядок отметок задан тем, какой поток успел первым, поэтому вывод
      сортируется — иначе он не сравнивался бы между сборками. }
    SetLength(Order, Length(Marks));
    for I := 0 to High(Marks) do Order[I] := I;
    for I := 0 to High(Order) - 1 do
      for J := 0 to High(Order) - 1 - I do
        if (Marks[Order[J]].Id > Marks[Order[J + 1]].Id)
           or ((Marks[Order[J]].Id = Marks[Order[J + 1]].Id)
               and (Marks[Order[J]].Branch > Marks[Order[J + 1]].Branch)) then
        begin
          Tmp := Order[J];
          Order[J] := Order[J + 1];
          Order[J + 1] := Tmp;
        end;

    Ids := nil;
    for I := 0 to High(Order) do
    begin
      if Marks[Order[I]].Branch <> '' then Continue;
      SetLength(Ids, Length(Ids) + 1);
      Ids[High(Ids)] := Marks[Order[I]].Id;
    end;

    for K := 0 to High(Ids) do
    begin
      Line := 'CHI_COVER ' + Ids[K];
      for I := 0 to High(Order) do
        if (Marks[Order[I]].Id = Ids[K]) and (Marks[Order[I]].Branch <> '') then
          Line := Line + ' ' + Marks[Order[I]].Branch + '='
                  + IntToStr(Marks[Order[I]].Count);
      Result := Result + Line + sLineBreak;
    end;
  finally
    ClaimLock.Release;
  end;
end;

function ChiFailureList: string;
var
  I: Integer;
begin
  ClaimLock.Acquire;
  try
    Result := '';
    for I := 0 to High(ClaimSeen) do
      Result := Result + sLineBreak + '    - ' + ClaimSeen[I];
  finally
    ClaimLock.Release;
  end;
end;

function ChiMix(Acc: UInt64; Value: Int64): UInt64;
var
  I: Integer;
begin
  Result := Acc;
  for I := 0 to 7 do
  begin
    Result := Result xor UInt64(Byte(Value shr (I * 8)));
    Result := Result * ChiPrime;
  end;
end;

function ChiNear(const A, B: Double; Tol: Double): Boolean;
var
  Scale: Double;
begin
  Scale := Abs(A);
  if Abs(B) > Scale then Scale := Abs(B);
  if Scale < 1.0 then Scale := 1.0;
  Result := Abs(A - B) <= Tol * Scale;
end;

function ChiFold(const S: TChiSum): Int64;
var
  I: Integer;
  Acc: UInt64;
begin
  Acc := S.Digest;
  for I := 0 to ChiExactCount - 1 do
    Acc := ChiMix(Acc, S.Exact[I]);
  Result := Int64(Acc and $7FFFFFFFFFFF);
end;

function ChiMakeTape(Count: Integer; ASeed: UInt64): TChiTape;
var
  Src: TChiSource;
  I: Integer;
  T, Step, Price, Qty: Double;
begin
  Result := nil;
  SetLength(Result, Count);
  Src := ChiSource(ASeed);
  T := 45000.0;
  Price := 1.0;
  for I := 0 to Count - 1 do
  begin
    { Шаг времени от нуля до полутора секунд. Верхняя граница выбрана так,
      чтобы лента заведомо ПЕРЕКРЫЛА самое дальнее окно свёртки: иначе обход
      доходил бы до начала ленты и досрочный выход по времени — отдельная и
      вполне ломающаяся ветка — не исполнялся бы ни разу. }
    Step := Src.NextUnit * 1.5 / ChiSecsPerDay;
    T := T + Step;
    Price := Price * (1.0 + (Src.NextUnit - 0.5) * 0.002);
    Qty := 0.5 + Src.NextUnit * 40.0;
    if Src.NextBelow(2) = 0 then Qty := -Qty;
    Result[I].Time := T;
    Result[I].Price := Price;
    Result[I].Qty := Qty;
  end;
end;

initialization
  ClaimLock := TCriticalSection.Create;

finalization
  ClaimLock.Free;

end.
