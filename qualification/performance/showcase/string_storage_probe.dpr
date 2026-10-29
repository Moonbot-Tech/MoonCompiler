program string_storage_probe;

// Storage experiment, not a public container. All candidates keep real owning
// Pascal strings and return owning pairs. The public RTL is an extra control.
{$mode delphiunicode}
{$codepage utf8}
{$pointermath on}
{$R-}{$Q-}

uses
  {$ifdef UNIX}cthreads,{$endif}
  SysUtils, Classes, Diagnostics, Generics.Collections, Generics.Hashes,
  {$ifdef MSWINDOWS}Windows,{$endif}
  Math;

type
  {$ifdef UTF16}TKey = UnicodeString;{$else}TKey = UTF8String;{$endif}
  TPair = TPair<TKey, UInt64>;
  TKeys = array of TKey;
  {$ifdef RTL_BASELINE}
  TMap = TDictionary<TKey, UInt64>;
  {$else}
  TMap = class
  private type
    TSlot = record
      Hash: UInt32;
      {$ifdef DENSE}
      Index: UInt32;
      {$else}
      {$ifdef MIRROR}Offset: UInt32;{$endif}
      Pair: TPair;
      {$endif}
    end;
  private
    {$ifdef SPLIT}
    FHashes: array of UInt32;
    FPairs: array of TPair;
    {$else}
    FSlots: array of TSlot;
    {$ifdef DENSE}FPairs: array of TPair;{$endif}
    {$endif}
    {$ifdef MIRROR}FText: TBytes; FUsed: SizeInt;{$endif}
    FCount, FMask: SizeInt;
    function Find(const Key: TKey; H: UInt32): SizeInt; noinline;
  public type
    TEnumerator = class
    private
      FMap: TMap;
      FIndex: SizeInt;
      function GetCurrent: TPair; inline;
    public
      constructor Create(Map: TMap);
      function MoveNext: Boolean; inline;
      property Current: TPair read GetCurrent;
    end;
  public
    constructor Create(Count: SizeInt);
    procedure Add(const Key: TKey; Value: UInt64);
    function TryGetValue(const Key: TKey; var Value: UInt64): Boolean; inline;
    function GetEnumerator: TEnumerator;
  end;
  {$endif}

const
  {$ifdef UTF16}Width = 2; Encoding = 'utf16';{$else}Width = 1; Encoding = 'utf8';{$endif}
  {$ifdef RTL_BASELINE}VariantName = 'rtl';{$else}
  {$ifdef SPLIT}VariantName = 'split';{$else}
  {$ifdef MIRROR}VariantName = 'mirror';{$else}
  {$ifdef DENSE}VariantName = 'dense';{$else}VariantName = 'slots';{$endif}{$endif}{$endif}{$endif}


var
  OriginalMM, MeterMM: TMemoryManager;
  Metering: Boolean;
  Allocations, Frees, Requested, LiveBytes, PeakBytes: Int64;

procedure RecordAllocation(P: Pointer; N: PtrUInt);
begin
  If Metering and (P <> nil) then begin
    Inc(Allocations);
    Inc(Requested, N);
    Inc(LiveBytes, OriginalMM.MemSize(P));
    If LiveBytes > PeakBytes then PeakBytes := LiveBytes;
  end;
end;

procedure RecordFree(P: Pointer);
begin
  If Metering and (P <> nil) then begin
    Inc(Frees);
    Dec(LiveBytes, OriginalMM.MemSize(P));
  end;
end;

function MeterGet(N: PtrUInt): Pointer;
begin
  Result := OriginalMM.GetMem(N);
  RecordAllocation(Result, N);
end;

function MeterAlloc(N: PtrUInt): Pointer;
begin
  Result := OriginalMM.AllocMem(N);
  RecordAllocation(Result, N);
end;

function MeterFree(P: Pointer): PtrUInt;
begin
  RecordFree(P);
  Result := OriginalMM.FreeMem(P);
end;

function MeterFreeSize(P: Pointer; N: PtrUInt): PtrUInt;
begin
  RecordFree(P);
  Result := OriginalMM.FreeMemSize(P, N);
end;

function MeterRealloc(var P: Pointer; N: PtrUInt): Pointer;
begin
  RecordFree(P);
  Result := OriginalMM.ReAllocMem(P, N);
  RecordAllocation(Result, N);
end;

procedure StartMeter;
begin
  Allocations := 0;
  Frees := 0;
  Requested := 0;
  LiveBytes := 0;
  PeakBytes := 0;
  Metering := True;
