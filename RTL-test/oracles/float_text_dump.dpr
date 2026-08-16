program float_text_dump;

{$ifdef FPC}
  {$mode delphi}{$H+}
{$endif}
{$APPTYPE CONSOLE}
{$Q-}{$R-}

uses
  SysUtils;

const
  SampleCount = 50000;

var
  Bits: UInt64;
  I: Integer;
  Settings: TFormatSettings;
  Value: Double;
begin
  Settings:=TFormatSettings.Create('en-US');
  Settings.DecimalSeparator:='.';
  Settings.ThousandSeparator:=',';
  Bits:=UInt64($9E3779B97F4A7C15);
  for I:=1 to SampleCount do
  begin
    Bits:=Bits xor (Bits shl 13);
    Bits:=Bits xor (Bits shr 7);
    Bits:=Bits xor (Bits shl 17);
    if (Bits and UInt64($7FF0000000000000))<>UInt64($7FF0000000000000) then
    begin
      Move(Bits,Value,SizeOf(Value));
      WriteLn(IntToHex(Bits,16),#9,FloatToStr(Value,Settings));
    end;
  end;
end.
