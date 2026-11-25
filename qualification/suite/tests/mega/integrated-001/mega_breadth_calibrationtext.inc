{ Coefficients read from an exported calibration file retain all binary64 bits. }

procedure RunBreadthCalibrationText;
const
  Texts: array[0..3] of string = ('2,2250738585072014e-308', '4,9406564584124654e-324',
    '-0,0', '9007199254740993');
  Encoded: array[0..3] of UInt64 = ($0010000000000000, $0000000000000001, $8000000000000000, $4340000000000000);
  Names: array[0..3] of AnsiString = (
    'breadth-calibration-text-parses-smallest-normal', 'breadth-calibration-text-parses-smallest-subnormal',
    'breadth-calibration-text-preserves-negative-zero', 'breadth-calibration-text-rounds-integer-tie-to-even');
var
  Settings: TFormatSettings;
  Coefficient: Double;
  I: Integer;
begin
  Settings := Default(TFormatSettings);
  Settings.DecimalSeparator := ',';
  for I := Low(Texts) to High(Texts) do begin
    Check(TryStrToFloat(Texts[I], Coefficient, Settings) and (DoubleBits(Coefficient) = Encoded[I]),
      Names[I]);
    Mix(DoubleBits(Coefficient));
  end;
end;
