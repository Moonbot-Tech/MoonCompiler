{ Interface dispatch, delegate lifetime and narrow scalar ABI. }

type
  IBreadthLeftChannel = interface
    ['{A86395C4-E768-4C9A-9316-EF9877AB25C2}']
    function Emit(Key: Int64; Factor: Double): TCrossEntry;
  end;

  IBreadthRightChannel = interface
    ['{59268CC4-47F2-4AF3-9A7F-EE4FD65BCDC4}']
    function Emit(Key: Int64; Factor: Double): TCrossEntry;
  end;

  TBreadthChannelPair = class(TInterfacedObject, IBreadthLeftChannel, IBreadthRightChannel)
    Bias: Integer;
    function LeftEmit(Key: Int64; Factor: Double): TCrossEntry;
    function RightEmit(Key: Int64; Factor: Double): TCrossEntry;
    function IBreadthLeftChannel.Emit = LeftEmit;
    function IBreadthRightChannel.Emit = RightEmit;
  end;

function TBreadthChannelPair.LeftEmit(Key: Int64; Factor: Double): TCrossEntry;
begin
  Result.Code := Key + Bias * 3 + Trunc(Factor * 32.0);
  Result.Text := 'left';
end;

function TBreadthChannelPair.RightEmit(Key: Int64; Factor: Double): TCrossEntry;
begin
  Result.Code := -Key + Bias * 5 + Trunc(Factor * 8.0);
  Result.Text := 'right';
end;

procedure RunBreadthDualInterfaceMethods;
var
  Host: TBreadthChannelPair;
  L: IBreadthLeftChannel;
  R: IBreadthRightChannel;
  A, B: TCrossEntry;
begin
  Host := TBreadthChannelPair.Create;
  Host.Bias := Integer(OpaqueI(47));
  L := Host;
  R := L as IBreadthRightChannel;
  A := L.Emit(OpaqueI(90000000013), OpaqueD(0.625));
  B := R.Emit(OpaqueI(90000000013), OpaqueD(0.625));
  Check((A.Code = 90000000174) and (A.Text = AnsiString('left')), 'breadth-dual-interface-left-resolution');
  Check((B.Code = -89999999773) and (B.Text = AnsiString('right')), 'breadth-dual-interface-right-resolution');
  Check((L as IInterface) = (R as IInterface), 'breadth-dual-interface-shares-canonical-identity');
  Mix(UInt64(A.Code) xor UInt64(B.Code));
end;

type
  IBreadthDelegate = interface
    ['{874090F3-5D0D-4648-AED2-2D82CCF564F2}']
    function ReadTag: Int64;
  end;

  TBreadthDelegate = class(TInterfacedObject, IBreadthDelegate)
    Value: Int64;
    class var Destroyed: Integer;
    constructor Create(Tag: Int64);
    function ReadTag: Int64;
    destructor Destroy; override;
  end;

  TBreadthDelegatingHost = class(TInterfacedObject, IBreadthDelegate)
    Active: IBreadthDelegate;
    class var Destroyed: Integer;
    function GetActive: IBreadthDelegate;
    destructor Destroy; override;
    property Delegate: IBreadthDelegate read GetActive implements IBreadthDelegate;
  end;

constructor TBreadthDelegate.Create(Tag: Int64);
begin
  inherited Create;
  Value := Tag;
end;

function TBreadthDelegate.ReadTag: Int64;
begin
  Result := Value;
end;

destructor TBreadthDelegate.Destroy;
begin
  Inc(Destroyed);
  inherited;
end;

function TBreadthDelegatingHost.GetActive: IBreadthDelegate;
begin
  Result := Active;
end;

destructor TBreadthDelegatingHost.Destroy;
begin
  Inc(Destroyed);
  inherited;
end;

procedure BreadthHoldDelegates;
var
  Host: TBreadthDelegatingHost;
  Keep: IInterface;
  Older, Newer: IBreadthDelegate;
begin
  Host := TBreadthDelegatingHost.Create;
  Keep := Host;
  Host.Active := TBreadthDelegate.Create(OpaqueI(78000000051));
  Older := Host as IBreadthDelegate;
  Host.Active := TBreadthDelegate.Create(OpaqueI(-46000000011));
  Newer := Host as IBreadthDelegate;
  Check(Older.ReadTag = 78000000051, 'breadth-delegate-old-interface-retains-provider');
  Check(Newer.ReadTag = -46000000011, 'breadth-delegate-new-query-uses-current-provider');
  Host.Active := nil;
  Check(TBreadthDelegate.Destroyed = 0, 'breadth-delegate-provider-interfaces-keep-owners');
  Keep := nil;
  Check(TBreadthDelegatingHost.Destroyed = 1, 'breadth-delegate-host-destroyed-separately');
  Check((Older.ReadTag = 78000000051) and (Newer.ReadTag = -46000000011), 'breadth-delegate-providers-outlive-host');
  Mix(UInt64(Newer.ReadTag));
end;

