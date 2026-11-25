{ Two service views keep one controller alive, with different QueryInterface routing. }

type
  IBreadthServiceOwner = interface
    ['{436D79AA-431D-4BD9-88D8-436D056F9363}']
    function Ticket: Int64;
  end;

  IBreadthAttachedService = interface
    ['{C56813E9-A8B2-4837-8E85-3C97A6F2FA22}']
    function Adjust(Delta: Int64): Int64;
  end;

  TBreadthJoinedService = class(TAggregatedObject, IBreadthAttachedService)
    function Adjust(Delta: Int64): Int64;
  end;

  TBreadthSeparateService = class(TContainedObject, IBreadthAttachedService)
    function Adjust(Delta: Int64): Int64;
  end;

  TBreadthServiceController = class(TInterfacedObject, IBreadthServiceOwner)
    Joined: TBreadthJoinedService;
    Separate: TBreadthSeparateService;
    class var Destroyed: Integer;
    function Ticket: Int64;
    destructor Destroy; override;
  end;

function TBreadthJoinedService.Adjust(Delta: Int64): Int64;
begin
  Result := (Controller as IBreadthServiceOwner).Ticket + Delta;
end;

function TBreadthSeparateService.Adjust(Delta: Int64): Int64;
begin
  Result := (Controller as IBreadthServiceOwner).Ticket - Delta;
end;

function TBreadthServiceController.Ticket: Int64;
begin
  Result := OpaqueI(730000000021);
end;

destructor TBreadthServiceController.Destroy;
begin
  FreeAndNil(Joined);
  FreeAndNil(Separate);
  Inc(Destroyed);
  inherited Destroy;
end;

procedure BreadthExerciseServiceViews;
var
  Host: TBreadthServiceController;
  Owner, Found: IBreadthServiceOwner;
  Joined, Separate, SelfView: IBreadthAttachedService;
  Observed: Int64;
begin
  Host := TBreadthServiceController.Create;
  Owner := Host;
  Host.Joined := TBreadthJoinedService.Create(Owner);
  Host.Separate := TBreadthSeparateService.Create(Owner);
  Joined := Host.Joined;
  Separate := Host.Separate;
  Owner := nil;
  Check(TBreadthServiceController.Destroyed = 0, 'breadth-interface-controller-service-views-keep-owner-alive');
  Check(Supports(Joined, IBreadthServiceOwner, Found) and (Found.Ticket = 730000000021),
    'breadth-aggregated-service-routes-query-to-outer-controller');
  Found := nil;
  Check(not Supports(Separate, IBreadthServiceOwner, Found) and (Found = nil),
    'breadth-contained-service-does-not-expose-controller-interface');
  Check(Supports(Separate, IBreadthAttachedService, SelfView) and (SelfView = Separate),
    'breadth-contained-service-queries-its-own-interface');
  Observed := Separate.Adjust(OpaqueI(37));
  Check((Joined.Adjust(OpaqueI(-108)) = 729999999913) and (Observed = 729999999984),
    'breadth-interface-controller-both-service-views-use-live-owner-data');
  Mix(UInt64(Observed));
end;

procedure RunBreadthInterfaceController;
begin
  TBreadthServiceController.Destroyed := 0;
  BreadthExerciseServiceViews;
  Check(TBreadthServiceController.Destroyed = 1, 'breadth-interface-controller-releases-on-last-service-view');
end;
