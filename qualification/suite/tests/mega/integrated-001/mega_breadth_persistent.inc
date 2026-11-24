{ TPersistent.Assign delegates to the source and preserves a managed destination on rejection. }

type
  TBreadthAssignTarget = class(TPersistent)
  public
    Stamp: Int64;
    Owner: IBreadthTaggedOwner;
  end;

  TBreadthAssignSource = class(TPersistent)
  public
    Owner: IBreadthTaggedOwner;
  protected
    procedure AssignTo(Dest: TPersistent); override;
  end;

procedure TBreadthAssignSource.AssignTo(Dest: TPersistent);
begin
  If Dest is TBreadthAssignTarget then begin
    TBreadthAssignTarget(Dest).Stamp := OpaqueI(-87000000033);
    TBreadthAssignTarget(Dest).Owner := Owner;
  end else
    inherited;
end;

procedure RunBreadthPersistentAssign;
var
  Source: TBreadthAssignSource;
  Target: TBreadthAssignTarget;
  Unrelated: TPersistent;
  Rejected: Boolean;
begin
  TBreadthTaggedOwner.Destroyed := 0;
  Source := TBreadthAssignSource.Create;
  try
    Target := TBreadthAssignTarget.Create;
    try
      Source.Owner := TBreadthTaggedOwner.Create;
      Target.Owner := TBreadthTaggedOwner.Create;
      Target.Assign(Source);
      Source.Owner := nil;
      Check((Target.Stamp = -87000000033) and (Target.Owner <> nil) and (Target.Owner.Tag = 74000000051)
        and (TBreadthTaggedOwner.Destroyed = 1), 'breadth-persistent-assign-dispatches-to-source-and-transfers-owner');
      Unrelated := TPersistent.Create;
      try
        Rejected := False;
        try
          Target.Assign(Unrelated);
        except
          on EConvertError do Rejected := True;
        end;
        Check(Rejected and (Target.Stamp = -87000000033) and (Target.Owner <> nil)
          and (TBreadthTaggedOwner.Destroyed = 1), 'breadth-persistent-assign-rejects-unrelated-source-without-losing-state');
      finally
        Unrelated.Free;
      end;
    finally
      Target.Free;
    end;
  finally
    Source.Free;
  end;
  Check(TBreadthTaggedOwner.Destroyed = 2, 'breadth-persistent-assign-releases-surviving-owner-once');
end;
