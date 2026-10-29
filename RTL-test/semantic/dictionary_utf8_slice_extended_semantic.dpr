program dictionary_utf8_slice_extended_semantic;

{$mode delphiunicode}
{$codepage utf8}

uses {$ifdef UNIX}cthreads, cwstring,{$endif} {$ifdef MSWINDOWS}Windows,{$endif} SysUtils, Classes, SyncObjs,
  Generics.Collections, Generics.Defaults, Generics.MemoryExpanders, DictionaryUtf8SliceCacheSupport;

type
  TConstantFactory = class(TGenericsHashFactory)
    class function GetHashCode(Key: Pointer; Size: SizeInt; Initial: UInt32 = 0): UInt32; override;
  end;
  TCallbackFactory = class(TGenericsHashFactory)
    class function GetHashCode(Key: Pointer; Size: SizeInt; Initial: UInt32 = 0): UInt32; override;
  end;
  TCountingProbe = class(TLinearProbing)
    class function Probe(I, Hash: UInt32): UInt32; static;
  end;
  TCallbackComparer = class(TEqualityComparer<UTF8String>)
    function Equals(const A, B: UTF8String): Boolean; override;
    function GetHashCode(const Key: UTF8String): Integer; override;
  end;
  TCallbackUtf8Map = TOpenAddressingLP<UTF8String, Integer, TCallbackFactory>;
  TCallbackUnicodeMap = TOpenAddressingLP<UnicodeString, Integer, TCallbackFactory>;
  TLatinString = type AnsiString(1252);
  TCyrillicString = type AnsiString(1251);
  TRecordKey = record Text: UnicodeString; Number: Integer; end;
  IToken = interface
    ['{0575C74E-125F-43A2-8738-899B68A424A0}']
    function Number: Integer;
  end;
  TToken = class(TInterfacedObject, IToken)
    function Number: Integer;
    destructor Destroy; override;
  end;
  TCacheReader = class(TThread)
    Map: TSliceCacheMap;
    StartEvent: TEvent;
    Failed: Boolean;
    procedure Execute; override;
  end;

var
  Checks, HashCalls, ProbeCalls, Destroyed: Integer;
  Utf8Map: TCallbackUtf8Map;
  UnicodeMap: TCallbackUnicodeMap;
  CustomMap: TDictionary<UTF8String, Integer>;
  ResizeAction: procedure;

procedure Check(Value: Boolean; const Why: string);
begin
  Inc(Checks);
  If not Value then raise Exception.Create(Why);
end;

class function TConstantFactory.GetHashCode(Key: Pointer; Size: SizeInt; Initial: UInt32): UInt32;
begin
  Inc(HashCalls);
  Result := 7;
end;

class function TCallbackFactory.GetHashCode(Key: Pointer; Size: SizeInt; Initial: UInt32): UInt32;
var Action: procedure;
begin
  Inc(HashCalls);
  Action := ResizeAction;
  ResizeAction := nil;
  If Assigned(Action) then Action;
  Result := inherited GetHashCode(Key, Size, Initial);
end;

class function TCountingProbe.Probe(I, Hash: UInt32): UInt32;
begin
  Inc(ProbeCalls);
  Result := UInt32(UInt64(Hash) + I);
end;

function TCallbackComparer.Equals(const A, B: UTF8String): Boolean;
begin
  Result := A = B;
end;

function TCallbackComparer.GetHashCode(const Key: UTF8String): Integer;
begin
  Result := Integer(TCallbackFactory.GetHashCode(Pointer(Key), Length(Key), 0));
end;

procedure ResizeUtf8;
begin
  Utf8Map.Capacity := Utf8Map.Capacity * 2;
end;

procedure ResizeUnicode;
begin
  UnicodeMap.Capacity := UnicodeMap.Capacity * 2;
end;

procedure ResizeCustom;
begin
  CustomMap.Capacity := CustomMap.Capacity * 2;
end;

function TToken.Number: Integer;
begin
  Result := 314;
end;

destructor TToken.Destroy;
begin
  Inc(Destroyed);
  inherited;
end;

