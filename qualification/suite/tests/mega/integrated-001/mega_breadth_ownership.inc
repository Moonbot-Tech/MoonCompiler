{ Extract and remove have different ownership effects in a generic object dictionary. }

type
  TBreadthOwnedItem = class
    LabelText: AnsiString;
    Slot: Integer;
    class var Releases: UInt32;
    class var ReleaseCount: Integer;
    constructor Create(AIndex: Integer);
    destructor Destroy; override;
  end;

  TBreadthOwnedMap = TObjectDictionary<TBreadthOwnedItem, TBreadthOwnedItem>;
  TBreadthOwnedPair = TPair<TBreadthOwnedItem, TBreadthOwnedItem>;

constructor TBreadthOwnedItem.Create(AIndex: Integer);
begin
  inherited Create;
  Slot := AIndex;
  LabelText := AnsiString('entry-' + IntToStr(AIndex));
end;

destructor TBreadthOwnedItem.Destroy;
begin
  Releases := Releases or (UInt32(1) shl Slot);
  Inc(ReleaseCount);
  inherited;
end;

procedure BreadthAddOwnedPair(Map: TBreadthOwnedMap; KeySlot, ValueSlot: Integer; out Key: TBreadthOwnedItem);
var
  Value: TBreadthOwnedItem;
begin
  Key := TBreadthOwnedItem.Create(KeySlot);
  try
    Value := TBreadthOwnedItem.Create(ValueSlot);
    try
      Map.Add(Key, Value);
    except
      Value.Free;
      raise;
    end;
  except
    Key.Free;
    raise;
  end;
end;

procedure RunBreadthObjectDictionary;
var
  Map: TBreadthOwnedMap;
  Key, OtherKey, Replacement: TBreadthOwnedItem;
  Extracted: TBreadthOwnedPair;
begin
  TBreadthOwnedItem.Releases := 0;
  TBreadthOwnedItem.ReleaseCount := 0;
  Extracted.Key := nil;
  Extracted.Value := nil;
  Map := TBreadthOwnedMap.Create([doOwnsKeys, doOwnsValues]);
  try
    BreadthAddOwnedPair(Map, Integer(OpaqueI(0)), Integer(OpaqueI(1)), Key);
    BreadthAddOwnedPair(Map, Integer(OpaqueI(3)), Integer(OpaqueI(4)), OtherKey);
    Replacement := TBreadthOwnedItem.Create(Integer(OpaqueI(2)));
    try
      Map.AddOrSetValue(Key, Replacement);
    except
      Replacement.Free;
      raise;
    end;
    Check((Map.Count = 2) and (Map[Key] = Replacement) and (TBreadthOwnedItem.Releases = $02),
      'breadth-owned-map-replaces-value-without-releasing-key');
    Extracted := Map.ExtractPair(Key);
    Check((Map.Count = 1) and (Extracted.Key = Key) and (Extracted.Value = Replacement)
      and (TBreadthOwnedItem.Releases = $02), 'breadth-owned-map-extract-transfers-both-objects');
    Map.Remove(OtherKey);
    Check((Map.Count = 0) and (TBreadthOwnedItem.Releases = $1A), 'breadth-owned-map-remove-releases-key-and-value');
    Check((Extracted.Key.LabelText = 'entry-0') and (Extracted.Value.LabelText = 'entry-2'),
      'breadth-owned-map-extracted-pair-keeps-managed-fields');
  finally
    Map.Free;
    Extracted.Value.Free;
    Extracted.Key.Free;
  end;
  Check((TBreadthOwnedItem.Releases = $1F) and (TBreadthOwnedItem.ReleaseCount = 5), 'breadth-owned-map-transfer-receivers-release-extracted-pair');
  Mix(UInt64(TBreadthOwnedItem.Releases));
end;
