unit chimera_field;

{ Орган «поля»: самоописывающийся поток настроек и плоская запись рынка.

  ── CHI-MB-FIELD-001 ──────────────────────────────────────────────────────
  Источник: `MoonBot/MoonProto\StrategySerializer.pas` — так
  ездят настройки стратегий. Перенесено дословно по форме:

    * поле едет как БАЙТ КОДА ТИПА, за которым значение; размер значения
      известен из кода, строка несёт свою длину двумя байтами;
    * если значение «нулевое», старший бит кода поднимается, и значения не
      едет вовсе. Читатель, увидев поднятый бит, значение не читает;
    * дробное считается нулевым по МОДУЛЮ МЕНЬШЕ порога — то есть очень малое
      ненулевое значение уезжает нулём. Это свойство формата, а не оплошность
      записи, и оно предъявлено отдельно;
    * незнакомое поле не ломает разбор: читатель пропускает его по размеру,
      который выводит из кода. Неизвестный код пропускается ВОСЕМЬЮ байтами
      вслепую — это последняя догадка формата, и она тоже предъявлена;
    * имена полей едут не строками, а номерами: словарь имя→номер выдаёт
      повторному имени ПРЕЖНИЙ номер.

  ── CHI-MB-PROTO-005 ──────────────────────────────────────────────────────
  Источник: `MoonBot/MoonProto\MoonProtoSerialization.pas` ::
  `WriteMarketToStream` / `ReadMarketFromStream`. Форма противоположная
  первой: сорок с лишним полей едут ПОДРЯД, без всяких кодов, и держатся
  только на том, что читатель повторяет порядок записи в точности. Читатель
  разбирает их в сорок с лишним локальных переменных и лишь потом раскладывает
  по месту, а рынок, который ему не нужен, всё равно вычитывает целиком —
  иначе поток съедет на следующем.

  Заменено оснасткой: механизм разбора описаний типов (он принадлежит языку,
  а не форме потока) — коды типов здесь задаются прямо.

  Оракулы:

    1. каждый код типа предъявляется таблицей: записанное значение читается
       обратно тем же значением, а длина записи равна обещанной кодом;
    2. поток с незнакомым полем посередине разбирается так же, как без него —
       сверяются ВСЕ последующие поля;
    3. плоская запись сверяется двусторонне: круговой обход поле в поле и
       длина потока, посчитанная по правилам, а не измеренная;
    4. вычитывание ненужного рынка проверяется тем, что следующий за ним
       читается верно. }

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch INLINEVARS}
{$endif}
{$Q-}{$R-}

interface

uses
  SysUtils, Classes, Math, Generics.Collections,
  mormot.core.base, chimera_body;

function ChiFieldRun: Int64;

implementation

const
  IdField = 'CHI-MB-FIELD-001';
  IdFlat  = 'CHI-MB-PROTO-005';

  TID_Bool   = 1;
  TID_Int32  = 2;
  TID_Int64  = 3;
  TID_Double = 4;
  TID_String = 5;
  TID_Byte   = 6;
  TID_Word   = 7;
  TID_UInt32 = 8;
  TID_UInt64 = 9;
  TID_Single = 10;

  TID_ZERO_FLAG = $80;

{ ═══ Самоописывающийся поток ═════════════════════════════════════════════ }

function TypeIDToSize(TypeID: Byte): Integer;
var
  RealTypeID: Byte;
begin
  RealTypeID := TypeID and $7F;
  case RealTypeID of
    TID_Bool:   Result := 1;
    TID_Byte:   Result := 1;
    TID_Word:   Result := 2;
    TID_Int32:  Result := 4;
    TID_UInt32: Result := 4;
    TID_Single: Result := 4;
    TID_Int64:  Result := 8;
    TID_UInt64: Result := 8;
    TID_Double: Result := 8;
    TID_String: Result := -1;
  else
    Result := 0;
  end;
end;

procedure SkipFieldByTypeID(Stream: TMemoryStream; TypeID: Byte);
var
  Len:        Word;
  Sz:         Integer;
  RealTypeID: Byte;
begin
  if (TypeID and TID_ZERO_FLAG) <> 0 then Exit;

  RealTypeID := TypeID and $7F;
  Sz := TypeIDToSize(RealTypeID);
  if Sz > 0 then
    Stream.Position := Stream.Position + Sz
  else if RealTypeID = TID_String then
  begin
    Stream.Read(Len, 2);
    Stream.Position := Stream.Position + Len;
  end
  else
    Stream.Position := Stream.Position + 8;
end;

procedure SkipField(Stream: TMemoryStream);
var
  TypeID: Byte;