end;


procedure Require(OK: Boolean; const Why: string);
begin
  If not OK then raise Exception.Create(Why);
end;

function Hash(const Key: TKey): UInt32; inline;
begin
  Result := crc32c(0, Pointer(Key), Length(Key) * Width) or $80000000;
end;

{$ifndef RTL_BASELINE}
constructor TMap.Create(Count: SizeInt);
var N: SizeInt;
begin
  inherited Create;
  N := 8;
  while (N * 3) div 4 < Count do N := N * 2;
  FMask := N - 1;
  {$ifdef SPLIT}
  SetLength(FHashes, N);
  SetLength(FPairs, N);
  {$else}
  SetLength(FSlots, N);
  {$ifdef DENSE}SetLength(FPairs, Count);{$endif}
  {$endif}
end;

function TMap.Find(const Key: TKey; H: UInt32): SizeInt;
{$ifdef MIRROR}var P: PByte; N: SizeInt;{$endif}
begin
  {$ifdef MIRROR}N := Length(Key) * Width;{$endif}
  Result := H and FMask;
  repeat
    {$ifdef SPLIT}
    If FHashes[Result] = 0 then Exit(not Result);
    If (FHashes[Result] = H) and (FPairs[Result].Key = Key) then Exit;
    {$else}
    If FSlots[Result].Hash = 0 then Exit(not Result);
    If FSlots[Result].Hash = H then begin
      {$ifdef MIRROR}
      If Pointer(FSlots[Result].Pair.Key) = Pointer(Key) then Exit;
      P := @FText[FSlots[Result].Offset];
      If (PSizeUInt(P)^ = SizeUInt(N)) and ((N = 0) or CompareMem(P + SizeOf(SizeUInt), Pointer(Key), N)) then Exit;
      {$else}
      {$ifdef DENSE}
      If FPairs[FSlots[Result].Index].Key = Key then Exit;
      {$else}
      If FSlots[Result].Pair.Key = Key then Exit;
      {$endif}
      {$endif}
    end;
    {$endif}
    Result := (Result + 1) and FMask;
  until False;
end;

procedure TMap.Add(const Key: TKey; Value: UInt64);
var H: UInt32; I: SizeInt;
{$ifdef MIRROR}N, Needed, Capacity: SizeInt;{$endif}
begin
  Require(FCount < ((FMask + 1) * 3) div 4, 'Reserved capacity exhausted');
  H := Hash(Key);
  I := Find(Key, H);
  Require(I < 0, 'Duplicate key');
  I := not I;
  {$ifdef SPLIT}
  FPairs[I].Key := Key;
  FPairs[I].Value := Value;
  FHashes[I] := H;
  {$else}
  {$ifdef MIRROR}
  N := Length(Key) * Width;
  Needed := FUsed + SizeOf(SizeUInt) + N;
  Require(Needed <= High(UInt32), 'Mirror offset overflow');
  If Needed > Length(FText) then begin
    Capacity := Max(256, Length(FText));
    while Capacity < Needed do Capacity := Capacity * 2;
    SetLength(FText, Capacity);
  end;
  PSizeUInt(@FText[FUsed])^ := N;
  If N <> 0 then Move(Pointer(Key)^, FText[FUsed + SizeOf(SizeUInt)], N);
  FSlots[I].Offset := FUsed;
  FUsed := Needed;
  {$endif}
  {$ifdef DENSE}
  FPairs[FCount].Key := Key;
  FPairs[FCount].Value := Value;
  FSlots[I].Index := FCount;
  {$else}
  FSlots[I].Pair.Key := Key;
  FSlots[I].Pair.Value := Value;
  {$endif}
  FSlots[I].Hash := H;
  {$endif}
  Inc(FCount);
end;

function TMap.TryGetValue(const Key: TKey; var Value: UInt64): Boolean;
var I: SizeInt;
begin
  I := Find(Key, Hash(Key));
  Result := I >= 0;
  If Result then begin
    {$ifdef SPLIT}Value := FPairs[I].Value;{$else}
    {$ifdef DENSE}Value := FPairs[FSlots[I].Index].Value;{$else}Value := FSlots[I].Pair.Value;{$endif}{$endif}
  end else Value := 0;
end;

constructor TMap.TEnumerator.Create(Map: TMap);
begin
  inherited Create;
  FMap := Map;
  FIndex := -1;
end;

