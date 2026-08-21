unit resident_codec;

{ Семейство `codec` — обратимые преобразования буфера.

  У всего здесь один и тот же оракул, и он не требует эталона: **обратимость**.
  Прогони буфер туда и обратно — обязан получиться исходный, байт в байт. Что
  именно получилось в середине, знать не нужно; достаточно, что дорога туда и
  дорога обратно сходятся. Такой оракул ловит и потерянный байт, и съехавший
  индекс, и хвост, до которого преобразование не дошло, — причём ловит одинаково
  хорошо на любых данных.

  Второй оракул — **независимость от нарезки**: поток, обработанный целиком, и
  тот же поток, обработанный кусками разной длины, обязаны дать одно и то же.
  Это ловит состояние, утёкшее между кусками, и границы, посчитанные от начала
  куска вместо начала потока.

  Третий — **чувствительность**: свёртка, у которой изменение одного байта
  входа ничего не меняет на выходе, сломана, даже если сама по себе стабильна.

  Ни одно из преобразований не претендует быть криптографией: это машинки для
  проверки индексации таблиц, границ буферов и байтовых операций. }

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
  SysUtils, Classes, Generics.Collections, resident_core;

implementation

type
  TResidentTable = array[0 .. 255] of Byte;

  TResidentCodecPocket = class(TResidentPocket)
  private
    FStream: TBytes;
    FRounds: Int64;
  end;

{ Таблица подстановки и обратная к ней: строятся из сида так, что подстановка
  заведомо взаимно однозначна — иначе обратимость была бы не свойством кода, а
  везением. }
procedure BuildTables(Seed: UInt64; out Forward_, Backward: TResidentTable);
var
  State: UInt64;
  I, J: Integer;
  Swap: Byte;
begin
  for I := 0 to 255 do
    Forward_[I] := Byte(I);
  State := Seed;
  for I := 255 downto 1 do
  begin
    J := Integer(ResidentNext(State) mod UInt64(I + 1));
    Swap := Forward_[I];
    Forward_[I] := Forward_[J];
    Forward_[J] := Swap;
  end;
  { Обратная строится из прямой, а не независимо: так она обратна по
    построению, и проверяется именно применение, а не совпадение двух таблиц. }
  for I := 0 to 255 do
    Backward[Forward_[I]] := Byte(I);
end;

function MakeBuffer(Carrier: TResidentCarrier; Room: Integer): TBytes;
var
  I: Integer;
begin
  SetLength(Result, Room);
  for I := 0 to Room - 1 do
    Result[I] := Byte((Carrier.Tag.Wide + I * 7 + Carrier.Serial) and $FF);
end;

function SameBytes(const A, B: TBytes): Boolean;
begin
  Result := Length(A) = Length(B);
  if Result and (Length(A) > 0) then
    Result := CompareMem(@A[0], @B[0], Length(A));
end;

{ Подстановка по таблице: прямая и обратная обязаны сойтись на исходном. }
procedure StageSubstitution(Carrier: TResidentCarrier);
var
  Forward_, Backward: TResidentTable;
  Source, Work: TBytes;
  I, Room: Integer;
  Moved: Integer;
begin
  BuildTables(ResidentMix(Carrier.Seed, UInt64(Cardinal(Carrier.Lap))),
              Forward_, Backward);
  Room := 32 + (Carrier.Lap mod 96);
  Source := MakeBuffer(Carrier, Room);
  Work := System.Copy(Source, 0, Room);

  for I := 0 to Room - 1 do
    Work[I] := Forward_[Work[I]];

  { Преобразование обязано что-то поменять — иначе обратимость доказывала бы
    только то, что ничего не делалось. }
  Moved := 0;
  for I := 0 to Room - 1 do
    if Work[I] <> Source[I] then
      Inc(Moved);
  Carrier.Feed(UInt64(Cardinal(Moved)));
  Carrier.Feed(UInt64(Ord(Moved > 0)));

  for I := 0 to Room - 1 do
    Work[I] := Backward[Work[I]];
  Carrier.Feed(UInt64(Ord(SameBytes(Source, Work))));
  Carrier.Feed(UInt64(Cardinal(Room)));

  { Таблица обязана быть перестановкой: каждый код встречается ровно раз. }
  var Seen := 0;
  var Mask: TResidentTable;
  FillChar(Mask, SizeOf(Mask), 0);
  for I := 0 to 255 do
    if Mask[Forward_[I]] = 0 then
    begin
      Mask[Forward_[I]] := 1;
      Inc(Seen);
    end;
  Carrier.Feed(UInt64(Cardinal(Seen)));
  Carrier.Feed(UInt64(Ord(Seen = 256)));
