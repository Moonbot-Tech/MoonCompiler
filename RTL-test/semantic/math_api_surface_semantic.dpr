program math_api_surface_semantic;

{$mode delphiunicode}
{$define MATH_API_FINANCIAL}
{$define MATH_API_RANDOM}
{$define MATH_API_STATISTICS}
{$define MATH_API_FPU_MODES}

uses
  SysUtils,
  Math;

type
  TSingle4 = array[0..3] of Single;
  TDouble4 = array[0..3] of Double;
  TExtended4 = array[0..3] of Extended;
  TInt4 = array[0..3] of Integer;
  TInt64Array4 = array[0..3] of Int64;

procedure Check(Condition: Boolean; const Name: UnicodeString);
begin
  If not Condition then begin
    WriteLn('FAIL ', Name);
    Halt(1);
  end;
end;

procedure CheckClose(const Name: UnicodeString; Actual, Expected: Extended;
  Tolerance: Extended = 2e-6);
var
  Scale: Extended;
begin
  Check(not IsNan(Actual) and not IsInfinite(Actual), Name + ' finite');
  Scale := Abs(Expected);
  If Scale < 1 then
    Scale := 1;
  If Abs(Actual - Expected) > Tolerance * Scale then
    WriteLn('DETAIL ', Name, ' actual=', Actual:0:18, ' expected=',
      Expected:0:18, ' tolerance=', Tolerance:0:18);
  Check(Abs(Actual - Expected) <= Tolerance * Scale, Name + ' value');
end;

procedure CheckMinMaxAndRanges;
var
  D: Double;
  E: Extended;
  I: Integer;
  I64: Int64;
  Q: QWord;
  S: Single;
  Values: array[0..3] of Integer;
begin
  Values[0] := 9;
  Values[1] := -4;
  Values[2] := 17;
  Values[3] := 3;
  Check(MinIntValue(Values) = -4, 'MinIntValue');
  Check(MaxIntValue(Values) = 17, 'MaxIntValue');

  I := -7;
  Check(Math.Min(I, 4) = -7, 'Min Integer');
  Check(Math.Max(I, 4) = 4, 'Max Integer');
  I64 := -7000000000;
  Check(Math.Min(I64, Int64(4)) = I64, 'Min Int64');
  Check(Math.Max(I64, Int64(4)) = 4, 'Max Int64');
  Q := High(QWord);
  Check(Math.Min(Q, QWord(4)) = 4, 'Min QWord');
  Check(Math.Max(Q, QWord(4)) = Q, 'Max QWord');
  S := -1.25;
  Check(Math.Min(S, Single(2.5)) = S, 'Min Single');
  Check(Math.Max(S, Single(2.5)) = 2.5, 'Max Single');
  D := -1.25;
  Check(Math.Min(D, Double(2.5)) = D, 'Min Double');
  Check(Math.Max(D, Double(2.5)) = 2.5, 'Max Double');
  E := -1.25;
  Check(Math.Min(E, Extended(2.5)) = E, 'Min Extended');
  Check(Math.Max(E, Extended(2.5)) = 2.5, 'Max Extended');

  Check(InRange(4, 3, 5) and not InRange(2, 3, 5), 'InRange Integer');
  Check(InRange(Int64(4), Int64(3), Int64(5)) and
    not InRange(Int64(6), Int64(3), Int64(5)), 'InRange Int64');
  Check(InRange(Double(4), Double(3), Double(5)) and
    not InRange(Double(6), Double(3), Double(5)), 'InRange Double');
  Check(EnsureRange(2, 3, 5) = 3, 'EnsureRange Integer low');
  Check(EnsureRange(Int64(6), Int64(3), Int64(5)) = 5,
    'EnsureRange Int64 high');
  Check(EnsureRange(Double(4), Double(3), Double(5)) = 4,
    'EnsureRange Double middle');

  Check(Sign(Integer(-1)) = NegativeValue, 'Sign Integer');
  Check(Sign(Int64(0)) = ZeroValue, 'Sign Int64');
  Check(Sign(Single(1)) = PositiveValue, 'Sign Single');
  Check(Sign(Double(-1)) = NegativeValue, 'Sign Double');
  Check(Sign(Extended(1)) = PositiveValue, 'Sign Extended');
  Check(IsZero(Single(0)) and IsZero(Single(0.01), Single(0.02)),
    'IsZero Single');
  Check(IsZero(Double(0)) and IsZero(Double(0.01), Double(0.02)),
    'IsZero Double');
  Check(IsZero(Extended(0)) and IsZero(Extended(0.01), Extended(0.02)),
    'IsZero Extended');
  Check(IsNan(Single(NaN)) and IsNan(Double(NaN)) and
    IsNan(Extended(NaN)), 'IsNan overloads');
  Check(IsInfinite(Single(Infinity)) and IsInfinite(Double(Infinity)) and
    IsInfinite(Extended(Infinity)), 'IsInfinite overloads');
  Check(SameValue(Single(1), Single(1)) and
    SameValue(Single(1), Single(1.01), Single(0.02)), 'SameValue Single');
  Check(SameValue(Double(1), Double(1)) and
    SameValue(Double(1), Double(1.01), Double(0.02)), 'SameValue Double');
  Check(SameValue(Extended(1), Extended(1)) and
    SameValue(Extended(1), Extended(1.01), Extended(0.02)),
    'SameValue Extended');
