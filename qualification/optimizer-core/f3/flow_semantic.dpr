program flow_semantic;

{$mode delphi}
{$pointermath on}

type
  TValues = array[0..15] of QWord;

var
  GlobalBias: QWord;

function Leaf(Value: QWord): QWord; noinline;
begin
  GlobalBias := GlobalBias + 3;
  Result := (Value xor GlobalBias) + 1;
end;

function Mix(var Values: TValues; Seed: QWord): QWord; noinline;
var
  I: Integer;
  Acc, Item: QWord;
begin
  Acc := Seed;
  for I := Low(Values) to High(Values) do
  begin
    Item := Values[I];
    Acc := (Acc + Item) xor (Item shl (I and 7));
    Values[I] := Acc + QWord(I);
  end;
  Result := Acc;
end;

function DividePair(Value, Divisor: QWord): QWord; noinline;
begin
  Result := (Value div Divisor) xor (Value mod Divisor);
end;

function AcrossCall(Value: QWord): QWord; noinline;
var
  Saved: QWord;
begin
  Saved := Value * 5;
  Result := Saved + Leaf(Value) + Saved;
end;

var
  Values: TValues;
  I: Integer;
  A, B, C: QWord;
begin
  GlobalBias := 7;
  for I := Low(Values) to High(Values) do
    Values[I] := QWord(I * 11 + 5);
  A := Mix(Values, 17);
  B := DividePair(A + 101, 13);
  C := AcrossCall(B);
  if (A <> 7489) or (B <> 588) or (C <> 6463) or
     (GlobalBias <> 10) or (Values[0] <> 19) or
     (Values[15] <> 7504) then
  begin
    Writeln('F3-MFACTS:FAIL ', A, ' ', B, ' ', C, ' ', GlobalBias,
      ' ', Values[0], ' ', Values[15]);
    Halt(1);
  end;
  Writeln('F3-MFACTS:PASS');
end.
