{ Streaming resolves component-valued properties after forward targets are constructed. }

type
  TBreadthLinkNode = class(TComponent)
  private
    FPartner: TBreadthLinkNode;
    FEdits: Integer;
    procedure SetPartner(Value: TBreadthLinkNode);
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    property Edits: Integer read FEdits;
  published
    property Partner: TBreadthLinkNode read FPartner write SetPartner;
  end;

procedure TBreadthLinkNode.SetPartner(Value: TBreadthLinkNode);
begin
  FPartner := Value;
  Inc(FEdits);
end;

procedure TBreadthLinkNode.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  If (Operation = opRemove) and (AComponent = FPartner) then
    FPartner := nil;
end;

procedure BreadthLoadLinks(Host: TComponent);
const
  Fixture: AnsiString =
    'object BreadthLinkHost: TComponent'#10 +
    '  object LeftNode: TBreadthLinkNode'#10 +
    '    Partner = RightNode'#10 +
    '  end'#10 +
    '  object RightNode: TBreadthLinkNode'#10 +
    '    Partner = LeftNode'#10 +
    '  end'#10 +
    'end'#10;
var
  Binary: TMemoryStream;
begin
  Binary := TMemoryStream.Create;
  try
    Check(BreadthReadTextComponent(Fixture, Host, Binary) = Host, 'breadth-component-fixup-uses-existing-root');
  finally
    Binary.Free;
  end;
end;

procedure RunBreadthComponentFixup;
var
  Host: TComponent;
  Left, Right: TBreadthLinkNode;
begin
  RegisterClass(TBreadthLinkNode);
  try
    Host := TComponent.Create(nil);
    try
      BreadthLoadLinks(Host);
      Left := Host.FindComponent('LeftNode') as TBreadthLinkNode;
      Right := Host.FindComponent('RightNode') as TBreadthLinkNode;
      Check((Host.ComponentCount = 2) and (Left <> nil) and (Right <> nil), 'breadth-component-fixup-creates-both-named-children');
      If (Left = nil) or (Right = nil) then
        Exit;
      Check((Left.Partner = Right) and (Right.Partner = Left) and (Left.Edits = 1) and (Right.Edits = 1),
        'breadth-component-fixup-resolves-forward-and-backward-links');
      Right.Free;
      Check((Host.ComponentCount = 1) and (Left.Partner = nil), 'breadth-component-fixup-owner-notifies-linked-sibling-on-removal');
      Mix(UInt64(Left.Edits * 10 + Host.ComponentCount));
    finally
      Host.Free;
    end;
  finally
    UnRegisterClass(TBreadthLinkNode);
  end;
end;
