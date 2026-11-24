{ Date/time text honors per-call settings even for a leap day close to midnight. }

procedure RunBreadthLocalDateText;
var
  Settings: TFormatSettings;
  Value, Parsed: TDateTime;
  Text: string;
  Hour, Minute, Second, Milli: Word;
begin
  Settings := Default(TFormatSettings);
  Settings.ShortDateFormat := 'yyyy/mm/dd';
  Settings.DateSeparator := '-';
  Settings.TimeSeparator := '~';
  Settings.ShortDayNames[5] := 'Fifth';
  Settings.ShortMonthNames[2] := 'Leap';
  Value := EncodeDate(2024, 2, 29) + EncodeTime(23, 59, 58, 625);

  Text := FormatDateTime('ddd d mmm yyyy "at" hh:nn:ss"."zzz', Value, Settings);
  Check(Text = 'Fifth 29 Leap 2024 at 23~59~58.625', 'breadth-date-text-uses-per-call-names-and-time-separator');
  Parsed := 0;
  Text := FormatDateTime('yyyy/mm/dd hh:nn:ss', Value, Settings);
  Check((Text = '2024-02-29 23~59~58') and TryStrToDateTime(Text, Parsed, Settings) and (Trunc(Parsed) = 45351),
    'breadth-date-text-parses-its-explicit-format-and-leap-day');
  DecodeTime(Parsed, Hour, Minute, Second, Milli);
  Check((Hour = 23) and (Minute = 59) and (Second = 58) and (Milli = 0),
    'breadth-date-text-roundtrip-keeps-time-with-custom-delimiter');
  Check(not TryStrToDateTime('2023-02-29 23~59~58', Parsed, Settings), 'breadth-date-text-rejects-impossible-date-with-same-settings');
end;
