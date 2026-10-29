program tbranchscalarvalues1;

{$mode delphi}{$H+}{$inline off}

uses SysUtils, Math;

type
  TValues = record
    Price, Quantity: Double;
  end;
  TAnswer = record
    Buy, Sell, LaterPrice, LaterQuantity: Double;
  end;

const
  Patterns: array[0..13] of QWord = (
    $0000000000000000, $8000000000000000,
    $3FF0000000000000, $BFF0000000000000,
    $0000000000000001, $8000000000000001,
    $0010000000000000, $7FEFFFFFFFFFFFFF,
    $7FF0000000000000, $FFF0000000000000,
    $7FF8000000000011, $FFF8000000000022,
    $7FF0000000000001, $FFF0000000000001);

{$push}{$optimization off}
function Reference(const V: TValues; Choose: Boolean): TAnswer;
begin
  Result.Buy := 0;
  Result.Sell := 0;
  If Choose then Result.Buy := V.Price * V.Quantity
  else Result.Sell := V.Price * V.Quantity;
  Result.LaterPrice := V.Price;
  Result.LaterQuantity := V.Quantity;
end;
{$pop}

function Actual(const V: TValues; Choose: Boolean): TAnswer;
begin
  Result.Buy := 0;
  Result.Sell := 0;
  If Choose then Result.Buy := V.Price * V.Quantity
  else Result.Sell := V.Price * V.Quantity;
  Result.LaterPrice := V.Price;
  Result.LaterQuantity := V.Quantity;
end;

procedure Same(Value, Expected: Double);
var
  A, B: QWord;
begin
  Move(Value, A, SizeOf(A));
  Move(Expected, B, SizeOf(B));
  If A <> B then begin
    Writeln('mismatch ', IntToHex(A, 16), ' ', IntToHex(B, 16));
    Halt(1);
  end;
end;

var
  V: TValues;
  A, B: TAnswer;
  I, J, Choice, Count: Integer;
  Rounding: TFPURoundingMode;
  SavedRounding: TFPURoundingMode;
  SavedMask: TFPUExceptionMask;
begin
  SavedMask := GetExceptionMask;
  SavedRounding := GetRoundMode;
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  Count := 0;
  try
    for Rounding := Low(TFPURoundingMode) to High(TFPURoundingMode) do begin
      SetRoundMode(Rounding);
      for I := Low(Patterns) to High(Patterns) do
        for J := Low(Patterns) to High(Patterns) do begin
          Move(Patterns[I], V.Price, SizeOf(V.Price));
          Move(Patterns[J], V.Quantity, SizeOf(V.Quantity));
          for Choice := 0 to 1 do begin
            A := Reference(V, Choice = 1);
            B := Actual(V, Choice = 1);
            Same(B.Buy, A.Buy);
            Same(B.Sell, A.Sell);
            Same(B.LaterPrice, A.LaterPrice);
            Same(B.LaterQuantity, A.LaterQuantity);
            Inc(Count);
          end;
        end;
    end;
  finally
    SetRoundMode(SavedRounding);
    SetExceptionMask(SavedMask);
  end;
  Writeln('SCALAR_VALUES_PASS ', Count);
end.
