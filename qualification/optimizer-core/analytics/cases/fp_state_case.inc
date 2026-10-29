type
  TValues=record Price,Quantity:TFloat; end;
  TAnswer=record Buy,Sell,LaterPrice,LaterQuantity:TFloat; end;

{$push}{$optimization off}
function Reference(const V:TValues; Choose:Boolean):TAnswer; noinline;
begin
  Result.Buy:=0;
  Result.Sell:=0;
  If Choose then Result.Buy:=V.Price*V.Quantity
  else Result.Sell:=V.Price*V.Quantity;
  Result.LaterPrice:=V.Price;
  Result.LaterQuantity:=V.Quantity;
end;
{$pop}

function Actual(const V:TValues; Choose:Boolean):TAnswer; noinline;
begin
  Result.Buy:=0;
  Result.Sell:=0;
  If Choose then Result.Buy:=V.Price*V.Quantity
  else Result.Sell:=V.Price*V.Quantity;
  Result.LaterPrice:=V.Price;
  Result.LaterQuantity:=V.Quantity;
end;

const Patterns:array[0..15] of TBits=(
{$ifdef SMALL_FLOAT}
  $00000000,$80000000,$3F800000,$BF800000,
  $00000001,$80000001,$00800000,$80800000,
  $7F7FFFFF,$FF7FFFFF,$7F800000,$FF800000,
  $7FC00011,$FFC00022,$7F800001,$FF800001
{$else}
  $0000000000000000,$8000000000000000,$3FF0000000000000,$BFF0000000000000,
  $0000000000000001,$8000000000000001,$0010000000000000,$8010000000000000,
  $7FEFFFFFFFFFFFFF,$FFEFFFFFFFFFFFFF,$7FF0000000000000,$FFF0000000000000,
  $7FF8000000000011,$FFF8000000000022,$7FF0000000000001,$FFF0000000000001
{$endif}
);
var
  V:TValues;
  Expected,Observed:TAnswer;
  FlagsExpected,FlagsObserved,SavedMXCSR:Cardinal;
  SavedMask:TFPUExceptionMask;
  SavedRound,Rounding:TFPURoundingMode;
  I,J,Choice,Count:Integer;
begin
  SavedMXCSR:=GetMXCSR;
  SavedRound:=GetRoundMode;
  SavedMask:=GetExceptionMask;
  try
    SetExceptionMask([exInvalidOp,exDenormalized,exZeroDivide,exOverflow,exUnderflow,exPrecision]);
    for Rounding:=Low(TFPURoundingMode) to High(TFPURoundingMode) do begin
      SetRoundMode(Rounding);
      for I:=Low(Patterns) to High(Patterns) do
        for J:=Low(Patterns) to High(Patterns) do
          for Choice:=0 to 1 do begin
            Move(Patterns[I],V.Price,SizeOf(TFloat));
            Move(Patterns[J],V.Quantity,SizeOf(TFloat));
            SetMXCSR(GetMXCSR and not Cardinal($3F));
            Expected:=Reference(V,Choice<>0);
            FlagsExpected:=GetMXCSR and $3F;
            SetMXCSR(GetMXCSR and not Cardinal($3F));
            Observed:=Actual(V,Choice<>0);
            FlagsObserved:=GetMXCSR and $3F;
            If not CompareMem(@Expected,@Observed,SizeOf(Expected)) or
               (FlagsExpected<>FlagsObserved) then begin
              Writeln('FP_STATE_MISMATCH ',I,' ',J,' ',Choice,' ',Ord(Rounding));
              Halt(1);
            end;
            Inc(Count);
          end;
    end;
  finally
    SetRoundMode(SavedRound);
    SetExceptionMask(SavedMask);
    SetMXCSR(SavedMXCSR);
  end;
  Writeln('FP_STATE_PASS ',Count);
end.