end;

{ Маска: применённая дважды, обязана вернуть исходное. }
procedure StageMask(Carrier: TResidentCarrier);
var
  Source, Work: TBytes;
  Key: array[0 .. 7] of Byte;
  I, Room: Integer;
begin
  Room := 24 + (Carrier.Lap mod 80);
  Source := MakeBuffer(Carrier, Room);
  Work := System.Copy(Source, 0, Room);
  { Младший бит ключа взведён нарочно: нулевая маска ничего бы не меняла, и
    обратимость доказывала бы только то, что преобразования не было. }
  for I := 0 to High(Key) do
    Key[I] := Byte(((Carrier.Tag.Wide shr (I * 8)) and $FF) or 1);

  for I := 0 to Room - 1 do
    Work[I] := Work[I] xor Key[I and 7];
  Carrier.Feed(UInt64(Ord(SameBytes(Source, Work)) xor 1));

  for I := 0 to Room - 1 do
    Work[I] := Work[I] xor Key[I and 7];
  Carrier.Feed(UInt64(Ord(SameBytes(Source, Work))));

  { Ключ, длина которого не делит длину буфера, обязан ложиться по кругу без
    смещения на хвосте. }
  for I := 0 to Room - 1 do
    Work[I] := Work[I] xor Key[I mod 5];
  for I := 0 to Room - 1 do
    Work[I] := Work[I] xor Key[I mod 5];
  Carrier.Feed(UInt64(Ord(SameBytes(Source, Work))));
  Carrier.Feed(UInt64(Cardinal(Room)));
end;

{ Обмен полубайтов — инволюция: применённая дважды, даёт исходное. }
procedure StageNibbleSwap(Carrier: TResidentCarrier);
var
  Source, Work: TBytes;
  I, Room: Integer;
  Sum: UInt64;
begin
  Room := 16 + (Carrier.Lap mod 48);
  Source := MakeBuffer(Carrier, Room);
  Work := System.Copy(Source, 0, Room);

  for I := 0 to Room - 1 do
    Work[I] := Byte((Work[I] shr 4) or (Work[I] shl 4));
  Sum := 0;
  for I := 0 to Room - 1 do
    Sum := Sum + Work[I];
  Carrier.Feed(Sum);

  for I := 0 to Room - 1 do
    Work[I] := Byte((Work[I] shr 4) or (Work[I] shl 4));
  Carrier.Feed(UInt64(Ord(SameBytes(Source, Work))));

  { Полубайты на месте: старший обязан стать младшим и наоборот. }
  Carrier.Feed(UInt64(Byte((Source[0] shr 4) or (Source[0] shl 4))));
  Carrier.Feed(UInt64(Source[0]));
end;

{ Шестнадцатеричная запись: длина ровно вдвое, разбор обязан вернуть исходное. }
procedure StageHex(Carrier: TResidentCarrier);
const
  Digits: array[0 .. 15] of Char = ('0', '1', '2', '3', '4', '5', '6', '7',
                                    '8', '9', 'A', 'B', 'C', 'D', 'E', 'F');
var
  Source, Back: TBytes;
  Text: string;
  I, Room: Integer;
  High_, Low_: Integer;

  function ValueOf(C: Char): Integer;
  begin
    case C of
      '0' .. '9': Result := Ord(C) - Ord('0');
      'A' .. 'F': Result := Ord(C) - Ord('A') + 10;
    else
      Result := -1;
    end;
  end;

