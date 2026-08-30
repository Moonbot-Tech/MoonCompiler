unit chimera_code;

{ Орган «кодирование»: перевод байтов в печатный вид и обратно.

  Источник: `MoonBot/Common\nethelpers.pas` — `Encode3to4`,
  `Decode4to3Ex`, `EncodeTriplet`. Перенесено дословно по форме: обе таблицы,
  индексная работа по БАЙТОВОЙ строке от единицы, накопление трёх байтов в
  четыре шестибитных куска через сдвиги и маски, разбор через сдвигаемый
  накопитель с пропуском чужих символов, дополнение хвоста, и тройное
  кодирование по множеству символов.

  Почему это отдельная форма:

    * байтовая строка индексируется с единицы, длина назначается заранее с
      запасом и урезается в конце фактическим счётчиком. Ошибка на единицу
      здесь не падает, а молча портит хвост;
    * работа идёт сдвигами и масками по узким типам с расширением до целого:
      `(c and $FC) shr 2`, `DOut[1] + (c and $F0) shr 4`. Приоритет операций
      здесь такой, что порядок сложения и сдвига — часть смысла, а не стиля;
    * разбор пропускает всё, что не входит в таблицу, через `Continue`, и
      добирает хвост по остатку счётчика — три разные концовки;
    * множество символов (`set of AnsiChar`) и проверка вхождения в него —
      отдельное представление данных.

  Оракулы:

    1. **стандартные векторы** RFC 4648 — внешняя истина, не зависящая ни от
       нашей реализации, ни от компилятора;
    2. **круговой обход** для всех длин от нуля до предельной: закодировать,
       разобрать, сравнить с исходником байт в байт. Одной кругóвости мало,
       поэтому она идёт ВМЕСТЕ с проверкой канонического вида — длины
       результата и позиций дополнения;
    3. **независимый разбор** — вторая реализация раскодирования, написанная
       поразрядно, без таблицы и без накопителя. }

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch INLINEVARS}
{$endif}
{$Q-}{$R-}

interface

uses
  SysUtils, chimera_body;

type
  TChiSpecials = set of AnsiChar;

const
  { Таблицы перенесены из живого юнита буква в букву. }
  { Тип задан явно: у нетипизированной строковой постоянной буква широкая, и
    сравнение с байтовой буквой строгий компилятор не пропустит. }
  ChiTableBase64: AnsiString =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';

  ChiReTableBase64 =
    #$40 + #$40 + #$40 + #$40 + #$40 + #$40 + #$40 + #$40 + #$40 + #$40 + #$3E + #$40
  + #$40 + #$40 + #$3F + #$34 + #$35 + #$36 + #$37 + #$38 + #$39 + #$3A + #$3B + #$3C
  + #$3D + #$40 + #$40 + #$40 + #$40 + #$40 + #$40 + #$40 + #$00 + #$01 + #$02 + #$03
  + #$04 + #$05 + #$06 + #$07 + #$08 + #$09 + #$0A + #$0B + #$0C + #$0D + #$0E + #$0F
  + #$10 + #$11 + #$12 + #$13 + #$14 + #$15 + #$16 + #$17 + #$18 + #$19 + #$40 + #$40
  + #$40 + #$40 + #$40 + #$40 + #$1A + #$1B + #$1C + #$1D + #$1E + #$1F + #$20 + #$21
  + #$22 + #$23 + #$24 + #$25 + #$26 + #$27 + #$28 + #$29 + #$2A + #$2B + #$2C + #$2D
  + #$2E + #$2F + #$30 + #$31 + #$32 + #$33 + #$40 + #$40 + #$40 + #$40 + #$40 + #$40;

function ChiCodeRun: Int64;

implementation

{ ═══ Перенесённые формы ══════════════════════════════════════════════════ }

function Encode3to4(const Value, Table: AnsiString): AnsiString;
var
  C: Byte;
  N, L: Integer;
  Count: Integer;
  DOut: array [0 .. 3] of Byte;
