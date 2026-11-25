{ Reports use ISO week years rather than calendar years at the New Year boundary. }

procedure RunBreadthWeekSchedule;
var
  Date, Monday: TDateTime;
  Year, Week, Day: Word;
begin
  Date := EncodeDate(Word(OpaqueI(2021)), 1, 1);
  DecodeDateWeek(Date, Year, Week, Day);
  Check((Year = 2020) and (Week = 53) and (Day = 5), 'breadth-week-schedule-new-year-belongs-to-previous-report');

  Check(TryEncodeDateWeek(2020, 53, Monday, 1) and (Monday = EncodeDate(2020, 12, 28)),
    'breadth-week-schedule-recovers-start-of-existing-week-fifty-three');
  Check(not TryEncodeDateWeek(2021, 53, Monday, 1), 'breadth-week-schedule-rejects-nonexistent-week-fifty-three');

  Date := EncodeDateWeek(2021, 1, 1);
  Check(Date = EncodeDate(2021, 1, 4), 'breadth-week-schedule-first-monday-follows-boundary-weekend');
  Mix(UInt64(Trunc(Date)));
end;
