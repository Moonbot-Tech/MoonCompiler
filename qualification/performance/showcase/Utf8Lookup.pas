unit Utf8Lookup;

// Benchmark implementations, not a replacement for the public RTL dictionary.
// Keys are owned by the table; queries are immutable, bounded byte views.
// UTF-8 equality is byte-exact, including NUL. No Unicode normalization.
{$mode delphiunicode}
{$H+}

interface

uses SysUtils, Generics.Collections, Generics.Defaults, mormot.core.base;

type
  TUtf8KeyView = record
    Text: PAnsiChar;
    Len: SizeInt;
    class function OfBytes(P: Pointer; N: SizeInt): TUtf8KeyView; static; inline;
  end;

  TUtf8ViewComparer = class(TEqualityComparer<TUtf8KeyView>)
    function Equals(const Left, Right: TUtf8KeyView): Boolean; override;
    function GetHashCode(const Key: TUtf8KeyView): Integer; override;
  end;

  TUtf8Lookup = class abstract
  protected
    FLimit, FCount: SizeInt;
    procedure CheckInsert(P: Pointer; N: SizeInt);
  public
    constructor Create(ExpectedCount: SizeInt); virtual;
    procedure Add(P: Pointer; N: SizeInt; Value: UInt64); virtual; abstract;
    function TryGetValue(P: Pointer; N: SizeInt; out Value: UInt64): Boolean; virtual; abstract;
    property Count: SizeInt read FCount;
  end;

  // Existing generic dictionary with a pointer/length comparer. Stored views
  // point into owned UTF-8 buffers; query views never acquire a string reference.
  TUtf8ViewDictionary = class(TUtf8Lookup)
  private
    FKeys: TArray<RawUtf8>;
    FMap: TDictionary<TUtf8KeyView, UInt64>;
  public
    constructor Create(ExpectedCount: SizeInt); override;
    destructor Destroy; override;
    procedure Add(P: Pointer; N: SizeInt; Value: UInt64); override;
    function TryGetValue(P: Pointer; N: SizeInt; out Value: UInt64): Boolean; override;
  end;

  TUtf8ExternalTable = class(TUtf8Lookup)
  private type
    TSlot = record
      Hash: UInt32;
      Len: UInt32;
      Text: PAnsiChar;
      Value: UInt64;
    end;
  private
    FSlots: TArray<TSlot>;
    FKeys: TArray<RawUtf8>;
  public
    constructor Create(ExpectedCount: SizeInt); override;
    procedure Add(P: Pointer; N: SizeInt; Value: UInt64); override;
    function TryGetValue(P: Pointer; N: SizeInt; out Value: UInt64): Boolean; override;
  end;

  TUtf8ArenaTable = class(TUtf8Lookup)
  private type
    TSlot = record
      Hash, Offset: UInt32;
    end;
    PEntry = ^TEntry;
    TEntry = record
      Len: UInt32;
      Value: UInt64;
    end;
  private
    FSlots: TArray<TSlot>;
    FArena: TBytes;
    FUsed: SizeUInt;
  public
    constructor Create(ExpectedCount: SizeInt); override;
    procedure Add(P: Pointer; N: SizeInt; Value: UInt64); override;
    function TryGetValue(P: Pointer; N: SizeInt; out Value: UInt64): Boolean; override;
  end;

  TUtf8InlineTable = class(TUtf8Lookup)
  private type
    TSlot = record
      Hash, Len: UInt32;
      Value: UInt64;
      LongText: PAnsiChar;
      ShortText: array[0..15] of Byte;
    end;
  private
    FSlots: TArray<TSlot>;
    FLongKeys: TArray<RawUtf8>;
  public
    constructor Create(ExpectedCount: SizeInt); override;
    procedure Add(P: Pointer; N: SizeInt; Value: UInt64); override;
    function TryGetValue(P: Pointer; N: SizeInt; out Value: UInt64): Boolean; override;
  end;

function Utf8KeyHash(P: Pointer; N: SizeInt): UInt32; inline;
function SameBytes(A, B: Pointer; N: SizeInt): Boolean; inline;

implementation

function Utf8KeyHash(P: Pointer; N: SizeInt): UInt32;
begin
  Result := crc32c(0, P, N) or $80000000;
end;

function SameBytes(A, B: Pointer; N: SizeInt): Boolean;
begin
  Result := (N = 0) or CompareMem(A, B, N);
end;

function SlotCount(Expected: SizeInt): SizeInt;
begin
  Result := 8;
  while Result < Expected * 2 do Result := Result * 2;
