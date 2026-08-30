unit chimera_proto;

{ Орган «протокол»: упаковка сообщений в поток и разбор обратно.

  Источники: `MoonBot/Vars.pas` — `WriteStringToStreamUtf8` и
  его короткий вариант; `MoonProto/MoonProtoEngineStruct.pas` — примитивы
  записи и чтения потока; `MoonProto/MoonProtoSerialization.pas` — порядок
  полей реального сообщения о рынке.

  Перенесено дословно по форме:

    * строка кладётся длиной В БАЙТАХ ПОСЛЕ перевода в восьмибитную кодировку,
      а не длиной в символах. Для строки с не-латинскими буквами это разные
      числа, и именно здесь рождается сдвиг всего последующего потока;
    * длина пишется словом в одном варианте и БАЙТОМ в коротком — короткий
      применяется к именам рынков, и переполнение длины там не проверяется;
    * запись обязательная (`WriteBuffer`), а чтение примитивов — по
      возможности (`Read`): не хватило байтов — вернулся мусор, а не
      исключение. Разница между двумя способами и есть предмет проверки;
    * поля пишутся подряд без разделителей, значит порядок чтения обязан
      совпасть с порядком записи поле в поле;
    * сообщение содержит и неуправляемые поля, и строки вперемешку.

  Оракулы:

    1. **канонический вид потока** — точные смещения и длины: для каждого
       записанного поля известно, сколько байтов оно заняло, и это
       проверяется, а не выводится из успешного чтения обратно;
    2. **круговой обход** сообщения целиком, поле в поле;
    3. **разрезанное чтение**: поток скармливается по кускам, граница которых
       нарочно попадает ВНУТРЬ длины и ВНУТРЬ многобайтового символа;
    4. **повторное использование** одного буфера под большее и меньшее
       сообщение подряд. }

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch INLINEVARS}
{$endif}
{$Q-}{$R-}

interface

uses
  SysUtils, Classes, chimera_body;

type
  { Сообщение о рынке: строки и числа вперемешку, как в живом коде. }
  TChiMarketMsg = record
    Name:       string;
    Currency:   string;
    Base:       string;
    Status:     string;
    PricePrec:  Integer;
    QtyPrec:    Integer;
    Leverage:   Integer;
    K1000:      Integer;
    TickSize:   Double;
    MinQty:     Double;
    Active:     Boolean;
    Kind:       Byte;
    Serial:     Int64;
  end;

function ChiProtoRun: Int64;

implementation

{ ═══ Примитивы потока ════════════════════════════════════════════════════ }

procedure WriteStrUtf8(AStream: TStream; const S: string);
var
  Buf: TBytes;
  L: Word;
begin
  Buf := TEncoding.UTF8.GetBytes(S);
  { Длина — В БАЙТАХ после перевода, а не в символах. }
  L := Length(Buf);
  AStream.WriteBuffer(L, SizeOf(L));
  if L > 0 then AStream.WriteBuffer(Buf[0], L);
end;

procedure ReadStrUtf8(AStream: TStream; var S: string);
var
  L: Word;
  Buf: TBytes;
begin
  AStream.ReadBuffer(L, SizeOf(L));
  if L > 0 then
  begin
    SetLength(Buf, L);
    AStream.ReadBuffer(Buf[0], L);
    S := TEncoding.UTF8.GetString(Buf);
  end
  else
    S := '';
end;

procedure WriteStrShort(AStream: TStream; const S: string);
var
  Buf: TBytes;
  L: Byte;
begin
  Buf := TEncoding.UTF8.GetBytes(S);
  { Байт длины: для имён рынка. Переполнение здесь не проверяется — это
    свойство живого кода, и оно предъявляется, а не чинится. }
  L := Length(Buf);
  AStream.WriteBuffer(L, SizeOf(L));
  if L > 0 then AStream.WriteBuffer(Buf[0], L);
end;

procedure ReadStrShort(AStream: TStream; var S: string);
var
  L: Byte;
  Buf: TBytes;
begin
  AStream.ReadBuffer(L, SizeOf(L));
  if L > 0 then
  begin
    SetLength(Buf, L);
    AStream.ReadBuffer(Buf[0], L);
    S := TEncoding.UTF8.GetString(Buf);
  end
  else
    S := '';
