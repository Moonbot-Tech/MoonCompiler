{ Deletion after a custom sort releases the logical item and keeps both adjacent attachments. }

type
  TBreadthSortAttachment = class
    Weight: Int64;
    Identity: Integer;
    class var Released, LastReleased: Integer;
    destructor Destroy; override;
  end;

destructor TBreadthSortAttachment.Destroy;
begin
  Inc(Released);
  LastReleased := Identity;
  inherited;
end;

function BreadthCompareAttachments(List: TStringList; Left, Right: Integer): Integer;
var
  L, R: Int64;
begin
  L := TBreadthSortAttachment(List.Objects[Left]).Weight;
  R := TBreadthSortAttachment(List.Objects[Right]).Weight;
  Result := Ord(L > R) - Ord(L < R);
  If Result = 0 then
    Result := CompareStr(List[Left], List[Right]);
end;

procedure RunBreadthStringListAttachments;
var
  List: TStringList;
  A, C: TBreadthSortAttachment;

  function AddWeighted(const Name: string; Weight: Int64; Identity: Integer): TBreadthSortAttachment;
  begin
    Result := TBreadthSortAttachment.Create;
    try
      Result.Weight := OpaqueI(Weight);
      Result.Identity := Identity;
      List.AddObject(Name, Result);
    except
      Result.Free;
      raise;
    end;
  end;

begin
  TBreadthSortAttachment.Released := 0;
  List := TStringList.Create;
  try
    List.OwnsObjects := True;
    A := AddWeighted('last', 90000000017, 1);
    AddWeighted('beta', -81000000019, 2);
    C := AddWeighted('alpha', -81000000019, 3);
    List.CustomSort(BreadthCompareAttachments);
    Check(TBreadthSortAttachment.Released = 0, 'breadth-string-list-sort-keeps-all-attachments-live');
    List.Delete(1);
    Check((TBreadthSortAttachment.LastReleased = 2) and (TBreadthSortAttachment.Released = 1),
      'breadth-string-list-delete-releases-exactly-the-sorted-item');
    Check((List.Count = 2) and (List[0] = 'alpha') and (List.Objects[0] = C) and (List[1] = 'last') and (List.Objects[1] = A),
      'breadth-string-list-delete-preserves-both-adjacent-attachments');
  finally
    List.Free;
  end;
  Check(TBreadthSortAttachment.Released = 3, 'breadth-string-list-frees-each-sorted-attachment-once');
end;