end;

procedure CheckDivisionAndRounding;
var
  DWordQ, DWordR: DWord;
  I32Q, I32R: LongInt;
  QWordQ, QWordR: QWord;
  SmallQ, SmallR: SmallInt;
  WordQ, WordR: Word;
begin
  DivMod(LongInt(100), Word(9), WordQ, WordR);
  Check((WordQ = 11) and (WordR = 1), 'DivMod Word');
  DivMod(LongInt(-100), Word(9), SmallQ, SmallR);
  Check((SmallQ = -11) and (SmallR = -1), 'DivMod SmallInt');
  DivMod(DWord(100), DWord(9), DWordQ, DWordR);
  Check((DWordQ = 11) and (DWordR = 1), 'DivMod DWord');
  DivMod(QWord(High(DWord) + QWord(10)), QWord(10), QWordQ, QWordR);
  Check((QWordQ = 429496730) and (QWordR = 5), 'DivMod QWord');
  DivMod(LongInt(-100), LongInt(9), I32Q, I32R);
  Check((I32Q = -11) and (I32R = -1), 'DivMod LongInt');

  CheckClose('FMod Single', FMod(Single(5.5), Single(2)), 1.5, 1e-6);
  CheckClose('FMod Double', FMod(Double(5.5), Double(2)), 1.5);
  CheckClose('FMod Extended', FMod(Extended(5.5), Extended(2)), 1.5);
  CheckClose('operator mod Float', Float(5.5) mod Float(2), 1.5);
  CheckClose('RoundTo Single', RoundTo(Single(12.6), 0), 13, 1e-5);
  CheckClose('RoundTo Double', RoundTo(Double(12.6), 0), 13);
  CheckClose('RoundTo Extended', RoundTo(Extended(12.6), 0), 13);
  CheckClose('SimpleRoundTo Single', SimpleRoundTo(Single(12.375), -2),
    12.38, 1e-5);
  CheckClose('SimpleRoundTo Double', SimpleRoundTo(Double(12.375), -2),
    12.38);
  CheckClose('SimpleRoundTo Extended', SimpleRoundTo(Extended(12.375), -2),
    12.38);
  Check(Ceil(1.1) = 2, 'Ceil');
  Check(Ceil64(2147483648.1) = 2147483649, 'Ceil64');
  Check(Floor(-1.1) = -2, 'Floor');
  Check(Floor64(-2147483648.1) = -2147483649, 'Floor64');
end;

procedure CheckAnglesAndTrig;
var
  CosD, SinD: Double;
  CosE, SinE: Extended;
  CosS, SinS: Single;
