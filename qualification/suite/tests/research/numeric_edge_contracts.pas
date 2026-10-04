program numeric_edge_contracts;

{$mode delphiunicode}
{$asmmode intel}

uses
  SysUtils,
  Math;

type
  TExtendedBits = packed record
    case Byte of
      0: (Frac: QWord; Exp: Word);
      1: (Value: Extended);
  end;

{$if defined(cpux86_64)}
procedure RawSetMXCSR(Value: Pointer); assembler; nostackframe;
asm
{$ifdef windows}
  ldmxcsr [rcx]
{$else}
  ldmxcsr [rdi]
{$endif}
end;

function RawGet8087StatusWord: Word; assembler; nostackframe;
asm
  fnstsw ax
end;
{$endif}

procedure Fail(const Name: string; Actual,Expected: Extended);
begin
  WriteLn('FAIL ',Name,' actual=',Actual,' expected=',Expected);
  Halt(1);
end;

procedure FailBits(const Name: string; Actual,Expected: QWord);
begin
  WriteLn('FAIL ',Name,' actual=',IntToHex(Actual,16),' expected=',IntToHex(Expected,16));
  Halt(1);
end;

function IsClose(Actual,Expected,Tolerance: Extended): Boolean;
var
  Scale: Extended;
begin
  if IsNan(Actual) or IsInfinite(Actual) or
     IsNan(Expected) or IsInfinite(Expected) then
    Exit(False);
  Scale:=Abs(Expected);
  if Scale<1.0 then
    Scale:=1.0;
  Result:=Abs(Actual-Expected)<=Tolerance*Scale;
end;

function IsRelative(Actual,Expected,Tolerance: Extended): Boolean;
begin
  Result:=not IsNan(Actual) and not IsInfinite(Actual) and
    not IsNan(Expected) and not IsInfinite(Expected) and
    (Expected<>0.0) and (Abs((Actual-Expected)/Expected)<=Tolerance);
end;

procedure ExpectClose(const Name: string; Actual,Expected,Tolerance: Extended);
begin
  if not IsClose(Actual,Expected,Tolerance) then
    Fail(Name,Actual,Expected);
end;

procedure ExpectRelative(const Name: string; Actual,Expected,Tolerance: Extended);
begin
  if not IsRelative(Actual,Expected,Tolerance) then
    Fail(Name,Actual,Expected);
end;

procedure CheckOracle;
begin
  if IsClose(NaN,1.0,1e-12) or IsClose(1.0,NaN,1e-12) or
     IsRelative(NaN,1.0,1e-12) or IsRelative(1.0,NaN,1e-12) then
    Fail('finite-oracle-accepted-nan',NaN,1.0);
  if IsClose(Infinity,1.0,1e-12) or IsRelative(NegInfinity,1.0,1e-12) then
    Fail('finite-oracle-accepted-infinity',Infinity,1.0);
end;

procedure CheckLdexp;
var
  SIn,SOut: TSingleRec;
  DIn,DOut: TDoubleRec;
  EIn,EOut: TExtendedBits;
  Mode, SavedMode: TFPURoundingMode;

  procedure ExpectSingle(const Name: string; Bits: DWord; Power: Integer; Expected: DWord);
  begin
    SIn.Data:=Bits;
    SOut.Value:=Ldexp(SIn.Value,Power);
    if SOut.Data<>Expected then
      FailBits(Name,SOut.Data,Expected);
  end;

  procedure ExpectDouble(const Name: string; Bits: QWord; Power: Integer; Expected: QWord);
  begin
    DIn.Data:=Bits;
    DOut.Value:=Ldexp(DIn.Value,Power);
    if DOut.Data<>Expected then
      FailBits(Name,DOut.Data,Expected);
  end;

  procedure ExpectExtended(const Name: string; Exp: Word; Frac: QWord;
    Power: Integer; ExpectedExp: Word; ExpectedFrac: QWord);
  begin
    EIn.Exp:=Exp;
    EIn.Frac:=Frac;
    EOut.Value:=Ldexp(EIn.Value,Power);
    if (EOut.Exp<>ExpectedExp) or (EOut.Frac<>ExpectedFrac) then
      begin
        WriteLn('FAIL ',Name,' actual=',IntToHex(EOut.Exp,4),':',IntToHex(EOut.Frac,16),
          ' expected=',IntToHex(ExpectedExp,4),':',IntToHex(ExpectedFrac,16));
        Halt(1);
      end;
  end;

begin
  SavedMode:=GetRoundMode;
  try
    for Mode:=Low(TFPURoundingMode) to High(TFPURoundingMode) do
    begin
      SetRoundMode(Mode);
      ExpectSingle('ldexp-single-identity',$3f800000,0,$3f800000);
      ExpectSingle('ldexp-single-subnormal-identity',$00000123,0,$00000123);
      ExpectSingle('ldexp-single-negative-zero',$80000000,High(Integer),$80000000);
      ExpectSingle('ldexp-single-nan-payload',$7fc12345,17,$7fc12345);
      ExpectSingle('ldexp-single-normal-to-subnormal',$00800000,-1,$00400000);
      ExpectSingle('ldexp-single-tie-even-up',$00000003,-1,$00000002);
      ExpectSingle('ldexp-single-above-half',$00000003,-2,$00000001);
      ExpectSingle('ldexp-single-tie-even-zero',$00000002,-2,$00000000);
      ExpectSingle('ldexp-single-round-to-normal',$00ffffff,-1,$00800000);
      ExpectSingle('ldexp-single-negative-subnormal',$80000003,-2,$80000001);
      ExpectSingle('ldexp-single-overflow',$3f800000,High(Integer),$7f800000);
      ExpectSingle('ldexp-single-underflow-sign',$bf800000,Low(Integer),$80000000);

      ExpectDouble('ldexp-double-identity',$3ff0000000000000,0,$3ff0000000000000);
      ExpectDouble('ldexp-double-subnormal-identity',$0000000000000123,0,$0000000000000123);
      ExpectDouble('ldexp-double-negative-zero',$8000000000000000,High(Integer),$8000000000000000);
      ExpectDouble('ldexp-double-nan-payload',$7ff8123456789abc,17,$7ff8123456789abc);
      ExpectDouble('ldexp-double-normal-to-subnormal',$0010000000000000,-1,$0008000000000000);
      ExpectDouble('ldexp-double-tie-even-up',$0000000000000003,-1,$0000000000000002);
      ExpectDouble('ldexp-double-above-half',$0000000000000003,-2,$0000000000000001);
      ExpectDouble('ldexp-double-tie-even-zero',$0000000000000002,-2,$0000000000000000);
      ExpectDouble('ldexp-double-round-to-normal',$001fffffffffffff,-1,$0010000000000000);
      ExpectDouble('ldexp-double-negative-subnormal',$8000000000000003,-2,$8000000000000001);
      ExpectDouble('ldexp-double-overflow',$3ff0000000000000,High(Integer),$7ff0000000000000);
      ExpectDouble('ldexp-double-underflow-sign',$bff0000000000000,Low(Integer),$8000000000000000);

      if SizeOf(Extended)=10 then
        begin
          ExpectExtended('ldexp-extended-normal-to-subnormal',1,$8000000000000000,-1,0,$4000000000000000);
          ExpectExtended('ldexp-extended-tie-even-up',0,3,-1,0,2);
          ExpectExtended('ldexp-extended-above-half',0,3,-2,0,1);
          ExpectExtended('ldexp-extended-tie-even-zero',0,2,-2,0,0);
          ExpectExtended('ldexp-extended-round-to-normal',1,$ffffffffffffffff,-1,1,$8000000000000000);
          ExpectExtended('ldexp-extended-negative-subnormal',$8000,3,-2,$8000,1);
          ExpectExtended('ldexp-extended-overflow',$3fff,$8000000000000000,
            High(Integer),$7fff,$8000000000000000);
          ExpectExtended('ldexp-extended-underflow-sign',$bfff,$8000000000000000,
            Low(Integer),$8000,0);
        end;
    end;
  finally
    SetRoundMode(SavedMode);
  end;
end;

procedure CheckHypot;
begin
  if not IsInfinite(Hypot(Infinity,NaN)) then
    Fail('hypot-inf-nan',Hypot(Infinity,NaN),Infinity);
  if not IsInfinite(Hypot(NaN,NegInfinity)) then
    Fail('hypot-nan-inf',Hypot(NaN,NegInfinity),Infinity);
  if not IsNan(Hypot(NaN,1.0)) then
    Fail('hypot-nan-finite',Hypot(NaN,1.0),NaN);
  if not IsNan(Hypot(1.0,NaN)) then
    Fail('hypot-finite-nan',Hypot(1.0,NaN),NaN);
  ExpectRelative('hypot-large',Hypot(1e200,1e200),
    1.4142135623730950488e200,2e-15);