begin
  Room := 8 + (Carrier.Lap mod 40);
  Source := MakeBuffer(Carrier, Room);

  SetLength(Text, Room * 2);
  for I := 0 to Room - 1 do
  begin
    Text[I * 2 + 1] := Digits[Source[I] shr 4];
    Text[I * 2 + 2] := Digits[Source[I] and $0F];
  end;
  Carrier.Feed(UInt64(Cardinal(Length(Text))));
  Carrier.Feed(UInt64(Ord(Length(Text) = Room * 2)));
  Carrier.FeedWide(Text);

  SetLength(Back, Room);
  for I := 0 to Room - 1 do
  begin
    High_ := ValueOf(Text[I * 2 + 1]);
    Low_ := ValueOf(Text[I * 2 + 2]);
    if (High_ < 0) or (Low_ < 0) then
      Break;
    Back[I] := Byte(High_ shl 4 or Low_);
  end;
  Carrier.Feed(UInt64(Ord(SameBytes(Source, Back))));

  { Свой разбор обязан сходиться с библиотечной записью того же байта. }
  Carrier.Feed(UInt64(Ord(IntToHex(Source[0], 2) =
                          System.Copy(Text, 1, 2))));
end;

{ Перестановка позиций: байты едут по таблице мест, обратная возвращает их
  туда, откуда взяли. }
procedure StageInterleave(Carrier: TResidentCarrier);
var
  Source, Work, Back: TBytes;
  Room, I, Half: Integer;
begin
  Room := 2 * (8 + (Carrier.Lap mod 24));
  Half := Room div 2;
  Source := MakeBuffer(Carrier, Room);
  SetLength(Work, Room);
  SetLength(Back, Room);

  { Первая половина на чётные места, вторая на нечётные. }
  for I := 0 to Half - 1 do
  begin
    Work[I * 2] := Source[I];
    Work[I * 2 + 1] := Source[Half + I];
  end;
  Carrier.Feed(UInt64(Work[0]));
  Carrier.Feed(UInt64(Work[1]));
  Carrier.Feed(UInt64(Ord(Work[0] = Source[0])));
  Carrier.Feed(UInt64(Ord(Work[1] = Source[Half])));

  for I := 0 to Half - 1 do
  begin
    Back[I] := Work[I * 2];
    Back[Half + I] := Work[I * 2 + 1];
  end;
  Carrier.Feed(UInt64(Ord(SameBytes(Source, Back))));
  Carrier.Feed(UInt64(Cardinal(Room)));
end;

{ Упаковка признаков в биты и обратно: восемь значений в байте, и ни одно не
  имеет права заехать в чужой разряд. }
procedure StageBitPack(Carrier: TResidentCarrier);
var
  Flags: array[0 .. 63] of Boolean;
  Packed_: array[0 .. 7] of Byte;
  I, Set_: Integer;
  Ok: Boolean;
begin
  Set_ := 0;
  for I := 0 to High(Flags) do
  begin
    Flags[I] := ((Carrier.Tag.Wide + I) and 3) = 0;
    if Flags[I] then
      Inc(Set_);
  end;
  Carrier.Feed(UInt64(Cardinal(Set_)));

  FillChar(Packed_, SizeOf(Packed_), 0);
  for I := 0 to High(Flags) do
    if Flags[I] then
      Packed_[I shr 3] := Packed_[I shr 3] or (1 shl (I and 7));

  for I := 0 to High(Packed_) do
    Carrier.Feed(UInt64(Packed_[I]));

  Ok := True;
  for I := 0 to High(Flags) do
    if ((Packed_[I shr 3] shr (I and 7)) and 1 = 1) <> Flags[I] then
      Ok := False;
  Carrier.Feed(UInt64(Ord(Ok)));

  { Крайние разряды — самое тихое место: младший бит первого байта и старший
    последнего. }
  Carrier.Feed(UInt64(Ord(((Packed_[0] and 1) = 1) = Flags[0])));
  Carrier.Feed(UInt64(Ord(((Packed_[7] shr 7) and 1 = 1) = Flags[63])));
