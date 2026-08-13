program memspeed;

{ Cross-machine memory-manager speed test, reworked to be machine-comparable.

  Direct wall-times are NOT comparable across boxes. This tool prints:
  - CAL-INT: pure ALU loop, zero allocations  -> hardware CPU baseline
  - CAL-BW : big Move() bandwidth             -> hardware RAM baseline
  - STR    : the classic string concat storm  (small realloc torture)
  - ALLOC  : small/med/large GetMem/FreeMem pattern with a frag ring
  - THR    : the same ALLOC pattern in 4 threads (MM lock contention)
  and two dimensionless MM indices:
      IdxStr   = STR   / CAL-INT
      IdxAlloc = ALLOC / CAL-INT
  Compare the INDICES between machines/managers, not the times.
  Hardware coefficient between two boxes: K = CAL-INT(B) / CAL-INT(A);
  expected STR on B if the MM were equal = STR(A) * K; the excess over
  that is the memory manager's own lag (the old EurekaLog-MM effect:
  loEnableMMDebugMode=1 multiplied exactly these workloads).

  Build (Delphi): dcc64 -B -CC -NSSystem -U<lib\win64\release> memspeed.dpr
  Build (FPC):    fpc -n @<toolchain>/etc/fpc.cfg -Mdelphi -O2 memspeed.dpr
  Optional arg: scale percent (default 100), e.g. "memspeed 25" for 1/4. }

{$ifdef FPC}
  {$mode delphi}{$H+}
{$endif}
{$APPTYPE CONSOLE}
{$Q-}{$R-}

uses
{$ifdef USEX64MM}
  mormot.core.fpcx64mm,                { must be the first unit }
{$endif}
{$ifdef USECMEM}
  cmem,                                { glibc malloc (FPC only) }
{$endif}
{$ifdef USESCALEMM}
  ScaleMM2,                            { Windows only }
{$endif}
{$ifdef FPC}
  cthreads,
{$else}
  Winapi.Windows,
{$endif}
  SysUtils, Classes;

var
  Sink: UInt64 = 0;                    { folds results: keeps loops alive }
  Scale: Integer = 100;

function Min3(A, B, C: Int64): Int64;
begin
  Result := A;
  if B < Result then
    Result := B;
  if C < Result then
    Result := C;
end;

{ ---------------- CAL-INT: pure ALU, no allocations ---------------- }

function CalIntOnce(Steps: Integer): Int64;
var
  X: UInt64;
  K: Integer;
  T0: Int64;
begin
  T0 := Int64(GetTickCount64);
  X := UInt64($2545F4914F6CDD1D);
  for K := 1 to Steps do
  begin
    X := X xor (X shr 12);
    X := X xor (X shl 25);
    X := X xor (X shr 27);
    X := X * UInt64($9E3779B97F4A7C15);
  end;
  Sink := Sink xor X;
  Result := Int64(GetTickCount64) - T0;
end;

{ ---------------- CAL-BW: memory bandwidth via Move ---------------- }

function CalBWOnce(MB, Reps: Integer): Int64;
var
  A, B: PByte;
  Bytes: NativeInt;
  K: Integer;
  T0: Int64;
begin
  Bytes := NativeInt(MB) * 1024 * 1024;
  GetMem(A, Bytes);
  GetMem(B, Bytes);
  FillChar(A^, Bytes, $5A);
  T0 := Int64(GetTickCount64);
  for K := 1 to Reps do
  begin
    Move(A^, B^, Bytes);
    Move(B^, A^, Bytes);
  end;
  Result := Int64(GetTickCount64) - T0;
  Sink := Sink xor A[Bytes div 2];
  FreeMem(A);
  FreeMem(B);
end;

{ -------- STR: the MemManagerTest concat storm (AnsiString) -------- }

function StrStormOnce(Outer, Inner: Integer): Int64;
var
  s1, s2: AnsiString;
  k, j: Integer;
  L: Int64;
  T0: Int64;
begin
  T0 := Int64(GetTickCount64);
  L := 0;
  for k := 1 to Outer do
  begin
    s1 := '';
    for j := 1 to Inner do
    begin
      s2 := AnsiString(IntToStr(j));
      s1 := s2 + s1;
      s1 := AnsiString('  ') + s1;
      s1 := AnsiString(IntToStr(k)) + s1;
    end;
    L := L + Length(s1);
  end;
  Sink := Sink xor UInt64(L);
  Result := Int64(GetTickCount64) - T0;
end;

