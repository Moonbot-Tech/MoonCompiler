program mm_crossmachine;

{ Cross-machine Delphi/FPC memory-manager comparison. CPU and slab
  calibrators are raw x86-64 assembly; only ABI register normalization differs. }

{$ifdef FPC}
  {$mode delphi}{$H+}
  {$asmmode Intel}
{$endif}
{$APPTYPE CONSOLE}
{$Q-}{$R-}

uses
{$ifdef FPC}
  {$ifdef USEMIMALLOC}
  mm_fpc_mimalloc,
  {$else}
  {$ifdef USELIBCMM}
  mormot.core.fpclibcmm,
  {$else}
  {$ifndef USEDEFAULTMM}
  mormot.core.fpcx64mm,
  {$endif}
  {$endif}
  {$endif}
  cthreads,
  Linux,
  UnixType,
{$else}
  {$ifdef USE_FASTMM5}
  FastMM5,
  {$endif}
  Winapi.Windows,
  System.SysUtils,
  System.Classes;
{$endif}
{$ifdef FPC}
  SysUtils,
  Classes;
{$endif}

const
  SampleCount = 7;
  FocusSampleCount = 3;
  DefaultScale = 100;
  DefaultSlabMB = 256;
  WorkerCount = 4;
  AppStringParts = 64;
  AppMinBytes = 32;
  AppSizeSpan = 481; // deterministic 32..512-byte working buffers
  ProfilePlanCount = 10000;
  ProfileReallocPerPlan = 1930;
  ProfileSlotCount = 2048;
  FixedSizes: array[0..11] of NativeUInt =
    (1, 8, 16, 24, 32, 40, 48, 56, 64, 128, 256, 512);
  HotSizes: array[0..3] of NativeUInt = (32, 56, 64, 128);
  TouchSizes: array[0..4] of NativeUInt = (32, 64, 128, 256, 512);

type
  TTimings = array[0..SampleCount - 1] of UInt64;
  TKernelKind = (kkSerial, kkParallel);
  TProfileShape = (psLow, psSpread, psHigh);
  TProfileSizePlan = array[0..ProfilePlanCount - 1] of NativeUInt;

var
  Sink: UInt64;
  ActiveSampleCount: Integer;
  ProfileGetPlans: array[TProfileShape] of TProfileSizePlan;
  ProfileReallocPlans: array[TProfileShape] of TProfileSizePlan;
  ProfileReallocAt: array[0..ProfilePlanCount - 1] of Boolean;
{$ifdef MSWINDOWS}
  TimerFrequency: Int64;
{$endif}

function ReadTimeNs: UInt64;
{$ifdef MSWINDOWS}
var
  Counter: Int64;
begin
  QueryPerformanceCounter(Counter);
  Result := UInt64(Counter div TimerFrequency) * UInt64(1000000000) +
    UInt64(Counter mod TimerFrequency) * UInt64(1000000000) div
    UInt64(TimerFrequency);
end;
{$else}
var
  Timestamp: UnixType.TTimeSpec;
begin
  If clock_gettime(CLOCK_MONOTONIC_RAW, @Timestamp) <> 0 then
    RaiseLastOSError;
  Result := UInt64(Timestamp.tv_sec) * UInt64(1000000000) +
    UInt64(Timestamp.tv_nsec);
end;
{$endif}

function AsmCpuSerial(Iterations: NativeUInt): UInt64;
  {$ifdef FPC} nostackframe; {$endif} assembler;
asm
        {$ifdef FPC}
        mov     rcx, rdi
        {$endif}
        mov     rax, $0123456789abcdef
        mov     rdx, $fedcba9876543210
        test    rcx, rcx
        jz      @done
        {$ifdef FPC}
        db      $0f, $1f, $40, $00
        {$else}
        db      $0f, $1f, $80, $00, $00, $00, $00
        {$endif}
@loop:  imul    rax, rax, 1664525
        add     rax, rdx
        ror     rax, 17
        xor     rdx, rax
        imul    rdx, rdx, 1103515245
        rol     rdx, 13
        xor     rax, rdx
        dec     rcx
        jnz     @loop
@done:  xor     rax, rdx
end;

function AsmCpuParallel(Iterations: NativeUInt): UInt64;
  {$ifdef FPC} nostackframe; {$endif} assembler;
asm
        {$ifdef FPC}
        mov     rcx, rdi
        {$endif}
        mov     rax, $0123456789abcdef
        mov     rdx, $fedcba9876543210
        mov     r8,  $d1b54a32d192ed03
        mov     r9,  $94d049bb133111eb
        test    rcx, rcx
        jz      @done
        {$ifndef FPC}
        db      $0f, $1f, $00
        {$endif}
