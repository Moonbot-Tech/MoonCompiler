program pulse_json;

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
  SysUtils,
  Classes,
  perf_clock in '..\common\perf_clock.pas',
  pulse_process_metrics in '..\common\pulse_process_metrics.pas',
  pulse_harness in '..\common\pulse_harness.pas';

type
  TLevelArray = array of Double;
  TQuote = record
    Id: Int64;
    Symbol: UnicodeString;
    Price: Double;
    Qty: Double;
    Active: Boolean;
    Note: UnicodeString;
    Levels: TLevelArray;
  end;
  TQuoteArray = array of TQuote;

var
  JsonSmall, JsonMedium, JsonLarge: RawByteString;
  InvariantFormat: TFormatSettings;
  PreparedFloats: array[0..63] of string;
  BuilderChunk: string;

function FloatText(Value: Double): string;
begin
  Result := FormatFloat('0.000000', Value, InvariantFormat);
end;

function BuildJson(Count: Integer): RawByteString;
var
  I, J: Integer;
  Builder: TStringBuilder;
begin
  Builder := TStringBuilder.Create(Count * 160);
  try
    Builder.Append('[');
    for I := 0 to Count - 1 do
    begin
      If I <> 0 then
        Builder.Append(',');
      Builder.Append('{"id":').Append(I + 1000000);
      Builder.Append(',"symbol":"SYM').Append(I mod 97).Append('-USD"');
      Builder.Append(',"price":').Append(FloatText(100.0 + I * 0.03125));
      Builder.Append(',"qty":').Append(FloatText(0.001 + (I mod 113) * 0.125));
      If (I and 3) <> 0 then
        Builder.Append(',"active":true')
      else
        Builder.Append(',"active":false');
      Builder.Append(',"note":"route\n').Append(I mod 17).Append('\tfast"');
      Builder.Append(',"levels":[');
      for J := 0 to 3 do
      begin
        If J <> 0 then
          Builder.Append(',');
        Builder.Append(FloatText(100.0 + I * 0.03125 + J * 0.01));
      end;
      Builder.Append(']}');
    end;
    Builder.Append(']');
    Result := RawByteString(AnsiString(Builder.ToString));
  finally
    Builder.Free;
  end;
end;

procedure Expect(const Text: RawByteString; var Position: Integer; Ch: AnsiChar);
begin
  If (Position > Length(Text)) or (AnsiChar(Text[Position]) <> Ch) then
    raise EConvertError.CreateFmt('JSON expected %s at %d', [Ch, Position]);
  Inc(Position);
end;

procedure ExpectLiteral(const Text: RawByteString; var Position: Integer;
  const Value: RawByteString);
var
  I: Integer;
begin
  for I := 1 to Length(Value) do
  begin
    If (Position > Length(Text)) or (Text[Position] <> Value[I]) then
      raise EConvertError.CreateFmt('JSON literal mismatch at %d', [Position]);
    Inc(Position);
  end;
end;

function ParseStringRaw(const Text: RawByteString; var Position: Integer):
  RawByteString;
var
  Start, OutPos: Integer;
  Escaped: Boolean;
begin
  Expect(Text, Position, '"');
  Start := Position;
  Escaped := False;
  while Position <= Length(Text) do
  begin
    If Text[Position] = '"' then
      Break;
    If Text[Position] = '\' then
    begin
      Escaped := True;
      Inc(Position);
      If Position > Length(Text) then
        raise EConvertError.Create('unterminated JSON escape');
    end;
    Inc(Position);
  end;
  If Position > Length(Text) then
    raise EConvertError.Create('unterminated JSON string');
  Result := Copy(Text, Start, Position - Start);
  Inc(Position);
  If Escaped then
  begin
    OutPos := 1;
    Start := 1;
    while Start <= Length(Result) do
    begin
      If Result[Start] = '\' then
      begin
        Inc(Start);
        case Result[Start] of
          'n': Result[OutPos] := #10;
          'r': Result[OutPos] := #13;
          't': Result[OutPos] := #9;
          else Result[OutPos] := Result[Start];
        end;
      end
      else
        Result[OutPos] := Result[Start];
      Inc(Start);
      Inc(OutPos);
    end;
    SetLength(Result, OutPos - 1);
  end;
end;