procedure TCacheReader.Execute;
var Input: UTF8String; Value: TSliceCacheValue;
begin
  Input := 'xcache-keyz';
  If StartEvent.WaitFor(5000) <> wrSignaled then begin
    Failed := True;
    Exit;
  end;
  for var I := 1 to 2000 do begin
    If not Map.TryGetValueUtf8(PAnsiChar(Input) + 1, 9, Value) or
      (Value.Number <> 123456789) or (Value.Witness <> 987654321) then begin
      Failed := True;
      Exit;
    end;
    If not LookupFromSliceCacheUnit(Map, PAnsiChar(Input) + 1, 9, Value) or
      (Value.Number <> 123456789) or (Value.Witness <> 987654321) then begin
      Failed := True;
      Exit;
    end;
    If Map.TryGetValueUtf8(PAnsiChar(Input) + 1, 8, Value) or
      (Value.Number <> 0) or (Value.Witness <> 0) then begin
      Failed := True;
      Exit;
    end;
  end;
end;

procedure CheckConcurrentCrossUnitCache;
var Map: TSliceCacheMap; StartEvent: TEvent; Readers: array[0..7] of TCacheReader;
begin
  Map := MakeSliceCacheMap;
  StartEvent := TEvent.Create(nil, True, False, '');
  for var I := 0 to High(Readers) do begin
    Readers[I] := TCacheReader.Create(True);
    Readers[I].Map := Map;
    Readers[I].StartEvent := StartEvent;
    Readers[I].Start;
  end;
  StartEvent.SetEvent;
  for var Reader in Readers do begin
    Reader.WaitFor;
    Check((Reader.FatalException = nil) and not Reader.Failed, 'Cold cache across threads and units');
    Reader.Free;
  end;
  StartEvent.Free;
  Map.Free;
end;

procedure CheckFactoryFallback;
var D: TOpenAddressingLP<UTF8String, Integer, TConstantFactory>;
    X: TOpenAddressingLP<UTF8String, Integer, TxxHash32HashFactory>;
    Input: UTF8String; Value: Integer;
begin
  D := TOpenAddressingLP<UTF8String, Integer, TConstantFactory>.Create;
  D.Add('first', 1);
  D.Add('second', 2);
  Check(D.Flat, 'Custom hash factory uses flat hash policy');
  Input := 'xxsecondzz';
  HashCalls := 0;
  Check(D.TryGetValueUtf8(PAnsiChar(Input) + 2, 6, Value) and (Value = 2), 'Custom factory hash preserved');
  Check(HashCalls = 1, 'Custom factory invoked exactly once');
  Check(not D.TryGetValueUtf8(PAnsiChar(Input), 2, Value) and (Value = 0), 'Custom factory colliding miss');
  D.Free;
  X := TOpenAddressingLP<UTF8String, Integer, TxxHash32HashFactory>.Create;
  X.Add('second', 3);
  Check(X.TryGetValueUtf8(PAnsiChar(Input) + 2, 6, Value) and (Value = 3), 'Independent factory hash service');
  X.Free;
end;

procedure CheckHashReentry;
var Input: UTF8String; Value: Integer; Before: SizeInt;
begin
  Input := 'xxfirstzz';
  Utf8Map := TCallbackUtf8Map.Create(8);
  Utf8Map.Add('first', 1);
  Utf8Map.Add('second', 2);
  Before := Utf8Map.Capacity;
  HashCalls := 0;
  ResizeAction := ResizeUtf8;
  Check(Utf8Map.TryGetValueUtf8(PAnsiChar(Input) + 2, 5, Value) and (Value = 1), 'UTF8 hash callback rehash');
  Check((HashCalls = 1) and (Utf8Map.Capacity > Before), 'UTF8 hash callback actually ran');
  Utf8Map.Free;
  UnicodeMap := TCallbackUnicodeMap.Create(8);
  UnicodeMap.Add('first', 3);
  UnicodeMap.Add('second', 4);
  Before := UnicodeMap.Capacity;
  HashCalls := 0;
  ResizeAction := ResizeUnicode;
  Check(UnicodeMap.TryGetValueUtf8(PAnsiChar(Input) + 2, 5, Value) and (Value = 3), 'Unicode hash callback rehash');
  Check((HashCalls = 1) and (UnicodeMap.Capacity > Before), 'Unicode hash callback actually ran');
  UnicodeMap.Free;
  CustomMap := TDictionary<UTF8String, Integer>.Create(TCallbackComparer.Create);
  Check(not CustomMap.Flat, 'Custom comparer bypasses flat hash policy');
  CustomMap.Add('first', 5);
  CustomMap.Add('second', 6);
  Before := CustomMap.Capacity;
  HashCalls := 0;
  ResizeAction := ResizeCustom;
  Check(CustomMap.TryGetValueUtf8(PAnsiChar(Input) + 2, 5, Value) and (Value = 5), 'Custom comparer rehash');
  Check((HashCalls = 1) and (CustomMap.Capacity > Before), 'Custom comparer callback actually ran');
  CustomMap.Free;