@loop:  imul    rax, rax, 1664525
        imul    rdx, rdx, 1103515245
        imul    r8,  r8,  214013
        imul    r9,  r9,  134775813
        add     rax, $13579bdf
        add     rdx, $2468ace0
        add     r8,  $10203040
        add     r9,  $50607080
        dec     rcx
        jnz     @loop
@done:  xor     rax, rdx
        xor     rax, r8
        xor     rax, r9
end;

function AsmSlabCopy(Source, Dest: Pointer; Bytes, Passes: NativeUInt): UInt64;
  {$ifdef FPC} nostackframe; {$endif} assembler;
asm
        {$ifdef FPC}
        mov     r10, rdi
        mov     r11, rsi
        mov     r8, rdx
        mov     r9, rcx
        {$else}
        mov     r10, rcx
        mov     r11, rdx
        {$endif}
        test    r9, r9
        jz      @done
@pass:  xor     rax, rax
        {$ifdef FPC}
        db      $66, $0f, $1f, $44, $00, $00
        db      $66, $0f, $1f, $44, $00, $00
        {$else}
        db      $66, $90
        {$endif}
@copy:  movdqu  xmm0, [r10 + rax]
        movdqu  xmm1, [r10 + rax + 16]
        movdqu  xmm2, [r10 + rax + 32]
        movdqu  xmm3, [r10 + rax + 48]
        movdqu  [r11 + rax], xmm0
        movdqu  [r11 + rax + 16], xmm1
        movdqu  [r11 + rax + 32], xmm2
        movdqu  [r11 + rax + 48], xmm3
        add     rax, 64
        cmp     rax, r8
        jb      @copy
        xchg    r10, r11
        dec     r9
        jnz     @pass
@done:  mov     rax, [r10]
end;

function Median(const Values: TTimings): UInt64;
var
  Sorted: TTimings;
  I, J: Integer;
  Value: UInt64;
begin
  Sorted := Values;
  for I := 1 to ActiveSampleCount - 1 do begin
    Value := Sorted[I];
    J := I - 1;
    while (J >= 0) and (Sorted[J] > Value) do begin
      Sorted[J + 1] := Sorted[J];
      Dec(J);
    end;
    Sorted[J + 1] := Value;
  end;
  Result := Sorted[ActiveSampleCount div 2];
end;

type
  TKernelThread = class(TThread)
  private
    FKind: TKernelKind;
    FIterations: NativeUInt;
  public
    Digest: UInt64;
    ElapsedNs: UInt64;
    constructor Create(AKind: TKernelKind; AIterations: NativeUInt);
  protected
    procedure Execute; override;
  end;

constructor TKernelThread.Create(AKind: TKernelKind; AIterations: NativeUInt);
begin
  inherited Create(True);
  FKind := AKind;
  FIterations := AIterations;
end;

procedure TKernelThread.Execute;
var
  Started: UInt64;
begin
  Started := ReadTimeNs;
  case FKind of
    kkSerial: Digest := AsmCpuSerial(FIterations);
    kkParallel: Digest := AsmCpuParallel(FIterations);
  end;
  ElapsedNs := ReadTimeNs - Started;
end;

function RunKernel(Kind: TKernelKind; Iterations: NativeUInt): UInt64;
begin
  case Kind of
    kkSerial: Result := AsmCpuSerial(Iterations);
  else
    Result := AsmCpuParallel(Iterations);
  end;
end;

function RunKernelThreads(Kind: TKernelKind; Iterations: NativeUInt;
  out Digest: UInt64): UInt64;
var
  Workers: array[0..WorkerCount - 1] of TKernelThread;
  I: Integer;
begin
  for I := 0 to High(Workers) do
    Workers[I] := TKernelThread.Create(Kind, Iterations);
  for I := 0 to High(Workers) do
    Workers[I].Start;
  for I := 0 to High(Workers) do
    Workers[I].WaitFor;
  Result := 0;
  Digest := 0;
  for I := 0 to High(Workers) do begin
    If Workers[I].ElapsedNs > Result then
      Result := Workers[I].ElapsedNs;
    Digest := Digest + Workers[I].Digest;
    Workers[I].Free;
  end;
end;

procedure MeasureKernel(const Name: string; Kind: TKernelKind;
  Iterations: NativeUInt; Threads: Integer);
var
  Samples: TTimings;
  Digest, Elapsed: UInt64;
  I: Integer;
begin
  If Threads = 1 then
    Digest := RunKernel(Kind, Iterations div 32 + 1)
  else
    RunKernelThreads(Kind, Iterations div 32 + 1, Digest);
  for I := 0 to ActiveSampleCount - 1 do begin
    If Threads = 1 then begin
      Elapsed := ReadTimeNs;
      Digest := RunKernel(Kind, Iterations);
      Samples[I] := ReadTimeNs - Elapsed;
    end else
      Samples[I] := RunKernelThreads(Kind, Iterations, Digest);
    Sink := Sink xor Digest;
  end;
  Elapsed := Median(Samples);
  WriteLn(Format('CAL name=%s threads=%d iterations=%d median_ns=%d '+
    'ns_per_worker_iter=%.4f digest=%s',
    [Name, Threads, Iterations, Elapsed, Elapsed / Iterations,
     IntToHex(Digest, 16)]));
