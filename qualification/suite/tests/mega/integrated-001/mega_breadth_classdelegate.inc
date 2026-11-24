{ A class-valued implements property forwards a managed return through its interface entry. }

type
  IBreadthServiceView = interface
    ['{04AC5287-AB75-4331-B043-95E0F3F0DB0C}']
    function ReadService(Code: Int64): TCrossEntry;
  end;

  TBreadthServiceNode = class(TInterfacedObject, IBreadthServiceView)
    Base: Int64;
    class var Released: Integer;
    function ReadService(Code: Int64): TCrossEntry; virtual;
    destructor Destroy; override;
  end;

  TBreadthServiceOverride = class(TBreadthServiceNode)
    function ReadService(Code: Int64): TCrossEntry; override;
  end;

  TBreadthServiceHost = class(TInterfacedObject, IBreadthServiceView)
  private
    FNode: TBreadthServiceNode;
    FKeepNode: IInterface;
    function GetNode: TBreadthServiceNode;
  public
    class var Released: Integer;
    constructor Create;
    destructor Destroy; override;
    property Node: TBreadthServiceNode read GetNode implements IBreadthServiceView;
  end;

function TBreadthServiceNode.ReadService(Code: Int64): TCrossEntry;
begin
  Result.Code := Base + Code;
  Result.Text := 'service';
end;

function TBreadthServiceOverride.ReadService(Code: Int64): TCrossEntry;
begin
  Result := inherited ReadService(Code);
  Result.Code := Result.Code * 3 - 5;
  Result.Text := Result.Text + '-virtual';
end;

destructor TBreadthServiceNode.Destroy;
begin
  Inc(Released);
  inherited;
end;

constructor TBreadthServiceHost.Create;
begin
  inherited Create;
  FNode := TBreadthServiceOverride.Create;
  FKeepNode := FNode;
  FNode.Base := OpaqueI(83000000051);
end;

destructor TBreadthServiceHost.Destroy;
begin
  Inc(Released);
  inherited;
end;

function TBreadthServiceHost.GetNode: TBreadthServiceNode;
begin
  Result := FNode;
end;

procedure BreadthExerciseClassDelegate;
var
  Host: IInterface;
  Service: IBreadthServiceView;
  First, Second: TCrossEntry;
begin
  Host := TBreadthServiceHost.Create;
  Check(Supports(Host, IBreadthServiceView, Service), 'breadth-class-delegate-query-resolves-class-property');
  If Service = nil then
    Exit;
  First := Service.ReadService(OpaqueI(-43000000017));
  Check((First.Code = 120000000097) and (First.Text = 'service-virtual'), 'breadth-class-delegate-dispatches-derived-implementation');
  Host := nil;
  Second := Service.ReadService(OpaqueI(71));
  Check((Second.Code = 249000000361) and (Second.Text = 'service-virtual') and (First.Code = 120000000097),
    'breadth-class-delegate-service-remains-live-after-host-lease-release');
  Check(TBreadthServiceNode.Released = 0, 'breadth-class-delegate-retains-target-during-dispatch');
  Mix(UInt64(Second.Code));
end;

procedure RunBreadthClassDelegate;
begin
  TBreadthServiceHost.Released := 0;
  TBreadthServiceNode.Released := 0;
  BreadthExerciseClassDelegate;
  Check((TBreadthServiceHost.Released = 1) and (TBreadthServiceNode.Released = 1),
    'breadth-class-delegate-releases-host-and-target-once');
end;
