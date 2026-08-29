{ Тела чистых шагов. Общие для листового юнита и юнита в кольце. }

function XNotional(const T: TChiTrade): Double;
begin
  Result := T.Price * T.Quantity;
end;

function XBucket(const First, Time: TDateTime): Integer;
begin
  Result := Trunc(Abs(First - Time) * ChiTenthsPerDay);
end;

function XMinuteRaw(const First, Time: TDateTime): Integer;
begin
  Result := Round(Abs(First - Time) * ChiMinsPerDay);
end;

function XMinuteSlot(Raw, CurMinute: Integer): Integer;
begin
  Result := CurMinute - Raw;
  if Result < 0 then Result := ChiMinutes + Result;
end;

function XIsSell(const T: TChiTrade): Boolean;
begin
  Result := T.Side = csSell;
end;

function XDelta(const Price, Last: Double): Double;
begin
  Result := Abs(Price - Last);
end;

function XAfter(const Time, Edge: TDateTime): Boolean;
begin
  Result := Time > Edge;
end;

function XEma(const Prev, Q: Double): Double;
begin
  Result := (Prev * 99 + Q) / 100;
end;

function XSameSecond(const Time, Mark: TDateTime): Boolean;
begin
  Result := Abs(Time - Mark) <= 0.99 / ChiSecsPerDay;
end;