begin
  SetLength(Result, ((Length(Value) + 2) div 3) * 4);
  L := 1;
  Count := 1;
  while Count <= Length(Value) do
  begin
    C := Ord(Value[Count]);
    Inc(Count);
    DOut[0] := (C and $FC) shr 2;
    DOut[1] := (C and $03) shl 4;
    if Count <= Length(Value) then
    begin
      C := Ord(Value[Count]);
      Inc(Count);
      DOut[1] := DOut[1] + (C and $F0) shr 4;
      DOut[2] := (C and $0F) shl 2;
      if Count <= Length(Value) then
      begin
        C := Ord(Value[Count]);
        Inc(Count);
        DOut[2] := DOut[2] + (C and $C0) shr 6;
        DOut[3] := (C and $3F);
      end
      else
        DOut[3] := $40;
    end
    else
    begin
      DOut[2] := $40;
      DOut[3] := $40;
    end;
    for N := 0 to 3 do
      if (DOut[N] + 1) <= Length(Table) then
      begin
        Result[L] := Table[DOut[N] + 1];
        Inc(L);
      end;
  end;
  SetLength(Result, L - 1);
end;

function Decode4to3Ex(const Value, Table: AnsiString): AnsiString;
var
  X, Y, Lv: Integer;
  D: Integer;
  Dl: Integer;
  C: Byte;
  P: Integer;
begin
  Lv := Length(Value);
  SetLength(Result, Lv);
  X := 1;
  Dl := 4;
  D := 0;
  P := 1;
  while X <= Lv do
  begin
    Y := Ord(Value[X]);
    if (Y >= 33) and (Y <= 127) then
      C := Ord(Table[Y - 32])
    else
      C := 64;
    Inc(X);
    if C > 63 then
      Continue;
    D := (D shl 6) or C;
    Dec(Dl);
    if Dl <> 0 then
      Continue;
    Result[P] := AnsiChar((D shr 16) and $FF);
    Inc(P);
    Result[P] := AnsiChar((D shr 8) and $FF);
    Inc(P);
    Result[P] := AnsiChar(D and $FF);
    Inc(P);
    D := 0;
    Dl := 4;
  end;
  case Dl of
    1:
      begin
        D := D shr 2;
        Result[P] := AnsiChar((D shr 8) and $FF);
        Inc(P);
        Result[P] := AnsiChar(D and $FF);
        Inc(P);
      end;
    2:
      begin
        D := D shr 4;
        Result[P] := AnsiChar(D and $FF);
        Inc(P);
      end;
  end;
  SetLength(Result, P - 1);
end;

function EncodeTriplet(const Value: AnsiString; Delimiter: AnsiChar;
  Specials: TChiSpecials): AnsiString;
var
  N, L: Integer;
  S: AnsiString;
  C: AnsiChar;
begin
  SetLength(Result, Length(Value) * 3);
  L := 1;
  for N := 1 to Length(Value) do
  begin
    C := Value[N];
    if C in Specials then
    begin
      Result[L] := Delimiter;
      Inc(L);
      S := AnsiString(IntToHex(Ord(C), 2));
      Result[L] := S[1];
      Inc(L);
      Result[L] := S[2];
      Inc(L);
    end
    else
    begin
      Result[L] := C;
      Inc(L);
    end;
  end;
  Dec(L);
  SetLength(Result, L);
end;

{ ═══ Независимый разбор ══════════════════════════════════════════════════

  Ни таблицы, ни сдвигаемого накопителя: позиция символа в алфавите ищется
  перебором, биты собираются по одному. Медленно и намеренно — это оракул, а
  не рабочий путь. }

function BitwiseDecode(const Value: AnsiString): AnsiString;
var
  I, J, Pos, Bits, Have: Integer;
  Byte1: Integer;