end;

procedure CheckInverseHyperbolic;
var
  Actual: Double;
  SavedMask: TFPUExceptionMask;
  Completed: Boolean;
begin
  ExpectRelative('asinh-small',ArcSinh(1e-20),1e-20,2e-15);
  ExpectClose('asinh-large',ArcSinh(1e200),461.210165779369082,2e-15);
  ExpectClose('asinh-negative-large',ArcSinh(-1e200),-461.210165779369082,2e-15);
  ExpectClose('acosh-large',ArcCosh(1e200),461.210165779369082,2e-15);
  ExpectClose('acsch-negative',ArcCscH(-1e-9),-21.416413017506358,2e-15);
  ExpectClose('acsch-tiny',ArcCscH(1e-200),461.210165779369082,2e-15);
  ExpectRelative('acsch-large',ArcCscH(1e200),1e-200,2e-15);
  ExpectClose('asech-tiny',ArcSecH(1e-308),709.889355822726016,2e-15);
  ExpectRelative('acoth-large',ArcCotH(1e20),1e-20,2e-15);
  ExpectRelative('acoth-negative-large',ArcCotH(-1e20),-1e-20,2e-15);

  SavedMask:=GetExceptionMask;
  Completed:=False;
  try
    SetExceptionMask(SavedMask-[exOverflow]);
    try
      Actual:=ArcCscH(1e-309);
      Completed:=True;
    except
      Completed:=False;
    end;
  finally
    SetExceptionMask(SavedMask);
  end;
  if not Completed then
    Fail('acsch-tiny-unmasked-overflow',Infinity,712.191940915720036);
  ExpectClose('acsch-tiny-unmasked',Actual,712.191940915720036,2e-15);
end;

procedure CheckAggregates;
var
  LargeNorm: array[0..1] of Double;
  LargeMean: array[0..2] of Double;
  BalancedMean: array[0..3] of Double;
  TinyNorm: array[0..0] of Double;
  SmallNorm: array[0..1] of Double;
  Special: array[0..1] of Double;
  TinyMean: array[0..2] of Double;
begin
  LargeNorm[0]:=1e200;
  LargeNorm[1]:=1e200;
  ExpectRelative('norm-large',Norm(LargeNorm),1.4142135623730950488e200,2e-15);
  SmallNorm[0]:=1e-200;
  SmallNorm[1]:=1e-200;
  ExpectRelative('norm-small',Norm(SmallNorm),1.4142135623730950488e-200,2e-15);
  TinyNorm[0]:=1.6e-162;
  ExpectRelative('norm-subnormal-square',Norm(TinyNorm),Abs(TinyNorm[0]),2e-15);
  LargeMean[0]:=1e308;
  LargeMean[1]:=1e308;
  LargeMean[2]:=1e308;
  ExpectRelative('mean-large',Mean(LargeMean),1e308,2e-15);
  LargeMean[0]:=MaxDouble;
  LargeMean[1]:=MaxDouble;
  LargeMean[2]:=MaxDouble;
  ExpectRelative('mean-max-identical',Mean(LargeMean),MaxDouble,2e-15);
  LargeMean[0]:=-MaxDouble;
  LargeMean[1]:=-MaxDouble;
  LargeMean[2]:=-MaxDouble;
  ExpectRelative('mean-min-identical',Mean(LargeMean),-MaxDouble,2e-15);
  LargeMean[0]:=1e308;
  LargeMean[1]:=-1e308;
  LargeMean[2]:=1e-100;
  ExpectRelative('mean-cancellation-masked',Mean(LargeMean),1e-100/3,3e-15);
  BalancedMean[0]:=MaxDouble;
  BalancedMean[1]:=-MaxDouble;
  BalancedMean[2]:=-MaxDouble;
  BalancedMean[3]:=MaxDouble;
  ExpectClose('mean-balanced-extremes',Mean(BalancedMean),0.0,0.0);
  TinyMean[0]:=MinDouble/16;
  TinyMean[1]:=MinDouble/16;
  TinyMean[2]:=MinDouble/16;
  ExpectRelative('mean-subnormal-identical',Mean(TinyMean),MinDouble/16,2e-15);
  Special[0]:=Infinity;
  Special[1]:=Infinity;
  if not IsInfinite(Mean(Special)) or (Mean(Special)<0.0) then
    Fail('mean-positive-infinity',Mean(Special),Infinity);
  Special[0]:=Infinity;
  Special[1]:=NegInfinity;
  if not IsNan(Mean(Special)) then
    Fail('mean-mixed-infinity',Mean(Special),NaN);
  Special[0]:=NaN;
  Special[1]:=Infinity;
  if not IsInfinite(Norm(Special)) then
    Fail('norm-nan-infinity',Norm(Special),Infinity);
  Special[0]:=Infinity;
  Special[1]:=NaN;
  if not IsInfinite(Norm(Special)) then
    Fail('norm-infinity-nan',Norm(Special),Infinity);
end;

procedure CheckMeanSizes(const Prefix: string);
const
  Counts: array[0..8] of Integer=(2,3,4,7,11,12,13,31,64);
var
  Data: array of Double;
  C,I,N: Integer;
  Expected,Tiny: Double;
begin
  Tiny:=MinDouble/16;
  for C:=0 to High(Counts) do
    begin
      N:=Counts[C];
      SetLength(Data,N);
      for I:=0 to N-1 do
        Data[I]:=MaxDouble;
      ExpectRelative(Prefix+'-mean-max-'+IntToStr(N),Mean(Data),MaxDouble,3e-15);
      for I:=0 to N-1 do
        Data[I]:=-MaxDouble;
      ExpectRelative(Prefix+'-mean-min-'+IntToStr(N),Mean(Data),-MaxDouble,3e-15);
      for I:=0 to N-1 do
        Data[I]:=Tiny;
      ExpectRelative(Prefix+'-mean-tiny-'+IntToStr(N),Mean(Data),Tiny,3e-15);
      for I:=0 to N-1 do
        if Odd(I) then
          Data[I]:=-MaxDouble
        else
          Data[I]:=MaxDouble;
      if Odd(N) then
        Expected:=MaxDouble/N
      else
        Expected:=0.0;
      if Expected=0.0 then
        ExpectClose(Prefix+'-mean-balanced-'+IntToStr(N),Mean(Data),Expected,0.0)
      else
        ExpectRelative(Prefix+'-mean-balanced-'+IntToStr(N),Mean(Data),Expected,3e-15);
    end;
end;

procedure CheckCancellationMean(const Prefix: string);
const
  Huge = 1e308;
  Residual = 1e-100;
var
  Data: array[0..2] of Double;
  TinyInput,TinyActual: TDoubleRec;
  Expected: Double;

  procedure CheckOrder(const Suffix: string; A,B,C: Double);
  begin
    Data[0]:=A;
    Data[1]:=B;
    Data[2]:=C;
    ExpectRelative(Prefix+'-mean-cancellation-'+Suffix,Mean(Data),Expected,3e-15);
  end;

  procedure CheckTinyOrder(const Suffix: string; A,B,C: Double);
  begin
    Data[0]:=A;
    Data[1]:=B;
    Data[2]:=C;
    TinyActual.Value:=Mean(Data);
    if TinyActual.Data<>1 then
      FailBits(Prefix+'-mean-exact-cancellation-'+Suffix,TinyActual.Data,1);
  end;

begin
  Expected:=Residual/3;
  CheckOrder('pnt',Huge,-Huge,Residual);
  CheckOrder('ptn',Huge,Residual,-Huge);
  CheckOrder('tpn',Residual,Huge,-Huge);
  CheckOrder('npt',-Huge,Huge,Residual);
  CheckOrder('ntp',-Huge,Residual,Huge);
  CheckOrder('tnp',Residual,-Huge,Huge);

  { Three minimum subnormal quanta divided by three remain exactly one
    quantum.  Scaling every input before cancellation loses this value. }
  TinyInput.Data:=3;
  CheckTinyOrder('pnt',Huge,-Huge,TinyInput.Value);
  CheckTinyOrder('ptn',Huge,TinyInput.Value,-Huge);
  CheckTinyOrder('tpn',TinyInput.Value,Huge,-Huge);
  CheckTinyOrder('npt',-Huge,Huge,TinyInput.Value);
  CheckTinyOrder('ntp',-Huge,TinyInput.Value,Huge);
  CheckTinyOrder('tnp',TinyInput.Value,-Huge,Huge);
end;

