program medium_contention;

{$ifdef FPC}
  {$mode delphi}{$H+}
  {$asmmode Intel}
{$endif}
{$APPTYPE CONSOLE}
{$Q-}{$R-}

uses
{$ifdef FPC}
  mormot.core.fpcx64mm,
  {$ifndef windows}
  cthreads,
  {$endif}
{$else}
  Winapi.Windows,
{$endif}
  SysUtils,
  Classes,
  perf_clock in '..\..\..\performance\common\perf_clock.pas';

const
  SizeCount = 10;
  SampleCount = 3;
  BlockSizes: array[0..SizeCount - 1] of Integer =
    (1200, 17000, 17496, 17497, 32768, 48936, 48937, 49152, 65536,
     100500);

type
  TTimes = array[0..SampleCount - 1] of Int64;

  TAllocThread = class(TThread)
  private
    FBlockSize: Integer;
    FRounds: Integer;
  public
    Checksum: UInt64;
    ElapsedNs: Int64;
    Failed: Boolean;
    {$ifdef FPC}
    Arena: Cardinal;
    {$endif}
    constructor Create(ABlockSize, ARounds: Integer);
  protected
    procedure Execute; override;
  end;

{$ifdef FPC}
function RawThreadSelf: QWord; nostackframe; assembler;
asm
  {$ifdef windows}
  db $65, $48, $8B, $04, $25, $48, $00, $00, $00
  {$else}
  db $64, $48, $8B, $04, $25, $10, $00, $00, $00
  {$endif}
end;
{$endif}

procedure AllocRing(BlockSize: Integer; var Checksum: UInt64);
var
  Fragments: array[0..999] of Pointer;
  Probe, SmallA, SmallB: PByte;
  K: Integer;
  FirstValue, LastValue: Byte;
begin
  for K := 0 to High(Fragments) do begin
    GetMem(Probe, BlockSize);
    GetMem(SmallA, 800);
    GetMem(SmallB, 1200);
    FirstValue := Byte(K);
    LastValue := Byte(K shr 1) xor $A5;
    Probe[0] := FirstValue;
    Probe[BlockSize - 1] := LastValue;
    SmallA[0] := FirstValue;
    SmallB[1199] := LastValue;
    If (Probe[0] <> FirstValue) or (Probe[BlockSize - 1] <> LastValue) or
       (SmallA[0] <> FirstValue) or (SmallB[1199] <> LastValue) then
      raise Exception.Create('allocation content mismatch');
    Checksum := Checksum + Probe[0] + Probe[BlockSize - 1] +
      SmallA[0] + SmallB[1199];
    FreeMem(Probe);
    GetMem(Fragments[K], 320);
    PByte(Fragments[K])^ := Byte(K);
    FreeMem(SmallA);
    FreeMem(SmallB);
  end;
  for K := 0 to High(Fragments) do begin
    Checksum := Checksum + PByte(Fragments[K])^;
    FreeMem(Fragments[K]);
  end;
end;

constructor TAllocThread.Create(ABlockSize, ARounds: Integer);
begin
  inherited Create(True);
  FBlockSize := ABlockSize;
  FRounds := ARounds;
end;

procedure TAllocThread.Execute;
var
  R: Integer;
  StartedAt: TPerfStamp;
  {$ifdef FPC}
  Product: Cardinal;
  {$endif}
begin
  {$ifdef FPC}
  Product := Cardinal(RawThreadSelf) * Cardinal($9E3779B1);
  Arena := Product shr 30;
  {$endif}
  StartedAt := BeginPerfStamp;
  try
    for R := 1 to FRounds do
      AllocRing(FBlockSize, Checksum);
  except
    Failed := True;
  end;
  ElapsedNs := Int64(EndDiagnosticPerfStamp(StartedAt).WallNs);
end;

function RunWorkers(BlockSize, Rounds, WorkerCount: Integer;
  out Checksum: UInt64): Int64;
var
  Workers: array of TAllocThread;
  T: Integer;
  Failed: Boolean;