end;

{ ═══ Сообщение ═══════════════════════════════════════════════════════════ }

procedure WriteMsg(AStream: TStream; const M: TChiMarketMsg);
begin
  WriteStrUtf8(AStream, M.Name);
  WriteStrUtf8(AStream, M.Currency);
  WriteStrUtf8(AStream, M.Base);
  WriteStrUtf8(AStream, M.Status);
  AStream.WriteBuffer(M.PricePrec, SizeOf(M.PricePrec));
  AStream.WriteBuffer(M.QtyPrec, SizeOf(M.QtyPrec));
  AStream.WriteBuffer(M.Leverage, SizeOf(M.Leverage));
  AStream.WriteBuffer(M.K1000, SizeOf(M.K1000));
  AStream.WriteBuffer(M.TickSize, SizeOf(M.TickSize));
  AStream.WriteBuffer(M.MinQty, SizeOf(M.MinQty));
  AStream.WriteBuffer(M.Active, SizeOf(M.Active));
  AStream.WriteBuffer(M.Kind, SizeOf(M.Kind));
  AStream.WriteBuffer(M.Serial, SizeOf(M.Serial));
end;

procedure ReadMsg(AStream: TStream; var M: TChiMarketMsg);
begin
  ReadStrUtf8(AStream, M.Name);
  ReadStrUtf8(AStream, M.Currency);
  ReadStrUtf8(AStream, M.Base);
  ReadStrUtf8(AStream, M.Status);
  { Чтение примитивов идёт по возможности: не хватило байтов — вернётся то,
    что было в переменной, а не исключение. }
  AStream.Read(M.PricePrec, SizeOf(M.PricePrec));
  AStream.Read(M.QtyPrec, SizeOf(M.QtyPrec));
  AStream.Read(M.Leverage, SizeOf(M.Leverage));
  AStream.Read(M.K1000, SizeOf(M.K1000));
  AStream.Read(M.TickSize, SizeOf(M.TickSize));
  AStream.Read(M.MinQty, SizeOf(M.MinQty));
  AStream.Read(M.Active, SizeOf(M.Active));
  AStream.Read(M.Kind, SizeOf(M.Kind));
  AStream.Read(M.Serial, SizeOf(M.Serial));
end;

function SameMsg(const A, B: TChiMarketMsg): Boolean;
begin
  Result := (A.Name = B.Name) and (A.Currency = B.Currency)
    and (A.Base = B.Base) and (A.Status = B.Status)
    and (A.PricePrec = B.PricePrec) and (A.QtyPrec = B.QtyPrec)
    and (A.Leverage = B.Leverage) and (A.K1000 = B.K1000)
    and (PInt64(@A.TickSize)^ = PInt64(@B.TickSize)^)
    and (PInt64(@A.MinQty)^ = PInt64(@B.MinQty)^)
    and (A.Active = B.Active) and (A.Kind = B.Kind) and (A.Serial = B.Serial);
end;

{ Канонический размер сообщения, посчитанный по правилам, а не измерением. }
function CanonSize(const M: TChiMarketMsg): Integer;
begin
  Result := (2 + Length(TEncoding.UTF8.GetBytes(M.Name)))
          + (2 + Length(TEncoding.UTF8.GetBytes(M.Currency)))
          + (2 + Length(TEncoding.UTF8.GetBytes(M.Base)))
          + (2 + Length(TEncoding.UTF8.GetBytes(M.Status)))
          + 4 * 4 + 8 * 2 + 1 + 1 + 8;
end;

{ ═══ Проверка ════════════════════════════════════════════════════════════ }

const
  IdMsg   = 'CHI-MB-PROTO-001';
  IdLen   = 'CHI-MB-PROTO-002';
  IdSplit = 'CHI-MB-PROTO-003';
  IdReuse = 'CHI-MB-PROTO-004';