end;

procedure MeasureSlab(Bytes, Passes: NativeUInt);
var
  Source, Dest: Pointer;
  Samples: TTimings;
  Digest, Elapsed, TotalBytes: UInt64;
  I: Integer;
begin
  GetMem(Source, Bytes);
  GetMem(Dest, Bytes);
  try
    FillChar(Source^, Bytes, $5a);
    FillChar(Dest^, Bytes, $a5);
    Digest := AsmSlabCopy(Source, Dest, Bytes, 1);
    Sink := Sink xor Digest;
    for I := 0 to ActiveSampleCount - 1 do begin
      Elapsed := ReadTimeNs;
      Digest := AsmSlabCopy(Source, Dest, Bytes, Passes);
      Samples[I] := ReadTimeNs - Elapsed;
      Sink := Sink xor Digest;
    end;
    Elapsed := Median(Samples);
    TotalBytes := UInt64(Bytes) * Passes;
    WriteLn(Format('CAL name=slab-copy threads=1 bytes=%d passes=%d '+
      'median_ns=%d gib_per_s=%.3f digest=%s',
      [Bytes, Passes, Elapsed,
       TotalBytes / Elapsed * (1000000000.0 / 1073741824.0),
       IntToHex(Digest, 16)]));
  finally
    FreeMem(Source);
    FreeMem(Dest);
  end;
end;

procedure AllocRing(SmallOnly: Boolean; var Digest: UInt64);
var
  Fragments: array[0..999] of Pointer;
  A, B, C: PByte;
  I: Integer;
begin
  for I := 0 to High(Fragments) do begin
    If SmallOnly then begin
      GetMem(A, 1200);
      GetMem(B, 256);
      GetMem(C, 800);
    end else begin
      GetMem(A, 100500);
      GetMem(B, 800);
      GetMem(C, 9000);
    end;
    A[0] := Byte(I);
    B[0] := Byte(I shr 1);
    C[0] := Byte(I xor $a5);
    Digest := Digest + A[0] + B[0] + C[0];
    FreeMem(A);
    If SmallOnly then
      GetMem(Fragments[I], 320)
    else
      GetMem(Fragments[I], 800);
    PByte(Fragments[I])^ := Byte(I);
    FreeMem(B);
    FreeMem(C);
  end;
  for I := 0 to High(Fragments) do begin
    Digest := Digest + PByte(Fragments[I])^;
    FreeMem(Fragments[I]);
  end;
end;

procedure AppMixWork(Rounds: Integer; var Digest: UInt64);
var
  Buffer: PByte;
  Text, Token, Prefix: string;
  Local: UInt64;
  RoundIndex, Part, Index, TextLength, Size: Integer;
begin
  Local := Digest xor UInt64($9e3779b97f4a7c15);
  for RoundIndex := 1 to Rounds do begin
    Text := '';
    Prefix := IntToStr(RoundIndex);
    for Part := 1 to AppStringParts do begin
      Token := IntToStr(Part);
      Text := Token + Text;
      Text := '  ' + Text;
      Text := Prefix + Text;
    end;
    TextLength := Length(Text);
    Size := AppMinBytes + RoundIndex * 73 mod AppSizeSpan;
    GetMem(Buffer, Size);
    try
      for Index := 0 to Size - 1 do
        Buffer[Index] := Byte((Index * 17 + RoundIndex +
          Ord(Text[Index mod TextLength + 1])) and $ff);
      for Index := 0 to Size - 1 do
        Local := ((Local shl 7) or (Local shr 57)) xor
          (UInt64(Buffer[Index]) + UInt64(Index));
    finally
      FreeMem(Buffer);
    end;
    Local := Local xor UInt64(TextLength) xor UInt64(Ord(Text[TextLength]));
  end;
  Digest := Local;
end;

type
  TAppMixThread = class(TThread)
  private
    FRounds: Integer;
  public
    Digest: UInt64;
    ElapsedNs: UInt64;
    constructor Create(ARounds: Integer);
  protected
    procedure Execute; override;
  end;

constructor TAppMixThread.Create(ARounds: Integer);
begin
  inherited Create(True);
  FRounds := ARounds;
end;

procedure TAppMixThread.Execute;
var
  Started: UInt64;
begin
  Started := ReadTimeNs;
  AppMixWork(FRounds, Digest);
  ElapsedNs := ReadTimeNs - Started;
end;

