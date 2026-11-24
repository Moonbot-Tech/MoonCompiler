{ Shrinking an unlocked Variant array releases precisely its truncated values. }

type
  TBreadthVariantOwner = class(TIntersectionOwner)
    Slot: Integer;
    class var Retired: Byte;
    destructor Destroy; override;
  end;

destructor TBreadthVariantOwner.Destroy;
begin
  Retired := Retired or Byte(1 shl Slot);
  inherited;
end;

procedure BreadthSeedVariantOwner(var Values: Variant; Index: Integer);
var
  ObjectValue: TBreadthVariantOwner;
  Held: IInterface;
begin
  ObjectValue := TBreadthVariantOwner.Create;
  ObjectValue.Slot := Index - 5;
  Held := ObjectValue;
  Values[Index] := Held;
end;

procedure BreadthShrinkVariantOwners;
var
  Values, Saved: Variant;
  I: Integer;
begin
  Values := VarArrayCreate([5, 7], varVariant);
  for I := 5 to 7 do
    BreadthSeedVariantOwner(Values, I);
  Saved := Values[7];
  Check((VarType(Saved) = varUnknown) and (TBreadthVariantOwner.Retired = 0),
    'breadth-variant-array-copy-retains-interface-element');

  VarArrayRedim(Values, Integer(OpaqueI(5)));
  Check((VarArrayLowBound(Values, 1) = 5) and (VarArrayHighBound(Values, 1) = 5)
    and (TBreadthVariantOwner.Retired = $02), 'breadth-variant-array-shrink-releases-only-unretained-truncated-value');
  VarArrayRedim(Values, Integer(OpaqueI(6)));
  Check((VarArrayHighBound(Values, 1) = 6) and VarIsEmpty(Values[6]) and (TBreadthVariantOwner.Retired = $02),
    'breadth-variant-array-regrown-slot-is-empty');

  VarClear(Values);
  Check((TBreadthVariantOwner.Retired = $03) and (VarType(Saved) = varUnknown),
    'breadth-variant-array-clear-leaves-detached-element-owned');
end;

procedure RunBreadthVariantArrayOwners;
begin
  TIntersectionOwner.Destroyed := 0;
  TBreadthVariantOwner.Retired := 0;
  BreadthShrinkVariantOwners;
  Check((TBreadthVariantOwner.Retired = $07) and (TIntersectionOwner.Destroyed = 3),
    'breadth-variant-array-shrink-and-clear-release-each-owner-once');
  Mix(TBreadthVariantOwner.Retired);
end;
