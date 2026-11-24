{ A published owned collection streams records in index order, with counted Unicode and Int64 fields. }

type
  TBreadthStreamItem = class(TCollectionItem)
  private
    FText: UnicodeString;
    FWeight: Int64;
  public
    procedure Assign(Source: TPersistent); override;
  published
    property Text: UnicodeString read FText write FText;
    property Weight: Int64 read FWeight write FWeight;
  end;

  TBreadthCollectionRoot = class(TComponent)
  private
    FEntries: TOwnedCollection;
    procedure SetEntries(Value: TOwnedCollection);
  public
    constructor Create(AnOwner: TComponent); override;
    destructor Destroy; override;
  published
    property Entries: TOwnedCollection read FEntries write SetEntries;
  end;

procedure TBreadthStreamItem.Assign(Source: TPersistent);
begin
  If Source is TBreadthStreamItem then begin
    FText := TBreadthStreamItem(Source).FText;
    FWeight := TBreadthStreamItem(Source).FWeight;
  end else
    inherited;
end;

procedure TBreadthCollectionRoot.SetEntries(Value: TOwnedCollection);
begin
  FEntries.Assign(Value);
end;

constructor TBreadthCollectionRoot.Create(AnOwner: TComponent);
begin
  inherited;
  FEntries := TOwnedCollection.Create(Self, TBreadthStreamItem);
end;

destructor TBreadthCollectionRoot.Destroy;
begin
  FEntries.Free;
  inherited;
end;

procedure RunBreadthCollectionStream;
var
  Original, Loaded: TBreadthCollectionRoot;
  First, Second: TBreadthStreamItem;
  FirstId: Integer;
  Existing: TOwnedCollection;
  Data: TMemoryStream;
begin
  Data := TMemoryStream.Create;
  try
    Original := TBreadthCollectionRoot.Create(nil);
    try
      Original.Name := 'CollectionRoot';
      First := TBreadthStreamItem(Original.Entries.Add);
      Second := TBreadthStreamItem(Original.Entries.Add);
      FirstId := First.ID;
      First.Text := 'first';
      First.Weight := -45000000013;
      Second.Text := 'second'#0#$20AC;
      Second.Weight := 86000000017;
      Second.Index := 0;
      Check((Original.Entries.Items[0] = Second) and (First.Index = 1)
        and (Original.Entries.FindItemID(FirstId) = First), 'breadth-collection-move-preserves-item-id');
      Data.WriteComponent(Original);
    finally
      Original.Free;
    end;

    Loaded := TBreadthCollectionRoot.Create(nil);
    try
      Existing := Loaded.Entries;
      TBreadthStreamItem(Existing.Add).Text := 'replace';
      Data.Position := 0;
      Data.ReadComponent(Loaded);
      Check((Loaded.Name = 'CollectionRoot') and (Loaded.Entries = Existing) and (Existing.Count = 2),
        'breadth-collection-stream-fixture-loads-into-existing-owned-collection');
      If Loaded.Entries.Count <> 2 then
        Exit;
      First := Loaded.Entries.Items[0] as TBreadthStreamItem;
      Second := Loaded.Entries.Items[1] as TBreadthStreamItem;
      Check((First.Text = 'second'#0#$20AC) and (First.Weight = 86000000017) and (First.Collection = Loaded.Entries),
        'breadth-collection-stream-preserves-first-item-order-and-wide-fields');
      Check((Second.Text = 'first') and (Second.Weight = -45000000013) and (Second.Collection = Loaded.Entries),
        'breadth-collection-stream-preserves-second-item-order-and-negative-int64');
    finally
      Loaded.Free;
    end;
  finally
    Data.Free;
  end;
end;