function RunAppMix(Rounds, Threads: Integer; out Digest: UInt64): UInt64;
var
  Workers: array of TAppMixThread;
  Started: UInt64;
  I: Integer;
begin
  If Threads = 1 then begin
    Digest := 0;
    Started := ReadTimeNs;
    AppMixWork(Rounds, Digest);
    Result := ReadTimeNs - Started;
    Exit;
  end;
  SetLength(Workers, Threads);
  for I := 0 to High(Workers) do
    Workers[I] := TAppMixThread.Create(Rounds);
  for I := 0 to High(Workers) do
    Workers[I].Start;
  for I := 0 to High(Workers) do
    Workers[I].WaitFor;
  Result := 0;
  Digest := 0;
  for I := 0 to High(Workers) do begin
    If Workers[I].ElapsedNs > Result then
      Result := Workers[I].ElapsedNs;
    Digest := Digest + Workers[I].Digest;
    Workers[I].Free;
  end;
end;

procedure MeasureAppMix(Rounds, Threads: Integer);
var
  Samples: TTimings;
  Digest, Elapsed: UInt64;
  I: Integer;
begin
  RunAppMix(Rounds div 20 + 1, Threads, Digest);
  for I := 0 to ActiveSampleCount - 1 do begin
    Samples[I] := RunAppMix(Rounds, Threads, Digest);
    Sink := Sink xor Digest;
  end;
  Elapsed := Median(Samples);
  WriteLn(Format('MM name=app-mix threads=%d rounds=%d median_ns=%d '+
    'ns_per_worker_round=%.4f digest=%s',
    [Threads, Rounds, Elapsed, Elapsed / Rounds,
     IntToHex(Digest, 16)]));
end;

function ProfileBucketSize(Offset, First, Last: NativeUInt;
  Shape: TProfileShape): NativeUInt;
begin
  case Shape of
    psLow:
      Result := First;
    psHigh:
      Result := Last;
  else
    Result := First + Offset * 40503 mod (Last - First + 1);
  end;
end;

function ProfileGetSize(Position: NativeUInt;
  Shape: TProfileShape): NativeUInt;
begin
  If Position < 9103 then
    Result := ProfileBucketSize(Position, 1, 64, Shape)
  else If Position < 9538 then
    Result := ProfileBucketSize(Position - 9103, 65, 128, Shape)
  else If Position < 9858 then
    Result := ProfileBucketSize(Position - 9538, 129, 256, Shape)
  else If Position < 9969 then
    Result := ProfileBucketSize(Position - 9858, 257, 512, Shape)
  else If Position < 9979 then
    Result := ProfileBucketSize(Position - 9969, 513, 1200, Shape)
  else If Position < 9987 then
    Result := ProfileBucketSize(Position - 9979, 1201, 2600, Shape)
  else If Position < 9994 then
    Result := ProfileBucketSize(Position - 9987, 2601, 9000, Shape)
  else If Position < 9998 then
    Result := ProfileBucketSize(Position - 9994, 9001, 65536, Shape)
  else If Position < 9999 then
    Result := ProfileBucketSize(0, 65537, 262144, Shape)
  else
    Result := ProfileBucketSize(0, 262145, 524288, Shape);
end;

function ProfileReallocSize(Position: NativeUInt;
  Shape: TProfileShape): NativeUInt;
begin
  If Position < 8056 then
    Result := ProfileBucketSize(Position, 1, 64, Shape)
  else If Position < 8428 then
    Result := ProfileBucketSize(Position - 8056, 65, 128, Shape)
  else If Position < 8651 then
    Result := ProfileBucketSize(Position - 8428, 129, 256, Shape)
  else If Position < 8767 then
    Result := ProfileBucketSize(Position - 8651, 257, 512, Shape)
  else If Position < 8953 then
    Result := ProfileBucketSize(Position - 8767, 513, 1200, Shape)
  else If Position < 9021 then
    Result := ProfileBucketSize(Position - 8953, 1201, 2600, Shape)
  else If Position < 9266 then
    Result := ProfileBucketSize(Position - 9021, 2601, 9000, Shape)
  else If Position < 9992 then
    Result := ProfileBucketSize(Position - 9266, 9001, 65536, Shape)
  else If Position < 9997 then
    Result := ProfileBucketSize(Position - 9992, 65537, 262144, Shape)
  else
    Result := ProfileBucketSize(Position - 9997, 262145, 524288, Shape);
end;

procedure InitProfilePlans;
var
  Shape: TProfileShape;
  Position: Integer;
  ReallocAccumulator: Integer;
