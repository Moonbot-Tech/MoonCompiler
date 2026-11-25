program timespan_text_semantic;
{$APPTYPE CONSOLE}
uses System.SysUtils, System.TimeSpan;

procedure Check(Ticks: Int64; const Expected: string);
var
  Span: TTimeSpan;
  Text: string;
begin
  Text := TTimeSpan.FromTicks(Ticks).ToString;
  if Text <> Expected then raise Exception.Create('format ' + Text + ' <> ' + Expected);
  if not TTimeSpan.TryParse(Text, Span) or (Span.Ticks <> Ticks) then
    raise Exception.Create('round trip ' + Text);
end;
var
  Span: TTimeSpan;
begin
  Check(0, '00:00:00');
  Check(70000000, '00:00:07');
  Check(74000000000, '02:03:20');
  Check(-1850000000, '-00:03:05');
  Check(-864000000000, '-1.00:00:00');
  Check(864000000010, '1.00:00:00.0000010');
  Check(-1000000, '-00:00:00.1000000');
  Check(High(Int64), '10675199.02:48:05.4775807');
  Check(Low(Int64), '-10675199.02:48:05.4775808');
  if not TTimeSpan.TryParse('  -00:03:05  ', Span) or (Span.Ticks <> -1850000000) then Halt(1);
  if not TTimeSpan.TryParse('-00:00:01.5', Span) or (Span.Ticks <> -15000000) then Halt(2);
  if TTimeSpan.TryParse('10675199.02:48:05.4775808', Span) or
     TTimeSpan.TryParse('-10675199.02:48:05.4775809', Span) or
     TTimeSpan.TryParse('00:00:01.12345678', Span) then Halt(3);
  if not TTimeSpan.TryParse('-2', Span) or (Span.Ticks <> -1728000000000) then Halt(4);
  if not TTimeSpan.TryParse('1.02:03', Span) or (Span.Ticks <> 937800000000) then Halt(5);
  if not TTimeSpan.TryParse('00:00:.05', Span) or (Span.Ticks <> 500000) then Halt(6);
  if TTimeSpan.TryParse('99:99', Span) or TTimeSpan.TryParse('+2', Span) or
     TTimeSpan.TryParse('2.', Span) or TTimeSpan.TryParse('+01:30', Span) then Halt(7);
  if TTimeSpan.TryParse('--01:00:00', Span) or TTimeSpan.TryParse('01:-2:00', Span) or
     TTimeSpan.TryParse('01:$0F:00', Span) or TTimeSpan.TryParse('01:02:03junk', Span) or
     TTimeSpan.TryParse('00:00:01' + #0 + 'junk', Span) then Halt(8);
  if not TTimeSpan.TryParse('25:00:00', Span) or (Span.Ticks <> 900000000000) then Halt(9);
  WriteLn('TIMESPAN_TEXT_PASS');
end.