begin
  TypeID := 0;
  Stream.Read(TypeID, 1);
  SkipFieldByTypeID(Stream, TypeID);
end;

type
  { Значение поля в том виде, в каком его знает поток: код типа и место под
    любое из значений. Отдельная запись нужна затем, чтобы проверка шла по
    таблице, а не по сорока отдельным вызовам. }
  TChiFieldValue = record
    TypeID: Byte;
    I:      Int64;
    U:      UInt64;
    D:      Double;
    F:      Single;
    S:      RawByteString;
    B:      Boolean;
  end;

function IsZeroValue(const V: TChiFieldValue): Boolean;
begin
  case V.TypeID of
    TID_Bool:
      Result := not V.B;
    TID_Byte, TID_Word, TID_Int32, TID_UInt32:
      Result := V.I = 0;
    TID_Int64:
      Result := V.I = 0;
    TID_UInt64:
      Result := V.U = 0;
    TID_Single:
      Result := Abs(V.F) < 1E-10;
    TID_Double:
      Result := Abs(V.D) < 1E-10;
    TID_String:
      Result := V.S = '';
  else
    Result := False;
  end;
end;

procedure WriteField(Stream: TMemoryStream; const V: TChiFieldValue);
var
  Len:         Word;
  U8:          Byte;
  U16:         Word;
  I32:         Int32;
  U32:         UInt32;
  I64:         Int64;
  U64:         UInt64;
  D:           Double;
  F:           Single;
  BVal:        Boolean;
  WriteTypeID: Byte;
begin
  if IsZeroValue(V) then
  begin
    WriteTypeID := V.TypeID or TID_ZERO_FLAG;
    Stream.Write(WriteTypeID, 1);
    Exit;
  end;

  Stream.Write(V.TypeID, 1);

  case V.TypeID of
    TID_Bool:
      begin
        BVal := V.B;
        Stream.Write(BVal, 1);
      end;
    TID_Byte:
      begin
        U8 := Byte(V.I);
        Stream.Write(U8, 1);
      end;
    TID_Word:
      begin
        U16 := Word(V.I);
        Stream.Write(U16, 2);
      end;
    TID_Int32:
      begin
        I32 := Int32(V.I);
        Stream.Write(I32, 4);
      end;
    TID_UInt32:
      begin
        U32 := UInt32(V.I);
        Stream.Write(U32, 4);
      end;
    TID_Int64:
      begin
        I64 := V.I;
        Stream.Write(I64, 8);
      end;
    TID_UInt64:
      begin
        U64 := V.U;
        Stream.Write(U64, 8);
      end;
    TID_Single:
      begin
        F := V.F;
        Stream.Write(F, 4);
      end;
    TID_Double:
      begin
        D := V.D;
        Stream.Write(D, 8);
      end;
    TID_String:
      begin
        Len := Length(V.S);
        Stream.Write(Len, 2);
        if Len > 0 then Stream.Write(Pointer(V.S)^, Len);
      end;
  end;
end;

function ReadField(Stream: TMemoryStream; out V: TChiFieldValue): Boolean;
var
  TypeID: Byte;
  Len:    Word;
  U8:     Byte;
  U16:    Word;
  I32:    Int32;
  U32:    UInt32;
begin
  V := Default(TChiFieldValue);
  TypeID := 0;
  Result := Stream.Read(TypeID, 1) = 1;
  if not Result then Exit;

  V.TypeID := TypeID and $7F;
  if (TypeID and TID_ZERO_FLAG) <> 0 then
    Exit;   { нулевое: значения в потоке нет }

  case V.TypeID of
    TID_Bool:   Stream.Read(V.B, 1);
    TID_Byte:   begin U8 := 0;  Stream.Read(U8, 1);  V.I := U8; end;
    TID_Word:   begin U16 := 0; Stream.Read(U16, 2); V.I := U16; end;
    TID_Int32:  begin I32 := 0; Stream.Read(I32, 4); V.I := I32; end;
    TID_UInt32: begin U32 := 0; Stream.Read(U32, 4); V.I := U32; end;
    TID_Int64:  Stream.Read(V.I, 8);
    TID_UInt64: Stream.Read(V.U, 8);
    TID_Single: Stream.Read(V.F, 4);
    TID_Double: Stream.Read(V.D, 8);
    TID_String:
      begin
        Len := 0;
        Stream.Read(Len, 2);
        SetLength(V.S, Len);
        if Len > 0 then Stream.Read(Pointer(V.S)^, Len);
      end;
  else
    Result := False;
  end;
end;