begin
  for Shape := Low(TProfileShape) to High(TProfileShape) do
    for Position := 0 to ProfilePlanCount - 1 do begin
      ProfileGetPlans[Shape][Position] := ProfileGetSize(Position, Shape);
      ProfileReallocPlans[Shape][Position] :=
        ProfileReallocSize(Position, Shape);
    end;
  ReallocAccumulator := 0;
  for Position := 0 to ProfilePlanCount - 1 do begin
    Inc(ReallocAccumulator, ProfileReallocPerPlan);
    ProfileReallocAt[Position] := ReallocAccumulator >= ProfilePlanCount;
    If ProfileReallocAt[Position] then
      Dec(ReallocAccumulator, ProfilePlanCount);
  end;
end;

procedure ProfileWork(Plans: Integer; Shape: TProfileShape;
  var Digest: UInt64);
var
  Pointers: array[0..ProfileSlotCount - 1] of Pointer;
  Sizes: array[0..ProfileSlotCount - 1] of NativeUInt;
  P: Pointer;
  Size, I, Total, Slot, PlanPosition, ReallocPosition: NativeUInt;
begin
  FillChar(Pointers, SizeOf(Pointers), 0);
  FillChar(Sizes, SizeOf(Sizes), 0);
  Total := NativeUInt(Plans) * ProfilePlanCount;
  PlanPosition := 0;
  ReallocPosition := 0;
  for I := 0 to Total - 1 do begin
    Size := ProfileGetPlans[Shape][PlanPosition];
    GetMem(P, Size);
    PByte(P)[0] := Byte(I);
    PByte(P)[Size - 1] := Byte(I shr 8);

    If ProfileReallocAt[PlanPosition] then begin
      Size := ProfileReallocPlans[Shape][ReallocPosition];
      ReallocMem(P, Size);
      PByte(P)[Size - 1] := Byte(I shr 16);
      Inc(ReallocPosition);
      If ReallocPosition = ProfilePlanCount then
        ReallocPosition := 0;
    end;

    Slot := I and (ProfileSlotCount - 1);
    If Pointers[Slot] <> nil then begin
      Digest := Digest + PByte(Pointers[Slot])[0] +
        PByte(Pointers[Slot])[Sizes[Slot] - 1];
      FreeMem(Pointers[Slot]);
    end;
    Pointers[Slot] := P;
    Sizes[Slot] := Size;

    Inc(PlanPosition);
    If PlanPosition = ProfilePlanCount then
      PlanPosition := 0;
  end;
  for Slot := 0 to High(Pointers) do
    If Pointers[Slot] <> nil then begin
      Digest := Digest + PByte(Pointers[Slot])[0] +
        PByte(Pointers[Slot])[Sizes[Slot] - 1];
      FreeMem(Pointers[Slot]);
    end;
end;

type
  TProfileThread = class(TThread)
  private
    FPlans: Integer;
    FShape: TProfileShape;
  public
    Digest: UInt64;
    ElapsedNs: UInt64;
    constructor Create(APlans: Integer; AShape: TProfileShape);
  protected
    procedure Execute; override;
  end;

constructor TProfileThread.Create(APlans: Integer; AShape: TProfileShape);
begin
  inherited Create(True);
  FPlans := APlans;
  FShape := AShape;
end;

procedure TProfileThread.Execute;
var
  Started: UInt64;
begin
  Started := ReadTimeNs;
  ProfileWork(FPlans, FShape, Digest);
  ElapsedNs := ReadTimeNs - Started;
end;

function RunProfile(Plans, Threads: Integer; Shape: TProfileShape;
  out Digest: UInt64): UInt64;
var
  Workers: array of TProfileThread;
  Started: UInt64;
  I: Integer;
begin
  If Threads = 1 then begin
    Digest := 0;
    Started := ReadTimeNs;
    ProfileWork(Plans, Shape, Digest);
    Result := ReadTimeNs - Started;
    Exit;
  end;
  SetLength(Workers, Threads);
  for I := 0 to High(Workers) do
    Workers[I] := TProfileThread.Create(Plans, Shape);
  for I := 0 to High(Workers) do
    Workers[I].Start;
  for I := 0 to High(Workers) do
    Workers[I].WaitFor;
  Result := 0;
  Digest := 0;
  for I := 0 to High(Workers) do begin
    If Workers[I].ElapsedNs > Result then
      Result := Workers[I].ElapsedNs;
    Digest := Digest + Workers[I].Digest;
    Workers[I].Free;
  end;
end;

procedure MeasureProfile(const Name: string; Plans, Threads: Integer;
  Shape: TProfileShape);
var
  Samples: TTimings;
  Digest, Elapsed, Actions: UInt64;
  I: Integer;
begin
  RunProfile(Plans div 20 + 1, Threads, Shape, Digest);
  for I := 0 to ActiveSampleCount - 1 do begin
    Samples[I] := RunProfile(Plans, Threads, Shape, Digest);
    Sink := Sink xor Digest;
  end;
  Elapsed := Median(Samples);
  Actions := UInt64(Plans) * ProfilePlanCount;
  WriteLn(Format('MM name=%s threads=%d plans=%d median_ns=%d '+
    'ns_per_worker_action=%.4f digest=%s',
    [Name, Threads, Plans, Elapsed, Elapsed / Actions,
     IntToHex(Digest, 16)]));
