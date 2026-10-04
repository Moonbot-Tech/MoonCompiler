program pulse_move;

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
  {$I ../common/pulse_placement_uses.inc}
  SysUtils,
  perf_clock in '..\common\perf_clock.pas',
  pulse_process_metrics in '..\common\pulse_process_metrics.pas',
  pulse_harness in '..\common\pulse_harness.pas';

{$I ../common/pulse_program_prefix.inc}

const
  CacheLineSize = 64;
  PageSize = 4096;
  MaximumMoveSize = 1024 * 1024;
  StreamingBytes = 64 * 1024 * 1024;
  RegionBytes = StreamingBytes + MaximumMoveSize + PageSize;

  DenseSizes: array[0..55] of NativeInt = (
    0, 1, 2, 3, 4, 5, 7, 8, 9, 15, 16, 17, 24, 31, 32, 33,
    48, 63, 64, 65, 80, 96, 127, 128, 129, 160, 192, 255,
    256, 257, 320, 384, 511, 512, 513, 640, 768, 896, 1023,
    1024, 1025, 1280, 1535, 1536, 1537, 2048, 3072, 4096,
    8192, 16384, 32768, 65536, 131072, 262144, 524288, 1048576);

  HugeHotSizes: array[0..2] of NativeInt = (
    2 * 1024 * 1024, 4 * 1024 * 1024, 8 * 1024 * 1024);

  AlignmentSizes: array[0..14] of NativeInt = (
    16, 31, 32, 33, 63, 64, 65, 127, 128, 129, 256, 512,
    1024, 1536, 4096);
  AlignmentPairs: array[0..4, 0..1] of NativeInt = (
    (0, 1), (1, 0), (1, 1), (15, 31), (31, 15));
  PageOffsetPairs: array[0..3, 0..1] of NativeInt = (
    (0, 128), (128, 0), (0, 2048), (2048, 0));

  OverlapSizes: array[0..15] of NativeInt = (
    33, 64, 65, 128, 192, 193, 255, 256, 320, 321, 512, 1024, 1536,
    2048, 4096, 65536);
  OverlapDistances: array[0..2] of NativeInt = (1, 16, 63);

  StreamingSizes: array[0..21] of NativeInt = (
    256, 512, 1024, 1536, 2048, 4096, 8192, 16384,
    32768, 65536, 131072, 262144, 524288, 786432, 1048575,
    1048576, 2 * 1024 * 1024, 4 * 1024 * 1024,
    8 * 1024 * 1024, 16 * 1024 * 1024, 32 * 1024 * 1024,
    64 * 1024 * 1024);

type
  TMovePattern = (mpHot, mpStream, mpOverlapForward,
    mpOverlapBackward);

var
  StorageAllocation: Pointer;
  SourceBase, DestBase, OverlapBase: PByte;
  ActiveSize, ActiveSourceAlignment, ActiveDestAlignment: NativeInt;
  ActiveDistance, ActiveStride, ActiveStreamMoves: NativeInt;
  ActivePattern: TMovePattern;

function AlignPointer(Value: Pointer; Alignment: NativeUInt): PByte;
begin
  Result := PByte((NativeUInt(Value) + Alignment - 1) and not (Alignment - 1));
end;

function MixDigest(P: PByte; Count: NativeInt): UInt64;
begin
  If Count <= 0 then
    Exit(UInt64(P[0]) xor $9e3779b97f4a7c15);
  Result := UInt64(P[0]) or (UInt64(P[Count shr 1]) shl 8) or
    (UInt64(P[Count - 1]) shl 16) xor UInt64(Count) * $9e3779b97f4a7c15;
end;

{ The copy loops read no global: the size reloaded from ActiveSize (page
  offset 0x050) right after the stores of a copy to a page start 4K-aliased
  them, and Zen 3 held every call on that false dependency by the layout of
  the code behind Move (audit WP3 r4).  A pass of the stream is a procedure of
  its own: its five values fit the five callee-saved registers of SysV, where
  the seven of a whole stream in one function left two pointers on the
  stack. }
function CaseMove(Iterations: Integer): UInt64;
var
  I: Integer;
  SourcePointer, DestPointer: PByte;
  Size: NativeInt;
