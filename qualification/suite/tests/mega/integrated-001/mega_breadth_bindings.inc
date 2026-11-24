{ Address binding, interface destination lifetime and a split-register value. }

type
  PBreadthBoundEntry = ^TCrossEntry;

procedure BreadthRetarget(var Entry: PBreadthBoundEntry; Target: PBreadthBoundEntry);
begin
  Entry := Target;
end;

procedure RunBreadthWithBinding;
var
  First, Second: TCrossEntry;
  Current: PBreadthBoundEntry;
  Fetches: Integer;

  function Fetch: PBreadthBoundEntry;
  begin
    Inc(Fetches);
    Result := Current;
  end;

begin
  First.Code := OpaqueI(313);
  First.Text := 'first';
  Second.Code := OpaqueI(709);
  Second.Text := 'second';
  Current := @First;
  Fetches := 0;
  with Fetch^ do begin
    Code := Code + 13;
    BreadthRetarget(Current, @Second);
    Text := Text + '!';
    Code := Code + 29;
  end;
  Check((First.Code = 355) and (First.Text = AnsiString('first!')), 'breadth-with-binds-original-designator');
  Check((Second.Code = 709) and (Second.Text = AnsiString('second')), 'breadth-with-retarget-does-not-write-new-receiver');
  Check((Fetches = 1) and (Current = @Second), 'breadth-with-evaluates-designator-once');
  Mix(UInt64(First.Code));
end;

type
  IBreadthTaggedOwner = interface
    ['{FC053663-FDD5-4FE9-B0B9-922923AF24B1}']
    function Tag: Int64;
  end;

  TBreadthTaggedOwner = class(TInterfacedObject, IBreadthTaggedOwner)
    class var Destroyed: Integer;
    function Tag: Int64;
    destructor Destroy; override;
  end;

function TBreadthTaggedOwner.Tag: Int64;
begin
  Result := 74000000051;
end;

destructor TBreadthTaggedOwner.Destroy;
begin
  Inc(Destroyed);
  inherited;
end;

procedure BreadthSupportsDestination;
var
  Source: IInterface;
  Destination: IBreadthTaggedOwner;
begin
  Destination := TBreadthTaggedOwner.Create;
  Source := TIntersectionOwner.Create;
  Check(not Supports(Source, IBreadthTaggedOwner, Destination), 'breadth-supports-missing-interface');
  Check((Destination = nil) and (TBreadthTaggedOwner.Destroyed = 1), 'breadth-supports-failed-out-releases-old');
  Source := TBreadthTaggedOwner.Create;
  Destination := TBreadthTaggedOwner.Create;
  Check(Supports(Source, IBreadthTaggedOwner, Destination), 'breadth-supports-present-interface');
  Check((Destination <> nil) and (TBreadthTaggedOwner.Destroyed = 2), 'breadth-supports-successful-out-replaces-old');
  Source := nil;
  Check((Destination <> nil) and (Destination.Tag = 74000000051), 'breadth-supports-new-interface-remains-owned');
end;

procedure RunBreadthSupportsDestination;
begin
  TBreadthTaggedOwner.Destroyed := 0;
  BreadthSupportsDestination;
  Check(TBreadthTaggedOwner.Destroyed = 3, 'breadth-supports-final-owner-destroyed');
  Mix(UInt64(TBreadthTaggedOwner.Destroyed));
end;

type
  TBreadthGuidEdit = function(Left, Right: TGUID; Salt: Cardinal): TGUID; cdecl;

function BreadthGuidEdit(Left, Right: TGUID; Salt: Cardinal): TGUID; cdecl;
var
  I: Integer;
begin
  Result.D1 := Left.D1 xor Salt xor Right.D1;
  Result.D2 := Right.D2;
  Result.D3 := Left.D3;
  for I := Low(Result.D4) to High(Result.D4) do
    Result.D4[I] := Left.D4[I] xor Right.D4[High(Result.D4) - I];
end;

procedure RunBreadthGuidABI;
const
  Expected: TGUID = (D1: $91000008; D2: $2653; D3: $5678; D4: ($90, $60, $10, $50, $58, $64, $72, $81));
var
  L, R, Actual: TGUID;
  Edit: TBreadthGuidEdit;
begin
  L := StringToGUID('{12000001-3142-5678-1020-304050607080}');
  R := StringToGUID('{03000006-2653-89AB-0102-040810204080}');
  Edit := BreadthGuidEdit;
  Actual := Edit(L, R, Cardinal(OpaqueI($8000000F)));
  Check(CompareMem(@Actual, @Expected, SizeOf(Actual)), 'breadth-guid-cdecl-two-aggregates-and-salt');
  Check(GUIDToString(Actual) = '{91000008-2653-5678-9060-105058647281}', 'breadth-guid-rendered-byte-order');
  Check((L.D1 = $12000001) and (L.D4[7] = $80) and (R.D3 = $89AB), 'breadth-guid-by-value-sources-unchanged');
  Mix(UInt64(Actual.D1));
end;

procedure RunBreadthBindingForms;
begin
  RunBreadthWithBinding;
  RunBreadthSupportsDestination;
  RunBreadthGuidABI;
end;
