program currency_abs_model;

{$mode delphi}

var
  State: QWord;
  Raw, Expected, Got: Int64;
  Value, AbsoluteValue: Currency;
  I: Integer;
begin
  State := QWord($9E3779B97F4A7C15);
  for I := 1 to 100000 do
    begin
      State := State xor (State shl 13);
      State := State xor (State shr 7);
      State := State xor (State shl 17);
      Raw := Int64(State);
      if Raw = Low(Int64) then
        Raw := Raw + 1;
      Move(Raw,Value,SizeOf(Value));
      AbsoluteValue := Abs(Value);
      Move(AbsoluteValue,Got,SizeOf(Got));
      if Raw < 0 then
        Expected := -Raw
      else
        Expected := Raw;
      if Got <> Expected then
        begin
          WriteLn('FAIL iteration=',I,' raw=',Raw,' got=',Got,' expected=',Expected);
          Halt(1);
        end;
    end;
end.