begin
  Size := ActiveSize;
  case ActivePattern of
    mpHot:
      begin
        SourcePointer := SourceBase + ActiveSourceAlignment;
        DestPointer := DestBase + ActiveDestAlignment;
      end;
    mpOverlapForward:
      begin
        SourcePointer := OverlapBase + ActiveDistance;
        DestPointer := OverlapBase;
      end;
  else
    begin
      SourcePointer := OverlapBase;
      DestPointer := OverlapBase + ActiveDistance;
    end;
  end;
  for I := 1 to Iterations do
    Move(SourcePointer^, DestPointer^, Size);
  If ActivePattern in [mpOverlapForward, mpOverlapBackward] then
    Result := UInt64(ActiveSize) xor (UInt64(ActiveDistance) shl 32) xor
      UInt64(Ord(ActivePattern)) * $9e3779b97f4a7c15
  else
    Result := MixDigest(DestPointer, ActiveSize);
end;

procedure StreamPass(Source, Dest: PByte; Size, Stride, Moves: NativeInt);
begin
  repeat
    Move(Source^, Dest^, Size);
    Inc(Source, Stride);
    Inc(Dest, Stride);
    Dec(Moves);
  until Moves = 0;
end;

function CaseStream(Iterations: Integer): UInt64;
var
  I: Integer;
  SourceStart, DestStart: PByte;
  Size, Stride, Moves: NativeInt;
begin
  SourceStart := SourceBase + ActiveSourceAlignment;
  DestStart := DestBase + ActiveDestAlignment;
  Size := ActiveSize;
  Stride := ActiveStride;
  Moves := ActiveStreamMoves;
  for I := 1 to Iterations do
    StreamPass(SourceStart, DestStart, Size, Stride, Moves);
  Result := MixDigest(DestBase + ActiveDestAlignment, ActiveSize) xor
    MixDigest(DestBase + ActiveDestAlignment +
      (ActiveStreamMoves - 1) * ActiveStride, ActiveSize) *
      $d6e8feb86659fd93 xor UInt64(ActiveStreamMoves);
end;

procedure InitializeRegion(P: PByte; Count: NativeInt; Seed: UInt32);
var
  I: NativeInt;
begin
  for I := 0 to Count - 1 do
    P[I] := Byte((UInt32(I) * 37 + (UInt32(I) shr 3) + Seed) and $ff);
end;

procedure InitializeData;
begin
  GetMem(StorageAllocation, RegionBytes * 2 + MaximumMoveSize + PageSize * 2);
  SourceBase := AlignPointer(StorageAllocation, PageSize);
  DestBase := SourceBase + RegionBytes;
  OverlapBase := DestBase + RegionBytes;
end;

procedure FinalizeData;
begin
  FreeMem(StorageAllocation);
end;

procedure RunConfiguredCase(const CaseName: string; Size, SourceAlignment,
  DestAlignment, Distance: NativeInt; Pattern: TMovePattern;
  const Profile: TPulseProfile; const SelectedCase: string; var Found: Boolean);
var
  StreamAlignment: NativeInt;
  Data: string;
  Body: TPulseCaseProc;
  Work: Pointer;
