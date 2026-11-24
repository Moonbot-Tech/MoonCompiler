{ Int64 RTTI setters and Variant property APIs dispatch the same inherited accessor. }

type
  TBreadthWideProperty = class(TPersistent)
  protected
    FRevision: Int64;
    FEdits: Integer;
    function ReadRevision: Int64; virtual;
    procedure WriteRevision(Value: Int64); virtual;
  public
    property Edits: Integer read FEdits;
  published
    property Revision: Int64 read ReadRevision write WriteRevision;
  end;

  TBreadthWideDerived = class(TBreadthWideProperty)
  protected
    function ReadRevision: Int64; override;
    procedure WriteRevision(Value: Int64); override;
  end;

function TBreadthWideProperty.ReadRevision: Int64;
begin
  Result := FRevision;
end;

procedure TBreadthWideProperty.WriteRevision(Value: Int64);
begin
  Inc(FEdits);
  FRevision := Value;
end;

function TBreadthWideDerived.ReadRevision: Int64;
begin
  Result := inherited ReadRevision - 19;
end;

procedure TBreadthWideDerived.WriteRevision(Value: Int64);
begin
  inherited WriteRevision(Value * 3 + 491);
end;

procedure RunBreadthWideReflection;
var
  Target: TBreadthWideProperty;
  Info: PPropInfo;
  Written, Observed: Variant;
begin
  Target := TBreadthWideDerived.Create;
  try
    Info := GetPropInfo(Target, 'Revision');
    Check(Info <> nil, 'breadth-int64-rtti-published-property-is-present');
    If Info = nil then
      Exit;
    SetInt64Prop(Target, Info, OpaqueI(-60000000013));
    Check((Target.Edits = 1) and (Target.Revision = -179999999567) and (GetInt64Prop(Target, Info) = -179999999567),
      'breadth-int64-rtti-preserves-negative-width-and-virtual-dispatch');
    Written := OpaqueI(70000000041);
    SetPropValue(Target, 'Revision', Written);
    Observed := GetPropValue(Target, 'Revision');
    Check((Target.Edits = 2) and (Target.Revision = 210000000595), 'breadth-int64-rtti-variant-write-uses-same-override');
    Check((VarType(Observed) = varInt64) and (Int64(Observed) = 210000000595),
      'breadth-int64-rtti-variant-read-preserves-carrier-and-value');
    Mix(UInt64(Int64(Observed)));
  finally
    Target.Free;
  end;
end;