end;

class function TUtf8KeyView.OfBytes(P: Pointer; N: SizeInt): TUtf8KeyView;
begin
  Result.Text := P;
  Result.Len := N;
end;

function TUtf8ViewComparer.Equals(const Left, Right: TUtf8KeyView): Boolean;
begin
  Result := (Left.Len = Right.Len) and SameBytes(Left.Text, Right.Text, Left.Len);
end;

function TUtf8ViewComparer.GetHashCode(const Key: TUtf8KeyView): Integer;
begin
  Result := Integer(Utf8KeyHash(Key.Text, Key.Len));
end;

constructor TUtf8Lookup.Create(ExpectedCount: SizeInt);
begin
  inherited Create;
  If (ExpectedCount < 0) or (ExpectedCount > High(Integer) div 4) then
    raise EArgumentOutOfRangeException.Create('Invalid reserved entry count');
  FLimit := ExpectedCount;
end;

procedure TUtf8Lookup.CheckInsert(P: Pointer; N: SizeInt);
begin
  If (N < 0) or (N > High(Integer)) or ((N <> 0) and (P = nil)) then
    raise EArgumentException.Create('Invalid key view');
  If FCount = FLimit then raise EArgumentException.Create('Reserved entry count exceeded');
end;

constructor TUtf8ViewDictionary.Create(ExpectedCount: SizeInt);
begin
  inherited Create(ExpectedCount);
  SetLength(FKeys, ExpectedCount);
  FMap := TDictionary<TUtf8KeyView, UInt64>.Create(ExpectedCount, TUtf8ViewComparer.Create);
end;

destructor TUtf8ViewDictionary.Destroy;
begin
  FMap.Free;
  inherited Destroy;
end;

procedure TUtf8ViewDictionary.Add(P: Pointer; N: SizeInt; Value: UInt64);
var Key: TUtf8KeyView;
begin
  CheckInsert(P, N);
  SetString(FKeys[FCount], PAnsiChar(P), N);
  Key := TUtf8KeyView.OfBytes(Pointer(FKeys[FCount]), N);
  FMap.Add(Key, Value);

  Inc(FCount);
end;

function TUtf8ViewDictionary.TryGetValue(P: Pointer; N: SizeInt; out Value: UInt64): Boolean;
begin
  Result := FMap.TryGetValue(TUtf8KeyView.OfBytes(P, N), Value);
end;


constructor TUtf8ExternalTable.Create(ExpectedCount: SizeInt);
begin
  inherited Create(ExpectedCount);
  SetLength(FSlots, SlotCount(ExpectedCount));
  SetLength(FKeys, ExpectedCount);
end;

procedure TUtf8ExternalTable.Add(P: Pointer; N: SizeInt; Value: UInt64);
var H: UInt32; I: SizeInt;
begin
  CheckInsert(P, N);
  H := Utf8KeyHash(P, N);
  I := H and (Length(FSlots) - 1);
  while FSlots[I].Hash <> 0 do begin
    If (FSlots[I].Hash = H) and (FSlots[I].Len = N) and SameBytes(FSlots[I].Text, P, N) then
      raise EArgumentException.Create('Duplicate key');
    I := (I + 1) and (Length(FSlots) - 1);
  end;
  SetString(FKeys[FCount], PAnsiChar(P), N);
  FSlots[I].Text := Pointer(FKeys[FCount]);
  FSlots[I].Len := N;
  FSlots[I].Value := Value;
  FSlots[I].Hash := H;

  Inc(FCount);
end;

function TUtf8ExternalTable.TryGetValue(P: Pointer; N: SizeInt; out Value: UInt64): Boolean;
var H: UInt32; I: SizeInt;
begin
  H := Utf8KeyHash(P, N);
  I := H and (Length(FSlots) - 1);
  while FSlots[I].Hash <> 0 do begin
    If (FSlots[I].Hash = H) and (FSlots[I].Len = N) and SameBytes(FSlots[I].Text, P, N) then begin
      Value := FSlots[I].Value;
      Exit(True);
    end;
    I := (I + 1) and (Length(FSlots) - 1);
  end;
  Value := 0;
  Result := False;
end;


constructor TUtf8ArenaTable.Create(ExpectedCount: SizeInt);
begin
  inherited Create(ExpectedCount);
  SetLength(FSlots, SlotCount(ExpectedCount));
end;

