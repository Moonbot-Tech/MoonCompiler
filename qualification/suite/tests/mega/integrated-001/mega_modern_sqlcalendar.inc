{$ifdef BREADTH_HAS_PRODUCT_IO}
{ A SQL statement binds date, clock time and a historical timestamp as distinct typed values. }

procedure RunBreadthSqlCalendarValues;
var
  Params: TParams;
  Day, Clock, Historical: TParam;
begin
  Params := TParams.Create(nil);
  try
    Day := Params.CreateParam(ftUnknown, 'SettlementDay', ptInput);
    Clock := Params.CreateParam(ftUnknown, 'Cutoff', ptInput);
    Historical := Params.CreateParam(ftUnknown, 'HistoricalTime', ptInput);
    Day.AsDate := EncodeDate(2024, 2, Word(OpaqueI(29)));
    Clock.AsTime := EncodeTime(21, 0, 0, 0);
    Historical.AsDateTime := OpaqueD(-1.25);
    Check((Day.DataType = ftDate) and Day.Bound and (VarType(Day.Value) = varDate) and (Day.AsDateTime = 45351),
      'breadth-sql-calendar-binds-leap-day-as-date-variant');
    Check((Clock.DataType = ftTime) and Clock.Bound and (VarType(Clock.Value) = varDate) and (Clock.AsDateTime = 0.875),
      'breadth-sql-calendar-binds-time-without-date');
    Check((Historical.DataType = ftDateTime) and Historical.Bound and (VarType(Historical.Value) = varDate)
      and (Historical.AsDateTime = -1.25), 'breadth-sql-calendar-keeps-sign-and-fraction-of-historical-timestamp');
    Historical.Clear;
    Check(Historical.IsNull and (Historical.DataType = ftDateTime) and (Day.AsDateTime = 45351),
      'breadth-sql-calendar-clear-preserves-historical-type-and-neighbor');
    Mix(UInt64(Trunc(Day.AsDateTime)));
  finally
    Params.Free;
  end;
end;
{$endif}
