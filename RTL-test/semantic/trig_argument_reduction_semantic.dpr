program trig_argument_reduction_semantic;

{$ifdef FPC}
  {$mode delphi}{$H+}{$codepage utf8}
{$endif}

uses
  {$ifdef FPC}
  mormot.core.fpcx64mm,
  SysUtils,
  Math;
  {$else}
  System.SysUtils,
  System.Math;
  {$endif}

type
  TTrigOracle = record
    X: Double;
    SinX: Double;
    CosX: Double;
    Tolerance: Double;
  end;

const
  Oracles: array[0..21] of TTrigOracle = (
    (X: 0.78539816339744817; SinX: 0.70710678118654746;
      CosX: 0.70710678118654768; Tolerance: 2E-15),
    (X: 0.78539816339744828; SinX: 0.70710678118654757;
      CosX: 0.70710678118654757; Tolerance: 2E-15),
    (X: 0.78539816339744839; SinX: 0.70710678118654757;
      CosX: 0.70710678118654746; Tolerance: 2E-15),
    (X: -0.78539816339744839; SinX: -0.70710678118654757;
      CosX: 0.70710678118654746; Tolerance: 2E-15),
    (X: 1.5707963267948966; SinX: 1.0;
      CosX: 6.123233995736766E-17; Tolerance: 2E-15),
    (X: -1.5707963267948966; SinX: -1.0;
      CosX: 6.123233995736766E-17; Tolerance: 2E-15),
    (X: 3.1415926535897931; SinX: 1.2246467991473532E-16;
      CosX: -1.0; Tolerance: 2E-15),
    (X: 10.0; SinX: -0.54402111088936977;
      CosX: -0.83907152907645244; Tolerance: 2E-15),
    (X: 123.456; SinX: -0.80393736857282394;
      CosX: -0.5947139710921574; Tolerance: 3E-14),
    (X: 12345.678900000001; SinX: -0.70344192126325633;
      CosX: 0.71075274421521484; Tolerance: 3E-13),
    (X: 1048576.25; SinX: 0.5537208420860511;
      CosX: 0.83270236521791774; Tolerance: 3E-11),
    (X: 4194303.75; SinX: 0.88998127778514691;
      CosX: 0.45599706708696847; Tolerance: 1E-10),
    (X: 1000000000.125; SinX: 0.6460479581588543;
      CosX: 0.76329682022053202; Tolerance: 3E-8),
    (X: -1000000000.125; SinX: -0.6460479581588543;
      CosX: 0.76329682022053202; Tolerance: 3E-8),
    (X: 999999999.0; SinX: -0.41013727728004373;
      CosX: 0.91202380110680914; Tolerance: 3E-8),
    (X: 123456789.125; SinX: 0.99987638542726287;
      CosX: 0.015723036122574079; Tolerance: 5E-9),
    (X: 1073741823.75; SinX: -0.79276968877759602;
      CosX: 0.60952130443116881; Tolerance: 5E-8),
    (X: 1073741824.0; SinX: -0.61732641504604213;
      CosX: 0.78670712294118816; Tolerance: 5E-8),
    (X: 1073741824.25; SinX: -0.40350077479882668;
      CosX: 0.91497930290075224; Tolerance: 5E-8),
    (X: -1073741823.75; SinX: 0.79276968877759602;
      CosX: 0.60952130443116881; Tolerance: 5E-8),
    (X: -1073741824.0; SinX: 0.61732641504604213;
      CosX: 0.78670712294118816; Tolerance: 5E-8),
    (X: -1073741824.25; SinX: 0.40350077479882668;
      CosX: 0.91497930290075224; Tolerance: 5E-8)
  );

procedure CheckClose(const AName: string; AActual, AExpected,
  ATolerance: Double);
begin
  If Abs(AActual - AExpected) > ATolerance then
    raise Exception.CreateFmt('%s: expected %.17g, got %.17g, delta %.17g',
      [AName, AExpected, AActual, Abs(AActual - AExpected)]);
end;

var
  I: Integer;
  SinValue, CosValue: Double;
begin
  try
    for I := Low(Oracles) to High(Oracles) do begin
      SinValue := Sin(Oracles[I].X);
      CosValue := Cos(Oracles[I].X);
      CheckClose('Sin[' + IntToStr(I) + ']', SinValue, Oracles[I].SinX,
        Oracles[I].Tolerance);
      CheckClose('Cos[' + IntToStr(I) + ']', CosValue, Oracles[I].CosX,
        Oracles[I].Tolerance);
      CheckClose('identity[' + IntToStr(I) + ']',
        SinValue * SinValue + CosValue * CosValue, 1.0, 2E-14);
    end;
    WriteLn('TRIG_ARGUMENT_REDUCTION_PASS');
  except
    on E: Exception do begin
      WriteLn(ErrOutput, E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