procedure CheckExactMeanRounding(const Prefix: string);
var
  Data: array[0..3] of Double;
  Input,Actual: TDoubleRec;

  procedure Check(const Suffix: string; TinyBits,ExpectedBits: QWord);
  begin
    Input.Data:=TinyBits;
    Data[2]:=Input.Value;
    Data[3]:=0.0;
    Actual.Value:=Mean(Data);
    if Actual.Data<>ExpectedBits then
      FailBits(Prefix+'-mean-exact-round-'+Suffix,Actual.Data,ExpectedBits);
  end;

begin
  Input.Data:=$7fefffffffffffff;
  Data[0]:=Input.Value;
  Input.Data:=$ffefffffffffffff;
  Data[1]:=Input.Value;
  Check('positive-half',2,0);
  Check('positive-above-half',3,1);
  Check('positive-tie-even-up',6,2);
  Check('negative-half',QWord($8000000000000002),QWord($8000000000000000));
  Check('negative-above-half',QWord($8000000000000003),QWord($8000000000000001));
  Check('negative-tie-even-up',QWord($8000000000000006),QWord($8000000000000002));
end;

procedure CheckIntegerMean(const Prefix: string);
var
  Data: array[0..4] of Int64;
  Actual,ExpectedNearest: Float;
  Mode,SavedMode: TFPURoundingMode;

  procedure CheckPair(const Suffix: string; A,B: Int64; Expected: Float);
  begin
    Data[0]:=A;
    Data[1]:=B;
    Actual:=Mean(PInt64(@Data[0]),2);
    if Actual<>Expected then
      Fail(Prefix+'-mean-int64-pointer-'+Suffix,Actual,Expected);
    Actual:=Mean(Slice(Data,2));
    if Actual<>Expected then
      Fail(Prefix+'-mean-int64-array-'+Suffix,Actual,Expected);
  end;

  procedure CheckOrder(const Suffix: string; A,B,C: Int64; Expected: Float);
  begin
    Data[0]:=A;
    Data[1]:=B;
    Data[2]:=C;
    Actual:=Mean(Slice(Data,3));
    if Actual<>Expected then
      Fail(Prefix+'-mean-int64-'+Suffix,Actual,Expected);
  end;

  procedure CheckFour(const Suffix: string; A,B,C,D: Int64; Expected: Float);
  begin
    Data[0]:=A;
    Data[1]:=B;
    Data[2]:=C;
    Data[3]:=D;
    Actual:=Mean(Slice(Data,4));
    if Actual<>Expected then
      Fail(Prefix+'-mean-int64-'+Suffix,Actual,Expected);
  end;

begin
  CheckPair('high',High(Int64),High(Int64),Float(High(Int64)));
  CheckPair('low',Low(Int64),Low(Int64),Float(Low(Int64)));
  CheckPair('wide-nonoverflow',High(Int64),0,Float(High(Int64))/2);
  CheckPair('half',Int64(1) shl 62,-(Int64(1) shl 62)+1,0.5);
  CheckOrder('residual-first',1,Int64(1) shl 62,-(Int64(1) shl 62),Float(1)/3);
  CheckOrder('residual-middle',Int64(1) shl 62,1,-(Int64(1) shl 62),Float(1)/3);
  CheckOrder('residual-last',Int64(1) shl 62,-(Int64(1) shl 62),1,Float(1)/3);
  CheckFour('overflow-cancels-a',High(Int64),-High(Int64),High(Int64),-High(Int64),0);
  CheckFour('overflow-cancels-b',High(Int64),High(Int64),-High(Int64),-High(Int64),0);
  CheckFour('overflow-cancels-c',Low(Int64),Low(Int64),High(Int64),High(Int64),-0.5);
  SavedMode:=GetRoundMode;
  try
    SetRoundMode(rmNearest);
    ExpectedNearest:=Float(1)/5;
    for Mode:=Low(TFPURoundingMode) to High(TFPURoundingMode) do
      begin
        SetRoundMode(Mode);
        Data[0]:=1;
        Data[1]:=0;
        Data[2]:=0;
        Data[3]:=0;
        Data[4]:=0;
        Actual:=Mean(Data);
        if Actual<>ExpectedNearest then
          Fail(Prefix+'-mean-int64-round-small-'+IntToStr(Ord(Mode)),Actual,ExpectedNearest);
        Data[0]:=3;
        Data[1]:=4;
        Actual:=Mean(Slice(Data,2));
        if Actual<>3.5 then
          Fail(Prefix+'-mean-int64-round-exact-'+IntToStr(Ord(Mode)),Actual,3.5);
        Data[0]:=High(Int64);
        Data[1]:=-High(Int64);
        Data[2]:=High(Int64);
        Data[3]:=-High(Int64);
        Data[4]:=1;
        Actual:=Mean(Data);
        if Actual<>ExpectedNearest then
          Fail(Prefix+'-mean-int64-round-wide-'+IntToStr(Ord(Mode)),Actual,ExpectedNearest);
      end;
  finally
    SetRoundMode(SavedMode);
  end;
end;

procedure CheckIntegerMeanEngineState;
{$if defined(cpux86_64) and (sizeof(Float)>8)}
const
  PrecisionModes: array[0..2] of Word = ($0000,$0200,$0300);
var
  A,B: array[0..5] of Int64;
  ActualA,ActualB,Expected,Numerator,Denominator: Float;
  SavedCW: Word;
  SavedMXCSR: DWord;
  I: Integer;
begin
  SavedCW:=Get8087CW;
  SavedMXCSR:=GetMXCSR;
  try
    SetRoundMode(rmNearest);
    A[0]:=High(Int64);
    A[1]:=-High(Int64);
    A[2]:=-High(Int64);
    A[3]:=High(Int64);
    A[4]:=1;
    A[5]:=100663301;
    B[0]:=High(Int64);
    B[1]:=-High(Int64);
    B[2]:=High(Int64);
    B[3]:=-High(Int64);
    B[4]:=1;
    B[5]:=100663301;
    Expected:=16777217;
    for I:=Low(PrecisionModes) to High(PrecisionModes) do
      begin
        Set8087CW((Get8087CW and not Word($0300)) or PrecisionModes[I]);
        ActualA:=Mean(A);
        ActualB:=Mean(B);
        if (ActualA<>Expected) or (ActualB<>Expected) or (ActualA<>ActualB) then
          Fail('mean-int64-x87-precision-'+IntToStr(I),ActualA,Expected);
      end;

    Set8087CW((Get8087CW and not Word($0f00)) or Word($0300));
    Numerator:=1;
    Denominator:=6;
    Expected:=Numerator/Denominator;
    A[4]:=0;
    A[5]:=1;
    B[4]:=0;
    B[5]:=1;
    Set8087CW((Get8087CW and not Word($0f00)) or Word($0700));
    ActualA:=Mean(A);
    ActualB:=Mean(B);
    if (ActualA<>Expected) or (ActualB<>Expected) or (ActualA<>ActualB) then
      Fail('mean-int64-x87-rounding',ActualA,Expected);
  finally
    Set8087CW(SavedCW);
    SetMXCSR(SavedMXCSR);
  end;
end;
{$else}
begin
end;
{$endif}

procedure CheckSecondMoments(const Prefix: string);
var
  DoubleData: array[0..2] of Double;
  SingleData: array[0..2] of Single;
  ExtendedData: array[0..2] of Extended;
  MeanValue,StdDevValue,Expected,Scale: Float;
  Spacing: Integer;