procedure RunBreadthDelegateChanges;
begin
  TBreadthDelegate.Destroyed := 0;
  TBreadthDelegatingHost.Destroyed := 0;
  BreadthHoldDelegates;
  Check(TBreadthDelegate.Destroyed = 2, 'breadth-delegate-releases-both-providers');
end;

type
  TBreadthScalarResult = record
    Sum: Int64;
    Bits: UInt64;
  end;

  TBreadthScalarCallback = function(A: Byte; B: ShortInt; C: Word; D: SmallInt; E: Cardinal; F: Integer;
    G: Int64; H: UInt64; Flip: Boolean; Scale: Double): TBreadthScalarResult; cdecl;

function BreadthScalarCallback(A: Byte; B: ShortInt; C: Word; D: SmallInt; E: Cardinal; F: Integer;
  G: Int64; H: UInt64; Flip: Boolean; Scale: Double): TBreadthScalarResult; cdecl;
begin
  Result.Sum := Int64(A) + 3 * B - 5 * C + 7 * D + 11 * Int64(E) - 13 * Int64(F) + G - Trunc(Scale * 128.0);
  Result.Bits := H xor ((UInt64(A) shl 56) or (UInt64(Word(D)) shl 32) or UInt64(Cardinal(F)));
  If Flip then
    Result.Bits := Result.Bits xor UInt64($8000000000000000);
end;

procedure RunBreadthNarrowScalarABI;
var
  Read: TBreadthScalarCallback;
  Answer: TBreadthScalarResult;
begin
  Read := BreadthScalarCallback;
  Answer := Read(Byte(OpaqueI(255)), ShortInt(OpaqueI(-128)), Word(OpaqueI(65535)), SmallInt(OpaqueI(-32768)),
    Cardinal(OpaqueI(4294967295)), Integer(OpaqueI(-2147483641)), OpaqueI(90000000017),
    UInt64(OpaqueI(Int64(UInt64($B27C5164A08D3E79)))), True, OpaqueD(1.75));
  Check(Answer.Sum = 165161370191, 'breadth-scalar-abi-signed-and-unsigned-arguments');
  Check(Answer.Bits = UInt64($CD7CD164208D3E7E), 'breadth-scalar-abi-packed-return-lanes');
  Mix(Answer.Bits);
  Answer := Read(Byte(OpaqueI(17)), ShortInt(OpaqueI(127)), Word(OpaqueI(32769)), SmallInt(OpaqueI(32767)),
    Cardinal(OpaqueI(2147483648)), Integer(OpaqueI(2147483641)), OpaqueI(-75000000019),
    UInt64(OpaqueI($17CE9A43028FE6B0)), False, OpaqueD(-3.625));
  Check((Answer.Sum = -79294900838) and (Answer.Bits = UInt64($06CEE5BC7D701949)), 'breadth-scalar-abi-opposite-signs');
  Mix(Answer.Bits);
end;

function BreadthInterfaceForCast(Compatible: Boolean): IInterface;
begin
  If Compatible then
    Result := TBreadthTaggedOwner.Create
  else
    Result := TIntersectionOwner.Create;
end;

function BreadthAttemptInterfaceCast(var Destination: IBreadthTaggedOwner; Compatible: Boolean): Boolean;
begin
  Result := False;
  try
    Destination := BreadthInterfaceForCast(Compatible) as IBreadthTaggedOwner;
  except
    on EIntfCastError do Result := True;
    on EInvalidCast do Result := True;
  end;
end;

procedure RunBreadthInterfaceCastFailure;
var
  Destination: IBreadthTaggedOwner;
  InitialIdentity: Pointer;
begin
  TIntersectionOwner.Destroyed := 0;
  TBreadthTaggedOwner.Destroyed := 0;
  Destination := TBreadthTaggedOwner.Create;
  InitialIdentity := Pointer(Destination);
  Check(BreadthAttemptInterfaceCast(Destination, False), 'breadth-interface-as-failure-is-a-cast-exception');
  Check((Pointer(Destination) = InitialIdentity) and (TBreadthTaggedOwner.Destroyed = 0),
    'breadth-interface-as-failure-retains-assignment-destination');
  Check(TIntersectionOwner.Destroyed = 1, 'breadth-interface-as-failure-releases-source-temporary');
  Check(not BreadthAttemptInterfaceCast(Destination, True), 'breadth-interface-as-compatible-succeeds');
  Check((Destination <> nil) and (Pointer(Destination) <> InitialIdentity) and (Destination.Tag = 74000000051),
    'breadth-interface-as-publishes-successful-source');
  Check(TBreadthTaggedOwner.Destroyed = 1, 'breadth-interface-as-success-releases-old-destination');
  Destination := nil;
  Check(TBreadthTaggedOwner.Destroyed = 2, 'breadth-interface-as-source-owned-until-release');
  Mix(UInt64(TBreadthTaggedOwner.Destroyed));
end;

procedure RunBreadthInterfaceForms;
begin
  RunBreadthDualInterfaceMethods;
  RunBreadthDelegateChanges;
  RunBreadthNarrowScalarABI;
end;