procedure TUtf8ArenaTable.Add(P: Pointer; N: SizeInt; Value: UInt64);
var H: UInt32; I: SizeInt; Entry: PEntry; Needed, Capacity: SizeUInt;
begin
  CheckInsert(P, N);
  H := Utf8KeyHash(P, N);
  I := H and (Length(FSlots) - 1);
  while FSlots[I].Hash <> 0 do begin
    Entry := PEntry(@FArena[FSlots[I].Offset]);
    If (FSlots[I].Hash = H) and (Entry.Len = N) and SameBytes(PByte(Entry) + SizeOf(TEntry), P, N) then
      raise EArgumentException.Create('Duplicate key');
    I := (I + 1) and (Length(FSlots) - 1);
  end;
  Needed := (FUsed + SizeOf(TEntry) + SizeUInt(N) + 7) and not SizeUInt(7);
  If Needed > High(UInt32) then raise EArgumentOutOfRangeException.Create('Arena exceeds 32-bit offsets');
  If Needed > SizeUInt(Length(FArena)) then begin
    Capacity := Length(FArena);
    If Capacity = 0 then Capacity := 256;
    while Capacity < Needed do Capacity := Capacity * 2;
    SetLength(FArena, Capacity);
  end;
  Entry := PEntry(@FArena[FUsed]);
  Entry.Len := N;
  Entry.Value := Value;
  If N <> 0 then Move(P^, (PByte(Entry) + SizeOf(TEntry))^, N);
  FSlots[I].Offset := FUsed;
  FSlots[I].Hash := H;
  FUsed := Needed;
  Inc(FCount);
end;

function TUtf8ArenaTable.TryGetValue(P: Pointer; N: SizeInt; out Value: UInt64): Boolean;
var H: UInt32; I: SizeInt; Entry: PEntry;
begin
  H := Utf8KeyHash(P, N);
  I := H and (Length(FSlots) - 1);
  while FSlots[I].Hash <> 0 do begin
    If FSlots[I].Hash = H then begin
      Entry := PEntry(@FArena[FSlots[I].Offset]);
      If (Entry.Len = N) and SameBytes(PByte(Entry) + SizeOf(TEntry), P, N) then begin
        Value := Entry.Value;
        Exit(True);
      end;
    end;
    I := (I + 1) and (Length(FSlots) - 1);
  end;
  Value := 0;
  Result := False;
end;


constructor TUtf8InlineTable.Create(ExpectedCount: SizeInt);
begin
  inherited Create(ExpectedCount);
  SetLength(FSlots, SlotCount(ExpectedCount));
  SetLength(FLongKeys, ExpectedCount);
end;

procedure TUtf8InlineTable.Add(P: Pointer; N: SizeInt; Value: UInt64);
var H: UInt32; I: SizeInt; Text: Pointer;
begin
  CheckInsert(P, N);
  H := Utf8KeyHash(P, N);
  I := H and (Length(FSlots) - 1);
  while FSlots[I].Hash <> 0 do begin
    If FSlots[I].Len <= SizeOf(FSlots[I].ShortText) then Text := @FSlots[I].ShortText
    else Text := FSlots[I].LongText;
    If (FSlots[I].Hash = H) and (FSlots[I].Len = N) and SameBytes(Text, P, N) then
      raise EArgumentException.Create('Duplicate key');
    I := (I + 1) and (Length(FSlots) - 1);
  end;
  If N <= SizeOf(FSlots[I].ShortText) then begin
    If N <> 0 then Move(P^, FSlots[I].ShortText, N);
  end else begin
    SetString(FLongKeys[FCount], PAnsiChar(P), N);
    FSlots[I].LongText := Pointer(FLongKeys[FCount]);
  end;
  FSlots[I].Len := N;
  FSlots[I].Value := Value;
  FSlots[I].Hash := H;
  Inc(FCount);
end;

function TUtf8InlineTable.TryGetValue(P: Pointer; N: SizeInt; out Value: UInt64): Boolean;
var H: UInt32; I: SizeInt; Text: Pointer;
begin
  H := Utf8KeyHash(P, N);
  I := H and (Length(FSlots) - 1);
  while FSlots[I].Hash <> 0 do begin
    If (FSlots[I].Hash = H) and (FSlots[I].Len = N) then begin
      If N <= SizeOf(FSlots[I].ShortText) then Text := @FSlots[I].ShortText
      else Text := FSlots[I].LongText;
      If SameBytes(Text, P, N) then begin
        Value := FSlots[I].Value;
        Exit(True);
      end;
    end;
    I := (I + 1) and (Length(FSlots) - 1);
  end;
  Value := 0;
  Result := False;
end;

end.