end;

procedure CheckStoredHashCollisions;
var Seen: TDictionary<UInt32, UInt64>; State, Previous: UInt64; Hash: UInt32;
    A, B, Input, Expected: UTF8String; Value: UnicodeString;
    D: TDictionary<UTF8String, UnicodeString>;
    P: TOpenAddressingLP<UTF8String, Integer, TDefaultHashFactory, TCountingProbe>;
    Saved: TPair<UTF8String, UnicodeString>; Number: Integer;
begin
  Seen := TDictionary<UInt32, UInt64>.Create;
  State := 987654321;
  SetLength(A, 8);
  repeat
    State := State xor (State shl 13);
    State := State xor (State shr 7);
    State := State xor (State shl 17);
    Move(State, A[1], 8);
    Hash := TDefaultHashFactory.GetHashCode(Pointer(A), 8, 0) or UInt32($80000000);
    If Seen.TryGetValue(Hash, Previous) then Break;
    Seen.Add(Hash, State);
    If Seen.Count >= 1000000 then raise Exception.Create('No stored-hash collision in one million candidates');
  until False;
  WriteLn('Collision candidates=', Seen.Count);
  Seen.Free;
  SetLength(B, 8);
  Move(Previous, B[1], 8);
  Check((A <> B) and ((TDefaultHashFactory.GetHashCode(Pointer(B), 8, 0) or UInt32($80000000)) = Hash),
    'Distinct keys have identical complete stored hash');
  D := TDictionary<UTF8String, UnicodeString>.Create;
  D.Add(A, 'first');
  Check(not D.TryGetValueUtf8(PAnsiChar(B), 8, Value) and (Value = ''), 'Full hash collision must compare payload');
  D.Add(B, 'second');
  Check(D.TryGetValueUtf8(PAnsiChar(A), 8, Value) and (Value = 'first'), 'Full hash collision first');
  Input := 'prefix' + B + 'suffix';
  Check(D.TryGetValueUtf8(PAnsiChar(Input) + 6, 8, Value) and (Value = 'second'), 'Full hash collision second');
  D.Remove(A);
  D.Capacity := 128;
  D.TrimExcess;
  Check(D.TryGetValueUtf8(PAnsiChar(B), 8, Value) and (Value = 'second'), 'Colliding neighbour survives mutation');
  for var Pair in D do Saved := Pair;
  Expected := B;
  UniqueString(Expected);
  P := TOpenAddressingLP<UTF8String, Integer, TDefaultHashFactory, TCountingProbe>.Create;
  P.Add(A, 11);
  P.Add(B, 22);
  ProbeCalls := 0;
  Check(P.TryGetValueUtf8(PAnsiChar(B), 8, Number) and (Number = 22), 'Custom probe lookup');
  Check(ProbeCalls > 0, 'Custom probe was not bypassed');
  P.Free;
  A := '';
  B := '';
  Input := '';
  D.Free;
  Check((Saved.Key = Expected) and (Saved.Value = 'second'), 'Owning Pair survives all original owners');
end;

procedure CheckEncodingAssignments;
const CodePages: array[0..4] of TSystemCodePage = (0, 1251, 1252, 65001, 65535);
var Input: UTF8String; LatinKey: TLatinString; CyrillicKey: TCyrillicString; AnsiKey: AnsiString;
    U: UnicodeString; W: WideString; Raw: RawByteString; Value: Integer;
    L: TDictionary<TLatinString, Integer>; C: TDictionary<TCyrillicString, Integer>;
    A: TDictionary<AnsiString, Integer>; R: TDictionary<RawByteString, Integer>;
    UnicodeD: TDictionary<UnicodeString, Integer>; WideD: TDictionary<WideString, Integer>;
