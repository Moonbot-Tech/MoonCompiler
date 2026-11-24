{ TypInfo passes an indexed dynamic-array property through its getter and managed setter. }

type
  TBreadthRttiInterfaces = array of IBreadthTaggedOwner;

  {$M+}
  TBreadthIndexedRttiArray = class
  private
    FItems: TBreadthRttiInterfaces;
    function GetItems(Index: Integer): TBreadthRttiInterfaces;
    procedure SetItems(Index: Integer; const Value: TBreadthRttiInterfaces);
  public
    ReadIndex, WriteIndex: Integer;
  published
    property Entries: TBreadthRttiInterfaces index -73 read GetItems write SetItems;
  end;
  {$M-}

function TBreadthIndexedRttiArray.GetItems(Index: Integer): TBreadthRttiInterfaces;
begin
  ReadIndex := Index;
  Result := FItems;
end;

procedure TBreadthIndexedRttiArray.SetItems(Index: Integer; const Value: TBreadthRttiInterfaces);
begin
  WriteIndex := Index;
  FItems := Value;
end;

procedure RunBreadthRttiDynamicProperty;
var
  Target: TBreadthIndexedRttiArray;
  Param: PPropInfo;
  Input: TBreadthRttiInterfaces;
begin
  TBreadthTaggedOwner.Destroyed := 0;
  Target := TBreadthIndexedRttiArray.Create;
  try
    Param := GetPropInfo(Target, 'Entries');
    Check(Param <> nil, 'breadth-rtti-indexed-dynarray-publishes-metadata');
    If Param = nil then
      Exit;
    SetLength(Target.FItems, 1);
    Target.FItems[0] := TBreadthTaggedOwner.Create;
    SetLength(Input, 2);
    Input[0] := TBreadthTaggedOwner.Create;
    Input[1] := TBreadthTaggedOwner.Create;
    SetDynArrayProp(Target, Param, Pointer(Input));
    Check((Target.WriteIndex = -73) and (Length(Target.FItems) = 2) and (TBreadthTaggedOwner.Destroyed = 1),
      'breadth-rtti-indexed-dynarray-setter-receives-index-and-replaces-old-owner');
    Check((GetDynArrayProp(Target, Param) = Pointer(Input)) and (Target.ReadIndex = -73),
      'breadth-rtti-indexed-dynarray-getter-receives-index-and-returns-live-storage');
    Input := nil;
    SetDynArrayProp(Target, Param, nil);
    Check((Length(Target.FItems) = 0) and (TBreadthTaggedOwner.Destroyed = 3),
      'breadth-rtti-indexed-dynarray-clearing-releases-every-element');
  finally
    Target.Free;
  end;
end;
