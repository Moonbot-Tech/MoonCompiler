program pulse_mormot_json;

{$ifndef FPC}
  {$APPTYPE CONSOLE}
{$endif}

{$ifdef FPC}
  {$mode delphi}{$H+}
{$endif}

{$Q-}{$R-}

uses
  {$if defined(FPC) and not defined(PULSE_DEFAULT_MM)}
  mormot.core.fpcx64mm,
  {$ifend}
  {$if defined(FPC) and defined(UNIX) and not defined(PULSE_DEFAULT_MM)}
  cthreads,
  {$ifend}
  SysUtils,
  Classes,
  Variants,
  mormot.core.base,
  mormot.core.rtti,
  mormot.core.unicode,
  mormot.core.text,
  mormot.core.json,
  mormot.core.variants,
  perf_clock in '..\common\perf_clock.pas',
  pulse_process_metrics in '..\common\pulse_process_metrics.pas',
  pulse_harness in '..\common\pulse_harness.pas';

type
  TLevelArray = array of Double;

  TQuoteRecord = packed record
    Id: Int64;
    Symbol: RawUtf8;
    Price: Double;
    Qty: Double;
    Active: Boolean;
    Note: RawUtf8;
    Levels: TLevelArray;
  end;

  TQuoteObject = class(TPersistent)
  private
    FId: Int64;
    FSymbol: RawUtf8;
    FPrice: Double;
    FQty: Double;
    FActive: Boolean;
    FNote: RawUtf8;
    FLevels: TLevelArray;
  published
    property Id: Int64 read FId write FId;
    property Symbol: RawUtf8 read FSymbol write FSymbol;
    property Price: Double read FPrice write FPrice;
    property Qty: Double read FQty write FQty;
    property Active: Boolean read FActive write FActive;
    property Note: RawUtf8 read FNote write FNote;
    property Levels: TLevelArray read FLevels write FLevels;
  end;

const
  __TQuoteRecord: RawUtf8 =
    'Id Int64 Symbol RawUtf8 Price double Qty double Active boolean ' +
    'Note RawUtf8 Levels array of double';

var
  JsonSmall, JsonMedium, JsonLarge: RawUtf8;

function BuildJson(PayloadLength: Integer): RawUtf8;
begin
  Result :=
    '{"Id":42,"Symbol":"BTCUSDT","Price":12345.5,"Qty":0.125,' +
    '"Active":true,"Note":"' + RawUtf8OfChar('x', PayloadLength) +
    '","Levels":[1.25,2.5,3.75,4]}';
end;

function DoubleBits(Value: Double): UInt64;
begin
  Result := 0;
  Move(Value, Result, SizeOf(Result));
end;

function RecordDigest(const Quote: TQuoteRecord): UInt64;
var
  I: Integer;
begin
  Result := UInt64(Quote.Id) xor DoubleBits(Quote.Price) xor
    (DoubleBits(Quote.Qty) shr 7) xor UInt64(Length(Quote.Symbol)) xor
    (UInt64(Length(Quote.Note)) shl 17);
  If Quote.Active then
    Inc(Result, 97);
  for I := 0 to High(Quote.Levels) do
    Result := Result xor (DoubleBits(Quote.Levels[I]) shr (I + 1));
end;

function ObjectDigest(Quote: TQuoteObject): UInt64;
var
  I: Integer;
begin
  Result := UInt64(Quote.Id) xor DoubleBits(Quote.Price) xor
    (DoubleBits(Quote.Qty) shr 7) xor UInt64(Length(Quote.Symbol)) xor
    (UInt64(Length(Quote.Note)) shl 17);
  If Quote.Active then
    Inc(Result, 97);
  for I := 0 to High(Quote.Levels) do
    Result := Result xor (DoubleBits(Quote.Levels[I]) shr (I + 1));
end;

function DocDigest(var Doc: TDocVariantData): UInt64;
var
  Levels: Variant;
begin
  Levels := Doc.GetValueOrRaiseException('Levels');
  Result := UInt64(Doc.I['Id']) xor DoubleBits(Doc.D['Price']) xor
    (DoubleBits(Doc.D['Qty']) shr 7) xor UInt64(Length(Doc.U['Symbol'])) xor
    (UInt64(Length(Doc.U['Note'])) shl 17) xor
    (UInt64(_Safe(Levels)^.Count) shl 41);
  If Doc.B['Active'] then
    Inc(Result, 97);
end;

