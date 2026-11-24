{ A read-only published subcomponent streams into the child created by its owner. }

type
  TBreadthReadonlySub = class(TComponent)
  private
    FCode: Int64;
    FLabelText: UnicodeString;
  published
    property Code: Int64 read FCode write FCode;
    property LabelText: UnicodeString read FLabelText write FLabelText;
  end;

  TBreadthSubcomponentRoot = class(TComponent)
  private
    FLeaf: TBreadthReadonlySub;
  public
    constructor Create(AnOwner: TComponent); override;
  published
    property Leaf: TBreadthReadonlySub read FLeaf;
  end;

constructor TBreadthSubcomponentRoot.Create(AnOwner: TComponent);
begin
  inherited;
  FLeaf := TBreadthReadonlySub.Create(Self);
  FLeaf.SetSubComponent(True);
end;

procedure RunBreadthReadonlySubcomponent;
var
  Data: TMemoryStream;
  Root: TBreadthSubcomponentRoot;
  Existing: TBreadthReadonlySub;
begin
  Data := TMemoryStream.Create;
  try
    Root := TBreadthSubcomponentRoot.Create(nil);
    try
      Root.Name := 'SubcomponentRoot';
      Root.Leaf.Code := OpaqueI(-71000000017);
      Root.Leaf.LabelText := 'left'#0'right';
      Data.WriteComponent(Root);
    finally
      Root.Free;
    end;

    Root := TBreadthSubcomponentRoot.Create(nil);
    try
      Existing := Root.Leaf;
      Existing.LabelText := 'before';
      Data.Position := 0;
      Check(Data.ReadComponent(Root) = Root, 'breadth-readonly-subcomponent-stream-loads-into-existing-root');
      Check((Root.Leaf = Existing) and (Root.ComponentCount = 1) and (Existing.Owner = Root),
        'breadth-readonly-subcomponent-stream-keeps-initial-child-and-owner');
      Check((Existing.Code = -71000000017) and (Existing.LabelText = 'left'#0'right'),
        'breadth-readonly-subcomponent-stream-assigns-nested-wide-fields');
    finally
      Root.Free;
    end;
  finally
    Data.Free;
  end;
end;
