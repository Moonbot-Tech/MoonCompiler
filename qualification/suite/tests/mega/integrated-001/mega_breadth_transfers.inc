{ Values crossing early returns, observer callbacks and representation changes. }

type
  TBreadthExitPacket = record
    Value: Int64;
    Owner: IInterface;
    Trail: AnsiString;
  end;

function BreadthExitPacket(Choice: Integer; var Cleanup: Integer): TBreadthExitPacket;
var
  Pending: TBreadthExitPacket;
begin
  Pending.Owner := TIntersectionOwner.Create;
  Pending.Value := OpaqueI(47000000031);
  Pending.Trail := 'begin';
  try
    case Choice of
      0: Exit(Pending);
      1: begin
        Pending.Value := -Pending.Value;
        Pending.Trail := Pending.Trail + '-alternate';
        Exit(Pending);
      end;
    end;
    raise EAbort.Create('packet not returned');
  finally
    Inc(Cleanup);
    Pending.Trail := 'local changed';
  end;
end;

procedure RunBreadthExitPacket;
var
  P, Staged: TBreadthExitPacket;
  Cleanup: Integer;
  Caught: Boolean;
begin
  TIntersectionOwner.Destroyed := 0;
  Cleanup := 0;
  P := BreadthExitPacket(Integer(OpaqueI(0)), Cleanup);
  Check((P.Value = 47000000031) and (P.Trail = AnsiString('begin')), 'breadth-exit-record-snapshot-before-finally');
  P := BreadthExitPacket(Integer(OpaqueI(1)), Cleanup);
  Check((P.Value = -47000000031) and (P.Trail = AnsiString('begin-alternate')), 'breadth-exit-record-alternate-snapshot');
  Check((P.Owner <> nil) and (TIntersectionOwner.Destroyed = 1), 'breadth-exit-record-replaces-old-owner');
  Caught := False;
  try
    Staged := BreadthExitPacket(Integer(OpaqueI(2)), Cleanup);
    P := Staged;
  except
    on EAbort do Caught := True;
  end;
  Check(Caught and (Cleanup = 3), 'breadth-exit-record-finally-on-all-paths');
  Check((P.Value = -47000000031) and (TIntersectionOwner.Destroyed = 2), 'breadth-exit-record-releases-failed-producer');
  P.Owner := nil;
  Check(TIntersectionOwner.Destroyed = 3, 'breadth-exit-record-final-owner-released');
  Mix(UInt64(P.Value));
end;

type
  TBreadthNotifyingPeer = class(TComponent)
  public
    Peer: TComponent;
    Removals: Integer;
    procedure Watch(Component: TComponent);
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  end;

procedure TBreadthNotifyingPeer.Watch(Component: TComponent);
begin
  If Peer <> nil then
    Peer.RemoveFreeNotification(Self);
  Peer := Component;
  If Peer <> nil then
    Peer.FreeNotification(Self);
end;

procedure TBreadthNotifyingPeer.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  If Operation = opRemove then begin
    Inc(Removals);
    If AComponent = Peer then
      Peer := nil;
  end;
end;

procedure RunBreadthNotificationTransfer;
var
  Observer: TBreadthNotifyingPeer;
  Former, Current, Container: TComponent;
begin
  Observer := TBreadthNotifyingPeer.Create(nil);
  try
    Container := TComponent.Create(nil);
    try
      Former := TComponent.Create(Container);
      Current := TComponent.Create(Container);
      Observer.Watch(Former);
      Observer.Watch(Current);
      Former.Free;
      Check((Observer.Peer = Current) and (Observer.Removals = 0), 'breadth-notification-old-registration-removed');
      Check((Container.ComponentCount = 1) and (Container.Components[0] = Current), 'breadth-notification-owner-list-updated');
    finally
      Container.Free;
    end;
    Check((Observer.Peer = nil) and (Observer.Removals = 1), 'breadth-notification-owner-destruction-clears-current');
    Mix(UInt64(Observer.Removals));
  finally
    Observer.Free;
  end;
end;

procedure BreadthVariantCoerce(var Value: Variant; Offset: Int64);
begin
  If VarIsNull(Value) then
    Value := Offset
  else If VarIsEmpty(Value) then
    Value := -Offset
  else
    Value := Int64(Value) + Offset;
end;

procedure RunBreadthVariantStates;
var
  Missing, Unknown, Alive, Snapshot: Variant;
  Delta: Int64;
begin
  Missing := Unassigned;
  Unknown := Null;
  Alive := OpaqueI(55000000009);
  Snapshot := Unknown;
  Delta := OpaqueI(31000000017);
  BreadthVariantCoerce(Unknown, Delta);
  BreadthVariantCoerce(Missing, Delta);
  BreadthVariantCoerce(Alive, Delta);
  Check(VarIsNull(Snapshot), 'breadth-variant-null-snapshot-survives-var-write');
  Check((VarType(Unknown) = varInt64) and (Int64(Unknown) = 31000000017), 'breadth-variant-null-supplied-int64');
  Check((VarType(Missing) = varInt64) and (Int64(Missing) = -31000000017), 'breadth-variant-empty-supplied-int64');
  Check(Int64(Alive) = 86000000026, 'breadth-variant-int64-already-present');
  VarClear(Alive);
  Check(VarIsEmpty(Alive), 'breadth-variant-explicit-clear-resets-tag');
  Mix(UInt64(Int64(Unknown)) xor UInt64(Int64(Missing)));
end;

procedure RunBreadthTransferForms;
begin
  RunBreadthExitPacket;
  RunBreadthNotificationTransfer;
  RunBreadthVariantStates;
end;
