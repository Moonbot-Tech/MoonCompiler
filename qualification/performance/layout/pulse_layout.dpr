program pulse_layout;

{$ifndef FPC}
  {$APPTYPE CONSOLE}
{$endif}

{$ifdef FPC}
  {$mode delphi}{$H+}
{$endif}

{$Q-}{$R-}
{$POINTERMATH ON}

uses
  {$if defined(FPC) and not defined(PULSE_DEFAULT_MM)}
  mormot.core.fpcx64mm,
  {$ifend}
  SysUtils,
  perf_clock in '..\common\perf_clock.pas',
  pulse_process_metrics in '..\common\pulse_process_metrics.pas',
  pulse_harness in '..\common\pulse_harness.pas';

const
  ItemCount = 8192;
  InnerCount = 256;

type
  PInt32 = ^Int32;
  TAlignedItem = record
    A, B: UInt64;
    C, D: UInt32;
    X, Y: Double;
  end;
  TPackedItem = packed record
    Flag: Byte;
    A: UInt64;
    C: UInt32;
    B: UInt64;
  end;
  TVariantItem = record
    Tag: Integer;
    case Integer of
      0: (IntegerValue: Int64);
      1: (DoubleValue: Double);
      2: (LowPart, HighPart: UInt32);
  end;
  TByteBlock16 = array[0..15] of Byte;
  TByteBlock64 = array[0..63] of Byte;
  TByteBlock256 = array[0..255] of Byte;
  TByteBlock1024 = array[0..1023] of Byte;

var
  AlignedItems: array of TAlignedItem;
  PackedItems: array of TPackedItem;
  VariantItems: array of TVariantItem;
  SoAA, SoAB: array of UInt64;
  SoAX, SoAY: array of Double;
  DynamicInts: TArray<Int32>;
  StaticInts: array[0..ItemCount - 1] of Int32;
  AlignedBytes: array of Byte;
  Source16, Target16: TByteBlock16;
  Source64, Target64: TByteBlock64;
  Source256, Target256: TByteBlock256;
  Source1024, Target1024: TByteBlock1024;

function CaseAlignedRead(Iterations: Integer): UInt64;
var
  I, J: Integer;
  P: PUInt64;
begin
  Result := 0;
  P := PUInt64(@AlignedBytes[0]);
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      Result := Result + P[(I + J) and 1023];
end;

function CaseUnalignedRead(Iterations: Integer): UInt64;
var
  I, J: Integer;
  P: PUInt64;
begin
  Result := 0;
  P := PUInt64(@AlignedBytes[1]);
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      Result := Result + P[(I + J) and 1023];
end;

