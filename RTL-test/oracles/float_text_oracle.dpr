program float_text_oracle;

{$ifdef FPC}
  {$mode delphi}{$H+}
{$endif}
{$APPTYPE CONSOLE}
{$Q-}{$R-}

uses
  SysUtils;

const
  SampleCount = 200000;

procedure HashText(var Hash: UInt64; const Value: UnicodeString);
var
  I: Integer;
begin
  for I := 1 to Length(Value) do
  begin
    Hash := Hash xor Ord(Value[I]);
    Hash := Hash * UInt64(1099511628211);
  end;
  Hash := Hash xor $FFFF;
  Hash := Hash * UInt64(1099511628211);
end;

procedure HashValue(var Hash: UInt64; const Value: Double;
  const Settings: TFormatSettings);
begin
  HashText(Hash,FloatToStr(Value,Settings));
end;

var
  Bits: UInt64;
  Hash: UInt64;
  I: Integer;
  Settings: TFormatSettings;
  Value: Double;
begin
  Settings := TFormatSettings.Create('en-US');
  Settings.DecimalSeparator := '.';
  Settings.ThousandSeparator := ',';
  Hash := UInt64(14695981039346656037);
  Value := 0.0;

  HashValue(Hash,0.0,Settings);
  Bits := UInt64(1) shl 63;
  Move(Bits,Value,SizeOf(Value));
  HashValue(Hash,Value,Settings);
  HashValue(Hash,0.1,Settings);
  HashValue(Hash,1.0 / 3.0,Settings);
  HashValue(Hash,1.0e-308,Settings);
  HashValue(Hash,1.0e308,Settings);

  Bits := UInt64($9E3779B97F4A7C15);
  for I := 1 to SampleCount do
  begin
    Bits := Bits xor (Bits shl 13);
    Bits := Bits xor (Bits shr 7);
    Bits := Bits xor (Bits shl 17);
    if (Bits and UInt64($7FF0000000000000)) <> UInt64($7FF0000000000000) then
    begin
      Move(Bits,Value,SizeOf(Value));
      HashValue(Hash,Value,Settings);
    end;
  end;

  WriteLn(IntToHex(Hash,16));
end.
