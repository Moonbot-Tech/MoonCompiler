program fpu_default_mask_semantic;

{$APPTYPE CONSOLE}

{$ifdef FPC}
  {$mode delphi}
{$endif}

uses
  {$ifdef FPC}
  mormot.core.fpcx64mm,
  {$ifdef UNIX}cthreads,cwstring,{$endif UNIX}
  {$endif FPC}
  SysUtils, Classes, Math;

const
  AllExceptions = [exInvalidOp, exDenormalized, exZeroDivide, exOverflow,
    exUnderflow, exPrecision];

type
  TMaskType = {$ifdef FPC}TFPUExceptionMask{$else}TArithmeticExceptionMask{$endif};

  TMaskThread = class(TThread)
  public
    Mask: TMaskType;
    procedure Execute; override;
  end;

procedure TMaskThread.Execute;
begin
  Mask := GetExceptionMask;
end;

procedure Fail(const Msg: string);
begin
  WriteLn('FAIL ', Msg);
  Halt(1);
end;

function DivideValues(A, B: Double): Double; {$ifdef FPC}noinline;{$endif}
begin
  Result := A / B;
end;

function MultiplyValues(A, B: Double): Double; {$ifdef FPC}noinline;{$endif}
begin
  Result := A * B;
end;

function TruncateValue(A: Double): Int64; {$ifdef FPC}noinline;{$endif}
begin
  Result := Trunc(A);
end;

var
  D, N: Double;
  T: TMaskThread;
begin
  If GetExceptionMask <> AllExceptions then
    Fail('main thread default exception mask');
  {$ifdef FPC}
  {$if defined(CPUX86_64) or defined(CPUI386)}
  If (Get8087CW and $3F) <> $3F then
    Fail('x87 default exception mask');
  If ((GetMXCSR shr 7) and $3F) <> $3F then
    Fail('SSE default exception mask');
  SysResetFPU;
  If GetExceptionMask <> AllExceptions then
    Fail('SysResetFPU process default exception mask');
  {$endif}
  {$endif FPC}

  D := DivideValues(1.0, 0.0);
  If not IsInfinite(D) or (D < 0) then
    Fail('positive infinity');
  N := DivideValues(0.0, 0.0);
  If not IsNan(N) then
    Fail('NaN result');
  If N > 1.0 then
    Fail('NaN comparison');
  D := MultiplyValues(1.0e308, 10.0);
  If not IsInfinite(D) then
    Fail('overflow infinity');
  If TruncateValue(1.0e30) <> Low(Int64) then
    Fail('masked invalid integer conversion');

  T := TMaskThread.Create(True);
  try
    T.Start;
    T.WaitFor;
    If T.Mask <> AllExceptions then
      Fail('worker thread default exception mask');
  finally
    T.Free;
  end;

  WriteLn('FPU_DEFAULT_MASK_OK');
end.