begin
  CheckClose('DegToRad', DegToRad(180), Pi);
  CheckClose('RadToDeg', RadToDeg(Pi), 180);
  CheckClose('GradToRad', GradToRad(200), Pi);
  CheckClose('RadToGrad', RadToGrad(Pi), 200);
  CheckClose('DegToGrad', DegToGrad(180), 200);
  CheckClose('GradToDeg', GradToDeg(200), 180);

  CheckClose('CycleToDeg Single', CycleToDeg(Single(0.5)), 180, 1e-5);
  CheckClose('CycleToDeg Double', CycleToDeg(Double(0.5)), 180);
  CheckClose('CycleToDeg Extended', CycleToDeg(Extended(0.5)), 180);
  CheckClose('DegToCycle Single', DegToCycle(Single(180)), 0.5, 1e-6);
  CheckClose('DegToCycle Double', DegToCycle(Double(180)), 0.5);
  CheckClose('DegToCycle Extended', DegToCycle(Extended(180)), 0.5);
  CheckClose('CycleToGrad Single', CycleToGrad(Single(0.5)), 200, 1e-5);
  CheckClose('CycleToGrad Double', CycleToGrad(Double(0.5)), 200);
  CheckClose('CycleToGrad Extended', CycleToGrad(Extended(0.5)), 200);
  CheckClose('GradToCycle Single', GradToCycle(Single(200)), 0.5, 1e-6);
  CheckClose('GradToCycle Double', GradToCycle(Double(200)), 0.5);
  CheckClose('GradToCycle Extended', GradToCycle(Extended(200)), 0.5);
  CheckClose('CycleToRad Single', CycleToRad(Single(0.5)), Pi, 1e-6);
  CheckClose('CycleToRad Double', CycleToRad(Double(0.5)), Pi);
  CheckClose('CycleToRad Extended', CycleToRad(Extended(0.5)), Pi);
  CheckClose('RadToCycle Single', RadToCycle(Single(Pi)), 0.5, 1e-6);
  CheckClose('RadToCycle Double', RadToCycle(Double(Pi)), 0.5);
  CheckClose('RadToCycle Extended', RadToCycle(Extended(Pi)), 0.5);
  CheckClose('DegNormalize Single', DegNormalize(Single(-10)), 350, 1e-5);
  CheckClose('DegNormalize Double', DegNormalize(Double(370)), 10);
  CheckClose('DegNormalize Extended', DegNormalize(Extended(720)), 0);

  CheckClose('Tan', Tan(Pi / 4), 1);
  CheckClose('Cotan', Cotan(Pi / 4), 1);
  CheckClose('Cot', Cot(Pi / 4), 1);
  SinCos(Single(Pi / 6), SinS, CosS);
  CheckClose('SinCos Single sin', SinS, 0.5, 1e-6);
  CheckClose('SinCos Single cos', CosS, Sqrt(3) / 2, 1e-6);
  SinCos(Double(Pi / 6), SinD, CosD);
  CheckClose('SinCos Double sin', SinD, 0.5);
  CheckClose('SinCos Double cos', CosD, Sqrt(3) / 2);
  SinCos(Extended(Pi / 6), SinE, CosE);
  CheckClose('SinCos Extended sin', SinE, 0.5);
  CheckClose('SinCos Extended cos', CosE, Sqrt(3) / 2);
  CheckClose('Secant', Secant(0), 1);
  CheckClose('Cosecant', Cosecant(Pi / 2), 1);
  CheckClose('Sec', Sec(0), 1);
  CheckClose('Csc', Csc(Pi / 2), 1);

  CheckClose('ArcSin Single', ArcSin(Single(0.5)), Pi / 6, 1e-6);
  CheckClose('ArcSin Double', ArcSin(Double(0.5)), Pi / 6);
  CheckClose('ArcSin Extended', ArcSin(Extended(0.5)), Pi / 6);
  CheckClose('ArcCos Single', ArcCos(Single(0.5)), Pi / 3, 1e-6);
  CheckClose('ArcCos Double', ArcCos(Double(0.5)), Pi / 3);
  CheckClose('ArcCos Extended', ArcCos(Extended(0.5)), Pi / 3);
  CheckClose('ArcTan2', ArcTan2(1, -1), 3 * Pi / 4);
end;

procedure CheckHyperbolic;
var
  X: Extended;
