program hasher_asm_semantic;

{ The hashers of Generics.Hashes as a program meets them, on both systems: the hand-written
  xxHash32 and crc32c (and the Pascal routines behind them) against references written here
  byte by byte, on buffers that end on an inaccessible page and begin right behind one (a
  read past either end is a fault, not a wrong value), from every start alignment of a line;
  the hasher the default comparers take on each system and CPU, and that a comparer built
  over a user factory takes the factory's hash; dictionaries with Variant keys; and a fault
  on a key's bytes inside xxHash32, whose frame saves registers of the caller: the exception
  has to reach the caller's except, and the caller's locals kept in registers have to be
  what they were (the unwinder restores the saved registers only when the frame is described
  to it: doc/ASM_LAYOUT_RULES.md, "Unwinding hand-written frames").  The same fault inside the
  SHA-1 transform of the hash package (the hand-written one of a CPU without SHA instructions,
  which saves rbx and rbp on Linux as well). }

{$ifdef FPC}
  {$mode delphi}{$H+}
{$endif}
{$Q-}{$R-}

uses
  {$ifdef MSWINDOWS}Windows,{$endif}
  {$ifdef UNIX}BaseUnix,{$endif}
  SysUtils, Variants, cpu, sha1, Generics.Hashes, Generics.Defaults, Generics.Collections;

const
  PageSize = 4096;
  DataPages = 4;

type
  { the canonical record of a numeric Variant key (Generics.Defaults) }
  TNumericKey = packed record
    Kind: Byte;
    Negative: Byte;
    Exponent: SmallInt;
    Mantissa: QWord;
    CurrencyMantissa: Int64;
  end;

  TUserFactory = class(THashFactory)
  public
    class function GetHashService: THashServiceClass; override;
    class function GetHashCode(AKey: Pointer; ASize: SizeInt; AInitVal: UInt32 = 0): UInt32; override;
  end;

  TUserDerived = class(TGenericsHashFactory)
  public
    class function GetHashService: THashServiceClass; override;
    class function GetHashCode(AKey: Pointer; ASize: SizeInt; AInitVal: UInt32 = 0): UInt32; override;
  end;

var
  Failures: Integer = 0;
  Checks: QWord = 0;
  Data, TailGuard: PByte;

procedure Fail(const What: string);
begin
  Inc(Failures);
  If Failures <= 40 then
    WriteLn('BAD ', What);
end;

procedure Check(Condition: Boolean; const What: string);
begin
  Inc(Checks);
  If not Condition then
    Fail(What);
end;

{ ---- references, byte by byte ---- }

function RefRead32(P: PByte): Cardinal;
begin
  Result := Cardinal(P[0]) or (Cardinal(P[1]) shl 8) or (Cardinal(P[2]) shl 16) or (Cardinal(P[3]) shl 24);
end;

function RefRol(V: Cardinal; N: Integer): Cardinal;
begin
  Result := Cardinal(V shl N) or Cardinal(V shr (32 - N));
end;

function RefMul(A, B: Cardinal): Cardinal;
begin
  Result := Cardinal(QWord(A) * QWord(B));
end;

function RefXX32(Seed: Cardinal; P: PByte; Len: Int64): Cardinal;
const
  P1 = Cardinal(2654435761);
  P2 = Cardinal(2246822519);
  P3 = Cardinal(3266489917);
  P4 = Cardinal(668265263);
  P5 = Cardinal(374761393);
var
  V1, V2, V3, V4, H: Cardinal;
  I: Int64;
begin
  I := 0;
  If Len >= 16 then begin
    V1 := Cardinal(Seed + P1 + P2);
    V2 := Cardinal(Seed + P2);
    V3 := Seed;
    V4 := Cardinal(Seed - P1);
    while I + 16 <= Len do begin
      V1 := RefMul(RefRol(Cardinal(V1 + RefMul(RefRead32(P + I), P2)), 13), P1);
      V2 := RefMul(RefRol(Cardinal(V2 + RefMul(RefRead32(P + I + 4), P2)), 13), P1);
      V3 := RefMul(RefRol(Cardinal(V3 + RefMul(RefRead32(P + I + 8), P2)), 13), P1);
      V4 := RefMul(RefRol(Cardinal(V4 + RefMul(RefRead32(P + I + 12), P2)), 13), P1);
      Inc(I, 16);
    end;
    H := Cardinal(RefRol(V1, 1) + RefRol(V2, 7) + RefRol(V3, 12) + RefRol(V4, 18));
  end else
    H := Cardinal(Seed + P5);
  H := Cardinal(H + Cardinal(Len));
  while I + 4 <= Len do begin
    H := RefMul(RefRol(Cardinal(H + RefMul(RefRead32(P + I), P3)), 17), P4);
    Inc(I, 4);
  end;
  while I < Len do begin
    H := RefMul(RefRol(Cardinal(H + RefMul(P[I], P5)), 11), P1);
    Inc(I);
  end;
  H := H xor (H shr 15);
  H := RefMul(H, P2);
  H := H xor (H shr 13);
  H := RefMul(H, P3);
  H := H xor (H shr 16);
  Result := H;