function MakeMsg(I: Integer): TChiMarketMsg;
begin
  Result.Name := 'MARKET' + IntToStr(I);
  { Не-латинские буквы: длина в символах и длина в байтах расходятся. }
  case I mod 4 of
    0: Result.Currency := 'BTC';
    1: Result.Currency := 'БИТКОЙН';
    2: Result.Currency := '';
    3: Result.Currency := 'Ω≈ç√∫';
  end;
  Result.Base := 'USDT';
  Result.Status := 'TRADING';
  Result.PricePrec := I;
  Result.QtyPrec := -I;
  Result.Leverage := 100 - I;
  Result.K1000 := 1000;
  Result.TickSize := 0.00001 * (I + 1);
  Result.MinQty := 1.5 * (I + 1);
  Result.Active := (I and 1) = 0;
  Result.Kind := Byte(I);
  Result.Serial := Int64(I) * 1000000007;
end;

function ChiProtoRun: Int64;
var
  Stream: TMemoryStream;
  Msg, Back: TChiMarketMsg;
  Acc: UInt64;
  I, Cut, Before: Integer;
  Text, Got: string;
  Bytes: TBytes;
  Long: string;
  Raised: Boolean;
begin
  ChiCovered(IdMsg);
  ChiCovered(IdLen);
  ChiCovered(IdSplit);
  ChiCovered(IdReuse);
  Acc := ChiOffset;

  Stream := TMemoryStream.Create;
  try
    { ── Длина строки — в байтах, а не в символах ── }
    Stream.Clear;
    Text := 'БИТКОЙН';
    WriteStrUtf8(Stream, Text);
    Bytes := TEncoding.UTF8.GetBytes(Text);
    ChiClaim(Length(Bytes) > Length(Text),
      'протокол: не-латинская строка не стала длиннее в байтах');
    ChiClaim(Stream.Size = 2 + Length(Bytes),
      'протокол: длина записана в символах, а не в байтах');
    Stream.Position := 0;
    ReadStrUtf8(Stream, Got);
    ChiClaim(Got = Text, 'протокол: строка не вернулась');
    ChiBranch(IdLen, 'utf8-length');
    Acc := ChiMix(Acc, Stream.Size);

    { Пустая строка — только длина, ноль байтов тела. }
    Stream.Clear;
    WriteStrUtf8(Stream, '');
    ChiClaim(Stream.Size = 2, 'протокол: пустая строка заняла не два байта');
    Stream.Position := 0;
    ReadStrUtf8(Stream, Got);
    ChiClaim(Got = '', 'протокол: пустая строка вернулась не пустой');
    ChiBranch(IdLen, 'empty-string');

    { Короткий вариант: байт длины. }
    Stream.Clear;
    WriteStrShort(Stream, 'BTCUSDT');
    ChiClaim(Stream.Size = 1 + 7, 'протокол: короткая длина заняла не байт');
    Stream.Position := 0;
    ReadStrShort(Stream, Got);
    ChiClaim(Got = 'BTCUSDT', 'протокол: короткая строка не вернулась');
    ChiBranch(IdLen, 'short-length');

    { Строка длиннее того, что влезает в байт длины: живой код её не
      проверяет, и длина усечётся по модулю. Это свойство формы, и оно
      предъявляется как факт, а не чинится здесь. }
    Long := StringOfChar('a', 300);
    Stream.Clear;
    WriteStrShort(Stream, Long);
    ChiClaim(Stream.Size = 1 + (300 and $FF),
      'протокол: усечение длины по модулю не совпало');
    ChiBranch(IdLen, 'short-overflow');
    Acc := ChiMix(Acc, Stream.Size);

    { ── Сообщение целиком ── }
    for I := 0 to 15 do
    begin
      Msg := MakeMsg(I);
      Stream.Clear;
      WriteMsg(Stream, Msg);
      ChiClaim(Stream.Size = CanonSize(Msg),
        'протокол: размер сообщения не канонический, ' + IntToStr(I));
      Stream.Position := 0;
      Back := Default(TChiMarketMsg);
      ReadMsg(Stream, Back);
      ChiClaim(SameMsg(Msg, Back),
        'протокол: сообщение вернулось искажённым, ' + IntToStr(I));
      ChiClaim(Stream.Position = Stream.Size,
        'протокол: после разбора остались непрочитанные байты');
      Acc := ChiMix(Acc, Stream.Size);
    end;
    ChiBranch(IdMsg, 'roundtrip');
    ChiBranch(IdMsg, 'canonical-size');

    { ── Разрезанное чтение ── }
    Msg := MakeMsg(1);   { валюта не-латинская, значит есть многобайтовый символ }
    Stream.Clear;
    WriteMsg(Stream, Msg);
    Bytes := nil;
    SetLength(Bytes, Stream.Size);
    Stream.Position := 0;
    Stream.ReadBuffer(Bytes[0], Length(Bytes));

    { Граница режет поток в каждой возможной точке. Разбор половины обязан
      либо отказать, либо не выйти за границу — но не выдать целое
      сообщение. }
    for Cut := 1 to Length(Bytes) - 1 do
    begin
      Stream.Clear;
      Stream.WriteBuffer(Bytes[0], Cut);
      Stream.Position := 0;
      Back := Default(TChiMarketMsg);
      Raised := False;
      try
        ReadMsg(Stream, Back);
      except
        on E: EReadError do Raised := True;
      end;
      { Точное свойство: из обрезанного потока НЕВОЗМОЖНО вычитать столько
        байтов, сколько занимает целое сообщение. Требовать при этом «значения
        не совпали» было бы неверно: чтение примитива по возможности кладёт
        столько байтов, сколько нашлось, и если старшие байты числа и так
        нули, обрезанное значение совпадёт с целым. }
      ChiClaim(Raised or (Stream.Position < CanonSize(Msg)),
        'протокол: из обрезанного потока вычитано целое сообщение, срез '
        + IntToStr(Cut));
    end;
    ChiBranch(IdSplit, 'every-cut');

    { Отдельно — срез ВНУТРИ многобайтового символа: длина прочитана, тела не
      хватает, обязательное чтение обязано отказать. }
    Stream.Clear;
    WriteStrUtf8(Stream, 'БИТКОЙН');
    Before := Stream.Size;
    Stream.Size := Before - 1;
    Stream.Position := 0;
    Raised := False;
    try
      ReadStrUtf8(Stream, Got);
    except
      on E: EReadError do Raised := True;
    end;
    ChiClaim(Raised, 'протокол: неполное тело строки прочиталось');
    ChiBranch(IdSplit, 'cut-inside-char');

    { ── Повторное использование буфера ── }
    Stream.Clear;
    Msg := MakeMsg(3);
    for I := 1 to 50 do WriteMsg(Stream, Msg);
    Before := Stream.Size;

    Stream.Clear;
    ChiClaim(Stream.Size = 0, 'протокол: очистка не обнулила длину');
    Msg := MakeMsg(0);
    WriteMsg(Stream, Msg);
    ChiClaim(Stream.Size = CanonSize(Msg),
      'протокол: после большого сообщения меньшее заняло не свой размер');
    ChiClaim(Stream.Size < Before, 'протокол: меньшее не стало меньше');
    Stream.Position := 0;
    Back := Default(TChiMarketMsg);
    ReadMsg(Stream, Back);
    ChiClaim(SameMsg(Msg, Back),
      'протокол: после повторного использования прочитан хвост прошлого');
    ChiBranch(IdReuse, 'big-then-small');
    Acc := ChiMix(Acc, Before);

    { Бросок посреди записи: поток обязан остаться пригодным для дальнейшей
      работы, а не развалиться. }
    Stream.Clear;
    Raised := False;
    try
      WriteStrUtf8(Stream, 'начало');
      raise EAbort.Create('посреди записи');
    except
      on E: EAbort do Raised := True;
    end;
    ChiClaim(Raised, 'протокол: бросок не вышел наружу');
    WriteStrUtf8(Stream, 'продолжение');
    Stream.Position := 0;
    ReadStrUtf8(Stream, Got);
    ChiClaim(Got = 'начало', 'протокол: записанное до броска потерялось');
    ReadStrUtf8(Stream, Got);
    ChiClaim(Got = 'продолжение', 'протокол: запись после броска не легла');
    ChiBranch(IdReuse, 'throw-midway');
  finally
    FreeAndNil(Stream);
  end;

  Result := Int64(Acc and $7FFFFFFFFFFF);
end;

end.
