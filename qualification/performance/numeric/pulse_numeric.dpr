program pulse_numeric;

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
  Math,
  perf_clock in '..\common\perf_clock.pas',
  pulse_process_metrics in '..\common\pulse_process_metrics.pas',
  pulse_harness in '..\common\pulse_harness.pas';

const
  InnerCount = 128;

type
  TSmallEnum = (se0, se1, se2, se3, se4, se5, se6, se7,
    se8, se9, se10, se11, se12, se13, se14, se15);
  TSmallSet = set of TSmallEnum;
  TWideSet = set of Byte;

var
  Signed32Data: array[0..255] of Int32;
  Signed64Data: array[0..255] of Int64;
  Unsigned64Data: array[0..255] of UInt64;
  DoubleData: array[0..255] of Double;
  SingleData: array[0..255] of Single;
  RuntimeDivisor32: UInt32;
  RuntimeDivisor64: UInt64;
  RuntimeShift: Integer;

function Rol32(Value: UInt32; Count: Integer): UInt32; inline;
begin
  Result := (Value shl Count) or (Value shr (32 - Count));
end;

function Rol64(Value: UInt64; Count: Integer): UInt64; inline;
begin
  Result := (Value shl Count) or (Value shr (64 - Count));
end;

function CaseInt32AddMul(Iterations: Integer): UInt64;
var
  I, J: Integer;
  A, B: Int32;
begin
  A := 17;
  B := -31;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      A := A * 33 + B + Signed32Data[(I + J) and 255];
      B := B * 17 - A + J;
    end;
  Result := UInt32(A) or (UInt64(UInt32(B)) shl 32);
end;

function CaseInt64AddMul(Iterations: Integer): UInt64;
var
  I, J: Integer;
  A, B: Int64;
begin
  A := 17;
  B := -31;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      A := A * 6364136223846793005 + B + Signed64Data[(I + J) and 255];
      B := B * 2862933555777941757 - A + J;
    end;
  Result := UInt64(A) xor Rol64(UInt64(B), 23);
end;

function CaseUInt32DivConst(Iterations: Integer): UInt64;
var
  I, J: Integer;
  X, Sum: UInt32;
begin
  Sum := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      X := UInt32(Signed32Data[(I + J) and 255]);
      Sum := Sum + X div 10 + X mod 1009;
    end;
  Result := Sum;
end;

function CaseInt32DivRuntime(Iterations: Integer): UInt64;
var
  I, J, Divisor: Integer;
  X, Sum: Int32;
begin
  Sum := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      X := Signed32Data[(I + J) and 255];
      Divisor := Integer(RuntimeDivisor32) + (J and 7);
      Sum := Sum + X div Divisor + X mod Divisor;
    end;
  Result := UInt32(Sum);
end;

function CaseUInt64DivConst(Iterations: Integer): UInt64;
var
  I, J: Integer;
  X, Sum: UInt64;
begin
  Sum := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      X := Unsigned64Data[(I + J) and 255];
      Sum := Sum + X div UInt64(10) + X mod UInt64(65537);
    end;
  Result := Sum;
end;