function CaseAoSOneField(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to ItemCount - 1 do
      Result := Result + AlignedItems[J].A;
end;

function CaseAoSAllFields(Iterations: Integer): UInt64;
var
  I, J: Integer;
  SumDouble: Double;
begin
  Result := 0;
  SumDouble := 0;
  for I := 1 to Iterations do
    for J := 0 to ItemCount - 1 do
    begin
      Result := Result + AlignedItems[J].A + AlignedItems[J].B +
        AlignedItems[J].C + AlignedItems[J].D;
      SumDouble := SumDouble + AlignedItems[J].X + AlignedItems[J].Y;
    end;
  Result := Result xor UInt64(Trunc(SumDouble * 1024.0));
end;

function CaseSoAOneField(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to ItemCount - 1 do
      Result := Result + SoAA[J];
end;

function CaseSoAAllFields(Iterations: Integer): UInt64;
var
  I, J: Integer;
  SumDouble: Double;
begin
  Result := 0;
  SumDouble := 0;
  for I := 1 to Iterations do
    for J := 0 to ItemCount - 1 do
    begin
      Result := Result + SoAA[J] + SoAB[J];
      SumDouble := SumDouble + SoAX[J] + SoAY[J];
    end;
  Result := Result xor UInt64(Trunc(SumDouble * 1024.0));
end;

function CasePackedRecord(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to ItemCount - 1 do
      Result := Result + PackedItems[J].A + PackedItems[J].B +
        PackedItems[J].C + PackedItems[J].Flag;
end;

function CaseVariantRecord(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to ItemCount - 1 do
      case VariantItems[J].Tag of
        0: Result := Result + UInt64(VariantItems[J].IntegerValue);
        1: Result := Result + UInt64(Trunc(VariantItems[J].DoubleValue * 1024.0));
      else
        Result := Result + VariantItems[J].LowPart + VariantItems[J].HighPart;
      end;
end;

function CaseStaticArray(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to ItemCount - 1 do
      Result := Result + UInt32(StaticInts[J]);
end;

function CaseDynamicArray(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to High(DynamicInts) do
      Result := Result + UInt32(DynamicInts[J]);
end;

function CasePointerWalk(Iterations: Integer): UInt64;
var
  I, J: Integer;
  P: PInt32;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    P := @StaticInts[0];
    for J := 0 to ItemCount - 1 do
    begin
      Result := Result + UInt32(P^);
      Inc(P);
    end;
  end;
end;

function CaseIndexedWalk(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to ItemCount - 1 do
      Result := Result + UInt32(StaticInts[J]);
end;

function CaseMove16(Iterations: Integer): UInt64;
var
  I: Integer;
begin
  for I := 1 to Iterations do
    Move(Source16, Target16, SizeOf(Target16));
  Result := Target16[Iterations and High(Target16)];
end;

function CaseMove64(Iterations: Integer): UInt64;
var
  I: Integer;
begin
  for I := 1 to Iterations do
    Move(Source64, Target64, SizeOf(Target64));
  Result := Target64[Iterations and High(Target64)];
end;

function CaseMove256(Iterations: Integer): UInt64;
var
  I: Integer;
begin
  for I := 1 to Iterations do
    Move(Source256, Target256, SizeOf(Target256));
  Result := Target256[Iterations and High(Target256)];
end;

function CaseMove1024(Iterations: Integer): UInt64;
var
  I: Integer;
begin
  for I := 1 to Iterations do
    Move(Source1024, Target1024, SizeOf(Target1024));
  Result := Target1024[Iterations and High(Target1024)];
end;

function CaseFill16(Iterations: Integer): UInt64;
var
  I: Integer;
begin
  for I := 1 to Iterations do
    FillChar(Target16, SizeOf(Target16), I);
  Result := Target16[Iterations and High(Target16)];
end;

function CaseFill64(Iterations: Integer): UInt64;
var
  I: Integer;
begin
  for I := 1 to Iterations do
    FillChar(Target64, SizeOf(Target64), I);
  Result := Target64[Iterations and High(Target64)];
end;

function CaseFill256(Iterations: Integer): UInt64;
var
  I: Integer;
begin
  for I := 1 to Iterations do
    FillChar(Target256, SizeOf(Target256), I);
  Result := Target256[Iterations and High(Target256)];
end;

function CaseFill1024(Iterations: Integer): UInt64;
var
  I: Integer;
begin
  for I := 1 to Iterations do
    FillChar(Target1024, SizeOf(Target1024), I);
  Result := Target1024[Iterations and High(Target1024)];
end;

procedure InitializeData;
var
  I: Integer;
begin
  SetLength(AlignedItems, ItemCount);
  SetLength(PackedItems, ItemCount);
  SetLength(VariantItems, ItemCount);
  SetLength(SoAA, ItemCount);
  SetLength(SoAB, ItemCount);
  SetLength(SoAX, ItemCount);
  SetLength(SoAY, ItemCount);
  SetLength(DynamicInts, ItemCount);
  SetLength(AlignedBytes, 8192 + 16);
  for I := 0 to ItemCount - 1 do
  begin
    AlignedItems[I].A := UInt64(I * 17 + 3);
    AlignedItems[I].B := UInt64(I * 31 + 7);
    AlignedItems[I].C := UInt32(I * 13 + 11);
    AlignedItems[I].D := UInt32(I * 19 + 5);
    AlignedItems[I].X := (I and 1023) * 0.0009765625;
    AlignedItems[I].Y := ((I * 7) and 1023) * 0.00048828125;
    PackedItems[I].Flag := Byte(I);
    PackedItems[I].A := AlignedItems[I].A;
    PackedItems[I].B := AlignedItems[I].B;
    PackedItems[I].C := AlignedItems[I].C;
    VariantItems[I].Tag := I mod 3;
    If VariantItems[I].Tag = 0 then
      VariantItems[I].IntegerValue := I * 17 + 3
    else If VariantItems[I].Tag = 1 then
      VariantItems[I].DoubleValue := I * 0.125
    else begin
      VariantItems[I].LowPart := UInt32(I * 13);
      VariantItems[I].HighPart := UInt32(I * 29);
    end;
    SoAA[I] := AlignedItems[I].A;
    SoAB[I] := AlignedItems[I].B;
    SoAX[I] := AlignedItems[I].X;
    SoAY[I] := AlignedItems[I].Y;
    StaticInts[I] := Int32(UInt32(I * 747796405 + 2891336453));
    DynamicInts[I] := StaticInts[I];
  end;
  for I := 0 to High(AlignedBytes) do
    AlignedBytes[I] := Byte(I * 37 + 11);
  for I := 0 to High(Source1024) do
    Source1024[I] := Byte(I * 17 + 3);
  Move(Source1024, Source256, SizeOf(Source256));
  Move(Source256, Source64, SizeOf(Source64));
  Move(Source64, Source16, SizeOf(Source16));
end;

var
  Profile: TPulseProfile;
  SelectedCase: string;
  Found: Boolean;
begin
  InitializeData;
  PulseInitialize('pulse_layout', Profile, SelectedCase);
  Found := False;
  PulseRunCase('pulse_layout', 'aligned-read', 'codegen+memory', 'compiler',
    @CaseAlignedRead, InnerCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_layout', 'unaligned-read', 'codegen+memory', 'compiler',
    @CaseUnalignedRead, InnerCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_layout', 'aos-one-field', 'codegen+memory', 'compiler',
    @CaseAoSOneField, ItemCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_layout', 'aos-all-fields', 'codegen+memory', 'compiler',
    @CaseAoSAllFields, ItemCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_layout', 'soa-one-field', 'codegen+memory', 'compiler',
    @CaseSoAOneField, ItemCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_layout', 'soa-all-fields', 'codegen+memory', 'compiler',
    @CaseSoAAllFields, ItemCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_layout', 'packed-record', 'codegen+memory', 'compiler',
    @CasePackedRecord, ItemCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_layout', 'variant-record', 'codegen+memory', 'compiler',
    @CaseVariantRecord, ItemCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_layout', 'static-array', 'codegen+memory', 'compiler',
    @CaseStaticArray, ItemCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_layout', 'dynamic-array', 'codegen+memory', 'compiler',
    @CaseDynamicArray, ItemCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_layout', 'pointer-walk', 'codegen+memory', 'compiler',
    @CasePointerWalk, ItemCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_layout', 'indexed-walk', 'codegen+memory', 'compiler',
    @CaseIndexedWalk, ItemCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_layout', 'move-16', 'rtl', 'System.Move', @CaseMove16, 16,
    Profile, SelectedCase, Found);
  PulseRunCase('pulse_layout', 'move-64', 'rtl', 'System.Move', @CaseMove64, 64,
    Profile, SelectedCase, Found);
  PulseRunCase('pulse_layout', 'move-256', 'rtl', 'System.Move', @CaseMove256,
    256, Profile, SelectedCase, Found);
  PulseRunCase('pulse_layout', 'move-1024', 'rtl', 'System.Move', @CaseMove1024,
    1024, Profile, SelectedCase, Found);
  PulseRunCase('pulse_layout', 'fill-16', 'rtl', 'System.FillChar', @CaseFill16,
    16, Profile, SelectedCase, Found);
  PulseRunCase('pulse_layout', 'fill-64', 'rtl', 'System.FillChar', @CaseFill64,
    64, Profile, SelectedCase, Found);
  PulseRunCase('pulse_layout', 'fill-256', 'rtl', 'System.FillChar',
    @CaseFill256, 256, Profile, SelectedCase, Found);
  PulseRunCase('pulse_layout', 'fill-1024', 'rtl', 'System.FillChar',
    @CaseFill1024, 1024, Profile, SelectedCase, Found);
  PulseFinish('pulse_layout', SelectedCase, Found);
end.