begin
  Result := '';
  Bits := 0;
  Have := 0;
  for I := 1 to Length(Value) do
  begin
    if Value[I] = '=' then Break;
    Pos := -1;
    for J := 1 to 64 do
      if ChiTableBase64[J] = Value[I] then
      begin
        Pos := J - 1;
        Break;
      end;
    if (Pos < 0) or (Pos > 63) then Continue;
    for J := 5 downto 0 do
    begin
      Bits := (Bits shl 1) or ((Pos shr J) and 1);
      Inc(Have);
      if Have = 8 then
      begin
        Byte1 := Bits and $FF;
        Result := Result + AnsiChar(Byte1);
        Bits := 0;
        Have := 0;
      end;
    end;
  end;
end;

{ ═══ Проверка ════════════════════════════════════════════════════════════ }

const
  IdCode = 'CHI-MB-CODE-001';
  IdUrl  = 'CHI-MB-CODE-002';
  IdStr  = 'CHI-MB-STR-001';

  { Векторы RFC 4648 — внешняя истина. }
  VecPlain: array [0 .. 6] of AnsiString =
    ('', 'f', 'fo', 'foo', 'foob', 'fooba', 'foobar');
  VecCoded: array [0 .. 6] of AnsiString =
    ('', 'Zg==', 'Zm8=', 'Zm9v', 'Zm9vYg==', 'Zm9vYmE=', 'Zm9vYmFy');

function ChiCodeRun: Int64;
var
  Src: TChiSource;
  I, J, Len: Integer;
  Plain, Coded, Back: AnsiString;
  Specials: TChiSpecials;
  Acc: UInt64;
  Pads: Integer;
  Wide: string;
  Ok: Boolean;
