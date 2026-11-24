{ Inherited property syntax must still dispatch managed accessor arguments and results virtually. }

type
  TBreadthAbstractStore = class
  protected
    function ReadEntry: TCrossEntry; virtual; abstract;
    procedure WriteEntry(const Value: TCrossEntry); virtual; abstract;
  public
    property Entry: TCrossEntry read ReadEntry write WriteEntry;
  end;

  TBreadthConcreteStore = class(TBreadthAbstractStore)
  private
    FEntry: TCrossEntry;
  protected
    function ReadEntry: TCrossEntry; override;
    procedure WriteEntry(const Value: TCrossEntry); override;
  end;

  TBreadthDecoratedStore = class(TBreadthConcreteStore)
  protected
    function ReadEntry: TCrossEntry; override;
    procedure WriteEntry(const Value: TCrossEntry); override;
  public
    function ReplaceInherited(const Value: TCrossEntry): TCrossEntry;
  end;

function TBreadthConcreteStore.ReadEntry: TCrossEntry;
begin
  Result := FEntry;
end;

procedure TBreadthConcreteStore.WriteEntry(const Value: TCrossEntry);
begin
  FEntry := Value;
end;

function TBreadthDecoratedStore.ReadEntry: TCrossEntry;
begin
  Result := inherited ReadEntry;
  Result.Code := Result.Code * 3 + 5;
  Result.Text := '<' + Result.Text + '>';
end;

procedure TBreadthDecoratedStore.WriteEntry(const Value: TCrossEntry);
var
  Adjusted: TCrossEntry;
begin
  Adjusted.Code := Value.Code + 19;
  Adjusted.Text := Value.Text + '!';
  inherited WriteEntry(Adjusted);
end;

function TBreadthDecoratedStore.ReplaceInherited(const Value: TCrossEntry): TCrossEntry;
begin
  inherited Entry := Value;
  Result := inherited Entry;
end;

procedure RunBreadthInheritedProperty;
var
  Item: TBreadthDecoratedStore;
  Base: TBreadthAbstractStore;
  Input, First, Second: TCrossEntry;
begin
  Item := TBreadthDecoratedStore.Create;
  try
    Base := Item;
    Input.Code := OpaqueI(17000000031);
    Input.Text := AnsiString('raw');
    First := Item.ReplaceInherited(Input);
    Second := Base.Entry;
    Check((First.Code = 51000000155) and (First.Text = '<raw!>'),
      'breadth-inherited-managed-property-dispatches-both-accessors');
    Check((Second.Code = 51000000155) and (Second.Text = '<raw!>') and (Input.Text = 'raw'),
      'breadth-virtual-managed-property-agrees-with-base-view');
    Input.Code := OpaqueI(-41);
    Input.Text := 'again';
    Second := Item.ReplaceInherited(Input);
    Check((Second.Code = -61) and (Second.Text = '<again!>') and (First.Text = '<raw!>'),
      'breadth-inherited-managed-property-replacement-keeps-earlier-result');
    Mix(UInt64(Second.Code));
  finally
    Item.Free;
  end;
end;