function TMap.TEnumerator.MoveNext: Boolean;
begin
  {$ifdef DENSE}
  Inc(FIndex);
  Result := FIndex < FMap.FCount;
  {$else}
  while FIndex < FMap.FMask do begin
    Inc(FIndex);
    {$ifdef SPLIT}
    If FMap.FHashes[FIndex] <> 0 then Exit(True);
    {$else}
    If FMap.FSlots[FIndex].Hash <> 0 then Exit(True);
    {$endif}
  end;
  Result := False;
  {$endif}
end;

function TMap.TEnumerator.GetCurrent: TPair;
begin
  {$if defined(SPLIT) or defined(DENSE)}
  Result := FMap.FPairs[FIndex];
  {$else}
  Result := FMap.FSlots[FIndex].Pair;
  {$endif}
end;

function TMap.GetEnumerator: TEnumerator;
begin
  Result := TEnumerator.Create(Self);
end;
{$endif}

{$ifdef UNIX}
type TTimespec = record Seconds, Nanoseconds: Int64; end;
function clock_gettime(Id: LongInt; var T: TTimespec): LongInt; cdecl; external 'c';
{$endif}

function CpuNs: Int64;
{$ifdef UNIX}
var T: TTimespec;
begin
  Require(clock_gettime(2, T) = 0, 'CPU clock');
  Result := T.Seconds * 1000000000 + T.Nanoseconds;
end;
{$else}
var C, F, K, U: TFileTime;
begin
  Require(GetProcessTimes(GetCurrentProcess, C, F, K, U), 'CPU clock');
  Result := ((Int64(K.dwHighDateTime) shl 32) + K.dwLowDateTime +
    (Int64(U.dwHighDateTime) shl 32) + U.dwLowDateTime) * 100;
end;
{$endif}

function KeyFor(I, Profile: Integer): TKey;
var S: UnicodeString;
begin
  S := 'SYM' + UnicodeString(Format('%.12d', [I]));
  case Profile of
    1: S := 'рынок😀' + S;
    2: S := UnicodeString(StringOfChar('p', I mod 114)) + S;
  end;
  {$ifdef UTF16}Result := S;{$else}Result := UTF8Encode(S);{$endif}
end;

procedure Contracts;
var D: TMap; S: TKey; Saved: TKeys; N: Integer; V: UInt64;
begin
  D := TMap.Create(100);
  for var I := 0 to 98 do begin
    S := KeyFor(I, I mod 3);
    D.Add(S, I + 1);
    S[1] := '?';
  end;
  D.Add('', 100);
  Require(D.TryGetValue('', V) and (V = 100), 'Empty');
  Require(not D.TryGetValue('missing', V) and (V = 0), 'Miss');
  SetLength(Saved, 100);
  N := 0;
  for var Pair in D do begin
    Saved[N] := Pair.Key;
    Require(D.TryGetValue(Pair.Key, V) and (V = Pair.Value), 'Enumeration');
    Inc(N);
  end;
  Require(N = 100, 'Count');
  D.Free;
  N := 0;
  for var I := 0 to High(Saved) do begin
    S := Saved[I];
    If S <> '' then begin
      Require(PByte(Pointer(S))^ <> Ord('?'), 'Source COW');
      S[1] := '!';
      Require(Saved[I][1] <> '!', 'Returned COW');
      Inc(N);
    end;
  end;
  Require(N = 99, 'Lifetime after destroy');
end;

procedure Measure(Count, Profile, HitPercent, Passes: Integer; SamePointer: Boolean);
var D: TMap; Keys, Queries: TKeys; State: UInt32; J: Integer;
  Value, Sum, Expected, IterSum, IterExpected: UInt64;
  Start, StartCpu, BuildNs, BuildCpu, LookupNs, LookupCpu, EnumNs, EnumCpu: Int64;
  MemLive, BuildAllocations, QueryAllocations, EnumerationAllocations: Int64;
