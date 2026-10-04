program memory_status;

{$mode delphi}

uses
  mormot.core.fpcx64mm,
  SysUtils;

procedure Check(Condition: boolean; const Message: string);
begin
  if not Condition then
    raise Exception.Create(Message);
end;

procedure CheckConsistent;
var
  light: TMMStatus;
  heavy: TMMFragmentationStatus;
begin
  light := CurrentHeapStatus;
  heavy := CurrentHeapFragmentationStatus;
  Check(heavy.Errors = 0, 'fragmentation scanner reported an invalid heap');
  Check(heavy.LiveSmallBytes = light.SmallBlocksSize,
    'small live-byte counters disagree');
  Check(heavy.LiveLargeBytes = light.Large.CurrentBytes,
    'large live-byte counters disagree');
  Check(light.MediumStandbyBytes = heavy.MediumStandbyBytes,
    'standby byte counters disagree');
  Check(light.OsHeldBytes = heavy.MediumReservedBytes +
    heavy.MediumStandbyBytes + heavy.LargeReservedBytes,
    'OS-held byte counters disagree');
end;

var
  baseline, status: TMMStatus;
  baselineHeavy, heavy: TMMFragmentationStatus;
  small, medium, large: pointer;
  expected: PtrUInt;
begin
  IsMultiThread := true;
  CheckConsistent;
  baseline := CurrentHeapStatus;
  baselineHeavy := CurrentHeapFragmentationStatus;
  small := _GetMem(17);
  medium := _GetMem(17000);
  large := _GetMem(300000);
  try
    status := CurrentHeapStatus;
    expected := baselineHeavy.LiveMediumBytes + _MemSize(medium) + SizeOf(pointer);
    Check(status.SmallBlocks = baseline.SmallBlocks + 1,
      'small allocation count was not recorded');
    Check(status.SmallBlocksSize > baseline.SmallBlocksSize,
      'small allocation capacity was not recorded');
    heavy := CurrentHeapFragmentationStatus;
    Check(heavy.LiveMediumBytes = expected,
      'medium allocation capacity was not recorded');
    Check(status.Large.CurrentBytes > baseline.Large.CurrentBytes,
      'large allocation capacity was not recorded');
    CheckConsistent;

    _ReallocMem(medium, 4000);
    heavy := CurrentHeapFragmentationStatus;
    expected := baselineHeavy.LiveMediumBytes + _MemSize(medium) + SizeOf(pointer);
    Check(heavy.LiveMediumBytes = expected,
      'medium in-place downsize was not recorded');
    CheckConsistent;

    _ReallocMem(medium, 120000);
    heavy := CurrentHeapFragmentationStatus;
    expected := baselineHeavy.LiveMediumBytes + _MemSize(medium) + SizeOf(pointer);
    Check(heavy.LiveMediumBytes = expected,
      'medium upsize was not recorded');
    CheckConsistent;
  finally
    _FreeMem(small);
    _FreeMem(medium);
    _FreeMem(large);
  end;
  status := CurrentHeapStatus;
  Check(status.SmallBlocks = baseline.SmallBlocks,
    'small allocation count did not return to baseline');
  Check(status.SmallBlocksSize = baseline.SmallBlocksSize,
    'small allocation capacity did not return to baseline');
  heavy := CurrentHeapFragmentationStatus;
  Check(heavy.LiveMediumBytes = baselineHeavy.LiveMediumBytes,
    'medium allocation capacity did not return to baseline');
  Check(status.Large.CurrentBytes = baseline.Large.CurrentBytes,
    'large allocation capacity did not return to baseline');
  CheckConsistent;
  Writeln('MEMORY_STATUS_PASS');
end.