function ParseInt64(const Text: RawByteString; var Position: Integer): Int64;
var
  Negative: Boolean;
begin
  Negative := False;
  If Text[Position] = '-' then
  begin
    Negative := True;
    Inc(Position);
  end;
  Result := 0;
  If (Position > Length(Text)) or not (Text[Position] in ['0'..'9']) then
    raise EConvertError.CreateFmt('integer expected at %d', [Position]);
  while (Position <= Length(Text)) and (Text[Position] in ['0'..'9']) do
  begin
    Result := Result * 10 + Ord(Text[Position]) - Ord('0');
    Inc(Position);
  end;
  If Negative then
    Result := -Result;
end;

function ParseDoubleAscii(const Text: RawByteString;
  var Position: Integer): Double;
var
  Negative: Boolean;
  Scale: Double;
begin
  Negative := False;
  If Text[Position] = '-' then
  begin
    Negative := True;
    Inc(Position);
  end;
  Result := 0;
  while (Position <= Length(Text)) and (Text[Position] in ['0'..'9']) do
  begin
    Result := Result * 10 + Ord(Text[Position]) - Ord('0');
    Inc(Position);
  end;
  If (Position <= Length(Text)) and (Text[Position] = '.') then
  begin
    Inc(Position);
    Scale := 0.1;
    while (Position <= Length(Text)) and (Text[Position] in ['0'..'9']) do
    begin
      Result := Result + (Ord(Text[Position]) - Ord('0')) * Scale;
      Scale := Scale * 0.1;
      Inc(Position);
    end;
  end;
  If Negative then
    Result := -Result;
end;

function ParseDoubleRtl(const Text: RawByteString;
  var Position: Integer): Double;
var
  Start: Integer;
  Token: string;
begin
  Start := Position;
  If Text[Position] = '-' then
    Inc(Position);
  while (Position <= Length(Text)) and
    (Text[Position] in ['0'..'9', '.', 'e', 'E', '+', '-']) do
    Inc(Position);
  Token := string(AnsiString(Copy(Text, Start, Position - Start)));
  Result := StrToFloat(Token, InvariantFormat);
end;

function ParseQuotes(const Text: RawByteString; UseRtlDouble: Boolean): TQuoteArray;
var
  Position, Count, J: Integer;
  Raw: RawByteString;

  procedure Key(const Expected: RawByteString);
  begin
    Raw := ParseStringRaw(Text, Position);
    If Raw <> Expected then
      raise EConvertError.Create('unexpected JSON key: ' + string(Raw));
    Expect(Text, Position, ':');
  end;

  function Number: Double;
  begin
    If UseRtlDouble then
      Result := ParseDoubleRtl(Text, Position)
    else
      Result := ParseDoubleAscii(Text, Position);
  end;

begin
  Position := 1;
  Expect(Text, Position, '[');
  Count := 0;
  SetLength(Result, 16);
  while (Position <= Length(Text)) and (Text[Position] <> ']') do
  begin
    If Count = Length(Result) then
      SetLength(Result, Length(Result) * 2);
    If Count <> 0 then
      Expect(Text, Position, ',');
    Expect(Text, Position, '{');
    Key('id');
    Result[Count].Id := ParseInt64(Text, Position);
    Expect(Text, Position, ','); Key('symbol');
    Result[Count].Symbol := UnicodeString(AnsiString(ParseStringRaw(Text, Position)));
    Expect(Text, Position, ','); Key('price');
    Result[Count].Price := Number;
    Expect(Text, Position, ','); Key('qty');
    Result[Count].Qty := Number;
    Expect(Text, Position, ','); Key('active');
    If Text[Position] = 't' then
    begin
      ExpectLiteral(Text, Position, 'true');
      Result[Count].Active := True;
    end
    else
    begin
      ExpectLiteral(Text, Position, 'false');
      Result[Count].Active := False;
    end;
    Expect(Text, Position, ','); Key('note');
    Result[Count].Note := UnicodeString(AnsiString(ParseStringRaw(Text, Position)));
    Expect(Text, Position, ','); Key('levels');
    Expect(Text, Position, '[');
    SetLength(Result[Count].Levels, 4);
    for J := 0 to 3 do
    begin
      If J <> 0 then Expect(Text, Position, ',');
      Result[Count].Levels[J] := Number;
    end;
    Expect(Text, Position, ']');
    Expect(Text, Position, '}');
    Inc(Count);
  end;
  Expect(Text, Position, ']');
  If Position <= Length(Text) then
    raise EConvertError.Create('trailing JSON content');
  SetLength(Result, Count);