type
  { Словарь имён: повторному имени выдаётся прежний номер. }
  TChiNameWriter = class
  private
    FDict:  TDictionary<string, Word>;
    FNames: TList<string>;
  public
    constructor Create;
    destructor Destroy; override;
    function GetIndex(const AName: string): Word;
    property Names: TList<string> read FNames;
  end;

constructor TChiNameWriter.Create;
begin
  inherited Create;
  FDict := TDictionary<string, Word>.Create;
  FNames := TList<string>.Create;
end;

destructor TChiNameWriter.Destroy;
begin
  FreeAndNil(FNames);
  FreeAndNil(FDict);
  inherited Destroy;
end;

function TChiNameWriter.GetIndex(const AName: string): Word;
begin
  if FDict.TryGetValue(AName, Result) then Exit;
  Result := FNames.Count;
  FNames.Add(AName);
  FDict.Add(AName, Result);
end;

{ ═══ Плоская запись рынка ════════════════════════════════════════════════ }

type
  { Ровно те поля и ровно в том порядке, в каком они едут в живом потоке. }
  TChiMarketWire = record
    Name, Currency, WireCurrency, Base, Long, Canonic: RawByteString;
    Display, Classic, Status, Leading:                 RawByteString;
    PricePrecision, QtyPrecision, MaxLeverage:         Integer;
    K1000, IcebergParts, MarginTableID:                Integer;
    DeliveryTime:                                      Int64;
    TickSize, StepSize, MinQty, MaxQty:                Double;
    MinNotional, MaxNotional, ContractSize:            Double;
    MinPrice, MaxPrice, MaxValue:                      Double;
    MultiplierUp, MultiplierDown:                      Double;
    BidMultiplierUp, BidMultiplierDown:                Double;
    AskMultiplierUp, AskMultiplierDown:                Double;
    IntMaxQty, FundingRate, FundingTime, Volume:       Double;
    IsBTC, StatusTrading, IsOddLot, Iceberg, Isolated: Boolean;
    FuturesKind:                                       Byte;
  end;

procedure WStr(Stream: TMemoryStream; const S: RawByteString);
var
  N: Integer;
begin
  N := Length(S);
  Stream.Write(N, SizeOf(N));
  if N > 0 then Stream.Write(Pointer(S)^, N);
end;

procedure RStr(Stream: TMemoryStream; out S: RawByteString);
var
  N: Integer;
begin
  N := 0;
  Stream.Read(N, SizeOf(N));
  SetLength(S, N);
  if N > 0 then Stream.Read(Pointer(S)^, N);
end;

procedure WInt(Stream: TMemoryStream; V: Integer);   begin Stream.Write(V, 4); end;
procedure WI64(Stream: TMemoryStream; V: Int64);     begin Stream.Write(V, 8); end;
procedure WDbl(Stream: TMemoryStream; V: Double);    begin Stream.Write(V, 8); end;
procedure WBool(Stream: TMemoryStream; V: Boolean);  begin Stream.Write(V, 1); end;
procedure WByte(Stream: TMemoryStream; V: Byte);     begin Stream.Write(V, 1); end;

function RInt(Stream: TMemoryStream): Integer;  begin Result := 0; Stream.Read(Result, 4); end;
function RI64(Stream: TMemoryStream): Int64;    begin Result := 0; Stream.Read(Result, 8); end;
function RDbl(Stream: TMemoryStream): Double;   begin Result := 0; Stream.Read(Result, 8); end;
function RBool(Stream: TMemoryStream): Boolean; begin Result := False; Stream.Read(Result, 1); end;
function RByte(Stream: TMemoryStream): Byte;    begin Result := 0; Stream.Read(Result, 1); end;

{ Сдвиг пояса уезжает вычтенным ровно из одного поля — и только когда оно
  непустое; ноль остаётся нулём. }
