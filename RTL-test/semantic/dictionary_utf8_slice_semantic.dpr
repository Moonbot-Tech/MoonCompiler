program dictionary_utf8_slice_semantic;
{$mode delphiunicode}
{$codepage utf8}
{$Q-}
uses
  {$ifdef UNIX}cthreads, cwstring,{$endif}
  {$ifdef MSWINDOWS}Windows,{$endif}
  SysUtils, Generics.Collections, Generics.Defaults;

type
  TMap = TDictionary<UTF8String, Integer>;
  TCaseComparer = class(TEqualityComparer<UTF8String>)
    function Equals(const A, B: UTF8String): Boolean; override;
    function GetHashCode(const Key: UTF8String): Integer; override;
  end;
  TTracked = class
    destructor Destroy; override;
  end;
  TLatinString = type AnsiString(1252);
var
  Checks, Freed, Allocations: Integer;
  OriginalMM, CountingMM: TMemoryManager;

procedure Check(OK: Boolean; const Why: string);
begin
  Inc(Checks);
  If not OK then raise Exception.Create(Why);
end;

function CountGet(N: PtrUInt): Pointer;
begin
  Inc(Allocations);
  Result := OriginalMM.GetMem(N);
end;
function CountAlloc(N: PtrUInt): Pointer;
begin
  Inc(Allocations);
  Result := OriginalMM.AllocMem(N);
end;
function CountRealloc(var P: Pointer; N: PtrUInt): Pointer;
begin
  Inc(Allocations);
  Result := OriginalMM.ReAllocMem(P, N);
end;
function TCaseComparer.Equals(const A, B: UTF8String): Boolean;
begin
  Result := UpperCase(UnicodeString(A)) = UpperCase(UnicodeString(B));
end;
function TCaseComparer.GetHashCode(const Key: UTF8String): Integer;
begin
  Result := 7;
end;
destructor TTracked.Destroy;
begin
  Inc(Freed);
  inherited;
end;

procedure CheckSlices;
const LongLengths: array[0..3] of Integer = (257, 1023, 4096, 16385);
var D: TMap; Key, Input, Original: UTF8String; V, Expected, I, N: Integer; A, B: Boolean;
begin
  D := TMap.Create;
  D.Add('', 0);
  Check(D.TryGetValueUtf8(nil, 0, V) and (V = 0), 'nil empty key');
  for I := 1 to 1024 do begin
    Key := UTF8String('рынок😀') + UTF8String(IntToStr(I)) + #0 + 'tail';
    D.Add(Key, I);
  end;
  for I := 1 to 1024 do begin
    Key := UTF8String('рынок😀') + UTF8String(IntToStr(I)) + #0 + 'tail';
    If I mod 3 = 0 then D.Remove(Key);
  end;
  D.TrimExcess;
  D.Capacity := D.Capacity * 2;
  for I := 0 to 2048 do begin
    Key := UTF8String('рынок😀') + UTF8String(IntToStr(I)) + #0 + 'tail';
    Input := 'prefix' + Key + 'suffix';
    Original := Copy(Input, 1, MaxInt);
    A := D.TryGetValue(Key, Expected);
    B := D.TryGetValueUtf8(PAnsiChar(Input) + 6, Length(Key), V);
    Check((A = B) and (V = Expected), 'ordinary/slice mismatch after mutations');
    Check(Input = Original, 'query changed');
  end;
  // Malformed UTF-8 is still an ordinary UTF8String key: no validation or normalization.
  Key := #$ff#$c0#0#$80;
  D.Add(Key, 987);
  Input := 'x' + Key + 'z';
  Check(D.TryGetValueUtf8(PAnsiChar(Input) + 1, Length(Key), V) and (V = 987), 'raw bytes');
  Input := 'discarded';
  Check(D.TryGetValue(Key, V) and (V = 987), 'query lifetime was retained');
  for N in LongLengths do begin
    Key := UTF8String(StringOfChar('x', N)) + UTF8String('😀') + #0 + 'end';
    D.Add(Key, N);
    Input := 'p' + Key + 's';
    Check(D.TryGetValueUtf8(PAnsiChar(Input) + 1, Length(Key), V) and (V = N), 'long slice');
    Check(not D.TryGetValueUtf8(PAnsiChar(Input) + 1, Length(Key) - 1, V), 'long slice prefix mismatch');
    Input[Length(Input) - 1] := 'X';
    Check(not D.TryGetValueUtf8(PAnsiChar(Input) + 1, Length(Key), V), 'long slice tail mismatch');
  end;
  Key := 'stable';
  D.Add(Key, 123);
  // Warm generic metadata before measuring; hits and misses must allocate nothing.
  D.TryGetValueUtf8(PAnsiChar(Key), Length(Key), V);
  GetMemoryManager(OriginalMM);
  CountingMM := OriginalMM;
  CountingMM.GetMem := CountGet;
  CountingMM.AllocMem := CountAlloc;
  CountingMM.ReAllocMem := CountRealloc;
  Allocations := 0;
  SetMemoryManager(CountingMM);
  for N := 1 to 10000 do begin
    A := D.TryGetValueUtf8(PAnsiChar(Key), Length(Key), V);
    If not A or (V <> 123) then Halt(20);
    B := D.TryGetValueUtf8(PAnsiChar(Key), Length(Key) - 1, V);
    If B or (V <> 0) then Halt(21);
  end;
  SetMemoryManager(OriginalMM);
  Check(Allocations = 0, 'slice lookup allocated');
  D.Clear;
  Check(not D.TryGetValueUtf8(nil, 0, V) and (V = 0), 'cleared empty lookup');
  D.Free;
end;

