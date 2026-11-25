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

procedure RunBreadthProtocolTimestamps;
var
  Moment: TDateTime;
  UnixSecond: Int64;
begin
  Check(TryISO8601ToDate('2038-01-19T09:14:09+06:00', Moment, True),
    'breadth-iso8601-accepts-full-offset-for-signed-unix-boundary');
  UnixSecond := DateTimeToUnix(Moment, True);
  Check(UnixSecond = 2147483649, 'breadth-iso8601-normalizes-offset-past-signed-32-bit-epoch');
  Check(DateToISO8601(UnixToDateTime(OpaqueI(2147483649), True), True) = '2038-01-19T03:14:09.000Z',
    'breadth-unix64-rebuilds-the-utc-wire-value');
  Mix(UInt64(UnixSecond));

  Moment := ISO8601ToDate('2000-01-01T00:00:00.500+14:00', True);
  Check(DateToISO8601(Moment, True) = '1999-12-31T10:00:00.500Z',
    'breadth-iso8601-offset-crosses-year-with-milliseconds');
  Moment := ISO8601ToDate('1969-12-31T23:32:31.250-00:30', True);
  Check(DateToISO8601(Moment, True) = '1970-01-01T00:02:31.250Z',
    'breadth-iso8601-negative-subhour-offset-crosses-epoch');
  Check(DateTimeToUnix(Moment, True) = 151, 'breadth-iso8601-epoch-keeps-correct-second-with-fraction');
  Check(DateTimeToUnix(ISO8601ToDate('1969-12-31T23:59:59.000Z', True), True) = -1,
    'breadth-epoch-preceding-whole-second-retains-sign');
end;