procedure WriteMarket(Stream: TMemoryStream; const M: TChiMarketWire; TZShift: Double);
begin
  WStr(Stream, M.Name);
  WStr(Stream, M.Currency);
  WStr(Stream, M.WireCurrency);
  WStr(Stream, M.Base);
  WStr(Stream, M.Long);
  WStr(Stream, M.Canonic);
  WStr(Stream, M.Display);
  WStr(Stream, M.Classic);
  WStr(Stream, M.Status);
  WStr(Stream, M.Leading);

  WInt(Stream, M.PricePrecision);
  WInt(Stream, M.QtyPrecision);
  WInt(Stream, M.MaxLeverage);
  WInt(Stream, M.K1000);
  WInt(Stream, M.IcebergParts);
  WInt(Stream, M.MarginTableID);

  WI64(Stream, M.DeliveryTime);

  WDbl(Stream, M.TickSize);
  WDbl(Stream, M.StepSize);
  WDbl(Stream, M.MinQty);
  WDbl(Stream, M.MaxQty);
  WDbl(Stream, M.MinNotional);
  WDbl(Stream, M.MaxNotional);
  WDbl(Stream, M.ContractSize);
  WDbl(Stream, M.MinPrice);
  WDbl(Stream, M.MaxPrice);
  WDbl(Stream, M.MaxValue);
  WDbl(Stream, M.MultiplierUp);
  WDbl(Stream, M.MultiplierDown);
  WDbl(Stream, M.BidMultiplierUp);
  WDbl(Stream, M.BidMultiplierDown);
  WDbl(Stream, M.AskMultiplierUp);
  WDbl(Stream, M.AskMultiplierDown);
  WDbl(Stream, M.IntMaxQty);
  WDbl(Stream, M.FundingRate);
  if M.FundingTime > 0
    then WDbl(Stream, M.FundingTime - TZShift)
    else WDbl(Stream, 0);
  WDbl(Stream, M.Volume);

  WBool(Stream, M.IsBTC);
  WBool(Stream, M.StatusTrading);
  WBool(Stream, M.IsOddLot);
  WBool(Stream, M.Iceberg);
  WBool(Stream, M.Isolated);

  WByte(Stream, M.FuturesKind);
end;

{ Читатель повторяет порядок в точности и складывает всё в свои переменные,
  прежде чем что-то отдать наружу. Когда рынок не нужен, поля всё равно
  вычитываются: иначе съедет следующий. }
procedure ReadMarket(Stream: TMemoryStream; TZShift: Double; AWanted: Boolean;
  var M: TChiMarketWire);
var
  sName, sCurrency, sWireCurrency, sBase, sLong, sCanonic:      RawByteString;
  sDisplay, sClassic, sStatus, sLeading:                        RawByteString;
  iPricePrecision, iQtyPrecision, iMaxLeverage:                 Integer;
  iK1000, iIcebergParts, iMarginTableID:                        Integer;
  iDeliveryTime:                                                Int64;
  dTick, dStep, dMinQty, dMaxQty, dMinNotional, dMaxNotional:   Double;
  dContract, dMinPrice, dMaxPrice, dMaxValue:                   Double;
  dMulUp, dMulDown, dBidUp, dBidDown, dAskUp, dAskDown:         Double;
  dIntMaxQty, dFundingRate, dFundingTime, dVolume:              Double;
  bIsBTC, bTrading, bOddLot, bIceberg, bIsolated:               Boolean;
  yFutures:                                                     Byte;
begin
  RStr(Stream, sName);
  RStr(Stream, sCurrency);
  RStr(Stream, sWireCurrency);
  RStr(Stream, sBase);
  RStr(Stream, sLong);
  RStr(Stream, sCanonic);
  RStr(Stream, sDisplay);
  RStr(Stream, sClassic);
  RStr(Stream, sStatus);
  RStr(Stream, sLeading);

  iPricePrecision := RInt(Stream);
  iQtyPrecision := RInt(Stream);
  iMaxLeverage := RInt(Stream);
  iK1000 := RInt(Stream);
  iIcebergParts := RInt(Stream);
  iMarginTableID := RInt(Stream);

  iDeliveryTime := RI64(Stream);

  dTick := RDbl(Stream);
  dStep := RDbl(Stream);
  dMinQty := RDbl(Stream);
  dMaxQty := RDbl(Stream);
  dMinNotional := RDbl(Stream);
  dMaxNotional := RDbl(Stream);
  dContract := RDbl(Stream);
  dMinPrice := RDbl(Stream);
  dMaxPrice := RDbl(Stream);
  dMaxValue := RDbl(Stream);
  dMulUp := RDbl(Stream);
  dMulDown := RDbl(Stream);
  dBidUp := RDbl(Stream);
  dBidDown := RDbl(Stream);
  dAskUp := RDbl(Stream);
  dAskDown := RDbl(Stream);
  dIntMaxQty := RDbl(Stream);
  dFundingRate := RDbl(Stream);
  dFundingTime := RDbl(Stream);
  dVolume := RDbl(Stream);

  bIsBTC := RBool(Stream);
  bTrading := RBool(Stream);
  bOddLot := RBool(Stream);
  bIceberg := RBool(Stream);
  bIsolated := RBool(Stream);

  yFutures := RByte(Stream);

  if not AWanted then Exit;

  M.Name := sName;
  M.Currency := sCurrency;
  M.WireCurrency := sWireCurrency;
  M.Base := sBase;
  M.Long := sLong;
  M.Canonic := sCanonic;
  M.Display := sDisplay;
  M.Classic := sClassic;
  M.Status := sStatus;
  M.Leading := sLeading;
  M.PricePrecision := iPricePrecision;
  M.QtyPrecision := iQtyPrecision;
  M.MaxLeverage := iMaxLeverage;
  M.K1000 := iK1000;
  M.IcebergParts := iIcebergParts;
  M.MarginTableID := iMarginTableID;
  M.DeliveryTime := iDeliveryTime;
  M.TickSize := dTick;
  M.StepSize := dStep;
  M.MinQty := dMinQty;
  M.MaxQty := dMaxQty;
  M.MinNotional := dMinNotional;
  M.MaxNotional := dMaxNotional;
  M.ContractSize := dContract;
  M.MinPrice := dMinPrice;
  M.MaxPrice := dMaxPrice;
  M.MaxValue := dMaxValue;
  M.MultiplierUp := dMulUp;
  M.MultiplierDown := dMulDown;
  M.BidMultiplierUp := dBidUp;
  M.BidMultiplierDown := dBidDown;
  M.AskMultiplierUp := dAskUp;
  M.AskMultiplierDown := dAskDown;
  M.IntMaxQty := dIntMaxQty;
  M.FundingRate := dFundingRate;
  if dFundingTime > 0
    then M.FundingTime := dFundingTime + TZShift
    else M.FundingTime := 0;
  M.Volume := dVolume;
  M.IsBTC := bIsBTC;
  M.StatusTrading := bTrading;
  M.IsOddLot := bOddLot;
  M.Iceberg := bIceberg;
  M.Isolated := bIsolated;
  M.FuturesKind := yFutures;