begin
  Scale:=Ldexp(1.0,511);
  DoubleData[0]:=Scale;
  DoubleData[1]:=-Scale;
  DoubleData[2]:=0;
  ExpectRelative(Prefix+'-variance-array',Variance(DoubleData),Ldexp(1.0,1022),2e-15);
  ExpectRelative(Prefix+'-variance-pointer',Variance(PDouble(@DoubleData[0]),3),
    Ldexp(1.0,1022),2e-15);
  ExpectRelative(Prefix+'-total-variance',TotalVariance(DoubleData),Ldexp(1.0,1023),2e-15);
  Expected:=Ldexp(2.0/3.0,1022);
  ExpectRelative(Prefix+'-population-variance',PopnVariance(DoubleData),Expected,2e-15);
  ExpectRelative(Prefix+'-stddev',StdDev(DoubleData),Scale,2e-15);
  Expected:=Ldexp(Sqrt(2.0/3.0),511);
  ExpectRelative(Prefix+'-population-stddev',PopnStdDev(DoubleData),Expected,2e-15);
  MeanAndStdDev(DoubleData,MeanValue,StdDevValue);
  ExpectClose(Prefix+'-mean-and-stddev-mean',MeanValue,0,0);
  ExpectRelative(Prefix+'-mean-and-stddev-value',StdDevValue,Scale,2e-15);

  Scale:=Ldexp(1.0,900);
  DoubleData[0]:=Scale;
  DoubleData[1]:=-Scale;
  ExpectRelative(Prefix+'-stddev-huge',StdDev(DoubleData),Scale,2e-15);
  MeanAndStdDev(PDouble(@DoubleData[0]),3,MeanValue,StdDevValue);
  ExpectRelative(Prefix+'-mean-and-stddev-huge',StdDevValue,Scale,2e-15);

  Scale:=Ldexp(1.0,-900);
  DoubleData[0]:=Scale;
  DoubleData[1]:=-Scale;
  ExpectRelative(Prefix+'-stddev-tiny',StdDev(DoubleData),Scale,2e-15);
  Expected:=Ldexp(Sqrt(2.0/3.0),-900);
  ExpectRelative(Prefix+'-population-stddev-tiny',PopnStdDev(DoubleData),Expected,2e-15);

  Scale:=Ldexp(1.5,-537);
  DoubleData[0]:=Scale;
  DoubleData[1]:=-Scale;
  DoubleData[2]:=0;
  ExpectRelative(Prefix+'-stddev-subnormal-square',StdDev(DoubleData),Scale,2e-15);

  DoubleData[0]:=1;
  DoubleData[1]:=1;
  DoubleData[2]:=1+Ldexp(1.0,-52);
  Expected:=Ldexp(Float(1),-104)/3;
  ExpectRelative(Prefix+'-variance-rounded-center',Variance(DoubleData),Expected,2e-15);

  for Spacing:=1 to 15 do
    begin
      DoubleData[0]:=1;
      DoubleData[1]:=1+Ldexp(Double(Spacing),-52);
      Expected:=Ldexp(Float(Spacing*Spacing),-105);
      ExpectClose(Prefix+'-variance-double-neighbor-array-'+IntToStr(Spacing),
        Variance(Slice(DoubleData,2)),Expected,0);
      ExpectClose(Prefix+'-variance-double-neighbor-pointer-'+IntToStr(Spacing),
        Variance(PDouble(@DoubleData[0]),2),Expected,0);
      ExpectClose(Prefix+'-total-variance-double-neighbor-'+IntToStr(Spacing),
        TotalVariance(Slice(DoubleData,2)),Expected,0);
      ExpectClose(Prefix+'-popn-variance-double-neighbor-'+IntToStr(Spacing),
        PopnVariance(Slice(DoubleData,2)),Expected/2,0);
      ExpectRelative(Prefix+'-stddev-double-neighbor-'+IntToStr(Spacing),
        StdDev(Slice(DoubleData,2)),Sqrt(Expected),2e-15);
      ExpectRelative(Prefix+'-popn-stddev-double-neighbor-'+IntToStr(Spacing),
        PopnStdDev(Slice(DoubleData,2)),Sqrt(Expected/2),2e-15);
      MeanAndStdDev(Slice(DoubleData,2),MeanValue,StdDevValue);
      ExpectRelative(Prefix+'-mean-stddev-double-neighbor-'+IntToStr(Spacing),
        StdDevValue,Sqrt(Expected),2e-15);
    end;

  for Spacing:=1 to 15 do
    begin
      SingleData[0]:=1;
      SingleData[1]:=1+Ldexp(Single(Spacing),-23);
      Expected:=Ldexp(Float(Spacing*Spacing),-47);
      ExpectClose(Prefix+'-variance-single-neighbor-'+IntToStr(Spacing),
        Variance(Slice(SingleData,2)),Expected,0);
      ExpectRelative(Prefix+'-stddev-single-neighbor-'+IntToStr(Spacing),
        StdDev(Slice(SingleData,2)),Sqrt(Expected),2e-15);
    end;

  SingleData[0]:=MaxSingle;
  SingleData[1]:=-MaxSingle;
  SingleData[2]:=0;
  ExpectRelative(Prefix+'-single-stddev',StdDev(SingleData),MaxSingle,2e-7);
  ExpectRelative(Prefix+'-single-variance',Variance(SingleData),
    Float(MaxSingle)*Float(MaxSingle),2e-7);

  if SizeOf(Extended)=10 then
    begin
      Scale:=Ldexp(Extended(1.0),9000);
      ExtendedData[0]:=Scale;
      ExtendedData[1]:=-Scale;
      ExtendedData[2]:=0;
      ExpectRelative(Prefix+'-extended-stddev-huge',StdDev(ExtendedData),Scale,2e-18);
      Scale:=Ldexp(Extended(1.0),-9000);
      ExtendedData[0]:=Scale;
      ExtendedData[1]:=-Scale;
      ExpectRelative(Prefix+'-extended-stddev-tiny',StdDev(ExtendedData),Scale,2e-18);
      for Spacing:=1 to 15 do
        begin
          ExtendedData[0]:=1;
          ExtendedData[1]:=1+Ldexp(Extended(Spacing),-63);
          Expected:=Ldexp(Float(Spacing*Spacing),-127);
          ExpectClose(Prefix+'-variance-extended-neighbor-'+IntToStr(Spacing),
            Variance(Slice(ExtendedData,2)),Expected,0);
          ExpectRelative(Prefix+'-stddev-extended-neighbor-'+IntToStr(Spacing),
            StdDev(Slice(ExtendedData,2)),Sqrt(Expected),4e-16);
        end;
    end;

  DoubleData[0]:=42;
  ExpectClose(Prefix+'-variance-singleton',Variance(PDouble(@DoubleData[0]),1),0,0);
  ExpectClose(Prefix+'-stddev-singleton',StdDev(PDouble(@DoubleData[0]),1),0,0);

  DoubleData[0]:=0;
  DoubleData[1]:=0;
  DoubleData[2]:=0;
  MeanValue:=123;
  StdDevValue:=456;
  MeanAndStdDev(DoubleData,MeanValue,StdDevValue);
  ExpectClose(Prefix+'-mean-and-stddev-zero-double-mean',MeanValue,0,0);
  ExpectClose(Prefix+'-mean-and-stddev-zero-double-value',StdDevValue,0,0);
  MeanValue:=123;
  StdDevValue:=456;
  MeanAndStdDev(PDouble(@DoubleData[0]),1,MeanValue,StdDevValue);
  ExpectClose(Prefix+'-mean-and-stddev-zero-double-singleton-mean',MeanValue,0,0);
  ExpectClose(Prefix+'-mean-and-stddev-zero-double-singleton-value',StdDevValue,0,0);

  SingleData[0]:=0;
  SingleData[1]:=0;
  SingleData[2]:=0;
  MeanValue:=123;
  StdDevValue:=456;
  MeanAndStdDev(SingleData,MeanValue,StdDevValue);
  ExpectClose(Prefix+'-mean-and-stddev-zero-single-mean',MeanValue,0,0);
  ExpectClose(Prefix+'-mean-and-stddev-zero-single-value',StdDevValue,0,0);

  ExtendedData[0]:=0;
  ExtendedData[1]:=0;
  ExtendedData[2]:=0;
  MeanValue:=123;
  StdDevValue:=456;
  MeanAndStdDev(ExtendedData,MeanValue,StdDevValue);
  ExpectClose(Prefix+'-mean-and-stddev-zero-extended-mean',MeanValue,0,0);
  ExpectClose(Prefix+'-mean-and-stddev-zero-extended-value',StdDevValue,0,0);

  DoubleData[0]:=Infinity;
  DoubleData[1]:=Infinity;
  if not IsNan(Variance(PDouble(@DoubleData[0]),2)) then
    Fail(Prefix+'-variance-infinity',Variance(PDouble(@DoubleData[0]),2),NaN);
end;

procedure CheckSecondMomentAcceptanceBoundaries;
const
  N=500000;
var
  Data: array of Double;
  SingleData: array of Single;
  ExtendedData: array of Extended;
  I: Integer;
  Step,Expected,MeanValue,StdDevValue: Float;
