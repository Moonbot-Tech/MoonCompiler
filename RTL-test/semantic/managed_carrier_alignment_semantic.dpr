program managed_carrier_alignment_semantic;

{ Raw byte arrays are used internally as storage carriers for Delphi managed
  records.  Their semantic element type has byte alignment, but the physical
  temporary must preserve the alignment of the record it contains.  Exercise
  real and inlined stack value parameters at the Win64/Linux x86-64 local
  alignment contract (16), then 32/64-byte sources whose open-array value
  copies are materialized by explicitly aligned heap carriers. }

{$APPTYPE CONSOLE}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  {$endif UNIX}
  SysUtils;

var
  InitializeFailures: Integer;
  FinalizeFailures: Integer;
  AssignDestFailures: Integer;
  AssignSourceFailures: Integer;
  RealParamFailures: Integer;
  InlineParamFailures: Integer;
  OpenArrayFailures: Integer;
  Heap32Failures: Integer;
  Align64Failures: Integer;

type
  TAlignedValue = record
    Value: Integer;
    Padding: array[0..11] of Byte;
    class operator Initialize(out Dest: TAlignedValue);
    class operator Finalize(var Dest: TAlignedValue);
    class operator Assign(var Dest: TAlignedValue;
      const [ref] Src: TAlignedValue);
  end align 16;

  THeapAlignedValue = record
    Value: Integer;
    Padding: array[0..27] of Byte;
    class operator Initialize(out Dest: THeapAlignedValue);
    class operator Finalize(var Dest: THeapAlignedValue);
    class operator Assign(var Dest: THeapAlignedValue;
      const [ref] Src: THeapAlignedValue);
  end align 32;

  THeapAlignedArray = array[0..1] of THeapAlignedValue;
  PHeapAlignedArray = ^THeapAlignedArray;

  TAligned64Value = record
    Value: Integer;
    Padding: array[0..59] of Byte;
    class operator Initialize(out Dest: TAligned64Value);
    class operator Finalize(var Dest: TAligned64Value);
    class operator Assign(var Dest: TAligned64Value;
      const [ref] Src: TAligned64Value);
  end align 64;

  TAligned64Array = array[0..1] of TAligned64Value;
  PAligned64Array = ^TAligned64Array;

class operator TAlignedValue.Initialize(out Dest: TAlignedValue);
begin
  If (PtrUInt(@Dest) and 15) <> 0 then
    Inc(InitializeFailures);
  Dest.Value := 100;
end;

class operator TAlignedValue.Finalize(var Dest: TAlignedValue);
begin
  If (PtrUInt(@Dest) and 15) <> 0 then
    Inc(FinalizeFailures);
end;

class operator TAlignedValue.Assign(var Dest: TAlignedValue;
  const [ref] Src: TAlignedValue);
begin
  If (PtrUInt(@Dest) and 15) <> 0 then
    Inc(AssignDestFailures);
  If (PtrUInt(@Src) and 15) <> 0 then
    Inc(AssignSourceFailures);
  Dest.Value := Src.Value + 1;
end;

class operator THeapAlignedValue.Initialize(out Dest: THeapAlignedValue);
begin
  If (PtrUInt(@Dest) and 31) <> 0 then
    Inc(Heap32Failures);
  Dest.Value := 100;
end;

class operator THeapAlignedValue.Finalize(var Dest: THeapAlignedValue);
begin
  If (PtrUInt(@Dest) and 31) <> 0 then
    Inc(Heap32Failures);
end;

class operator THeapAlignedValue.Assign(var Dest: THeapAlignedValue;
  const [ref] Src: THeapAlignedValue);
begin
  If ((PtrUInt(@Dest) or PtrUInt(@Src)) and 31) <> 0 then
    Inc(Heap32Failures);
  Dest.Value := Src.Value + 1;
end;

class operator TAligned64Value.Initialize(out Dest: TAligned64Value);
begin
  If (PtrUInt(@Dest) and 63) <> 0 then
    Inc(Align64Failures);
  Dest.Value := 100;
end;

class operator TAligned64Value.Finalize(var Dest: TAligned64Value);
begin
  If (PtrUInt(@Dest) and 63) <> 0 then
    Inc(Align64Failures);
