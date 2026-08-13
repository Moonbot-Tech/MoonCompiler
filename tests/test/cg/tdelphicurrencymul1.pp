{ %TARGET=win64 }
{ %OPT=-O2 }
program tdelphicurrencymul1;

{$ifdef FPC}
  {$mode delphi}
{$endif}

uses
{$ifdef FPC}
  SysUtils;
{$else}
  System.SysUtils;
{$endif}

procedure CheckMul(A, B: Currency; ExpectedRaw: Int64; ErrorCode: Byte);
{$ifdef FPC} noinline; {$endif}
var
  Actual: Currency;
begin
  Actual := A * B;
{$ifdef WIN64}
  if PInt64(@Actual)^ <> ExpectedRaw then
    begin
      WriteLn('FAIL raw=', PInt64(@Actual)^, ' expected=', ExpectedRaw);
      Halt(ErrorCode);
    end;
{$endif}
end;

procedure CheckOverflow;
{$ifdef FPC} noinline; {$endif}
var
  A, B, Actual: Currency;
begin
  A := 123456789.1234;
  B := 7654321.4321;
  try
    Actual := A * B;
    WriteLn('FAIL overflow result=', Actual:0:4);
    Halt(20);
  except
    on E: EIntOverflow do
      ;
  end;
end;

begin
  { Issue 39480 values: the result fits Currency, but the scaled 64-bit
    intermediate does not.  Delphi 12.2 Win64 supplies the exact oracles. }
  CheckMul(-542226.5406, 1387845832.7798, -7525268447943170356, 1);
  CheckMul(-539324.3317, -593647440.2441, 3201685089750649174, 2);

  { Nearest/ties-to-even on the raw 1/10000 scale, including signs. }
  CheckMul(0.0001, 0.5000, 0, 3);
  CheckMul(0.0003, 0.5000, 2, 4);
  CheckMul(-0.0001, 0.5000, 0, 5);
  CheckMul(-0.0003, 0.5000, -2, 6);
  CheckMul(0.0001, 0.5001, 1, 7);

  { Existing exact fast path remains an adjacent control. }
  CheckMul(123.4567, 2.0000, 2469134, 8);
{$ifdef WIN64}
  CheckOverflow;
{$endif}
end.