begin
  SetLength(Data,N);
  Step:=Ldexp(Float(1),-52);
  for I:=0 to N-1 do
    Data[I]:=1+Step*Ord(Odd(I));
  Expected:=Sqr(Step)*Float(N)/(4*Float(N-1));
  ExpectClose('variance-large-tight-cluster',Variance(Data),Expected,0);

  Data[0]:=0;
  for I:=1 to N-1 do
    Data[I]:=1;
  ExpectRelative('variance-large-skewed-cluster',Variance(Data),Float(1)/N,3e-15);

  { Cross the acceptance boundary with a center error that is small in
    absolute terms but material relative to the second moment. }
  Step:=Ldexp(Float(65537),-52);
  for I:=0 to N-1 do
    Data[I]:=1+Step*Ord(Odd(I));
  Expected:=Sqr(Step)*Float(N)/(4*Float(N-1));
  ExpectRelative('variance-large-acceptance-boundary',Variance(Data),Expected,2e-15);

  SetLength(Data,64);
  Step:=Ldexp(Float((Int64(1) shl 22)+1),-52);
  for I:=0 to High(Data) do
    Data[I]:=1+Step*Ord(Odd(I));
  Expected:=Sqr(Step)*Length(Data)/(4*Float(Length(Data)-1));
  ExpectRelative('variance-acceptance-boundary-array',Variance(Data),Expected,2e-15);
  ExpectRelative('variance-acceptance-boundary-pointer',
    Variance(PDouble(@Data[0]),Length(Data)),Expected,2e-15);
  ExpectRelative('total-variance-acceptance-boundary',TotalVariance(Data),
    Sqr(Step)*Length(Data)/4,2e-15);
  ExpectRelative('popn-variance-acceptance-boundary',PopnVariance(Data),
    Sqr(Step)/4,2e-15);
  ExpectRelative('stddev-acceptance-boundary',StdDev(Data),Sqrt(Expected),2e-15);
  ExpectRelative('popn-stddev-acceptance-boundary',PopnStdDev(Data),
    Sqrt(Sqr(Step)/4),2e-15);
  MeanAndStdDev(Data,MeanValue,StdDevValue);
  ExpectRelative('mean-and-stddev-acceptance-boundary',StdDevValue,Sqrt(Expected),2e-15);

  SetLength(SingleData,500003);
  Step:=Ldexp(Float(1),-23);
  for I:=0 to High(SingleData)-1 do
    SingleData[I]:=1;
  SingleData[High(SingleData)]:=1+Step;
  Expected:=Sqr(Step)/Length(SingleData);
  ExpectRelative('variance-single-acceptance-boundary',Variance(SingleData),Expected,2e-15);
  ExpectRelative('stddev-single-acceptance-boundary',StdDev(SingleData),Sqrt(Expected),2e-15);

  if SizeOf(Extended)>8 then
    begin
      SetLength(ExtendedData,N);
      Step:=Ldexp(Float((Int64(1) shl 27)+1),-63);
      for I:=0 to High(ExtendedData) do
        ExtendedData[I]:=1+Step*Ord(Odd(I));
      Expected:=Sqr(Step)*Float(N)/(4*Float(N-1));
      ExpectRelative('variance-extended-acceptance-boundary',
        Variance(ExtendedData),Expected,2e-18);
      ExpectRelative('stddev-extended-acceptance-boundary',
        StdDev(ExtendedData),Sqrt(Expected),4e-16);
    end;
end;

procedure CheckSecondMomentAcceptanceMatrix;
const
  Counts: array[0..9] of Integer=(2,11,12,13,63,64,65,1023,1024,1025);
  Powers: array[0..5] of Integer=(15,19,22,27,32,37);
var
  DoubleData: array of Double;
  ExtendedData: array of Extended;
  CountIndex,PowerIndex,I,N,LowerCount,UpperCount: Integer;
  Spacing,Step,Expected: Float;
begin
  for CountIndex:=Low(Counts) to High(Counts) do
    begin
      N:=Counts[CountIndex];
      LowerCount:=(N+1) div 2;
      UpperCount:=N div 2;
      SetLength(DoubleData,N);
      if SizeOf(Extended)>8 then
        SetLength(ExtendedData,N);
      for PowerIndex:=Low(Powers) to High(Powers) do
        begin
          Spacing:=Ldexp(Float(1),Powers[PowerIndex])+1;
          Step:=Ldexp(Spacing,-52);
          for I:=0 to N-1 do
            DoubleData[I]:=1+Step*Ord(Odd(I));
          Expected:=Sqr(Step)*LowerCount*UpperCount/(Float(N)*Float(N-1));
          ExpectRelative('variance-double-acceptance-matrix-'+
            IntToStr(N)+'-'+IntToStr(Powers[PowerIndex]),
            Variance(DoubleData),Expected,2e-15);

          if SizeOf(Extended)>8 then
            begin
              Step:=Ldexp(Spacing,-63);
              for I:=0 to N-1 do
                ExtendedData[I]:=1+Step*Ord(Odd(I));
              Expected:=Sqr(Step)*LowerCount*UpperCount/(Float(N)*Float(N-1));
              ExpectRelative('variance-extended-acceptance-matrix-'+
                IntToStr(N)+'-'+IntToStr(Powers[PowerIndex]),
                Variance(ExtendedData),Expected,2e-18);
            end;
        end;
    end;
end;

procedure CheckSecondMomentExceptionalState;
var
  Data: array[0..5] of Double;
  SavedMask: TFPUExceptionMask;
  Actual: Float;
  X: Double;
  E,J,K: Integer;
  Raised: Boolean;
begin
  SavedMask:=GetExceptionMask;
  try
    SetExceptionMask(SavedMask-[exOverflow,exUnderflow]);
    Data[0]:=1;
    Data[1]:=-1;
    Data[2]:=Ldexp(Float(1),-600);
    ExpectClose('stddev-mixed-scale-unmasked',StdDev(Slice(Data,3)),1,0);

    { Exercise the compensation path with the tiny terms before and after the
      normal ones.  The result is normal, so no intermediate underflow may
      escape from a correct scaled implementation. }
    for E:=-520 to -480 do
      for J:=0 to 63 do
        for K:=0 to 3 do
          begin
            X:=Ldexp(Double(1),E);
            TDoubleRec(X).Data:=TDoubleRec(X).Data+J;
            Data[0]:=X;
            Data[1]:=-X;
            TDoubleRec(Data[1]).Data:=TDoubleRec(Data[1]).Data+1;
            Data[2]:=X;
            TDoubleRec(Data[2]).Data:=TDoubleRec(Data[2]).Data+2;
            Data[3]:=-X;
            Data[4]:=1;
            Data[5]:=-1;
            if K and 1<>0 then
              begin
                Data[4]:=Data[0];
                Data[0]:=1;
              end;
            if K and 2<>0 then
              begin
                Data[5]:=Data[1];
                Data[1]:=-1;
              end;
            Actual:=StdDev(Data);
            ExpectRelative('stddev-tiny-compensation-unmasked',Actual,Sqrt(0.4),2e-15);
          end;

    SetExceptionMask(SavedMask-[exInvalidOp]);
    Data[0]:=Infinity;
    Data[1]:=Infinity;
    Raised:=False;
    try
      Actual:=StdDev(Slice(Data,2));
    except
      on EInvalidOp do
        Raised:=True;
    end;
    if not Raised then
      Fail('stddev-infinity-invalid-not-raised',Actual,NaN);
  finally
    SetExceptionMask(SavedMask);
  end;
end;

procedure CheckNeighborMeanTypes(const Prefix: string; AllOrders: Boolean);
var
  SingleData: array[0..2] of Single;
  SingleTiny: TSingleRec;
  SingleActual,SingleExpected: Float;
  ExtendedData: array[0..2] of Extended;
  ExtendedTiny,ExtendedActual: TExtendedBits;

  procedure CheckSingleOrder(const Suffix: string; A,B,C: Single);
  begin
    SingleData[0]:=A;
    SingleData[1]:=B;
    SingleData[2]:=C;
    SingleActual:=Mean(SingleData);
    if SingleActual<>SingleExpected then
      Fail(Prefix+'-mean-single-cancellation-'+Suffix,SingleActual,SingleExpected);
  end;

  procedure CheckSingleBits(Bits: DWord);
  begin
    SingleTiny.Data:=Bits;
    SingleExpected:=Float(SingleTiny.Value)/3;
    CheckSingleOrder(IntToStr(Bits)+'-pnt',MaxSingle,-MaxSingle,SingleTiny.Value);
    if AllOrders then
      begin
        CheckSingleOrder(IntToStr(Bits)+'-ptn',MaxSingle,SingleTiny.Value,-MaxSingle);
        CheckSingleOrder(IntToStr(Bits)+'-tpn',SingleTiny.Value,MaxSingle,-MaxSingle);
        CheckSingleOrder(IntToStr(Bits)+'-npt',-MaxSingle,MaxSingle,SingleTiny.Value);
        CheckSingleOrder(IntToStr(Bits)+'-ntp',-MaxSingle,SingleTiny.Value,MaxSingle);
        CheckSingleOrder(IntToStr(Bits)+'-tnp',SingleTiny.Value,-MaxSingle,MaxSingle);
      end;
  end;

  procedure CheckExtendedOrder(const Suffix: string; A,B,C: Extended;
    ExpectedExp: Word; ExpectedFrac: QWord);
  begin
    ExtendedData[0]:=A;
    ExtendedData[1]:=B;
    ExtendedData[2]:=C;
    ExtendedActual.Value:=Mean(ExtendedData);
    if (ExtendedActual.Exp<>ExpectedExp) or
       (ExtendedActual.Frac<>ExpectedFrac) then
      begin
        WriteLn('FAIL ',Prefix,'-mean-extended-cancellation-',Suffix,
          ' actual=',IntToHex(ExtendedActual.Exp,4),':',
          IntToHex(ExtendedActual.Frac,16),' expected=',
          IntToHex(ExpectedExp,4),':',IntToHex(ExpectedFrac,16));
        Halt(1);
      end;
  end;

  procedure CheckExtendedTiny(Sign: Word);
  begin
    ExtendedTiny.Exp:=Sign;
    ExtendedTiny.Frac:=3;
    CheckExtendedOrder(IntToHex(Sign,4)+'-pnt',MaxFloat,-MaxFloat,
      ExtendedTiny.Value,Sign,1);
    if AllOrders then
      begin
        CheckExtendedOrder(IntToHex(Sign,4)+'-ptn',MaxFloat,
          ExtendedTiny.Value,-MaxFloat,Sign,1);
        CheckExtendedOrder(IntToHex(Sign,4)+'-tpn',ExtendedTiny.Value,
          MaxFloat,-MaxFloat,Sign,1);
        CheckExtendedOrder(IntToHex(Sign,4)+'-npt',-MaxFloat,
          MaxFloat,ExtendedTiny.Value,Sign,1);
        CheckExtendedOrder(IntToHex(Sign,4)+'-ntp',-MaxFloat,
          ExtendedTiny.Value,MaxFloat,Sign,1);
        CheckExtendedOrder(IntToHex(Sign,4)+'-tnp',ExtendedTiny.Value,
          -MaxFloat,MaxFloat,Sign,1);
      end;
  end;

