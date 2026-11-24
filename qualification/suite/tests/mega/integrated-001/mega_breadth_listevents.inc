{ TStringList batches visible changes and lets a before-change handler reject an edit. }

type
  TBreadthListListener = class
    Reject: Boolean;
    ChangedCount: Integer;
    Snapshot: string;
    procedure Changing(Sender: TObject);
    procedure Changed(Sender: TObject);
  end;

procedure TBreadthListListener.Changing(Sender: TObject);
begin
  If Reject then
    raise EAbort.Create('list edit refused');
end;

procedure TBreadthListListener.Changed(Sender: TObject);
begin
  Inc(ChangedCount);
  Snapshot := TStringList(Sender).CommaText;
end;

procedure RunBreadthListEvents;
var
  Listener: TBreadthListListener;
  Items: TStringList;
  Caught: Boolean;
begin
  Listener := TBreadthListListener.Create;
  try
    Items := TStringList.Create;
    try
      Items.OnChanging := Listener.Changing;
      Items.OnChange := Listener.Changed;
      Items.Add('first');
      Check((Listener.ChangedCount = 1) and (Listener.Snapshot = 'first'), 'breadth-list-change-sees-committed-entry');
      Items.BeginUpdate;
      try
        Items.Add('second');
        Items.BeginUpdate;
        try
          Items.Add('third');
        finally
          Items.EndUpdate;
        end;
        Check((Items.Count = 3) and (Listener.ChangedCount = 1), 'breadth-list-update-defers-visible-notifications');
      finally
        Items.EndUpdate;
      end;
      Check((Listener.ChangedCount = 2) and (Listener.Snapshot = 'first,second,third'),
        'breadth-list-update-publishes-complete-batch-once');

      Listener.Reject := True;
      Caught := False;
      try
        Items.Delete(Integer(OpaqueI(1)));
      except
        on E: EAbort do Caught := E.Message = 'list edit refused';
      end;
      Check(Caught and (Items.Count = 3) and (Items[1] = 'second') and (Listener.ChangedCount = 2),
        'breadth-list-rejected-edit-keeps-old-string-and-emits-no-change');
      Caught := False;
      try
        Items.BeginUpdate;
        Items.EndUpdate;
      except
        on E: EAbort do Caught := E.Message = 'list edit refused';
      end;
      Check(Caught and (Listener.ChangedCount = 2), 'breadth-list-rejected-batch-opening-emits-no-change');
      Listener.Reject := False;
      Items.Delete(Integer(OpaqueI(1)));
      Check((Listener.ChangedCount = 3) and (Listener.Snapshot = 'first,third'),
        'breadth-list-accepts-edit-after-handler-rejection');
      Mix(UInt64(Length(Listener.Snapshot)));
    finally
      Items.OnChanging := nil;
      Items.OnChange := nil;
      Items.Free;
    end;
  finally
    Listener.Free;
  end;
end;
