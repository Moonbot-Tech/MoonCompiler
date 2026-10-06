program dictionary_flat_semantic;

{ TDictionary flat path and notification flag (packages/rtl-generics).

  With the default equality comparer and an ordinal, pointer, class or
  string key TDictionary looks keys up on one straight path (FlatFind:
  hash, probe loop, compare) and notifies KeyNotify/ValueNotify only when
  a handler is assigned or a descendant overrides them.  This program is
  the contract of that change:

  1. Flat is taken exactly for the listed key kinds with the default
     comparer, never for a custom comparer, a record or a float key.
  2. A model-checked operation mix over every key kind: the dictionary
     agrees with a plain array model after every operation, through
     rehash, TrimExcess, Clear and enumeration, on both paths.
  3. Notifications: nothing is observable without a handler, exact
     counts and order with handlers assigned and removed at run time, a
     descendant that overrides KeyNotify or ValueNotify keeps receiving
     them without any handler, TObjectDictionary keeps owning.
  4. Hash spread: allocator-strided pointers, sequential integers and
     Int64 keys that differ only in their high half do not cluster - the
     populations on which the CRC of the key bytes collapsed. }

{$mode delphi}{$H+}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  cwstring,
  {$endif UNIX}
  SysUtils,
  Generics.Defaults,
  Generics.MemoryExpanders,
  Generics.Collections;

type
  TEnumKey = (ekA, ekB, ekC, ekD, ekE, ekF, ekG, ekH);
  TSparseKey = (skA = 0, skB = 2, skC = 5);

  TRecordKey = record
    A: Integer;
    B: Int64;
  end;

  TCounted = class
  public
    Id: Integer;
    constructor Create(AId: Integer);
    destructor Destroy; override;
  end;

  TConstantHashComparer = class(TInterfacedObject, IEqualityComparer<Integer>)
  public
    function Equals(const ALeft, ARight: Integer): Boolean; reintroduce;
    function GetHashCode(const AValue: Integer): Integer; reintroduce;
  end;

  TNotifyLog = class
  public
    KeyAdded, KeyRemoved, KeyExtracted: Integer;
    ValueAdded, ValueRemoved, ValueExtracted: Integer;
    LastKey, LastValue: Integer;
    LastValueAction: TCollectionNotification;
    procedure KeyEvent(ASender: TObject; const AItem: Integer;
      AAction: TCollectionNotification);
    procedure ValueEvent(ASender: TObject; const AItem: Integer;
      AAction: TCollectionNotification);
    function Total: Integer;
  end;

  TObjectNotifyLog = class
  public
    Removed, Extracted: Integer;
    procedure ValueEvent(ASender: TObject; const AItem: TCounted;
      AAction: TCollectionNotification);
  end;

  { NotifyActive is protected: a plain descendant reads it }
  TProbeDictionary = class(TDictionary<Integer, Integer>)
  public
    function Active: Boolean;
  end;

  TOverridingDictionary = class(TDictionary<Integer, Integer>)
  protected
    procedure KeyNotify(const AKey: Integer;
      ACollectionNotification: TCollectionNotification); override;
    procedure ValueNotify(const AValue: Integer;
      ACollectionNotification: TCollectionNotification); override;
  public
    function Active: Boolean;
  end;

  { only ValueNotify overridden: owns its values like TObjectDictionary }
  TOwningValueDictionary = class(TDictionary<Integer, TCounted>)
  protected
    procedure ValueNotify(const AValue: TCounted;
      ACollectionNotification: TCollectionNotification); override;
  public
    function Active: Boolean;
  end;

  { an object key with value equality - the Delphi idiom of overriding
    Equals and GetHashCode so that two instances with the same Id are one key }
  TValueKey = class
  public
    Id: Integer;
    constructor Create(AId: Integer);
    destructor Destroy; override;
    function Equals(AObject: TObject): Boolean; override;
    function GetHashCode: PtrInt; override;
  end;

  { overrides Equals only: an object that is equal to nothing but itself
    hashes as an address and must not be confused with another instance }
  TIdentityKey = class
  public
    function Equals(AObject: TObject): Boolean; override;
  end;

  TLayoutProbe = class
  public
    Occupied: TArray<Boolean>;
    procedure Position(ASender: TObject; AKeyPos: UInt32);
    function ClusterCost(ACount: Integer): Double;
  end;

  { model-checked operation mix over one dictionary type }
  TExercise<TKey, TValue> = class
  public type
    TMakeKey = function(AIndex: Integer): TKey;
    TMakeValue = function(ASeed: Integer): TValue;
    TSameValue = function(const ALeft, ARight: TValue): Boolean;
  private
    class function IndexOf(const AComparer: IEqualityComparer<TKey>;
      const AKeys: TArray<TKey>; const AKey: TKey): Integer;
    class procedure Verify(const AName: string;
      ADictionary: TDictionary<TKey, TValue>;
      const AComparer: IEqualityComparer<TKey>; const AKeys: TArray<TKey>;
      const APresent: TArray<Boolean>; const AValues: TArray<TValue>;
      ASameValue: TSameValue);
  public
    class procedure Run(const AName: string;
      ADictionary: TDictionary<TKey, TValue>; AExpectFlat: Boolean;
      AMakeKey: TMakeKey; AMakeValue: TMakeValue; ASameValue: TSameValue;
      AKeySpace, AOperations: Integer);
  end;

var
  Destroyed: Integer = 0;
  OverrideKeyEvents: Integer = 0;
  OverrideValueEvents: Integer = 0;
  Seed: Cardinal = 20260921;
  ObjectPool: TArray<TObject>;