end;

function RefCrc32c(Crc: Cardinal; P: PByte; Len: Int64): Cardinal;
var
  I: Int64;
  K: Integer;
begin
  Crc := not Crc;
  I := 0;
  while I < Len do begin
    Crc := Crc xor P[I];
    for K := 1 to 8 do
      If (Crc and 1) <> 0 then
        Crc := (Crc shr 1) xor $82F63B78
      else
        Crc := Crc shr 1;
    Inc(I);
  end;
  Result := not Crc;
end;

{ ---- user factories ---- }

class function TUserFactory.GetHashService: THashServiceClass;
begin
  Result := THashService<TUserFactory>;
end;

class function TUserFactory.GetHashCode(AKey: Pointer; ASize: SizeInt; AInitVal: UInt32): UInt32;
begin
  Result := RefCrc32c(AInitVal xor $5A5A5A5A, AKey, ASize) xor $0F0F0F0F;
end;

class function TUserDerived.GetHashService: THashServiceClass;
begin
  Result := THashService<TUserDerived>;
end;

class function TUserDerived.GetHashCode(AKey: Pointer; ASize: SizeInt; AInitVal: UInt32): UInt32;
begin
  Result := RefXX32(AInitVal xor $13579BDF, AKey, ASize) xor $F0F0F0F0;
end;

{ ---- data between two inaccessible pages ---- }

procedure GuardedAlloc;
var
  Base: PByte;
  Total: PtrUInt;
  I: PtrUInt;
{$ifdef MSWINDOWS}
  Old: DWORD;
{$endif}
begin
  Total := (DataPages + 2) * PageSize;
{$ifdef MSWINDOWS}
  Base := VirtualAlloc(nil, Total, MEM_RESERVE or MEM_COMMIT, PAGE_READWRITE);
  If (Base = nil) or not VirtualProtect(Base, PageSize, PAGE_NOACCESS, @Old) or
     not VirtualProtect(Base + (DataPages + 1) * PageSize, PageSize, PAGE_NOACCESS, @Old) then begin
    WriteLn('guard pages: VirtualAlloc/VirtualProtect failed');
    Halt(3);
  end;
{$else}
  Base := Fpmmap(nil, Total, PROT_READ or PROT_WRITE, MAP_PRIVATE or MAP_ANONYMOUS, -1, 0);
  If (Base = nil) or (Base = PByte(-1)) or (Fpmprotect(Base, PageSize, PROT_NONE) <> 0) or
     (Fpmprotect(Base + (DataPages + 1) * PageSize, PageSize, PROT_NONE) <> 0) then begin
    WriteLn('guard pages: mmap/mprotect failed');
    Halt(3);
  end;
{$endif}
  Data := Base + PageSize;
  TailGuard := Base + (DataPages + 1) * PageSize;
  for I := 0 to DataPages * PageSize - 1 do
    Data[I] := Byte((I * 131 + 17) xor (I shr 3) xor (I shr 11));
end;

{ ---- every hasher on one buffer ---- }

const
  Seeds: array[0..4] of Cardinal = (0, 1, $12345678, $FFFFFFFF, $9E3779B1);

procedure OneBuffer(const Where: string; P: PByte; Len: Integer);
var
  S: Integer;
  WantX, WantC, Got: Cardinal;
  Tag: string;
