{ %OPT=-O3 }
program tarrayindexoffsetconv1;

{$mode delphi}

type
  TTimings = array[0 .. 6] of QWord;
  TSignedValues = array[-3 .. 3] of Integer;

procedure SortTimings(var Values: TTimings);
var
  I, J: Integer;
  Value: QWord;
begin
  for I := 1 to High(Values) do
  begin
    Value := Values[I];
    J := I - 1;
    while (J >= 0) and (Values[J] > Value) do
    begin
      Values[J + 1] := Values[J];
      Dec(J);
    end;
    Values[J + 1] := Value;
  end;
end;

procedure SortSigned(var Values: TSignedValues);
var
  I, J, Value: Integer;
begin
  for I := Low(Values) + 1 to High(Values) do
  begin
    Value := Values[I];
    J := I - 1;
    while (J >= Low(Values)) and (Values[J] > Value) do
    begin
      Values[1 + J] := Values[J];
      Dec(J);
    end;
    Values[J - (-1)] := Value;
  end;
end;

var
  Timings: TTimings = (7, 6, 5, 4, 3, 2, 1);
  SignedValues: TSignedValues = (3, 2, 1, 0, -1, -2, -3);
begin
  SortTimings(Timings);
  if (Timings[0] <> 1) or (Timings[1] <> 2) or
     (Timings[2] <> 3) or (Timings[3] <> 4) or
     (Timings[4] <> 5) or (Timings[5] <> 6) or
     (Timings[6] <> 7) then
    Halt(1);

  SortSigned(SignedValues);
  if (SignedValues[-3] <> -3) or (SignedValues[-2] <> -2) or
     (SignedValues[-1] <> -1) or (SignedValues[0] <> 0) or
     (SignedValues[1] <> 1) or (SignedValues[2] <> 2) or
     (SignedValues[3] <> 3) then
    Halt(2);
end.