begin
  X := 0.5;
  CheckClose('cosh Single', cosh(Single(X)), (Exp(X) + Exp(-X)) / 2, 1e-6);
  CheckClose('cosh Double', cosh(Double(X)), (Exp(X) + Exp(-X)) / 2);
  CheckClose('cosh Extended', cosh(Extended(X)), (Exp(X) + Exp(-X)) / 2);
  CheckClose('sinh Single', sinh(Single(X)), (Exp(X) - Exp(-X)) / 2, 1e-6);
  CheckClose('sinh Double', sinh(Double(X)), (Exp(X) - Exp(-X)) / 2);
  CheckClose('sinh Extended', sinh(Extended(X)), (Exp(X) - Exp(-X)) / 2);
  CheckClose('tanh Single', tanh(Single(X)), sinh(X) / cosh(X), 1e-6);
  CheckClose('tanh Double', tanh(Double(X)), sinh(X) / cosh(X));
  CheckClose('tanh Extended', tanh(Extended(X)), sinh(X) / cosh(X));
  CheckClose('SecH Single', SecH(Single(X)), 1 / cosh(X), 1e-6);
  CheckClose('SecH Double', SecH(Double(X)), 1 / cosh(X));
  CheckClose('SecH Extended', SecH(Extended(X)), 1 / cosh(X));
  CheckClose('CscH Single', CscH(Single(X)), 1 / sinh(X), 1e-6);
  CheckClose('CscH Double', CscH(Double(X)), 1 / sinh(X));
  CheckClose('CscH Extended', CscH(Extended(X)), 1 / sinh(X));
  CheckClose('CotH Single', CotH(Single(X)), cosh(X) / sinh(X), 1e-6);
  CheckClose('CotH Double', CotH(Double(X)), cosh(X) / sinh(X));
  CheckClose('CotH Extended', CotH(Extended(X)), cosh(X) / sinh(X));

  CheckClose('ArcCosH', ArcCosH(cosh(X)), X);
  CheckClose('ArCosH', ArCosH(cosh(X)), X);
  CheckClose('ArcSinH', ArcSinH(sinh(X)), X);
  CheckClose('ArSinH', ArSinH(sinh(X)), X);
  CheckClose('ArcTanH', ArcTanH(tanh(X)), X);
  CheckClose('ArTanH', ArTanH(tanh(X)), X);
  CheckClose('ArcSec Single', ArcSec(Single(2)), Pi / 3, 1e-6);
  CheckClose('ArcSec Double', ArcSec(Double(2)), Pi / 3);
  CheckClose('ArcSec Extended', ArcSec(Extended(2)), Pi / 3);
  CheckClose('ArcCsc Single', ArcCsc(Single(2)), Pi / 6, 1e-6);
  CheckClose('ArcCsc Double', ArcCsc(Double(2)), Pi / 6);
  CheckClose('ArcCsc Extended', ArcCsc(Extended(2)), Pi / 6);
  CheckClose('ArcCot Single', ArcCot(Single(1)), Pi / 4, 1e-6);
  CheckClose('ArcCot Double', ArcCot(Double(1)), Pi / 4);
  CheckClose('ArcCot Extended', ArcCot(Extended(1)), Pi / 4);
  CheckClose('ArcSecH Single', ArcSecH(Single(0.5)), ArcCosH(2), 1e-6);
  CheckClose('ArcSecH Double', ArcSecH(Double(0.5)), ArcCosH(2));
  CheckClose('ArcSecH Extended', ArcSecH(Extended(0.5)), ArcCosH(2));
  CheckClose('ArcCscH Single', ArcCscH(Single(2)), ArcSinH(0.5), 1e-6);
  CheckClose('ArcCscH Double', ArcCscH(Double(2)), ArcSinH(0.5));
  CheckClose('ArcCscH Extended', ArcCscH(Extended(2)), ArcSinH(0.5));
  CheckClose('ArcCotH Single', ArcCotH(Single(2)), ArcTanH(0.5), 1e-6);
  CheckClose('ArcCotH Double', ArcCotH(Double(2)), ArcTanH(0.5));
  CheckClose('ArcCotH Extended', ArcCotH(Extended(2)), ArcTanH(0.5));
end;

procedure CheckLogPowerAndFrexp;
var
  DM: Double;
  EE: Integer;
  EM: Extended;
  SE: Integer;
  SM: Single;
begin
  CheckClose('Hypot', Hypot(3, 4), 5);
  CheckClose('Log10', Log10(1000), 3);
  CheckClose('Log2', Log2(8), 3);
  CheckClose('LogN', LogN(3, 81), 4);
  CheckClose('LnXP1', LnXP1(1e-10), Ln(1 + 1e-10), 1e-10);
  CheckClose('ExpM1 Double', ExpM1(Double(1e-8)), Exp(1e-8) - 1, 1e-8);
  CheckClose('ExpM1 Extended', ExpM1(Extended(1e-8)), Exp(1e-8) - 1, 1e-8);
  CheckClose('Power', Power(9, 0.5), 3);
  CheckClose('IntPower', IntPower(3, 4), 81);
  CheckClose('operator power Float', Float(3) ** Float(4), 81);
  Check(Int64(3) ** Int64(4) = 81, 'operator power Int64');

  Frexp(Single(12), SM, SE);
  CheckClose('Frexp Single mantissa', SM, 0.75, 1e-6);
  Check(SE = 4, 'Frexp Single exponent');
  CheckClose('Ldexp Single', Ldexp(Single(0.75), 4), 12, 1e-6);
  Frexp(Double(12), DM, EE);
  CheckClose('Frexp Double mantissa', DM, 0.75);
  Check(EE = 4, 'Frexp Double exponent');
  CheckClose('Ldexp Double', Ldexp(Double(0.75), 4), 12);
  Frexp(Extended(12), EM, EE);
  CheckClose('Frexp Extended mantissa', EM, 0.75);
  Check(EE = 4, 'Frexp Extended exponent');
  CheckClose('Ldexp Extended', Ldexp(Extended(0.75), 4), 12);
