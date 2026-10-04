program numeric_range_contracts;

{$mode delphiunicode}
{$H+}

uses
  Math,
  SysUtils;

type
  TDoubleBits = packed record
    case Boolean of
      False: (Value: Double);
      True: (Bits: QWord);
  end;
  TSingleBits = packed record
    case Boolean of
      False: (Value: Single);
      True: (Bits: DWord);
  end;

procedure Fail(const Name: UnicodeString; Actual,Expected: Double);
begin
  WriteLn(StdErr,'FAIL ',Name,' actual=',Actual,' expected=',Expected);
  Halt(1);
end;

function IsClose(Actual,Expected,Tolerance: Double): Boolean;
begin
  Result:=not IsNan(Actual) and not IsInfinite(Actual) and
    not IsNan(Expected) and not IsInfinite(Expected) and
    (Abs(Actual-Expected)<=Tolerance);
end;

procedure ExpectClose(const Name: UnicodeString; Actual,Expected,Tolerance: Double);
begin
  if not IsClose(Actual,Expected,Tolerance) then
    Fail(Name,Actual,Expected);
end;

procedure CheckOracle;
begin
  if IsClose(NaN,1.0,1e-12) or IsClose(1.0,NaN,1e-12) then
    Fail('finite-oracle-accepted-nan',NaN,1.0);
  if IsClose(Infinity,1.0,1e-12) or IsClose(1.0,NegInfinity,1e-12) then
    Fail('finite-oracle-accepted-infinity',Infinity,1.0);
end;

procedure ExpectRoundToDoubleBits(const Name: UnicodeString; InputBits: QWord;
  Digits: TRoundToRange; ExpectedBits: QWord);
var
  Actual, Input: TDoubleBits;
begin
  Input.Bits:=InputBits;
  Actual.Value:=RoundTo(Input.Value,Digits);
  if Actual.Bits<>ExpectedBits then begin
    WriteLn(StdErr,'FAIL ',Name,' actual=',IntToHex(Actual.Bits,16),
      ' expected=',IntToHex(ExpectedBits,16));
    Halt(1);
  end;
end;

procedure ExpectRoundToSingleBits(const Name: UnicodeString; InputBits: DWord;
  Digits: TRoundToRange; ExpectedBits: DWord);
var
  Actual, Input: TSingleBits;
begin
  Input.Bits:=InputBits;
  Actual.Value:=RoundTo(Input.Value,Digits);
  if Actual.Bits<>ExpectedBits then begin
    WriteLn(StdErr,'FAIL ',Name,' actual=',IntToHex(Actual.Bits,8),
      ' expected=',IntToHex(ExpectedBits,8));
    Halt(1);
  end;
end;

procedure ExpectLdexpDoubleBits(const Name: UnicodeString; InputBits: QWord;
  Exponent: Integer; ExpectedBits: QWord);
var
  Actual, Input: TDoubleBits;
begin
  Input.Bits:=InputBits;
  Actual.Value:=Ldexp(Input.Value,Exponent);
  if Actual.Bits<>ExpectedBits then begin
    WriteLn(StdErr,'FAIL ',Name,' actual=',IntToHex(Actual.Bits,16),
      ' expected=',IntToHex(ExpectedBits,16));
    Halt(1);
  end;
end;

procedure ExpectLdexpSingleBits(const Name: UnicodeString; InputBits: DWord;
  Exponent: Integer; ExpectedBits: DWord);
var
  Actual, Input: TSingleBits;
begin
  Input.Bits:=InputBits;
  Actual.Value:=Ldexp(Input.Value,Exponent);
  if Actual.Bits<>ExpectedBits then begin
    WriteLn(StdErr,'FAIL ',Name,' actual=',IntToHex(Actual.Bits,8),
      ' expected=',IntToHex(ExpectedBits,8));
    Halt(1);
  end;
end;