begin
  for S := 0 to High(Seeds) do begin
    WantX := RefXX32(Seeds[S], P, Len);
    WantC := RefCrc32c(Seeds[S], P, Len);
    Tag := Where + ' len=' + IntToStr(Len) + ' seed=' + IntToHex(Seeds[S], 8) + ' at=' +
      IntToHex(PtrUInt(P) and 4095, 3);
    try
      Got := xxHash32(Seeds[S], P, Len);
      Check(Got = WantX, 'xxHash32 ' + Tag + ' got=' + IntToHex(Got, 8) + ' want=' + IntToHex(WantX, 8));
      Got := xxHash32Pascal(Seeds[S], P, Len);
      Check(Got = WantX, 'xxHash32Pascal ' + Tag + ' got=' + IntToHex(Got, 8) + ' want=' + IntToHex(WantX, 8));
      Got := crc32c(Seeds[S], P, Len);
      Check(Got = WantC, 'crc32c ' + Tag + ' got=' + IntToHex(Got, 8) + ' want=' + IntToHex(WantC, 8));
      Got := mORMotHasher(Seeds[S], P, Len);
      Check((Got = WantC) or (Got = WantX), 'mORMotHasher ' + Tag + ' got=' + IntToHex(Got, 8));
    except
      on E: Exception do
        Fail(Tag + ': a hasher read outside the buffer (' + E.ClassName + ')');
    end;
  end;
end;

procedure TestBuffers;
const
  Digits: AnsiString = '123456789';
var
  Len, Off: Integer;
begin
  Check(xxHash32(0, nil, 0) = $02CC5D05, 'xxHash32 of nothing, seed 0');
  Check(xxHash32($9E3779B1, nil, 0) = $36B78AE7, 'xxHash32 of nothing, seed PRIME32_1');
  Check(crc32c(0, Pointer(Digits), 9) = $E3069283, 'crc32c of 123456789');
  Check(RefCrc32c(0, Pointer(Digits), 9) = $E3069283, 'reference crc32c of 123456789');
  { ends exactly on the inaccessible page: the tail loops may not read past it }
  for Len := 0 to 300 do
    OneBuffer('page-end', TailGuard - Len, Len);
  { begins right behind the inaccessible page in front }
  for Len := 0 to 300 do
    OneBuffer('page-start', Data, Len);
  for Off := 0 to 63 do
    for Len := 0 to 130 do
      OneBuffer('align', Data + 256 + Off, Len);
  OneBuffer('long', TailGuard - 4097, 4097);
  OneBuffer('long', Data + 3, DataPages * PageSize - 3);
  OneBuffer('nil', nil, 0);
  Check(crc32c($12345678, nil, 5) = $12345678, 'crc32c of nil with a length');
end;