procedure Check(ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    raise Exception.Create('DICTIONARY_FLAT_FAIL: ' + AMessage);
end;

function Next: Cardinal;
begin
  Seed := Seed * 1664525 + 1013904223;
  Result := Seed shr 8;
end;

{ TCounted }

constructor TCounted.Create(AId: Integer);
begin
  inherited Create;
  Id := AId;
end;

destructor TCounted.Destroy;
begin
  Inc(Destroyed);
  inherited;
end;

{ TConstantHashComparer }

function TConstantHashComparer.Equals(const ALeft, ARight: Integer): Boolean;
begin
  Result := ALeft = ARight;
end;

function TConstantHashComparer.GetHashCode(const AValue: Integer): Integer;
begin
  Result := 1;
end;

{ TNotifyLog }

procedure TNotifyLog.KeyEvent(ASender: TObject; const AItem: Integer;
  AAction: TCollectionNotification);
begin
  case AAction of
    cnAdded: Inc(KeyAdded);
    cnRemoved: Inc(KeyRemoved);
    cnExtracted: Inc(KeyExtracted);
  end;
  LastKey := AItem;
end;

procedure TNotifyLog.ValueEvent(ASender: TObject; const AItem: Integer;
  AAction: TCollectionNotification);
begin
  case AAction of
    cnAdded: Inc(ValueAdded);
    cnRemoved: Inc(ValueRemoved);
    cnExtracted: Inc(ValueExtracted);
  end;
  LastValue := AItem;
  LastValueAction := AAction;
end;

function TNotifyLog.Total: Integer;
begin
  Result := KeyAdded + KeyRemoved + KeyExtracted +
    ValueAdded + ValueRemoved + ValueExtracted;
end;

{ TObjectNotifyLog }

procedure TObjectNotifyLog.ValueEvent(ASender: TObject; const AItem: TCounted;
  AAction: TCollectionNotification);
begin
  case AAction of
    cnRemoved: Inc(Removed);
    cnExtracted: Inc(Extracted);
  end;
end;

{ TProbeDictionary }

function TProbeDictionary.Active: Boolean;
begin
  Result := NotifyActive;
end;

{ TOverridingDictionary }

procedure TOverridingDictionary.KeyNotify(const AKey: Integer;
  ACollectionNotification: TCollectionNotification);
begin
  Inc(OverrideKeyEvents);
  inherited;
end;

procedure TOverridingDictionary.ValueNotify(const AValue: Integer;
  ACollectionNotification: TCollectionNotification);
begin
  Inc(OverrideValueEvents);
  inherited;
end;

function TOverridingDictionary.Active: Boolean;
begin
  Result := NotifyActive;
end;

{ TOwningValueDictionary }

procedure TOwningValueDictionary.ValueNotify(const AValue: TCounted;
  ACollectionNotification: TCollectionNotification);
begin
  inherited;
  if ACollectionNotification = cnRemoved then
    AValue.Free;
end;

function TOwningValueDictionary.Active: Boolean;
begin
  Result := NotifyActive;
end;

{ TValueKey }

constructor TValueKey.Create(AId: Integer);
begin
  inherited Create;
  Id := AId;
end;

destructor TValueKey.Destroy;
begin
  Inc(Destroyed);
  inherited;
end;

function TValueKey.Equals(AObject: TObject): Boolean;
begin
  Result := (AObject is TValueKey) and (TValueKey(AObject).Id = Id);
end;

function TValueKey.GetHashCode: PtrInt;
begin
  Result := Id * 31;
end;

{ TIdentityKey }

function TIdentityKey.Equals(AObject: TObject): Boolean;
begin
  Result := AObject = Self;
end;

{ TLayoutProbe }

procedure TLayoutProbe.Position(ASender: TObject; AKeyPos: UInt32);
begin
  Check(AKeyPos < Length(Occupied), 'layout position inside the table');
  Check(not Occupied[AKeyPos], 'layout position reported once');
  Occupied[AKeyPos] := True;
end;

{ sum over the cyclic runs of occupied slots of L*(L+1)/2, per key: the
  probe count of a lookup if every key of a run had the first slot of the
  run as its home; about 3 for a random-like hash at load 0.5 }
function TLayoutProbe.ClusterCost(ACount: Integer): Double;
var
  Start, I, Run, Size: Integer;
  Sum: Double;
begin
  Size := Length(Occupied);
  Start := -1;
  for I := 0 to Size - 1 do
    if not Occupied[I] then
    begin
      Start := I;
      Break;
    end;
  if Start < 0 then
    Exit(Size);
  Sum := 0;
  Run := 0;
  for I := 1 to Size do
  begin
    if Occupied[(Start + I) mod Size] then
      Inc(Run)
    else
    begin
      Sum := Sum + Run * (Run + 1) * 0.5;
      Run := 0;
    end;
  end;
  Result := Sum / ACount;
end;

{ TExercise<TKey, TValue> }

class function TExercise<TKey, TValue>.IndexOf(
  const AComparer: IEqualityComparer<TKey>; const AKeys: TArray<TKey>;
  const AKey: TKey): Integer;
var
  I: Integer;
begin
  for I := 0 to High(AKeys) do
    if AComparer.Equals(AKeys[I], AKey) then
      Exit(I);
  Result := -1;
end;

class procedure TExercise<TKey, TValue>.Verify(const AName: string;
  ADictionary: TDictionary<TKey, TValue>;
  const AComparer: IEqualityComparer<TKey>; const AKeys: TArray<TKey>;
  const APresent: TArray<Boolean>; const AValues: TArray<TValue>;
  ASameValue: TSameValue);
var
  Seen: TArray<Boolean>;
  Expected, Found, K: Integer;
  V: TValue;
  Pair: TPair<TKey, TValue>;
  Key: TKey;
begin
  Expected := 0;
  for K := 0 to High(AKeys) do
    if APresent[K] then
      Inc(Expected);
  Check(ADictionary.Count = Expected, AName + ': Count');
  Check(ADictionary.IsEmpty = (Expected = 0), AName + ': IsEmpty');
  for K := 0 to High(AKeys) do
  begin
    Check(ADictionary.ContainsKey(AKeys[K]) = APresent[K], AName + ': ContainsKey');
    if ADictionary.TryGetValue(AKeys[K], V) then
      Check(APresent[K] and ASameValue(V, AValues[K]), AName + ': TryGetValue value')
    else
      Check((not APresent[K]) and ASameValue(V, Default(TValue)),
        AName + ': TryGetValue miss');
  end;

  { the enumeration is a permutation of the model }
  SetLength(Seen, Length(AKeys));
  Found := 0;
  for Pair in ADictionary do
  begin
    K := IndexOf(AComparer, AKeys, Pair.Key);
    Check(K >= 0, AName + ': enumerated key is known');
    Check(APresent[K] and not Seen[K], AName + ': enumerated key present once');
    Check(ASameValue(Pair.Value, AValues[K]), AName + ': enumerated value');
    Seen[K] := True;
    Inc(Found);
  end;
  Check(Found = Expected, AName + ': enumeration count');

  Found := 0;
  for Key in ADictionary.Keys do
  begin
    K := IndexOf(AComparer, AKeys, Key);
    Check((K >= 0) and APresent[K], AName + ': Keys enumeration');
    Inc(Found);
  end;
  Check(Found = Expected, AName + ': Keys count');
  Check(Length(ADictionary.Values.ToArray) = Expected, AName + ': Values.ToArray');
  Check(Length(ADictionary.ToArray) = Expected, AName + ': ToArray');
end;

class procedure TExercise<TKey, TValue>.Run(const AName: string;
  ADictionary: TDictionary<TKey, TValue>; AExpectFlat: Boolean;
  AMakeKey: TMakeKey; AMakeValue: TMakeValue; ASameValue: TSameValue;
  AKeySpace, AOperations: Integer);
var
  Keys: TArray<TKey>;
  Present: TArray<Boolean>;
  Values: TArray<TValue>;
  Comparer: IEqualityComparer<TKey>;
  I, K, Op, Count: Integer;
  V: TValue;
  PV: ^TValue;
  Pair: TPair<TKey, TValue>;
  Raised: Boolean;
begin
  Comparer := TEqualityComparer<TKey>.Default;
  Check(ADictionary.Flat = AExpectFlat, AName + ': Flat');
  SetLength(Keys, AKeySpace);
  SetLength(Present, AKeySpace);
  SetLength(Values, AKeySpace);
  for K := 0 to AKeySpace - 1 do
    Keys[K] := AMakeKey(K);
  for K := 1 to AKeySpace - 1 do
    Check(not Comparer.Equals(Keys[K], Keys[K - 1]), AName + ': keys are distinct');
  try
    Count := 0;
    for I := 1 to AOperations do
    begin
      K := Next mod Cardinal(AKeySpace);
      Op := Next mod 20;
      case Op of
        0..3, 18:
          begin
            V := AMakeValue(I);
            ADictionary.AddOrSetValue(Keys[K], V);
            if not Present[K] then
              Inc(Count);
            Present[K] := True;
            Values[K] := V;
          end;
        19:
          begin
            { the pointer API: GetOrAddMutableValue adds a default value for a
              missing key, TryGetMutableValue/GetMutableValue see the slot }
            V := AMakeValue(I);
            PV := ADictionary.GetOrAddMutableValue(Keys[K]);
            if Present[K] then
              Check(ASameValue(PV^, Values[K]), AName + ': GetOrAddMutableValue sees the value')
            else
            begin
              Check(ASameValue(PV^, Default(TValue)), AName + ': GetOrAddMutableValue adds a default');
              Inc(Count);
              Present[K] := True;
            end;
            PV^ := V;
            Values[K] := V;
            Check(ADictionary.TryGetMutableValue(Keys[K], PV) and ASameValue(PV^, V),
              AName + ': TryGetMutableValue after a write through the pointer');
            Check(ASameValue(ADictionary.GetMutableValue(Keys[K])^, V), AName + ': GetMutableValue');
          end;
        4, 5:
          begin
            V := AMakeValue(I);
            Raised := ADictionary.TryAdd(Keys[K], V);
            Check(Raised = not Present[K], AName + ': TryAdd result');
            if Raised then
            begin
              Inc(Count);
              Present[K] := True;
              Values[K] := V;
            end;
          end;
        6, 7:
          begin
            ADictionary.Remove(Keys[K]);
            if Present[K] then
              Dec(Count);
            Present[K] := False;
          end;
        8, 9:
          begin
            Check(ADictionary.TryGetValue(Keys[K], V) = Present[K], AName + ': TryGetValue');
            if Present[K] then
              Check(ASameValue(V, Values[K]), AName + ': TryGetValue value');
          end;
        10:
          Check(ADictionary.ContainsKey(Keys[K]) = Present[K], AName + ': ContainsKey');
        11:
          begin
            Raised := False;
            try
              V := ADictionary[Keys[K]];
              Check(Present[K] and ASameValue(V, Values[K]), AName + ': Items read');
            except
              on EListError do
                Raised := True;
            end;
            Check(Raised = not Present[K], AName + ': Items read of a missing key raises');
          end;
        12:
          begin
            V := AMakeValue(I);
            Raised := False;
            try
              ADictionary[Keys[K]] := V;
              Values[K] := V;
            except
              on EListError do
                Raised := True;
            end;
            Check(Raised = not Present[K], AName + ': Items write of a missing key raises');
          end;
        13:
          begin
            Pair := ADictionary.ExtractPair(Keys[K]);
            if Present[K] then
            begin
              Check(Comparer.Equals(Pair.Key, Keys[K]), AName + ': ExtractPair key');
              Check(ASameValue(Pair.Value, Values[K]), AName + ': ExtractPair value');
              Dec(Count);
              Present[K] := False;
            end
            else
            begin
              Check(ASameValue(Pair.Value, Default(TValue)), AName + ': ExtractPair miss value');
              Check(Comparer.Equals(Pair.Key, Keys[K]), AName + ': ExtractPair miss returns the requested key');
            end;
          end;
        14:
          begin
            V := AMakeValue(I);
            Raised := False;
            try
              ADictionary.Add(Keys[K], V);
            except
              on EListError do
                Raised := True;
            end;
            Check(Raised = Present[K], AName + ': Add raises exactly for a present key');
            if not Raised then
            begin
              Inc(Count);
              Present[K] := True;
              Values[K] := V;
            end;
          end;
        15:
          begin
            Check(ADictionary.Count = Count, AName + ': Count');
            if I mod 512 = 0 then
            begin
              ADictionary.TrimExcess;
              Check((ADictionary.Count = Count) and (ADictionary.Capacity >= Count),
                AName + ': TrimExcess keeps the items');
            end;
          end;
        16:
          if I mod 1024 = 0 then
            ADictionary.Capacity := ADictionary.Count * 4 + 16;
        17:
          if I mod 3000 = 0 then
          begin
            ADictionary.Clear;
            for K := 0 to AKeySpace - 1 do
              Present[K] := False;
            Count := 0;
          end;
      end;
      Check(ADictionary.Count = Count, AName + ': Count after operation');
      if I mod 2500 = 0 then
        Verify(AName, ADictionary, Comparer, Keys, Present, Values, ASameValue);
    end;
    Verify(AName, ADictionary, Comparer, Keys, Present, Values, ASameValue);
    ADictionary.Clear;
    for K := 0 to AKeySpace - 1 do
      Present[K] := False;
    Verify(AName + ' cleared', ADictionary, Comparer, Keys, Present, Values, ASameValue);
    for K := 0 to AKeySpace - 1 do
      if K mod 3 = 0 then
      begin
        Values[K] := AMakeValue(K);
        ADictionary.Add(Keys[K], Values[K]);
        Present[K] := True;
      end;
    Verify(AName + ' refilled', ADictionary, Comparer, Keys, Present, Values, ASameValue);
  finally
    ADictionary.Free;
  end;
end;

{ key and value makers }

function MakeInteger(AIndex: Integer): Integer;
begin
  Result := AIndex * 7919 - 1000000;
end;

function MakeInt64(AIndex: Integer): Int64;
begin
  Result := (Int64(AIndex) shl 32) + (AIndex xor 5);
end;

function MakeQWord(AIndex: Integer): QWord;
begin
  Result := QWord(AIndex) * QWord($9E3779B97F4A7C15);
end;

function MakeCardinal(AIndex: Integer): Cardinal;
begin
  Result := Cardinal(AIndex) * 2654435761;
end;

function MakeWord(AIndex: Integer): Word;
begin
  Result := Word(AIndex * 40503);
end;

function MakeByte(AIndex: Integer): Byte;
begin
  Result := Byte(AIndex * 37);
end;

function MakeEnum(AIndex: Integer): TEnumKey;
begin
  Result := TEnumKey(AIndex);
end;

function MakeBoolean(AIndex: Integer): Boolean;
begin
  Result := AIndex <> 0;
end;

function MakeWideChar(AIndex: Integer): WideChar;
begin
  Result := WideChar($100 + AIndex);
end;

{ index 0 is the empty string: a key of length 0 has no character to hash }
function MakeString(AIndex: Integer): string;
begin
  if AIndex = 0 then
    Result := ''
  else
    Result := 'key-' + IntToStr(AIndex);
end;

function MakeAnsiString(AIndex: Integer): AnsiString;
begin
  if AIndex = 0 then
    Result := ''
  else
    Result := AnsiString('k' + IntToStr(AIndex * 3));
end;

function MakeShortInt(AIndex: Integer): ShortInt;
begin
  Result := ShortInt(AIndex * 37 - 128);
end;

function MakeSmallInt(AIndex: Integer): SmallInt;
begin
  Result := SmallInt(AIndex * 40503 - 32768);
end;

function MakePointer(AIndex: Integer): Pointer;
begin
  Result := Pointer(NativeUInt($1C8A3F40000) + NativeUInt(AIndex) * 32);
end;

function MakeObject(AIndex: Integer): TObject;
begin
  Result := ObjectPool[AIndex];
end;

function MakeClass(AIndex: Integer): TClass;
begin
  case AIndex of
    0: Result := TObject;
    1: Result := TCounted;
    2: Result := TNotifyLog;
  else
    Result := TLayoutProbe;
  end;
end;

function MakeRecord(AIndex: Integer): TRecordKey;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.A := AIndex;
  Result.B := Int64(AIndex) * 3;
end;

function MakeDouble(AIndex: Integer): Double;
begin
  Result := AIndex * 0.5 - 100;
end;

function MakeIntegerValue(ASeed: Integer): Integer;
begin
  Result := ASeed xor $5A5A;
end;

function MakeStringValue(ASeed: Integer): string;
begin
  Result := 'value ' + IntToStr(ASeed);
end;

function SameInteger(const ALeft, ARight: Integer): Boolean;
begin
  Result := ALeft = ARight;
end;

function SameString(const ALeft, ARight: string): Boolean;
begin
  Result := ALeft = ARight;
end;

{ 1. which dictionaries take the flat path }

procedure CheckFlatSelection;
var
  Custom: IEqualityComparer<Integer>;
begin
  Custom := TConstantHashComparer.Create;
  Check(TDictionary<Integer, Integer>.Create.Flat, 'Integer key is flat');
  Check(TDictionary<Integer, Integer>.Create(4096).Flat, 'Integer key with capacity is flat');
  Check(TDictionary<Integer, Integer>.Create(TEqualityComparer<Integer>.Default).Flat,
    'the explicit default comparer is the same instance');
  Check(not TDictionary<Integer, Integer>.Create(Custom).Flat, 'custom comparer is not flat');
  Check(not TDictionary<Integer, Integer>.Create(4096, Custom).Flat,
    'custom comparer with capacity is not flat');
  Check(TDictionary<Int64, Integer>.Create.Flat, 'Int64 key is flat');
  Check(TDictionary<QWord, Integer>.Create.Flat, 'QWord key is flat');
  Check(TDictionary<Cardinal, Integer>.Create.Flat, 'Cardinal key is flat');
  Check(TDictionary<Word, Integer>.Create.Flat, 'Word key is flat');
  Check(TDictionary<Byte, Integer>.Create.Flat, 'Byte key is flat');
  Check(TDictionary<TEnumKey, Integer>.Create.Flat, 'enum key is flat');
  Check(TDictionary<Boolean, Integer>.Create.Flat, 'Boolean key is flat');
  Check(TDictionary<AnsiChar, Integer>.Create.Flat, 'AnsiChar key is flat');
  Check(TDictionary<WideChar, Integer>.Create.Flat, 'WideChar key is flat');
  Check(TDictionary<string, TObject>.Create.Flat, 'string key is flat');
  Check(TDictionary<AnsiString, Integer>.Create.Flat, 'AnsiString key is flat');
  Check(not TDictionary<string, Integer>.Create(TIStringComparer.Ordinal).Flat,
    'case-insensitive string comparer is not flat');
  Check(TDictionary<Pointer, Integer>.Create.Flat, 'Pointer key is flat');
  Check(TDictionary<TObject, TDateTime>.Create.Flat, 'TObject key is flat');
  Check(TDictionary<TClass, Integer>.Create.Flat, 'TClass key is flat');
  Check(not TDictionary<TRecordKey, Integer>.Create.Flat, 'record key is not flat');
  Check(not TDictionary<Double, Integer>.Create.Flat, 'Double key is not flat');
  Check(not TDictionary<Single, Integer>.Create.Flat, 'Single key is not flat');
  Check(not TDictionary<TBytes, Integer>.Create.Flat, 'dynamic array key is not flat');
  Check(TProbeDictionary.Create.Flat, 'a descendant is flat');
  Check(TOverridingDictionary.Create.Flat, 'a descendant with notifications is flat');
end;

{ 2. model-checked operation mix per key kind }

procedure CheckOperationMix;
var
  I: Integer;
  Custom: IEqualityComparer<Integer>;
begin
  SetLength(ObjectPool, 2048);
  for I := 0 to High(ObjectPool) do
    ObjectPool[I] := TObject.Create;
  try
    TExercise<Integer, Integer>.Run('Integer', TDictionary<Integer, Integer>.Create, True,
      MakeInteger, MakeIntegerValue, SameInteger, 2000, 24000);
    TExercise<Integer, string>.Run('Integer/string', TDictionary<Integer, string>.Create, True,
      MakeInteger, MakeStringValue, SameString, 1000, 16000);
    TExercise<Int64, Integer>.Run('Int64', TDictionary<Int64, Integer>.Create(4096), True,
      MakeInt64, MakeIntegerValue, SameInteger, 2000, 16000);
    TExercise<QWord, Integer>.Run('QWord', TDictionary<QWord, Integer>.Create, True,
      MakeQWord, MakeIntegerValue, SameInteger, 1000, 12000);
    TExercise<Cardinal, Integer>.Run('Cardinal', TDictionary<Cardinal, Integer>.Create, True,
      MakeCardinal, MakeIntegerValue, SameInteger, 1000, 12000);
    TExercise<Word, Integer>.Run('Word', TDictionary<Word, Integer>.Create, True,
      MakeWord, MakeIntegerValue, SameInteger, 1000, 12000);
    TExercise<Byte, Integer>.Run('Byte', TDictionary<Byte, Integer>.Create, True,
      MakeByte, MakeIntegerValue, SameInteger, 256, 8000);
    TExercise<ShortInt, Integer>.Run('ShortInt', TDictionary<ShortInt, Integer>.Create, True,
      MakeShortInt, MakeIntegerValue, SameInteger, 256, 8000);
    TExercise<SmallInt, Integer>.Run('SmallInt', TDictionary<SmallInt, Integer>.Create, True,
      MakeSmallInt, MakeIntegerValue, SameInteger, 1000, 12000);
    TExercise<TEnumKey, Integer>.Run('enum', TDictionary<TEnumKey, Integer>.Create, True,
      MakeEnum, MakeIntegerValue, SameInteger, 8, 4000);
    TExercise<Boolean, Integer>.Run('Boolean', TDictionary<Boolean, Integer>.Create, True,
      MakeBoolean, MakeIntegerValue, SameInteger, 2, 3000);
    TExercise<WideChar, Integer>.Run('WideChar', TDictionary<WideChar, Integer>.Create, True,
      MakeWideChar, MakeIntegerValue, SameInteger, 1000, 12000);
    TExercise<string, Integer>.Run('string', TDictionary<string, Integer>.Create, True,
      MakeString, MakeIntegerValue, SameInteger, 2000, 16000);
    TExercise<string, string>.Run('string/string', TDictionary<string, string>.Create(64), True,
      MakeString, MakeStringValue, SameString, 1000, 12000);
    TExercise<AnsiString, Integer>.Run('AnsiString', TDictionary<AnsiString, Integer>.Create, True,
      MakeAnsiString, MakeIntegerValue, SameInteger, 1000, 12000);
    TExercise<Pointer, Integer>.Run('Pointer', TDictionary<Pointer, Integer>.Create, True,
      MakePointer, MakeIntegerValue, SameInteger, 2000, 16000);
    TExercise<TObject, Integer>.Run('TObject', TDictionary<TObject, Integer>.Create, True,
      MakeObject, MakeIntegerValue, SameInteger, 2048, 16000);
    TExercise<TClass, Integer>.Run('TClass', TDictionary<TClass, Integer>.Create, True,
      MakeClass, MakeIntegerValue, SameInteger, 4, 3000);
    { comparer path: record, float, custom comparers }
    TExercise<TRecordKey, Integer>.Run('record', TDictionary<TRecordKey, Integer>.Create, False,
      MakeRecord, MakeIntegerValue, SameInteger, 1000, 12000);
    TExercise<Double, Integer>.Run('Double', TDictionary<Double, Integer>.Create, False,
      MakeDouble, MakeIntegerValue, SameInteger, 1000, 12000);
    TExercise<string, Integer>.Run('string case-insensitive',
      TDictionary<string, Integer>.Create(TIStringComparer.Ordinal), False,
      MakeString, MakeIntegerValue, SameInteger, 1000, 12000);
    Custom := TConstantHashComparer.Create;
    TExercise<Integer, Integer>.Run('Integer constant hash',
      TDictionary<Integer, Integer>.Create(Custom), False,
      MakeInteger, MakeIntegerValue, SameInteger, 48, 6000);
  finally
    for I := 0 to High(ObjectPool) do
      ObjectPool[I].Free;
    ObjectPool := nil;
  end;
end;

{ the case-insensitive comparer path still folds case }

procedure CheckCaseInsensitiveComparerPath;
var
  D: TDictionary<string, Integer>;
  V: Integer;
begin
  D := TDictionary<string, Integer>.Create(TIStringComparer.Ordinal);
  try
    D.Add('BTCUSDT', 1);
    Check(D.TryGetValue('btcusdt', V) and (V = 1), 'case-insensitive lookup');
    D.AddOrSetValue('BtcUsdt', 2);
    Check((D.Count = 1) and (D['BTCUSDT'] = 2), 'case-insensitive update');
    D.Remove('BTCusdt');
    Check(D.Count = 0, 'case-insensitive remove');
  finally
    D.Free;
  end;
end;

{ construction contracts of Delphi's TDictionary: a copied dictionary is flat
  and equal; a source collection with repeated keys keeps the last value
  instead of raising; a nil comparer means the default one; a capacity
  reserves room for that many items without a rehash }

procedure CheckCopyConstruction;
var
  Source: TDictionary<Integer, Integer>;
  Copy: TDictionary<Integer, Integer>;
  List: TList<TPair<Integer, Integer>>;
  I: Integer;
begin
  Source := TDictionary<Integer, Integer>.Create;
  List := TList<TPair<Integer, Integer>>.Create;
  Copy := nil;
  try
    for I := 0 to 999 do
      Source.Add(I * 3, I);
    List.AddRange(Source.ToArray);
    Copy := TDictionary<Integer, Integer>.Create(List);
    Check(Copy.Flat, 'copy is flat');
    Check(Copy.Count = 1000, 'copy count');
    for I := 0 to 999 do
      Check(Copy[I * 3] = I, 'copy content');
    FreeAndNil(Copy);

    List.Add(TPair<Integer, Integer>.Create(3, -1));
    List.Add(TPair<Integer, Integer>.Create(3, -2));
    Copy := TDictionary<Integer, Integer>.Create(List);
    Check((Copy.Count = 1000) and (Copy[3] = -2), 'repeated keys in the source: the last value wins');
    FreeAndNil(Copy);
    Copy := TDictionary<Integer, Integer>.Create([TPair<Integer, Integer>.Create(1, 10),
      TPair<Integer, Integer>.Create(2, 20), TPair<Integer, Integer>.Create(1, 11)]);
    Check((Copy.Count = 2) and (Copy[1] = 11) and (Copy[2] = 20) and Copy.Flat, 'construction from an array');
  finally
    Copy.Free;
    List.Free;
    Source.Free;
  end;
end;

procedure CheckNilComparer;
var
  Comparer: IEqualityComparer<Integer>;
  D: TDictionary<Integer, Integer>;
  V: Integer;
begin
  Comparer := nil;
  D := TDictionary<Integer, Integer>.Create(Comparer);
  try
    Check(D.Flat, 'a nil comparer is the default comparer');
    D.Add(5, 50);
    Check(D.TryGetValue(5, V) and (V = 50), 'lookup with the defaulted comparer');
  finally
    D.Free;
  end;
  D := TDictionary<Integer, Integer>.Create(64, Comparer);
  try
    Check(D.Flat and (D.Capacity >= 64), 'nil comparer with a capacity');
  finally
    D.Free;
  end;
  Comparer := TEqualityComparer<Integer>.Default;
  D := TDictionary<Integer, Integer>.Create(Comparer);
  try
    Check(D.Flat, 'an explicit default comparer is still flat');
    D.Add(5, 50);
    Check(D.TryGetValue(5, V) and (V = 50), 'lookup with an explicit default comparer');
  finally
    D.Free;
  end;
end;

procedure CheckSparseComparer;
var
  D: TDictionary<TSparseKey, Integer>;
  Comparer: IEqualityComparer<TSparseKey>;
  I: Integer;
begin
  { Repeated construction must not remember the address of a freed
    binary comparer. Exercise both the implicit and explicit defaults. }
  for I := 1 to 32 do
  begin
    D := TDictionary<TSparseKey, Integer>.Create;
    try
      Check(not D.Flat, 'a sparse enum keeps the comparer path');
      D.Add(skA, 10);
      D.Add(skB, 20);
      D.Add(skC, 50);
      Check((D.Count = 3) and (D[skB] = 20), 'sparse enum keys remain distinct');
    finally
      D.Free;
    end;
    Comparer := TEqualityComparer<TSparseKey>.Default;
    D := TDictionary<TSparseKey, Integer>.Create(Comparer);
    try
      Check(not D.Flat, 'an explicit sparse enum comparer is not flat');
      D.Add(skC, 50);
      Check(D.ContainsKey(skC) and not D.ContainsKey(skA), 'explicit sparse enum lookup');
    finally
      D.Free;
    end;
    Comparer := nil;
  end;
end;

procedure CheckReservedCapacity;
const
  Reservations: array[0..6] of Integer = (1, 7, 8, 100, 384, 1000, 4096);
var
  D: TDictionary<Integer, Integer>;
  Reserved, I: Integer;
begin
  { the table must not move at any point of the fill: a reservation that is
    dropped on the first Add and grown back by the last one ends at the same
    size, so the size is checked after every add, not once at the end }
  for Reserved in Reservations do
  begin
    D := TDictionary<Integer, Integer>.Create(Reserved);
    try
      Check(D.Capacity >= Reserved, 'capacity covers the reservation');
      I := D.Capacity;
      while D.Count < Reserved do
      begin
        D.Add(D.Count * 7, D.Count);
        Check(D.Capacity = I, Format('%d reserved items were added without a rehash', [Reserved]));
      end;
      D.Clear;
      D.Capacity := Reserved;
      I := D.Capacity;
      while D.Count < Reserved do
      begin
        D.Add(D.Count * 7, D.Count);
        Check(D.Capacity = I, Format('Capacity := %d reserves room for that many items', [Reserved]));
      end;
      D.TrimExcess;
      Check((D.Count = Reserved) and (D.Capacity >= Reserved), 'TrimExcess keeps the items');
    finally
      D.Free;
    end;
  end;
end;

{ keys whose stored flat hash collides must still be told apart: the
  Integer pairs have MurmurHash3 finalizer values that differ only in the
  sign bit the table keeps for "occupied", the Int64 pairs share the low
  32 bits of the 64-bit finalizer }

procedure CheckCollidingKeys;
const
  IntPairs: array[0..5, 0..1] of Integer = (
    (7, 275898385), (42, -2010658066), (1000, 638699191),
    (123456, 1351519481), (-5, 1307136516), (2026, -1121035474));
  LongPairs: array[0..3, 0..1] of Int64 = (
    (595923707400, 1030971427366), (110260407205, 118459457371),
    (387756769962, 330881842300), (360595024070, 230702259642));
var
  Ints: TDictionary<Integer, Integer>;
  Longs: TDictionary<Int64, Integer>;
  Pointers: TDictionary<Pointer, Integer>;
  I: Integer;
begin
  Ints := TDictionary<Integer, Integer>.Create;
  Longs := TDictionary<Int64, Integer>.Create;
  Pointers := TDictionary<Pointer, Integer>.Create;
  try
    for I := 0 to High(IntPairs) do
    begin
      Ints.Add(IntPairs[I, 0], 1);
      Check(not Ints.ContainsKey(IntPairs[I, 1]), 'colliding Integer key is absent');
      Ints.Add(IntPairs[I, 1], 2);
      Check((Ints[IntPairs[I, 0]] = 1) and (Ints[IntPairs[I, 1]] = 2),
        'colliding Integer keys are distinct');
      Check(not Ints.TryAdd(IntPairs[I, 1], 3), 'colliding Integer key found by TryAdd');
      Ints.Remove(IntPairs[I, 0]);
      Check((not Ints.ContainsKey(IntPairs[I, 0])) and (Ints[IntPairs[I, 1]] = 2),
        'colliding Integer key survives the removal of its twin');
    end;
    Check(Ints.Count = Length(IntPairs), 'colliding Integer count');
    for I := 0 to High(LongPairs) do
    begin
      Longs.Add(LongPairs[I, 0], 1);
      Check(not Longs.ContainsKey(LongPairs[I, 1]), 'colliding Int64 key is absent');
      Longs.Add(LongPairs[I, 1], 2);
      Check((Longs[LongPairs[I, 0]] = 1) and (Longs[LongPairs[I, 1]] = 2),
        'colliding Int64 keys are distinct');
      Longs.Remove(LongPairs[I, 1]);
      Check((not Longs.ContainsKey(LongPairs[I, 1])) and (Longs[LongPairs[I, 0]] = 1),
        'colliding Int64 key survives the removal of its twin');
      Pointers.Add(Pointer(LongPairs[I, 0]), 1);
      Pointers.Add(Pointer(LongPairs[I, 1]), 2);
      Check((Pointers[Pointer(LongPairs[I, 0])] = 1) and (Pointers[Pointer(LongPairs[I, 1])] = 2),
        'colliding Pointer keys are distinct');
    end;
    Check((Longs.Count = Length(LongPairs)) and (Pointers.Count = 2 * Length(LongPairs)),
      'colliding Int64/Pointer counts');
  finally
    Pointers.Free;
    Longs.Free;
    Ints.Free;
  end;
end;

{ the base-class methods (statically bound through a base reference) share
  the table with the flat ones: same hash, same slots, same values }

procedure CheckBaseClassReference;
var
  D: TDictionary<Integer, Integer>;
  Base: TOpenAddressingLP<Integer, Integer, TDefaultHashFactory, TLinearProbing>;
  I, V: Integer;
begin
  D := TDictionary<Integer, Integer>.Create;
  try
    Base := D;
    for I := 0 to 999 do
      Base.AddOrSetValue(I, I * 2);
    Check(D.Count = 1000, 'base AddOrSetValue count');
    for I := 0 to 999 do
      Check(D.TryGetValue(I, V) and (V = I * 2), 'flat lookup of base-inserted keys');
    for I := 0 to 999 do
      Base.AddOrSetValue(I, I * 3);
    Check(D.Count = 1000, 'base update count');
    for I := 0 to 999 do
      Check(D[I] = I * 3, 'base update seen by the flat path');
    Base[5] := 55;
    Check((D[5] = 55) and (Base[5] = 55), 'base Items write');
    D.AddOrSetValue(7, 77);
    Check(Base.TryGetValue(7, V) and (V = 77), 'base lookup of a flat-updated key');
    Check(Base.ContainsKey(999) and not Base.ContainsKey(1000), 'base ContainsKey');
    Base.Remove(1);
    Check((not D.ContainsKey(1)) and (Base.Count = 999), 'base Remove');
    Check(Base.TryAdd(1, 11) and (D[1] = 11), 'base TryAdd');
  finally
    D.Free;
  end;
end;

{ object keys with value equality: Equals/GetHashCode overrides decide,
  on the flat path (TDictionary), on the comparer path (TObjectDictionary,
  a base-typed reference) and for a plain object (identity) in the same
  table }

procedure CheckObjectKeyEquality;
var
  D: TDictionary<TObject, Integer>;
  Owning: TObjectDictionary<TValueKey, Integer>;
  A1, A2, B: TValueKey;
  P1, P2: TObject;
  Pair: TPair<TObject, Integer>;
  V: Integer;
begin
  A1 := TValueKey.Create(1);
  A2 := TValueKey.Create(1);
  B := TValueKey.Create(2);
  P1 := TIdentityKey.Create;
  P2 := TIdentityKey.Create;
  D := TDictionary<TObject, Integer>.Create;
  try
    Check(D.Flat, 'object keys take the flat path');
    D.Add(A1, 10);
    Check(D.ContainsKey(A2), 'an equal instance finds the key');
    Check(D.TryGetValue(A2, V) and (V = 10), 'lookup by an equal instance');
    Check(not D.ContainsKey(B), 'a different Id is another key');
    D.AddOrSetValue(A2, 11);
    Check((D.Count = 1) and (D[A1] = 11), 'AddOrSetValue by an equal instance updates, not adds');
    Check(not D.TryAdd(A2, 12) and (D[A1] = 11), 'TryAdd by an equal instance is rejected');
    D.Add(B, 20);
    D.Add(P1, 30);
    Check(D.ContainsKey(P1) and not D.ContainsKey(P2), 'identity object equals itself only');
    D.Add(P2, 31);
    Check(D.Count = 4, 'four keys: two value keys, two identity keys');
    Pair := D.ExtractPair(A2);
    Check((Pair.Value = 11) and (D.Count = 3) and not D.ContainsKey(A1), 'ExtractPair by an equal instance');
    D.Remove(P2);
    Check((D.Count = 2) and D.ContainsKey(P1) and D.ContainsKey(B), 'Remove of an identity key');
    D.Add(A1, 13);
    Check(D[A2] = 13, 'value key re-added and found by the twin');
  finally
    D.Free;
  end;

  { the comparer path: TObjectDictionary is not on the flat path, its
    default comparer must dispatch the same way }
  Destroyed := 0;
  Owning := TObjectDictionary<TValueKey, Integer>.Create([doOwnsKeys]);
  try
    Owning.Add(TValueKey.Create(7), 70);
    Owning.Add(TValueKey.Create(8), 80);
    Check(Owning.ContainsKey(A1) = False, 'comparer path: a different Id is absent');
    A1.Id := 7;
    Check(Owning.TryGetValue(A1, V) and (V = 70), 'comparer path: an equal instance finds the key');
    Owning.AddOrSetValue(A1, 71);
    Check((Owning.Count = 2) and (Destroyed = 0), 'comparer path: update by an equal instance keeps the owned key');
    Owning.Remove(A1);
    Check((Owning.Count = 1) and (Destroyed = 1), 'comparer path: Remove by an equal instance frees the owned key');
    A1.Id := 1;
  finally
    Owning.Free;
  end;
  Check(Destroyed = 2, 'comparer path: the remaining owned key freed');
  A1.Free; A2.Free; B.Free; P1.Free; P2.Free;
end;

{ 3. notifications }

procedure CheckNotifyFlag;
var
  D: TProbeDictionary;
  Log: TNotifyLog;
  Pair: TPair<Integer, Integer>;
  Snapshot: Integer;
begin
  D := TProbeDictionary.Create;
  Log := TNotifyLog.Create;
  try
    Check(not D.Active, 'no handler: notifications inactive');
    D.Add(1, 10);
    D.AddOrSetValue(1, 11);
    D[1] := 12;
    D.Remove(1);
    D.Clear;
    Check(D.Count = 0, 'silent operations');

    D.OnKeyNotify := Log.KeyEvent;
    Check(D.Active, 'key handler activates notifications');
    Check(D.Flat, 'a handler does not leave the flat path');
    D.Add(1, 10);
    Check((Log.KeyAdded = 1) and (Log.ValueAdded = 0) and (Log.LastKey = 1),
      'key handler alone');

    D.OnValueNotify := Log.ValueEvent;
    D.Add(2, 20);
    Check((Log.KeyAdded = 2) and (Log.ValueAdded = 1) and (Log.LastValue = 20),
      'both handlers on Add');
    D.AddOrSetValue(2, 21);
    Check((Log.KeyAdded = 2) and (Log.ValueRemoved = 1) and (Log.ValueAdded = 2) and
      (Log.LastValue = 21) and (Log.LastValueAction = cnAdded),
      'AddOrSetValue of an existing key: value removed then added, no key event');
    D[2] := 22;
    Check((Log.ValueRemoved = 2) and (Log.ValueAdded = 3) and (Log.LastValue = 22),
      'Items write: value removed then added');
    D.AddOrSetValue(3, 30);
    Check((Log.KeyAdded = 3) and (Log.ValueAdded = 4), 'AddOrSetValue of a new key adds');
    Check(not D.TryAdd(3, 31), 'TryAdd of an existing key');
    Check(Log.Total = 9, 'failed TryAdd is silent');
    D.Remove(3);
    Check((Log.KeyRemoved = 1) and (Log.ValueRemoved = 3) and (Log.LastKey = 3) and
      (Log.LastValue = 30), 'Remove notifies key and value');
    D.Remove(99);
    Check(Log.Total = 11, 'Remove of a missing key is silent');
    Pair := D.ExtractPair(2);
    Check((Pair.Key = 2) and (Pair.Value = 22) and (Log.KeyExtracted = 1) and
      (Log.ValueExtracted = 1), 'ExtractPair notifies cnExtracted');
    Snapshot := Log.Total;
    D.Capacity := 1024;
    D.TrimExcess;
    Check(Log.Total = Snapshot, 'rehash is silent');
    D.Add(4, 40);
    D.Add(5, 50);
    Check((D.Count = 3) and (Log.KeyAdded = 5) and (Log.ValueAdded = 6), 'adds after rehash');

    D.OnKeyNotify := nil;
    Check(D.Active, 'value handler keeps notifications active');
    D.Remove(4);
    Check((Log.KeyRemoved = 1) and (Log.ValueRemoved = 4), 'key handler removed at run time');
    D.OnValueNotify := nil;
    Check(not D.Active, 'both handlers removed: inactive');
    Snapshot := Log.Total;
    D.Remove(5);
    D.AddOrSetValue(1, 13);
    D.Add(6, 60);
    D.Clear;
    Check((Log.Total = Snapshot) and (D.Count = 0), 'silent again');

    D.Add(7, 70);
    D.Add(8, 80);
    D.OnKeyNotify := Log.KeyEvent;
    D.Clear;
    Check((Log.KeyRemoved = 3) and (Log.ValueRemoved = 4), 'Clear notifies every key');
    D.OnKeyNotify := nil;
  finally
    D.Free;
    Log.Free;
  end;
end;

procedure CheckOverrides;
var
  D: TOverridingDictionary;
  Owning: TOwningValueDictionary;
  Log: TNotifyLog;
  Extracted: TCounted;
begin
  OverrideKeyEvents := 0;
  OverrideValueEvents := 0;
  D := TOverridingDictionary.Create;
  Log := TNotifyLog.Create;
  try
    Check(D.Active, 'overridden KeyNotify/ValueNotify are active without a handler');
    D.Add(1, 10);
    Check((OverrideKeyEvents = 1) and (OverrideValueEvents = 1), 'override on Add');
    D.AddOrSetValue(1, 11);
    Check((OverrideKeyEvents = 1) and (OverrideValueEvents = 3), 'override on update');
    D[1] := 12;
    Check(OverrideValueEvents = 5, 'override on Items write');
    D.Remove(1);
    Check((OverrideKeyEvents = 2) and (OverrideValueEvents = 6), 'override on Remove');
    D.Add(2, 20);
    D.Add(3, 30);
    D.Clear;
    Check((OverrideKeyEvents = 6) and (OverrideValueEvents = 10), 'override on Clear');
    { a handler on top of the overrides: both run, the inherited call reaches it }
    D.OnValueNotify := Log.ValueEvent;
    D.Add(4, 40);
    Check((OverrideValueEvents = 11) and (Log.ValueAdded = 1), 'override and handler');
    D.OnValueNotify := nil;
    Check(D.Active, 'still active after the handler is removed');
    D.Add(5, 50);
    Check((OverrideKeyEvents = 8) and (Log.Total = 1), 'override without handler again');
  finally
    D.Free;
  end;
  Check((OverrideKeyEvents = 10) and (OverrideValueEvents = 14), 'Destroy clears with notifications');
  Log.Free;

  Destroyed := 0;
  Owning := TOwningValueDictionary.Create;
  try
    Check(Owning.Active, 'overriding ValueNotify alone is active');
    Owning.Add(1, TCounted.Create(1));
    Owning.Add(2, TCounted.Create(2));
    Owning.AddOrSetValue(1, TCounted.Create(11));
    Check(Destroyed = 1, 'replaced value freed by the override');
    Owning[2] := TCounted.Create(22);
    Check(Destroyed = 2, 'replaced value on Items write freed');
    Owning.Add(3, TCounted.Create(3));
    Owning.Remove(3);
    Check(Destroyed = 3, 'removed value freed');
    Extracted := Owning.ExtractPair(2).Value;
    Check((Destroyed = 3) and (Extracted.Id = 22), 'extracted value survives');
    Extracted.Free;
    Check(Destroyed = 4, 'extracted value freed by the caller');
  finally
    Owning.Free;
  end;
  Check(Destroyed = 5, 'remaining value freed on Destroy');
end;

procedure CheckObjectOwnership;
var
  Values: TObjectDictionary<Integer, TCounted>;
  Keys: TObjectDictionary<TCounted, Integer>;
  Log: TObjectNotifyLog;
  Extracted, KeyA, KeyB, KeyC: TCounted;
begin
  Destroyed := 0;
  Log := TObjectNotifyLog.Create;
  Values := TObjectDictionary<Integer, TCounted>.Create([doOwnsValues]);
  try
    Values.Add(1, TCounted.Create(1));
    Values.Add(2, TCounted.Create(2));
    Values.Add(3, TCounted.Create(3));
    Values.AddOrSetValue(1, TCounted.Create(11));
    Check(Destroyed = 1, 'owned value replaced by AddOrSetValue is freed');
    Values[2] := TCounted.Create(22);
    Check(Destroyed = 2, 'owned value replaced by Items write is freed');
    Values.Remove(3);
    Check(Destroyed = 3, 'owned value removed is freed');
    Extracted := Values.ExtractPair(2).Value;
    Check((Destroyed = 3) and (Extracted.Id = 22), 'extracted value is not freed');
    Extracted.Free;
    Values.Add(5, TCounted.Create(5));
    Values.Add(6, TCounted.Create(6));
    Values.Clear;
    Check((Destroyed = 7) and (Values.Count = 0), 'Clear frees every owned value');
    Values.Add(7, TCounted.Create(7));
    Values.Add(8, TCounted.Create(8));
    Values.OnValueNotify := Log.ValueEvent;
    Values.Remove(7);
    Check((Destroyed = 8) and (Log.Removed = 1), 'handler and ownership together');
    Values.ExtractPair(8).Value.Free;
    Check((Destroyed = 9) and (Log.Extracted = 1), 'extraction with a handler');
    Values.OnValueNotify := nil;
    Values.Add(9, TCounted.Create(9));
  finally
    Values.Free;
  end;
  Check(Destroyed = 10, 'Destroy frees the remaining owned value');

  Destroyed := 0;
  KeyA := TCounted.Create(1);
  KeyB := TCounted.Create(2);
  KeyC := TCounted.Create(3);
  Keys := TObjectDictionary<TCounted, Integer>.Create([doOwnsKeys]);
  try
    Keys.Add(KeyA, 1);
    Keys.Add(KeyB, 2);
    Keys.Add(KeyC, 3);
    Check(Keys.Count = 3, 'owned keys added');
    Keys.Remove(KeyA);
    Check(Destroyed = 1, 'owned key removed is freed');
    Check(Keys.ExtractPair(KeyB).Key = KeyB, 'extracted key returned');
    Check(Destroyed = 1, 'extracted key is not freed');
    KeyB.Free;
    Check((Destroyed = 2) and (Keys.Count = 1), 'extracted key freed by the caller');
  finally
    Keys.Free;
  end;
  Check(Destroyed = 3, 'remaining owned key freed on Destroy');
  Log.Free;
end;

{ 4. hash spread over the populations that collapsed under the byte CRC }

{ the fixed populations are deterministic (about 3 under the flat hash,
  8.2 to 18.5 under the byte CRC); the addresses of allocated objects are
  not, a random-like hash stays below 5 on them (simulated: mean 3.0,
  max 5.0 over 3000 allocator-like populations) }
procedure CheckSpreadCost(const AName: string; AProbe: TLayoutProbe; ACount: Integer;
  ABound: Double);
var
  Cost: Double;
begin
  Cost := AProbe.ClusterCost(ACount);
  Check(Cost < ABound, Format('%s: cluster cost %.2f', [AName, Cost]));
end;

procedure CheckPointerSpread(const AName: string; const AKeys: TArray<Pointer>;
  ABound: Double);
var
  D: TDictionary<Pointer, Integer>;
  Probe: TLayoutProbe;
  I: Integer;
begin
  D := TDictionary<Pointer, Integer>.Create;
  Probe := TLayoutProbe.Create;
  try
    D.Capacity := 512;                    { room for 512 items: 1024 slots }
    for I := 0 to High(AKeys) do
      D.Add(AKeys[I], I);
    Check(D.Capacity = 1024, AName + ': table not grown');
    SetLength(Probe.Occupied, D.Capacity);
    D.GetMemoryLayout(Probe.Position);
    CheckSpreadCost(AName, Probe, Length(AKeys), ABound);
  finally
    Probe.Free;
    D.Free;
  end;
end;

procedure CheckHashSpread;
var
  Pointers: TArray<Pointer>;
  Objects: TArray<TObject>;
  Ints: TDictionary<Integer, Integer>;
  Longs: TDictionary<Int64, Integer>;
  Probe: TLayoutProbe;
  I, Stride: Integer;
begin
  SetLength(Pointers, 512);
  for Stride in [32, 64] do
  begin
    for I := 0 to 511 do
      Pointers[I] := Pointer(NativeUInt($1C8A3F40000) + NativeUInt(Stride) * NativeUInt(I));
    CheckPointerSpread(Format('pointer stride %d', [Stride]), Pointers, 6.0);
  end;
  SetLength(Objects, 512);
  for I := 0 to 511 do
  begin
    Objects[I] := TObject.Create;
    Pointers[I] := Objects[I];
  end;
  try
    CheckPointerSpread('allocated objects', Pointers, 8.0);
  finally
    for I := 0 to 511 do
      Objects[I].Free;
  end;

  Probe := TLayoutProbe.Create;
  Ints := TDictionary<Integer, Integer>.Create;
  Longs := TDictionary<Int64, Integer>.Create;
  try
    Ints.Capacity := 512;
    for I := 0 to 511 do
      Ints.Add(I, I);
    Check(Ints.Capacity = 1024, 'integer table not grown');
    SetLength(Probe.Occupied, Ints.Capacity);
    Ints.GetMemoryLayout(Probe.Position);
    CheckSpreadCost('sequential integers', Probe, 512, 6.0);

    Longs.Capacity := 512;
    for I := 0 to 511 do
      Longs.Add(Int64(I) shl 32, I);
    Check(Longs.Capacity = 1024, 'Int64 table not grown');
    Probe.Occupied := nil;
    SetLength(Probe.Occupied, Longs.Capacity);
    Longs.GetMemoryLayout(Probe.Position);
    CheckSpreadCost('Int64 high half', Probe, 512, 6.0);
  finally
    Longs.Free;
    Ints.Free;
    Probe.Free;
  end;
end;

begin
  try
    CheckFlatSelection;
    CheckOperationMix;
    CheckCaseInsensitiveComparerPath;
    CheckCopyConstruction;
    CheckNilComparer;
    CheckSparseComparer;
    CheckReservedCapacity;
    CheckCollidingKeys;
    CheckBaseClassReference;
    CheckObjectKeyEquality;
    CheckNotifyFlag;
    CheckOverrides;
    CheckObjectOwnership;
    CheckHashSpread;
    WriteLn('DICTIONARY_FLAT_PASS');
  except
    on E: Exception do
    begin
      WriteLn(ErrOutput, E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