end;

{$ifdef MATH_API_STATISTICS}
procedure CheckStatistics;
var
  D: TDouble4;
  E: TExtended4;
  I: TInt4;
  I64: TInt64Array4;
  K1, K2, K3, K4, Kurtosis, M, Skew, SD, SS: Float;
  S: TSingle4;
begin
  S[0] := 1; S[1] := 2; S[2] := 3; S[3] := 4;
  D[0] := 1; D[1] := 2; D[2] := 3; D[3] := 4;
  E[0] := 1; E[1] := 2; E[2] := 3; E[3] := 4;
  I[0] := 1; I[1] := 2; I[2] := 3; I[3] := 4;
  I64[0] := 1; I64[1] := 2; I64[2] := 3; I64[3] := 4;

  CheckClose('Sum Single array', Sum(S), 10);
  CheckClose('Sum Single pointer', Sum(PSingle(@S[0]), Length(S)), 10);
  CheckClose('Sum Double array', Sum(D), 10);
  CheckClose('Sum Double pointer', Sum(PDouble(@D[0]), Length(D)), 10);
  CheckClose('Sum Extended array', Sum(E), 10);
  CheckClose('Sum Extended pointer', Sum(PExtended(@E[0]), Length(E)), 10);
  CheckClose('Mean Single array', Mean(S), 2.5);
  CheckClose('Mean Single pointer', Mean(PSingle(@S[0]), Length(S)), 2.5);
  CheckClose('Mean Double array', Mean(D), 2.5);
  CheckClose('Mean Double pointer', Mean(PDouble(@D[0]), Length(D)), 2.5);
  CheckClose('Mean Extended array', Mean(E), 2.5);
  CheckClose('Mean Extended pointer', Mean(PExtended(@E[0]), Length(E)), 2.5);
  Check(SumInt(I) = 10, 'SumInt Integer array');
  Check(SumInt(PInteger(@I[0]), Length(I)) = 10, 'SumInt Integer pointer');
  Check(SumInt(I64) = 10, 'SumInt Int64 array');
  Check(SumInt(PInt64(@I64[0]), Length(I64)) = 10, 'SumInt Int64 pointer');
  CheckClose('Mean Integer array', Mean(I), 2.5);
  CheckClose('Mean Integer pointer', Mean(PInteger(@I[0]), Length(I)), 2.5);
  CheckClose('Mean Int64 array', Mean(I64), 2.5);
  CheckClose('Mean Int64 pointer', Mean(PInt64(@I64[0]), Length(I64)), 2.5);

  CheckClose('SumOfSquares Single array', SumOfSquares(S), 30);
  CheckClose('SumOfSquares Single pointer', SumOfSquares(PSingle(@S[0]), Length(S)), 30);
  CheckClose('SumOfSquares Double array', SumOfSquares(D), 30);
  CheckClose('SumOfSquares Double pointer', SumOfSquares(PDouble(@D[0]), Length(D)), 30);
  CheckClose('SumOfSquares Extended array', SumOfSquares(E), 30);
  CheckClose('SumOfSquares Extended pointer', SumOfSquares(PExtended(@E[0]), Length(E)), 30);
  SumsAndSquares(S, SS, K1);
  CheckClose('SumsAndSquares Single array sum', SS, 10);
  CheckClose('SumsAndSquares Single array squares', K1, 30);
  SumsAndSquares(PSingle(@S[0]), Length(S), SS, K1);
  CheckClose('SumsAndSquares Single pointer', SS + K1, 40);
  SumsAndSquares(D, SS, K1);
  CheckClose('SumsAndSquares Double array', SS + K1, 40);
  SumsAndSquares(PDouble(@D[0]), Length(D), SS, K1);
  CheckClose('SumsAndSquares Double pointer', SS + K1, 40);
  SumsAndSquares(E, SS, K1);
  CheckClose('SumsAndSquares Extended array', SS + K1, 40);
  SumsAndSquares(PExtended(@E[0]), Length(E), SS, K1);
  CheckClose('SumsAndSquares Extended pointer', SS + K1, 40);

  CheckClose('MinValue Single array', MinValue(S), 1);
  CheckClose('MinValue Single pointer', MinValue(PSingle(@S[0]), Length(S)), 1);
  CheckClose('MaxValue Single array', MaxValue(S), 4);
  CheckClose('MaxValue Single pointer', MaxValue(PSingle(@S[0]), Length(S)), 4);
  CheckClose('MinValue Double array', MinValue(D), 1);
  CheckClose('MinValue Double pointer', MinValue(PDouble(@D[0]), Length(D)), 1);
  CheckClose('MaxValue Double array', MaxValue(D), 4);
  CheckClose('MaxValue Double pointer', MaxValue(PDouble(@D[0]), Length(D)), 4);
  CheckClose('MinValue Extended array', MinValue(E), 1);
  CheckClose('MinValue Extended pointer', MinValue(PExtended(@E[0]), Length(E)), 1);
  CheckClose('MaxValue Extended array', MaxValue(E), 4);
  CheckClose('MaxValue Extended pointer', MaxValue(PExtended(@E[0]), Length(E)), 4);
  Check(MinValue(I) = 1, 'MinValue Integer array');
  Check(MinValue(PInteger(@I[0]), Length(I)) = 1, 'MinValue Integer pointer');
  Check(MaxValue(I) = 4, 'MaxValue Integer array');
  Check(MaxValue(PInteger(@I[0]), Length(I)) = 4, 'MaxValue Integer pointer');

  CheckClose('StdDev Single array', StdDev(S), Sqrt(5 / 3));
  CheckClose('StdDev Single pointer', StdDev(PSingle(@S[0]), Length(S)), Sqrt(5 / 3));
  CheckClose('StdDev Double array', StdDev(D), Sqrt(5 / 3));
  CheckClose('StdDev Double pointer', StdDev(PDouble(@D[0]), Length(D)), Sqrt(5 / 3));
  CheckClose('StdDev Extended array', StdDev(E), Sqrt(5 / 3));
  CheckClose('StdDev Extended pointer', StdDev(PExtended(@E[0]), Length(E)), Sqrt(5 / 3));
  MeanAndStdDev(S, M, SD);
  CheckClose('MeanAndStdDev Single array mean', M, 2.5);
  CheckClose('MeanAndStdDev Single array sd', SD, Sqrt(5 / 3));
  MeanAndStdDev(PSingle(@S[0]), Length(S), M, SD);
  CheckClose('MeanAndStdDev Single pointer', M + SD, 2.5 + Sqrt(5 / 3));
  MeanAndStdDev(D, M, SD);
  CheckClose('MeanAndStdDev Double array', M + SD, 2.5 + Sqrt(5 / 3));
  MeanAndStdDev(PDouble(@D[0]), Length(D), M, SD);
  CheckClose('MeanAndStdDev Double pointer', M + SD, 2.5 + Sqrt(5 / 3));
  MeanAndStdDev(E, M, SD);
  CheckClose('MeanAndStdDev Extended array', M + SD, 2.5 + Sqrt(5 / 3));
  MeanAndStdDev(PExtended(@E[0]), Length(E), M, SD);
  CheckClose('MeanAndStdDev Extended pointer', M + SD, 2.5 + Sqrt(5 / 3));

  CheckClose('Variance Single array', Variance(S), 5 / 3);
  CheckClose('Variance Single pointer', Variance(PSingle(@S[0]), Length(S)), 5 / 3);
  CheckClose('Variance Double array', Variance(D), 5 / 3);
  CheckClose('Variance Double pointer', Variance(PDouble(@D[0]), Length(D)), 5 / 3);
  CheckClose('Variance Extended array', Variance(E), 5 / 3);
  CheckClose('Variance Extended pointer', Variance(PExtended(@E[0]), Length(E)), 5 / 3);
  CheckClose('TotalVariance Single array', TotalVariance(S), 5);
  CheckClose('TotalVariance Single pointer', TotalVariance(PSingle(@S[0]), Length(S)), 5);
  CheckClose('TotalVariance Double array', TotalVariance(D), 5);
  CheckClose('TotalVariance Double pointer', TotalVariance(PDouble(@D[0]), Length(D)), 5);
  CheckClose('TotalVariance Extended array', TotalVariance(E), 5);
  CheckClose('TotalVariance Extended pointer', TotalVariance(PExtended(@E[0]), Length(E)), 5);
  CheckClose('PopnVariance Single array', PopnVariance(S), 1.25);
  CheckClose('PopnVariance Single pointer', PopnVariance(PSingle(@S[0]), Length(S)), 1.25);
  CheckClose('PopnVariance Double array', PopnVariance(D), 1.25);
  CheckClose('PopnVariance Double pointer', PopnVariance(PDouble(@D[0]), Length(D)), 1.25);
  CheckClose('PopnVariance Extended array', PopnVariance(E), 1.25);
  CheckClose('PopnVariance Extended pointer', PopnVariance(PExtended(@E[0]), Length(E)), 1.25);
  CheckClose('PopnStdDev Single array', PopnStdDev(S), Sqrt(1.25));
  CheckClose('PopnStdDev Single pointer', PopnStdDev(PSingle(@S[0]), Length(S)), Sqrt(1.25));
  CheckClose('PopnStdDev Double array', PopnStdDev(D), Sqrt(1.25));
  CheckClose('PopnStdDev Double pointer', PopnStdDev(PDouble(@D[0]), Length(D)), Sqrt(1.25));
  CheckClose('PopnStdDev Extended array', PopnStdDev(E), Sqrt(1.25));
  CheckClose('PopnStdDev Extended pointer', PopnStdDev(PExtended(@E[0]), Length(E)), Sqrt(1.25));

  MomentSkewKurtosis(S, K1, K2, K3, K4, Skew, Kurtosis);
  CheckClose('Moment Single array mean', K1, 2.5);
  MomentSkewKurtosis(PSingle(@S[0]), Length(S), K1, K2, K3, K4, Skew, Kurtosis);
  CheckClose('Moment Single pointer mean', K1, 2.5);
  MomentSkewKurtosis(D, K1, K2, K3, K4, Skew, Kurtosis);
  CheckClose('Moment Double array mean', K1, 2.5);
  MomentSkewKurtosis(PDouble(@D[0]), Length(D), K1, K2, K3, K4, Skew, Kurtosis);
  CheckClose('Moment Double pointer mean', K1, 2.5);
  MomentSkewKurtosis(E, K1, K2, K3, K4, Skew, Kurtosis);
  CheckClose('Moment Extended array mean', K1, 2.5);
  MomentSkewKurtosis(PExtended(@E[0]), Length(E), K1, K2, K3, K4, Skew, Kurtosis);
  CheckClose('Moment Extended pointer mean', K1, 2.5);
  CheckClose('Norm Single array', Norm(S), Sqrt(30));
  CheckClose('Norm Single pointer', Norm(PSingle(@S[0]), Length(S)), Sqrt(30));
  CheckClose('Norm Double array', Norm(D), Sqrt(30));
  CheckClose('Norm Double pointer', Norm(PDouble(@D[0]), Length(D)), Sqrt(30));
  CheckClose('Norm Extended array', Norm(E), Sqrt(30));
  CheckClose('Norm Extended pointer', Norm(PExtended(@E[0]), Length(E)), Sqrt(30));