begin
  ChiCovered(IdCode);
  ChiCovered(IdUrl);
  ChiCovered(IdStr);
  Acc := ChiOffset;
  Src := ChiSource(99991);

  { ── Векторы: внешняя истина, ни от чего нашего не зависящая ── }
  for I := 0 to High(VecPlain) do
  begin
    Coded := Encode3to4(VecPlain[I], ChiTableBase64);
    ChiClaim(Coded = VecCoded[I],
      'кодирование: вектор ' + IntToStr(I) + ' дал ' + string(Coded));
    Back := Decode4to3Ex(VecCoded[I], ChiReTableBase64);
    ChiClaim(Back = VecPlain[I],
      'кодирование: разбор вектора ' + IntToStr(I) + ' не сошёлся');
    Acc := ChiMix(Acc, Length(Coded));
  end;
  ChiBranch(IdCode, 'vectors');

  { ── Круговой обход всех длин, вместе с проверкой канонического вида ── }
  for Len := 0 to 200 do
  begin
    SetLength(Plain, Len);
    for I := 1 to Len do
      Plain[I] := AnsiChar(Src.NextBelow(256));

    Coded := Encode3to4(Plain, ChiTableBase64);

    { Канонический вид: длина кратна четырём, дополнение только в хвосте и
      ровно столько, сколько требует остаток. }
    ChiClaim((Length(Coded) mod 4) = 0,
      'кодирование: длина не кратна четырём, длина входа ' + IntToStr(Len));
    Pads := 0;
    for I := Length(Coded) downto 1 do
      if Coded[I] = '=' then Inc(Pads) else Break;
    case Len mod 3 of
      0: ChiClaim(Pads = 0, 'кодирование: лишнее дополнение');
      1: ChiClaim(Pads = 2, 'кодирование: должно быть два знака дополнения');
      2: ChiClaim(Pads = 1, 'кодирование: должен быть один знак дополнения');
    end;
    for I := 1 to Length(Coded) - Pads do
      ChiClaim(Coded[I] <> '=', 'кодирование: дополнение не в хвосте');

    Back := Decode4to3Ex(Coded, ChiReTableBase64);
    ChiClaim(Back = Plain,
      'кодирование: круговой обход не сошёлся на длине ' + IntToStr(Len));

    { Независимый разбор — второй способ получить то же. }
    ChiClaim(BitwiseDecode(Coded) = Plain,
      'кодирование: поразрядный разбор разошёлся на длине ' + IntToStr(Len));

    Acc := ChiMix(Acc, Length(Coded));
    Acc := ChiMix(Acc, Pads);
  end;
  ChiBranch(IdCode, 'roundtrip');
  ChiBranch(IdCode, 'canonical-padding');
  ChiBranch(IdCode, 'independent-decode');

  { ── Разбор обязан пропускать чужие символы, а не спотыкаться о них ── }
  Coded := 'Zm9v' + #13#10 + 'YmFy';
  ChiClaim(Decode4to3Ex(Coded, ChiReTableBase64) = 'foobar',
    'кодирование: перевод строки внутри не пропущен');
  ChiBranch(IdCode, 'skip-foreign');

  { ── Тройное кодирование для адреса ── }
  Specials := [#$00 .. #$20, '<', '>', '"', '%', '{', '}', '|', '\', '^',
               '[', ']', '`', #$7F .. #$FF]
              + [';', '/', '?', ':', '@', '=', '&', '#', '+'];

  ChiClaim(EncodeTriplet('abc', '%', Specials) = 'abc',
    'адрес: обычные символы изменены');
  ChiBranch(IdUrl, 'plain');

  ChiClaim(EncodeTriplet('a b', '%', Specials) = 'a%20b',
    'адрес: пробел закодирован неверно');
  ChiBranch(IdUrl, 'escaped');

  ChiClaim(EncodeTriplet('a/b?c=d&e', '%', Specials) = 'a%2Fb%3Fc%3Dd%26e',
    'адрес: разделители закодированы неверно');
  ChiBranch(IdUrl, 'separators');

  ChiClaim(EncodeTriplet('', '%', Specials) = '', 'адрес: пустой вход');
  ChiBranch(IdUrl, 'empty');

  { Старшие байты: множество включает весь верхний диапазон, значит каждый
    такой байт обязан развернуться в три символа. }
  SetLength(Plain, 4);
  for I := 1 to 4 do Plain[I] := AnsiChar($80 + I);
  Coded := EncodeTriplet(Plain, '%', Specials);
  ChiClaim(Length(Coded) = 12, 'адрес: старшие байты не развёрнуты');
  ChiBranch(IdUrl, 'high-bytes');
  Acc := ChiMix(Acc, Length(Coded));

  { Строка целиком из особых символов — предельный случай выделенной длины. }
  SetLength(Plain, 64);
  for I := 1 to 64 do Plain[I] := '%';
  Coded := EncodeTriplet(Plain, '%', Specials);
  ChiClaim(Length(Coded) = 192, 'адрес: предельная длина не совпала');
  ChiBranch(IdUrl, 'all-special');
  Acc := ChiMix(Acc, Length(Coded));

  { Встроенный ноль обязан пережить и кодирование, и разбор. }
  SetLength(Plain, 5);
  Plain[1] := 'a'; Plain[2] := #0; Plain[3] := 'b'; Plain[4] := #0; Plain[5] := 'c';
  Coded := Encode3to4(Plain, ChiTableBase64);
  ChiClaim(Decode4to3Ex(Coded, ChiReTableBase64) = Plain,
    'кодирование: встроенный ноль потерян');
  ChiBranch(IdCode, 'embedded-zero');
  Acc := ChiMix(Acc, Length(Coded));

  { Повторное наращивание управляемой строки: длина назначается с запасом и
    урезается, и так двести раз подряд поверх одной переменной. }
  Coded := '';
  for J := 1 to 200 do
  begin
    SetLength(Plain, J);
    for I := 1 to J do Plain[I] := AnsiChar(64 + (I mod 32));
    Coded := Encode3to4(Plain, ChiTableBase64);
  end;
  ChiClaim(Length(Coded) > 0, 'кодирование: повторное наращивание дало пустое');
  ChiBranch(IdCode, 'regrow');
  Acc := ChiMix(Acc, Length(Coded));

  { ═══ Строки: то, что проезжает через кодирование по дороге на биржу ═══

    Байтовая строка в этих путях не текст, а последовательность байтов: в неё
    попадают и старшие байты, и ноль, и всё остальное. Проверяется, что длина
    остаётся длиной, а не считается по нулю, и что перевод между узкой и
    широкой формой не теряет байты. }

  { Встроенный ноль не обрывает ни длину, ни сравнение, ни поиск. }
  SetLength(Plain, 7);
  Plain[1] := 'a'; Plain[2] := #0; Plain[3] := 'b';
  Plain[4] := #0; Plain[5] := 'c'; Plain[6] := #0; Plain[7] := 'd';
  ChiClaim(Length(Plain) = 7, 'строки: ноль обрезал длину');
  ChiClaim(Pos(AnsiString('c'), Plain) = 5, 'строки: поиск за нулём не нашёл');
  Coded := Plain;
  ChiClaim(Coded = Plain, 'строки: сравнение оборвалось на нуле');
  Coded[2] := 'X';
  ChiClaim(Coded <> Plain, 'строки: копия с нулём не отделилась от оригинала');
  ChiBranch(IdStr, 'embedded-zero');
  Acc := ChiMix(Acc, Length(Plain));

  { Все двести пятьдесят шесть значений байта обязаны пережить дорогу. }
  SetLength(Plain, 256);
  for I := 1 to 256 do Plain[I] := AnsiChar(I - 1);
  Coded := Encode3to4(Plain, ChiTableBase64);
  ChiClaim(Decode4to3Ex(Coded, ChiReTableBase64) = Plain,
    'строки: не все значения байта пережили кодирование');
  ChiBranch(IdStr, 'all-bytes');

  { Узкая строка в широкую и обратно: старшие байты не имеют права
    превратиться в вопросительные знаки. Перевод идёт побайтно, потому что
    речь о байтах, а не о тексте. }
  SetLength(Wide, Length(Plain));
  for I := 1 to Length(Plain) do Wide[I] := WideChar(Ord(Plain[I]));
  SetLength(Back, Length(Wide));
  for I := 1 to Length(Wide) do Back[I] := AnsiChar(Ord(Wide[I]) and $FF);
  ChiClaim(Back = Plain, 'строки: перевод в широкую форму потерял байты');
  ChiBranch(IdStr, 'narrow-wide');

  { Пустая строка: длина ноль, обращение к телу не нужно. }
  Plain := '';
  ChiClaim(Length(Plain) = 0, 'строки: пустая не пуста');
  ChiClaim(Encode3to4(Plain, ChiTableBase64) = '',
    'строки: кодирование пустой дало не пустое');
  ChiBranch(IdStr, 'empty');

  { Повторное наращивание одной переменной: длина растёт по одному символу
    тысячу раз, и содержимое обязано остаться тем, что клали. }
  Plain := '';
  for I := 1 to 1000 do Plain := Plain + AnsiChar(32 + (I mod 90));
  ChiClaim(Length(Plain) = 1000, 'строки: наращивание дало не ту длину');
  Ok := True;
  for I := 1 to 1000 do
    if Plain[I] <> AnsiChar(32 + (I mod 90)) then Ok := False;
  ChiClaim(Ok, 'строки: наращивание испортило содержимое');
  ChiBranch(IdStr, 'regrow-by-one');
  Acc := ChiMix(Acc, Length(Plain));

  { Копия при записи: две переменные делят тело, пока одну не тронули.
    Символ для правки берётся заведомо отсутствующий в наборе выше. }
  Coded := Plain;
  Coded[1] := #1;
  ChiClaim(Plain[1] <> #1, 'строки: правка длинной копии задела оригинал');
  ChiClaim(Coded[1] = #1, 'строки: правка копии не записалась');
  ChiClaim(Length(Coded) = Length(Plain), 'строки: копия сменила длину');
  ChiBranch(IdStr, 'copy-on-write');

  Result := Int64(Acc and $7FFFFFFFFFFF);
end;

end.
