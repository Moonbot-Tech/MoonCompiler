{ %OPT=-Mdelphi -O2 -dMOONCOMPILER_UNICODE_DEFAULT }
program tmoonunicodeformat1;

uses
  SysUtils;

var
  UnicodeCalls: Integer;
  AnsiCalls: Integer;

procedure Accept(const Value: UnicodeString); overload;
begin
  Inc(UnicodeCalls);
end;

procedure Accept(const Value: AnsiString); overload;
begin
  Inc(AnsiCalls);
end;

procedure Check(Condition: Boolean; Code: Byte);
begin
  if not Condition then
    Halt(Code);
end;

procedure CheckDefaultString;
var
  S: String;
  Settings: TFormatSettings;
begin
  S := Format('%s:%d', [UnicodeString(#$0416), 42]);
  Check(S = UnicodeString(#$0416) + ':42', 1);
  Accept(Format('%d', [7]));
  Check((UnicodeCalls = 1) and (AnsiCalls = 0), 2);

  Settings := DefaultFormatSettings;
  Settings.DecimalSeparator := ',';
  S := Format('%.1f', [1.5], Settings);
  Check(S = '1,5', 3);
  Accept(Format('%d', [8], Settings));
  Check((UnicodeCalls = 2) and (AnsiCalls = 0), 4);
end;

procedure CheckExplicitAnsi;
var
  Fmt: AnsiString;
  S: AnsiString;
begin
  Fmt := '%d';
  S := Format(Fmt, [9]);
  Check(S = '9', 5);
  Accept(Format(Fmt, [10]));
  Check((UnicodeCalls = 2) and (AnsiCalls = 1), 6);
end;

procedure CheckExplicitUnicodeFormatSettings;
var
  Buffer: array[0..31] of UnicodeChar;
  Count: Cardinal;
  Fmt: UnicodeString;
  S: UnicodeString;
  Settings: TFormatSettings;
begin
  Settings := DefaultFormatSettings;
  Settings.DecimalSeparator := '#';

  UnicodeFmtStr(S, '%.1f', [1.5], Settings);
  Check(S = '1#5', 7);

  Fmt := '%.1f';
  Count := UnicodeFormatBuf(Buffer[0], Length(Buffer), Fmt[1], Length(Fmt),
    [1.5], Settings);
  SetString(S, PUnicodeChar(@Buffer[0]), Count);
  Check(S = '1#5', 8);
end;

begin
  CheckDefaultString;
  CheckExplicitAnsi;
  CheckExplicitUnicodeFormatSettings;
end.
