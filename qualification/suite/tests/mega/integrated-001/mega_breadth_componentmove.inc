{ Moving a component changes both owner's name table and its typed field. }

type
  TBreadthRouteChild = class(TComponent);

  TBreadthRouteHost = class(TComponent)
  public
    Removed: Integer;
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  published
    Route: TBreadthRouteChild;
    Renamed: TBreadthRouteChild;
  end;

procedure TBreadthRouteHost.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  If (Operation = opRemove) and (AComponent is TBreadthRouteChild) then
    Inc(Removed);
end;

procedure RunBreadthComponentMove;
var
  Source, Destination: TBreadthRouteHost;
  Member, Blocker: TBreadthRouteChild;
  Rejected: Boolean;
begin
  Source := TBreadthRouteHost.Create(nil);
  Destination := nil;
  Member := nil;
  try
    Destination := TBreadthRouteHost.Create(nil);
    Member := TBreadthRouteChild.Create(Source);
    Member.Name := 'Route';
    Blocker := TBreadthRouteChild.Create(Source);
    Blocker.Name := 'Reserved';
    Check((Source.Route = Member) and (Source.FindComponent('rOuTe') = Member),
      'breadth-component-owner-lookup-matches-published-field');
    Rejected := False;
    try
      Member.Name := 'Reserved';
    except
      on E: EComponentError do Rejected := True;
    end;
    Check(Rejected and (Member.Name = 'Route') and (Source.Route = Member)
      and (Source.FindComponent('Reserved') = Blocker), 'breadth-component-duplicate-name-keeps-existing-owner-links');

    Source.RemoveComponent(Member);
    Check((Source.Removed = 1) and (Source.Route = nil) and (Source.FindComponent('Route') = nil)
      and (Member.Owner = nil), 'breadth-component-explicit-removal-clears-old-owner-and-field');
    Destination.InsertComponent(Member);
    Check((Member.Owner = Destination) and (Destination.Route = Member) and (Source.Components[0] = Blocker),
      'breadth-component-insert-sets-the-new-owner-and-field');
    Member.Name := 'Renamed';
    Check((Destination.Route = nil) and (Destination.Renamed = Member) and (Destination.FindComponent('Route') = nil)
      and (Destination.FindComponent('reNamed') = Member), 'breadth-component-rename-moves-the-typed-reference');
    Mix(UInt64(Source.Removed * 100 + Destination.ComponentCount));
  finally
    FreeAndNil(Member);
    FreeAndNil(Destination);
    FreeAndNil(Source);
  end;
end;