end;

{ ═══ Оснастка ════════════════════════════════════════════════════════════ }

function MakeMarket(ASeed: UInt64; AWithFunding: Boolean): TChiMarketWire;
var
  Src: TChiSource;
begin
  Src := ChiSource(ASeed);
  Result := Default(TChiMarketWire);
  Result.Name := RawByteString('MKT' + IntToStr(Src.NextBelow(1000)));
  Result.Currency := RawByteString('CCY' + IntToStr(Src.NextBelow(1000)));
  Result.WireCurrency := Result.Currency;
  Result.Base := RawByteString('USDT');
  Result.Long := RawByteString('');           { пустая строка — законное поле }
  Result.Canonic := RawByteString('CANON');
  Result.Display := RawByteString('DISP');
  Result.Classic := RawByteString('CLASSIC');
  Result.Status := RawByteString('TRADING');
  Result.Leading := RawByteString('1000');
  Result.PricePrecision := Src.NextBelow(9);
  Result.QtyPrecision := Src.NextBelow(9);
  Result.MaxLeverage := Src.NextBelow(126);
  Result.K1000 := 1000;
  Result.IcebergParts := Src.NextBelow(10);
  Result.MarginTableID := -1;                 { отрицательное целое }
  Result.DeliveryTime := Int64(1756500000000);
  Result.TickSize := 0.00000001;
  Result.StepSize := 0.001;
  Result.MinQty := 0.0001;
  Result.MaxQty := 1E9;
  Result.MinNotional := 5;
  Result.MaxNotional := 1E12;
  Result.ContractSize := 1;
  Result.MinPrice := 0;                       { ноль тоже едет }
  Result.MaxPrice := 1E7;
  Result.MaxValue := 1E8;
  Result.MultiplierUp := 1.05;
  Result.MultiplierDown := 0.95;
  Result.BidMultiplierUp := 1.02;
  Result.BidMultiplierDown := 0.98;
  Result.AskMultiplierUp := 1.03;
  Result.AskMultiplierDown := 0.97;
  Result.IntMaxQty := 12345.678;
  Result.FundingRate := -0.0001;              { отрицательное дробное }
  if AWithFunding
    then Result.FundingTime := 45900.25
    else Result.FundingTime := 0;
  Result.Volume := 987654321.125;
  Result.IsBTC := True;
  Result.StatusTrading := True;
  Result.IsOddLot := False;
  Result.Iceberg := True;
  Result.Isolated := False;
  Result.FuturesKind := 2;
end;