end;

procedure FixedWork(Actions: Integer; BlockSize: NativeUInt;
  KeepLive, TouchAll: Boolean; var Digest: UInt64);
var
  Pointers: array[0..ProfileSlotCount - 1] of Pointer;
  P: Pointer;
  Local: UInt64;
  I, Slot: NativeUInt;
begin
  If not KeepLive then begin
    If TouchAll then begin
      Local := Digest xor UInt64($9e3779b97f4a7c15);
      for I := 0 to NativeUInt(Actions) - 1 do begin
        GetMem(P, BlockSize);
        for Slot := 0 to BlockSize - 1 do
          PByte(P)[Slot] := Byte(I + Slot * 17);
        for Slot := 0 to BlockSize - 1 do
          Local := ((Local shl 7) or (Local shr 57)) xor PByte(P)[Slot];
        Local := Local * UInt64($100000001b3) + I + BlockSize;
        FreeMem(P);
      end;
      Digest := Local;
    end else begin
      for I := 0 to NativeUInt(Actions) - 1 do begin
        GetMem(P, BlockSize);
        PByte(P)[0] := Byte(I);
        PByte(P)[BlockSize - 1] := Byte(I shr 8);
        Digest := Digest + PByte(P)[0] + PByte(P)[BlockSize - 1];
        FreeMem(P);
      end;
    end;
    Exit;
  end;
  FillChar(Pointers, SizeOf(Pointers), 0);
  for I := 0 to NativeUInt(Actions) - 1 do begin
    GetMem(P, BlockSize);
    PByte(P)[0] := Byte(I);
    PByte(P)[BlockSize - 1] := Byte(I shr 8);
    Slot := I and (ProfileSlotCount - 1);
    If Pointers[Slot] <> nil then begin
      Digest := Digest + PByte(Pointers[Slot])[0] +
        PByte(Pointers[Slot])[BlockSize - 1];
      FreeMem(Pointers[Slot]);
    end;
    Pointers[Slot] := P;
  end;
  for Slot := 0 to High(Pointers) do
    If Pointers[Slot] <> nil then begin
      Digest := Digest + PByte(Pointers[Slot])[0] +
        PByte(Pointers[Slot])[BlockSize - 1];
      FreeMem(Pointers[Slot]);
    end;
end;

type
  TFixedThread = class(TThread)
  private
    FActions: Integer;
    FBlockSize: NativeUInt;
    FKeepLive: Boolean;
    FTouchAll: Boolean;
  public
    Digest: UInt64;
    ElapsedNs: UInt64;
    constructor Create(AActions: Integer; ABlockSize: NativeUInt;
      AKeepLive, ATouchAll: Boolean);
  protected
    procedure Execute; override;
  end;

constructor TFixedThread.Create(AActions: Integer; ABlockSize: NativeUInt;
  AKeepLive, ATouchAll: Boolean);
begin
  inherited Create(True);
  FActions := AActions;
  FBlockSize := ABlockSize;
  FKeepLive := AKeepLive;
  FTouchAll := ATouchAll;
end;

procedure TFixedThread.Execute;
var
  Started: UInt64;
begin
  Started := ReadTimeNs;
  FixedWork(FActions, FBlockSize, FKeepLive, FTouchAll, Digest);
  ElapsedNs := ReadTimeNs - Started;
end;

function RunFixed(Actions, Threads: Integer; BlockSize: NativeUInt;
  KeepLive, TouchAll: Boolean; out Digest: UInt64): UInt64;
var
  Workers: array of TFixedThread;
  Started: UInt64;
  I: Integer;
begin
  If Threads = 1 then begin
    Digest := 0;
    Started := ReadTimeNs;
    FixedWork(Actions, BlockSize, KeepLive, TouchAll, Digest);
    Result := ReadTimeNs - Started;
    Exit;
  end;
  SetLength(Workers, Threads);
  for I := 0 to High(Workers) do
    Workers[I] := TFixedThread.Create(Actions, BlockSize, KeepLive, TouchAll);
  for I := 0 to High(Workers) do
    Workers[I].Start;
  for I := 0 to High(Workers) do
    Workers[I].WaitFor;
  Result := 0;
  Digest := 0;
  for I := 0 to High(Workers) do begin
    If Workers[I].ElapsedNs > Result then
      Result := Workers[I].ElapsedNs;
    Digest := Digest + Workers[I].Digest;
    Workers[I].Free;
  end;
end;

procedure MeasureFixed(Actions, Threads: Integer; BlockSize: NativeUInt;
  KeepLive, TouchAll: Boolean);
