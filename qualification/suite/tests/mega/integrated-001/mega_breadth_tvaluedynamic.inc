{ A boxed dynamic interface array shares its data, and extracted elements remain owned. }

procedure ExerciseBreadthDynamicValue;
type
  TInterfaces = array of IBreadthTaggedOwner;
var
  Values, Alias: TInterfaces;
  Box, First: TValue;
  Empty, Recovered: IBreadthTaggedOwner;
begin
  SetLength(Values, 2);
  Values[0] := TBreadthTaggedOwner.Create;
  Values[1] := TBreadthTaggedOwner.Create;
  Alias := Values;
  Box := TValue.From<TInterfaces>(Values);
  Values := nil;
  Check((Box.Kind = tkDynArray) and (Box.GetArrayLength = 2) and (TBreadthTaggedOwner.Destroyed = 0),
    'breadth-tvalue-dynamic-array-holds-its-shared-interfaces');
  First := Box.GetArrayElement(0);
  Empty := nil;
  Box.SetArrayElement(1, TValue.From<IBreadthTaggedOwner>(Empty));
  Check((Alias[1] = nil) and (Alias[0] <> nil) and (TBreadthTaggedOwner.Destroyed = 1),
    'breadth-tvalue-dynamic-array-edit-updates-alias-and-releases-displaced-element');
  Alias := nil;
  Box := TValue.Empty;
  Recovered := First.AsInterface as IBreadthTaggedOwner;
  Check((Recovered <> nil) and (Recovered.Tag = 74000000051) and (TBreadthTaggedOwner.Destroyed = 1),
    'breadth-tvalue-dynamic-array-extracted-value-keeps-its-interface');
end;

procedure RunBreadthDynamicValue;
begin
  TBreadthTaggedOwner.Destroyed := 0;
  ExerciseBreadthDynamicValue;
  Check(TBreadthTaggedOwner.Destroyed = 2, 'breadth-tvalue-dynamic-array-releases-both-owners-once');
end;
