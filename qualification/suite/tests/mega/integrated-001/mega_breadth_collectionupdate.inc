{ A collection observer sees the finished order once, then sees the individual edit after the batch. }

type
  TBreadthSelectionItem = class(TCollectionItem)
  public
    Ticket: Int64;
    procedure SetTicket(Value: Int64);
  end;

  TBreadthSelection = class(TCollection)
  public
    Updates: Integer;
    UpdatedItem: TCollectionItem;
    FirstTicket: Int64;
  protected
    procedure Update(Item: TCollectionItem); override;
  end;

procedure TBreadthSelectionItem.SetTicket(Value: Int64);
begin
  Ticket := Value;
  Changed(False);
end;

procedure TBreadthSelection.Update(Item: TCollectionItem);
begin
  Inc(Updates);
  UpdatedItem := Item;
  If Count = 0 then
    FirstTicket := 0
  else
    FirstTicket := TBreadthSelectionItem(Items[0]).Ticket;
end;

procedure RunBreadthCollectionUpdate;
var
  Selection: TBreadthSelection;
  Earlier, Current: TBreadthSelectionItem;
begin
  Selection := TBreadthSelection.Create(TBreadthSelectionItem);
  try
    Selection.BeginUpdate;
    try
      Earlier := Selection.Add as TBreadthSelectionItem;
      Earlier.SetTicket(OpaqueI(970000000057));
      Selection.BeginUpdate;
      try
        Current := Selection.Add as TBreadthSelectionItem;
        Current.SetTicket(OpaqueI(-810000000043));
        Current.Index := 0;
      finally
        Selection.EndUpdate;
      end;
      Check((Selection.Updates = 0) and (Selection.Items[0] = Current) and (Earlier.Index = 1),
        'breadth-collection-inner-end-update-keeps-observers-suspended');
    finally
      Selection.EndUpdate;
    end;
    Check((Selection.Updates = 1) and (Selection.UpdatedItem = nil) and (Selection.FirstTicket = -810000000043),
      'breadth-collection-end-update-publishes-committed-order-once');
    Current.SetTicket(OpaqueI(650000000019));
    Check((Selection.Updates = 2) and (Selection.UpdatedItem = Current) and (Selection.FirstTicket = 650000000019),
      'breadth-collection-item-edit-notifies-observer-with-current-item');
    FreeAndNil(Current);
    Check((Selection.Updates = 3) and (Selection.UpdatedItem = nil) and (Selection.Count = 1)
      and (Selection.FirstTicket = 970000000057), 'breadth-collection-removal-notifies-without-retaining-deleted-item');
    Mix(UInt64(Selection.FirstTicket));
  finally
    FreeAndNil(Selection);
  end;
end;
