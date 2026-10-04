program math_extreme_contracts_semantic;

{$mode delphiunicode}

uses
  SysUtils,
  Math;

procedure Check(Condition: Boolean; const Name: UnicodeString);
begin
  If not Condition then begin
    WriteLn('FAIL ', Name);
    Halt(1);
  end;
end;

procedure CheckRelative(const Name: UnicodeString; Actual, Expected, Tolerance: Extended);
var
  Scale: Extended;
begin
  Check(not IsNan(Actual) and not IsInfinite(Actual), Name + ' finite');
  Scale := Abs(Expected);
  If Scale < 1 then
    Scale := 1;
  Check(Abs(Actual - Expected) <= Tolerance * Scale, Name + ' value');
end;

procedure CheckArcCscHSingle;
var
  Boundary: Single;
  Expected: Extended;
begin
  Boundary := Single(1.0 / MaxSingle);
  Expected := Ln(2.0) - Ln(Extended(Boundary));
  CheckRelative('ArcCscH Single boundary', ArcCscH(Boundary), Expected, 2e-6);
  CheckRelative('ArcCscH Single negative boundary', ArcCscH(-Boundary), -Expected, 2e-6);
  CheckRelative('ArcCscH Single below boundary', ArcCscH(Boundary / 2),
    Ln(2.0) - Ln(Extended(Boundary / 2)), 2e-6);
  CheckRelative('ArcCscH Single above boundary', ArcCscH(Boundary * 2),
    ArcSinh(1.0 / Extended(Boundary * 2)), 2e-6);
end;

procedure CheckArcCscHDouble;
var
  Boundary: Double;
  Expected: Extended;
begin
  Boundary := Double(1.0 / MaxDouble);
  Expected := Ln(2.0) - Ln(Extended(Boundary));
  CheckRelative('ArcCscH Double boundary', ArcCscH(Boundary), Expected, 2e-15);
  CheckRelative('ArcCscH Double negative boundary', ArcCscH(-Boundary), -Expected, 2e-15);
  CheckRelative('ArcCscH Double below boundary', ArcCscH(Boundary / 2),
    Ln(2.0) - Ln(Extended(Boundary / 2)), 2e-15);
  CheckRelative('ArcCscH Double above boundary', ArcCscH(Boundary * 2),
    ArcSinh(1.0 / Extended(Boundary * 2)), 2e-15);
end;

{$ifdef FPC_HAS_TYPE_EXTENDED}
procedure CheckArcCscHExtended;
var
  Boundary: Extended;
  Expected: Extended;
begin
  Boundary := Extended(1.0 / MaxExtended);
  Expected := Ln(2.0) - Ln(Boundary);
  CheckRelative('ArcCscH Extended boundary', ArcCscH(Boundary), Expected, 2e-15);
  CheckRelative('ArcCscH Extended negative boundary', ArcCscH(-Boundary), -Expected, 2e-15);
  CheckRelative('ArcCscH Extended below boundary', ArcCscH(Boundary / 2),
    Ln(2.0) - Ln(Boundary / 2), 2e-15);
  CheckRelative('ArcCscH Extended above boundary', ArcCscH(Boundary * 2),
    ArcSinh(1.0 / (Boundary * 2)), 2e-15);
end;
{$endif FPC_HAS_TYPE_EXTENDED}

procedure CheckArcCscHUnmasked;
var
  Boundary: Double;
  Expected, Actual: Double;
  SavedMask: TFPUExceptionMask;
begin
  Boundary := Double(1.0 / MaxDouble);
  Expected := Ln(2.0) - Ln(Boundary);
  SavedMask := GetExceptionMask;
  try
    ClearExceptions;
    SetExceptionMask(SavedMask - [exOverflow]);
    Actual := ArcCscH(Boundary);
  finally
    ClearExceptions;
    SetExceptionMask(SavedMask);
  end;
  CheckRelative('ArcCscH unmasked exact boundary', Actual, Expected, 2e-15);
end;

procedure CheckIntPowerUnmasked;
var
  SavedMask: TFPUExceptionMask;
begin
  SavedMask := GetExceptionMask;
  try
    ClearExceptions;
    SetExceptionMask(SavedMask - [exOverflow]);
    CheckRelative('IntPower exponent one', IntPower(1e200, 1), 1e200, 2e-15);
    CheckRelative('IntPower exponent two', IntPower(1e150, 2), 1e300, 2e-15);
    CheckRelative('IntPower negative exponent', IntPower(1e-200, -1), 1e200, 2e-15);
  finally
    ClearExceptions;
    SetExceptionMask(SavedMask);
  end;
  Check(IntPower(2.0, 0) = 1.0, 'IntPower exponent zero');
  Check(IntPower(1.0, Low(LongInt)) = 1.0, 'IntPower Low(LongInt) one');
  Check(IntPower(-1.0, Low(LongInt)) = 1.0, 'IntPower Low(LongInt) negative one');
  Check(IntPower(2.0, Low(LongInt)) = 0.0, 'IntPower Low(LongInt) underflow');
end;

function ReferenceIntPower(Base: Extended; Exponent: Integer): Extended;
var
  I, Magnitude: Integer;
begin
  Result:=1.0;
  Magnitude:=Abs(Exponent);
  for I:=1 to Magnitude do
    Result:=Result*Base;
  if Exponent<0 then
    Result:=1.0/Result;
end;

procedure CheckIntPowerMatrix;
const
  Bases: array[0..3] of Extended = (-2.0,-0.5,0.5,2.0);
var
  BaseIndex, Exponent: Integer;
  Name: UnicodeString;
begin
  for BaseIndex:=Low(Bases) to High(Bases) do
    for Exponent:=-16 to 16 do
      begin
      Name:='IntPower matrix '+IntToStr(BaseIndex)+'/'+IntToStr(Exponent);
      Check(IntPower(Bases[BaseIndex],Exponent)=
        ReferenceIntPower(Bases[BaseIndex],Exponent),Name);
      end;
  for Exponent:=1 to 32 do
    Check(IntPower(0.0,Exponent)=0.0,'IntPower zero '+IntToStr(Exponent));
end;

begin
  CheckArcCscHSingle;
  CheckArcCscHDouble;
  {$ifdef FPC_HAS_TYPE_EXTENDED}
  CheckArcCscHExtended;
  {$endif FPC_HAS_TYPE_EXTENDED}
  CheckArcCscHUnmasked;
  CheckIntPowerUnmasked;
  CheckIntPowerMatrix;
  WriteLn('MATH_EXTREME_CONTRACTS_PASS');
end.
