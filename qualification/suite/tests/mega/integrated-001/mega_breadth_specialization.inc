{ Specialization-local class storage with nested managed value types. }

type
  TBreadthHeldValue = record
    Owners: array[0..1] of IInterface;
    Text: AnsiString;
  end;
  TBreadthHeldTwin = record
    Owners: array[0..1] of IInterface;
    Text: AnsiString;
  end;

  TBreadthSpecializedSlot<T> = class
  private
    class var Value: T;
  public
    class procedure Store(const Source: T); static;
    class function Snapshot: T; static;
    class procedure Reset; static;
  end;

class procedure TBreadthSpecializedSlot<T>.Store(const Source: T);
begin
  Value := Source;
end;

class function TBreadthSpecializedSlot<T>.Snapshot: T;
begin
  Result := Value;
end;

class procedure TBreadthSpecializedSlot<T>.Reset;
begin
  Value := Default(T);
end;

type
  TBreadthValueSlot = TBreadthSpecializedSlot<TBreadthHeldValue>;
  TBreadthTwinSlot = TBreadthSpecializedSlot<TBreadthHeldTwin>;

procedure BreadthCheckOtherSlot;
var
  Twin: TBreadthHeldTwin;
begin
  Twin := TBreadthTwinSlot.Snapshot;
  Check((Twin.Text = 'right-238') and (Twin.Owners[0] = nil) and (Twin.Owners[1] <> nil),
    'breadth-specialized-other-slot-survives-reset');
end;

procedure RunBreadthSpecializedStorage;
var
  Value, Saved: TBreadthHeldValue;
  Twin: TBreadthHeldTwin;
begin
  TIntersectionOwner.Destroyed := 0;
  try
    Value.Owners[0] := TIntersectionOwner.Create;
    Value.Owners[1] := TIntersectionOwner.Create;
    Value.Text := AnsiString('left-' + IntToStr(OpaqueI(63)));
    TBreadthValueSlot.Store(Value);
    Value := Default(TBreadthHeldValue);
    Twin := TBreadthTwinSlot.Snapshot;
    Check((Twin.Owners[0] = nil) and (Twin.Owners[1] = nil) and (Twin.Text = ''),
      'breadth-specialized-storage-distinct-even-at-identical-layout');

    Twin.Owners[1] := TIntersectionOwner.Create;
    Twin.Text := AnsiString('right-' + IntToStr(OpaqueI(238)));
    TBreadthTwinSlot.Store(Twin);
    Twin := Default(TBreadthHeldTwin);
    Saved := TBreadthValueSlot.Snapshot;
    Check((Saved.Text = 'left-63') and (Saved.Owners[0] <> nil) and (Saved.Owners[1] <> nil),
      'breadth-specialized-snapshot-survives-other-specialization-store');

    TBreadthValueSlot.Reset;
    Check(TIntersectionOwner.Destroyed = 0, 'breadth-specialized-reset-keeps-copied-owners');
    Value := TBreadthValueSlot.Snapshot;
    Check((Value.Owners[0] = nil) and (Value.Owners[1] = nil) and (Value.Text = ''),
      'breadth-specialized-reset-uses-managed-default');
    Saved := Default(TBreadthHeldValue);
    Check(TIntersectionOwner.Destroyed = 2, 'breadth-specialized-discard-releases-both-nested-owners');

    BreadthCheckOtherSlot;
    TBreadthTwinSlot.Reset;
    Check(TIntersectionOwner.Destroyed = 3, 'breadth-specialized-reset-releases-other-owner');
    Mix(UInt64(TIntersectionOwner.Destroyed));
  finally
    TBreadthValueSlot.Reset;
    TBreadthTwinSlot.Reset;
  end;
end;