end;
{$endif MATH_API_STATISTICS}

{$ifdef MATH_API_FINANCIAL}
procedure CheckFinancialAndMisc;
var
  D: Double;
  FV, Pmt, PV, Rate: Float;
  I, N: Integer;
  I64: Int64;
  Q: QWord;
begin
  PV := 1000;
  Pmt := -100;
  Rate := 0.05;
  N := 10;
  FV := FutureValue(Rate, N, Pmt, PV, ptEndOfPeriod);
  CheckClose('PresentValue roundtrip',
    PresentValue(Rate, N, Pmt, FV, ptEndOfPeriod), PV, 1e-9);
  CheckClose('Payment roundtrip',
    Payment(Rate, N, PV, FV, ptEndOfPeriod), Pmt, 1e-9);
  CheckClose('NumberOfPeriods roundtrip',
    NumberOfPeriods(Rate, Pmt, PV, FV, ptEndOfPeriod), N, 1e-9);
  CheckClose('InterestRate roundtrip',
    InterestRate(N, Pmt, PV, FV, ptEndOfPeriod), Rate, 1e-7);
  FV := FutureValue(Rate, N, Pmt, PV, ptStartOfPeriod);
  CheckClose('Financial start-period roundtrip',
    PresentValue(Rate, N, Pmt, FV, ptStartOfPeriod), PV, 1e-9);

  I := IfThen(True, Integer(7), Integer(9));
  I64 := IfThen(False, Int64(7), Int64(9));
  D := IfThen(True, Double(7), Double(9));
  Check((I = 7) and (I64 = 9) and (D = 7), 'IfThen overloads');
  Check(CompareValue(Integer(1), Integer(2)) = LessThanValue,
    'CompareValue Integer');
  Check(CompareValue(Int64(2), Int64(2)) = EqualsValue,
    'CompareValue Int64');
  Q := High(QWord);
  Check(CompareValue(Q, QWord(1)) = GreaterThanValue, 'CompareValue QWord');
  Check(CompareValue(Single(1), Single(1.01), Single(0.02)) = EqualsValue,
    'CompareValue Single');
  Check(CompareValue(Double(1), Double(1.01), Double(0.02)) = EqualsValue,
    'CompareValue Double');
  Check(CompareValue(Extended(1), Extended(1.01), Extended(0.02)) = EqualsValue,
    'CompareValue Extended');