function SameMarket(const A, B: TChiMarketWire): Boolean;
begin
  Result := (A.Name = B.Name) and (A.Currency = B.Currency) and
            (A.WireCurrency = B.WireCurrency) and (A.Base = B.Base) and
            (A.Long = B.Long) and (A.Canonic = B.Canonic) and
            (A.Display = B.Display) and (A.Classic = B.Classic) and
            (A.Status = B.Status) and (A.Leading = B.Leading) and
            (A.PricePrecision = B.PricePrecision) and (A.QtyPrecision = B.QtyPrecision) and
            (A.MaxLeverage = B.MaxLeverage) and (A.K1000 = B.K1000) and
            (A.IcebergParts = B.IcebergParts) and (A.MarginTableID = B.MarginTableID) and
            (A.DeliveryTime = B.DeliveryTime) and
            (A.TickSize = B.TickSize) and (A.StepSize = B.StepSize) and
            (A.MinQty = B.MinQty) and (A.MaxQty = B.MaxQty) and
            (A.MinNotional = B.MinNotional) and (A.MaxNotional = B.MaxNotional) and
            (A.ContractSize = B.ContractSize) and (A.MinPrice = B.MinPrice) and
            (A.MaxPrice = B.MaxPrice) and (A.MaxValue = B.MaxValue) and
            (A.MultiplierUp = B.MultiplierUp) and (A.MultiplierDown = B.MultiplierDown) and
            (A.BidMultiplierUp = B.BidMultiplierUp) and (A.BidMultiplierDown = B.BidMultiplierDown) and
            (A.AskMultiplierUp = B.AskMultiplierUp) and (A.AskMultiplierDown = B.AskMultiplierDown) and
            (A.IntMaxQty = B.IntMaxQty) and (A.FundingRate = B.FundingRate) and
            (A.Volume = B.Volume) and (A.IsBTC = B.IsBTC) and
            (A.StatusTrading = B.StatusTrading) and (A.IsOddLot = B.IsOddLot) and
            (A.Iceberg = B.Iceberg) and (A.Isolated = B.Isolated) and
            (A.FuturesKind = B.FuturesKind);
end;

{ Длина потока, посчитанная по правилам, а не измеренная. }
function WireSize(const M: TChiMarketWire): Integer;
begin
  Result := 10 * 4 +
            Length(M.Name) + Length(M.Currency) + Length(M.WireCurrency) +
            Length(M.Base) + Length(M.Long) + Length(M.Canonic) +
            Length(M.Display) + Length(M.Classic) + Length(M.Status) +
            Length(M.Leading) +
            6 * 4 + 8 + 20 * 8 + 5 * 1 + 1;
end;

{ ═══ Прогон ══════════════════════════════════════════════════════════════ }

function ChiFieldRun: Int64;
var
  Acc:    UInt64;
  ms:     TMemoryStream;
  V, Got: TChiFieldValue;
  Names:  TChiNameWriter;
  M, B:   TChiMarketWire;
  TZ:     Double;