begin
  CheckSingleBits(1);
  CheckSingleBits(3);
  CheckSingleBits($80000001);
  CheckSingleBits($80000003);
  if SizeOf(Extended)=10 then
    begin
      CheckExtendedTiny(0);
      CheckExtendedTiny($8000);
    end;
end;

procedure CheckRoundTo;
const
  MXCSRModes: array[0..3] of DWord = ($1f80,$1fc0,$9f80,$9fc0);
var
  Mode: TFPURoundingMode;
  BeforeState,AfterState: TNativeFPUControlWord;
  SavedMask: TFPUExceptionMask;
  Actual: Double;
  SingleActual: Single;
  ExtendedActual: Extended;
  DoubleInput,DoubleOutput: TDoubleRec;
  SingleInput,SingleOutput: TSingleRec;
  NegativeZeroBits,ActualBits: QWord;
  NegativeZero: Double absolute NegativeZeroBits;
  ActualAsBits: Double absolute ActualBits;
  Digits: TRoundToRange;
  Completed: Boolean;
  ChangedMXCSR,SavedMXCSR: DWord;
  MXCSRModeIndex: Integer;
begin
  ExpectClose('roundto-cents',RoundTo(123.456,-2),123.46,2e-15);
  ExpectClose('roundto-cents-positive-half-neighbour',RoundTo(0.005,-2),0.01,0.0);
  ExpectClose('roundto-cents-negative-half-neighbour',RoundTo(-0.005,-2),-0.01,0.0);
  ExpectClose('roundto-even-positive-down',RoundTo(2.5,0),2.0,0.0);
  ExpectClose('roundto-even-positive-up',RoundTo(3.5,0),4.0,0.0);
  ExpectClose('roundto-even-negative-up',RoundTo(-2.5,0),-2.0,0.0);
  ExpectClose('roundto-even-negative-down',RoundTo(-3.5,0),-4.0,0.0);
  ExpectClose('roundto-large',RoundTo(1e20,0),1e20,0.0);
  ExpectClose('roundto-huge',RoundTo(1e100,-2),1e100,0.0);

  DoubleInput.Data:=$4364000000000003;
  DoubleOutput.Value:=RoundTo(DoubleInput.Value,1);
  if DoubleOutput.Data<>QWord($4364000000000002) then
    FailBits('roundto-double-half-neighbour',DoubleOutput.Data,QWord($4364000000000002));
  SingleInput.Data:=$4ca00003;
  SingleOutput.Value:=RoundTo(SingleInput.Value,1);
  if SingleOutput.Data<>$4ca00002 then
    FailBits('roundto-single-half-neighbour',SingleOutput.Data,$4ca00002);
  SingleInput.Value:=1.0;
  SingleOutput.Value:=RoundTo(SingleInput.Value,37);
  if SingleOutput.Data<>0 then
    FailBits('roundto-single-wide-quantum',SingleOutput.Data,0);

  SingleActual:=RoundTo(Single(3.5),0);
  ExpectClose('roundto-single',SingleActual,4.0,0.0);
  ExtendedActual:=RoundTo(Extended(-3.5),0);
  ExpectClose('roundto-extended',ExtendedActual,-4.0,0.0);

  NegativeZeroBits:=$8000000000000000;
  Actual:=RoundTo(NegativeZero,0);
  ActualAsBits:=Actual;
  if ActualBits<>NegativeZeroBits then
    Fail('roundto-negative-zero',Actual,NegativeZero);
  Actual:=RoundTo(-1e-300,-22);
  ActualAsBits:=Actual;
  if ActualBits<>NegativeZeroBits then
    Fail('roundto-negative-underflow-zero',Actual,NegativeZero);
  if not IsNan(RoundTo(NaN,0)) then
    Fail('roundto-nan',RoundTo(NaN,0),NaN);
  if not IsInfinite(RoundTo(Infinity,0)) then
    Fail('roundto-infinity',RoundTo(Infinity,0),Infinity);

  SavedMXCSR:=GetMXCSR;
  try
    for Digits:=Low(TRoundToRange) to High(TRoundToRange) do
      begin
        for MXCSRModeIndex:=Low(MXCSRModes) to High(MXCSRModes) do
          begin
            ChangedMXCSR:=(SavedMXCSR and not DWord($e07f)) or MXCSRModes[MXCSRModeIndex];
            {$if defined(cpux86_64)}
            RawSetMXCSR(@ChangedMXCSR);
            {$else}
            SetMXCSR(ChangedMXCSR);
            {$endif}
            DoubleInput.Data:=1;
            SingleInput.Data:=1;
            DoubleOutput.Value:=RoundTo(DoubleInput.Value,Digits);
            SingleOutput.Value:=RoundTo(SingleInput.Value,Digits);
            if DoubleOutput.Data<>0 then
              FailBits('roundto-positive-double-'+IntToStr(Digits),DoubleOutput.Data,0);
            if SingleOutput.Data<>0 then
              FailBits('roundto-positive-single-'+IntToStr(Digits),SingleOutput.Data,0);
            DoubleInput.Data:=QWord($8000000000000001);
            SingleInput.Data:=$80000001;
            DoubleOutput.Value:=RoundTo(DoubleInput.Value,Digits);
            SingleOutput.Value:=RoundTo(SingleInput.Value,Digits);
            if DoubleOutput.Data<>QWord($8000000000000000) then
              FailBits('roundto-negative-double-'+IntToStr(Digits),DoubleOutput.Data,
                QWord($8000000000000000));
            if SingleOutput.Data<>$80000000 then
              FailBits('roundto-negative-single-'+IntToStr(Digits),SingleOutput.Data,
                $80000000);
            DoubleInput.Data:=QWord($000fffffffffffff);
            SingleInput.Data:=$007fffff;
            DoubleOutput.Value:=RoundTo(DoubleInput.Value,Digits);
            SingleOutput.Value:=RoundTo(SingleInput.Value,Digits);
            if DoubleOutput.Data<>0 then
              FailBits('roundto-max-subnormal-double-'+IntToStr(Digits),DoubleOutput.Data,0);
            if SingleOutput.Data<>0 then
              FailBits('roundto-max-subnormal-single-'+IntToStr(Digits),SingleOutput.Data,0);
          end;
      end;
  finally
    {$if defined(cpux86_64)}
    RawSetMXCSR(@SavedMXCSR);
    {$else}
    SetMXCSR(SavedMXCSR);
    {$endif}
  end;

  for Digits:=Low(TRoundToRange) to High(TRoundToRange) do
    begin
      Actual:=RoundTo(123.456,Digits);
      if IsNan(Actual) or IsInfinite(Actual) then
        Fail('roundto-digit-'+IntToStr(Digits),Actual,123.456);
    end;

  for Mode:=Low(TFPURoundingMode) to High(TFPURoundingMode) do
    begin
      SetRoundMode(Mode);
      BeforeState:=GetNativeFPUControlWord;
      ExpectClose('roundto-mode-positive-'+IntToStr(Ord(Mode)),RoundTo(2.5,0),2.0,0.0);
      ExpectClose('roundto-mode-negative-'+IntToStr(Ord(Mode)),RoundTo(-2.5,0),-2.0,0.0);
      ExpectClose('roundto-mode-cents-'+IntToStr(Ord(Mode)),RoundTo(123.456,-2),123.46,2e-15);
      AfterState:=GetNativeFPUControlWord;
      if not CompareMem(@BeforeState,@AfterState,SizeOf(BeforeState)) then
        Fail('roundto-fpu-state-'+IntToStr(Ord(Mode)),Ord(GetRoundMode),Ord(Mode));
    end;
  SetRoundMode(rmNearest);

  BeforeState:=GetNativeFPUControlWord;
  try
    for Mode:=Low(TFPURoundingMode) to High(TFPURoundingMode) do
      begin
        Set8087CW((BeforeState.cw8087 and $f3ff) or (Ord(Mode) shl 10));
        ChangedMXCSR:=(BeforeState.MXCSR and $ffff9fff) or (DWord(Ord(Mode)) shl 13);
        {$if defined(cpux86_64)}
        RawSetMXCSR(@ChangedMXCSR);
        {$else}
        SetMXCSR(ChangedMXCSR);
        {$endif}
        ExpectClose('roundto-direct-mode-'+IntToStr(Ord(Mode)),RoundTo(123.456,-2),123.46,2e-15);
      end;
  finally
    Set8087CW(BeforeState.cw8087);
    {$if defined(cpux86_64)}
    RawSetMXCSR(@BeforeState.MXCSR);
    {$else}
    SetMXCSR(BeforeState.MXCSR);
    {$endif}
  end;

  SavedMask:=GetExceptionMask;
  Completed:=False;
  try
    SetExceptionMask(SavedMask-[exInvalidOp]);
    try
      Actual:=RoundTo(1e20,0);
      Completed:=True;
    except
      Completed:=False;
    end;
  finally
    SetExceptionMask(SavedMask);
  end;
  if not Completed then
    Fail('roundto-large-unmasked-invalid',Infinity,1e20);
  ExpectClose('roundto-large-unmasked',Actual,1e20,0.0);
