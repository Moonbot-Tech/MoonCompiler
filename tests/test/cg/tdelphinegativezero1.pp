{ %CPU=x86_64 }
program tdelphinegativezero1;

{$ifdef FPC}
  {$mode delphi}
{$endif}
{$Q-}{$R-}

type
  TDoubleBits = record
    case Boolean of
      False: (Value: Double);
      True: (Bits: UInt64);
  end;

function BitsOf(Value: Double): UInt64;
var
  Box: TDoubleBits;
begin
  Box.Value:=Value;
  Result:=Box.Bits;
end;

procedure RequireSign(Value: Double; Negative: Boolean; ErrorCode: Byte);
const
  SignMask = UInt64($8000000000000000);
begin
  if ((BitsOf(Value) and SignMask)<>0)<>Negative then
    Halt(ErrorCode);
end;

var
  Zero, NegativeOne: Double;
begin
  { Adjacent constants must not be coalesced just because IEEE comparison
    reports +0.0 = -0.0. }
  RequireSign(0.0,False,1);
  RequireSign(-0.0,True,2);
  RequireSign(-0.0,True,3);
  RequireSign(0.0,False,4);

  { Constant arithmetic must retain the same zero sign as live arithmetic. }
  RequireSign(0.0*-1.0,True,5);
  RequireSign(-0.0*1.0,True,6);
  RequireSign(-0.0*-1.0,False,7);
  RequireSign(0.0/-1.0,True,8);
  RequireSign(-0.0/1.0,True,9);
  RequireSign(-0.0+-0.0,True,10);
  RequireSign(-0.0-0.0,True,11);

  Zero:=0.0;
  NegativeOne:=-1.0;
  RequireSign(-Zero,True,12);
  RequireSign(Zero*NegativeOne,True,13);
  RequireSign(Zero/NegativeOne,True,14);
end.
