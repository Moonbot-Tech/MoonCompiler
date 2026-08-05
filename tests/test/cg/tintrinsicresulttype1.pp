{ %CPU=x86_64 }
{ %TARGET=linux }
program tintrinsicresulttype1;

{$mode delphi}

uses
  Math,
  uintrinsicresulttype1;

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

procedure Check(Condition: Boolean; const Name: String);
begin
  if not Condition then
    begin
      WriteLn('FAIL ',Name);
      Inc(Failed);
    end;
end;

function RuntimeDouble(Value: Double): Double; noinline;
begin
  Result := Value;
end;

procedure CheckRuntimeKinds;
var
  S: Single;
  D: Double;
  E: Extended;
  C: CExtended;
begin
  S := RuntimeDouble(1.25);
  Check(Kind(Int(S))=64,'runtime-int-single');
  Check(Kind(Frac(S))=64,'runtime-frac-single');
  Check(Kind(Exp(S))=64,'runtime-exp-single');
  Check(Kind(Ln(S))=64,'runtime-ln-single');
  Check(Kind(Sin(S))=64,'runtime-sin-single');
  Check(Kind(Cos(S))=64,'runtime-cos-single');
  Check(Kind(ArcTan(S))=64,'runtime-arctan-single');
  Check(Kind(Sqrt(S))=64,'runtime-sqrt-single');

  D := RuntimeDouble(1.25);
  Check(Kind(Int(D))=64,'runtime-int-double');
  Check(Kind(Frac(D))=64,'runtime-frac-double');
  Check(Kind(Exp(D))=64,'runtime-exp-double');
  Check(Kind(Ln(D))=64,'runtime-ln-double');
  Check(Kind(Sin(D))=64,'runtime-sin-double');
  Check(Kind(Cos(D))=64,'runtime-cos-double');
  Check(Kind(ArcTan(D))=64,'runtime-arctan-double');
  Check(Kind(Sqrt(D))=64,'runtime-sqrt-double');

  E := RuntimeDouble(1.25);
  Check(Kind(Int(E))=64,'runtime-int-extended');
  Check(Kind(Frac(E))=64,'runtime-frac-extended');
  Check(Kind(Exp(E))=64,'runtime-exp-extended');
  Check(Kind(Ln(E))=64,'runtime-ln-extended');
  Check(Kind(Sin(E))=64,'runtime-sin-extended');
  Check(Kind(Cos(E))=64,'runtime-cos-extended');
  Check(Kind(ArcTan(E))=64,'runtime-arctan-extended');
  Check(Kind(Sqrt(E))=64,'runtime-sqrt-extended');
  Check(Kind(Abs(E))=80,'control-abs-extended');
  Check(Kind(Sqr(E))=80,'control-sqr-extended');

  C := RuntimeDouble(1.25);
  Check(Kind(Int(C))=128,'runtime-int-cextended');
  Check(Kind(Frac(C))=128,'runtime-frac-cextended');
  Check(Kind(Exp(C))=128,'runtime-exp-cextended');
  Check(Kind(Ln(C))=128,'runtime-ln-cextended');
  Check(Kind(Sin(C))=128,'runtime-sin-cextended');
  Check(Kind(Cos(C))=128,'runtime-cos-cextended');
  Check(Kind(ArcTan(C))=128,'runtime-arctan-cextended');
  Check(Kind(Sqrt(C))=128,'runtime-sqrt-cextended');
  Check(Kind(Abs(C))=128,'control-abs-cextended');
  Check(Kind(Sqr(C))=128,'control-sqr-cextended');

  Check(CrossUnitKinds(E)=8*64,'cross-unit-kinds');
end;

procedure CheckWidths;
var
  A, B, C: Double;
begin
  A := RuntimeDouble(1e200);
  B := RuntimeDouble(1e200);
  C := RuntimeDouble(1e-200);
  Check(IsInfinite(Int(A)*B*C),'width-int');
  Check(IsInfinite((Frac(A)+A)*B*C),'width-frac');
  Check(IsInfinite((Ln(A)+A)*B*C),'width-ln');
  Check(IsInfinite((Sin(A)+A)*B*C),'width-sin');
  Check(IsInfinite((Cos(A)+A)*B*C),'width-cos');
  Check(IsInfinite((ArcTan(A)+A)*B*C),'width-arctan');
  Check(IsInfinite((Sqrt(A)+A)*B*C),'width-sqrt');
  Check(CrossUnitWidth(A,B,C),'cross-unit-width');

  A := RuntimeDouble(716.0);
  Check(IsInfinite(Exp(A)*C),'width-exp');
end;

procedure ExcessOn;
{$EXCESSPRECISION ON}
begin
  CheckWidths;
end;

procedure ExcessOff;
{$EXCESSPRECISION OFF}
begin
  CheckWidths;
end;

begin
  SetExceptionMask([exInvalidOp,exDenormalized,exZeroDivide,exOverflow,
    exUnderflow,exPrecision]);
  CheckRuntimeKinds;
  ExcessOn;
  ExcessOff;
  if Failed<>0 then
    Halt(1);
end.