function CaseInt64DivRuntime(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Divisor, X, Sum: Int64;
begin
  Sum := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      X := Signed64Data[(I + J) and 255];
      Divisor := Int64(RuntimeDivisor64 + UInt64(J and 15));
      Sum := Sum + X div Divisor + X mod Divisor;
    end;
  Result := UInt64(Sum);
end;

function CaseShiftConstant(Iterations: Integer): UInt64;
var
  I, J: Integer;
  X: UInt64;
begin
  X := $0123456789ABCDEF;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      X := (X shl 7) xor (X shr 11) xor (X shl 29);
  Result := X;
end;

function CaseShiftVariable(Iterations: Integer): UInt64;
var
  I, J, Count: Integer;
  X: UInt64;
begin
  X := $0123456789ABCDEF;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      Count := ((J + RuntimeShift) and 31) + 1;
      X := (X shl Count) xor (X shr (64 - Count));
    end;
  Result := X;
end;

function CaseRotateMix(Iterations: Integer): UInt64;
var
  I, J: Integer;
  A, B: UInt64;
begin
  A := $243F6A8885A308D3;
  B := $13198A2E03707344;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      A := Rol64(A + B, 13) xor UInt64(J);
      B := Rol64(B xor A, 37) + $9E3779B185EBCA87;
    end;
  Result := A xor B;
end;

function CaseBitBoolean(Iterations: Integer): UInt64;
var
  I, J: Integer;
  A, B, C: UInt32;
begin
  A := $A5A5A5A5;
  B := $3C6EF372;
  C := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      C := C + ((A and B) xor ((not A) and Rol32(B, 7)));
      A := Rol32(A xor C, 5);
      B := Rol32(B + A, 11);
    end;
  Result := UInt64(A) or (UInt64(B) shl 32) xor C;
end;

function CaseDoubleArithmetic(Iterations: Integer): UInt64;
var
  I, J: Integer;
  A, B: Double;
begin
  A := 1.0000001;
  B := 0.9999997;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      A := A * 0.9999991 + DoubleData[(I + J) and 255];
      B := B * 0.9999989 + A * 0.0000001;
    end;
  Result := UInt64(Trunc(A * 1000000.0)) xor
    Rol64(UInt64(Trunc(B * 1000000.0)), 17);
end;

function CaseSingleArithmetic(Iterations: Integer): UInt64;
var
  I, J: Integer;
  A, B: Single;
begin
  A := 1.0001;
  B := 0.9997;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      A := A * 0.99991 + SingleData[(I + J) and 255];
      B := B * 0.99989 + A * 0.00001;
    end;
  Result := UInt64(Trunc(A * 1000.0)) xor
    Rol64(UInt64(Trunc(B * 1000.0)), 17);
end;

function CaseIntDoubleConvert(Iterations: Integer): UInt64;
var
  I, J: Integer;
  X: Int64;
  D: Double;
begin
  X := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      D := Signed32Data[(I + J) and 255] * 0.125 + J;
      X := X + Trunc(D) + Round(D * 0.25);
    end;
  Result := UInt64(X);
end;

function CaseSingleDoubleConvert(Iterations: Integer): UInt64;
var
  I, J: Integer;
  S: Single;
  D: Double;
  Sum: Int64;
begin
  Sum := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      S := SingleData[(I + J) and 255];
      D := S;
      S := D * 1.0001;
      Sum := Sum + Trunc(S * 1000.0);
    end;
  Result := UInt64(Sum);
end;

function CaseMinMaxMixed(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Value, Minimum, Maximum: Int64;
begin
  Minimum := High(Int64);
  Maximum := Low(Int64);
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      Value := Signed64Data[(I * 13 + J) and 255];
      If Value < Minimum then
        Minimum := Value;
      If Value > Maximum then
        Maximum := Value;
    end;
  Result := UInt64(Minimum) xor Rol64(UInt64(Maximum), 19);
end;

function CaseSmallSetOps(Iterations: Integer): UInt64;
var
  I, J: Integer;
  A, B, C: TSmallSet;
  E: TSmallEnum;
begin
  A := [se0, se2, se4, se6, se8, se10, se12, se14];
  B := [se1, se2, se5, se6, se9, se10, se13, se14];
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      C := (A + B) - [TSmallEnum(J and 15)];
      for E := Low(TSmallEnum) to High(TSmallEnum) do
        If E in C then
          Inc(Result, Ord(E) + 1);
      A := B;
      B := C;
    end;
end;

function CaseWideSetOps(Iterations: Integer): UInt64;
var
  I, J, K: Integer;
  A, B, C: TWideSet;
begin
  A := [];
  B := [];
  for K := 0 to 255 do
    If (K and 3) = 0 then
      Include(A, Byte(K))
    else If (K and 3) = 1 then
      Include(B, Byte(K));
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      C := (A + B) - [Byte((I + J) and 255)];
      If Byte((J * 17) and 255) in C then
        Inc(Result);
      A := B;
      B := C;
    end;
end;

{$R+}
function CaseRangeCheckedIndex(Iterations: Integer): UInt64;
var
  I, J, Index: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      Index := (I + J) and 255;
      Result := Result + UInt32(Signed32Data[Index]);
    end;
end;
{$R-}

function CaseUncheckedIndex(Iterations: Integer): UInt64;
var
  I, J, Index: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      Index := (I + J) and 255;
      Result := Result + UInt32(Signed32Data[Index]);
    end;
end;

{$Q+}
function CaseOverflowChecked(Iterations: Integer): UInt64;
var
  I, J: Integer;
  X: Int64;
begin
  X := 1;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      X := (X + J + I) and $3FFFFFFFFFFFFFFF;
  Result := UInt64(X);
end;
{$Q-}

function CaseOverflowUnchecked(Iterations: Integer): UInt64;
var
  I, J: Integer;
  X: Int64;
begin
  X := 1;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      X := (X + J + I) and $3FFFFFFFFFFFFFFF;
  Result := UInt64(X);
end;

procedure InitializeData;
var
  I: Integer;
begin
  for I := 0 to 255 do
  begin
    Signed32Data[I] := Int32(UInt32(I * 747796405 + 2891336453));
    Signed64Data[I] := Int64(UInt64(I + 1) * UInt64(6364136223846793005) +
      UInt64(1442695040888963407));
    Unsigned64Data[I] := UInt64(Signed64Data[I]) xor $A5A5A5A5A5A5A5A5;
    DoubleData[I] := (I - 127) * 0.00003125;
    SingleData[I] := (I - 127) * 0.00003125;
  end;
  RuntimeDivisor32 := 7;
  RuntimeDivisor64 := 17;
  RuntimeShift := 3;
end;

var
  Profile: TPulseProfile;
  SelectedCase: string;
  Found: Boolean;
begin
  InitializeData;
  PulseInitialize('pulse_numeric', Profile, SelectedCase);
  Found := False;
  PulseRunCase('pulse_numeric', 'int32-add-mul', 'codegen', 'compiler',
    @CaseInt32AddMul, InnerCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_numeric', 'int64-add-mul', 'codegen', 'compiler',
    @CaseInt64AddMul, InnerCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_numeric', 'uint32-div-constant', 'codegen', 'compiler',
    @CaseUInt32DivConst, InnerCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_numeric', 'int32-div-runtime', 'codegen', 'compiler',
    @CaseInt32DivRuntime, InnerCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_numeric', 'uint64-div-constant', 'codegen', 'compiler',
    @CaseUInt64DivConst, InnerCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_numeric', 'int64-div-runtime', 'codegen', 'compiler',
    @CaseInt64DivRuntime, InnerCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_numeric', 'shift-constant', 'codegen', 'compiler',
    @CaseShiftConstant, InnerCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_numeric', 'shift-variable', 'codegen', 'compiler',
    @CaseShiftVariable, InnerCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_numeric', 'rotate-mix', 'codegen', 'compiler',
    @CaseRotateMix, InnerCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_numeric', 'bit-boolean', 'codegen', 'compiler',
    @CaseBitBoolean, InnerCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_numeric', 'double-arithmetic', 'codegen', 'compiler',
    @CaseDoubleArithmetic, InnerCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_numeric', 'single-arithmetic', 'codegen', 'compiler',
    @CaseSingleArithmetic, InnerCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_numeric', 'int-double-convert', 'codegen+rtl', 'compiler',
    @CaseIntDoubleConvert, InnerCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_numeric', 'single-double-convert', 'codegen', 'compiler',
    @CaseSingleDoubleConvert, InnerCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_numeric', 'min-max-mixed', 'codegen', 'compiler',
    @CaseMinMaxMixed, InnerCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_numeric', 'small-set-ops', 'codegen', 'compiler',
    @CaseSmallSetOps, InnerCount * 16, Profile, SelectedCase, Found);
  PulseRunCase('pulse_numeric', 'wide-set-ops', 'codegen+rtl', 'compiler',
    @CaseWideSetOps, InnerCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_numeric', 'range-checked-index', 'codegen', 'compiler',
    @CaseRangeCheckedIndex, InnerCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_numeric', 'unchecked-index', 'codegen', 'compiler',
    @CaseUncheckedIndex, InnerCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_numeric', 'overflow-checked', 'codegen', 'compiler',
    @CaseOverflowChecked, InnerCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_numeric', 'overflow-unchecked', 'codegen', 'compiler',
    @CaseOverflowUnchecked, InnerCount, Profile, SelectedCase, Found);
  PulseFinish('pulse_numeric', SelectedCase, Found);
end.
