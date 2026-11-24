{ A comparer can reject a colliding key before an insertion takes ownership. }

type
  TBreadthThrowingComparer = class(TInterfacedObject, IEqualityComparer<string>)
  public
    Armed: Boolean;
    Faults: Integer;
    function Equals({$ifdef BREADTH_LEGACY_COMPARER}constref{$else}const{$endif} Left, Right: string): Boolean;
      reintroduce;
    function GetHashCode({$ifdef BREADTH_LEGACY_COMPARER}constref{$else}const{$endif} Value: string): TBreadthHash;
      reintroduce;
  end;

function TBreadthThrowingComparer.Equals(
  {$ifdef BREADTH_LEGACY_COMPARER}constref{$else}const{$endif} Left, Right: string): Boolean;
begin
  If Armed and ((Left = 'new') or (Right = 'new')) then begin
    Inc(Faults);
    raise EAbort.Create('key comparison');
  end;
  Result := Left = Right;
end;

function TBreadthThrowingComparer.GetHashCode(
  {$ifdef BREADTH_LEGACY_COMPARER}constref{$else}const{$endif} Value: string): TBreadthHash;
begin
  Result := 5;
end;

procedure RunBreadthDictionaryRecovery;
var
  Dict: TDictionary<string, IBreadthTaggedOwner>;
  Comparer: IEqualityComparer<string>;
  Witness: TBreadthThrowingComparer;
  OldOwner, NewOwner, Found: IBreadthTaggedOwner;
  Original: Pointer;
  Rejected: Boolean;
begin
  TBreadthTaggedOwner.Destroyed := 0;
  Witness := TBreadthThrowingComparer.Create;
  Comparer := Witness;
  Dict := TDictionary<string, IBreadthTaggedOwner>.Create(Comparer);
  try
    OldOwner := TBreadthTaggedOwner.Create;
    Original := Pointer(OldOwner);
    Dict.Add('old', OldOwner);
    OldOwner := nil;
    NewOwner := TBreadthTaggedOwner.Create;
    Witness.Armed := True;
    Rejected := False;
    try
      Dict.AddOrSetValue('new', NewOwner);
    except
      on E: EAbort do Rejected := E.Message = 'key comparison';
    end;
    Witness.Armed := False;
    Check(Rejected and (Witness.Faults = 1) and (Dict.Count = 1),
      'breadth-dictionary-collision-exception-prevents-insertion');
    Check(not Dict.ContainsKey('new') and Dict.TryGetValue('old', Found) and (Pointer(Found) = Original),
      'breadth-dictionary-comparer-failure-keeps-existing-owner');
    Found := nil;
    NewOwner := nil;
    Check(TBreadthTaggedOwner.Destroyed = 1, 'breadth-dictionary-failed-write-does-not-retain-new-owner');
    NewOwner := TBreadthTaggedOwner.Create;
    Dict.AddOrSetValue('new', NewOwner);
    Check((Dict.Count = 2) and Dict.TryGetValue('new', Found) and (Found = NewOwner),
      'breadth-dictionary-retry-after-comparer-exception-uses-new-owner');
    Found := nil;
    NewOwner := nil;
  finally
    Dict.Free;
  end;
  Check(TBreadthTaggedOwner.Destroyed = 3, 'breadth-dictionary-recovered-container-releases-both-owners');
  Mix(UInt64(TBreadthTaggedOwner.Destroyed));
end;