begin
  Acc := 0;

  { ── Самоописывающийся поток ── }
  ChiCovered(IdField);
  ms := TMemoryStream.Create;
  try
    { Таблица: каждый код типа, непустое значение, обещанная длина. }
    var Table: array [0 .. 9] of TChiFieldValue;
    Table[0] := Default(TChiFieldValue); Table[0].TypeID := TID_Bool;   Table[0].B := True;
    Table[1] := Default(TChiFieldValue); Table[1].TypeID := TID_Byte;   Table[1].I := 250;
    Table[2] := Default(TChiFieldValue); Table[2].TypeID := TID_Word;   Table[2].I := 65500;
    Table[3] := Default(TChiFieldValue); Table[3].TypeID := TID_Int32;  Table[3].I := -123456;
    Table[4] := Default(TChiFieldValue); Table[4].TypeID := TID_UInt32; Table[4].I := 4000000000;
    Table[5] := Default(TChiFieldValue); Table[5].TypeID := TID_Int64;  Table[5].I := -Int64(1) shl 40;
    Table[6] := Default(TChiFieldValue); Table[6].TypeID := TID_UInt64; Table[6].U := UInt64($FFFFFFFFFFFFFFFF);
    Table[7] := Default(TChiFieldValue); Table[7].TypeID := TID_Single; Table[7].F := -1.5;
    Table[8] := Default(TChiFieldValue); Table[8].TypeID := TID_Double; Table[8].D := 3.14159265358979;
    Table[9] := Default(TChiFieldValue); Table[9].TypeID := TID_String; Table[9].S := RawByteString('слово');

    for var I := 0 to High(Table) do
    begin
      ms.Size := 0;
      ms.Position := 0;
      WriteField(ms, Table[I]);
      var Want := TypeIDToSize(Table[I].TypeID);
      if Want > 0
        then ChiClaim(ms.Size = 1 + Want, 'поле: длина записи не та, что обещает код типа')
        else ChiClaim(ms.Size = 1 + 2 + Length(Table[I].S), 'поле: длина строки не та');
      ms.Position := 0;
      ChiClaim(ReadField(ms, Got), 'поле: чтение отказалось');
      ChiClaim(Got.TypeID = Table[I].TypeID, 'поле: код типа изменился');
      case Got.TypeID of
        TID_Bool:   ChiClaim(Got.B = Table[I].B, 'поле: логическое не сошлось');
        TID_Single: ChiClaim(Got.F = Table[I].F, 'поле: дробное одинарной точности не сошлось');
        TID_Double: ChiClaim(Got.D = Table[I].D, 'поле: дробное не сошлось');
        TID_String: ChiClaim(Got.S = Table[I].S, 'поле: строка не сошлась');
        TID_UInt64: ChiClaim(Got.U = Table[I].U, 'поле: беззнаковое не сошлось');
      else
        ChiClaim(Got.I = Table[I].I, 'поле: целое не сошлось');
      end;
      ChiClaim(ms.Position = ms.Size, 'поле: чтение съело не всё');
      Acc := ChiMix(Acc, ms.Size);
    end;
    ChiBranch(IdField, 'every-type-roundtrip');

    { Нулевое значение: один байт вместо девяти, и старший бит поднят. }
    V := Default(TChiFieldValue);
    V.TypeID := TID_Double;
    V.D := 0;
    ms.Size := 0;
    ms.Position := 0;
    WriteField(ms, V);
    ChiClaim(ms.Size = 1, 'поле: нулевое дробное заняло не один байт');
    ChiClaim(PByte(ms.Memory)^ = (TID_Double or TID_ZERO_FLAG), 'поле: признак нуля не поднят');
    ms.Position := 0;
    ChiClaim(ReadField(ms, Got), 'поле: нулевое не прочиталось');
    ChiClaim((Got.TypeID = TID_Double) and (Got.D = 0), 'поле: нулевое прочиталось не нулём');
    ChiBranch(IdField, 'zero-flag');

    { Очень малое дробное уезжает нулём: свойство формата, предъявляем его. }
    V.D := 1E-12;
    ms.Size := 0;
    ms.Position := 0;
    WriteField(ms, V);
    ChiClaim(ms.Size = 1, 'поле: очень малое поехало значением');
    ms.Position := 0;
    ReadField(ms, Got);
    ChiClaim(Got.D = 0, 'поле: очень малое доехало не нулём');
    V.D := 1E-9;
    ms.Size := 0;
    ms.Position := 0;
    WriteField(ms, V);
    ChiClaim(ms.Size = 9, 'поле: значение выше порога поехало нулём');
    ChiBranch(IdField, 'tiny-becomes-zero');

    { Пустая строка — тоже нулевое значение. }
    V := Default(TChiFieldValue);
    V.TypeID := TID_String;
    ms.Size := 0;
    ms.Position := 0;
    WriteField(ms, V);
    ChiClaim(ms.Size = 1, 'поле: пустая строка заняла не один байт');
    ms.Position := 0;
    ReadField(ms, Got);
    ChiClaim(Got.S = '', 'поле: пустая строка доехала непустой');
    ChiBranch(IdField, 'empty-string-is-zero');

    { Незнакомое поле посередине: поток обязан не съехать. }
    ms.Size := 0;
    ms.Position := 0;
    WriteField(ms, Table[3]);            { известное целое }
    var Alien: Byte := TID_Single;
    ms.Write(Alien, 1);
    var AlienVal: Single := 2.5;
    ms.Write(AlienVal, 4);
    WriteField(ms, Table[9]);            { известная строка }
    ms.Position := 0;
    ChiClaim(ReadField(ms, Got) and (Got.I = Table[3].I), 'пропуск: первое поле не сошлось');
    SkipField(ms);
    ChiClaim(ReadField(ms, Got) and (Got.S = Table[9].S),
      'пропуск: поле после незнакомого съехало');
    ChiClaim(ms.Position = ms.Size, 'пропуск: поток вычитан не до конца');
    ChiBranch(IdField, 'skip-unknown-field');

    { Пропуск строки читает её длину, а нулевое поле пропускается без чтения. }
    ms.Size := 0;
    ms.Position := 0;
    WriteField(ms, Table[9]);
    V := Default(TChiFieldValue);
    V.TypeID := TID_Int64;
    WriteField(ms, V);                   { нулевое: один байт }
    WriteField(ms, Table[1]);
    ms.Position := 0;
    SkipField(ms);
    SkipField(ms);
    ChiClaim(ReadField(ms, Got) and (Got.I = Table[1].I),
      'пропуск: после строки и нулевого поле съехало');
    ChiBranch(IdField, 'skip-string-and-zero');

    { Неизвестный код типа пропускается восемью байтами вслепую — последняя
      догадка формата. Предъявляем именно это поведение. }
    ms.Size := 0;
    ms.Position := 0;
    var Unknown: Byte := 99;
    ms.Write(Unknown, 1);
    var Filler: Int64 := 0;
    ms.Write(Filler, 8);
    WriteField(ms, Table[1]);
    ms.Position := 0;
    SkipField(ms);
    ChiClaim(ms.Position = 9, 'пропуск: неизвестный код пропущен не восемью байтами');
    ChiClaim(ReadField(ms, Got) and (Got.I = Table[1].I),
      'пропуск: после неизвестного кода поле съехало');
    ChiBranch(IdField, 'unknown-typeid-guess');
  finally
    FreeAndNil(ms);
  end;

  { ── Словарь имён ── }
  Names := TChiNameWriter.Create;
  try
    ChiClaim(Names.GetIndex('Alpha') = 0, 'словарь: первый номер не нулевой');
    ChiClaim(Names.GetIndex('Beta') = 1, 'словарь: второй номер не первый');
    ChiClaim(Names.GetIndex('Alpha') = 0, 'словарь: повторное имя получило новый номер');
    ChiClaim(Names.GetIndex('alpha') = 2, 'словарь: имя иного регистра сочтено тем же');
    ChiClaim(Names.Names.Count = 3, 'словарь: имён накопилось не столько');
    ChiBranch(IdField, 'name-dictionary');
    Acc := ChiMix(Acc, Names.Names.Count);
  finally
    FreeAndNil(Names);
  end;

  { ── Плоская запись рынка ── }
  ChiCovered(IdFlat);
  TZ := 180 / 1440;
  ms := TMemoryStream.Create;
  try
    M := MakeMarket(20260830, True);
    WriteMarket(ms, M, TZ);
    ChiClaim(ms.Size = WireSize(M), 'рынок: длина потока не та, что по правилам');
    ChiBranch(IdFlat, 'wire-size-by-rule');

    ms.Position := 0;
    B := Default(TChiMarketWire);
    ReadMarket(ms, TZ, True, B);
    ChiClaim(SameMarket(M, B), 'рынок: круговой обход исказил поля');
    ChiClaim(ChiNear(B.FundingTime, M.FundingTime, 1E-9),
      'рынок: время выплаты сместилось при равных поясах');
    ChiClaim(ms.Position = ms.Size, 'рынок: вычитано не всё');
    ChiBranch(IdFlat, 'roundtrip');
    Acc := ChiMix(Acc, ms.Size);

    { Ноль во времени выплаты остаётся нулём, а не превращается в сдвиг. }
    ms.Size := 0;
    ms.Position := 0;
    M := MakeMarket(777, False);
    WriteMarket(ms, M, TZ);
    ms.Position := 0;
    B := Default(TChiMarketWire);
    ReadMarket(ms, TZ, True, B);
    ChiClaim(B.FundingTime = 0, 'рынок: пустое время выплаты приехало сдвигом');
    ChiBranch(IdFlat, 'zero-funding-stays-zero');

    { Читатель в другом поясе получает своё местное время. }
    ms.Position := 0;
    B := Default(TChiMarketWire);
    ReadMarket(ms, TZ + 1 / 24, True, B);
    ChiClaim(B.FundingTime = 0, 'рынок: пустое время в другом поясе перестало быть пустым');
    ChiBranch(IdFlat, 'zero-across-timezones');

    { Ненужный рынок вычитывается целиком: следующий за ним обязан читаться. }
    ms.Size := 0;
    ms.Position := 0;
    var Skipped := MakeMarket(11, True);
    var Wanted := MakeMarket(22, True);
    WriteMarket(ms, Skipped, TZ);
    WriteMarket(ms, Wanted, TZ);
    ms.Position := 0;
    B := Default(TChiMarketWire);
    ReadMarket(ms, TZ, False, B);
    ChiClaim(B.Name = '', 'рынок: ненужный всё-таки разложен по месту');
    ReadMarket(ms, TZ, True, B);
    ChiClaim(SameMarket(Wanted, B), 'рынок: следующий за ненужным съехал');
    ChiClaim(ms.Position = ms.Size, 'рынок: после двух записей вычитано не всё');
    ChiBranch(IdFlat, 'unwanted-still-consumed');
    Acc := ChiMix(Acc, Length(B.Name));
  finally
    FreeAndNil(ms);
  end;

  Result := Int64(Acc and $7FFFFFFFFFFF);
end;

end.
