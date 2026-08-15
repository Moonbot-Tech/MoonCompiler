program pulse_mm;

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
  pulse_harness in '..\common\pulse_harness.pas';

const
  RingCount = 256;

type
  TSizeArray = array[0..7] of NativeInt;

const
  MixedSizes: TSizeArray = (16, 48, 128, 512, 4096, 17000, 100500, 1048576);

function AllocateTouchFree(Size, Iterations: Integer): UInt64;
var
  I: Integer;
  P: PByte;
  Digest: UInt64;
begin
  Digest := 0;
  for I := 1 to Iterations do
  begin
    GetMem(P, Size);
    P[0] := Byte(I);
    P[Size - 1] := Byte(I shr 8);
    Digest := Digest + P[0] + UInt64(P[Size - 1]) shl 8;
    FreeMem(P);
  end;
  Result := Digest;
end;

function CaseAlloc16(Iterations: Integer): UInt64;
begin Result := AllocateTouchFree(16, Iterations); end;
function CaseAlloc64(Iterations: Integer): UInt64;
begin Result := AllocateTouchFree(64, Iterations); end;
function CaseAlloc256(Iterations: Integer): UInt64;
begin Result := AllocateTouchFree(256, Iterations); end;
function CaseAlloc1024(Iterations: Integer): UInt64;
begin Result := AllocateTouchFree(1024, Iterations); end;
function CaseAlloc16K(Iterations: Integer): UInt64;
begin Result := AllocateTouchFree(16384, Iterations); end;
function CaseAlloc17408(Iterations: Integer): UInt64;
begin Result := AllocateTouchFree(17408, Iterations); end;
function CaseAlloc17409(Iterations: Integer): UInt64;
begin Result := AllocateTouchFree(17409, Iterations); end;
function CaseAllocMedium(Iterations: Integer): UInt64;
begin Result := AllocateTouchFree(100500, Iterations); end;
function CaseAlloc1M(Iterations: Integer): UInt64;
begin Result := AllocateTouchFree(1048576, Iterations); end;
function CaseAlloc2M(Iterations: Integer): UInt64;
begin Result := AllocateTouchFree(2097152, Iterations); end;

