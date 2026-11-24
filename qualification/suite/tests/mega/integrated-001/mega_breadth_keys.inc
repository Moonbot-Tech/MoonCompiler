{ Packed values crossing generic comparer interfaces and checked narrowing. }

{$ifdef FPC}
  {$if FPC_FULLVERSION <= 30204}
    {$define BREADTH_LEGACY_COMPARER}
  {$endif}
{$endif}

type
  TBreadthHash = {$ifdef BREADTH_LEGACY_COMPARER}Cardinal{$else}Integer{$endif};

  TBreadthLookupKey = packed record
    Padding: Byte;
    Serial: Int64;
    Name: AnsiString;
  end;

  TBreadthKeyComparer = class(TInterfacedObject, IEqualityComparer<TBreadthLookupKey>)
    HashCalls, Comparisons: Integer;
    function Equals({$ifdef BREADTH_LEGACY_COMPARER}constref{$else}const{$endif} Left, Right: TBreadthLookupKey): Boolean;
      reintroduce;
    function GetHashCode({$ifdef BREADTH_LEGACY_COMPARER}constref{$else}const{$endif} Value: TBreadthLookupKey): TBreadthHash;
      reintroduce;
  end;

function TBreadthKeyComparer.Equals(
  {$ifdef BREADTH_LEGACY_COMPARER}constref{$else}const{$endif} Left, Right: TBreadthLookupKey): Boolean;
begin
  Inc(Comparisons);
  Result := (Left.Serial = Right.Serial) and (Left.Name = Right.Name);
end;

function TBreadthKeyComparer.GetHashCode(
  {$ifdef BREADTH_LEGACY_COMPARER}constref{$else}const{$endif} Value: TBreadthLookupKey): TBreadthHash;
begin
  Inc(HashCalls);
  Result := Length(Value.Name) and 3;
end;

procedure RunBreadthDictionaryKeys;
type
  TMap = TDictionary<TBreadthLookupKey, UnicodeString>;
var
  Dict: TMap;
  Comparer: IEqualityComparer<TBreadthLookupKey>;
  Witness: TBreadthKeyComparer;
  A, B, Query: TBreadthLookupKey;
  Value, Snapshot: UnicodeString;
begin
  Witness := TBreadthKeyComparer.Create;
  Comparer := Witness;
  Dict := TMap.Create(Comparer);
  try
    A.Padding := $37;
    A.Serial := OpaqueI(4294967297);
    A.Name := 'ax';
    B := A;
    B.Serial := OpaqueI(-4294967295);
    Dict.Add(A, 'large positive');
    Dict.Add(B, 'large negative');
    Query := A;
    Query.Padding := $89;
    Check(Dict.TryGetValue(Query, Value) and (Value = 'large positive'), 'breadth-dict-comparer-ignores-padding');
    Check(Dict.TryGetValue(B, Value) and (Value = 'large negative'), 'breadth-dict-collision-keeps-full-signed-key');
    Snapshot := Value;
    Query.Name[2] := 'z';
    Check(not Dict.ContainsKey(Query), 'breadth-dict-key-string-snapshot');
    Query := B;
    Query.Padding := $59;
    Dict.AddOrSetValue(Query, 'updated');
    Check(Dict.TryGetValue(B, Value) and (Value = 'updated') and (Dict.Count = 2), 'breadth-dict-equal-key-updates-without-insert');
    Dict.Remove(Query);
    Check((Dict.Count = 1) and not Dict.ContainsKey(B), 'breadth-dict-removes-equivalent-key');
    Check((Snapshot = 'large negative') and Dict.TryGetValue(A, Value) and (Value = 'large positive'),
      'breadth-dict-removal-keeps-other-collision-and-value-copy');
    Check((Witness.HashCalls > 0) and (Witness.Comparisons > 0), 'breadth-dict-used-generic-interface-comparer');
    Mix(UInt64(Length(Value)));
  finally
    Dict.Free;
  end;
end;

type
  TBreadthNarrowPacket = packed record
    Left: Byte;
    Field: Byte;
    Right: Word;
  end;

{$R+}
procedure BreadthImplicitNarrow(var Packet: TBreadthNarrowPacket; Wide: Int64);
begin
  Packet.Field := Wide;
end;

procedure BreadthExplicitNarrow(var Packet: TBreadthNarrowPacket; Wide: Int64);
begin
  Packet.Field := Byte(Wide);
end;
{$R-}

procedure RunBreadthCheckedNarrowAssignment;
const
  Inputs: array[0..6] of Int64 = (0, 255, 256, -1, 4294967313, -4294967280, High(Int64));
  ImplicitValues: array[0..6] of Integer = (0, 255, -1, -1, -1, -1, -1);
  ExplicitValues: array[0..6] of Byte = (0, 255, 0, 255, 17, 16, 255);
var
  Packet: TBreadthNarrowPacket;
  I: Integer;
  Wide: Int64;
  Caught: Boolean;
begin
  Packet.Left := $A3;
  Packet.Right := $CE51;
  for I := Low(Inputs) to High(Inputs) do begin
    Wide := OpaqueI(Inputs[I]);
    Packet.Field := $D7;
    Caught := False;
    try
      BreadthImplicitNarrow(Packet, Wide);
    except
      on ERangeError do Caught := True;
    end;
    Check(Caught = (ImplicitValues[I] < 0), 'breadth-checked-implicit-narrowing-domain');
    If ImplicitValues[I] < 0 then
      Check(Packet.Field = $D7, 'breadth-checked-failed-narrowing-does-not-write')
    else
      Check(Packet.Field = ImplicitValues[I], 'breadth-checked-implicit-narrowing-stores-valid-value');
    BreadthExplicitNarrow(Packet, Wide);
    Check(Packet.Field = ExplicitValues[I], 'breadth-checked-explicit-narrowing-wraps');
    Check((Packet.Left = $A3) and (Packet.Right = $CE51), 'breadth-checked-narrowing-preserves-neighbors');
    Mix(Packet.Field);
  end;
end;

procedure RunBreadthKeyForms;
begin
  RunBreadthDictionaryKeys;
  RunBreadthCheckedNarrowAssignment;
end;