procedure CheckLdexp;
begin
  ExpectLdexpDoubleBits('ldexp-double-normal',$3fe8000000000000,4,$4028000000000000);
  ExpectLdexpDoubleBits('ldexp-double-original-regression',$0000000000000003,-2,$0000000000000001);
  ExpectLdexpDoubleBits('ldexp-double-normal-to-subnormal',$0010000000000000,-1,$0008000000000000);
  ExpectLdexpSingleBits('ldexp-single-normal',$3f400000,4,$41400000);
  ExpectLdexpSingleBits('ldexp-single-original-regression',$00000003,-2,$00000001);
  ExpectLdexpSingleBits('ldexp-single-normal-to-subnormal',$00800000,-1,$00400000);
end;

procedure CheckNormalStatistics;
var
  DoubleData: array[0..3] of Double;
  IntegerData: array[0..3] of Int64;
begin
  DoubleData[0]:=1;
  DoubleData[1]:=2;
  DoubleData[2]:=3;
  DoubleData[3]:=4;
  ExpectClose('mean-normal-double',Mean(DoubleData),2.5,0);
  ExpectClose('variance-normal-double',Variance(DoubleData),Double(5)/3,1e-15);
  ExpectClose('stddev-normal-double',StdDev(DoubleData),Sqrt(Double(5)/3),1e-15);
  ExpectClose('norm-normal-double',Norm(DoubleData),Sqrt(30),1e-15);

  IntegerData[0]:=10;
  IntegerData[1]:=20;
  IntegerData[2]:=30;
  IntegerData[3]:=40;
  ExpectClose('mean-normal-int64',Mean(IntegerData),25,0);
end;

procedure CheckNormalRoundTo;
begin
  ExpectClose('roundto-normal-cents',RoundTo(123.456,-2),123.46,5e-14);
  ExpectClose('roundto-normal-even-down',RoundTo(2.5,0),2,0);
  ExpectClose('roundto-normal-even-up',RoundTo(3.5,0),4,0);
  ExpectClose('roundto-normal-negative',RoundTo(-123.456,-2),-123.46,5e-14);

  { Exact binary-input contracts selected from the independent rational oracle. }
  ExpectRoundToDoubleBits('roundto-double-midpoint-below',$3f747ae147ae147a,-2,$0000000000000000);
  ExpectRoundToDoubleBits('roundto-double-midpoint-above',$3f747ae147ae147b,-2,$3f847ae147ae147b);
  ExpectRoundToDoubleBits('roundto-double-even-midpoint',$4004000000000000,0,$4000000000000000);
  ExpectRoundToDoubleBits('roundto-double-midpoint-neighbour',$4004000000000001,0,$4008000000000000);
  ExpectRoundToDoubleBits('roundto-double-large-integral',$4415af1d78b58c40,0,$4415af1d78b58c40);
  ExpectRoundToDoubleBits('roundto-double-large-quantum',$4415af1d78b58c40,37,$0000000000000000);
  ExpectRoundToDoubleBits('roundto-double-max-finite',$7fefffffffffffff,-37,$7fefffffffffffff);
  ExpectRoundToDoubleBits('roundto-double-negative-subnormal',$8000000000000001,-37,$8000000000000000);
  ExpectRoundToDoubleBits('roundto-double-negative-zero',$8000000000000000,0,$8000000000000000);
  ExpectRoundToDoubleBits('roundto-double-infinity',$7ff0000000000000,0,$7ff0000000000000);
  ExpectRoundToDoubleBits('roundto-double-nan-payload',$7ff8000000000001,0,$7ff8000000000001);

  ExpectRoundToSingleBits('roundto-single-midpoint-below',$3ba3d70a,-2,$00000000);
  ExpectRoundToSingleBits('roundto-single-midpoint-above',$3ba3d70b,-2,$3c23d70a);
  ExpectRoundToSingleBits('roundto-single-even-midpoint',$40200000,0,$40000000);
  ExpectRoundToSingleBits('roundto-single-even-up',$40600000,0,$40800000);
  ExpectRoundToSingleBits('roundto-single-large-integral',$60ad78ec,0,$60ad78ec);

  if RoundTo(Extended(1e20),0)<>Extended(1e20) then
    Fail('roundto-extended-large-integral',RoundTo(Extended(1e20),0),1e20);
end;

begin
  CheckOracle;
  CheckNormalStatistics;
  CheckLdexp;
  CheckNormalRoundTo;
  WriteLn('NUMERIC_RANGE_CONTRACTS_OK');
end.