function CaseRingSameClass(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Pointers: array[0..RingCount - 1] of Pointer;
  P: PByte;
  Digest: UInt64;
begin
  Digest := 0;
  for I := 1 to Iterations do
  begin
    for J := 0 to RingCount - 1 do
    begin
      GetMem(Pointers[J], 96);
      P := Pointers[J];
      P[0] := Byte(I + J);
    end;
    for J := RingCount - 1 downto 0 do
    begin
      P := Pointers[J];
      Digest := Digest + P[0];
      FreeMem(Pointers[J]);
    end;
  end;
  Result := Digest;
end;

function CaseRingMixed(Iterations: Integer): UInt64;
var
  I, J, Size: Integer;
  Pointers: array[0..RingCount - 1] of Pointer;
  P: PByte;
  Digest: UInt64;
begin
  Digest := 0;
  for I := 1 to Iterations do
  begin
    for J := 0 to RingCount - 1 do
    begin
      Size := MixedSizes[J and High(MixedSizes)];
      GetMem(Pointers[J], Size);
      P := Pointers[J];
      P[0] := Byte(I + J);
      P[Size - 1] := Byte(J);
    end;
    for J := RingCount - 1 downto 0 do
    begin
      Size := MixedSizes[J and High(MixedSizes)];
      P := Pointers[J];
      Digest := Digest + P[0] + P[Size - 1];
      FreeMem(Pointers[J]);
    end;
  end;
  Result := Digest;
end;

function CaseReallocGrow(Iterations: Integer): UInt64;
var
  I, Size: Integer;
  P: PByte;
  Digest: UInt64;
begin
  Digest := 0;
  for I := 1 to Iterations do
  begin
    Size := 32;
    GetMem(P, Size);
    P[0] := Byte(I);
    while Size < 131072 do
    begin
      Size := Size * 2;
      ReallocMem(P, Size);
      P[Size - 1] := Byte(Size shr 10);
      Digest := Digest + P[0] + P[Size - 1];
    end;
    FreeMem(P);
  end;
  Result := Digest;
end;

function CaseReallocShrink(Iterations: Integer): UInt64;
var
  I, Size: Integer;
  P: PByte;
  Digest: UInt64;
begin
  Digest := 0;
  for I := 1 to Iterations do
  begin
    Size := 131072;
    GetMem(P, Size);
    P[0] := Byte(I);
    while Size > 32 do
    begin
      Size := Size div 2;
      ReallocMem(P, Size);
      Digest := Digest + P[0];
    end;
    FreeMem(P);
  end;
  Result := Digest;
end;

function CaseFragmented(Iterations: Integer): UInt64;
var
  I, J, Size: Integer;
  Pointers: array[0..511] of Pointer;
  P: PByte;
  Digest: UInt64;
begin
  Digest := 0;
  for I := 1 to Iterations do
  begin
    for J := 0 to High(Pointers) do
    begin
      Size := 16 + ((J * 73) mod 16384);
      GetMem(Pointers[J], Size);
      P := Pointers[J];
      P[0] := Byte(J);
    end;
    for J := 0 to High(Pointers) do
      If (J and 1) = 0 then
      begin
        P := Pointers[J];
        Digest := Digest + P[0];
        FreeMem(Pointers[J]);
        Pointers[J] := nil;
      end;
    for J := 0 to High(Pointers) do
      If Pointers[J] = nil then
      begin
        Size := 24 + ((J * 101) mod 8192);
        GetMem(Pointers[J], Size);
        PByte(Pointers[J])[0] := Byte(J xor I);
      end;
    for J := High(Pointers) downto 0 do
    begin
      P := Pointers[J];
      Digest := Digest + P[0];
      FreeMem(Pointers[J]);
    end;
  end;
  Result := Digest;
end;

function ManagerName: string;
begin
  {$ifdef FPC}
    {$ifdef PULSE_DEFAULT_MM}
    Result := 'fpc-default';
    {$else}
    Result := 'moon-fpcx64mm';
    {$endif}
  {$else}
  Result := 'delphi-default-fastmm4';
  {$endif}
end;

procedure Run;
var
  Profile: TPulseProfile;
  SelectedCase: string;
  Found: Boolean;
  UnitName: string;
begin
  PulseInitialize('pulse_mm', Profile, SelectedCase);
  UnitName := ManagerName;
  Found := False;
  PulseRunCase('pulse_mm', 'alloc-free-16', 'mm', UnitName, @CaseAlloc16, 1,
    Profile, SelectedCase, Found);
  PulseRunCase('pulse_mm', 'alloc-free-64', 'mm', UnitName, @CaseAlloc64, 1,
    Profile, SelectedCase, Found);
  PulseRunCase('pulse_mm', 'alloc-free-256', 'mm', UnitName, @CaseAlloc256, 1,
    Profile, SelectedCase, Found);
  PulseRunCase('pulse_mm', 'alloc-free-1024', 'mm', UnitName, @CaseAlloc1024, 1,
    Profile, SelectedCase, Found);
  PulseRunCase('pulse_mm', 'alloc-free-16k', 'mm', UnitName, @CaseAlloc16K, 1,
    Profile, SelectedCase, Found);
  PulseRunCase('pulse_mm', 'alloc-free-17408', 'mm', UnitName,
    @CaseAlloc17408, 1, Profile, SelectedCase, Found);
  PulseRunCase('pulse_mm', 'alloc-free-17409', 'mm', UnitName,
    @CaseAlloc17409, 1, Profile, SelectedCase, Found);
  PulseRunCase('pulse_mm', 'alloc-free-100500', 'mm', UnitName,
    @CaseAllocMedium, 1, Profile, SelectedCase, Found);
  PulseRunCase('pulse_mm', 'alloc-free-1m', 'mm', UnitName, @CaseAlloc1M, 1,
    Profile, SelectedCase, Found);
  PulseRunCase('pulse_mm', 'alloc-free-2m', 'mm', UnitName, @CaseAlloc2M, 1,
    Profile, SelectedCase, Found);
  PulseRunCase('pulse_mm', 'ring-same-class-96', 'mm', UnitName,
    @CaseRingSameClass, RingCount * 2, Profile, SelectedCase, Found);
  PulseRunCase('pulse_mm', 'ring-mixed-16-to-1m', 'mm', UnitName,
    @CaseRingMixed, RingCount * 2, Profile, SelectedCase, Found);
  PulseRunCase('pulse_mm', 'realloc-grow', 'mm', UnitName, @CaseReallocGrow, 13,
    Profile, SelectedCase, Found);
  PulseRunCase('pulse_mm', 'realloc-shrink', 'mm', UnitName,
    @CaseReallocShrink, 13, Profile, SelectedCase, Found);
  PulseRunCase('pulse_mm', 'fragmented-mixed', 'mm', UnitName,
    @CaseFragmented, 1024, Profile, SelectedCase, Found);
  PulseFinish('pulse_mm', SelectedCase, Found);
end;

begin
  try
    Run;
  except
    on E: Exception do
    begin
      WriteLn(ErrOutput, E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
