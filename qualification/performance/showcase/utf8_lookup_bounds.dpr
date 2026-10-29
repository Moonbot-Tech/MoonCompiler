program utf8_lookup_bounds;

// Focused immutable/bounded query and complete-hash collision checks.
{$mode delphiunicode}
{$H+}

uses
  {$ifdef UNIX}cthreads,{$endif}
  SysUtils, Generics.Collections,
  {$ifdef MSWINDOWS}Windows,{$endif}
  mormot.core.base, Utf8Lookup, Utf8LookupAstra;

type
  TLookupClass = class of TUtf8Lookup;

const
  Implementations: array[0..4] of TLookupClass =
    (TUtf8ViewDictionary, TUtf8ExternalTable, TUtf8ArenaTable, TUtf8InlineTable, TUtf8HybridTable);
procedure Require(OK: Boolean; const Reason: string);
begin
  If not OK then raise Exception.Create(Reason);
end;

{$ifdef UNIX}
function mmap(P: Pointer; Size: PtrUInt; Protection, Flags, FD: LongInt; Offset: Int64): Pointer; cdecl; external 'c';
function mprotect(P: Pointer; Size: PtrUInt; Protection: LongInt): LongInt; cdecl; external 'c';
function munmap(P: Pointer; Size: PtrUInt): LongInt; cdecl; external 'c';
function getpagesize: LongInt; cdecl; external 'c';
{$endif}

procedure CheckFullHashCollision;
var Seen: TDictionary<UInt32, UInt64>; State, Previous, Value: UInt64; H: UInt32;
    A, B: RawUtf8; Table: TUtf8Lookup;
begin
  Seen := TDictionary<UInt32, UInt64>.Create;
  State := 987654321;
  SetLength(A, 8);
  repeat
    State := State * 6364136223846793005 + 1442695040888963407;
    Move(State, A[1], 8);
    H := Utf8KeyHash(Pointer(A), 8);
    If Seen.TryGetValue(H, Previous) then Break;
    Seen.Add(H, State);
    Require(Seen.Count < 1000000, 'No collision in one million candidates');
  until False;
  SetLength(B, 8);
  Move(Previous, B[1], 8);
  Seen.Free;
  for var LongKeys := 0 to 1 do begin
    If LongKeys <> 0 then begin
      A := RawUtf8(StringOfChar('p', 60)) + A;
      B := RawUtf8(StringOfChar('p', 60)) + B;
    end;
    Require((A <> B) and (Utf8KeyHash(Pointer(A), Length(A)) = Utf8KeyHash(Pointer(B), Length(B))), 'Collision setup');
    for var C in Implementations do begin
      Table := C.Create(2);
      Table.Add(Pointer(A), Length(A), 11);
      Table.Add(Pointer(B), Length(B), 22);
      Require(Table.TryGetValue(Pointer(A), Length(A), Value) and (Value = 11), 'Full hash collision first');
      Require(Table.TryGetValue(Pointer(B), Length(B), Value) and (Value = 22), 'Full hash collision second');
      Table.Free;
    end;
  end;
  Writeln('FULL_HASH_COLLISIONS_PASS');
end;
procedure CheckGuardPage(C: TLookupClass);
var
  Page: PtrUInt;
  Region, P: PByte;
  Table: TUtf8Lookup;
  Value: UInt64;
  {$ifdef MSWINDOWS}Info: TSystemInfo; OldProtection: DWORD;{$endif}
begin
  {$ifdef MSWINDOWS}
  GetSystemInfo(Info);
  Page := Info.dwPageSize;
  Region := VirtualAlloc(nil, Page * 2, MEM_COMMIT or MEM_RESERVE, PAGE_READWRITE);
  Require(Region <> nil, 'VirtualAlloc');
  Require(VirtualProtect(Region + Page, Page, PAGE_NOACCESS, OldProtection), 'VirtualProtect');
  {$else}
  Page := getpagesize;
  Region := mmap(nil, Page * 2, 3, $22, -1, 0);
  Require(PtrUInt(Region) <> High(PtrUInt), 'mmap');
  Require(mprotect(Region + Page, Page, 0) = 0, 'mprotect');
  {$endif}
  // Every tested view ends exactly at the inaccessible page, no terminator.
  for var N := 0 to 96 do begin
    Table := C.Create(1);
    P := Region + Page - N;
    for var I := 0 to N - 1 do P[I] := Byte(I + 1);
    Table.Add(P, N, 123);
    {$ifdef MSWINDOWS}
    Require(VirtualProtect(Region, Page, PAGE_READONLY, OldProtection), 'Read-only query');
    {$else}
    Require(mprotect(Region, Page, 1) = 0, 'Read-only query');
    {$endif}
    Require(Table.TryGetValue(P, N, Value) and (Value = 123), 'Guard-page hit');
    {$ifdef MSWINDOWS}
    Require(VirtualProtect(Region, Page, PAGE_READWRITE, OldProtection), 'Writable query');
    {$else}
    Require(mprotect(Region, Page, 3) = 0, 'Writable query');
    {$endif}
    If N <> 0 then begin
      P[N - 1] := 0;
      Require(not Table.TryGetValue(P, N, Value), 'Guard-page miss');
    end;
    Table.Free;
  end;
  {$ifdef MSWINDOWS}
  Require(VirtualFree(Region, 0, MEM_RELEASE), 'VirtualFree');
  {$else}
  Require(munmap(Region, Page * 2) = 0, 'munmap');
  {$endif}
end;

begin
  for var C in Implementations do CheckGuardPage(C);
  CheckFullHashCollision;
  Writeln('UTF8_LOOKUP_BOUNDS_PASS');
end.