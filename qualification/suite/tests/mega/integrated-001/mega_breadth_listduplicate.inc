{ A failed sorted insertion preserves the stored object and the caller's pending object. }

procedure RunBreadthSortedDuplicate;
var
  List: TStringList;
  Stored, Pending, Accepted: TBreadthSortAttachment;
  Position: Integer;
  Rejected: Boolean;
begin
  TBreadthSortAttachment.Released := 0;
  List := TStringList.Create;
  try
    List.OwnsObjects := True;
    List.CaseSensitive := False;
    List.Sorted := True;
    List.Duplicates := dupError;
    Stored := TBreadthSortAttachment.Create;
    try
      List.AddObject('mix', Stored);
    except
      Stored.Free;
      raise;
    end;

    Pending := TBreadthSortAttachment.Create;
    try
      Rejected := False;
      try
        List.AddObject('MIX', Pending);
        Pending := nil;
      except
        on EStringListError do Rejected := True;
      end;
      If TBreadthSortAttachment.Released <> 0 then
        Pending := nil;
      Check(Rejected and (Pending <> nil) and (List.Count = 1) and (List.Objects[0] = Stored),
        'breadth-string-list-duplicate-rejection-keeps-list-and-caller-owners');
      If Pending = nil then
        Exit;

      List.CaseSensitive := True;
      Accepted := Pending;
      List.AddObject('MIX', Pending);
      Pending := nil;
      Check((List.Count = 2) and List.Find('MIX', Position) and (List.Objects[Position] = Accepted),
        'breadth-string-list-case-sensitive-retry-stores-distinct-object');
      Check(List.Find('mix', Position) and (List.Objects[Position] = Stored), 'breadth-string-list-retry-preserves-original-case-key');
    finally
      Pending.Free;
    end;
  finally
    List.Free;
  end;
  Check(TBreadthSortAttachment.Released = 2, 'breadth-string-list-retry-releases-both-owned-objects-once');
end;