end;

{ Повторы: сжатие и разжатие обязаны сойтись на исходном, включая случай, когда
  повторов нет вовсе и «сжатое» длиннее исходного. }
procedure StageRunLength(Carrier: TResidentCarrier);
var
  Source, Packed_, Back: TBytes;
  I, Room, Count, Out_: Integer;
  Current: Byte;
begin
  Room := 32 + (Carrier.Lap mod 64);
  SetLength(Source, Room);
  { Половина буфера — длинные повторы, половина — пёстрая: обе дороги обязаны
    отработать в одном прогоне. }
  for I := 0 to Room - 1 do
    if I < Room div 2 then
      Source[I] := Byte((Carrier.Tag.Wide + I div 7) and $FF)
    else
      Source[I] := Byte((Carrier.Tag.Wide + I * 13) and $FF);

  SetLength(Packed_, Room * 2);
  Out_ := 0;
  I := 0;
  while I < Room do
  begin
    Current := Source[I];
    Count := 1;
    while (I + Count < Room) and (Source[I + Count] = Current) and
          (Count < 255) do
      Inc(Count);
    Packed_[Out_] := Byte(Count);
    Packed_[Out_ + 1] := Current;
    Inc(Out_, 2);
    Inc(I, Count);
  end;
  SetLength(Packed_, Out_);
  Carrier.Feed(UInt64(Cardinal(Out_)));
  Carrier.Feed(UInt64(Ord(Out_ mod 2 = 0)));

  SetLength(Back, 0);
  I := 0;
  while I < Length(Packed_) do
  begin
    Count := Packed_[I];
    Current := Packed_[I + 1];
    SetLength(Back, Length(Back) + Count);
    FillChar(Back[Length(Back) - Count], Count, Current);
    Inc(I, 2);
  end;
  Carrier.Feed(UInt64(Cardinal(Length(Back))));
  Carrier.Feed(UInt64(Ord(SameBytes(Source, Back))));
end;

{ Свёртка по таблице: значение само по себе — дело реализации, а вот
  чувствительность обязана быть. Один изменённый байт обязан менять свёртку. }
procedure StageDigestSensitivity(Carrier: TResidentCarrier);
var
  Table: TResidentTable;
  Ignore: TResidentTable;
  Source: TBytes;
  Room, I, Changed: Integer;
  Base, Other: UInt64;

  function Fold(const Data: TBytes): UInt64;
  var
    K: Integer;
  begin
    Result := ResidentOffset;
    for K := 0 to High(Data) do
      Result := ResidentMix(Result, UInt64(Table[Data[K]]));
  end;

begin
  BuildTables(Carrier.Seed, Table, Ignore);
  Room := 16 + (Carrier.Lap mod 32);
  Source := MakeBuffer(Carrier, Room);
  Base := Fold(Source);
  Carrier.Feed(Base);

  { Каждый байт по очереди меняется на соседний код — и свёртка обязана
    поехать каждый раз, иначе часть буфера в неё не входит. }
  Changed := 0;
  for I := 0 to Room - 1 do
  begin
    Source[I] := Byte(Source[I] + 1);
    Other := Fold(Source);
    if Other <> Base then
      Inc(Changed);
    Source[I] := Byte(Source[I] - 1);
  end;
  Carrier.Feed(UInt64(Cardinal(Changed)));
  Carrier.Feed(UInt64(Ord(Changed = Room)));
  { Возврат к исходному обязан вернуть и свёртку. }
  Carrier.Feed(UInt64(Ord(Fold(Source) = Base)));
end;

{ Независимость от нарезки: тот же поток, поданный кусками разной длины, обязан
  дать ту же свёртку, что и поданный целиком. }
procedure StageChunking(Carrier: TResidentCarrier);
var
  Source: TBytes;
  Room, I, Cut, Taken: Integer;
  Whole, Piece: UInt64;

  procedure Absorb(var Acc: UInt64; const Data: TBytes; Start, Count: Integer);
  var
    K: Integer;
  begin
    for K := Start to Start + Count - 1 do
      Acc := ResidentMix(Acc, UInt64(Data[K]));
  end;

