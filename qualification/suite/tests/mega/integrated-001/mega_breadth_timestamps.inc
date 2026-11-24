{ TDateTime's signed day number and positive clock fraction meet in TTimeStamp. }

type
  TBreadthRecodeTime = function(Value: TDateTime; out Stamp: TTimeStamp): TDateTime; cdecl;

function BreadthRecodeTime(Value: TDateTime; out Stamp: TTimeStamp): TDateTime; cdecl;
begin
  Stamp := DateTimeToTimeStamp(Value);
  Result := TimeStampToDateTime(Stamp);
end;

procedure RunBreadthCalendarBoundary;
var
  Recode: TBreadthRecodeTime;
  Original, RoundTrip: TDateTime;
  Stamp: TTimeStamp;
  Settings: TFormatSettings;
begin
  Settings := Default(TFormatSettings);
  Settings.DateSeparator := '.';
  Settings.TimeSeparator := '-';
  Recode := BreadthRecodeTime;
  RoundTrip := Recode(OpaqueD(-1.25), Stamp);
  Check((Stamp.Date = 693593) and (Stamp.Time = 21600000), 'breadth-timestamp-negative-date-separates-day-and-clock');
  Check(DoubleBits(RoundTrip) = UInt64($BFF4000000000000), 'breadth-timestamp-negative-roundtrip-keeps-sign-and-fraction');
  Check(FormatDateTime('yyyy/mm/dd hh:nn:ss', RoundTrip, Settings) = '1899.12.29 06-00-00',
    'breadth-timestamp-negative-date-formats-calendar-not-raw-fraction');

  Check(not TryEncodeDate(Word(OpaqueI(1900)), 2, 29, Original), 'breadth-timestamp-century-must-be-divisible-by-four-hundred');
  Check(TryEncodeDate(Word(OpaqueI(2000)), 2, 29, Original), 'breadth-timestamp-century-leap-day-accepted');
  Original := Original + EncodeTime(23, 59, 59, 875);
  RoundTrip := Recode(Original, Stamp);
  Check((Stamp.Date = 730179) and (Stamp.Time = 86399875), 'breadth-timestamp-leap-day-retains-millisecond-before-midnight');
  Check(FormatDateTime('yyyy/mm/dd hh:nn:ss.zzz', RoundTrip, Settings) = '2000.02.29 23-59-59.875',
    'breadth-timestamp-format-uses-explicit-separators-and-milliseconds');
  Mix(UInt64(Stamp.Date) shl 32 or UInt64(Stamp.Time));
end;