end;
{$endif MATH_API_FINANCIAL}

{$ifdef MATH_API_RANDOM}
procedure CheckRandomHelpers;
var
  D: Double;
  I, N: Integer;
  I64: Int64;
  RandomD: array[0..2] of Double;
  RandomI: array[0..2] of Integer;
  RandomI64: array[0..2] of Int64;
begin
  RandomD[0] := 1.5;
  RandomD[1] := 2.5;
  RandomD[2] := 3.5;
  RandomI[0] := 1;
  RandomI[1] := 2;
  RandomI[2] := 3;
  RandomI64[0] := 4;
  RandomI64[1] := 5;
  RandomI64[2] := 6;
  RandSeed := 12345;
  for I := 1 to 100 do begin
    N := RandomRange(-5, 7);
    Check((N >= -5) and (N < 7), 'RandomRange Integer');
    I64 := RandomRange(Int64(-5000000000), Int64(7000000000));
    Check((I64 >= -5000000000) and (I64 < 7000000000), 'RandomRange Int64');
    D := RandomFrom(RandomD);
    Check((D = 1.5) or (D = 2.5) or (D = 3.5), 'RandomFrom Double');
    N := RandomFrom(RandomI);
    Check((N >= 1) and (N <= 3), 'RandomFrom Integer');
    I64 := RandomFrom(RandomI64);
    Check((I64 >= 4) and (I64 <= 6), 'RandomFrom Int64');
  end;
  D := RandG(10, 0);
  Check(D = 10, 'RandG zero deviation');