end;

procedure CheckAggregatesUnmasked;
var
  LargeNorm: array[0..1] of Double;
  LargeMean: array[0..2] of Double;
  BalancedMean: array[0..3] of Double;
  SingleNorm: array[0..0] of Single;
  SingleMean: array[0..1] of Single;
  MultiLevelSingle: array[0..4] of Single;
  TrueOverflow: array[0..2] of Extended;
  TinySingle: TSingleRec;
  SavedMask: TFPUExceptionMask;
  Actual: Float;
  Completed,Raised: Boolean;
begin
  SavedMask:=GetExceptionMask;
  try
    SetExceptionMask(SavedMask-[exOverflow]);

    LargeNorm[0]:=1e200;
    LargeNorm[1]:=1e200;
    Completed:=False;
    try
      Actual:=Norm(LargeNorm);
      Completed:=True;
    except
      Completed:=False;
    end;
    if not Completed then
      Fail('norm-large-unmasked-overflow',Infinity,1.4142135623730950488e200);
    ExpectRelative('norm-large-unmasked',Actual,1.4142135623730950488e200,2e-15);

    SingleNorm[0]:=MaxSingle;
    Completed:=False;
    try
      Actual:=Norm(SingleNorm);
      Completed:=True;
    except
      Completed:=False;
    end;
    if not Completed then
      Fail('norm-single-max-unmasked-overflow',Infinity,MaxSingle);
    ExpectRelative('norm-single-max-unmasked',Actual,MaxSingle,2e-7);

    LargeMean[0]:=MaxDouble;
    LargeMean[1]:=MaxDouble;
    LargeMean[2]:=MaxDouble;
    Completed:=False;
    try
      Actual:=Mean(LargeMean);
      Completed:=True;
    except
      Completed:=False;
    end;
    if not Completed then
      Fail('mean-max-unmasked-overflow',Infinity,MaxDouble);
    ExpectRelative('mean-max-unmasked',Actual,MaxDouble,2e-15);

    BalancedMean[0]:=MaxDouble;
    BalancedMean[1]:=-MaxDouble;
    BalancedMean[2]:=-MaxDouble;
    BalancedMean[3]:=MaxDouble;
    Completed:=False;
    try
      Actual:=Mean(BalancedMean);
      Completed:=True;
    except
      Completed:=False;
    end;
    if not Completed then
      Fail('mean-balanced-unmasked-overflow',Infinity,0.0);
    ExpectClose('mean-balanced-unmasked',Actual,0.0,0.0);

    CheckMeanSizes('unmasked');
    CheckIntegerMean('unmasked');
    CheckSecondMoments('unmasked');
    SetExceptionMask(SavedMask-[exOverflow,exUnderflow]);
    CheckSecondMoments('unmasked-overflow-underflow');
    SetExceptionMask(SavedMask-[exOverflow]);
    CheckCancellationMean('unmasked');
    CheckExactMeanRounding('unmasked');
    CheckNeighborMeanTypes('unmasked',True);

    { The overflow-safe paths must not suppress a different unmasked FP
      exception carried by non-finite input. }
    SetExceptionMask(SavedMask-[exOverflow,exInvalidOp]);
    LargeMean[0]:=MaxDouble;
    LargeMean[1]:=MaxDouble;
    LargeMean[2]:=Infinity;
    Actual:=Mean(LargeMean);
    if not IsInfinite(Actual) or (Actual<0) then
      Fail('mean-double-finite-prefix-infinity',Actual,Infinity);
    LargeMean[2]:=NaN;
    Actual:=Mean(LargeMean);
    if not IsNan(Actual) then
      Fail('mean-double-finite-prefix-nan',Actual,NaN);

    TrueOverflow[0]:=MaxFloat;
    TrueOverflow[1]:=MaxFloat;
    TrueOverflow[2]:=Infinity;
    Actual:=Mean(TrueOverflow);
    if not IsInfinite(Actual) or (Actual<0) then
      Fail('mean-extended-finite-prefix-infinity',Actual,Infinity);
    TrueOverflow[2]:=NaN;
    Actual:=Mean(TrueOverflow);
    if not IsNan(Actual) then
      Fail('mean-extended-finite-prefix-nan',Actual,NaN);

    LargeMean[0]:=Infinity;
    LargeMean[1]:=NegInfinity;
    LargeMean[2]:=0;
    Raised:=False;
    try
      Actual:=Mean(LargeMean);
    except
      on E: EInvalidOp do
        Raised:=True;
    end;
    if not Raised then
      Fail('mean-double-invalid-not-raised',Actual,NaN);
    SingleMean[0]:=Infinity;
    SingleMean[1]:=NegInfinity;
    Raised:=False;
    try
      Actual:=Mean(SingleMean);
    except
      on E: EInvalidOp do
        Raised:=True;
    end;
    if not Raised then
      Fail('mean-single-invalid-not-raised',Actual,NaN);
    TrueOverflow[0]:=Infinity;
    TrueOverflow[1]:=NegInfinity;
    TrueOverflow[2]:=0;
    Raised:=False;
    try
      Actual:=Mean(TrueOverflow);
    except
      on E: EInvalidOp do
        Raised:=True;
    end;
    if not Raised then
      Fail('mean-extended-invalid-not-raised',Actual,NaN);

    SetExceptionMask(SavedMask-[exOverflow]);

    TinySingle.Data:=1;
    MultiLevelSingle[0]:=MaxSingle;
    MultiLevelSingle[1]:=1;
    MultiLevelSingle[2]:=TinySingle.Value;
    MultiLevelSingle[3]:=-MaxSingle;
    MultiLevelSingle[4]:=-1;
    Actual:=Mean(MultiLevelSingle);
    if Actual<>Float(TinySingle.Value)/Length(MultiLevelSingle) then
      Fail('mean-single-multilevel-cancellation',Actual,
        Float(TinySingle.Value)/Length(MultiLevelSingle));
    MultiLevelSingle[0]:=TinySingle.Value;
    MultiLevelSingle[1]:=-1;
    MultiLevelSingle[2]:=-MaxSingle;
    MultiLevelSingle[3]:=MaxSingle;
    MultiLevelSingle[4]:=1;
    Actual:=Mean(MultiLevelSingle);
    if Actual<>Float(TinySingle.Value)/Length(MultiLevelSingle) then
      Fail('mean-single-multilevel-permuted',Actual,
        Float(TinySingle.Value)/Length(MultiLevelSingle));

    TrueOverflow[0]:=MaxFloat;
    TrueOverflow[1]:=MaxFloat;
    TrueOverflow[2]:=0;
    Raised:=False;
    try
      Actual:=Norm(TrueOverflow);
    except
      on E: EOverflow do
        Raised:=True;
    end;
    if not Raised then
      Fail('norm-real-overflow-not-raised',Actual,Infinity);
  finally
    SetExceptionMask(SavedMask);
  end;