begin
  ActiveSize := Size;
  ActiveSourceAlignment := SourceAlignment;
  ActiveDestAlignment := DestAlignment;
  ActiveDistance := Distance;
  ActivePattern := Pattern;
  ActiveStride := (ActiveSize + CacheLineSize - 1) and -CacheLineSize;
  If ActiveStride < CacheLineSize then
    ActiveStride := CacheLineSize;
  If Pattern = mpStream then
  begin
    StreamAlignment := ActiveSourceAlignment;
    If ActiveDestAlignment > StreamAlignment then
      StreamAlignment := ActiveDestAlignment;
    ActiveStreamMoves :=
      (StreamingBytes - StreamAlignment - ActiveSize) div ActiveStride + 1;
  end
  else
    ActiveStreamMoves := 1;
  If (Profile.Name <> 'list') and
    ((SelectedCase = 'all') or SameText(SelectedCase, CaseName)) then
    case Pattern of
      mpHot:
        begin
          InitializeRegion(SourceBase, ActiveSize + SourceAlignment + CacheLineSize, 11);
          InitializeRegion(DestBase, ActiveSize + DestAlignment + CacheLineSize, 173);
        end;
      mpStream:
        begin
          InitializeRegion(SourceBase, StreamingBytes + SourceAlignment, 11);
          InitializeRegion(DestBase, StreamingBytes + DestAlignment, 173);
        end;
    else
      InitializeRegion(OverlapBase, ActiveSize + Distance + CacheLineSize, 91);
    end;
  { The first copy's source and target, as the body computes them. }
  case Pattern of
    mpOverlapForward:
      Data := PulseData('src', OverlapBase + Distance) + PulseData('dst', OverlapBase);
    mpOverlapBackward:
      Data := PulseData('src', OverlapBase) + PulseData('dst', OverlapBase + Distance);
  else
    Data := PulseData('src', SourceBase + SourceAlignment) +
      PulseData('dst', DestBase + DestAlignment);
  end;
  { The copies of a stream loop in StreamPass: registered as the work, its
    loop is checked with the body's. }
  If Pattern = mpStream then
  begin
    Body := @CaseStream;
    Work := @StreamPass;
  end
  else
  begin
    Body := @CaseMove;
    Work := nil;
  end;
  PulseRunCaseData('pulse_move', CaseName, 'rtl+memory', 'System.Move', Body,
    ActiveStreamMoves, Profile, SelectedCase, Found, Work, Data);
end;

var
  Profile: TPulseProfile;
  SelectedCase, CaseName: string;
  Found: Boolean;
  I, J, K: Integer;
begin
  {$ifdef PULSE_PROGRAM_PREFIX}PulseProgramPrefix;{$endif}
  PulseInitialize('pulse_move', Profile, SelectedCase);
  InitializeData;
  try
    Found := False;
    for I := Low(DenseSizes) to High(DenseSizes) do
    begin
      CaseName := Format('hot-a0-a0-n%d', [DenseSizes[I]]);
      RunConfiguredCase(CaseName, DenseSizes[I], 0, 0, 0, mpHot,
        Profile, SelectedCase, Found);
    end;
    for I := Low(HugeHotSizes) to High(HugeHotSizes) do
    begin
      CaseName := Format('hot-a0-a0-n%d', [HugeHotSizes[I]]);
      RunConfiguredCase(CaseName, HugeHotSizes[I], 0, 0, 0, mpHot,
        Profile, SelectedCase, Found);
    end;
    for I := Low(AlignmentSizes) to High(AlignmentSizes) do
      for J := Low(AlignmentPairs) to High(AlignmentPairs) do
      begin
        CaseName := Format('hot-a%d-a%d-n%d', [AlignmentPairs[J, 0],
          AlignmentPairs[J, 1], AlignmentSizes[I]]);
        RunConfiguredCase(CaseName, AlignmentSizes[I], AlignmentPairs[J, 0],
          AlignmentPairs[J, 1], 0, mpHot, Profile, SelectedCase, Found);
      end;
    for I := Low(AlignmentSizes) to High(AlignmentSizes) do
      for J := Low(PageOffsetPairs) to High(PageOffsetPairs) do
      begin
        CaseName := Format('hot-a%d-a%d-n%d', [PageOffsetPairs[J, 0],
          PageOffsetPairs[J, 1], AlignmentSizes[I]]);
        RunConfiguredCase(CaseName, AlignmentSizes[I], PageOffsetPairs[J, 0],
          PageOffsetPairs[J, 1], 0, mpHot, Profile, SelectedCase, Found);
      end;
    for I := Low(OverlapSizes) to High(OverlapSizes) do
      for J := Low(OverlapDistances) to High(OverlapDistances) do
        If OverlapDistances[J] < OverlapSizes[I] then
          for K := 0 to 1 do
          begin
            If K = 0 then
              CaseName := Format('overlap-forward-d%d-n%d',
                [OverlapDistances[J], OverlapSizes[I]])
            else
              CaseName := Format('overlap-backward-d%d-n%d',
                [OverlapDistances[J], OverlapSizes[I]]);
            RunConfiguredCase(CaseName, OverlapSizes[I], 0, 0,
              OverlapDistances[J], TMovePattern(Ord(mpOverlapForward) + K),
              Profile, SelectedCase, Found);
          end;
    for I := Low(StreamingSizes) to High(StreamingSizes) do
    begin
      CaseName := Format('stream-a0-a0-n%d', [StreamingSizes[I]]);
      RunConfiguredCase(CaseName, StreamingSizes[I], 0, 0, 0, mpStream,
        Profile, SelectedCase, Found);
    end;
    PulseFinish('pulse_move', SelectedCase, Found);
  finally
    FinalizeData;
  end;
end.