begin
  Room := 64 + (Carrier.Lap mod 128);
  Source := MakeBuffer(Carrier, Room);

  Whole := ResidentOffset;
  Absorb(Whole, Source, 0, Room);
  Carrier.Feed(Whole);

  { Куски по одному байту. }
  Piece := ResidentOffset;
  for I := 0 to Room - 1 do
    Absorb(Piece, Source, I, 1);
  Carrier.Feed(UInt64(Ord(Piece = Whole)));

  { Куски неровной длины, включая пустой. }
  Piece := ResidentOffset;
  Taken := 0;
  Cut := 1;
  while Taken < Room do
  begin
    if Taken + Cut > Room then
      Cut := Room - Taken;
    Absorb(Piece, Source, Taken, Cut);
    Inc(Taken, Cut);
    Cut := 1 + (Cut * 2) mod 17;
  end;
  Carrier.Feed(UInt64(Ord(Piece = Whole)));
  Carrier.Feed(UInt64(Cardinal(Taken)));
  Carrier.Feed(UInt64(Ord(Taken = Room)));

  { Пустой кусок не имеет права что-либо менять. }
  Absorb(Piece, Source, 0, 0);
  Carrier.Feed(UInt64(Ord(Piece = Whole)));
end;

{ Поток, растущий между оборотами: дописанное обязано не портить уже
  обработанное, а свёртка целого — совпадать со свёрткой по частям. }
procedure StageStreamAcrossLaps(Carrier: TResidentCarrier);
var
  Pocket: TResidentCodecPocket;
  Table, Ignore: TResidentTable;
  I, WasLen: Integer;
  Whole, Parts: UInt64;
begin
  Pocket := Carrier.PocketAs<TResidentCodecPocket>('codec-stream');
  BuildTables(Carrier.Seed, Table, Ignore);

  WasLen := Length(Pocket.FStream);
  SetLength(Pocket.FStream, WasLen + 8);
  for I := 0 to 7 do
    Pocket.FStream[WasLen + I] := Byte((Carrier.Tag.Wide + Carrier.Lap + I) and $FF);

  Whole := ResidentOffset;
  for I := 0 to High(Pocket.FStream) do
    Whole := ResidentMix(Whole, UInt64(Table[Pocket.FStream[I]]));

  { То же самое двумя частями: старая голова и свежий хвост. }
  Parts := ResidentOffset;
  for I := 0 to WasLen - 1 do
    Parts := ResidentMix(Parts, UInt64(Table[Pocket.FStream[I]]));
  for I := WasLen to High(Pocket.FStream) do
    Parts := ResidentMix(Parts, UInt64(Table[Pocket.FStream[I]]));
  Carrier.Feed(UInt64(Ord(Parts = Whole)));
  Carrier.Feed(UInt64(Cardinal(Length(Pocket.FStream))));

  Inc(Pocket.FRounds);
  Carrier.Feed(UInt64(Pocket.FRounds));

  if Length(Pocket.FStream) >= 256 then
  begin
    SetLength(Pocket.FStream, 0);
    Pocket.FRounds := 0;
    Carrier.Feed(UInt64(Cardinal(Length(Pocket.FStream))));
  end;
end;

initialization
  ResidentRegisterStage('codec-bit-pack', @StageBitPack);
  ResidentRegisterStage('codec-chunking', @StageChunking);
  ResidentRegisterStage('codec-digest-sensitivity', @StageDigestSensitivity);
  ResidentRegisterStage('codec-hex', @StageHex);
  ResidentRegisterStage('codec-interleave', @StageInterleave);
  ResidentRegisterStage('codec-mask', @StageMask);
  ResidentRegisterStage('codec-nibble-swap', @StageNibbleSwap);
  ResidentRegisterStage('codec-run-length', @StageRunLength);
  ResidentRegisterStage('codec-stream-across-laps', @StageStreamAcrossLaps);
  ResidentRegisterStage('codec-substitution', @StageSubstitution);

end.