end;
{$endif MATH_API_RANDOM}

{$ifdef MATH_API_FPU_MODES}
procedure CheckFpuModes;
var
  OldExceptions: TFPUExceptionMask;
  OldPrecision: TFPUPrecisionMode;
  OldRound: TFPURoundingMode;
begin
  OldRound := GetRoundMode;
  OldPrecision := GetPrecisionMode;
  OldExceptions := GetExceptionMask;
  try
    SetRoundMode(rmNearest);
    Check(GetRoundMode = rmNearest, 'round mode nearest');
    SetPrecisionMode(pmDouble);
    Check(GetPrecisionMode = pmDouble, 'precision mode double');
    SetExceptionMask(OldExceptions + [exZeroDivide]);
    Check(exZeroDivide in GetExceptionMask, 'exception mask zero divide');
    ClearExceptions(False);
  finally
    SetExceptionMask(OldExceptions);
    SetPrecisionMode(OldPrecision);
    SetRoundMode(OldRound);
  end;
end;
{$endif MATH_API_FPU_MODES}

begin
  CheckMinMaxAndRanges;
  CheckDivisionAndRounding;
  CheckAnglesAndTrig;
  CheckHyperbolic;
  CheckLogPowerAndFrexp;
  {$ifdef MATH_API_STATISTICS}
  CheckStatistics;
  {$endif MATH_API_STATISTICS}
  {$ifdef MATH_API_FINANCIAL}
  CheckFinancialAndMisc;
  {$endif MATH_API_FINANCIAL}
  {$ifdef MATH_API_RANDOM}
  CheckRandomHelpers;
  {$endif MATH_API_RANDOM}
  {$ifdef MATH_API_FPU_MODES}
  CheckFpuModes;
  {$endif MATH_API_FPU_MODES}
  WriteLn('MATH_API_SURFACE_PASS');
end.
