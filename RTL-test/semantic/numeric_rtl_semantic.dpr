program numeric_rtl_semantic;
{$mode delphiunicode}{$R-}{$Q-}
uses SysUtils, rtl_random_reference;
var Checks: UInt64;
procedure Check(B: Boolean; const What: UnicodeString);
begin
  Inc(Checks);
  if not B then begin WriteLn('FAIL ',What); Halt(1); end;
end;
function ReferenceHex(V: QWord; Digits: Integer): UnicodeString;
const Hex: UnicodeString='0123456789ABCDEF';
begin
  Result:='';
  repeat
    Result:=Hex[Integer(V and 15)+1]+Result;
    V:=V shr 4;
  until V=0;
  while Length(Result)<Digits do Result:='0'+Result;
end;
procedure TestHex;
var V: QWord; I,D: Integer;
begin
  V:=$123456789ABCDEF0;
  for I:=0 to 8191 do begin
    V:=V*6364136223846793005+1442695040888963407;
    for D:=-2 to 72 do begin
      Check(IntToHex(V,D)=ReferenceHex(V,D),'QWord hex width');
      Check(IntToHex(Int64(V),D)=ReferenceHex(V,D),'Int64 hex width');
      Check(IntToHex(LongInt(V),D)=ReferenceHex(Cardinal(V),D),'LongInt hex width');
    end;
  end;
  for I:=0 to 63 do begin
    V:=QWord(1) shl I;
    Check(IntToHex(V,0)=ReferenceHex(V,0),'one-bit boundary');
    Check(IntToHex(V-1,0)=ReferenceHex(V-1,0),'below one-bit boundary');
  end;
  Check(IntToHex(Int8(-1))='FF','Int8 fixed width');
  Check(IntToHex(Int16(-1))='FFFF','Int16 fixed width');
  Check(IntToHex(Int32(-1))='FFFFFFFF','Int32 fixed width');
  Check(IntToHex(Int64(-1))='FFFFFFFFFFFFFFFF','Int64 fixed width');
  Check(IntToHex(UInt8(0))='00','UInt8 fixed width');
  Check(IntToHex(UInt16(0))='0000','UInt16 fixed width');
  Check(IntToHex(UInt32(0))='00000000','UInt32 fixed width');
  Check(IntToHex(UInt64(0))='0000000000000000','UInt64 fixed width');
end;
procedure DrawChecks(Count: Integer);
const B64: array[0..7] of Int64=(0,1,-1,2147483648,-2147483649,High(Int64),Low(Int64),4294967297);
      B32: array[0..7] of LongInt=(0,1,-1,2,Low(LongInt),High(LongInt),-1073741825,1073741825);
var I: Integer; A,B: Double; X,Y: Int64;
begin
  for I:=0 to Count-1 do begin
    if (I and 3)=0 then begin
      X:=rtl_random_reference.Draw32(B32[(I shr 2) and 7]);
      Y:=System.Random(B32[(I shr 2) and 7]);
      Check(X=Y,'Random32 exact stream');
    end else if (I and 3)=1 then begin
      X:=rtl_random_reference.Draw64(B64[(I shr 2) and 7]);
      Y:=System.Random(B64[(I shr 2) and 7]);
      Check(X=Y,'Random64 exact stream and rejection');
    end else begin
      A:=rtl_random_reference.DrawFloat;
      B:=System.Random;
      Check(PQWord(@A)^=PQWord(@B)^,'Random Double exact bits');
      Check((B>=0) and (B<1),'Random Double range');
    end;
    Check(System.RandSeed=rtl_random_reference.CurrentSeed,'public RandSeed');
  end;
end;
var S: Cardinal; I: Integer;
begin
  System.RandSeed:=$FFFFFFFF;
  rtl_random_reference.ResetSeed($FFFFFFFF);
  DrawChecks(1000);
  S:=0;
  for I:=0 to 31 do begin
    System.RandSeed:=S;
    rtl_random_reference.ResetSeed(S);
    DrawChecks(32768);
    S:=S*1664525+1013904223;
  end;
  Check(rtl_random_reference.RareDraws>0,'extra exponent draw exercised');
  TestHex;
  WriteLn('NUMERIC_RTL_PASS',' checks=',Checks,' rare_draws=',rtl_random_reference.RareDraws);
end.
