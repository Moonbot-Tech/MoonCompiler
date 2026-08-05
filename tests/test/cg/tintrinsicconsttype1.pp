{ %CPU=x86_64 }
{ %TARGET=linux }
program tintrinsicconsttype1;

{$mode delphi}

uses
  uintrinsicconsttype1;

const
  ConvertedExtended: Extended = CExtended(1.25);

var
  Failed: Integer;

function Kind(Value: Single): Integer; overload;
begin
  Result := 32;
end;

function Kind(Value: Double): Integer; overload;
begin
  Result := 64;
end;

function Kind(Value: Extended): Integer; overload;
begin
  Result := 80;
end;

function Kind(Value: CExtended): Integer; overload;
begin
  Result := 128;
end;

function AcceptExtended(Value: Extended): Integer; noinline;
begin
  Result := Kind(Value);
end;

procedure Check(Condition: Boolean; const Name: String);
begin
  if not Condition then
    begin
      WriteLn('FAIL ',Name);
      Inc(Failed);
    end;
end;

procedure CheckEight(const Name: String; IntKind, FracKind, ExpKind, LnKind,
  SinKind, CosKind, ArcTanKind, SqrtKind, Expected: Integer);
begin
  Check(IntKind=Expected,Name+'-int');
  Check(FracKind=Expected,Name+'-frac');
  Check(ExpKind=Expected,Name+'-exp');
  Check(LnKind=Expected,Name+'-ln');
  Check(SinKind=Expected,Name+'-sin');
  Check(CosKind=Expected,Name+'-cos');
  Check(ArcTanKind=Expected,Name+'-arctan');
  Check(SqrtKind=Expected,Name+'-sqrt');
end;

begin
  CheckEight('ordinal',Kind(Int(1)),Kind(Frac(1)),Kind(Exp(1)),Kind(Ln(1)),
    Kind(Sin(1)),Kind(Cos(1)),Kind(ArcTan(1)),Kind(Sqrt(1)),64);
  CheckEight('untyped-real',Kind(Int(1.0)),Kind(Frac(1.0)),Kind(Exp(1.0)),
    Kind(Ln(1.0)),Kind(Sin(1.0)),Kind(Cos(1.0)),Kind(ArcTan(1.0)),
    Kind(Sqrt(1.0)),64);
  CheckEight('single',Kind(Int(Single(1))),Kind(Frac(Single(1))),
    Kind(Exp(Single(1))),Kind(Ln(Single(1))),Kind(Sin(Single(1))),
    Kind(Cos(Single(1))),Kind(ArcTan(Single(1))),Kind(Sqrt(Single(1))),64);
  CheckEight('double',Kind(Int(Double(1))),Kind(Frac(Double(1))),
    Kind(Exp(Double(1))),Kind(Ln(Double(1))),Kind(Sin(Double(1))),
    Kind(Cos(Double(1))),Kind(ArcTan(Double(1))),Kind(Sqrt(Double(1))),64);
  CheckEight('extended',Kind(Int(Extended(1))),Kind(Frac(Extended(1))),
    Kind(Exp(Extended(1))),Kind(Ln(Extended(1))),Kind(Sin(Extended(1))),
    Kind(Cos(Extended(1))),Kind(ArcTan(Extended(1))),Kind(Sqrt(Extended(1))),64);
  CheckEight('cextended',Kind(Int(CExtended(1))),Kind(Frac(CExtended(1))),
    Kind(Exp(CExtended(1))),Kind(Ln(CExtended(1))),Kind(Sin(CExtended(1))),
    Kind(Cos(CExtended(1))),Kind(ArcTan(CExtended(1))),
    Kind(Sqrt(CExtended(1))),128);

  Check(Kind(Abs(1.0))=80,'control-abs-untyped');
  Check(Kind(Sqr(1.0))=80,'control-sqr-untyped');
  Check(Kind(Pi)=80,'control-pi');
  Check(Kind(Abs(CExtended(1)))=128,'control-abs-cextended');
  Check(Kind(Sqr(CExtended(1)))=128,'control-sqr-cextended');
  Check(Kind(Extended(CExtended(1)))=80,'control-explicit-conversion');
  Check(Kind(ConvertedExtended)=80,'control-typed-conversion-type');
  Check(ConvertedExtended=1.25,'control-typed-conversion-value');
  Check(AcceptExtended(CExtended(1))=80,'control-formal-conversion');

  CheckEight('cross-extended',Kind(CrossInt),Kind(CrossFrac),Kind(CrossExp),
    Kind(CrossLn),Kind(CrossSin),Kind(CrossCos),Kind(CrossArcTan),
    Kind(CrossSqrt),64);
  CheckEight('cross-cextended',Kind(CrossCInt),Kind(CrossCFrac),Kind(CrossCExp),
    Kind(CrossCLn),Kind(CrossCSin),Kind(CrossCCos),Kind(CrossCArcTan),
    Kind(CrossCSqrt),128);

  if Failed<>0 then
    Halt(1);
end.
