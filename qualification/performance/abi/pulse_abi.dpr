program pulse_abi;

{$ifndef FPC}
  {$APPTYPE CONSOLE}
{$endif}

{$ifdef FPC}
  {$mode delphi}{$H+}
{$endif}

{$Q-}{$R-}

uses
  {$if defined(FPC) and not defined(PULSE_DEFAULT_MM)}
  mormot.core.fpcx64mm,
  {$ifend}
  SysUtils,
  perf_clock in '..\common\perf_clock.pas',
  pulse_process_metrics in '..\common\pulse_process_metrics.pas',
  pulse_harness in '..\common\pulse_harness.pas',
  pulse_abi_targets in 'pulse_abi_targets.pas';

const
  InnerCount = 64;

var
  TextValue: UnicodeString;
  ArrayValue: TArray<Integer>;
  PlainCallback: TUInt64Func;
  MethodCallback: TUInt64Method;
  AbiObject: TAbiObject;
  AbiInterface: IAbiCall;

function LocalMix(Value: UInt64): UInt64;
begin
  Result := (Value xor (Value shr 29)) * UInt64($9E3779B185EBCA87);
end;

function CaseNoArgs(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 1 to InnerCount do
      Result := Result xor NoArgs;
end;

function CaseOneArg(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 1;
  for I := 1 to Iterations do
    for J := 1 to InnerCount do
      Result := OneArg(Result + UInt64(J));
end;

function CaseFourArgs(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 1;
  for I := 1 to Iterations do
    for J := 1 to InnerCount do
      Result := FourArgs(Result, UInt64(I), UInt64(J), UInt64(I + J));
end;

function CaseEightArgs(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 1;
  for I := 1 to Iterations do
    for J := 1 to InnerCount do
      Result := EightArgs(Result, UInt64(I), UInt64(J), UInt64(I + J),
        UInt64(I - J), UInt64(I * 3), UInt64(J * 5), UInt64(I xor J));
end;

function CaseMixedArgs(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 1;
  for I := 1 to Iterations do
    for J := 1 to InnerCount do
      Result := MixedArgs(Result, I * 0.25, @ArrayValue[0], J, J * 0.5,
        UInt64(I + J));
end;

function CaseRecord8Value(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Value: TRec8;
begin
  Value.A := 1;
  Result := 0;
  for I := 1 to Iterations do
    for J := 1 to InnerCount do
    begin
      Value.A := Value.A + UInt64(I + J);
      Result := Result xor Record8Value(Value);
    end;
end;

function CaseRecord16Value(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Value: TRec16;
begin
  Value.A := 1;
  Value.B := 2;
  Result := 0;
  for I := 1 to Iterations do
    for J := 1 to InnerCount do
    begin
      Value.A := Value.A + UInt64(I);
      Value.B := Value.B + UInt64(J);
      Result := Result xor Record16Value(Value);
    end;
end;

function CaseRecord24Value(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Value: TRec24;
begin
  Value.A := 1;
  Value.B := 2;
  Value.C := 3;
  Result := 0;
  for I := 1 to Iterations do
    for J := 1 to InnerCount do
    begin
      Value.C := Value.C + UInt64(I + J);
      Result := Result xor Record24Value(Value);
    end;
end;

function CaseRecord32Value(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Value: TRec32;
begin
  Value.A := 1;
  Value.B := 2;
  Value.C := 3;
  Value.D := 4;
  Result := 0;
  for I := 1 to Iterations do
    for J := 1 to InnerCount do
    begin
      Value.D := Value.D + UInt64(I + J);
      Result := Result xor Record32Value(Value);
    end;
end;

function CaseRecord32Const(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Value: TRec32;
begin
  Value.A := 1;
  Value.B := 2;
  Value.C := 3;
  Value.D := 4;
  Result := 0;
  for I := 1 to Iterations do
    for J := 1 to InnerCount do
      Result := Result xor Record32Const(Value);
end;

function CaseRecord32Var(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Value: TRec32;
begin
  Value.A := 1;
  Value.B := 2;
  Value.C := 3;
  Value.D := 4;
  for I := 1 to Iterations do
    for J := 1 to InnerCount do
      Record32Var(Value);
  Result := Value.A xor Value.B;
end;

function CaseReturnRecord8(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Value: TRec8;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 1 to InnerCount do
    begin
      Value := ReturnRecord8(Result + UInt64(I + J));
      Result := Result xor Value.A;
    end;
end;

function CaseReturnRecord16(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Value: TRec16;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 1 to InnerCount do
    begin
      Value := ReturnRecord16(Result + UInt64(I + J));
      Result := Value.A xor Value.B;
    end;
end;

function CaseReturnRecord24(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Value: TRec24;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 1 to InnerCount do
    begin
      Value := ReturnRecord24(Result + UInt64(I + J));
      Result := Value.A xor Value.B xor Value.C;
    end;
end;

function CaseReturnRecord32(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Value: TRec32;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 1 to InnerCount do
    begin
      Value := ReturnRecord32(Result + UInt64(I + J));
      Result := Value.A xor Value.B xor Value.C xor Value.D;
    end;
end;

function CaseStringValue(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 1 to InnerCount do
      Result := Result + StringValue(TextValue);
end;

function CaseStringConst(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 1 to InnerCount do
      Result := Result + StringConst(TextValue);
end;

function CaseArrayValue(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 1 to InnerCount do
      Result := Result + DynamicArrayValue(ArrayValue);
end;

function CaseArrayConst(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 1 to InnerCount do
      Result := Result + DynamicArrayConst(ArrayValue);
end;

function CaseOpenArray(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 1 to InnerCount do
      Result := Result + OpenArrayConst(ArrayValue);
end;

function CaseFunctionPointer(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 1;
  for I := 1 to Iterations do
    for J := 1 to InnerCount do
      Result := InvokeCallback(PlainCallback, Result + UInt64(J));
end;

function CaseMethodPointer(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 1;
  for I := 1 to Iterations do
    for J := 1 to InnerCount do
      Result := MethodCallback(Result + UInt64(J));
end;

function CaseVirtualMethod(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 1;
  for I := 1 to Iterations do
    for J := 1 to InnerCount do
      Result := AbiObject.Apply(Result + UInt64(J));
end;

function CaseInterfaceMethod(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 1;
  for I := 1 to Iterations do
    for J := 1 to InnerCount do
      Result := AbiInterface.Apply(Result + UInt64(J));
end;

procedure InitializeData;
var
  I: Integer;
begin
  TextValue := 'MoonCompiler ABI qualification text';
  SetLength(ArrayValue, 128);
  for I := 0 to High(ArrayValue) do
    ArrayValue[I] := I * 17 + 3;
  PlainCallback := @LocalMix;
  AbiObject := TAbiObject.Create;
  AbiInterface := AbiObject;
  MethodCallback := AbiObject.MethodApply;
end;

var
  Profile: TPulseProfile;
  SelectedCase: string;
  Found: Boolean;
begin
  InitializeData;
  try
    PulseInitialize('pulse_abi', Profile, SelectedCase);
    Found := False;
    PulseRunCase('pulse_abi', 'no-args', 'abi', 'compiler', @CaseNoArgs,
      InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_abi', 'one-arg', 'abi', 'compiler', @CaseOneArg,
      InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_abi', 'four-args', 'abi', 'compiler', @CaseFourArgs,
      InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_abi', 'eight-args', 'abi', 'compiler', @CaseEightArgs,
      InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_abi', 'mixed-args', 'abi', 'compiler', @CaseMixedArgs,
      InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_abi', 'record8-value', 'abi', 'compiler',
      @CaseRecord8Value, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_abi', 'record16-value', 'abi', 'compiler',
      @CaseRecord16Value, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_abi', 'record24-value', 'abi', 'compiler',
      @CaseRecord24Value, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_abi', 'record32-value', 'abi', 'compiler',
      @CaseRecord32Value, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_abi', 'record32-const', 'abi', 'compiler',
      @CaseRecord32Const, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_abi', 'record32-var', 'abi', 'compiler',
      @CaseRecord32Var, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_abi', 'return-record8', 'abi', 'compiler',
      @CaseReturnRecord8, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_abi', 'return-record16', 'abi', 'compiler',
      @CaseReturnRecord16, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_abi', 'return-record24', 'abi', 'compiler',
      @CaseReturnRecord24, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_abi', 'return-record32', 'abi', 'compiler',
      @CaseReturnRecord32, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_abi', 'string-value', 'abi+managed', 'compiler',
      @CaseStringValue, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_abi', 'string-const', 'abi+managed', 'compiler',
      @CaseStringConst, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_abi', 'dynamic-array-value', 'abi+managed', 'compiler',
      @CaseArrayValue, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_abi', 'dynamic-array-const', 'abi+managed', 'compiler',
      @CaseArrayConst, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_abi', 'open-array-const', 'abi', 'compiler',
      @CaseOpenArray, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_abi', 'function-pointer', 'abi', 'compiler',
      @CaseFunctionPointer, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_abi', 'method-pointer', 'abi', 'compiler',
      @CaseMethodPointer, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_abi', 'virtual-method', 'abi', 'compiler',
      @CaseVirtualMethod, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_abi', 'interface-method', 'abi+managed', 'compiler',
      @CaseInterfaceMethod, InnerCount, Profile, SelectedCase, Found);
    PulseFinish('pulse_abi', SelectedCase, Found);
  finally
    AbiInterface := nil;
    AbiObject := nil;
  end;
end.