end;

function QuoteDigest(const Quotes: TQuoteArray): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 0 to High(Quotes) do
  begin
    Result := Result + UInt64(Quotes[I].Id) + UInt64(Length(Quotes[I].Symbol)) +
      UInt64(Length(Quotes[I].Note));
    Result := Result xor PUInt64(@Quotes[I].Price)^ xor
      (PUInt64(@Quotes[I].Qty)^ shr 7);
    If Quotes[I].Active then
      Inc(Result, 17);
    for J := 0 to High(Quotes[I].Levels) do
      Result := Result + (PUInt64(@Quotes[I].Levels[J])^ shr (J + 1));
  end;
end;

function CaseGenerateJson(Iterations: Integer): UInt64;
var
  I: Integer;
  Text: RawByteString;
  Digest: UInt64;
begin
  Digest := 0;
  for I := 1 to Iterations do
  begin
    Text := BuildJson(64);
    Digest := Digest + UInt64(Length(Text)) + Byte(Text[Length(Text)]);
  end;
  Result := Digest;
end;

function CaseBuilderGrowth(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Builder: TStringBuilder;
  Text: string;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    Builder := TStringBuilder.Create(16);
    try
      for J := 1 to 1024 do
        Builder.Append(BuilderChunk);
      Text := Builder.ToString;
      Result := Result + UInt64(Length(Text)) + Ord(Text[Length(Text)]);
    finally
      Builder.Free;
    end;
  end;
end;

function CaseBuilderPreparedFloats(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Builder: TStringBuilder;
  Text: string;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    Builder := TStringBuilder.Create(1024);
    try
      for J := 0 to High(PreparedFloats) do
      begin
        Builder.Append(PreparedFloats[J]);
        Builder.Append(',');
      end;
      Text := Builder.ToString;
      Result := Result + UInt64(Length(Text)) + Ord(Text[Length(Text)]);
    finally
      Builder.Free;
    end;
  end;
end;

function ScanJson(const Text: RawByteString; Iterations: Integer): UInt64;
var
  I, J: Integer;
  Digest: UInt64;
begin
  Digest := 0;
  for I := 1 to Iterations do
    for J := 1 to Length(Text) do
      case Text[J] of
        '{', '}', '[', ']', ':', ',': Digest := Digest + UInt64(J);
        '"': Digest := Digest xor UInt64(J * 17);
      end;
  Result := Digest;
end;

function CaseScanSmall(Iterations: Integer): UInt64;
begin Result := ScanJson(JsonSmall, Iterations); end;
function CaseScanMedium(Iterations: Integer): UInt64;
begin Result := ScanJson(JsonMedium, Iterations); end;
function CaseScanLarge(Iterations: Integer): UInt64;
begin Result := ScanJson(JsonLarge, Iterations); end;

function ParseCase(const Text: RawByteString; Iterations: Integer;
  UseRtlDouble: Boolean): UInt64;
var
  I: Integer;
  Quotes: TQuoteArray;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    Quotes := ParseQuotes(Text, UseRtlDouble);
    Result := Result + QuoteDigest(Quotes);
  end;
end;

function CaseParseSmallCustom(Iterations: Integer): UInt64;
begin Result := ParseCase(JsonSmall, Iterations, False); end;
function CaseParseMediumCustom(Iterations: Integer): UInt64;
begin Result := ParseCase(JsonMedium, Iterations, False); end;
function CaseParseLargeCustom(Iterations: Integer): UInt64;
begin Result := ParseCase(JsonLarge, Iterations, False); end;
function CaseParseMediumRtl(Iterations: Integer): UInt64;
begin Result := ParseCase(JsonMedium, Iterations, True); end;

function CaseApplicationPipeline(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Quotes: TQuoteArray;
  Notional, Qty: Double;
  Output: RawByteString;
  Digest: UInt64;
begin
  Digest := 0;
  for I := 1 to Iterations do
  begin
    Quotes := ParseQuotes(JsonMedium, False);
    Notional := 0;
    Qty := 0;
    for J := 0 to High(Quotes) do
      If Quotes[J].Active then
      begin
        Notional := Notional + Quotes[J].Price * Quotes[J].Qty;
        Qty := Qty + Quotes[J].Qty;
      end;
    Output := RawByteString(AnsiString(FloatText(Notional / Qty) + '|' +
      IntToStr(Length(Quotes))));
    Digest := Digest + QuoteDigest(Quotes) + UInt64(Length(Output)) +
      PUInt64(@Notional)^;
  end;
  Result := Digest;
end;

procedure VerifyJson;
var
  A, B: TQuoteArray;
begin
  A := ParseQuotes(JsonSmall, False);
  B := ParseQuotes(JsonSmall, True);
  If (Length(A) <> 16) or (Length(B) <> 16) then
    raise EAbort.Create('JSON count oracle failed');
  If (Abs(A[0].Price - B[0].Price) > 0.000000001) or
     (Abs(A[15].Qty - B[15].Qty) > 0.000000001) then
    raise EAbort.Create('custom/RTL numeric oracle mismatch');
  If (A[0].Symbol <> 'SYM0-USD') or (A[0].Note <> 'route' + #10 + '0' + #9 +
     'fast') then
    raise EAbort.Create('JSON text oracle failed');
end;

procedure Run;
var
  I: Integer;
  Profile: TPulseProfile;
  SelectedCase: string;
  Found: Boolean;
begin
  InvariantFormat := TFormatSettings.Create;
  InvariantFormat.DecimalSeparator := '.';
  InvariantFormat.ThousandSeparator := ',';
  JsonSmall := BuildJson(16);
  JsonMedium := BuildJson(256);
  JsonLarge := BuildJson(4096);
  BuilderChunk := StringOfChar('x', 64);
  for I := 0 to High(PreparedFloats) do
    PreparedFloats[I] := FloatText(100.0 + I * 0.03125);
  VerifyJson;
  PulseInitialize('pulse_json', Profile, SelectedCase);
  Found := False;
  PulseRunCase('pulse_json', 'generate-64', 'rtl', 'TStringBuilder',
    @CaseGenerateJson, 64, Profile, SelectedCase, Found);
  PulseRunCase('pulse_json', 'builder-growth-64k', 'rtl', 'TStringBuilder',
    @CaseBuilderGrowth, 65536, Profile, SelectedCase, Found);
  PulseRunCase('pulse_json', 'builder-append-prepared-floats-64', 'rtl',
    'TStringBuilder', @CaseBuilderPreparedFloats, 64, Profile, SelectedCase,
    Found);
  PulseRunCase('pulse_json', 'byte-scan-small-16', 'codegen', 'Pascal',
    @CaseScanSmall, Length(JsonSmall), Profile, SelectedCase, Found);
  PulseRunCase('pulse_json', 'byte-scan-medium-256', 'codegen', 'Pascal',
    @CaseScanMedium, Length(JsonMedium), Profile, SelectedCase, Found);
  PulseRunCase('pulse_json', 'byte-scan-large-4096', 'codegen', 'Pascal',
    @CaseScanLarge, Length(JsonLarge), Profile, SelectedCase, Found);
  PulseRunCase('pulse_json', 'parse-small-custom-double', 'compiler+rtl',
    'Pascal', @CaseParseSmallCustom, 16, Profile, SelectedCase, Found);
  PulseRunCase('pulse_json', 'parse-medium-custom-double', 'compiler+rtl',
    'Pascal', @CaseParseMediumCustom, 256, Profile, SelectedCase, Found);
  PulseRunCase('pulse_json', 'parse-large-custom-double', 'compiler+rtl',
    'Pascal', @CaseParseLargeCustom, 4096, Profile, SelectedCase, Found);
  PulseRunCase('pulse_json', 'parse-medium-strtofloat', 'rtl', 'StrToFloat',
    @CaseParseMediumRtl, 256, Profile, SelectedCase, Found);
  PulseRunCase('pulse_json', 'pipeline-parse-vwap-format', 'integrated',
    'Pascal+RTL', @CaseApplicationPipeline, 256, Profile, SelectedCase, Found);
  PulseFinish('pulse_json', SelectedCase, Found);
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
