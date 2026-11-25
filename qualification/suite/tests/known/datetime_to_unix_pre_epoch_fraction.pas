program datetime_to_unix_pre_epoch_fraction;

{$APPTYPE CONSOLE}

uses
  SysUtils, DateUtils;

procedure Check(const Wire: string; DelphiSeconds: Int64);
var
  Moment: TDateTime;
  Observed: Int64;
  Normalized: string;
begin
  Moment := ISO8601ToDate(Wire, True);
  Observed := DateTimeToUnix(Moment, True);
  Normalized := DateToISO8601(Moment, True);
  Writeln(Wire, ' normalized=', Normalized, ' seconds=', Observed, ' Delphi=', DelphiSeconds);
  If Normalized <> Wire then
    ExitCode := 2
  else If (ExitCode = 0) and (Observed <> DelphiSeconds) then
    ExitCode := 1;
end;

begin
  Check('1969-12-31T23:59:58.625Z', -1);
  Check('1969-12-31T23:59:59.000Z', -1);
  Check('1969-12-31T23:59:59.875Z', 0);
  Check('1970-01-01T00:00:00.125Z', 0);
end.
