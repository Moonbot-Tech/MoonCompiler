{ %OPT=-O3 }
program tdelphiinlineexceptreg1;

{$ifdef FPC}
  {$mode delphi}
{$endif}

uses
{$ifdef FPC}
  SysUtils;
{$else}
  System.SysUtils;
{$endif}

var
  FinallyValue: UInt64;
  CallerFinallyRuns, InnerFinallyRuns: Integer;

function Mix(Value: UInt64): UInt64; inline;
begin
  Result := (Value xor (Value shr 27)) * UInt64($3C79AC492BA7B653);
end;

function RaiseAfter(Value: UInt64): UInt64; inline;
begin
  If Value <> 0 then
    raise Exception.Create('expected');
  Result := Value;
end;

function OwnExcept(Value: UInt64): UInt64; inline;
begin
  try
    RaiseAfter(Value);
    Result := 0;
  except
    Result := Value;
  end;
end;

function OwnFinally(Value: UInt64): UInt64; inline;
begin
  try
    Result := Value + 1;
  finally
    FinallyValue := Value;
  end;
end;

function LocalExit(Value: Integer): Integer; inline;
begin
  If Value = 0 then
    Exit(37);
  Result := Value + 1;
end;

function LocalExitWithOwnFinally(Value: Integer): Integer; inline;
begin
  try
    If Value = 0 then
      Exit(41);
    Result := Value + 2;
  finally
    Inc(InnerFinallyRuns);
  end;
end;

function CallerFinallyAroundLocalExit(Value: Integer): Integer;
begin
  try
    Result := LocalExit(Value) + 5;
  finally
    Inc(CallerFinallyRuns);
  end;
end;

function CallerFinallyAroundNestedExit(Value: Integer): Integer;
begin
  try
    Result := LocalExitWithOwnFinally(Value) + 5;
  finally
    Inc(CallerFinallyRuns);
  end;
end;

function PureInCallerExcept(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 1;
  for I := 1 to Iterations do
    for J := 1 to 256 do
      try
        Result := Mix(Result + UInt64(J));
      except
        Result := 0;
      end;
end;

function ThrowToCaller(Value: UInt64): UInt64;
begin
  try
    Result := Mix(Value + RaiseAfter(Value));
  except
    Result := Value;
  end;
end;

{$Q+}
function CheckedOverflowCaught(Value: Integer): Integer;
begin
  try
    Result := Value + 1;
  except
    on EIntOverflow do
      Result := 71;
  end;
end;
{$Q-}

function DivideByZeroCaught(Value: Integer): Integer;
begin
  try
    Result := 100 div Value;
  except
    on EDivByZero do
      Result := 73;
  end;
end;

function RaiseIndex: Integer; inline;
begin
  raise Exception.Create('expected index failure');
end;

function IndexedIncrementCaught: Integer;
var
  Items: array[0..3] of Integer;
begin
  Items[0] := 1;
  try
    Inc(Items[RaiseIndex]);
    Result := 0;
  except
    Result := 83;
  end;
end;

function ReadVar(var Value: Integer): Integer; inline;
begin
  Result := Value + 1;
end;

function NilVarCaught: Integer;
begin
  try
    Result := ReadVar(PInteger(nil)^);
  except
    on EAccessViolation do
      Result := 89;
  end;
end;

{$R+}
function RangeCheckCaught(Value: Integer): Integer;
var
  Items: array[0..3] of Integer;
begin
  Items[0] := 1;
  try
    Result := Items[Value];
  except
    on ERangeError do
      Result := 79;
  end;
end;
{$R-}

begin
  If PureInCallerExcept(2) <> UInt64($69F5269C5D3D72FF) then
    Halt(1);
  { The inlined callee has its own handler and reads Value after the raise.
    Its parameter must remain unwind-visible even though it is ordinal. }
  If OwnExcept(Mix(0) + 42) <> 42 then
    Halt(2);
  FinallyValue := 0;
  If OwnFinally(17) <> 18 then
    Halt(3);
  If FinallyValue <> 17 then
    Halt(4);
  If ThrowToCaller(23) <> 23 then
    Halt(5);
  If CheckedOverflowCaught(High(Integer)) <> 71 then
    Halt(6);
  If DivideByZeroCaught(0) <> 73 then
    Halt(7);
  If RangeCheckCaught(256) <> 79 then
    Halt(8);
  If IndexedIncrementCaught <> 83 then
    Halt(9);
  If NilVarCaught <> 89 then
    Halt(10);
  CallerFinallyRuns := 0;
  If CallerFinallyAroundLocalExit(0) <> 42 then
    Halt(11);
  If CallerFinallyRuns <> 1 then
    Halt(12);
  CallerFinallyRuns := 0;
  InnerFinallyRuns := 0;
  If CallerFinallyAroundNestedExit(0) <> 46 then
    Halt(13);
  If InnerFinallyRuns <> 1 then
    Halt(14);
  If CallerFinallyRuns <> 1 then
    Halt(15);
end.