function RecordCase(const Json: RawUtf8; Iterations: Integer;
  RoundTrip: Boolean): UInt64;
var
  I: Integer;
  Quote: TQuoteRecord;
  Saved: RawUtf8;
begin
  Result := 0;
  FillChar(Quote, SizeOf(Quote), 0);
  try
    for I := 1 to Iterations do
    begin
      If not RecordLoadJson(Quote, Json, TypeInfo(TQuoteRecord)) then
        raise EConvertError.Create('RecordLoadJson failed');
      Result := Result + RecordDigest(Quote);
      If RoundTrip then
      begin
        Saved := RecordSaveJson(Quote, TypeInfo(TQuoteRecord));
        Result := Result xor UInt64(Length(Saved));
      end;
      Finalize(Quote);
      FillChar(Quote, SizeOf(Quote), 0);
    end;
  finally
    Finalize(Quote);
  end;
end;

function DocCase(const Json: RawUtf8; Iterations: Integer;
  RoundTrip: Boolean): UInt64;
var
  I: Integer;
  Doc: TDocVariantData;
  Saved: RawUtf8;
begin
  Result := 0;
  FillChar(Doc, SizeOf(Doc), 0);
  try
    for I := 1 to Iterations do
    begin
      If not Doc.InitJson(Json, JSON_FAST_FLOAT) then
        raise EConvertError.Create('TDocVariantData.InitJson failed');
      Result := Result + DocDigest(Doc);
      If RoundTrip then
      begin
        Saved := Doc.ToJson;
        Result := Result xor UInt64(Length(Saved));
      end;
      Doc.Clear;
    end;
  finally
    Doc.Clear;
  end;
end;

function ObjectCase(const Json: RawUtf8; Iterations: Integer;
  RoundTrip: Boolean): UInt64;