end;

class operator TAligned64Value.Assign(var Dest: TAligned64Value;
  const [ref] Src: TAligned64Value);
begin
  If ((PtrUInt(@Dest) or PtrUInt(@Src)) and 63) <> 0 then
    Inc(Align64Failures);
  Dest.Value := Src.Value + 1;
end;

procedure TakeValue(Value: TAlignedValue);
begin
  If (PtrUInt(@Value) and 15) <> 0 then
    Inc(RealParamFailures);
  If Value.Value <> 8 then
    raise Exception.Create('real value copy');
end;

procedure TakeValueInline(Value: TAlignedValue); inline;
begin
  If (PtrUInt(@Value) and 15) <> 0 then
    Inc(InlineParamFailures);
  If Value.Value <> 8 then
    raise Exception.Create('inlined value copy');
end;

procedure TakeOpen(Values: array of TAlignedValue);
begin
  If Length(Values) <> 2 then
    raise Exception.Create('open-array length');
  If (PtrUInt(@Values[0]) and 15) <> 0 then
    Inc(OpenArrayFailures);
  If (Values[0].Value <> 12) or (Values[1].Value <> 22) then
    raise Exception.Create('open-array values');
end;

procedure TakeOpen32(Values: array of THeapAlignedValue);
begin
  If Length(Values) <> 2 then
    raise Exception.Create('aligned open-array length');
  If (PtrUInt(@Values[0]) and 31) <> 0 then
    Inc(Heap32Failures);
  If (Values[0].Value <> 32) or (Values[1].Value <> 42) then
    raise Exception.Create('aligned open-array values');
end;

procedure TakeOpen64(Values: array of TAligned64Value);
begin
  If Length(Values) <> 2 then
    raise Exception.Create('64-byte aligned open-array length');
  If (PtrUInt(@Values[0]) and 63) <> 0 then
    Inc(Align64Failures);
  If (Values[0].Value <> 52) or (Values[1].Value <> 62) then
    raise Exception.Create('64-byte aligned open-array values');
end;

procedure Run;
var
  Value: TAlignedValue;
  Values: array[0..1] of TAlignedValue;
  HeapValues: PHeapAlignedArray;
  Aligned64Values: PAligned64Array;
begin
  Value.Value := 7;
  TakeValue(Value);
  TakeValueInline(Value);

  Values[0].Value := 11;
  Values[1].Value := 21;
  TakeOpen(Values);

  HeapValues := AllocMemAligned(SizeOf(THeapAlignedArray),32);
  If not Assigned(HeapValues) then
    raise Exception.Create('32-byte aligned source allocation');
  try
    HeapValues^[0].Value := 31;
    HeapValues^[1].Value := 41;
    TakeOpen32(HeapValues^);
  finally
    FreeMemAligned(HeapValues);
  end;

  Aligned64Values := AllocMemAligned(SizeOf(TAligned64Array),64);
  If not Assigned(Aligned64Values) then
    raise Exception.Create('64-byte aligned source allocation');
  try
    Aligned64Values^[0].Value := 51;
    Aligned64Values^[1].Value := 61;
    TakeOpen64(Aligned64Values^);
  finally
    FreeMemAligned(Aligned64Values);
  end;
end;

begin
  try
    Run;
    If (InitializeFailures <> 0) or (FinalizeFailures <> 0) or
       (AssignDestFailures <> 0) or (AssignSourceFailures <> 0) or
       (RealParamFailures <> 0) or (InlineParamFailures <> 0) or
       (OpenArrayFailures <> 0) or (Heap32Failures <> 0) or
       (Align64Failures <> 0) then
      raise Exception.CreateFmt(
        'misaligned carriers init=%d fin=%d assign-dest=%d assign-src=%d real=%d inline=%d open=%d heap32=%d align64=%d',
        [InitializeFailures, FinalizeFailures, AssignDestFailures,
         AssignSourceFailures, RealParamFailures, InlineParamFailures,
         OpenArrayFailures, Heap32Failures, Align64Failures]);
    WriteLn('MANAGED_CARRIER_ALIGNMENT_OK');
  except
    on E: Exception do begin
      WriteLn('MANAGED_CARRIER_ALIGNMENT_FAIL ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
