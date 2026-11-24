{$ifdef FPC}
  {$if FPC_FULLVERSION <= 30204}
    {$define BREADTH_LEGACY_NOTIFY}
  {$endif}
{$endif}
{ Extract transfers an interface and signals cnExtracted even after list storage shifts. }

type
  TBreadthListExtractOwner = class(TInterfacedObject)
    destructor Destroy; override;
  end;

  TBreadthListExtractNotice = class
    Target, Other: Pointer;
    Trace: Integer;
    procedure Notified(Sender: TObject; {$ifdef BREADTH_LEGACY_NOTIFY}constref{$else}const{$endif} Item: IInterface; Action: TCollectionNotification);
  end;

var
  BreadthListExtractDrops: Integer;

destructor TBreadthListExtractOwner.Destroy;
begin
  Inc(BreadthListExtractDrops);
  inherited;
end;

procedure TBreadthListExtractNotice.Notified(Sender: TObject; {$ifdef BREADTH_LEGACY_NOTIFY}constref{$else}const{$endif} Item: IInterface; Action: TCollectionNotification);
begin
  If (Pointer(Item) = Target) and (Action = cnExtracted) then
    Trace := Trace * 10 + 1
  else If (Pointer(Item) = Other) and (Action = cnRemoved) then
    Trace := Trace * 10 + 2
  else
    Trace := Trace * 10 + 9;
end;

procedure ExerciseBreadthListExtract;
var
  List: TList<IInterface>;
  Notice: TBreadthListExtractNotice;
  First, Second, Extracted, Missing: IInterface;
begin
  BreadthListExtractDrops := 0;
  Notice := TBreadthListExtractNotice.Create;
  try
    List := TList<IInterface>.Create;
    try
      First := TBreadthListExtractOwner.Create;
      Second := TBreadthListExtractOwner.Create;
      Notice.Target := Pointer(First);
      Notice.Other := Pointer(Second);
      List.Add(First);
      List.Add(Second);
      List.OnNotify := Notice.Notified;
      Extracted := List.Extract(First);
      First := nil;
      Check((List.Count = 1) and (Pointer(List[0]) = Notice.Other) and (Notice.Trace = 1),
        'breadth-list-extract-shifts-item-and-notifies-with-extracted-action');
      Check((Pointer(Extracted) = Notice.Target) and (BreadthListExtractDrops = 0),
        'breadth-list-extract-transfers-an-owned-interface');
      Missing := List.Extract(Extracted);
      Check((Missing = nil) and (Notice.Trace = 1) and (List.Count = 1),
        'breadth-list-extract-missing-item-does-not-notify');
      List.Remove(Second);
      Check((Notice.Trace = 12) and (List.Count = 0) and (BreadthListExtractDrops = 0),
        'breadth-list-remove-distinguishes-action-and-keeps-caller-owners');
    finally
      List.Free;
    end;
  finally
    Notice.Free;
  end;
end;

procedure RunBreadthListExtract;
begin
  ExerciseBreadthListExtract;
  Check(BreadthListExtractDrops = 2, 'breadth-list-extracted-and-removed-interfaces-release-on-scope-exit');
end;