{ ------- ALLOC: MemTest small/med/large pattern + frag ring -------- }

procedure AllocRing;
var
  pFrag: array[1..1000] of Pointer;
  pLarge, pMed, pSmall: Pointer;
  k: Integer;
begin
  for k := 1 to 1000 do
  begin
    GetMem(pLarge, 100500);
    GetMem(pSmall, 800);
    GetMem(pMed, 9000);
    PByte(pLarge)^ := Byte(k);         { touch the pages }
    PByte(pMed)^ := Byte(k);
    PByte(pSmall)^ := Byte(k);
    FreeMem(pLarge);
    GetMem(pFrag[k], 800);
    PByte(pFrag[k])^ := Byte(k);
    FreeMem(pSmall);
    FreeMem(pMed);
  end;
  for k := 1 to 1000 do
    FreeMem(pFrag[k]);
end;

function AllocOnce(Rounds: Integer): Int64;
var
  r: Integer;
  T0: Int64;
begin
  T0 := Int64(GetTickCount64);
  for r := 1 to Rounds do
    AllocRing;
  Result := Int64(GetTickCount64) - T0;
end;

{ small-only ring: every block fits the small-block pools (<= 1200 b),
  no medium allocations at all — isolates the medium-lock question }

procedure AllocRingSmall;
var
  pFrag: array[1..1000] of Pointer;
  pA, pB, pC: Pointer;
  k: Integer;
begin
  for k := 1 to 1000 do
  begin
    GetMem(pA, 1200);
    GetMem(pB, 256);
    GetMem(pC, 800);
    PByte(pA)^ := Byte(k);
    PByte(pB)^ := Byte(k);
    PByte(pC)^ := Byte(k);
    FreeMem(pA);
    GetMem(pFrag[k], 320);
    PByte(pFrag[k])^ := Byte(k);
    FreeMem(pB);
    FreeMem(pC);
  end;
  for k := 1 to 1000 do
    FreeMem(pFrag[k]);
end;

function AllocSmallOnce(Rounds: Integer): Int64;
var
  r: Integer;
  T0: Int64;
begin
  T0 := Int64(GetTickCount64);
  for r := 1 to Rounds do
    AllocRingSmall;
  Result := Int64(GetTickCount64) - T0;
end;

{ ------------- THR: the same pattern in 4 worker threads ----------- }

type
  TAllocThread = class(TThread)
  public
    Rounds: Integer;
    SmallOnly: Boolean;
    constructor Create(ARounds: Integer; ASmall: Boolean);
  protected
    procedure Execute; override;
  end;

constructor TAllocThread.Create(ARounds: Integer; ASmall: Boolean);
begin
  inherited Create(True);
  Rounds := ARounds;
  SmallOnly := ASmall;
end;

procedure TAllocThread.Execute;
var
  r: Integer;
begin
  if SmallOnly then
    for r := 1 to Rounds do
      AllocRingSmall
  else
    for r := 1 to Rounds do
      AllocRing;
end;

function ThreadedOnce(Rounds: Integer; Small: Boolean): Int64;
var
  Ws: array[0..3] of TAllocThread;
  T: Integer;
  T0: Int64;
begin
  for T := 0 to 3 do
    Ws[T] := TAllocThread.Create(Rounds, Small);
  T0 := Int64(GetTickCount64);
  for T := 0 to 3 do
    Ws[T].Start;
  for T := 0 to 3 do
    Ws[T].WaitFor;
  Result := Int64(GetTickCount64) - T0;
  for T := 0 to 3 do
    Ws[T].Free;
end;

{ ------------------------------------------------------------------ }

function Pct(V: Integer): Integer;
begin
  Result := Integer(Int64(V) * Scale div 100);
  if Result < 1 then
    Result := 1;
end;

function Ratio(A, B: Int64): AnsiString;
begin
  if B <= 0 then
    Result := 'n/a'
  else
    Result := AnsiString(Format('%.2f', [A / B]));
end;

var
  Code: Integer;
  TCalInt, TCalBW, TStr, TAlloc, TAllocS, TThr, TThrS: Int64;
  CalSteps, StrOuter, StrInner, AllocRounds, ThrRounds, BwMB, BwReps: Integer;
  StrOps, AllocOps: Int64;
