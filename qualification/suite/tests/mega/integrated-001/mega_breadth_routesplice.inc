{ Insert a plan into itself, restore the original order and release each retained route exactly once. }

type
  IBreadthSpliceRoute = interface
    ['{D7077E22-6D28-478D-A4B6-3F663A83A780}']
    function ID: Int64;
  end;

  TBreadthSpliceRoute = class(TInterfacedObject, IBreadthSpliceRoute)
  private
    FSlot: Integer;
  public
    class var Released, ReleasedMask: Integer;
    constructor Create(Slot: Integer);
    destructor Destroy; override;
    function ID: Int64;
  end;

const
  BreadthSpliceIDs: array[0..2] of Int64 = (9007199254740993, -870000000079, 700000000001);

constructor TBreadthSpliceRoute.Create(Slot: Integer);
begin
  inherited Create;
  FSlot := Slot;
end;

destructor TBreadthSpliceRoute.Destroy;
begin
  Inc(Released);
  ReleasedMask := ReleasedMask or (1 shl FSlot);
  inherited Destroy;
end;

function TBreadthSpliceRoute.ID: Int64;
begin
  Result := BreadthSpliceIDs[FSlot];
end;

procedure BreadthSpliceRoutePlan(KeepOriginal: Boolean);
var
  Plan, Original: TArray<IBreadthSpliceRoute>;
  I, At: Integer;
begin
  TBreadthSpliceRoute.Released := 0;
  TBreadthSpliceRoute.ReleasedMask := 0;
  SetLength(Plan, Length(BreadthSpliceIDs));
  for I := 0 to High(Plan) do
    Plan[I] := TBreadthSpliceRoute.Create(I);
  If KeepOriginal then
    Original := Plan;
  At := Integer(OpaqueI(1));
  Insert(Plan, Plan, At);
  Check((Length(Plan) = 6) and (Plan[0].ID = 9007199254740993) and (Plan[1] = Plan[0])
    and (Plan[2].ID = -870000000079) and (Plan[3].ID = 700000000001) and (Plan[4] = Plan[2]) and (Plan[5] = Plan[3]),
    'breadth-route-splice-duplicates-exact-aliased-plan-and-retains-interface-identities');
  Delete(Plan, At, Length(BreadthSpliceIDs));
  Check((Length(Plan) = 3) and (Plan[0].ID = 9007199254740993) and (Plan[1].ID = -870000000079)
    and (Plan[2].ID = 700000000001), 'breadth-route-splice-removes-inserted-segment-and-restores-order');
  Check((TBreadthSpliceRoute.Released = 0) and (not KeepOriginal or ((Length(Original) = 3)
    and (Original[0] = Plan[0]) and (Original[1] = Plan[1]) and (Original[2] = Plan[2]))),
    'breadth-route-splice-preserves-other-array-view-and-remaining-references');
  Plan := nil;
  Original := nil;
  Check((TBreadthSpliceRoute.Released = 3) and (TBreadthSpliceRoute.ReleasedMask = 7),
    'breadth-route-splice-releases-each-route-on-last-array-release');
  Mix(UInt64(TBreadthSpliceRoute.ReleasedMask * 10 + Ord(KeepOriginal)));
end;

procedure RunBreadthRouteSplice;
begin
  BreadthSpliceRoutePlan(False);
  BreadthSpliceRoutePlan(True);
end;
