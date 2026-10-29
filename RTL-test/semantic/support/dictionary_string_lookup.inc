{ Included with UTF8String and UnicodeString TKey. The model is independent
  of the dictionary's slots, hash and enumeration order. }

type
  TMap = TDictionary<TKey, UnicodeString>;
  TCollisionFactory = class(TGenericsHashFactory)
    class function GetHashCode(Key: Pointer; Size: SizeInt; Initial: UInt32 = 0): UInt32; override;
  end;
  TCollisionMap = TOpenAddressingLP<TKey, UnicodeString, TCollisionFactory>;
  TCaseComparer = class(TEqualityComparer<TKey>)
    function Equals(const A, B: TKey): Boolean; override;
    function GetHashCode(const Key: TKey): Integer; override;
  end;
  TObserver = class
    Keys, Values: Integer;
    procedure KeyNotify(Sender: TObject; const Key: TKey; Action: TCollectionNotification);
    procedure ValueNotify(Sender: TObject; const Value: UnicodeString; Action: TCollectionNotification);
  end;
  TCallbackFactory = class(TGenericsHashFactory)
    class function GetHashCode(Key: Pointer; Size: SizeInt; Initial: UInt32 = 0): UInt32; override;
  end;
  TCallbackMap = TOpenAddressingLP<TKey, UInt64, TCallbackFactory>;
  IToken = interface
    ['{50A41BAF-AE82-4DC8-95C9-D814180BD63F}']
    function Number: Integer;
  end;
  TToken = class(TInterfacedObject, IToken)
    function Number: Integer;
    destructor Destroy; override;
  end;

var
  Checks, Destroyed, FactoryCalls: Integer;
  CallbackMap: TCallbackMap;
  Armed: Boolean;

procedure Check(Value: Boolean; const Why: UnicodeString);
begin
  Inc(Checks);
  If not Value then raise Exception.Create(Why);
end;

class function TCollisionFactory.GetHashCode(Key: Pointer; Size: SizeInt; Initial: UInt32): UInt32;
begin
  Result := 7;
end;

function TCaseComparer.Equals(const A, B: TKey): Boolean;
begin
  Result := UpperCase(UnicodeString(A)) = UpperCase(UnicodeString(B));
end;

function TCaseComparer.GetHashCode(const Key: TKey): Integer;
begin
  Result := 7;
end;

procedure TObserver.KeyNotify(Sender: TObject; const Key: TKey; Action: TCollectionNotification);
begin
  Inc(Keys);
end;

procedure TObserver.ValueNotify(Sender: TObject; const Value: UnicodeString; Action: TCollectionNotification);
begin
  Inc(Values);
end;

class function TCallbackFactory.GetHashCode(Key: Pointer; Size: SizeInt; Initial: UInt32): UInt32;
begin
  Inc(FactoryCalls);
  If Armed then begin
    Armed := False;
    CallbackMap.Capacity := CallbackMap.Capacity * 2;
  end;
  Result := inherited GetHashCode(Key, Size, Initial);
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

procedure CheckModel;
const KeyCount = 128;
var D: TMap; Observer: TObserver; Keys: array[0..KeyCount-1] of TKey;
    Present: array[0..KeyCount-1] of Boolean; Values: array[0..KeyCount-1] of UnicodeString;
    Seed: UInt32; K, Op, ExpectedCount, BeforeKeys, BeforeValues: Integer; V, NewValue: UnicodeString;
    Found, Added: Boolean; Query: TKey; Pair: TPair<TKey, UnicodeString>;
begin
  FillChar(Present, SizeOf(Present), 0);
  Keys[0] := '';
  Keys[1] := TKey('a'#0'b');
  Keys[2] := TKey('кириллица-😀');
  for var I := 3 to KeyCount-1 do Keys[I] := TKey('prefix-' + StringOfChar('x', I) + '-' + IntToStr(I));
  D := TMap.Create;
  Observer := TObserver.Create;
  D.OnKeyNotify := Observer.KeyNotify;
  D.OnValueNotify := Observer.ValueNotify;
  Check(D.Flat, 'Default string lookup is flat');
  V := 'stale';
  Check(not D.TryGetValue('', V) and (V = ''), 'Empty table miss resets managed output');
  Check(not D.ContainsKey(''), 'Empty ContainsKey');
  Seed := 1234567;
  for var Step := 0 to 7999 do begin
    Seed := UInt32(UInt64(Seed) * 1664525 + 1013904223);
    K := (Seed shr 16) mod KeyCount;
    Op := (Seed shr 8) and 7;
    NewValue := 'value-' + IntToStr(Step);
    case Op of
      0, 1: begin
        D.AddOrSetValue(Keys[K], NewValue);
        Present[K] := True;
        Values[K] := NewValue;
      end;
      2: begin
        D.Remove(Keys[K]);
        Present[K] := False;
      end;
      3: begin
        Added := D.TryAdd(Keys[K], NewValue);
        Check(Added = not Present[K], 'TryAdd result');
        If Added then begin
          Present[K] := True;
          Values[K] := NewValue;
        end;
      end;
      4: begin
        Pair := D.ExtractPair(Keys[K]);
        Check(Pair.Key = Keys[K], 'Extract key');
        If Present[K] then Check(Pair.Value = Values[K], 'Extract value')
        else Check(Pair.Value = '', 'Extract absent value');
        Present[K] := False;
      end;
      5: D.Capacity := D.Count + 200;
      6: D.TrimExcess;
      7: If Step mod 257 = 0 then begin
        D.Clear;
        FillChar(Present, SizeOf(Present), 0);
      end;
    end;
    Query := Keys[K];
    UniqueString(Query);
    BeforeKeys := Observer.Keys;
    BeforeValues := Observer.Values;
    V := 'stale';
    Found := D.TryGetValue(Query, V);
    Check(Found = Present[K], 'Model hit/miss');
    If Found then Check(V = Values[K], 'Model value')
    else Check(V = '', 'Miss resets output');
    Check(D.ContainsKey(Query) = Present[K], 'Model ContainsKey');
    Check((Observer.Keys = BeforeKeys) and (Observer.Values = BeforeValues), 'Lookup must not notify');
    If Step mod 97 = 0 then begin
      ExpectedCount := 0;
      for var I := 0 to KeyCount-1 do begin
        Check(D.TryGetValue(Keys[I], V) = Present[I], 'Full model lookup');
        If Present[I] then begin
          Inc(ExpectedCount);
          Check(V = Values[I], 'Full model value');
        end;
      end;
      Check(D.Count = ExpectedCount, 'Model count');
      ExpectedCount := 0;
      for var Entry in D do begin
        Inc(ExpectedCount);
        Check(Entry.Value <> '', 'Owning enum managed value');
        Check(D.ContainsKey(Entry.Key), 'Lookup with owning enum key');
      end;
      Check(D.Count = ExpectedCount, 'Owning enum count');
    end;
  end;
  D.Free;
  Check(Observer.Keys > 0, 'Notification observer active');
  Observer.Free;
end;

procedure CheckCollisionsAndComparer;
var D: TCollisionMap; Custom: TMap; Value: UnicodeString;
begin
  D := TCollisionMap.Create;
  Check(D.Flat, 'Collision factory remains flat');
  D.Add('first', 'one');
  D.Add('second', 'two');
  D.Add('third', 'three');
  Check(D.Capacity = 8, 'Hash 7 wraps from slot 7 to slot 0');
  Check(D.TryGetValue('third', Value) and (Value = 'three'), 'Wrapped collision lookup');
  Check(not D.ContainsKey('absent'), 'Full-hash collision miss');
  D.Remove('first');
  Check(D.TryGetValue('second', Value) and (Value = 'two'), 'Collision neighbour after removal');
  D.Capacity := 128;
  D.TrimExcess;
  Check(D.TryGetValue('third', Value) and (Value = 'three'), 'Collision neighbour after rehash');
  D.Free;
  Custom := TMap.Create(TCaseComparer.Create);
  Check(not Custom.Flat, 'Custom comparer bypasses flat path');
  Custom.Add('Alpha', 'one');
  Custom.Add('Beta', 'two');
  Check(Custom.TryGetValue('ALPHA', Value) and (Value = 'one'), 'Custom equality lookup');
  Check(not Custom.TryAdd('alpha', 'bad'), 'Custom duplicate');
  Custom.Remove('ALPHA');
  Check(Custom.ContainsKey('BETA') and not Custom.ContainsKey('alpha'), 'Custom collision neighbour');
  Custom.Free;
end;

procedure CheckOwningPairs;
var D: TMap; Original, Source: TKey; Value: UnicodeString;
    Saved, Extracted: TPair<TKey, UnicodeString>; Snapshot: TArray<TPair<TKey, UnicodeString>>;
begin
  D := TMap.Create;
  Original := TKey('owned-' + StringOfChar('x', 200));
  Source := Original;
  D.Add(Source, 'value');
  for var Pair in D do begin
    Check(Pointer(Pair.Key) = Pointer(Original), 'Owning pair retains normal string identity');
    Saved := Pair;
  end;
  Source[1] := '!';
  Check(D.TryGetValue(Original, Value) and (Value = 'value'), 'Input COW');
  Snapshot := D.ToArray;
  Extracted := D.ExtractPair(Original);
  D.Add('remaining', 'other');
  D.Clear;
  D.Free;
  Check((Saved.Key = Original) and (Saved.Value = 'value'), 'Owning enum Pair survives deletion and Free');
  Check((Extracted.Key = Original) and (Extracted.Value = 'value'), 'Extracted Pair survives Free');
  Check((Length(Snapshot) = 1) and (Snapshot[0].Key = Original), 'ToArray owns keys after Free');
  Source := Saved.Key;
  Source[1] := '!';
  Check((Saved.Key = Original) and (Snapshot[0].Value = 'value'), 'Saved Pair COW after Free');
end;

procedure CheckCodepageEquality;
var D: TOpenAddressingLP<RawByteString, Integer, TCollisionFactory>; A, B: RawByteString; Value: Integer;
begin
  SetLength(A, 1);
  A[1] := AnsiChar($E9);
  SetCodePage(A, 1252, False);
  SetLength(B, 2);
  B[1] := AnsiChar($C3);
  B[2] := AnsiChar($A9);
  SetCodePage(B, 65001, False);
  Check((StringCodePage(A) <> StringCodePage(B)) and (UnicodeString(A) = UnicodeString(B)), 'Codepage oracle');
  { A constant hash isolates equality's translating fallback from hashing. }
  D := TOpenAddressingLP<RawByteString, Integer, TCollisionFactory>.Create;
  D.Add(A, 123);
  Check(D.TryGetValue(B, Value) and (Value = 123), 'ANSI codepage equality fallback');
  Check(D.ContainsKey(B), 'ANSI ContainsKey codepage fallback');
  Check(not D.TryAdd(B, 999), 'ANSI codepage duplicate');
  D.Free;
end;

procedure CheckManagedValue;
var D: TDictionary<TKey, IToken>; Token, Value: IToken; Pair: TPair<TKey, IToken>;
begin
  D := TDictionary<TKey, IToken>.Create;
  Token := TToken.Create;
  D.Add('token', Token);
  Token := nil;
  Check(D.TryGetValue('token', Value) and (Value.Number = 314), 'Managed interface lookup');
  Pair := D.ExtractPair('token');
  D.Free;
  Check((Destroyed = 0) and (Pair.Value.Number = 314), 'Interface lifetime after Extract and Free');
  Pair.Value := nil;
  Check(Destroyed = 0, 'Lookup result owns interface');
  Value := nil;
  Check(Destroyed = 1, 'Managed interface released exactly once');
end;

procedure CheckFactoryReentry;
var Value: UInt64;
begin
  CallbackMap := TCallbackMap.Create(8);
  CallbackMap.Add('first', 1);
  CallbackMap.Add('second', 2);
  Check(CallbackMap.Flat, 'Callback factory enters flat path');
  FactoryCalls := 0;
  Armed := True;
  Check(CallbackMap.TryGetValue('first', Value) and (Value = 1), 'Lookup after hash callback rehash');
  Check(FactoryCalls = 1, 'TryGetValue invokes hash callback once');
  FactoryCalls := 0;
  Armed := True;
  Check(CallbackMap.ContainsKey('second'), 'ContainsKey after hash callback rehash');
  Check(FactoryCalls = 1, 'ContainsKey invokes hash callback once');
  CallbackMap.Free;
end;

procedure RunStringDictionaryChecks;
begin
  CheckModel;
  CheckCollisionsAndComparer;
  CheckOwningPairs;
  CheckCodepageEquality;
  CheckManagedValue;
  CheckFactoryReentry;
  WriteLn('Checks=', Checks);
end;