end;

procedure CheckAggregateHardwareState;
var
  Data: array[0..1] of Double;
  MeanData: array[0..2] of Double;
  SavedCW: Word;
  SavedMXCSR: DWord;
  Actual: Float;
  Completed: Boolean;
begin
  SavedCW:=Get8087CW;
  SavedMXCSR:=GetMXCSR;
  try
    SetExceptionMask([exInvalidOp,exDenormalized,exZeroDivide,exOverflow,
      exUnderflow,exPrecision]);
    ClearExceptions(False);

    { Math is not the only writer of floating-point control state. }
    {$if sizeof(Float)>8}
    Set8087CW(Get8087CW and not Word($8));
    {$else}
    SetMXCSR((GetMXCSR and not DWord($43f)));
    {$endif}
    Data[0]:=1e200;
    Data[1]:=1e200;
    Completed:=False;
    try
      Actual:=Norm(Data);
      Completed:=True;
    except
      Completed:=False;
    end;
    if not Completed then
      Fail('norm-direct-register-overflow',Infinity,1.4142135623730950488e200);
    ExpectRelative('norm-direct-register-overflow-value',Actual,
      1.4142135623730950488e200,2e-15);

    SetExceptionMask([exInvalidOp,exDenormalized,exZeroDivide,exOverflow,
      exUnderflow,exPrecision]);
    ClearExceptions(False);
    {$if sizeof(Float)>8}
    Set8087CW(Get8087CW and not Word($8));
    {$else}
    SetMXCSR(GetMXCSR and not DWord($43f));
    {$endif}
    MeanData[0]:=MaxDouble;
    MeanData[1]:=1e-100;
    MeanData[2]:=-MaxDouble;
    Completed:=False;
    try
      Actual:=Mean(MeanData);
      Completed:=True;
    except
      Completed:=False;
    end;
    if not Completed then
      Fail('mean-direct-register-overflow',Infinity,1e-100/3);
    ExpectRelative('mean-direct-register-overflow-value',Actual,1e-100/3,3e-15);

    SetExceptionMask([exInvalidOp,exDenormalized,exZeroDivide,exOverflow,
      exUnderflow,exPrecision]);
    ClearExceptions(False);
    {$if sizeof(Float)>8}
    Set8087CW(Get8087CW and not Word($10));
    {$else}
    SetMXCSR((GetMXCSR and not DWord($83f)));
    {$endif}
    Data[0]:=1e-200;
    Data[1]:=1e-200;
    Completed:=False;
    try
      Actual:=Norm(Data);
      Completed:=True;
    except
      Completed:=False;
    end;
    if not Completed then
      Fail('norm-direct-register-underflow',0.0,1.4142135623730950488e-200);
    ExpectRelative('norm-direct-register-underflow-value',Actual,
      1.4142135623730950488e-200,2e-15);
  finally
    Set8087CW(SavedCW);
    SetMXCSR(SavedMXCSR);
  end;
end;

procedure CheckSecondMomentHardwareState;
var
  DoubleData: array[0..2] of Double;
  SingleData: array[0..2] of Single;
  {$if defined(cpux86_64) and (sizeof(Float)>8)}
  ExtendedData: array[0..2] of Extended;
  {$endif}
  DoubleBits: TDoubleRec;
  SingleBits: TSingleRec;
  SavedCW: Word;
  {$if defined(cpux86_64) and (sizeof(Float)>8)}
  StatusBefore: Word;
  {$endif}
  SavedMXCSR,ChangedMXCSR: DWord;
  Actual,Expected: Float;
  I: Integer;
begin
  SavedCW:=Get8087CW;
  SavedMXCSR:=GetMXCSR;
  try
    ChangedMXCSR:=SavedMXCSR or $9fc0;
    {$if defined(cpux86_64)}
    RawSetMXCSR(@ChangedMXCSR);
    {$else}
    SetMXCSR(ChangedMXCSR);
    {$endif}
    DoubleBits.Data:=3;
    DoubleData[0]:=DoubleBits.Value;
    DoubleBits.Data:=QWord($8000000000000003);
    DoubleData[1]:=DoubleBits.Value;
    DoubleData[2]:=0;
    DoubleBits.Value:=StdDev(DoubleData);
    if DoubleBits.Data<>3 then
      FailBits('stddev-double-daz-ftz',DoubleBits.Data,3);

    DoubleBits.Data:=3;
    DoubleData[0]:=DoubleBits.Value;
    DoubleBits.Data:=5;
    DoubleData[1]:=DoubleBits.Value;
    DoubleBits.Data:=7;
    DoubleData[2]:=DoubleBits.Value;
    DoubleBits.Value:=StdDev(DoubleData);
    if DoubleBits.Data<>2 then
      FailBits('stddev-double-daz-ftz-centered',DoubleBits.Data,2);

    SingleBits.Data:=3;
    SingleData[0]:=SingleBits.Value;
    SingleBits.Data:=$80000003;
    SingleData[1]:=SingleBits.Value;
    SingleData[2]:=0;
    Actual:=StdDev(SingleData);
    Expected:=Ldexp(Float(3),-149);
    if Actual<>Expected then
      Fail('stddev-single-daz-ftz',Actual,Expected);

    SingleBits.Data:=3;
    SingleData[0]:=SingleBits.Value;
    SingleBits.Data:=5;
    SingleData[1]:=SingleBits.Value;
    SingleBits.Data:=7;
    SingleData[2]:=SingleBits.Value;
    Actual:=StdDev(SingleData);
    Expected:=Ldexp(Float(2),-149);
    if Actual<>Expected then
      Fail('stddev-single-daz-ftz-centered',Actual,Expected);

    DoubleData[0]:=1;
    DoubleData[1]:=-1;
    DoubleData[2]:=Ldexp(Float(1),-1022);
    for I:=0 to 3 do
      begin
        ChangedMXCSR:=(SavedMXCSR or $1f80) and not DWord($800 or $6000);
        if I and 1<>0 then
          ChangedMXCSR:=ChangedMXCSR or $40;
        if I and 2<>0 then
          ChangedMXCSR:=ChangedMXCSR or $8000;
        {$if defined(cpux86_64)}
        RawSetMXCSR(@ChangedMXCSR);
        {$else}
        SetMXCSR(ChangedMXCSR);
        {$endif}
        ExpectClose('stddev-unmasked-underflow-daz-ftz-'+IntToStr(I),
          StdDev(DoubleData),1,0);
      end;

    {$if defined(cpux86_64) and (sizeof(Float)>8)}
    Expected:=Ldexp(Float(1),-48)/3;
    ExtendedData[0]:=1;
    ExtendedData[1]:=1;
    ExtendedData[2]:=1+Ldexp(Extended(1),-24);
    Set8087CW(Get8087CW and not Word($0f00));
    Actual:=ExtendedData[0]/3;
    if Actual=0 then
      Fail('x87-status-primer',Actual,Float(1)/3);
    StatusBefore:=RawGet8087StatusWord;
    if (StatusBefore and $20)=0 then
      Fail('x87-inexact-status-not-set',StatusBefore,$20);
    ExpectRelative('variance-x87-reduced-precision',Variance(ExtendedData),
      Expected,1e-6);
    if (Get8087CW and $0f00)<>0 then
      Fail('variance-x87-control-word-not-restored',Get8087CW and $0f00,0);
    if (RawGet8087StatusWord and StatusBefore)<>StatusBefore then
      Fail('variance-x87-status-not-preserved',RawGet8087StatusWord,StatusBefore);
    {$endif}
  finally
    Set8087CW(SavedCW);
    {$if defined(cpux86_64)}
    RawSetMXCSR(@SavedMXCSR);
    {$else}
    SetMXCSR(SavedMXCSR);
    {$endif}
  end;
end;

begin
  CheckOracle;
  CheckLdexp;
  CheckHypot;
  CheckInverseHyperbolic;
  CheckAggregates;
  CheckMeanSizes('masked');
  CheckIntegerMean('masked');
  CheckIntegerMeanEngineState;
  CheckSecondMoments('masked');
  CheckSecondMomentAcceptanceBoundaries;
  CheckSecondMomentAcceptanceMatrix;
  CheckSecondMomentExceptionalState;
  CheckNeighborMeanTypes('masked',False);
  CheckRoundTo;
  CheckAggregatesUnmasked;
  CheckAggregateHardwareState;
  CheckSecondMomentHardwareState;
  WriteLn('NUMERIC_RANGE_CONTRACTS_OK');
end.