begin
  Input := UTF8String('café-рынок-😀') + #0 + 'tail';
  LatinKey := Input;
  CyrillicKey := Input;
  AnsiKey := Input;
  U := Input;
  W := Input;
  L := TDictionary<TLatinString, Integer>.Create;
  C := TDictionary<TCyrillicString, Integer>.Create;
  A := TDictionary<AnsiString, Integer>.Create;
  UnicodeD := TDictionary<UnicodeString, Integer>.Create;
  WideD := TDictionary<WideString, Integer>.Create;
  L.Add(LatinKey, 1);
  C.Add(CyrillicKey, 2);
  A.Add(AnsiKey, 3);
  UnicodeD.Add(U, 4);
  WideD.Add(W, 5);
  Check(L.TryGetValueUtf8(PAnsiChar(Input), Length(Input), Value) and (Value = 1), 'Typed CP1252 assignment oracle');
  Check(C.TryGetValueUtf8(PAnsiChar(Input), Length(Input), Value) and (Value = 2), 'Typed CP1251 assignment oracle');
  Check(A.TryGetValueUtf8(PAnsiChar(Input), Length(Input), Value) and (Value = 3), 'Typed system codepage oracle');
  Check(UnicodeD.TryGetValueUtf8(PAnsiChar(Input), Length(Input), Value) and (Value = 4), 'Unicode NUL and surrogate pair');
  Check(WideD.TryGetValueUtf8(PAnsiChar(Input), Length(Input), Value) and (Value = 5), 'WideString NUL and surrogate pair');
  L.Free;
  C.Free;
  A.Free;
  UnicodeD.Free;
  WideD.Free;
  R := TDictionary<RawByteString, Integer>.Create;
  Input := 'ascii';
  for var CP in CodePages do begin
    Raw := Input;
    SetCodePage(Raw, CP, False);
    R.Add(Raw, CP);
    Check(R.TryGetValueUtf8(PAnsiChar(Input), Length(Input), Value) and (Value = CP), 'Dynamic codepage fallback');
    R.Clear;
  end;
  R.Free;
end;

procedure CheckRejectionAndManagedValue;
var Integers: TDictionary<Integer, Integer>; Records: TDictionary<TRecordKey, Integer>;
    Shorts: TDictionary<ShortString, Integer>; D: TDictionary<UTF8String, IToken>;
    Input: UTF8String; Value: Integer; Rejected: Boolean; Token, Found: IToken;
begin
  Input := 'value';
  Integers := TDictionary<Integer, Integer>.Create;
  Records := TDictionary<TRecordKey, Integer>.Create;
  Shorts := TDictionary<ShortString, Integer>.Create;
  Rejected := False;
  try Integers.TryGetValueUtf8(PAnsiChar(Input), Length(Input), Value);
  except on E: EArgumentException do Rejected := True; end;
  Check(Rejected, 'Ordinal keys are rejected');
  Rejected := False;
  try Records.TryGetValueUtf8(nil, 0, Value);
  except on E: EArgumentException do Rejected := True; end;
  Check(Rejected, 'Managed record keys are rejected safely');
  Rejected := False;
  try Shorts.TryGetValueUtf8(PAnsiChar(Input), Length(Input), Value);
  except on E: EArgumentException do Rejected := True; end;
  Check(Rejected, 'ShortString is explicitly outside supported key kinds');
  Integers.Free;
  Records.Free;
  Shorts.Free;
  D := TDictionary<UTF8String, IToken>.Create;
  Token := TToken.Create;
  D.Add(Input, Token);
  Token := nil;
  Check(D.TryGetValueUtf8(PAnsiChar(Input), Length(Input), Found) and (Found.Number = 314), 'Managed interface result');
  D.Free;
  Check((Destroyed = 0) and (Found.Number = 314), 'Managed result owns value after dictionary Free');
  Found := nil;
  Check(Destroyed = 1, 'Managed result releases exactly once');
end;