var
  Samples: TTimings;
  Digest, Elapsed: UInt64;
  I: Integer;
  Name: string;
begin
  RunFixed(Actions div 20 + 1, Threads, BlockSize, KeepLive, TouchAll, Digest);
  for I := 0 to ActiveSampleCount - 1 do begin
    Samples[I] := RunFixed(Actions, Threads, BlockSize, KeepLive, TouchAll,
      Digest);
    Sink := Sink xor Digest;
  end;
  Elapsed := Median(Samples);
  If KeepLive then
    Name := 'fixed-' + IntToStr(BlockSize)
  else If TouchAll then
    Name := 'touch-ping-' + IntToStr(BlockSize)
  else
    Name := 'hot-ping-' + IntToStr(BlockSize);
  WriteLn(Format('MM name=%s threads=%d actions=%d median_ns=%d '+
    'ns_per_worker_action=%.4f digest=%s',
    [Name, Threads, Actions, Elapsed, Elapsed / Actions,
     IntToHex(Digest, 16)]));
end;

type
  TAllocThread = class(TThread)
  private
    FRounds: Integer;
    FSmallOnly: Boolean;
  public
    Digest: UInt64;
    ElapsedNs: UInt64;
    constructor Create(ARounds: Integer; ASmallOnly: Boolean);
  protected
    procedure Execute; override;
  end;

constructor TAllocThread.Create(ARounds: Integer; ASmallOnly: Boolean);
begin
  inherited Create(True);
  FRounds := ARounds;
  FSmallOnly := ASmallOnly;
end;

procedure TAllocThread.Execute;
var
  I: Integer;
  Started: UInt64;
begin
  Started := ReadTimeNs;
  for I := 1 to FRounds do
    AllocRing(FSmallOnly, Digest);
  ElapsedNs := ReadTimeNs - Started;
end;

function RunAlloc(Rounds, Threads: Integer; SmallOnly: Boolean;
  out Digest: UInt64): UInt64;
var
  Workers: array of TAllocThread;
  Started: UInt64;
  I: Integer;
begin
  If Threads = 1 then begin
    Digest := 0;
    Started := ReadTimeNs;
    for I := 1 to Rounds do
      AllocRing(SmallOnly, Digest);
    Result := ReadTimeNs - Started;
    Exit;
  end;
  SetLength(Workers, Threads);
  for I := 0 to High(Workers) do
    Workers[I] := TAllocThread.Create(Rounds, SmallOnly);
  for I := 0 to High(Workers) do
    Workers[I].Start;
  for I := 0 to High(Workers) do
    Workers[I].WaitFor;
  Result := 0;
  Digest := 0;
  for I := 0 to High(Workers) do begin
    If Workers[I].ElapsedNs > Result then
      Result := Workers[I].ElapsedNs;
    Digest := Digest + Workers[I].Digest;
    Workers[I].Free;
  end;
end;

procedure MeasureAlloc(const Name: string; Rounds, Threads: Integer;
  SmallOnly: Boolean);
var
  Samples: TTimings;
  Digest, Elapsed, Operations: UInt64;
  I: Integer;
begin
  RunAlloc(Rounds div 20 + 1, Threads, SmallOnly, Digest);
  for I := 0 to ActiveSampleCount - 1 do begin
    Samples[I] := RunAlloc(Rounds, Threads, SmallOnly, Digest);
    Sink := Sink xor Digest;
  end;
  Elapsed := Median(Samples);
  Operations := UInt64(Rounds) * 1000 * 8;
  WriteLn(Format('MM name=%s threads=%d rounds=%d median_ns=%d '+
    'ns_per_worker_op=%.4f digest=%s',
    [Name, Threads, Rounds, Elapsed, Elapsed / Operations,
     IntToHex(Digest, 16)]));
end;

function Scaled(Value, Scale: Integer): Integer;
begin
  Result := Integer(Int64(Value) * Scale div 100);
  If Result < 1 then
    Result := 1;
end;

var
  Scale, SlabMB, Code, SizeIndex: Integer;
  FocusOnly: Boolean;
  CpuSerialIterations, CpuParallelIterations: NativeUInt;
  SlabBytes, SlabPasses: NativeUInt;
  AllocRounds, ThreadRounds: Integer;