begin
  Checksum := 0;
  SetLength(Workers, WorkerCount);
  for T := 0 to WorkerCount - 1 do
    Workers[T] := TAllocThread.Create(BlockSize, Rounds);
  for T := 0 to WorkerCount - 1 do
    Workers[T].Start;
  for T := 0 to WorkerCount - 1 do
    Workers[T].WaitFor;
  {$ifdef FPC}
  If WorkerCount > 1 then begin
    Write('ARENAS ');
    for T := 0 to WorkerCount - 1 do
      Write(Workers[T].Arena, ' ');
    WriteLn;
  end;
  {$endif}
  Result := 0;
  Failed := False;
  for T := 0 to WorkerCount - 1 do begin
    If Workers[T].ElapsedNs > Result then
      Result := Workers[T].ElapsedNs;
    If Workers[T].Failed then
      Failed := True;
    If (T > 0) and (Workers[T].Checksum <> Workers[0].Checksum) then
      Failed := True;
    Checksum := Checksum xor Workers[T].Checksum;
  end;
  for T := 0 to WorkerCount - 1 do
    Workers[T].Free;
  If Failed then
    raise Exception.Create('worker failed or checksum mismatch');
end;

function Median(const Values: TTimes): Int64;
var
  Sorted: TTimes;
  I, J: Integer;
  V: Int64;
begin
  Sorted := Values;
  for I := 1 to High(Sorted) do begin
    V := Sorted[I];
    J := I - 1;
    while (J >= 0) and (Sorted[J] > V) do begin
      Sorted[J + 1] := Sorted[J];
      Dec(J);
    end;
    Sorted[J + 1] := V;
  end;
  Result := Sorted[SampleCount div 2];
end;

var
  SingleTimes: array[0..SizeCount - 1] of TTimes;
  ThreadTimes: array[0..SizeCount - 1] of TTimes;
  Sample, Offset, SizeIndex, Code, Rounds, ThreadCount: Integer;
  SingleNs, ThreadNs: Int64;
  Operations: Int64;
  Checksum, Sink: UInt64;
begin
  InitializePerfClock;
  Rounds := 100;
  ThreadCount := 4;
  If ParamCount > 0 then begin
    Val(ParamStr(1), Rounds, Code);
    If (Code <> 0) or (Rounds < 1) then
      Rounds := 100;
  end;
  If ParamCount > 1 then begin
    Val(ParamStr(2), ThreadCount, Code);
    If (Code <> 0) or (ThreadCount < 1) then
      ThreadCount := 4;
  end;
  Operations := Int64(Rounds) * 1000 * 8;

{$ifdef FPC}
  WriteLn('medium-contention: FPC ', {$I %FPCVERSION%},
    ' MM=fpcx64mm flags=', FPCMM_FLAGS, ' rounds=', Rounds);
{$else}
  WriteLn('medium-contention: Delphi ', CompilerVersion:0:1,
    ' MM=default rounds=', Rounds);
{$endif}

  for SizeIndex := 0 to SizeCount - 1 do
    RunWorkers(BlockSizes[SizeIndex], Rounds div 10 + 1, 1, Checksum);

  Sink := 0;
  for Sample := 0 to SampleCount - 1 do
    for Offset := 0 to SizeCount - 1 do begin
      SizeIndex := (Sample + Offset) mod SizeCount;
      SingleTimes[SizeIndex, Sample] := RunWorkers(BlockSizes[SizeIndex],
        Rounds, 1, Checksum);
      Sink := Sink xor Checksum;
      ThreadTimes[SizeIndex, Sample] := RunWorkers(BlockSizes[SizeIndex],
        Rounds, ThreadCount, Checksum);
      Sink := Sink xor Checksum;
      WriteLn(Format('RAW sample=%d size=%d single_ns=%d thread_ns=%d workers=%d',
        [Sample + 1, BlockSizes[SizeIndex], SingleTimes[SizeIndex, Sample],
         ThreadTimes[SizeIndex, Sample], ThreadCount]));
      Flush(Output);
    end;

  for SizeIndex := 0 to SizeCount - 1 do begin
    SingleNs := Median(SingleTimes[SizeIndex]);
    ThreadNs := Median(ThreadTimes[SizeIndex]);
    If SingleNs = 0 then
      raise Exception.Create('single-thread sample is too short');
    WriteLn(Format('RESULT size=%d single_ns=%d thread_ns=%d workers=%d '+
      'single_ns_per_op=%.2f thread_ns_per_op=%.2f contention=%.2f',
      [BlockSizes[SizeIndex], SingleNs, ThreadNs, ThreadCount,
       SingleNs / Operations, ThreadNs / Operations,
       ThreadNs / SingleNs]));
  end;
  WriteLn('sink=', IntToHex(Sink, 16));
end.