{$ifdef UNIX}
function mmap(P: Pointer; Size: PtrUInt; Protection, Flags, FD: LongInt; Offset: Int64): Pointer; cdecl; external 'c';
function mprotect(P: Pointer; Size: PtrUInt; Protection: LongInt): LongInt; cdecl; external 'c';
function munmap(P: Pointer; Size: PtrUInt): LongInt; cdecl; external 'c';
function getpagesize: LongInt; cdecl; external 'c';
{$endif}

procedure CheckLongReadOnlyBounds;
const Lengths: array[0..8] of Integer = (257, 511, 512, 513, 1023, 1024, 1025, 2048, 4096);
var Page: PtrUInt; Region, Text: PByte; Key: UTF8String; UnicodeKey: UnicodeString; Value: Integer;
    D: TDictionary<UTF8String, Integer>; U: TDictionary<UnicodeString, Integer>;
    {$ifdef MSWINDOWS}Info: TSystemInfo; OldProtection: DWORD;{$endif}
begin
  {$ifdef MSWINDOWS}
  GetSystemInfo(Info);
  Page := Info.dwPageSize;
  Region := VirtualAlloc(nil, Page * 3, MEM_COMMIT or MEM_RESERVE, PAGE_READWRITE);
  Check(Region <> nil, 'Bounded allocation');
  Check(VirtualProtect(Region, Page, PAGE_NOACCESS, OldProtection), 'Left guard page');
  Check(VirtualProtect(Region + Page * 2, Page, PAGE_NOACCESS, OldProtection), 'Right guard page');
  {$else}
  Page := getpagesize;
  Region := mmap(nil, Page * 3, 3, $22, -1, 0);
  Check(PtrUInt(Region) <> High(PtrUInt), 'Bounded allocation');
  Check(mprotect(Region, Page, 0) = 0, 'Left guard page');
  Check(mprotect(Region + Page * 2, Page, 0) = 0, 'Right guard page');
  {$endif}
  D := TDictionary<UTF8String, Integer>.Create;
  U := TDictionary<UnicodeString, Integer>.Create;
  for var N in Lengths do begin
    If N > Page then Continue;
    Text := Region + Page * 2 - N;
    for var I := 0 to N - 1 do Text[I] := Byte(I and $7F);
    SetString(Key, PAnsiChar(Text), N);
    UnicodeKey := Key;
    D.Add(Key, N);
    U.Add(UnicodeKey, N);
    {$ifdef MSWINDOWS}
    Check(VirtualProtect(Region + Page, Page, PAGE_READONLY, OldProtection), 'Read-only query page');
    {$else}
    Check(mprotect(Region + Page, Page, 1) = 0, 'Read-only query page');
    {$endif}
    Check(D.TryGetValueUtf8(PAnsiChar(Text), N, Value) and (Value = N), 'Long bounded byte hit');
    Check(U.TryGetValueUtf8(PAnsiChar(Text), N, Value) and (Value = N), 'Long bounded converted hit');
    D.Clear;
    U.Clear;
    Check(not D.TryGetValueUtf8(PAnsiChar(Text), N, Value) and (Value = 0), 'Long read-only byte miss');
    Check(not U.TryGetValueUtf8(PAnsiChar(Text), N, Value) and (Value = 0), 'Long read-only converted miss');
    {$ifdef MSWINDOWS}
    Check(VirtualProtect(Region + Page, Page, PAGE_READWRITE, OldProtection), 'Writable query page');
    {$else}
    Check(mprotect(Region + Page, Page, 3) = 0, 'Writable query page');
    {$endif}
  end;
  D.Free;
  U.Free;
  {$ifdef MSWINDOWS}
  Check(VirtualFree(Region, 0, MEM_RELEASE), 'Bounded release');
  {$else}
  Check(munmap(Region, Page * 3) = 0, 'Bounded release');
  {$endif}
end;

begin
  CheckConcurrentCrossUnitCache;
  CheckFactoryFallback;
  CheckHashReentry;
  CheckStoredHashCollisions;
  CheckEncodingAssignments;
  CheckRejectionAndManagedValue;
  CheckLongReadOnlyBounds;
  WriteLn('Checks=', Checks);
  WriteLn('DICTIONARY_UTF8_SLICE_EXTENDED_OK');
end.