begin
  try
    Scale := DefaultScale;
    SlabMB := DefaultSlabMB;
    If ParamCount > 0 then begin
      Val(ParamStr(1), Scale, Code);
      If (Code <> 0) or (Scale < 1) then
        Scale := DefaultScale;
    end;
    If ParamCount > 1 then begin
      Val(ParamStr(2), SlabMB, Code);
      If (Code <> 0) or (SlabMB < 64) then
        SlabMB := DefaultSlabMB;
    end;
    FocusOnly := SameText(ParamStr(3), 'focus');
    If FocusOnly then
      ActiveSampleCount := FocusSampleCount
    else
      ActiveSampleCount := SampleCount;
    {$ifdef MSWINDOWS}
    If not QueryPerformanceFrequency(TimerFrequency) then
      RaiseLastOSError;
    {$endif}
    InitProfilePlans;
    CpuSerialIterations := Scaled(100000000, Scale);
    CpuParallelIterations := Scaled(50000000, Scale);
    SlabBytes := NativeUInt(SlabMB) * 1024 * 1024;
    SlabPasses := Scaled(16, Scale);
    AllocRounds := Scaled(3000, Scale);
    ThreadRounds := Scaled(1500, Scale);

    {$ifdef FPC}
    WriteLn('CROSS_MACHINE compiler=FPC-', {$I %FPCVERSION%},
      ' os=', {$I %FPCTARGETOS%},
      {$ifdef USEMIMALLOC} ' mm=mimalloc-v3.3.2 scale=',
      {$else} {$ifdef USELIBCMM} ' mm=glibc scale=',
      {$else} {$ifdef USEDEFAULTMM} ' mm=FPC-default scale=',
      {$else} ' mm=fpcx64mm scale=', {$endif} {$endif} {$endif} Scale,
      ' slab_mb=', SlabMB);
    {$else}
    {$ifdef USE_FASTMM5}
    WriteLn('CROSS_MACHINE compiler=Delphi-', CompilerVersion:0:1,
      ' os=Windows mm=FastMM5-', CFastMM_Version, ' scale=', Scale,
      ' slab_mb=', SlabMB);
    {$else}
    WriteLn('CROSS_MACHINE compiler=Delphi-', CompilerVersion:0:1,
      ' os=Windows mm=default scale=', Scale, ' slab_mb=', SlabMB);
    {$endif}
    {$endif}

    MeasureKernel('cpu-serial', kkSerial, CpuSerialIterations, 1);
    MeasureKernel('cpu-ilp4', kkParallel, CpuParallelIterations, 1);
    MeasureKernel('cpu-serial', kkSerial, CpuSerialIterations, WorkerCount);
    MeasureKernel('cpu-ilp4', kkParallel, CpuParallelIterations, WorkerCount);
    If FocusOnly then
      WriteLn('MODE focus')
    else begin
      MeasureSlab(SlabBytes, SlabPasses);
      MeasureAlloc('mix', AllocRounds, 1, False);
      MeasureAlloc('small', AllocRounds, 1, True);
      MeasureAlloc('mix', ThreadRounds, WorkerCount, False);
      MeasureAlloc('small', ThreadRounds, WorkerCount, True);
    end;
    MeasureAppMix(Scaled(5000, Scale), 1);
    MeasureAppMix(Scaled(2500, Scale), WorkerCount);
    If FocusOnly then begin
      MeasureProfile('moonbot-spread', Scaled(300, Scale), 1, psSpread);
      MeasureProfile('moonbot-spread', Scaled(150, Scale), WorkerCount,
        psSpread);
    end else begin
      MeasureProfile('moonbot-low', Scaled(300, Scale), 1, psLow);
      MeasureProfile('moonbot-spread', Scaled(300, Scale), 1, psSpread);
      MeasureProfile('moonbot-high', Scaled(300, Scale), 1, psHigh);
      MeasureProfile('moonbot-low', Scaled(150, Scale), WorkerCount, psLow);
      MeasureProfile('moonbot-spread', Scaled(150, Scale), WorkerCount,
        psSpread);
      MeasureProfile('moonbot-high', Scaled(150, Scale), WorkerCount, psHigh);
      for SizeIndex := 0 to High(FixedSizes) do
        MeasureFixed(Scaled(3000000, Scale), 1, FixedSizes[SizeIndex], True,
          False);
      for SizeIndex := 0 to High(FixedSizes) do
        MeasureFixed(Scaled(1500000, Scale), WorkerCount,
          FixedSizes[SizeIndex], True, False);
    end;
    for SizeIndex := 0 to High(HotSizes) do
      MeasureFixed(Scaled(3000000, Scale), 1, HotSizes[SizeIndex], False,
        False);
    for SizeIndex := 0 to High(HotSizes) do
      MeasureFixed(Scaled(1500000, Scale), WorkerCount,
        HotSizes[SizeIndex], False, False);
    for SizeIndex := 0 to High(TouchSizes) do
      MeasureFixed(Scaled(50000, Scale), 1, TouchSizes[SizeIndex], False,
        True);
    for SizeIndex := 0 to High(TouchSizes) do
      MeasureFixed(Scaled(25000, Scale), WorkerCount,
        TouchSizes[SizeIndex], False, True);
    WriteLn('DONE sink=', IntToHex(Sink, 16));
  except
    on E: Exception do begin
      WriteLn('FAIL ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