{ ---- a fault on the key's bytes inside a hasher ---- }

{ The caller keeps four values across the call in registers the ABI makes the callee save; after
  the except they have to be what they were.  The key has 24 readable bytes, then the page that
  is not there: 200 bytes fault in the 16-byte loop, 26 in the tail. }
function FaultThrough(Which, Len: Integer): string; noinline;
var
  A, B, C, D: Int64;
  R: Cardinal;
  I: Integer;
begin
  A := $1111111111111111;
  B := $2222222222222222;
  C := $3333333333333333;
  D := $4444444444444444;
  R := 0;
  for I := 1 to 2 do begin
    try
      case Which of
        0: R := xxHash32(Cardinal(A), TailGuard - 24, Len);
        1: R := crc32c(Cardinal(B), TailGuard - 24, Len);
        2: R := mORMotHasher(Cardinal(C), TailGuard - 24, Len);
        3: R := xxHash32Pascal(Cardinal(D), TailGuard - 24, Len);
      else
        R := SHA1Buffer((TailGuard - 24)^, Len)[0];
      end;
      Result := 'returned ' + IntToHex(R, 8);
    except
      on E: EAccessViolation do
        Result := 'raised';
    end;
    A := A + D - $4444444444444444;
    B := B xor (C - $3333333333333333);
  end;
  If (A <> $1111111111111111) or (B <> $2222222222222222) or (C <> $3333333333333333) or
     (D <> $4444444444444444) then
    Result := Result + ', the caller''s registers were not restored';
end;

procedure TestFaults;
const
  Names: array[0..4] of string = ('xxHash32', 'crc32c', 'mORMotHasher', 'xxHash32Pascal', 'SHA1Buffer');
var
  Which: Integer;
  Got: string;
begin
  for Which := 0 to 4 do begin
    Got := FaultThrough(Which, 200);
    Check(Got = 'raised', Names[Which] + ' over a key that runs into an unmapped page, 200 bytes: ' + Got);
    Got := FaultThrough(Which, 26);
    Check(Got = 'raised', Names[Which] + ' over a key that runs into an unmapped page, 26 bytes: ' + Got);
  end;
end;

{ ---- which hasher the comparers take ---- }

procedure IntegerKey(Value: Int64; out Key: TNumericKey);
var
  M: QWord;
  Shift: Integer;
begin
  FillChar(Key, SizeOf(Key), 0);
  If Value = 0 then
    Exit;
  Key.Kind := 1;
  If Value < 0 then begin
    Key.Negative := 1;
    M := QWord(-(Value + 1)) + 1;
  end else
    M := QWord(Value);
  Shift := 0;
  while (M and 1) = 0 do begin
    M := M shr 1;
    Inc(Shift);
  end;
  Key.Mantissa := M;
  Key.Exponent := Shift;
end;

function Which(Got: Cardinal; P: Pointer; Len: Integer): string;
begin
  If Got = RefXX32(0, P, Len) then
    Result := 'xxHash32'
  else If Got = RefCrc32c(0, P, Len) then
    Result := 'crc32c'
  else
    Result := 'other';
end;

procedure TestFactory(const Name: string; const Comparer: IEqualityComparer<Variant>;
  Factory: THashFactoryClass; Exact: Boolean);
var
  I: Integer;
  Key: TNumericKey;
  V: Variant;
  Got, Want: Cardinal;
  Text: UnicodeString;
begin
  for I := -40 to 40 do begin
    V := I * 977;
    IntegerKey(I * 977, Key);
    Got := Comparer.GetHashCode(V);
    Want := Factory.GetHashCode(@Key, SizeOf(Key), 0);
    If Exact then
      Check(Got = Want, 'a Variant key through ' + Name + ': number ' + IntToStr(I * 977) + ' got=' +
        IntToHex(Got, 8) + ' factory=' + IntToHex(Want, 8));
    V := Double(I * 977);
    Check(Comparer.GetHashCode(V) = Got, 'a Variant key through ' + Name + ': the number as Double hashes apart');
    V := Int64(I * 977);
    Check(Comparer.GetHashCode(V) = Got, 'a Variant key through ' + Name + ': the number as Int64 hashes apart');
  end;
  Text := 'BTC-USDT-12345';
  V := Text;
  Got := Comparer.GetHashCode(V);
  Want := Factory.GetHashCode(@Text[1], Length(Text) * SizeOf(WideChar), 0);
  If Exact then
    Check(Got = Want, 'a Variant key through ' + Name + ': text got=' + IntToHex(Got, 8) + ' factory=' +
      IntToHex(Want, 8));
  V := AnsiString('BTC-USDT-12345');
  Check(Comparer.GetHashCode(V) = Got, 'a Variant key through ' + Name + ': the text as AnsiString hashes apart');
end;

procedure TestComparers;
var
  Key: TNumericKey;
  V: Variant;
  Text: UnicodeString;
  I64: Int64;
  Guid: TGUID;
  ForVariant, ForText, ForInt64, ForGuid: string;
begin
  V := 123456;
  IntegerKey(123456, Key);
  ForVariant := Which(TEqualityComparer<Variant>.Default.GetHashCode(V), @Key, SizeOf(Key));
  Text := 'BTC-USDT-12345';
  ForText := Which(TEqualityComparer<UnicodeString>.Default.GetHashCode(Text), @Text[1],
    Length(Text) * SizeOf(WideChar));
  I64 := $0123456789ABCDEF;
  ForInt64 := Which(TEqualityComparer<Int64>.Default.GetHashCode(I64), @I64, SizeOf(I64));
  Guid := StringToGUID('{6F9619FF-8B86-D011-B42D-00C04FC964FF}');
  ForGuid := Which(TEqualityComparer<TGUID>.Default.GetHashCode(Guid), @Guid, SizeOf(Guid));
  WriteLn('SSE4.2 ', SSE42Support, ': Variant ', ForVariant, ', text ', ForText, ', Int64 ', ForInt64,
    ', TGUID ', ForGuid);
  If SSE42Support then begin
    { the instruction on both systems; the numeric Variant record keeps the avalanche of xxHash32
      on Linux, where it had it before the Linux packages got their assembler back }
    {$ifdef LINUX}
    Check(ForVariant = 'xxHash32', 'Linux: the default Variant comparer takes ' + ForVariant);
    {$else}
    Check(ForVariant = 'crc32c', 'Win64: the default Variant comparer takes ' + ForVariant);
    {$endif}
    Check(ForText = 'crc32c', 'the default text comparer takes ' + ForText);
    Check(ForInt64 = 'crc32c', 'the default Int64 comparer takes ' + ForInt64);
    Check(ForGuid = 'crc32c', 'the default TGUID comparer takes ' + ForGuid);
  end else begin
    Check(ForVariant = 'xxHash32', 'no SSE4.2: the default Variant comparer takes ' + ForVariant);
    Check(ForText = 'xxHash32', 'no SSE4.2: the default text comparer takes ' + ForText);
    Check(ForInt64 = 'xxHash32', 'no SSE4.2: the default Int64 comparer takes ' + ForInt64);
    Check(ForGuid = 'xxHash32', 'no SSE4.2: the default TGUID comparer takes ' + ForGuid);
  end;
  { a comparer over any other factory takes that factory's hash }
  TestFactory('the default', TEqualityComparer<Variant>.Default, TGenericsHashFactory, False);
  TestFactory('a user factory', TEqualityComparer<Variant>.Default(TUserFactory), TUserFactory, True);
  TestFactory('a user factory derived from TGenericsHashFactory',
    TEqualityComparer<Variant>.Default(TUserDerived), TUserDerived, True);
  TestFactory('TDelphiHashFactory', TEqualityComparer<Variant>.Default(TDelphiHashFactory),
    TDelphiHashFactory, True);
  TestFactory('TxxHash32HashFactory', TEqualityComparer<Variant>.Default(TxxHash32HashFactory),
    TxxHash32HashFactory, True);
  TestFactory('TxxHash32PascalHashFactory', TEqualityComparer<Variant>.Default(TxxHash32PascalHashFactory),
    TxxHash32PascalHashFactory, True);
  TestFactory('TAdler32HashFactory', TEqualityComparer<Variant>.Default(TAdler32HashFactory),
    TAdler32HashFactory, True);
  V := 123456;
  Check(Which(TEqualityComparer<Variant>.Default.GetHashCode(V), @Key, SizeOf(Key)) = ForVariant,
    'the default Variant comparer changed after the user factories');
end;

{ ---- dictionaries with Variant keys ---- }

procedure TestDictionary(const Name: string; const Comparer: IEqualityComparer<Variant>);
var
  Dict: TDictionary<Variant, Integer>;
  I, Got, Seen: Integer;
  V: Variant;
  Pair: TPair<Variant, Integer>;
begin
  If Comparer = nil then
    Dict := TDictionary<Variant, Integer>.Create
  else
    Dict := TDictionary<Variant, Integer>.Create(Comparer);
  try
    for I := 0 to 19999 do begin
      V := I;
      Dict.Add(V, I);
    end;
    for I := 0 to 999 do begin
      V := UnicodeString('MKT' + IntToStr(I) + 'USDT');
      Dict.Add(V, -I - 1);
    end;
    Check(Dict.Count = 21000, Name + ': count after the fill is ' + IntToStr(Dict.Count));
    for I := 0 to 19999 do begin
      V := Double(I);
      Check(Dict.TryGetValue(V, Got) and (Got = I), Name + ': number ' + IntToStr(I) + ' not found as Double');
      V := Int64(I);
      Check(Dict.TryGetValue(V, Got) and (Got = I), Name + ': number ' + IntToStr(I) + ' not found as Int64');
    end;
    for I := 0 to 999 do begin
      V := AnsiString('MKT' + IntToStr(I) + 'USDT');
      Check(Dict.TryGetValue(V, Got) and (Got = -I - 1), Name + ': text ' + IntToStr(I) + ' not found as AnsiString');
    end;
    for I := 20000 to 20999 do begin
      V := I;
      Check(not Dict.ContainsKey(V), Name + ': absent number ' + IntToStr(I) + ' found');
    end;
    for I := 0 to 9999 do begin
      V := I * 2;
      Dict.Remove(V);
    end;
    Check(Dict.Count = 11000, Name + ': count after the removal is ' + IntToStr(Dict.Count));
    for I := 0 to 19999 do begin
      V := I;
      Check(Dict.ContainsKey(V) = Odd(I), Name + ': number ' + IntToStr(I) + ' after the removal');
    end;
    Seen := 0;
    for Pair in Dict do
      Inc(Seen);
    Check(Seen = 11000, Name + ': the enumeration gave ' + IntToStr(Seen));
  finally
    FreeAndNil(Dict);
  end;
end;

begin
  GuardedAlloc;
  TestBuffers;
  TestFaults;
  TestComparers;
  TestDictionary('a dictionary with the default comparer', nil);
  TestDictionary('a dictionary over a user factory', TEqualityComparer<Variant>.Default(TUserFactory));
  WriteLn('checks=', Checks, ' failures=', Failures);
  If Failures <> 0 then
    Halt(1);
  WriteLn('HASHER_ASM_SEMANTIC_PASS');
end.