procedure CheckFallbacksAndOwnership;
var D: TMap; U: TDictionary<UnicodeString, string>; W: TDictionary<WideString, Integer>;
    R: TDictionary<RawByteString, Integer>; L: TDictionary<TLatinString, Integer>;
    O: TObjectDictionary<UTF8String, TTracked>; Obj, Found: TTracked;
    Input: UTF8String; LatinKey: TLatinString; V: Integer; S: string; Rejected: Boolean;
begin
  D := TMap.Create(TCaseComparer.Create);
  D.Add('MARKET', 7);
  Input := 'xxmarketzz';
  Check(D.TryGetValueUtf8(PAnsiChar(Input) + 2, 6, V) and (V = 7), 'custom comparer bypassed');
  Check(not D.TryGetValueUtf8(PAnsiChar(Input), 2, V) and (V = 0), 'custom comparer miss');
  Rejected := False;
  try D.TryGetValueUtf8(nil, 1, V); except on E: EArgumentException do Rejected := True; end;
  Check(Rejected, 'nil nonempty slice accepted');
  Rejected := False;
  try D.TryGetValueUtf8(PAnsiChar(Input), -1, V); except on E: EArgumentException do Rejected := True; end;
  Check(Rejected, 'negative slice accepted');
  D.Free;
  Input := UTF8String('рынок😀');
  U := TDictionary<UnicodeString, string>.Create;
  U.Add(UnicodeString(Input), 'managed value');
  Check(U.TryGetValueUtf8(PAnsiChar(Input), Length(Input), S) and (S = 'managed value'), 'UTF16 conversion');
  Check(not U.TryGetValueUtf8(nil, 0, S) and (S = ''), 'managed miss reset');
  U.Free;
  W := TDictionary<WideString, Integer>.Create;
  W.Add(WideString(Input), 9);
  Check(W.TryGetValueUtf8(PAnsiChar(Input), Length(Input), V) and (V = 9), 'WideString conversion');
  W.Free;
  R := TDictionary<RawByteString, Integer>.Create;
  R.Add(Input, 10);
  Check(R.TryGetValueUtf8(PAnsiChar(Input), Length(Input), V) and (V = 10), 'RawByteString UTF8');
  R.Free;
  Input := UTF8String('café');
  L := TDictionary<TLatinString, Integer>.Create;
  LatinKey := Input;
  L.Add(LatinKey, 11);
  Check(L.TryGetValueUtf8(PAnsiChar(Input), Length(Input), V) and (V = 11), 'CP1252 conversion');
  L.Free;
  O := TObjectDictionary<UTF8String, TTracked>.Create([doOwnsValues]);
  Obj := TTracked.Create;
  O.Add(Input, Obj);
  Check(O.TryGetValueUtf8(PAnsiChar(Input), Length(Input), Found) and (Found = Obj), 'object dictionary');
  O.Free;
  Check(Freed = 1, 'object ownership');
end;

{$ifdef UNIX}
function mmap(P: Pointer; Size: PtrUInt; Protection, Flags, FD: LongInt; Offset: Int64): Pointer; cdecl; external 'c';
function mprotect(P: Pointer; Size: PtrUInt; Protection: LongInt): LongInt; cdecl; external 'c';
function munmap(P: Pointer; Size: PtrUInt): LongInt; cdecl; external 'c';
function getpagesize: LongInt; cdecl; external 'c';
{$endif}

procedure CheckBounds;
var Page: PtrUInt; Region, P: PByte; D: TMap; Key: UTF8String; V, N, I: Integer;
    {$ifdef MSWINDOWS}Info: TSystemInfo; OldProtection: DWORD;{$endif}
begin
  {$ifdef MSWINDOWS}
  GetSystemInfo(Info);
  Page := Info.dwPageSize;
  Region := VirtualAlloc(nil, Page * 2, MEM_COMMIT or MEM_RESERVE, PAGE_READWRITE);
  Check(Region <> nil, 'VirtualAlloc');
  Check(VirtualProtect(Region + Page, Page, PAGE_NOACCESS, OldProtection), 'VirtualProtect');
  {$else}
  Page := getpagesize;
  Region := mmap(nil, Page * 2, 3, $22, -1, 0);
  Check(PtrUInt(Region) <> High(PtrUInt), 'mmap');
  Check(mprotect(Region + Page, Page, 0) = 0, 'mprotect');
  {$endif}
  D := TMap.Create;
  for N := 0 to 256 do begin
    P := Region + Page - N;
    for I := 0 to N - 1 do P[I] := Byte(I);
    SetString(Key, PAnsiChar(P), N);
    D.Add(Key, N);
    {$ifdef MSWINDOWS}
    Check(VirtualProtect(Region, Page, PAGE_READONLY, OldProtection), 'read-only');
    {$else}
    Check(mprotect(Region, Page, 1) = 0, 'read-only');
    {$endif}
    Check(D.TryGetValueUtf8(PAnsiChar(P), N, V) and (V = N), 'guard-page hit');
    {$ifdef MSWINDOWS}
    Check(VirtualProtect(Region, Page, PAGE_READWRITE, OldProtection), 'writable');
    {$else}
    Check(mprotect(Region, Page, 3) = 0, 'writable');
    {$endif}
    D.Remove(Key);
    Check(not D.TryGetValueUtf8(PAnsiChar(P), N, V) and (V = 0), 'guard-page miss');
  end;
  D.Free;
  {$ifdef MSWINDOWS}
  Check(VirtualFree(Region, 0, MEM_RELEASE), 'VirtualFree');
  {$else}
  Check(munmap(Region, Page * 2) = 0, 'munmap');
  {$endif}
end;

begin
  CheckSlices;
  CheckFallbacksAndOwnership;
  CheckBounds;
  Writeln('Checks=', Checks);
  WriteLn('DICTIONARY_UTF8_SLICE_OK');
end.