begin
  SetLength(Keys, Count);
  for var I := 0 to High(Keys) do Keys[I] := KeyFor(I, Profile);
  SetLength(Queries, 200000);
  State := 123456789;
  Expected := 0;
  for var I := 0 to High(Queries) do begin
    State := State * 1664525 + 1013904223;
    J := State mod UInt32(Count);
    If (I mod 100) < HitPercent then begin
      If SamePointer then Queries[I] := Keys[J]
      else Queries[I] := Copy(Keys[J], 1, MaxInt);
      Inc(Expected, UInt64(J) * 17 + 3);
    end else Queries[I] := KeyFor(J + Count, Profile);
  end;
  StartCpu := CpuNs;
  Start := TStopwatch.GetTimeStamp;
  D := TMap.Create(Count);
  for var I := 0 to High(Keys) do D.Add(Keys[I], UInt64(I) * 17 + 3);
  BuildNs := Round((TStopwatch.GetTimeStamp - Start) * 1e9 / TStopwatch.Frequency);
  BuildCpu := CpuNs - StartCpu;
  // Verify before measuring; measured loops contain only the operation at issue.
  for var I := 0 to High(Keys) do
    Require(D.TryGetValue(Keys[I], Value) and (Value = UInt64(I) * 17 + 3), 'Build');
  Sum := 0;
  StartCpu := CpuNs;
  Start := TStopwatch.GetTimeStamp;
  for var P := 1 to Passes do
    for var I := 0 to High(Queries) do
      If D.TryGetValue(Queries[I], Value) then Inc(Sum, Value);
  LookupNs := Round((TStopwatch.GetTimeStamp - Start) * 1e9 / TStopwatch.Frequency);
  LookupCpu := CpuNs - StartCpu;
  Require(Sum = Expected * UInt64(Passes), 'Lookup oracle');
  IterExpected := 0;
  for var I := 0 to High(Keys) do Inc(IterExpected, Length(Keys[I]) + UInt64(I) * 17 + 3);
  IterSum := 0;
  StartCpu := CpuNs;
  Start := TStopwatch.GetTimeStamp;
  for var P := 1 to Max(1, 1000000 div Count) do
    for var Pair in D do Inc(IterSum, Length(Pair.Key) + Pair.Value);
  EnumNs := Round((TStopwatch.GetTimeStamp - Start) * 1e9 / TStopwatch.Frequency);
  EnumCpu := CpuNs - StartCpu;
  Require(IterSum = IterExpected * UInt64(Max(1, 1000000 div Count)), 'Iteration oracle');
  D.Free;
  // Count separately: an instrumented allocator is not used for timings.
  GetMemoryManager(OriginalMM);
  MeterMM := OriginalMM;
  MeterMM.GetMem := MeterGet;
  MeterMM.AllocMem := MeterAlloc;
  MeterMM.FreeMem := MeterFree;
  MeterMM.FreeMemSize := MeterFreeSize;
  MeterMM.ReAllocMem := MeterRealloc;
  SetMemoryManager(MeterMM);
  StartMeter;
  D := TMap.Create(Count);
  for var I := 0 to High(Keys) do D.Add(Keys[I], UInt64(I) * 17 + 3);
  MemLive := LiveBytes;
  BuildAllocations := Allocations;
  for var I := 0 to High(Queries) do D.TryGetValue(Queries[I], Value);
  QueryAllocations := Allocations - BuildAllocations;
  Require(QueryAllocations = 0, 'Lookup allocated');
  for var Pair in D do Inc(IterSum, Length(Pair.Key) + Pair.Value);
  EnumerationAllocations := Allocations - BuildAllocations;
  D.Free;
  Require(LiveBytes = 0, 'Container storage leak');
  Metering := False;
  SetMemoryManager(OriginalMM);
  Writeln('{"variant":"', VariantName, '","encoding":"', Encoding,
    '","count":', Count, ',"profile":', Profile, ',"hit_percent":', HitPercent,
    ',"same_pointer":', Ord(SamePointer), ',"passes":', Passes,
    ',"build_ns":', BuildNs, ',"build_cpu_ns":', BuildCpu,
    ',"lookup_ns":', LookupNs, ',"lookup_cpu_ns":', LookupCpu,
    ',"enum_ns":', EnumNs, ',"enum_cpu_ns":', EnumCpu,
    ',"table_live_bytes":', MemLive, ',"build_allocations":', BuildAllocations,
    ',"lookup_allocations":', QueryAllocations, ',"enumeration_allocations":', EnumerationAllocations,
    ',"checksum":', Sum, ',"enum_checksum":', IterSum, '}');
end;

begin
  If ParamCount = 0 then begin
    Contracts;
    Writeln('STRING_STORAGE_CONTRACTS PASS ', VariantName, ' ', Encoding);
  end else begin
    Require(ParamCount = 5, 'count profile hit-percent passes same-pointer');
    Measure(StrToInt(ParamStr(1)), StrToInt(ParamStr(2)), StrToInt(ParamStr(3)),
      StrToInt(ParamStr(4)), StrToInt(ParamStr(5)) <> 0);
  end;
end.
