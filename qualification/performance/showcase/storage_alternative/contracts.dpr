program storage_alternative_contracts;

{$mode delphiunicode}
{$codepage utf8}

uses SysUtils, Generics.Defaults, Astra.Collections;

type
  {$ifdef UTF16}TKey = UnicodeString;{$else}TKey = UTF8String;{$endif}
  TMap = TDictionary<TKey, UnicodeString>;
  TRecordKey = record A, B: Int64; end;
  TCaseComparer = class(TEqualityComparer<TKey>)
    function Equals(const A, B: TKey): Boolean; override;
    function GetHashCode(const Key: TKey): Integer; override;
  end;

procedure Require(B: Boolean; const Why: string);
begin
  If not B then raise Exception.Create(Why);
end;

function TCaseComparer.Equals(const A, B: TKey): Boolean;
begin
  Result := UpperCase(UnicodeString(A)) = UpperCase(UnicodeString(B));
end;

function TCaseComparer.GetHashCode(const Key: TKey): Integer;
begin
  Result := 7; // Force full-hash collisions and custom equality on every probe.
end;

procedure DefaultContracts;
var D: TMap; S, Original: TKey; V: UnicodeString; N: Integer;
    Saved: TArray<TPair<TKey, UnicodeString>>; Extracted: TPair<TKey, UnicodeString>;
begin
  D := TMap.Create;
  S := TKey('owned-' + StringOfChar('x', 200));
  Original := S;
  D.Add(S, 'value');
  Require(D.TryGetValue(S, V) and (V = 'value'), 'Same-pointer lookup');
  for var Pair in D do Require(Pointer(Pair.Key) = Pointer(S), 'Pair retains ordinary string identity');
  S[1] := '!';
  Require(D.TryGetValue(Original, V), 'Source COW');
  D.Add('', 'empty');
  D.Add(TKey('a'#0'b'), 'nul');
  for var I := 0 to 999 do D.Add(TKey(IntToStr(I)), IntToStr(I));
  for var I := 0 to 999 do begin
    If I mod 2 = 0 then D.Remove(TKey(IntToStr(I)))
    else D.AddOrSetValue(TKey(IntToStr(I)), 'updated');
  end;
  for var I := 0 to 999 do begin
    Require(D.TryGetValue(TKey(IntToStr(I)), V) = (I mod 2 <> 0), 'Remove/rehash');
    If I mod 2 <> 0 then Require(V = 'updated', 'Value update');
  end;
  Require(not D.TryAdd('', 'bad'), 'Duplicate TryAdd');
  Require(D.TryGetValue('', V) and (V = 'empty'), 'Empty retained');
  Require(D.TryGetValue(TKey('a'#0'b'), V) and (V = 'nul'), 'Embedded NUL');
  Extracted := D.ExtractPair(Original);
  Require(not D.ContainsKey(Original), 'Extract removed key');
  Saved := D.ToArray;
  N := 0;
  for var Pair in D do Inc(N);
  Require(N = 502, 'Owning enumeration count');
  D.Clear;
  Require(D.Count = 0, 'Clear');
  D.Free;
  Require((Extracted.Key = Original) and (Extracted.Value = 'value'), 'Extract lifetime');
  Require(Length(Saved) = 502, 'Snapshot lifetime');
  S := Extracted.Key;
  S[1] := '!';
  Require(Extracted.Key = Original, 'Current COW after destruction');
  for var Pair in Saved do Require(Pair.Value <> '', 'Managed value survives destruction');
end;

procedure CustomContracts;
var D: TMap; V: UnicodeString;
begin
  D := TMap.Create(TCaseComparer.Create);
  Require(not D.Flat, 'Custom comparer must bypass flat path');
  D.Add('Alpha', 'one');
  D.Add('Beta', 'two');
  Require(D.TryGetValue('ALPHA', V) and (V = 'one'), 'Custom case-insensitive hit');
  Require(D.TryGetValue('BETA', V) and (V = 'two'), 'Custom hash collision');
  Require(not D.TryAdd('alpha', 'bad'), 'Custom duplicate');
  D.Remove('ALPHA');
  Require(D.TryGetValue('beta', V) and (V = 'two'), 'Custom remove collision chain');
  D.Free;
end;

procedure OtherKeyKinds;
var Integers: TDictionary<Integer, UnicodeString>;
    Records: TDictionary<TRecordKey, UnicodeString>; K: TRecordKey; V: UnicodeString;
begin
  Integers := TDictionary<Integer, UnicodeString>.Create;
  Integers.Add(123, 'integer');
  Require(Integers.TryGetValue(123, V) and (V = 'integer'), 'Unchanged ordinal specialization');
  Integers.Free;
  Records := TDictionary<TRecordKey, UnicodeString>.Create;
  K.A := 123;
  K.B := -456;
  Records.Add(K, 'record');
  Require(Records.TryGetValue(K, V) and (V = 'record'), 'Unchanged record specialization');
  Records.Free;
end;

begin
  DefaultContracts;
  CustomContracts;
  OtherKeyKinds;
  Writeln('STORAGE_ALTERNATIVE_CONTRACTS_PASS');
end.
