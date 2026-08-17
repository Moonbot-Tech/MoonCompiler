program format_float_semantic;

{$ifdef FPC}
  {$mode delphi}
{$endif}

{$Q-}{$R-}

uses
  {$ifdef FPC}
  mormot.core.fpcx64mm,
  {$endif}
  SysUtils;

procedure Fail(const NameText, Actual, Expected: string);
begin
  WriteLn('FAIL ', NameText, ': "', Actual, '" <> "', Expected, '"');
  Halt(1);
end;

procedure Check(const NameText, Actual, Expected: string);
begin
  If Actual <> Expected then
    Fail(NameText, Actual, Expected);
end;

procedure CheckFormat(const NameText, Mask: string; Value: Extended;
  const FormatSettings: TFormatSettings; const Expected: string);
begin
  Check(NameText, FormatFloat(Mask, Value, FormatSettings), Expected);
end;

function DigitsOf(const FloatRec: TFloatRec): string;
var
  I: Integer;
begin
  // Digits is array of AnsiChar in Moon RTL and array of Byte in Delphi 12;
  // Ord/Chr keeps one source compiling against both declarations.
  Result := '';
  I := Low(FloatRec.Digits);
  while (I <= High(FloatRec.Digits)) and (Ord(FloatRec.Digits[I]) <> 0) do
    begin
      Result := Result + Char(Chr(Ord(FloatRec.Digits[I])));
      Inc(I);
    end;
end;

procedure CheckDecimal(const NameText: string; Value: Extended;
  Precision, Decimals: Integer; const ExpectedDigits: string;
  ExpectedExponent: Integer; ExpectedNegative: Boolean);
var
  FloatRec: TFloatRec;
begin
  // Poison the whole record with '9' bytes: FloatToDecimal takes it as an
  // out/var parameter and must not leave any stale byte where a consumer
  // (rounding, digit walk) can read it. A zeroed stack would hide that.
  FillChar(FloatRec, SizeOf(FloatRec), Ord('9'));
  FloatToDecimal(FloatRec, Value, fvExtended, Precision, Decimals);
  Check(NameText + ' digits', DigitsOf(FloatRec), ExpectedDigits);
  Check(NameText + ' exponent', IntToStr(FloatRec.Exponent),
    IntToStr(ExpectedExponent));
  Check(NameText + ' negative', BoolToStr(FloatRec.Negative, True),
    BoolToStr(ExpectedNegative, True));
end;

procedure Run;
var
  FormatSettings: TFormatSettings;
  NegativeZero: Double;
  OmegaMask, OmegaExpected: string;
begin
  FormatSettings := TFormatSettings.Create;
  FormatSettings.DecimalSeparator := '.';
  FormatSettings.ThousandSeparator := ',';

  CheckFormat('fixed positive', '0.000000', 100.03125, FormatSettings,
    '100.031250');
  CheckFormat('fixed negative', '0.000000', -0.125, FormatSettings,
    '-0.125000');
  CheckFormat('fraction rounding', '0.000000', 0.001, FormatSettings,
    '0.001000');
  CheckFormat('optional digits', '0.00000###', 0.00001234, FormatSettings,
    '0.00001234');
  CheckFormat('required integer digits', '000.000', -1, FormatSettings,
    '-001.000');
  CheckFormat('thousands', '#,##0.0', 1123.4567, FormatSettings, '1,123.5');
  CheckFormat('positive section', '#,##0.00;(#,##0.00);zero', 1123.4567,
    FormatSettings, '1,123.46');
  CheckFormat('negative section', '#,##0.00;(#,##0.00);zero', -1123.4567,
    FormatSettings, '(1,123.46)');
  CheckFormat('zero section', '#,##0.00;(#,##0.00);zero', 0,
    FormatSettings, 'zero');
  NegativeZero := -0.0;
  CheckFormat('negative zero section', '#,##0.00;(#,##0.00);zero',
    NegativeZero, FormatSettings, 'zero');
  CheckFormat('quoted semicolon', '0.00 "gross;net"', 1.25,
    FormatSettings, '1.25 gross;net');
  CheckFormat('quoted exponent text', '0.00"E+00"', 1.25,
    FormatSettings, '1.25E+00');
  CheckFormat('scientific plus', '0.00E+00', 0.00001234, FormatSettings,
    '1.23E-05');
  CheckFormat('scientific minus', '0.00E-00', 1123.4567, FormatSettings,
    '1.12E03');
  CheckFormat('large exponent', '0.000000E+000', 1.0E+300, FormatSettings,
    '1.000000E+300');
  CheckFormat('small exponent', '0.000000E+000', 1.0E-300, FormatSettings,
    '1.000000E-300');

  // Direct FloatToDecimal boundary: Precision equal to the full 17 digits a
  // double provides puts the rounding index exactly on the first byte past
  // the real digits. That byte must be a zeroed pad, never leftover memory.
  // Moon RTL derives digits from Str's fixed 17-digit expansion; Delphi 12
  // returns shortest round-trip digits for the same value, so the two
  // systems pin different exact digit strings for 0.1 at full precision.
  CheckDecimal('poisoned full precision', 0.1, 17, 9999,
    {$ifdef FPC} '10000000000000001' {$else} '1' {$endif}, 0, False);
  CheckDecimal('poisoned negative full precision', -0.1, 17, 9999,
    {$ifdef FPC} '10000000000000001' {$else} '1' {$endif}, 0, True);
  CheckDecimal('poisoned power of ten', 1.0E+100, 17, 9999, '1', 101, False);
  CheckDecimal('poisoned negative exponent', 1.0E-300, 17, 9999, '1', -299,
    False);
  CheckDecimal('poisoned typical precision', 0.1, 15, 9999, '1', 0, False);

  FormatSettings.DecimalSeparator := ',';
  FormatSettings.ThousandSeparator := '.';
  CheckFormat('custom separators', '#,##0.00', 1234.5, FormatSettings,
    '1.234,50');

  FormatSettings.DecimalSeparator := '.';
  FormatSettings.ThousandSeparator := ',';
  OmegaMask := '0.00 "' + WideChar($03A9) + '"';
  OmegaExpected := '1.25 ' + WideChar($03A9);
  CheckFormat('unicode literal', OmegaMask, 1.25, FormatSettings,
    OmegaExpected);
end;

begin
  Run;
  WriteLn('FORMAT_FLOAT_SEMANTIC_OK');
end.