var
  I: Integer;
  Quote: TQuoteObject;
  Buffer, Saved: RawUtf8;
  Valid: Boolean;
  EndOfJson: PUtf8Char;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    Quote := TQuoteObject.Create;
    try
      Buffer := Json;
      EndOfJson := JsonToObject(Quote, UniqueRawUtf8(Buffer), Valid);
      If not Valid or (EndOfJson = nil) or (EndOfJson^ <> #0) then
        raise EConvertError.Create('JsonToObject failed');
      Result := Result + ObjectDigest(Quote);
      If RoundTrip then
      begin
        Saved := ObjectToJson(Quote, []);
        Result := Result xor UInt64(Length(Saved));
      end;
    finally
      Quote.Free;
    end;
  end;
end;

function CaseRecordLoadSmall(I: Integer): UInt64; begin Result := RecordCase(JsonSmall, I, False); end;
function CaseRecordLoadMedium(I: Integer): UInt64; begin Result := RecordCase(JsonMedium, I, False); end;
function CaseRecordLoadLarge(I: Integer): UInt64; begin Result := RecordCase(JsonLarge, I, False); end;
function CaseRecordRoundSmall(I: Integer): UInt64; begin Result := RecordCase(JsonSmall, I, True); end;
function CaseRecordRoundMedium(I: Integer): UInt64; begin Result := RecordCase(JsonMedium, I, True); end;
function CaseRecordRoundLarge(I: Integer): UInt64; begin Result := RecordCase(JsonLarge, I, True); end;
function CaseDocLoadSmall(I: Integer): UInt64; begin Result := DocCase(JsonSmall, I, False); end;
function CaseDocLoadMedium(I: Integer): UInt64; begin Result := DocCase(JsonMedium, I, False); end;
function CaseDocLoadLarge(I: Integer): UInt64; begin Result := DocCase(JsonLarge, I, False); end;
function CaseDocRoundSmall(I: Integer): UInt64; begin Result := DocCase(JsonSmall, I, True); end;
function CaseDocRoundMedium(I: Integer): UInt64; begin Result := DocCase(JsonMedium, I, True); end;
function CaseDocRoundLarge(I: Integer): UInt64; begin Result := DocCase(JsonLarge, I, True); end;
function CaseObjectLoadSmall(I: Integer): UInt64; begin Result := ObjectCase(JsonSmall, I, False); end;
function CaseObjectLoadMedium(I: Integer): UInt64; begin Result := ObjectCase(JsonMedium, I, False); end;
function CaseObjectLoadLarge(I: Integer): UInt64; begin Result := ObjectCase(JsonLarge, I, False); end;
function CaseObjectRoundSmall(I: Integer): UInt64; begin Result := ObjectCase(JsonSmall, I, True); end;
function CaseObjectRoundMedium(I: Integer): UInt64; begin Result := ObjectCase(JsonMedium, I, True); end;
function CaseObjectRoundLarge(I: Integer): UInt64; begin Result := ObjectCase(JsonLarge, I, True); end;

procedure VerifyJson;
var
  RecordValue: TQuoteRecord;
  Doc: TDocVariantData;
  Quote: TQuoteObject;
  Buffer: RawUtf8;
  Valid: Boolean;
begin
  FillChar(RecordValue, SizeOf(RecordValue), 0);
  FillChar(Doc, SizeOf(Doc), 0);
  Quote := TQuoteObject.Create;
  try
    If not RecordLoadJson(RecordValue, JsonSmall, TypeInfo(TQuoteRecord)) or
       (RecordValue.Id <> 42) or (Length(RecordValue.Levels) <> 4) or
       (Length(RecordValue.Note) <> 32) then
      raise EAbort.Create('record JSON oracle failed');
    If not Doc.InitJson(JsonMedium, JSON_FAST_FLOAT) or
       (Doc.I['Id'] <> 42) or (Length(Doc.U['Note']) <> 4096) then
      raise EAbort.Create('TDocVariant JSON oracle failed');
    Buffer := JsonLarge;
    JsonToObject(Quote, UniqueRawUtf8(Buffer), Valid);
    If not Valid or (Quote.Id <> 42) or (Length(Quote.Note) <> 65536) then
      raise EAbort.Create('object JSON oracle failed');
  finally
    Finalize(RecordValue);
    Doc.Clear;
    Quote.Free;
  end;
end;

procedure Run;
var
  Profile: TPulseProfile;
  SelectedCase: string;
  Found: Boolean;

  procedure Add(const Name: string; Proc: TPulseCaseProc; Bytes: UInt64);
  begin
    PulseRunCase('pulse_mormot_json', Name, 'mormot-json',
      'mormot.core.json', Proc, Bytes, Profile, SelectedCase, Found);
  end;

begin
  Rtti.RegisterFromText(TypeInfo(TQuoteRecord), __TQuoteRecord);
  JsonSmall := BuildJson(32);
  JsonMedium := BuildJson(4096);
  JsonLarge := BuildJson(65536);
  VerifyJson;
  PulseInitialize('pulse_mormot_json', Profile, SelectedCase);
  Found := False;
  Add('record-load-small', @CaseRecordLoadSmall, Length(JsonSmall));
  Add('record-load-medium', @CaseRecordLoadMedium, Length(JsonMedium));
  Add('record-load-large', @CaseRecordLoadLarge, Length(JsonLarge));
  Add('record-roundtrip-small', @CaseRecordRoundSmall, Length(JsonSmall));
  Add('record-roundtrip-medium', @CaseRecordRoundMedium, Length(JsonMedium));
  Add('record-roundtrip-large', @CaseRecordRoundLarge, Length(JsonLarge));
  Add('docvariant-load-small', @CaseDocLoadSmall, Length(JsonSmall));
  Add('docvariant-load-medium', @CaseDocLoadMedium, Length(JsonMedium));
  Add('docvariant-load-large', @CaseDocLoadLarge, Length(JsonLarge));
  Add('docvariant-roundtrip-small', @CaseDocRoundSmall, Length(JsonSmall));
  Add('docvariant-roundtrip-medium', @CaseDocRoundMedium, Length(JsonMedium));
  Add('docvariant-roundtrip-large', @CaseDocRoundLarge, Length(JsonLarge));
  Add('object-load-small', @CaseObjectLoadSmall, Length(JsonSmall));
  Add('object-load-medium', @CaseObjectLoadMedium, Length(JsonMedium));
  Add('object-load-large', @CaseObjectLoadLarge, Length(JsonLarge));
  Add('object-roundtrip-small', @CaseObjectRoundSmall, Length(JsonSmall));
  Add('object-roundtrip-medium', @CaseObjectRoundMedium, Length(JsonMedium));
  Add('object-roundtrip-large', @CaseObjectRoundLarge, Length(JsonLarge));
  PulseFinish('pulse_mormot_json', SelectedCase, Found);
  Rtti.RegisterFromText(TypeInfo(TQuoteRecord), '');
end;

begin
  try
    Run;
  except
    on E: Exception do
    begin
      WriteLn(ErrOutput, E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