begin
  if ParamCount > 0 then
  begin
    Val(ParamStr(1), Scale, Code);
    if (Code <> 0) or (Scale < 1) then
      Scale := 100;
  end;

  { sizes aim at 300+ ms per workload on a modern core: GetTickCount64
    resolution is ~16 ms, so anything under ~100 ms is noise }
  CalSteps := Pct(800000000);
  BwMB := 32;
  BwReps := Pct(60);
  StrOuter := Pct(6000);
  StrInner := 500;
  AllocRounds := Pct(3000);
  ThrRounds := Pct(1500);              { x4 threads }

  StrOps := Int64(StrOuter) * StrInner * 3;          { concats }
  AllocOps := Int64(AllocRounds) * 1000 * 8;         { get+free calls }

{$ifdef FPC}
  WriteLn('memspeed: FPC ', {$I %FPCVERSION%}, ' ', {$I %FPCTARGETOS%},
    {$ifdef USEX64MM} ' MM=fpcx64mm',
    {$else} {$ifdef USECMEM} ' MM=cmem', {$else} ' MM=default', {$endif}
    {$endif}
    ' scale=', Scale, '%');
{$else}
  WriteLn('memspeed: Delphi (compiler ', CompilerVersion: 0: 1,
    {$ifdef USESCALEMM} ') Win64 MM=ScaleMM2 scale=',
    {$else} ') Win64 MM=default scale=', {$endif}
    Scale, '%');
{$endif}

  TCalInt := Min3(CalIntOnce(CalSteps), CalIntOnce(CalSteps),
    CalIntOnce(CalSteps));
  WriteLn(Format('CAL-INT  %7d ms   (%d ALU steps)', [TCalInt, CalSteps]));
  TCalBW := Min3(CalBWOnce(BwMB, BwReps), CalBWOnce(BwMB, BwReps),
    CalBWOnce(BwMB, BwReps));
  WriteLn(Format('CAL-BW   %7d ms   (%d MB x %d x2 Move)', [TCalBW, BwMB, BwReps]));
  TStr := Min3(StrStormOnce(StrOuter, StrInner),
    StrStormOnce(StrOuter, StrInner), StrStormOnce(StrOuter, StrInner));
  WriteLn(Format('STR      %7d ms   (%d concats, %.1f ns/op)',
    [TStr, StrOps, TStr * 1E6 / StrOps]));
  TAlloc := Min3(AllocOnce(AllocRounds), AllocOnce(AllocRounds),
    AllocOnce(AllocRounds));
  WriteLn(Format('ALLOC    %7d ms   (%d get/free, %.1f ns/op)',
    [TAlloc, AllocOps, TAlloc * 1E6 / AllocOps]));
  TAllocS := Min3(AllocSmallOnce(AllocRounds), AllocSmallOnce(AllocRounds),
    AllocSmallOnce(AllocRounds));
  WriteLn(Format('ALLOC-S  %7d ms   (%d small get/free, %.1f ns/op)',
    [TAllocS, AllocOps, TAllocS * 1E6 / AllocOps]));
  TThr := Min3(ThreadedOnce(ThrRounds, False), ThreadedOnce(ThrRounds, False),
    ThreadedOnce(ThrRounds, False));
  WriteLn(Format('THR x4   %7d ms   (%d get/free total)',
    [TThr, Int64(ThrRounds) * 4 * 1000 * 8]));
  TThrS := Min3(ThreadedOnce(ThrRounds, True), ThreadedOnce(ThrRounds, True),
    ThreadedOnce(ThrRounds, True));
  WriteLn(Format('THR-S x4 %7d ms   (%d small get/free total)',
    [TThrS, Int64(ThrRounds) * 4 * 1000 * 8]));

  WriteLn;
  WriteLn('IdxStr   = STR/CAL-INT   = ', string(Ratio(TStr, TCalInt)));
  WriteLn('IdxAlloc = ALLOC/CAL-INT = ', string(Ratio(TAlloc, TCalInt)));
  { contention: per-op latency inside one worker vs the single-thread
    run; 1.00 = the MM scales perfectly to 4 threads }
  WriteLn('IdxThr   = per-op THR/ALLOC = ',
    string(Ratio(TThr * AllocOps, TAlloc * (Int64(ThrRounds) * 1000 * 8))));
  WriteLn('IdxThrS  = per-op THR-S/ALLOC-S = ',
    string(Ratio(TThrS * AllocOps, TAllocS * (Int64(ThrRounds) * 1000 * 8))));
  WriteLn('IdxBW    = ALLOC/CAL-BW  = ', string(Ratio(TAlloc, TCalBW)));
  WriteLn('sink=', IntToHex(Sink, 16));
end.
